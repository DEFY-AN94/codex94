import Combine
import CoreFoundation
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
        static let floatingWindowPinned = "floatingWindowPinned.v1"
        static let floatingWindowPosition = "floatingWindowPosition.v1"
        static let codexMonitoringEnabled = "codexMonitoringEnabled.v1"
        static let claudeMonitoringEnabled = "claudeMonitoringEnabled.v1"
        static let claudeCLIUsageEnabled = "claude.cliUsageEnabled.v1"
        static let menuBarServiceMode = "menuBarServiceMode.v1"
        static let primaryProvider = "primaryProvider.v1"
        static let floatingProvider = "floatingProvider.v1"
        static let claudeRefreshInterval = "claude.refreshInterval.v1"
        static let claudeMenuBarQuotaSelection = "claude.menuBarQuotaSelection.v1"
        static let claudeDualWindowBucketSelection = "claude.dualWindowBucketSelection.v1"
        static let claudeNotifications = "claude.notifications.v1"
    }

    private enum LegacyDisplayMode: String {
        case automatic
        case fiveHour
        case weekly
    }

    private let defaults: UserDefaults

    @Published var codexMonitoringEnabled: Bool {
        didSet { defaults.set(codexMonitoringEnabled, forKey: Key.codexMonitoringEnabled) }
    }
    @Published var claudeMonitoringEnabled: Bool {
        didSet { defaults.set(claudeMonitoringEnabled, forKey: Key.claudeMonitoringEnabled) }
    }
    @Published var claudeCLIUsageEnabled: Bool {
        didSet { defaults.set(claudeCLIUsageEnabled, forKey: Key.claudeCLIUsageEnabled) }
    }
    @Published var menuBarServiceMode: MenuBarServiceMode {
        didSet { defaults.set(menuBarServiceMode.rawValue, forKey: Key.menuBarServiceMode) }
    }
    @Published var primaryProvider: QuotaProviderID {
        didSet { defaults.set(primaryProvider.rawValue, forKey: Key.primaryProvider) }
    }
    @Published var floatingProvider: QuotaProviderID {
        didSet { defaults.set(floatingProvider.rawValue, forKey: Key.floatingProvider) }
    }
    @Published var claudeRefreshInterval: RefreshInterval {
        didSet { defaults.set(claudeRefreshInterval.rawValue, forKey: Key.claudeRefreshInterval) }
    }
    @Published var claudeMenuBarQuotaSelection: MenuBarQuotaSelection {
        didSet { persist(claudeMenuBarQuotaSelection, key: Key.claudeMenuBarQuotaSelection) }
    }
    @Published var claudeDualWindowBucketSelection: MenuBarBucketSelection {
        didSet { persist(claudeDualWindowBucketSelection, key: Key.claudeDualWindowBucketSelection) }
    }
    @Published var claudeNotifications: NotificationPreferences {
        didSet { persist(claudeNotifications, key: Key.claudeNotifications) }
    }

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
    @Published var floatingWindowPinned: Bool {
        didSet { defaults.set(floatingWindowPinned, forKey: Key.floatingWindowPinned) }
    }
    @Published var floatingWindowPosition: FloatingWindowPosition? {
        didSet {
            if let floatingWindowPosition {
                persist(floatingWindowPosition, key: Key.floatingWindowPosition)
            } else {
                defaults.removeObject(forKey: Key.floatingWindowPosition)
            }
        }
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
        codexMonitoringEnabled = Self.loadBoolean(from: defaults, key: Key.codexMonitoringEnabled, fallback: true)
        claudeMonitoringEnabled = Self.loadBoolean(from: defaults, key: Key.claudeMonitoringEnabled, fallback: false)
        claudeCLIUsageEnabled = Self.loadBoolean(from: defaults, key: Key.claudeCLIUsageEnabled, fallback: false)
        menuBarServiceMode = MenuBarServiceMode(rawValue: defaults.string(forKey: Key.menuBarServiceMode) ?? "") ?? .single
        primaryProvider = QuotaProviderID(rawValue: defaults.string(forKey: Key.primaryProvider) ?? "") ?? .codex
        floatingProvider = QuotaProviderID(rawValue: defaults.string(forKey: Key.floatingProvider) ?? "") ?? .codex
        claudeRefreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: Key.claudeRefreshInterval)) ?? .fiveMinutes
        claudeMenuBarQuotaSelection = Self.decode(
            MenuBarQuotaSelection.self, key: Key.claudeMenuBarQuotaSelection, from: defaults
        ) ?? .automatic
        claudeDualWindowBucketSelection = Self.decode(
            MenuBarBucketSelection.self, key: Key.claudeDualWindowBucketSelection, from: defaults
        ) ?? .automatic
        claudeNotifications = Self.decode(
            NotificationPreferences.self, key: Key.claudeNotifications, from: defaults
        )?.validated ?? NotificationPreferences()
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
        floatingWindowPinned = defaults.object(forKey: Key.floatingWindowPinned) as? Bool ?? true
        floatingWindowPosition = Self.decode(
            FloatingWindowPosition.self, key: Key.floatingWindowPosition, from: defaults
        ).flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }
        manualCodexPath = defaults.string(forKey: Key.manualCodexPath)
        hasChosenIdentityMode = defaults.bool(forKey: Key.hasChosenIdentityMode)
        dualWindowBucketSelection = Self.decode(MenuBarBucketSelection.self, key: Key.dualWindowBucketSelection, from: defaults) ?? .automatic
        globalHotKey = Self.decode(GlobalHotKey.self, key: Key.globalHotKey, from: defaults)
        notifications = Self.decode(NotificationPreferences.self, key: Key.notifications, from: defaults)?.validated
            ?? NotificationPreferences()
        persistMenuBarQuotaSelection()
    }

    var enabledProviders: [QuotaProviderID] {
        QuotaProviderID.allCases.filter { isMonitoringEnabled(for: $0) }
    }

    var resolvedPrimaryProvider: QuotaProviderID? {
        isMonitoringEnabled(for: primaryProvider) ? primaryProvider : enabledProviders.first
    }

    var resolvedFloatingProvider: QuotaProviderID? {
        isMonitoringEnabled(for: floatingProvider) ? floatingProvider : resolvedPrimaryProvider
    }

    var menuBarProviders: [QuotaProviderID] {
        guard let primary = resolvedPrimaryProvider else { return [] }
        switch menuBarServiceMode {
        case .single: return [primary]
        case .both: return [primary] + enabledProviders.filter { $0 != primary }
        }
    }

    func isMonitoringEnabled(for provider: QuotaProviderID) -> Bool {
        switch provider {
        case .codex: codexMonitoringEnabled
        case .claude: claudeMonitoringEnabled
        }
    }

    /// Selection fallbacks are projections; disabling a service does not erase
    /// the user's saved primary/floating choice or either service's settings.
    func setMonitoringEnabled(_ enabled: Bool, for provider: QuotaProviderID) {
        guard isMonitoringEnabled(for: provider) != enabled else { return }
        switch provider {
        case .codex: codexMonitoringEnabled = enabled
        case .claude: claudeMonitoringEnabled = enabled
        }
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

    private static func loadBoolean(from defaults: UserDefaults, key: String, fallback: Bool) -> Bool {
        guard let value = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return fallback }
        return value.boolValue
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
