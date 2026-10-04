import Foundation

/// History is text-only. These functions never construct current quota windows,
/// change selection, or infer that an expired window has recovered.
enum ClaudeQuotaHistoryFormatting {
    static func sourceTime(source: ClaudeQuotaSource?, reportedAt: Date?, language: LanguagePreference,
                           timeZone: TimeZone = .autoupdatingCurrent) -> String {
        guard let reportedAt, let timestamp = QuotaFormatting.absoluteReset(
            to: reportedAt, locale: language.locale, calendar: Calendar(identifier: .gregorian), timeZone: timeZone
        ) else { return localized("claude.sourceTime.unavailable", language: language) }
        let key: String = switch source {
        case .localCache: "claude.localCacheTime %@"
        case .statusline: "claude.localReportTime %@"
        case .cliUsage, nil: "claude.sourceTime %@"
        }
        return localized(key, arguments: [timestamp], language: language)
    }

    static func relativeAge(since date: Date, now: Date, language: LanguagePreference) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else {
            return localized("claude.history.ageUnknown", language: language)
        }
        let key: String
        let value: Int?
        switch QuotaFormatting.relativeAge(since: date, now: now) {
        case .justNow: key = "accessibility.freshness.age.justNow"; value = nil
        case let .minutes(count):
            key = count == 1 ? "accessibility.freshness.age.minute %@" : "accessibility.freshness.age.minutes %@"
            value = count
        case let .hours(count):
            key = count == 1 ? "accessibility.freshness.age.hour %@" : "accessibility.freshness.age.hours %@"
            value = count
        case let .days(count):
            key = count == 1 ? "accessibility.freshness.age.day %@" : "accessibility.freshness.age.days %@"
            value = count
        }
        let text = localized(key, arguments: value.map { [String($0)] } ?? [], language: language)
        return value == nil ? text : localized("claude.history.age %@", arguments: [text], language: language)
    }

    static func reportTime(_ history: ClaudeQuotaHistoryPresentation, now: Date, language: LanguagePreference,
                           timeZone: TimeZone = .autoupdatingCurrent) -> String {
        sourceTime(source: history.source, reportedAt: history.reportedAt, language: language, timeZone: timeZone)
            + " · " + relativeAge(since: history.reportedAt, now: now, language: language)
    }

    static func quotaText(usedPercentage: Double, language: LanguagePreference) -> String {
        localized("claude.history.quota %@ %@", arguments: [
            QuotaFormatting.percent(precise: 100 - usedPercentage, language: language),
            QuotaFormatting.percent(precise: usedPercentage, language: language)
        ], language: language)
    }

    static func compactSummary(_ history: ClaudeQuotaHistoryPresentation, language: LanguagePreference) -> String {
        let values = history.windows.sorted { $0.kind.sortOrder < $1.kind.sortOrder }.map { window in
            localized(window.kind == .fiveHour ? "quota.fiveHourShort" : "quota.weeklyShort", language: language)
                + " " + QuotaFormatting.percent(precise: 100 - window.usedPercentage, language: language)
        }.joined(separator: " · ")
        return localized("claude.history.compact %@", arguments: [values], language: language)
    }

    static func summary(_ history: ClaudeQuotaHistoryPresentation, now: Date, language: LanguagePreference,
                        timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var parts = [localized("claude.history.currentUnknown", language: language),
                     localized(history.source.localizationKey, language: language),
                     reportTime(history, now: now, language: language, timeZone: timeZone)]
        for window in history.windows.sorted(by: { $0.kind.sortOrder < $1.kind.sortOrder }) {
            let title = localized(window.kind == .fiveHour
                ? "accessibility.quotaWindow.fiveHour" : "accessibility.quotaWindow.weekly", language: language)
            parts.append(title + ": " + quotaText(usedPercentage: window.usedPercentage, language: language))
        }
        for limit in history.modelLimits {
            parts.append(limit.modelName + " · " + localized("quota.weeklyShort", language: language)
                + ": " + quotaText(usedPercentage: limit.usedPercentage, language: language))
        }
        return parts.joined(separator: "; ")
    }

    private static func localized(_ key: String, arguments: [String] = [], language: LanguagePreference) -> String {
        StatusAccessibilityString.localized(key, arguments: arguments.map { $0 as CVarArg }, language: language, bundle: .main)
    }
}
