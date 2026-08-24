import SwiftUI

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

enum StatusAccessibilityText {
    static func connectionContext(_ presentation: StatusPresentation) -> Text {
        var text = Text(presentation.localizedConnectionKey)
        if presentation.usesCachedData, presentation.connectionBadge != .stale {
            text = text + Text(verbatim: ", ") + Text("status.cached")
        }
        return text
    }

    static func quotaWindow(_ kind: LocalizedStringKey) -> Text {
        Text("accessibility.quotaWindow \(Text(kind))")
    }

    static func remainingPercent(_ percent: String) -> Text {
        Text("accessibility.remainingPercent \(percent)")
    }

    static func cachedAge(_ age: String) -> Text {
        Text("accessibility.cachedAge \(age)")
    }

    static var unavailableQuota: Text {
        Text("accessibility.unavailableQuota")
    }
}

extension View {
    func codex94Environment(_ preferences: PreferencesStore) -> some View {
        environment(\.locale, preferences.language.locale)
    }
}
