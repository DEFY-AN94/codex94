import Combine
import Foundation

enum TokenUsageChartStyle: String, CaseIterable, Identifiable, Sendable {
    case bar
    case line

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .bar: "usage.chartStyle.bar"
        case .line: "usage.chartStyle.line"
        }
    }
}

enum TokenUsageRange: String, CaseIterable, Identifiable {
    case sevenDays
    case thirtyDays
    case all
    case custom

    var id: String { rawValue }

    var dayCount: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .all, .custom: nil
        }
    }

    var titleKey: String {
        switch self {
        case .sevenDays: "usage.range.sevenDays"
        case .thirtyDays: "usage.range.thirtyDays"
        case .all: "usage.range.all"
        case .custom: "usage.range.custom"
        }
    }
}

struct TokenUsagePlotDay: Identifiable, Equatable {
    let startDate: String
    let date: Date
    let tokens: Int
    let plotDate: Date
    let barStartDate: Date
    let barEndDate: Date

    var id: String { startDate }

    init(startDate: String, date: Date, tokens: Int) {
        self.startDate = startDate
        self.date = date
        self.tokens = tokens
        plotDate = TokenUsagePresentation.plotDate(for: date)
        barStartDate = date.addingTimeInterval(86_400 * 0.16)
        barEndDate = date.addingTimeInterval(86_400 * 0.84)
    }
}

struct TokenUsageLineSegment: Identifiable, Equatable {
    let days: [TokenUsagePlotDay]
    var id: String { days.first?.id ?? "" }
}

enum TokenUsageComparisonUnavailableReason: Equatable {
    case invalidRange
    case incompleteCurrentRange
    case incompletePreviousRange
    case zeroBaseline
    case totalOverflow
}

/// The immediately preceding interval has the same number of source calendar days.
/// Totals remain reported-row totals; only complete intervals receive a percentage.
struct TokenUsageComparison: Equatable {
    let startDate: Date?
    let endDate: Date?
    let expectedDayCount: Int
    let reportedDayCount: Int
    let reportedTotal: Int?
    /// Percentage change: 20 means an increase of 20%, not a multiplier of 20.
    let percentChange: Double?
    let unavailableReason: TokenUsageComparisonUnavailableReason?
}

/// UTC is a stable plotting coordinate for source date labels, not a claim about
/// the account's reporting time zone. Missing source dates are never filled.
struct TokenUsagePresentation: Equatable {
    let range: TokenUsageRange
    let customRange: ClosedRange<Date>?
    let allDays: [TokenUsagePlotDay]
    let visibleDays: [TokenUsagePlotDay]
    let startDate: Date?
    let endDate: Date?
    /// Independent series preserve unreported-day gaps.
    let lineSegments: [TokenUsageLineSegment]
    /// Sum of reported rows only, not a claim of complete coverage.
    let reportedTotal: Int?
    let expectedDayCount: Int
    /// Explicit zero rows count toward this average; unreported days do not.
    let reportedDailyAverage: Double?
    /// Peak among selected reported rows, independent of the service summary peak.
    let reportedPeak: Int?
    let comparison: TokenUsageComparison
    let maximumY: Double
    private let daysByDate: [Date: TokenUsagePlotDay]

    init(snapshot: TokenUsageSnapshot?, range: TokenUsageRange, customRange: ClosedRange<Date>? = nil) {
        let days: [TokenUsagePlotDay] = (snapshot?.dailyUsageBuckets ?? []).compactMap { day in
            guard let date = Self.sourceDate(day.startDate) else { return nil }
            return TokenUsagePlotDay(startDate: day.startDate, date: date, tokens: day.tokens)
        }.sorted { $0.date < $1.date }
        self.init(sortedDays: days, range: range, customRange: customRange)
    }

