import Combine
import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    private enum Key {
        static let displayMode = "displayMode"
        static let menuBarQuotaSelection = "menuBarQuotaSelection.v2"
        static let menuBarLayout = "menuBarLayout.v1"
        static let statusAccentOverrides = "statusAccentOverrides.v1"
        static let identityMode = "identityMode"
        static let refreshInterval = "refreshInterval"
        static let theme = "theme"
        static let language = "language"
        static let manualCodexPath = "manualCodexPath"
        static let hasChosenIdentityMode = "hasChosenIdentityMode"
        static let dualWindowBucketSelection = "dualWindowBucketSelection.v1"
        static let globalHotKey = "globalHotKey.v1"
        static let notifications = "notifications.v1"
        static let tokenUsageChartStyle = "tokenUsageChartStyle.v1"
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
    @Published var menuBarLayout: MenuBarLayout {
        didSet { defaults.set(menuBarLayout.rawValue, forKey: Key.menuBarLayout) }
    }
    @Published var statusAccentOverrides: StatusAccentOverrides {
        didSet { persistStatusAccentOverrides() }
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
    @Published var tokenUsageChartStyle: TokenUsageChartStyle {
        didSet { defaults.set(tokenUsageChartStyle.rawValue, forKey: Key.tokenUsageChartStyle) }
    }
    @Published var manualCodexPath: String? {
        didSet { defaults.set(manualCodexPath, forKey: Key.manualCodexPath) }
    }
    @Published var hasChosenIdentityMode: Bool {
        didSet { defaults.set(hasChosenIdentityMode, forKey: Key.hasChosenIdentityMode) }
    }
    @Published var dualWindowBucketSelection: MenuBarBucketSelection {
        didSet { persist(dualWindowBucketSelection, key: Key.dualWindowBucketSelection) }
    }
    @Published var globalHotKey: GlobalHotKey? {
        didSet {
            if let globalHotKey { persist(globalHotKey, key: Key.globalHotKey) }
            else { defaults.removeObject(forKey: Key.globalHotKey) }
        }
    }
    @Published var notifications: NotificationPreferences {
        didSet { persist(notifications, key: Key.notifications) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarQuotaSelection = Self.loadMenuBarQuotaSelection(from: defaults)
        menuBarLayout = MenuBarLayout(storedValue: defaults.object(forKey: Key.menuBarLayout))
        statusAccentOverrides = StatusAccentOverrides(
            storedValue: defaults.object(forKey: Key.statusAccentOverrides)
        )
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
        tokenUsageChartStyle = TokenUsageChartStyle(
            rawValue: defaults.string(forKey: Key.tokenUsageChartStyle) ?? ""
        ) ?? .bar
        manualCodexPath = defaults.string(forKey: Key.manualCodexPath)
        hasChosenIdentityMode = defaults.bool(forKey: Key.hasChosenIdentityMode)
        dualWindowBucketSelection = Self.decode(MenuBarBucketSelection.self, key: Key.dualWindowBucketSelection, from: defaults) ?? .automatic
        globalHotKey = Self.decode(GlobalHotKey.self, key: Key.globalHotKey, from: defaults)
        notifications = Self.decode(NotificationPreferences.self, key: Key.notifications, from: defaults)?.validated
            ?? NotificationPreferences()
        persistMenuBarQuotaSelection()
    }

    func restoreDefaultColors() {
        statusAccentOverrides = StatusAccentOverrides()
    }

    private func persist<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, key: String, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persistStatusAccentOverrides() {
        if statusAccentOverrides.isEmpty {
            defaults.removeObject(forKey: Key.statusAccentOverrides)
        } else {
            defaults.set(statusAccentOverrides.storageDictionary, forKey: Key.statusAccentOverrides)
        }
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
