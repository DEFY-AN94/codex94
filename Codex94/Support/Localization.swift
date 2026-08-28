import SwiftUI

extension DashboardSection {
    var titleKey: LocalizedStringKey {
        switch self {
        case .connection: "dashboard.connection"
        case .display: "dashboard.display"
        case .startup: "dashboard.startup"
        case .diagnostics: "dashboard.diagnostics"
        case .about: "dashboard.about"
        }
    }
}

extension MenuBarLayout {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .ringAndPercentage: "display.layout.ringAndPercentage"
        case .percentageOnly: "display.layout.percentageOnly"
        case .ringOnly: "display.layout.ringOnly"
        }
    }
}

extension StatusAccentRole {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .healthy: "display.colors.healthy"
        case .warning: "display.colors.warning"
        case .critical: "display.colors.critical"
        case .error: "display.colors.error"
        }
    }
}

extension ConnectionRecoveryDestination {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .connection: "recovery.openConnection"
        case .diagnostics: "recovery.openDiagnostics"
        }
    }

    var helpKey: LocalizedStringKey {
        switch self {
        case .connection: "recovery.openConnection.help"
        case .diagnostics: "recovery.openDiagnostics.help"
        }
    }
}

extension DashboardWindowSizePreset {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .compact: "display.windowSize.compact"
        case .standard: "display.windowSize.standard"
        case .large: "display.windowSize.large"
        case .fullHD: "display.windowSize.fullHD"
        }
    }
}

extension QuotaWindowKind {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .fiveHour: "quota.fiveHourShort"
        case .weekly: "quota.weeklyShort"
        }
    }
}

extension IdentityMode {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .quotaAndAccount: "identity.account"
        case .quotaOnly: "identity.quotaOnly"
        }
    }
}

extension ThemePreference {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .system: "theme.system"
        case .terminalDark: "theme.dark"
        case .terminalLight: "theme.light"
        }
    }
}

extension LanguagePreference {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .system: "language.system"
        case .simplifiedChinese: "language.zhHans"
        case .english: "language.english"
        }
    }
}

extension ConnectionIssue {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .codexNotFound: "error.codexNotFound"
        case .codexNotExecutable: "error.codexNotExecutable"
        case .invalidCodexVersion: "error.invalidCodexVersion"
        case .processLaunchFailed: "error.processLaunchFailed"
        case .initializationTimedOut, .requestTimedOut, .totalTimedOut: "error.timeout"
        case .notLoggedIn: "error.notLoggedIn"
        case .quotaUnavailable: "error.quotaUnavailable"
        case .serverExited, .malformedResponse, .responseTooLarge,
             .serverError, .missingResult, .cacheFailure, .unknown:
            "error.connectionFailed"
        }
    }
}

extension StatusPresentation {
    var localizedConnectionKey: LocalizedStringKey {
        switch connectionBadge {
        case .none:
            isIdle ? "status.idle" : "status.connected"
        case .refreshing:
            "status.refreshing"
        case .stale:
            "status.cached"
        case .unavailable:
            "status.unavailable"
        }
    }
}

extension ConnectionBadge {
    var localizedHelpKey: LocalizedStringKey {
        switch self {
        case .none:
            "status.connected"
        case .refreshing:
            "status.refreshing.help"
        case .stale:
            "status.cached.help"
        case .unavailable:
            "status.unavailable.help"
        }
    }
}

enum StatusVisibleText {
    static func context(_ presentation: StatusPresentation, now: Date) -> Text {
        var text = Text(presentation.localizedConnectionKey)
        if let freshness = freshness(presentation.freshness, now: now) {
            text = text + Text(verbatim: " · ") + freshness
        }
        return text
    }

    static func freshness(_ detail: FreshnessDetail, now: Date) -> Text? {
        switch detail {
        case .none:
            return nil
        case let .updated(date):
            let age = QuotaFormatting.relativeAge(since: date, now: now)
            if age == .justNow { return Text("freshness.updated.justNow") }
            return Text("freshness.updated \(ageText(age))")
        case let .lastSuccess(date):
            let age = QuotaFormatting.relativeAge(since: date, now: now)
            if age == .justNow { return Text("freshness.lastSuccess.justNow") }
            return Text("freshness.lastSuccess \(ageText(age))")
        case .noSuccessfulData:
            return Text("freshness.noSuccessfulData")
        case .noSuccessfulDataYet:
            return Text("freshness.noSuccessfulDataYet")
        }
    }