    fileprivate init(
        sortedDays: [TokenUsagePlotDay], range: TokenUsageRange, customRange: ClosedRange<Date>? = nil
    ) {
        self.range = range
        self.customRange = range == .custom ? Self.normalized(customRange) : nil
        allDays = sortedDays
        let requestedRange: ClosedRange<Date>?
        if range == .custom {
            requestedRange = self.customRange
        } else if let latest = allDays.last?.date {
            let first = range.dayCount.flatMap {
                Self.calendar.date(byAdding: .day, value: 1 - $0, to: latest)
            } ?? allDays.first?.date
            requestedRange = first.flatMap { Self.normalized($0...latest) }
        } else {
            requestedRange = nil
        }
        startDate = requestedRange?.lowerBound
        endDate = requestedRange?.upperBound
        expectedDayCount = Self.dayCount(in: requestedRange)
        if let startDate, let endDate {
            visibleDays = allDays.filter { $0.date >= startDate && $0.date <= endDate }
        } else {
            visibleDays = []
        }

        var segments: [[TokenUsagePlotDay]] = []
        var lookup: [Date: TokenUsagePlotDay] = [:]
        lookup.reserveCapacity(visibleDays.count)
        var maximum = 0
        let calendar = Self.calendar
        for day in visibleDays {
            lookup[day.date] = day
            maximum = max(maximum, day.tokens)
            if let previous = segments.last?.last,
               calendar.date(byAdding: .day, value: 1, to: previous.date) == day.date {
                segments[segments.count - 1].append(day)
            } else {
                segments.append([day])
            }
        }
        lineSegments = segments.map { TokenUsageLineSegment(days: $0) }
        daysByDate = lookup
        reportedTotal = Self.total(of: visibleDays)
        if let reportedTotal {
            reportedDailyAverage = Double(reportedTotal) / Double(visibleDays.count)
        } else {
            reportedDailyAverage = nil
        }
        reportedPeak = visibleDays.isEmpty ? nil : maximum
        maximumY = max(1, Double(maximum) * 1.15)
        comparison = Self.previousComparison(
            allDays: allDays, currentRange: requestedRange,
            expectedDayCount: expectedDayCount, reportedDayCount: visibleDays.count,
            reportedTotal: reportedTotal
        )
    }

    static var calendar: Calendar { SourceDay.calendar }

    var reportedDayCount: Int { visibleDays.count }

    var hasCompleteCoverage: Bool { expectedDayCount > 0 && reportedDayCount == expectedDayCount }

    /// Bound dates before asking Calendar to normalize them, including nonfinite Dates.
    /// These are the same representable source-label limits enforced by the parser.
    private static let firstSourceDay = SourceDay.parse("0001-01-01")!
    private static let lastSourceDay = SourceDay.parse("9999-12-31")!

    fileprivate static func normalized(_ range: ClosedRange<Date>?) -> ClosedRange<Date>? {
        guard let range,
              range.lowerBound.timeIntervalSinceReferenceDate.isFinite,
              range.upperBound.timeIntervalSinceReferenceDate.isFinite,
              range.lowerBound >= firstSourceDay,
              range.upperBound < lastSourceDay.addingTimeInterval(86_400) else { return nil }
        let start = calendar.startOfDay(for: range.lowerBound)
        let end = calendar.startOfDay(for: range.upperBound)
        guard start <= end else { return nil }
        return start...end
    }

    private static func dayCount(in range: ClosedRange<Date>?) -> Int {
        guard let range,
              let distance = calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day
        else { return 0 }
        return distance + 1
    }

