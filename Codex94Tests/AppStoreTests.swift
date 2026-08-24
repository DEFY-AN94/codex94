import Darwin
import XCTest
@testable import Codex94

@MainActor
final class AppStoreTests: XCTestCase {
    func testIdentityUpgradeQueuesAccountRefreshWhenRefreshIsAlreadyRunning() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94StoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\necho 'codex-cli 9.4.0'\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let suiteName = "Codex94StorePreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.manualCodexPath = executable.path
        preferences.identityMode = .quotaOnly
        preferences.hasChosenIdentityMode = true

        let fetcher = IdentityRecordingFetcher()
        let store = AppStore(
            preferences: preferences,
            locator: CodexExecutableLocator(
                environment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"],
                homeDirectory: directory
            ),
            fetcher: fetcher,
            cache: SnapshotCache(fileURL: directory.appendingPathComponent("quota.json"))
        )

        store.refresh(trigger: .manual)
        store.setIdentityMode(.quotaAndAccount)

        let deadline = Date().addingTimeInterval(3)
        while store.snapshot?.account?.email != "account@example.com", Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(store.snapshot?.account?.email, "account@example.com")
        XCTAssertEqual(store.snapshot?.buckets.map(\.limitID), ["default-v2", "model-special"])
        let requestedModes = await fetcher.requestedModes()
        XCTAssertEqual(requestedModes, [.quotaOnly, .quotaAndAccount])
        XCTAssertFalse(store.isRefreshing)
    }

    func testIdentityDowngradeNeverAppliesAccountFromInFlightRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94StoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\necho 'codex-cli 9.4.0'\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let suiteName = "Codex94StorePreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.manualCodexPath = executable.path
        preferences.identityMode = .quotaAndAccount
        preferences.hasChosenIdentityMode = true

        let fetcher = IdentityRecordingFetcher()
        let store = AppStore(
            preferences: preferences,
            locator: CodexExecutableLocator(
                environment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"],
                homeDirectory: directory
            ),
            fetcher: fetcher,
            cache: SnapshotCache(fileURL: directory.appendingPathComponent("quota.json"))
        )

        store.refresh(trigger: .manual)
        store.setIdentityMode(.quotaOnly)

        let deadline = Date().addingTimeInterval(3)
        while store.isRefreshing, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertNil(store.snapshot?.account)
        XCTAssertEqual(store.snapshot?.buckets.map(\.limitID), ["default-v2", "model-special"])
        XCTAssertEqual(store.snapshot?.bucket(id: "model-special")?.limitName, "Spark")
        let requestedModes = await fetcher.requestedModes()
        XCTAssertEqual(requestedModes, [.quotaAndAccount, .quotaOnly])
        XCTAssertFalse(store.isRefreshing)
    }

    func testMissingSelectedBucketFallsBackAtRuntimeAndRestoresPreference() async throws {
        let missingSpark = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
        let restoredSpark = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: 85,
            fetchedAt: Date(timeIntervalSince1970: 2_000)
        )
        let fetcher = SnapshotSequenceFetcher([missingSpark, restoredSpark])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .bucket(limitID: "model-special", kind: .weekly)
        )

        try await refreshAndWait(fixture.store)

        XCTAssertEqual(
            fixture.preferences.menuBarQuotaSelection,
            .bucket(limitID: "model-special", kind: .weekly)
        )
        XCTAssertTrue(fixture.store.menuBarSelectionUsesFallback)
        XCTAssertEqual(fixture.store.menuBarQuota?.bucket.limitID, "default-v2")
        XCTAssertEqual(fixture.store.menuBarQuota?.window.remainingPercent, 60)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.quotaLevel, .healthy)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.connectionBadge, .none)
        let unavailable = fixture.store.menuBarQuotaOptions.first {
            $0.selection == .bucket(limitID: "model-special", kind: .weekly)
        }
        XCTAssertEqual(unavailable?.isAvailable, false)

        try await refreshAndWait(fixture.store)

        XCTAssertEqual(
            fixture.preferences.menuBarQuotaSelection,
            .bucket(limitID: "model-special", kind: .weekly)
        )
        XCTAssertFalse(fixture.store.menuBarSelectionUsesFallback)
        XCTAssertEqual(fixture.store.menuBarQuota?.bucket.limitID, "model-special")
        XCTAssertEqual(fixture.store.menuBarQuota?.window.remainingPercent, 15)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.quotaLevel, .critical)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.connectionBadge, .none)
    }

    func testDefaultSelectionFollowsChangedOpaqueDefaultLimitID() async throws {
        let snapshot = makeSnapshot(
            defaultLimitID: "opaque-default",
            defaultUsed: 64,
            sparkUsed: 20,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
        let fixture = try makeStoreFixture(
            fetcher: SnapshotSequenceFetcher([snapshot]),
            selection: .defaultBucket(.weekly)
        )

        try await refreshAndWait(fixture.store)

        XCTAssertEqual(fixture.store.menuBarQuota?.bucket.limitID, "opaque-default")
        XCTAssertEqual(fixture.store.menuBarQuota?.window.usedPercent, 64)
        XCTAssertFalse(fixture.store.menuBarSelectionUsesFallback)
    }

    func testPopoverBucketBrowsingDoesNotChangeMenuBarSelection() async throws {
        let withSpark = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 30,
            sparkUsed: 80,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
        let withoutSpark = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 35,
            sparkUsed: nil,
            fetchedAt: Date(timeIntervalSince1970: 2_000)
        )
        let fixture = try makeStoreFixture(
            fetcher: SnapshotSequenceFetcher([withSpark, withoutSpark]),
            selection: .defaultBucket(.weekly)
        )
        try await refreshAndWait(fixture.store)

        fixture.store.setViewedBucket("model-special")

        XCTAssertEqual(fixture.store.viewedBucket?.limitID, "model-special")
        XCTAssertEqual(fixture.store.viewedWindow?.usedPercent, 80)
        XCTAssertEqual(fixture.preferences.menuBarQuotaSelection, .defaultBucket(.weekly))
        XCTAssertEqual(fixture.store.menuBarQuota?.bucket.limitID, "default-v2")
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.quotaLevel, .healthy)
        XCTAssertEqual(fixture.store.viewedStatusPresentation.quotaLevel, .warning)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.connectionBadge, .none)
        XCTAssertEqual(fixture.store.viewedStatusPresentation.connectionBadge, .none)

        try await refreshAndWait(fixture.store)

        XCTAssertEqual(fixture.store.viewedBucket?.limitID, "default-v2")
        XCTAssertEqual(fixture.preferences.menuBarQuotaSelection, .defaultBucket(.weekly))
    }

    func testMenuBarOptionsAreStableAndHideUnnamedExtraBuckets() async throws {
        let snapshot = QuotaSnapshot(
            buckets: [
                bucket(
                    id: "default-v2",
                    name: nil,
                    windows: [window(.weekly, used: 20), window(.fiveHour, used: 10)]
                ),
                bucket(id: "z-model", name: "Alpha", windows: [window(.weekly, used: 30)]),
                bucket(id: "a-model", name: "Alpha", windows: [window(.fiveHour, used: 40)]),
                bucket(id: "beta", name: "Beta", windows: [window(.weekly, used: 50)]),
                bucket(id: "hidden", name: nil, windows: [window(.fiveHour, used: 99)])
            ],
            defaultLimitID: "default-v2",
            fetchedAt: Date(timeIntervalSince1970: 1_000),
            account: nil,
            codex: nil
        )
        let fixture = try makeStoreFixture(
            fetcher: SnapshotSequenceFetcher([snapshot]),
            selection: .automatic
        )

        try await refreshAndWait(fixture.store)

        XCTAssertEqual(fixture.store.menuBarQuotaOptions.map(\.selection), [
            .automatic,
            .defaultBucket(.fiveHour),
            .defaultBucket(.weekly),
            .bucket(limitID: "a-model", kind: .fiveHour),
            .bucket(limitID: "z-model", kind: .weekly),
            .bucket(limitID: "beta", kind: .weekly)
        ])
        XCTAssertFalse(fixture.store.menuBarQuotaOptions.contains {
            if case let .bucket(limitID, _) = $0.selection { return limitID == "hidden" }
            return false
        })
    }

    func testCachedSnapshotDoesNotOverwriteUnavailableSelection() throws {
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
        let fixture = try makeStoreFixture(
            fetcher: SnapshotSequenceFetcher([]),
            selection: .bucket(limitID: "model-special", kind: .weekly),
            cachedSnapshot: cached
        )

        XCTAssertEqual(
            fixture.preferences.menuBarQuotaSelection,
            .bucket(limitID: "model-special", kind: .weekly)
        )
        XCTAssertTrue(fixture.store.menuBarSelectionUsesFallback)
        XCTAssertEqual(fixture.store.menuBarQuota?.bucket.limitID, "default-v2")
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.quotaLevel, .healthy)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.connectionBadge, .stale)
        XCTAssertTrue(fixture.store.menuBarStatusPresentation.usesCachedData)
        XCTAssertEqual(fixture.store.viewedStatusPresentation.quotaLevel, .healthy)
        XCTAssertEqual(fixture.store.viewedStatusPresentation.connectionBadge, .stale)
    }

    func testUnavailableWithoutSnapshotProjectsUnknownQuota() async throws {
        let fixture = try makeStoreFixture(
            fetcher: SnapshotSequenceFetcher([]),
            selection: .automatic
        )

        fixture.store.refresh(trigger: .manual)
        try await waitForRefreshToFinish(fixture.store)

        XCTAssertEqual(fixture.store.connectionState, .unavailable(.quotaUnavailable))
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.quotaLevel, .unknown)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.connectionBadge, .unavailable)
        XCTAssertEqual(fixture.store.viewedStatusPresentation.quotaLevel, .unknown)
        XCTAssertEqual(fixture.store.viewedStatusPresentation.connectionBadge, .unavailable)
    }

    func testCachedSnapshotRetryProjectsRefreshingAndCachedData() async throws {
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
        let fixture = try makeStoreFixture(
            fetcher: DelayedFailureFetcher(),
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.refresh(trigger: .manual)

        XCTAssertTrue(fixture.store.isRefreshing)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.quotaLevel, .healthy)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.connectionBadge, .refreshing)
        XCTAssertTrue(fixture.store.menuBarStatusPresentation.usesCachedData)
        XCTAssertEqual(fixture.store.viewedStatusPresentation.connectionBadge, .refreshing)
        XCTAssertTrue(fixture.store.viewedStatusPresentation.usesCachedData)

        try await waitForRefreshToFinish(fixture.store)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.connectionBadge, .stale)
        XCTAssertTrue(fixture.store.menuBarStatusPresentation.usesCachedData)
    }

    func testConnectedSnapshotRefreshProjectsRefreshingWithoutCachedData() async throws {
        let first = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 30,
            sparkUsed: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
        let second = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 35,
            sparkUsed: nil,
            fetchedAt: Date(timeIntervalSince1970: 2_000)
        )
        let fixture = try makeStoreFixture(
            fetcher: DelayedSnapshotSequenceFetcher([first, second]),
            selection: .automatic
        )
        try await refreshAndWait(fixture.store)

        fixture.store.refresh(trigger: .background)

        XCTAssertTrue(fixture.store.isRefreshing)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.quotaLevel, .healthy)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.connectionBadge, .refreshing)
        XCTAssertFalse(fixture.store.menuBarStatusPresentation.usesCachedData)

        try await waitForRefreshToFinish(fixture.store)
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.connectionBadge, .none)
        XCTAssertFalse(fixture.store.menuBarStatusPresentation.usesCachedData)
    }

    private struct StoreFixture {
        let store: AppStore
        let preferences: PreferencesStore
    }

    private func makeStoreFixture(
        fetcher: any QuotaFetching,
        selection: MenuBarQuotaSelection,
        cachedSnapshot: QuotaSnapshot? = nil
    ) throws -> StoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94StoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\necho 'codex-cli 9.4.0'\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let suiteName = "Codex94StorePreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.manualCodexPath = executable.path
        preferences.identityMode = .quotaOnly
        preferences.hasChosenIdentityMode = true
        preferences.menuBarQuotaSelection = selection

        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("quota.json"))
        if let cachedSnapshot { try cache.save(cachedSnapshot) }
        let store = AppStore(
            preferences: preferences,
            locator: CodexExecutableLocator(
                environment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"],
                homeDirectory: directory
            ),
            fetcher: fetcher,
            cache: cache
        )
        return StoreFixture(store: store, preferences: preferences)
    }

    private func refreshAndWait(_ store: AppStore) async throws {
        store.refresh(trigger: .manual)
        try await waitForRefreshToFinish(store)
        XCTAssertEqual(store.connectionState, .connected)
    }

    private func waitForRefreshToFinish(_ store: AppStore) async throws {
        let deadline = Date().addingTimeInterval(3)
        while store.isRefreshing, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(store.isRefreshing)
    }

    private func makeSnapshot(
        defaultLimitID: String,
        defaultUsed: Int,
        sparkUsed: Int?,
        fetchedAt: Date
    ) -> QuotaSnapshot {
        var buckets = [
            bucket(
                id: defaultLimitID,
                name: nil,
                windows: [window(.weekly, used: defaultUsed)]
            )
        ]
        if let sparkUsed {
            buckets.append(bucket(
                id: "model-special",
                name: "Spark",
                windows: [window(.weekly, used: sparkUsed)]
            ))
        }
        return QuotaSnapshot(
            buckets: buckets,
            defaultLimitID: defaultLimitID,
            fetchedAt: fetchedAt,
            account: nil,
            codex: nil
        )
    }

    private func bucket(
        id: String,
        name: String?,
        windows: [QuotaWindowSnapshot]
    ) -> QuotaBucketSnapshot {
        QuotaBucketSnapshot(
            limitID: id,
            limitName: name,
            planType: "pro",
            windows: windows
        )
    }

    private func window(_ kind: QuotaWindowKind, used: Int) -> QuotaWindowSnapshot {
        QuotaWindowSnapshot(
            kind: kind,
            usedPercent: used,
            windowMinutes: kind == .fiveHour ? 300 : 10_080,
            resetsAt: nil
        )
    }
}

