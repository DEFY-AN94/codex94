import XCTest
@testable import Codex94

@MainActor
final class ProviderPreferencesTests: XCTestCase {
    func testExistingInstallationDefaultsToOnlyCodexWithoutWritingClaudeSettings() throws {
        let defaults = try isolatedDefaults()
        defaults.set("weekly", forKey: "displayMode")
        defaults.set("quotaOnly", forKey: "identityMode")
        defaults.set(true, forKey: "hasChosenIdentityMode")
        defaults.set("/synthetic/codex", forKey: "manualCodexPath")
        defaults.set(15, forKey: "refreshInterval")
        defaults.set("terminalLight", forKey: "theme")
        defaults.set("simplifiedChinese", forKey: "language")
        let preferences = PreferencesStore(defaults: defaults)

        XCTAssertEqual(preferences.enabledProviders, [.codex])
        XCTAssertEqual(preferences.menuBarProviders, [.codex])
        XCTAssertEqual(preferences.menuBarServiceMode, .single)
        XCTAssertEqual(preferences.primaryProvider, .codex)
        XCTAssertEqual(preferences.floatingProvider, .codex)
        XCTAssertEqual(preferences.menuBarQuotaSelection, .defaultBucket(.weekly))
        XCTAssertEqual(preferences.refreshInterval, .fifteenMinutes)
        XCTAssertEqual(preferences.identityMode, .quotaOnly)
        XCTAssertTrue(preferences.hasChosenIdentityMode)
        XCTAssertEqual(preferences.manualCodexPath, "/synthetic/codex")
        XCTAssertEqual(preferences.theme, .terminalLight)
        XCTAssertEqual(preferences.language, .simplifiedChinese)
        XCTAssertFalse(preferences.claudeMonitoringEnabled)
        XCTAssertFalse(preferences.claudeCLIUsageEnabled)
        XCTAssertFalse(preferences.claudeNotifications.isEnabled)
        XCTAssertEqual(preferences.claudeRefreshInterval, .fiveMinutes)
        XCTAssertEqual(preferences.claudeMenuBarQuotaSelection, .automatic)
        XCTAssertEqual(preferences.claudeDualWindowBucketSelection, .automatic)
        XCTAssertEqual(defaults.string(forKey: "displayMode"), "weekly")
        for key in ["codexMonitoringEnabled.v1", "claudeMonitoringEnabled.v1", "claude.cliUsageEnabled.v1", "claude.refreshInterval.v1",
                    "claude.notifications.v1", "claude.menuBarQuotaSelection.v1", "claude.dualWindowBucketSelection.v1"] {
            XCTAssertNil(defaults.object(forKey: key), "Loading old preferences must not silently enable or configure Claude")
        }
    }

    func testCLIUsageRequiresIndependentExplicitOptInAndPersistsOnlyBooleans() throws {
        let defaults = try isolatedDefaults()
        defaults.set(true, forKey: "claudeMonitoringEnabled.v1")
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertTrue(preferences.claudeMonitoringEnabled)
        XCTAssertFalse(preferences.claudeCLIUsageEnabled, "Existing monitoring must never opt into CLI reads")
        XCTAssertNil(defaults.object(forKey: "claude.cliUsageEnabled.v1"))
        preferences.claudeCLIUsageEnabled = true
        XCTAssertTrue(PreferencesStore(defaults: defaults).claudeCLIUsageEnabled)
        preferences.claudeCLIUsageEnabled = false
        XCTAssertFalse(PreferencesStore(defaults: defaults).claudeCLIUsageEnabled)
        for malformed in [1, "true"] as [Any] {
            defaults.set(malformed, forKey: "claude.cliUsageEnabled.v1")
            XCTAssertFalse(PreferencesStore(defaults: defaults).claudeCLIUsageEnabled)
        }
        XCTAssertTrue(PreferencesStore(defaults: defaults).claudeMonitoringEnabled)
    }