    private static func ageText(_ age: RelativeAge) -> Text {
        switch age {
        case .justNow:
            Text("freshness.age.justNow")
        case let .minutes(value):
            Text("freshness.age.minutes \(String(value))")
        case let .hours(value):
            Text("freshness.age.hours \(String(value))")
        case let .days(value):
            Text("freshness.age.days \(String(value))")
        }
    }
}

enum StatusAccessibilityText {
    static func connectionContext(_ presentation: StatusPresentation) -> Text {
        var text = Text(presentation.localizedConnectionKey)
        if presentation.usesCachedData, presentation.connectionBadge != .stale {
            text = text + Text(verbatim: ", ") + Text("status.cached")
        }
        return text
    }

    static func quotaWindow(_ kind: QuotaWindowKind) -> Text {
        switch kind {
        case .fiveHour:
            Text("accessibility.quotaWindow.fiveHour")
        case .weekly:
            Text("accessibility.quotaWindow.weekly")
        }
    }

    static func remainingPercent(_ percent: String) -> Text {
        Text("accessibility.remainingPercent \(percent)")
    }

    static func resets(_ countdown: String) -> Text {
        Text("accessibility.resets \(countdown)")
    }

    static func statusContext(_ presentation: StatusPresentation, now: Date) -> Text {
        var text = connectionContext(presentation)
        if let freshness = freshness(presentation.freshness, now: now) {
            text = text + Text(verbatim: ", ") + freshness
        }
        return text
    }

    static func freshness(_ detail: FreshnessDetail, now: Date) -> Text? {
        switch detail {
        case .none:
            return nil
        case let .updated(date):
            let age = QuotaFormatting.relativeAge(since: date, now: now)
            if age == .justNow {
                return Text("accessibility.freshness.updated.justNow")
            }
            return Text("accessibility.freshness.updated \(ageText(age))")
        case let .lastSuccess(date):
            let age = QuotaFormatting.relativeAge(since: date, now: now)
            if age == .justNow {
                return Text("accessibility.freshness.lastSuccess.justNow")
            }
            return Text("accessibility.freshness.lastSuccess \(ageText(age))")
        case .noSuccessfulData:
            return Text("accessibility.freshness.noSuccessfulData")
        case .noSuccessfulDataYet:
            return Text("accessibility.freshness.noSuccessfulDataYet")
        }
    }

    private static func ageText(_ age: RelativeAge) -> Text {
        switch age {
        case .justNow:
            Text("accessibility.freshness.age.justNow")
        case let .minutes(value):
            if value == 1 {
                Text("accessibility.freshness.age.minute \(String(value))")
            } else {
                Text("accessibility.freshness.age.minutes \(String(value))")
            }
        case let .hours(value):
            if value == 1 {
                Text("accessibility.freshness.age.hour \(String(value))")
            } else {
                Text("accessibility.freshness.age.hours \(String(value))")
            }
        case let .days(value):
            if value == 1 {
                Text("accessibility.freshness.age.day \(String(value))")
            } else {
                Text("accessibility.freshness.age.days \(String(value))")
            }
        }
    }

    static var unavailableQuota: Text {
        Text("accessibility.unavailableQuota")
    }
}

enum StatusAccessibilityString {
    static func quotaSummary(
        bucketName: String,
        window: QuotaWindowSnapshot?,
        presentation: StatusPresentation,
        now: Date,
        language: LanguagePreference,
        locale: Locale? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .autoupdatingCurrent,
        bundle: Bundle = .main
    ) -> String {
        var components = [bucketName]
        if let window {
            components.append(quotaWindow(
                window.kind,
                language: language,
                bundle: bundle
            ))
            components.append(localized(
                "accessibility.remainingPercent %@",
                arguments: [QuotaFormatting.percent(window.remainingPercent)],
                language: language,
                bundle: bundle
            ))
            components.append(QuotaResetPresentation(
                resetsAt: window.resetsAt,
                now: now,
                language: language,
                locale: locale,
                calendar: calendar,
                timeZone: timeZone,
                bundle: bundle
            ).accessibilityLabel)
        } else {
            components.append(localized(
                "accessibility.unavailableQuota",
                language: language,
                bundle: bundle
            ))
        }
        components.append(statusContext(
            presentation,
            now: now,
            language: language,
            bundle: bundle
        ))
        return components.joined(separator: ", ")
    }