    private static func total(of days: [TokenUsagePlotDay]) -> Int? {
        guard !days.isEmpty else { return nil }
        var total = 0
        for day in days {
            let result = total.addingReportingOverflow(day.tokens)
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return total
    }

    private static func previousComparison(
        allDays: [TokenUsagePlotDay], currentRange: ClosedRange<Date>?,
        expectedDayCount: Int, reportedDayCount: Int, reportedTotal: Int?
    ) -> TokenUsageComparison {
        guard let currentRange, expectedDayCount > 0,
              let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentRange.lowerBound),
              let previousStart = calendar.date(
                byAdding: .day, value: -expectedDayCount, to: currentRange.lowerBound
              ),
              let previousRange = normalized(previousStart...previousEnd) else {
            return TokenUsageComparison(
                startDate: nil, endDate: nil, expectedDayCount: expectedDayCount,
                reportedDayCount: 0, reportedTotal: nil, percentChange: nil, unavailableReason: .invalidRange
            )
        }
        let previousDays = allDays.filter { previousRange.contains($0.date) }
        let previousTotal = total(of: previousDays)
        let reason: TokenUsageComparisonUnavailableReason?
        if reportedDayCount != expectedDayCount {
            reason = .incompleteCurrentRange
        } else if previousDays.count != expectedDayCount {
            reason = .incompletePreviousRange
        } else if reportedTotal == nil || previousTotal == nil {
            reason = .totalOverflow
        } else if previousTotal == 0 {
            reason = .zeroBaseline
        } else {
            reason = nil
        }
        let percentChange: Double?
        if reason == nil, let current = reportedTotal, let previous = previousTotal {
            // Both are nonnegative Int values, so their difference cannot overflow.
            percentChange = Double(current - previous) / Double(previous) * 100
        } else {
            percentChange = nil
        }
        return TokenUsageComparison(
            startDate: previousRange.lowerBound, endDate: previousRange.upperBound,
            expectedDayCount: expectedDayCount, reportedDayCount: previousDays.count,
            reportedTotal: previousTotal, percentChange: percentChange, unavailableReason: reason
        )
    }

    static func plotDate(for sourceDate: Date) -> Date {
        calendar.startOfDay(for: sourceDate).addingTimeInterval(43_200)
    }

    static func sourceDate(_ raw: String) -> Date? {
        SourceDay.parse(raw)
    }

    static func sourceLabel(for date: Date) -> String {
        SourceDay.label(for: date)
    }

    var plotDomain: ClosedRange<Date>? {
        guard let startDate, let endDate,
              let exclusiveEnd = Self.calendar.date(byAdding: .day, value: 1, to: endDate) else { return nil }
        return startDate...exclusiveEnd
    }

    var missingDayCount: Int {
        max(0, expectedDayCount - reportedDayCount)
    }

    /// Tick labels share the marks' day-center coordinate, including missing calendar days.
    func axisPlotDates(maximumCount: Int) -> [Date] {
        guard maximumCount > 0, let startDate, let endDate,
              let distance = Self.calendar.dateComponents([.day], from: startDate, to: endDate).day else {
            return []
        }
        let count = min(distance + 1, maximumCount)
        guard count > 1 else { return [Self.plotDate(for: startDate)] }
        return (0..<count).compactMap { index in
            let offset = Int((Double(index) * Double(distance) / Double(count - 1)).rounded())
            return Self.calendar.date(byAdding: .day, value: offset, to: startDate).map(Self.plotDate(for:))
        }
    }

    func day(on date: Date) -> TokenUsagePlotDay? {
        daysByDate[Self.calendar.startOfDay(for: date)]
    }

    var csv: String {
        "source_date,tokens\r\n" + visibleDays.map { "\($0.startDate),\($0.tokens)\r\n" }.joined()
    }

    var exportFilename: String {
        guard let startDate, let endDate else { return "Codex94-token-usage.csv" }
        return "Codex94-token-usage-\(Self.sourceLabel(for: startDate))-\(Self.sourceLabel(for: endDate)).csv"
    }
}

/// One view-owned memo, resolved synchronously with the snapshot being rendered.
/// It publishes nothing: cache updates must not invalidate a SwiftUI body.
@MainActor
final class TokenUsagePresentationCache: ObservableObject {
    private var sourceDays: [TokenUsageDay]?
    private var cached: TokenUsagePresentation?

