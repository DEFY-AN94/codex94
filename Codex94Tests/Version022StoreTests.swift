import Darwin
import XCTest
@testable import Codex94

@MainActor
final class Version022StoreTests: XCTestCase {
    func testResetCreditLifecycleRemovesIdentityAndNeverRestoresCountFromDisk() async throws {
        let first = snapshot(remaining: 70, sequence: 1, email: "private@example.com", resetCredits: 3)
        let latest = snapshot(remaining: 60, sequence: 2, email: "private@example.com")
        let fixture = try makeFixture(
            outcomes: [.success(first), .failure(.requestTimedOut), .success(latest)],
            cachedSnapshot: snapshot(remaining: 80, sequence: 0, resetCredits: 9)
        )
        defer { fixture.store.shutdown() }

        XCTAssertNotNil(fixture.store.snapshot)
        XCTAssertNil(fixture.store.snapshot?.resetCreditsAvailableCount)
        XCTAssertFalse(fixture.store.hasFetchedLiveSnapshot)

        try await refresh(fixture.store)
        XCTAssertEqual(fixture.store.snapshot?.resetCreditsAvailableCount, 3)
        XCTAssertNil(fixture.store.snapshot?.account)
        XCTAssertTrue(fixture.store.hasFetchedLiveSnapshot)
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertNil(fixture.cache.load()?.resetCreditsAvailableCount)
        let saved = try fingerprint(fixture.cache.fileURL)
        let savedText = try XCTUnwrap(String(data: saved.bytes, encoding: .utf8))
        XCTAssertFalse(savedText.contains("resetCreditsAvailableCount"))
        XCTAssertFalse(savedText.contains("private@example.com"))

        try await refresh(fixture.store)
        XCTAssertEqual(fixture.store.snapshot?.resetCreditsAvailableCount, 3)
        XCTAssertEqual(
            fixture.store.connectionState,
            .stale(lastSuccess: first.fetchedAt, issue: .requestTimedOut)
        )
        XCTAssertEqual(try fingerprint(fixture.cache.fileURL), saved)

        try await refresh(fixture.store)
        XCTAssertNil(fixture.store.snapshot?.resetCreditsAvailableCount)
        XCTAssertNil(fixture.store.snapshot?.account)
        XCTAssertTrue(fixture.store.hasFetchedLiveSnapshot)
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertNil(fixture.cache.load()?.resetCreditsAvailableCount)
        let modes = await fixture.fetcher.requestedModes()
        XCTAssertEqual(modes, [.quotaOnly, .quotaOnly, .quotaOnly])
        XCTAssertEqual(fixture.notifications.authorizationReads, 0)
        XCTAssertEqual(fixture.notifications.permissionRequests, 0)
        XCTAssertTrue(fixture.notifications.messages.isEmpty)
    }

    func testNotificationBaselineDeduplicationAndPreferenceChangesHaveNoQuotaSideEffects() async throws {
        let fixture = try makeFixture(outcomes: [
            .success(snapshot(remaining: 50, sequence: 0)),
            .success(snapshot(remaining: 19, sequence: 1)),
            .success(snapshot(remaining: 18, sequence: 2))
        ])
        defer { fixture.store.shutdown() }
        fixture.store.setNotificationPreferences(NotificationPreferences(isEnabled: true))
        try await waitUntil { fixture.store.notificationController.authorization == .authorized }
        XCTAssertEqual(fixture.notifications.permissionRequests, 1, "Only the fake service is used")

        try await refresh(fixture.store)
        XCTAssertTrue(fixture.notifications.messages.isEmpty, "The first live success establishes a baseline")
        try await refresh(fixture.store)
        try await waitUntil { fixture.notifications.messages.count == 1 }
        try await refresh(fixture.store)
        XCTAssertEqual(fixture.notifications.messages.count, 1)

        let saved = try fingerprint(fixture.cache.fileURL)
        let snapshotBefore = fixture.store.snapshot
        let countBefore = await fixture.fetcher.requestCount()
        let legacyChoice = fixture.preferences.menuBarQuotaSelection
        fixture.preferences.menuBarLayout = .dualWindow
        fixture.store.setDualWindowBucketSelection(.bucket(limitID: "extra"))
        var changed = fixture.preferences.notifications
        changed.warningThreshold = 30
        changed.criticalThreshold = 5
        changed.additionalBucketIDs = ["extra"]
        fixture.store.setNotificationPreferences(changed)
        XCTAssertFalse(fixture.store.isRefreshing)
        try await Task.sleep(for: .milliseconds(75))

        let countAfter = await fixture.fetcher.requestCount()
        XCTAssertEqual(countAfter, countBefore)
        XCTAssertEqual(fixture.store.snapshot, snapshotBefore)
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertEqual(try fingerprint(fixture.cache.fileURL), saved)
        XCTAssertEqual(fixture.notifications.messages.count, 1)
        XCTAssertEqual(fixture.notifications.permissionRequests, 1)
        XCTAssertEqual(fixture.preferences.menuBarQuotaSelection, legacyChoice)
        XCTAssertEqual(fixture.store.dualWindowBucket?.limitID, "extra")
        XCTAssertEqual(fixture.preferences.notifications.warningThreshold, 30)
    }

