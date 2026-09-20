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

    var id: String { rawValue }

    var dayCount: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .all: nil
        }
    }

    var titleKey: String {
        switch self {
        case .sevenDays: "usage.range.sevenDays"
        case .thirtyDays: "usage.range.thirtyDays"
        case .all: "usage.range.all"
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

/// UTC is a stable plotting coordinate for source date labels, not a claim about
/// the account's reporting time zone. Missing source dates are never filled.
struct TokenUsagePresentation: Equatable {
    let range: TokenUsageRange
    let allDays: [TokenUsagePlotDay]
    let visibleDays: [TokenUsagePlotDay]
    let startDate: Date?
    let endDate: Date?
    /// Independent series preserve unreported-day gaps.
    let lineSegments: [TokenUsageLineSegment]
    /// Sum of reported rows only, not a claim of complete coverage.
    let reportedTotal: Int?
    let maximumY: Double
    private let daysByDate: [Date: TokenUsagePlotDay]

    init(snapshot: TokenUsageSnapshot?, range: TokenUsageRange) {
        let days: [TokenUsagePlotDay] = (snapshot?.dailyUsageBuckets ?? []).compactMap { day in
            guard let date = Self.sourceDate(day.startDate) else { return nil }
            return TokenUsagePlotDay(startDate: day.startDate, date: date, tokens: day.tokens)
        }.sorted { $0.date < $1.date }
        self.init(sortedDays: days, range: range)
    }

    fileprivate init(sortedDays: [TokenUsagePlotDay], range: TokenUsageRange) {
        self.range = range
        allDays = sortedDays
        endDate = allDays.last?.date
        if let endDate, let count = range.dayCount {
            startDate = Self.calendar.date(byAdding: .day, value: 1 - count, to: endDate)
        } else {
            startDate = allDays.first?.date
        }
        if let startDate, let endDate {
            visibleDays = allDays.filter { $0.date >= startDate && $0.date <= endDate }
        } else {
            visibleDays = []
        }

        var segments: [[TokenUsagePlotDay]] = []
        var lookup: [Date: TokenUsagePlotDay] = [:]
        lookup.reserveCapacity(visibleDays.count)
        var total = 0
        var totalOverflowed = false
        var maximum = 0
        let calendar = Self.calendar
        for day in visibleDays {
            lookup[day.date] = day
            maximum = max(maximum, day.tokens)
            if !totalOverflowed {
                let result = total.addingReportingOverflow(day.tokens)
                totalOverflowed = result.overflow
                total = result.partialValue
            }
            if let previous = segments.last?.last,
               calendar.date(byAdding: .day, value: 1, to: previous.date) == day.date {
                segments[segments.count - 1].append(day)
            } else {
                segments.append([day])
            }
        }
        lineSegments = segments.map { TokenUsageLineSegment(days: $0) }
        daysByDate = lookup
        reportedTotal = visibleDays.isEmpty || totalOverflowed ? nil : total
        maximumY = max(1, Double(maximum) * 1.15)
    }

    static var calendar: Calendar { SourceDay.calendar }

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
        guard let startDate, let endDate,
              let distance = Self.calendar.dateComponents([.day], from: startDate, to: endDate).day else { return 0 }
        return max(0, distance + 1 - visibleDays.count)
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

    func resolve(snapshot: TokenUsageSnapshot?, range: TokenUsageRange) -> TokenUsagePresentation {
        let days = snapshot?.dailyUsageBuckets
        let result: TokenUsagePresentation
        if let cached, sourceDays == days {
            if cached.range == range { return cached }
            result = TokenUsagePresentation(sortedDays: cached.allDays, range: range)
        } else {
            result = TokenUsagePresentation(snapshot: snapshot, range: range)
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
