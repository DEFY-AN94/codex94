import Combine
import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    private enum Key {
        static let displayMode = "displayMode"
        static let identityMode = "identityMode"
        static let refreshInterval = "refreshInterval"
        static let theme = "theme"
        static let language = "language"
        static let manualCodexPath = "manualCodexPath"
        static let hasChosenIdentityMode = "hasChosenIdentityMode"
    }

    private let defaults: UserDefaults

    @Published var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }
    @Published var identityMode: IdentityMode {
        didSet { defaults.set(identityMode.rawValue, forKey: Key.identityMode) }
    }
    @Published var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) }
    }
    @Published var theme: ThemePreference {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }
    @Published var language: LanguagePreference {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }
    @Published var manualCodexPath: String? {
        didSet { defaults.set(manualCodexPath, forKey: Key.manualCodexPath) }
    }
    @Published var hasChosenIdentityMode: Bool {
        didSet { defaults.set(hasChosenIdentityMode, forKey: Key.hasChosenIdentityMode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        displayMode = DisplayMode(
            rawValue: defaults.string(forKey: Key.displayMode) ?? ""
        ) ?? .automatic
        identityMode = IdentityMode(
            rawValue: defaults.string(forKey: Key.identityMode) ?? ""
        ) ?? .quotaAndAccount
        refreshInterval = RefreshInterval(
            rawValue: defaults.integer(forKey: Key.refreshInterval)
        ) ?? .fiveMinutes
        theme = ThemePreference(
            rawValue: defaults.string(forKey: Key.theme) ?? ""
        ) ?? .system
        language = LanguagePreference(
            rawValue: defaults.string(forKey: Key.language) ?? ""
        ) ?? .system
        manualCodexPath = defaults.string(forKey: Key.manualCodexPath)
        hasChosenIdentityMode = defaults.bool(forKey: Key.hasChosenIdentityMode)
    }
}

