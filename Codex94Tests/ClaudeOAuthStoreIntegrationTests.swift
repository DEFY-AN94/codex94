import Foundation
import XCTest
@testable import Codex94

@MainActor
final class ClaudeOAuthStoreIntegrationTests: XCTestCase {
    func testDefaultOAuthNeverConstructsLegacyCLIAndExistingProducerDoesNotAuthorizeFallback() async throws {
        let fixture = try fixture()
        try fixture.capture(used: 25)
        fixture.preferences.setClaudePassiveProducerID(try fixture.cache.load()?.producerID)
        XCTAssertEqual(fixture.preferences.claudeSourceMode, .oauthPreferred)
        fixture.store.start()
        try await wait { fixture.store.oauthIssue == .integrationUnavailable }
        XCTAssertTrue(fixture.store.passiveReportNeedsConfirmation)
        XCTAssertNil(fixture.store.snapshot, "A previously selected local producer is not an OAuth account binding")
        for trigger in [RefreshTrigger.manual, .background, .popover, .systemWake, .quotaReset, .automaticRetry] {
            fixture.store.refresh(trigger: trigger)
        }
        fixture.store.handleSystemWake()
        fixture.store.handleSystemClockChange()
        XCTAssertEqual(fixture.cliConstructions.value, 0)
        let calls = await fixture.http.calls
        XCTAssertEqual(calls, 0)
        fixture.store.adoptPendingPassiveReport()
        XCTAssertEqual(fixture.store.source, .statusline)
        XCTAssertTrue(fixture.store.isUsingOAuthFallback)
        XCTAssertEqual(fixture.store.identityConfidence, .unverifiedLocal)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.weekly)?.preciseRemainingPercent, 75)
        XCTAssertTrue(fixture.notifications.deliveries.isEmpty)
        fixture.store.setStatuslineFallbackEnabled(false)
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertFalse(fixture.store.isUsingOAuthFallback)
    }

    func testSelectingStatuslineOnlyStopsOAuthAndDoesNotNotifyOnUnverifiedQuotaChanges() async throws {
        let fixture = try fixture()
        fixture.store.start()
        try await wait { fixture.store.oauthIssue == .integrationUnavailable }
        fixture.store.setSourceMode(.statuslineOnly)
        try fixture.capture(used: 10)
        fixture.store.refresh()
        XCTAssertEqual(fixture.store.sourceMode, .statuslineOnly)
        XCTAssertEqual(fixture.store.source, .statusline)
        fixture.clock.advance(1)
        try fixture.capture(used: 95)
        fixture.store.refresh()
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.weekly)?.preciseRemainingPercent, 5)
        XCTAssertTrue(fixture.notifications.deliveries.isEmpty)
        XCTAssertEqual(fixture.cliConstructions.value, 0)
        let calls = await fixture.http.calls
        XCTAssertEqual(calls, 0)
    }

    func testSourcePreferenceMigrationPreservesExplicitLegacyOptInAndCodexValues() throws {
        let domain = "Codex94OAuthMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "claudeMonitoringEnabled.v1")
        defaults.set(15, forKey: "refreshInterval")
        let first = PreferencesStore(defaults: defaults)
        XCTAssertEqual(first.claudeSourceMode, .oauthPreferred)
        XCTAssertTrue(first.claudeStatuslineFallbackEnabled)
        XCTAssertEqual(first.refreshInterval, .fifteenMinutes)
        XCTAssertNil(defaults.object(forKey: "claude.sourceMode.v1"), "Loading does not write a credential or source connection")
        defaults.set(true, forKey: "claude.cliUsageEnabled.v1")
        XCTAssertEqual(PreferencesStore(defaults: defaults).claudeSourceMode, .legacyCLI)
        let legacy = PreferencesStore(defaults: defaults)
        legacy.claudeSourceMode = .statuslineOnly
        XCTAssertFalse(defaults.bool(forKey: "claude.cliUsageEnabled.v1"))
        XCTAssertEqual(PreferencesStore(defaults: defaults).claudeSourceMode, .statuslineOnly)
        legacy.claudeSourceMode = .oauthPreferred
        XCTAssertFalse(legacy.claudeCLIUsageEnabled)
        XCTAssertEqual(legacy.refreshInterval, .fifteenMinutes)
        XCTAssertTrue(legacy.claudeMonitoringEnabled)
    }

    func testAConfirmationFromThePreviousConnectionCannotAdoptEvenTheSameReport() async throws {
        let fixture = try fixture()
        try fixture.capture(used: 25)
        fixture.store.start()
        try await wait { fixture.store.pendingPassiveConfirmationID != nil }
        let previous = try XCTUnwrap(fixture.store.pendingPassiveConfirmationID)
        let frozen = try XCTUnwrap(fixture.store.pendingPassivePreview)
        fixture.store.oauthCredentialsDidChange()
        try await wait {
            fixture.store.pendingPassiveConfirmationID != nil
                && fixture.store.pendingPassiveConfirmationID != previous
        }
        XCTAssertEqual(fixture.store.pendingPassivePreview, frozen, "The report data can be identical while the connection changed")
        fixture.store.adoptPendingPassiveReport(expectedConfirmationID: previous)
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertTrue(fixture.store.passiveReportNeedsConfirmation)
        fixture.store.adoptPendingPassiveReport(expectedConfirmationID: fixture.store.pendingPassiveConfirmationID)
        XCTAssertTrue(fixture.store.isUsingOAuthFallback)
        XCTAssertEqual(fixture.store.identityConfidence, .unverifiedLocal)
        XCTAssertTrue(fixture.notifications.deliveries.isEmpty)
    }

    private struct Fixture {
        let preferences: PreferencesStore
        let store: ClaudeQuotaStore
        let cache: ClaudeStatuslineCache
        let clock: OAuthStoreClock
        let cliConstructions: OAuthStoreCounter
        let http: OAuthStoreUnexpectedHTTP
        let notifications: OAuthStoreNotifications

        func capture(used: Int) throws {
            let data = try JSONSerialization.data(withJSONObject: [
                "session_id": "00000000-0000-0000-0000-000000000001",
                "rate_limits": ["seven_day": ["used_percentage": used,
                    "resets_at": Int(clock.date.timeIntervalSince1970) + 7_200]]
            ])
            try cache.capture(data, at: clock.date)
        }
    }

    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Codex94OAuthStore-\(UUID().uuidString)")
        let domain = "Codex94OAuthStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let preferences = PreferencesStore(defaults: defaults)
        preferences.claudeMonitoringEnabled = true
        preferences.claudeNotifications.isEnabled = true
        let cache = ClaudeStatuslineCache(fileURL: directory.appendingPathComponent("support/statusline.json"))
        let installer = ClaudeStatuslineInstaller(settingsURL: directory.appendingPathComponent("settings.json"), cache: cache,
            executableURL: URL(fileURLWithPath: "/bin/echo"), supportDirectory: directory.appendingPathComponent("support"))
        let clock = OAuthStoreClock(), count = OAuthStoreCounter(), http = OAuthStoreUnexpectedHTTP()
        let notifications = OAuthStoreNotifications()
        let store = ClaudeQuotaStore(preferences: preferences, cache: cache, installer: installer,
            fetcherFactory: { count.increment(); return OAuthStoreUnexpectedCLI() },
            oauthClient: http, oauthCache: ClaudeOAuthQuotaCache(directory: directory.appendingPathComponent("oauth")),
            notificationController: NotificationController(service: notifications), now: { clock.date },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
        addTeardownBlock {
            await MainActor.run { store.shutdown() }
            UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: directory)
        }
        return Fixture(preferences: preferences, store: store, cache: cache, clock: clock,
                       cliConstructions: count, http: http, notifications: notifications)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}

private actor OAuthStoreUnexpectedHTTP: ClaudeOAuthUsageFetching {
    private(set) var calls = 0
    func fetchUsage(using credential: ClaudeOAuthCredential) async throws -> ClaudeOAuthUsageSnapshot {
        calls += 1; throw ClaudeOAuthIssue.network
    }
    func fetchProfile(using credential: ClaudeOAuthCredential) async throws -> ClaudeOAuthAccountContext {
        calls += 1; throw ClaudeOAuthIssue.network
    }
}

private struct OAuthStoreUnexpectedCLI: ClaudeQuotaFetching {
    func fetch() async throws -> ClaudeQuotaReport { throw ClaudeQuotaIssue.unavailable }
}

private final class OAuthStoreCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class OAuthStoreClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Date(timeIntervalSince1970: 1_900_000_000)
    var date: Date { lock.withLock { stored } }
    func advance(_ seconds: TimeInterval) { lock.withLock { stored.addTimeInterval(seconds) } }
}

@MainActor
private final class OAuthStoreNotifications: QuotaNotificationServing {
    private(set) var deliveries: [String] = []
    func authorization() async -> NotificationAuthorization { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func deliver(title: String, body: String) async throws { deliveries.append(body) }
}