private actor SnapshotSequenceFetcher: QuotaFetching {
    private var snapshots: [QuotaSnapshot]

    init(_ snapshots: [QuotaSnapshot]) {
        self.snapshots = snapshots
    }

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        guard !snapshots.isEmpty else { throw ConnectionIssue.quotaUnavailable }
        return snapshots.removeFirst()
    }
}

private actor DelayedFailureFetcher: QuotaFetching {
    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        try await Task.sleep(for: .milliseconds(250))
        throw ConnectionIssue.requestTimedOut
    }
}

private actor DelayedSnapshotSequenceFetcher: QuotaFetching {
    private var snapshots: [QuotaSnapshot]
    private var requestCount = 0

    init(_ snapshots: [QuotaSnapshot]) {
        self.snapshots = snapshots
    }

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        requestCount += 1
        if requestCount > 1 {
            try await Task.sleep(for: .milliseconds(250))
        }
        guard !snapshots.isEmpty else { throw ConnectionIssue.quotaUnavailable }
        return snapshots.removeFirst()
    }
}

private actor IdentityRecordingFetcher: QuotaFetching {
    private var modes: [IdentityMode] = []

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        modes.append(identityMode)
        if modes.count == 1 {
            try await Task.sleep(for: .milliseconds(150))
        }

        return QuotaSnapshot(
            buckets: [
                QuotaBucketSnapshot(
                    limitID: "default-v2",
                    limitName: nil,
                    planType: "pro",
                    windows: [
                        QuotaWindowSnapshot(
                            kind: .weekly,
                            usedPercent: 40,
                            windowMinutes: 10_080,
                            resetsAt: nil
                        )
                    ]
                ),
                QuotaBucketSnapshot(
                    limitID: "model-special",
                    limitName: "Spark",
                    planType: "pro",
                    windows: [
                        QuotaWindowSnapshot(
                            kind: .fiveHour,
                            usedPercent: 30,
                            windowMinutes: 300,
                            resetsAt: nil
                        )
                    ]
                )
            ],
            defaultLimitID: "default-v2",
            fetchedAt: Date(),
            account: identityMode == .quotaAndAccount
                ? AccountSummary(
                    type: "chatgpt",
                    email: "account@example.com",
                    planType: "pro"
                )
                : nil,
            codex: executable
        )
    }

    func requestedModes() -> [IdentityMode] {
        modes
    }
}