    private static func statusContext(
        _ presentation: StatusPresentation,
        now: Date,
        language: LanguagePreference,
        bundle: Bundle
    ) -> String {
        var components = [localized(
            connectionKey(presentation),
            language: language,
            bundle: bundle
        )]
        if presentation.usesCachedData, presentation.connectionBadge != .stale {
            components.append(localized(
                "status.cached",
                language: language,
                bundle: bundle
            ))
        }
        if let freshness = freshness(
            presentation.freshness,
            now: now,
            language: language,
            bundle: bundle
        ) {
            components.append(freshness)
        }
        return components.joined(separator: ", ")
    }

    private static func connectionKey(_ presentation: StatusPresentation) -> String {
        switch presentation.connectionBadge {
        case .none:
            presentation.isIdle ? "status.idle" : "status.connected"
        case .refreshing:
            "status.refreshing"
        case .stale:
            "status.cached"
        case .unavailable:
            "status.unavailable"
        }
    }

    private static func quotaWindow(
        _ kind: QuotaWindowKind,
        language: LanguagePreference,
        bundle: Bundle
    ) -> String {
        let key = switch kind {
        case .fiveHour: "accessibility.quotaWindow.fiveHour"
        case .weekly: "accessibility.quotaWindow.weekly"
        }
        return localized(
            key,
            language: language,
            bundle: bundle
        )
    }

    private static func freshness(
        _ detail: FreshnessDetail,
        now: Date,
        language: LanguagePreference,
        bundle: Bundle
    ) -> String? {
        switch detail {
        case .none:
            return nil
        case let .updated(date):
            let age = QuotaFormatting.relativeAge(since: date, now: now)
            if age == .justNow {
                return localized(
                    "accessibility.freshness.updated.justNow",
                    language: language,
                    bundle: bundle
                )
            }
            return localized(
                "accessibility.freshness.updated %@",
                arguments: [ageText(age, language: language, bundle: bundle)],
                language: language,
                bundle: bundle
            )
        case let .lastSuccess(date):
            let age = QuotaFormatting.relativeAge(since: date, now: now)
            if age == .justNow {
                return localized(
                    "accessibility.freshness.lastSuccess.justNow",
                    language: language,
                    bundle: bundle
                )
            }
            return localized(
                "accessibility.freshness.lastSuccess %@",
                arguments: [ageText(age, language: language, bundle: bundle)],
                language: language,
                bundle: bundle
            )
        case .noSuccessfulData:
            return localized(
                "accessibility.freshness.noSuccessfulData",
                language: language,
                bundle: bundle
            )
        case .noSuccessfulDataYet:
            return localized(
                "accessibility.freshness.noSuccessfulDataYet",
                language: language,
                bundle: bundle
            )
        }
    }

    private static func ageText(
        _ age: RelativeAge,
        language: LanguagePreference,
        bundle: Bundle
    ) -> String {
        switch age {
        case .justNow:
            localized(
                "accessibility.freshness.age.justNow",
                language: language,
                bundle: bundle
            )
        case let .minutes(value):
            localized(
                value == 1
                    ? "accessibility.freshness.age.minute %@"
                    : "accessibility.freshness.age.minutes %@",
                arguments: [String(value)],
                language: language,
                bundle: bundle
            )
        case let .hours(value):
            localized(
                value == 1
                    ? "accessibility.freshness.age.hour %@"
                    : "accessibility.freshness.age.hours %@",
                arguments: [String(value)],
                language: language,
                bundle: bundle
            )
        case let .days(value):
            localized(
                value == 1
                    ? "accessibility.freshness.age.day %@"
                    : "accessibility.freshness.age.days %@",
                arguments: [String(value)],
                language: language,
                bundle: bundle
            )
        }
    }