    func resolve(
        snapshot: TokenUsageSnapshot?, range: TokenUsageRange, customRange: ClosedRange<Date>? = nil
    ) -> TokenUsagePresentation {
        let days = snapshot?.dailyUsageBuckets
        let normalizedRange = range == .custom ? TokenUsagePresentation.normalized(customRange) : nil
        let result: TokenUsagePresentation
        if let cached, sourceDays == days {
            if cached.range == range, cached.customRange == normalizedRange { return cached }
            result = TokenUsagePresentation(sortedDays: cached.allDays, range: range, customRange: normalizedRange)
        } else {
            result = TokenUsagePresentation(snapshot: snapshot, range: range, customRange: normalizedRange)
        }
        sourceDays = days
        cached = result
        return result
    }
}

enum TokenUsageFormatting {
    private static let dateFormatters = TokenUsageDateFormatterCache()

    static func localized(_ key: String, language: LanguagePreference, arguments: [String] = []) -> String {
        StatusAccessibilityString.localized(
            key, arguments: arguments.map { $0 as CVarArg }, language: language, bundle: .main
        )
    }

    static func number(_ value: Int?, language: LanguagePreference) -> String {
        value.map { $0.formatted(.number.locale(language.locale)) } ?? "—"
    }

    static func compactNumber(_ value: Double, language: LanguagePreference) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(language.locale))
    }

    static func date(_ value: Date, language: LanguagePreference, includeYear: Bool = true) -> String {
        date(value, locale: language.locale, includeYear: includeYear)
    }

    static func date(_ value: Date, locale: Locale, includeYear: Bool = true) -> String {
        dateFormatters.string(from: value, locale: locale, includeYear: includeYear)
    }

    static func duration(_ seconds: Int?, language: LanguagePreference) -> String {
        guard let seconds else { return "—" }
        let key: String
        let values: [Int]
        if seconds >= 86_400 {
            key = "usage.duration.daysHours %@ %@"
            values = [seconds / 86_400, seconds % 86_400 / 3_600]
        } else if seconds >= 3_600 {
            key = "usage.duration.hoursMinutes %@ %@"
            values = [seconds / 3_600, seconds % 3_600 / 60]
        } else if seconds >= 60 {
            key = "usage.duration.minutesSeconds %@ %@"
            values = [seconds / 60, seconds % 60]
        } else {
            key = "usage.duration.seconds %@"
            values = [seconds]
        }
        return localized(key, language: language, arguments: values.map { number($0, language: language) })
    }
}

/// Preserve the existing ICU/template output while safely reusing mutable
/// DateFormatter instances. Both lookup and formatting are protected by the lock.
private final class TokenUsageDateFormatterCache: @unchecked Sendable {
    private struct Key: Hashable {
        let locale: Locale
        let includeYear: Bool
    }

    private let lock = NSLock()
    private var formatters: [Key: DateFormatter] = [:]
    private var localeObservation: NSObjectProtocol?

    init() {
        localeObservation = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.formatters.removeAll() }
        }
    }

    deinit {
        if let localeObservation { NotificationCenter.default.removeObserver(localeObservation) }
    }

    func string(from date: Date, locale: Locale, includeYear: Bool) -> String {
        lock.withLock {
            let key = Key(locale: locale, includeYear: includeYear)
            let formatter: DateFormatter
            if let cached = formatters[key] {
                formatter = cached
            } else {
                formatter = DateFormatter()
                formatter.locale = locale
                formatter.calendar = TokenUsagePresentation.calendar
                formatter.timeZone = TokenUsagePresentation.calendar.timeZone
                formatter.setLocalizedDateFormatFromTemplate(includeYear ? "yMMMd" : "MMMd")
                if formatters.count >= 16 { formatters.removeAll() }
                formatters[key] = formatter
            }
            return formatter.string(from: date)
        }
    }
}
