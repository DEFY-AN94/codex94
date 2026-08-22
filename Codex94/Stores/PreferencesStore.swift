import Combine
import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    private enum Key {
        static let displayMode = "displayMode"
        static let menuBarQuotaSelection = "menuBarQuotaSelection.v2"
        static let identityMode = "identityMode"
        static let refreshInterval = "refreshInterval"
        static let theme = "theme"
        static let language = "language"
        static let manualCodexPath = "manualCodexPath"
        static let hasChosenIdentityMode = "hasChosenIdentityMode"
    }

    private enum LegacyDisplayMode: String {
        case automatic
        case fiveHour
        case weekly
    }

    private let defaults: UserDefaults

    @Published var menuBarQuotaSelection: MenuBarQuotaSelection {
        didSet { persistMenuBarQuotaSelection() }
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
        menuBarQuotaSelection = Self.loadMenuBarQuotaSelection(from: defaults)
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
        persistMenuBarQuotaSelection()
    }

    private func persistMenuBarQuotaSelection() {
        guard let data = try? JSONEncoder().encode(menuBarQuotaSelection) else { return }
        defaults.set(data, forKey: Key.menuBarQuotaSelection)
    }

    private static func loadMenuBarQuotaSelection(from defaults: UserDefaults) -> MenuBarQuotaSelection {
        if let data = defaults.data(forKey: Key.menuBarQuotaSelection),
           let selection = try? JSONDecoder().decode(MenuBarQuotaSelection.self, from: data) {
            return selection
        }

        switch LegacyDisplayMode(rawValue: defaults.string(forKey: Key.displayMode) ?? "") {
        case .fiveHour:
            return .defaultBucket(.fiveHour)
        case .weekly:
            return .defaultBucket(.weekly)
        case .automatic, .none:
            return .automatic
        }
    }
}