    func testPassiveProducerSelectionPersistsOnlyNormalizedOpaqueHashes() throws {
        let defaults = try isolatedDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertNil(preferences.claudePassiveProducerID)
        let hash = String(repeating: "A1", count: 32)
        preferences.setClaudePassiveProducerID(hash)
        XCTAssertEqual(PreferencesStore(defaults: defaults).claudePassiveProducerID, hash.lowercased())
        for value in ["", String(repeating: "g", count: 64), String(repeating: "a", count: 63), "session-id"] {
            defaults.set(value, forKey: "claude.passiveProducerID.v1")
            XCTAssertNil(PreferencesStore(defaults: defaults).claudePassiveProducerID)
        }
        preferences.setClaudePassiveProducerID(nil)
        XCTAssertNil(defaults.object(forKey: "claude.passiveProducerID.v1"))
    }

    func testClaudeSettingsRoundTripWithoutChangingCodexKeys() throws {
        let defaults = try isolatedDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        preferences.menuBarQuotaSelection = .bucket(limitID: "codex-model", kind: .weekly)
        preferences.dualWindowBucketSelection = .bucket(limitID: "codex-dual")
        preferences.refreshInterval = .fifteenMinutes
        preferences.manualCodexPath = "/synthetic/codex"
        var codexNotifications = NotificationPreferences()
        codexNotifications.warningThreshold = 30
        preferences.notifications = codexNotifications
        let original = legacyValues(defaults)

        preferences.setMonitoringEnabled(true, for: .claude)
        preferences.menuBarServiceMode = .both
        preferences.primaryProvider = .claude
        preferences.floatingProvider = .claude
        preferences.claudeRefreshInterval = .oneMinute
        preferences.claudeMenuBarQuotaSelection = .defaultBucket(.fiveHour)
        preferences.claudeDualWindowBucketSelection = .bucket(limitID: "claude-model")
        var claudeNotifications = NotificationPreferences()
        claudeNotifications.isEnabled = true
        claudeNotifications.criticalThreshold = 5
        preferences.claudeNotifications = claudeNotifications
        XCTAssertEqual(legacyValues(defaults), original)

        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertTrue(reloaded.codexMonitoringEnabled)
        XCTAssertTrue(reloaded.claudeMonitoringEnabled)
        XCTAssertEqual(reloaded.menuBarServiceMode, .both)
        XCTAssertEqual(reloaded.menuBarProviders, [.claude, .codex])
        XCTAssertEqual(reloaded.primaryProvider, .claude)
        XCTAssertEqual(reloaded.floatingProvider, .claude)
        XCTAssertEqual(reloaded.claudeRefreshInterval, .oneMinute)
        XCTAssertEqual(reloaded.claudeMenuBarQuotaSelection, .defaultBucket(.fiveHour))
        XCTAssertEqual(reloaded.claudeDualWindowBucketSelection, .bucket(limitID: "claude-model"))
        XCTAssertEqual(reloaded.claudeNotifications, claudeNotifications)
        XCTAssertEqual(reloaded.notifications, codexNotifications)
        XCTAssertEqual(reloaded.menuBarQuotaSelection, .bucket(limitID: "codex-model", kind: .weekly))
        XCTAssertEqual(reloaded.dualWindowBucketSelection, .bucket(limitID: "codex-dual"))
        XCTAssertEqual(reloaded.refreshInterval, .fifteenMinutes)
    }

