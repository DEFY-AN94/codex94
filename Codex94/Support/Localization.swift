import SwiftUI

extension DisplayMode {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .automatic: "display.auto"
        case .fiveHour: "display.fiveHour"
        case .weekly: "display.weekly"
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

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .terminalDark: .dark
        case .terminalLight: .light
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

extension View {
    func codex94Environment(_ preferences: PreferencesStore) -> some View {
        environment(\.locale, preferences.language.locale)
            .preferredColorScheme(preferences.theme.colorScheme)
    }
}
