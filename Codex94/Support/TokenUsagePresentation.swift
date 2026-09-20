import Foundation

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

    var id: String { startDate }
    var plotDate: Date { date.addingTimeInterval(12 * 60 * 60) }
}

/// UTC is a stable plotting coordinate for source date labels, not a claim about
/// the account's reporting time zone. Missing source dates are never filled.
struct TokenUsagePresentation: Equatable {
    let range: TokenUsageRange
    let allDays: [TokenUsagePlotDay]
    let visibleDays: [TokenUsagePlotDay]
    let startDate: Date?
    let endDate: Date?

    init(snapshot: TokenUsageSnapshot?, range: TokenUsageRange) {
        self.range = range
        allDays = (snapshot?.dailyUsageBuckets ?? []).compactMap { day in
            guard let date = Self.sourceDate(day.startDate) else { return nil }
            return TokenUsagePlotDay(startDate: day.startDate, date: date, tokens: day.tokens)
        }.sorted { $0.date < $1.date }
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
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func sourceDate(_ raw: String) -> Date? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard raw.utf8.count == 10, parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              raw.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else { return nil }
        return date
    }

    static func sourceLabel(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
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

    /// This is the sum of reported rows in the chosen range, never a coverage claim.
    var reportedTotal: Int? {
        guard !visibleDays.isEmpty else { return nil }
        var total = 0
        for day in visibleDays {
            let sum = total.addingReportingOverflow(day.tokens)
            guard !sum.overflow else { return nil }
            total = sum.partialValue
        }
        return total
    }

    func day(on date: Date) -> TokenUsagePlotDay? {
        let key = Self.sourceLabel(for: date)
        return visibleDays.first { $0.startDate == key }
    }

    var csv: String {
        "source_date,tokens\r\n" + visibleDays.map { "\($0.startDate),\($0.tokens)\r\n" }.joined()
    }

    var exportFilename: String {
        guard let startDate, let endDate else { return "Codex94-token-usage.csv" }
        return "Codex94-token-usage-\(Self.sourceLabel(for: startDate))-\(Self.sourceLabel(for: endDate)).csv"
    }
}

enum TokenUsageFormatting {
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
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = TokenUsagePresentation.calendar
        formatter.timeZone = TokenUsagePresentation.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(includeYear ? "yMMMd" : "MMMd")
        return formatter.string(from: value)
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