    func testKnownAccountChangeReestablishesNotificationBaseline() async throws {
        let fixture = try makeFixture(
            outcomes: [
                .success(snapshot(remaining: 25, sequence: 0, email: "user@example.com")),
                .success(snapshot(remaining: 15, sequence: 1, email: "test@example.com")),
                .success(snapshot(remaining: 5, sequence: 2, email: "test@example.com")),
                .success(snapshot(remaining: 50, sequence: 3, email: "account@example.com"))
            ],
            identityMode: .quotaAndAccount
        )
        defer { fixture.store.shutdown() }
        fixture.store.setNotificationPreferences(NotificationPreferences(
            isEnabled: true,
            recoveryEnabled: true
        ))
        try await waitUntil { fixture.store.notificationController.authorization == .authorized }

        try await refresh(fixture.store)
        try await refresh(fixture.store)
        XCTAssertTrue(fixture.notifications.messages.isEmpty, "Another account's 15% is a new baseline")
        try await refresh(fixture.store)
        try await waitUntil { fixture.notifications.messages.count == 1 }
        let message = try XCTUnwrap(fixture.notifications.messages.first)
        XCTAssertTrue(message.body.contains("Codex"))
        XCTAssertTrue(message.body.contains("5%"))
        XCTAssertFalse(message.title.contains("@"))
        XCTAssertFalse(message.body.contains("@"))
        try await refresh(fixture.store)
        XCTAssertEqual(fixture.notifications.messages.count, 1, "Account replacement must not report recovery")
        XCTAssertEqual(fixture.store.snapshot?.account?.email, "account@example.com")
    }

    func testNotificationPreferencesPersistAndMalformedStorageFallsBackToDisabled() throws {
        let defaults = try isolatedDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertFalse(preferences.notifications.isEnabled)
        XCTAssertEqual(preferences.notifications.warningThreshold, 20)
        XCTAssertEqual(preferences.notifications.criticalThreshold, 10)
        XCTAssertFalse(preferences.notifications.recoveryEnabled)

        let selected = NotificationPreferences(
            isEnabled: true,
            warningThreshold: 30,
            criticalThreshold: 0,
            recoveryEnabled: true,
            fiveHourEnabled: false,
            additionalBucketIDs: ["extra"]
        )
        preferences.notifications = selected
        XCTAssertNotNil(defaults.data(forKey: "notifications.v1"))
        XCTAssertEqual(PreferencesStore(defaults: defaults).notifications, selected)

        var invalidFields = selected
        invalidFields.warningThreshold = -1
        invalidFields.criticalThreshold = 101
        invalidFields.additionalBucketIDs = ["", "extra"]
        defaults.set(try JSONEncoder().encode(invalidFields), forKey: "notifications.v1")
        let corrected = PreferencesStore(defaults: defaults).notifications
        XCTAssertTrue(corrected.isEnabled)
        XCTAssertEqual(corrected.warningThreshold, 20)
        XCTAssertEqual(corrected.criticalThreshold, 10)
        XCTAssertEqual(corrected.additionalBucketIDs, ["extra"])

        for malformed in [Data("not-json".utf8), Data("{\"isEnabled\":true}".utf8)] {
            defaults.set(malformed, forKey: "notifications.v1")
            XCTAssertEqual(PreferencesStore(defaults: defaults).notifications, NotificationPreferences())
        }
        defaults.set("wrong-storage-type", forKey: "notifications.v1")
        XCTAssertEqual(PreferencesStore(defaults: defaults).notifications, NotificationPreferences())
    }

    private struct Fixture {
        let store: AppStore
        let preferences: PreferencesStore
        let fetcher: Version022QueueFetcher
        let notifications: Version022NotificationService
        let cache: SnapshotCache
    }