    static func localized(
        _ key: String,
        arguments: [CVarArg] = [],
        language: LanguagePreference,
        bundle: Bundle
    ) -> String {
        let localizedBundle = Self.bundle(for: language, fallback: bundle)
        let format = localizedBundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    private static func bundle(
        for language: LanguagePreference,
        fallback: Bundle
    ) -> Bundle {
        let resourceName: String? = switch language {
        case .system: nil
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        }
        guard let resourceName,
              let url = fallback.url(forResource: resourceName, withExtension: "lproj"),
              let localizedBundle = Bundle(url: url) else {
            return fallback
        }
        return localizedBundle
    }
}

enum QuotaLocalizedString {
    static func resetCountdown(
        _ countdown: ResetCountdown,
        language: LanguagePreference,
        bundle: Bundle = .main
    ) -> String {
        switch countdown {
        case .unavailable:
            "--"
        case let .minutes(minutes):
            StatusAccessibilityString.localized(
                "quota.reset.minutes %@",
                arguments: [String(minutes)],
                language: language,
                bundle: bundle
            )
        case let .hours(hours, minutes):
            StatusAccessibilityString.localized(
                "quota.reset.hours %@ %@",
                arguments: [String(hours), String(minutes)],
                language: language,
                bundle: bundle
            )
        case let .days(days, hours):
            StatusAccessibilityString.localized(
                "quota.reset.days %@ %@",
                arguments: [String(days), String(hours)],
                language: language,
                bundle: bundle
            )
        }
    }

    static func accessibilityResetCountdown(
        _ countdown: ResetCountdown,
        language: LanguagePreference,
        bundle: Bundle = .main
    ) -> String? {
        let components: [String]
        switch countdown {
        case .unavailable:
            return nil
        case let .minutes(minutes):
            components = [duration(
                minutes == 1
                    ? "accessibility.duration.minute %@"
                    : "accessibility.duration.minutes %@",
                value: minutes,
                language: language,
                bundle: bundle
            )]
        case let .hours(hours, minutes):
            components = [
                duration(
                    hours == 1
                        ? "accessibility.duration.hour %@"
                        : "accessibility.duration.hours %@",
                    value: hours,
                    language: language,
                    bundle: bundle
                ),
                duration(
                    minutes == 1
                        ? "accessibility.duration.minute %@"
                        : "accessibility.duration.minutes %@",
                    value: minutes,
                    language: language,
                    bundle: bundle
                )
            ]
        case let .days(days, hours):
            components = [
                duration(
                    days == 1
                        ? "accessibility.duration.day %@"
                        : "accessibility.duration.days %@",
                    value: days,
                    language: language,
                    bundle: bundle
                ),
                duration(
                    hours == 1
                        ? "accessibility.duration.hour %@"
                        : "accessibility.duration.hours %@",
                    value: hours,
                    language: language,
                    bundle: bundle
                )
            ]
        }
        return components.joined(
            separator: StatusAccessibilityString.localized(
                "accessibility.duration.separator",
                language: language,
                bundle: bundle
            )
        )
    }

    private static func duration(
        _ key: String,
        value: Int,
        language: LanguagePreference,
        bundle: Bundle
    ) -> String {
        StatusAccessibilityString.localized(
            key,
            arguments: [String(value)],
            language: language,
            bundle: bundle
        )
    }
}

/// One display projection shared by quota rows, Connection and quota accessibility labels.
/// Formatting has no dependency on AppStore, preferences or the refresh lifecycle.
struct QuotaResetPresentation: Equatable {
    let countdown: String
    let absolute: String
    let accessibilityLabel: String

    init(
        resetsAt: Date?,
        now: Date,
        language: LanguagePreference,
        locale: Locale? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .autoupdatingCurrent,
        bundle: Bundle = .main
    ) {
        let remaining = QuotaFormatting.resetCountdown(to: resetsAt, now: now)
        countdown = QuotaLocalizedString.resetCountdown(
            remaining, language: language, bundle: bundle
        )
        let timestamp = QuotaFormatting.absoluteReset(
            to: resetsAt,
            locale: locale ?? language.locale,
            calendar: calendar,
            timeZone: timeZone
        )
        if let timestamp {
            absolute = StatusAccessibilityString.localized(
                "quota.resetAt %@",
                arguments: [timestamp],
                language: language,
                bundle: bundle
            )
        } else {
            absolute = StatusAccessibilityString.localized(
                "quota.resetAt.unavailable", language: language, bundle: bundle
            )
        }

        if let duration = QuotaLocalizedString.accessibilityResetCountdown(
            remaining, language: language, bundle: bundle
        ) {
            let relative = StatusAccessibilityString.localized(
                "accessibility.resets %@",
                arguments: [duration],
                language: language,
                bundle: bundle
            )
            accessibilityLabel = relative + ", " + absolute
        } else {
            accessibilityLabel = absolute
        }
    }
}

extension View {
    func codex94Environment(_ preferences: PreferencesStore) -> some View {
        environment(\.locale, preferences.language.locale)
    }
}