    func testSingleAndBothModesRespectIndependentEnablementAndSavedSelections() throws {
        let defaults = try isolatedDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        preferences.primaryProvider = .claude
        preferences.floatingProvider = .codex
        XCTAssertEqual(preferences.menuBarProviders, [.codex], "Unavailable primary falls back without enabling it")
        preferences.claudeMonitoringEnabled = true
        XCTAssertEqual(preferences.menuBarProviders, [.claude])
        XCTAssertEqual(preferences.resolvedFloatingProvider, .codex)
        preferences.menuBarServiceMode = .both
        XCTAssertEqual(preferences.menuBarProviders, [.claude, .codex])

        preferences.codexMonitoringEnabled = false
        XCTAssertEqual(preferences.enabledProviders, [.claude])
        XCTAssertEqual(preferences.menuBarProviders, [.claude])
        XCTAssertEqual(preferences.resolvedFloatingProvider, .claude)
        XCTAssertEqual(preferences.floatingProvider, .codex)
        preferences.claudeMonitoringEnabled = false
        XCTAssertEqual(preferences.enabledProviders, [])
        XCTAssertEqual(preferences.menuBarProviders, [])
        XCTAssertNil(preferences.resolvedPrimaryProvider)
        XCTAssertNil(preferences.resolvedFloatingProvider)

        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.enabledProviders, [])
        XCTAssertEqual(reloaded.primaryProvider, .claude)
        XCTAssertEqual(reloaded.floatingProvider, .codex)
        reloaded.setMonitoringEnabled(true, for: .codex)
        reloaded.setMonitoringEnabled(true, for: .claude)
        XCTAssertEqual(reloaded.menuBarProviders, [.claude, .codex])
        XCTAssertEqual(reloaded.resolvedFloatingProvider, .codex)
        reloaded.menuBarServiceMode = .single
        XCTAssertEqual(reloaded.menuBarProviders, [.claude])
    }

    func testMalformedNewPreferencesFallBackWithoutAffectingLegacyValues() throws {
        let defaults = try isolatedDefaults()
        defaults.set(15, forKey: "refreshInterval")
        defaults.set("yes", forKey: "codexMonitoringEnabled.v1")
        defaults.set(1, forKey: "claudeMonitoringEnabled.v1")
        defaults.set("unknown", forKey: "menuBarServiceMode.v1")
        defaults.set("future-service", forKey: "primaryProvider.v1")
        defaults.set(7, forKey: "floatingProvider.v1")
        defaults.set(99, forKey: "claude.refreshInterval.v1")
        defaults.set(Data(#"{"mode":"bucket","limitID":"","kind":"weekly"}"#.utf8), forKey: "claude.menuBarQuotaSelection.v1")
        defaults.set(Data(#"{"mode":"bucket","limitID":"  "}"#.utf8), forKey: "claude.dualWindowBucketSelection.v1")
        defaults.set(Data("invalid-json".utf8), forKey: "claude.notifications.v1")
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertEqual(preferences.enabledProviders, [.codex])
        XCTAssertEqual(preferences.menuBarServiceMode, .single)
        XCTAssertEqual(preferences.primaryProvider, .codex)
        XCTAssertEqual(preferences.floatingProvider, .codex)
        XCTAssertEqual(preferences.refreshInterval, .fifteenMinutes)
        XCTAssertEqual(preferences.claudeRefreshInterval, .fiveMinutes)
        XCTAssertEqual(preferences.claudeMenuBarQuotaSelection, .automatic)
        XCTAssertEqual(preferences.claudeDualWindowBucketSelection, .automatic)
        XCTAssertFalse(preferences.claudeNotifications.isEnabled)
    }

    func testProviderIdentifiersRoundTripAndRejectUnknownCases() throws {
        for provider in QuotaProviderID.allCases {
            XCTAssertEqual(try JSONDecoder().decode(QuotaProviderID.self, from: JSONEncoder().encode(provider)), provider)
            XCTAssertFalse(provider.displayName.isEmpty)
            XCTAssertFalse(provider.systemImageName.isEmpty)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(QuotaProviderID.self, from: Data(#""future-service""#.utf8)))
    }

    private func legacyValues(_ defaults: UserDefaults) -> NSDictionary {
        let keys = ["manualCodexPath", "refreshInterval", "menuBarQuotaSelection.v2", "dualWindowBucketSelection.v1", "notifications.v1"]
        return NSDictionary(dictionary: Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0) ?? NSNull()) }))
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "Codex94ProviderPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}