    private func makeFixture(
        outcomes: [Version022FetchOutcome],
        identityMode: IdentityMode = .quotaOnly,
        cachedSnapshot: QuotaSnapshot? = nil
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94Version022Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\n[ \"$1\" = \"--version\" ] || exit 70\necho 'codex-cli 9.4.0'\n".write(
            to: executable, atomically: true, encoding: .utf8
        )
        XCTAssertEqual(chmod(executable.path, 0o700), 0)
        let preferences = PreferencesStore(defaults: try isolatedDefaults())
        preferences.manualCodexPath = executable.path
        preferences.identityMode = identityMode
        preferences.hasChosenIdentityMode = true
        preferences.language = .english
        preferences.menuBarQuotaSelection = .defaultBucket(.weekly)
        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("quota.json"))
        if let cachedSnapshot { try cache.save(cachedSnapshot) }
        let fetcher = Version022QueueFetcher(outcomes)
        let notifications = Version022NotificationService()
        let store = AppStore(
            preferences: preferences,
            launchAtLogin: LaunchAtLoginController(
                readStatus: { .notRegistered },
                register: { XCTFail("Fixture must not register Login Items") },
                unregister: { XCTFail("Fixture must not unregister Login Items") },
                stableInstall: { false }
            ),
            locator: CodexExecutableLocator(
                environment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"],
                homeDirectory: directory
            ),
            fetcher: fetcher,
            cache: cache,
            hotKeyController: GlobalHotKeyController(service: Version022HotKeyService()),
            notificationController: NotificationController(service: notifications)
        )
        return Fixture(store: store, preferences: preferences, fetcher: fetcher,
                       notifications: notifications, cache: cache)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "Codex94Version022Preferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func refresh(_ store: AppStore) async throws {
        store.refresh(trigger: .manual)
        try await waitUntil { !store.isRefreshing }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for isolated store work")
    }

    private struct CacheFingerprint: Equatable {
        let bytes: Data
        let modifiedAt: Date
        let fileNumber: UInt64
    }

    private func fingerprint(_ fileURL: URL) throws -> CacheFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return CacheFingerprint(
            bytes: try Data(contentsOf: fileURL),
            modifiedAt: try XCTUnwrap(attributes[.modificationDate] as? Date),
            fileNumber: try XCTUnwrap(attributes[.systemFileNumber] as? NSNumber).uint64Value
        )
    }

    private func snapshot(
        remaining: Int,
        sequence: Int,
        email: String? = nil,
        resetCredits: Int? = nil
    ) -> QuotaSnapshot {
        let window = QuotaWindowSnapshot(
            kind: .weekly,
            usedPercent: 100 - remaining,
            windowMinutes: 10_080,
            resetsAt: nil
        )
        return QuotaSnapshot(
            buckets: [
                QuotaBucketSnapshot(limitID: "codex", limitName: nil, planType: "pro", windows: [window]),
                QuotaBucketSnapshot(limitID: "extra", limitName: "Extra", planType: "pro", windows: [window])
            ],
            defaultLimitID: "codex",
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000 + Double(sequence * 60)),
            account: email.map { AccountSummary(type: "chatgpt", email: $0, planType: "pro") },
            codex: nil,
            resetCreditsAvailableCount: resetCredits
        )
    }
}

private enum Version022FetchOutcome: Sendable {
    case success(QuotaSnapshot)
    case failure(ConnectionIssue)
}

private actor Version022QueueFetcher: QuotaFetching {
    private var outcomes: [Version022FetchOutcome]
    private var modes: [IdentityMode] = []

    init(_ outcomes: [Version022FetchOutcome]) { self.outcomes = outcomes }

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        modes.append(identityMode)
        guard !outcomes.isEmpty else { throw ConnectionIssue.quotaUnavailable }
        switch outcomes.removeFirst() {
        case let .success(snapshot): return snapshot
        case let .failure(issue): throw issue
        }
    }

    func requestCount() -> Int { modes.count }
    func requestedModes() -> [IdentityMode] { modes }
}

@MainActor
private final class Version022NotificationService: QuotaNotificationServing {
    struct Message { let title: String; let body: String }
    var authorizationReads = 0
    var permissionRequests = 0
    var messages: [Message] = []
    private var state: NotificationAuthorization = .notDetermined

    func authorization() async -> NotificationAuthorization {
        authorizationReads += 1
        return state
    }

    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        state = .authorized
        return true
    }

    func deliver(title: String, body: String) async throws {
        messages.append(Message(title: title, body: body))
    }
}

@MainActor
private final class Version022HotKeyService: GlobalHotKeyServing {
    func start(handler: @escaping @MainActor (GlobalHotKeyEvent) -> Void) -> Bool { true }
    func register(_ hotKey: GlobalHotKey, identifier: UInt32) -> GlobalHotKeyIssue? {
        XCTFail("Store tests must not register a global shortcut")
        return .unavailable
    }
    func unregister(identifier: UInt32) -> Bool { true }
    func stop() {}
}
