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

    func testSystemWakeAppliesIdentityAndFreshnessPolicy() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let response = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 20,
            sparkUsed: nil,
            fetchedAt: now
        )
        let cases: [(String, Date?, Bool)] = [
            ("missing", nil, true),
            ("fresh", now.addingTimeInterval(-59), false),
            ("threshold", now.addingTimeInterval(-60), true),
            ("old", now.addingTimeInterval(-7_200), true),
            ("future", now.addingTimeInterval(1), true)
        ]

        for (name, fetchedAt, shouldRefresh) in cases {
            let fetcher = GatedRecordingFetcher(outcomes: [.success(response)])
            let cachedSnapshot = fetchedAt.map {
                makeSnapshot(
                    defaultLimitID: "default-v2",
                    defaultUsed: 40,
                    sparkUsed: nil,
                    fetchedAt: $0
                )
            }
            let fixture = try makeStoreFixture(
                fetcher: fetcher,
                selection: .automatic,
                cachedSnapshot: cachedSnapshot
            )

            fixture.store.handleSystemWake(now: now)

            if shouldRefresh {
                try await waitForRequestCount(1, fetcher: fetcher)
                await fetcher.releaseOne()
                try await waitForRefreshToFinish(fixture.store)
                XCTAssertEqual(fixture.store.connectionState, .connected, name)
                XCTAssertEqual(fixture.store.snapshot?.fetchedAt, now, name)
            } else {
                try await Task.sleep(for: .milliseconds(75))
                let requestCount = await fetcher.requestCount()
                XCTAssertEqual(requestCount, 0, name)
                XCTAssertFalse(fixture.store.isRefreshing, name)
                XCTAssertEqual(fixture.store.snapshot?.fetchedAt, fetchedAt, name)
            }
        }

        let identityFetcher = GatedRecordingFetcher(outcomes: [.success(response)])
        let onboarding = try makeStoreFixture(
            fetcher: identityFetcher,
            selection: .automatic,
            hasChosenIdentityMode: false
        )

        onboarding.store.handleSystemWake(now: now)
        try await Task.sleep(for: .milliseconds(75))

        let onboardingRequestCount = await identityFetcher.requestCount()
        XCTAssertEqual(onboardingRequestCount, 0)
        XCTAssertFalse(onboarding.store.isRefreshing)
        XCTAssertNil(onboarding.store.snapshot)
    }

    func testSystemWakeSuccessAdvancesSnapshotWithoutRestoringAccountInQuotaOnlyMode() async throws {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        let oldSnapshot = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: oldDate
        )
        let freshBase = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 35,
            sparkUsed: 25,
            fetchedAt: newDate
        )
        let response = QuotaSnapshot(
            buckets: freshBase.buckets,
            defaultLimitID: freshBase.defaultLimitID,
            fetchedAt: freshBase.fetchedAt,
            account: AccountSummary(
                type: "chatgpt",
                email: "account@example.com",
                planType: "pro"
            ),
            codex: freshBase.codex
        )
        let fetcher = GatedRecordingFetcher(outcomes: [.success(response)])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: oldSnapshot
        )

        fixture.store.handleSystemWake(now: newDate)
        try await waitForRequestCount(1, fetcher: fetcher)
        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)

        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertEqual(fixture.store.snapshot?.fetchedAt, newDate)
        XCTAssertNil(fixture.store.snapshot?.account)
        XCTAssertEqual(fixture.store.snapshot?.bucket(id: "model-special")?.limitName, "Spark")
        XCTAssertEqual(fixture.store.menuBarStatusPresentation.freshness, .updated(newDate))
    }

    func testSystemWakeFailurePreservesCachedSnapshotOrBecomesUnavailable() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let oldSnapshot = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: oldDate
        )
        let cachedFetcher = GatedRecordingFetcher(outcomes: [.failure(.requestTimedOut)])
        let cachedFixture = try makeStoreFixture(
            fetcher: cachedFetcher,
            selection: .automatic,
            cachedSnapshot: oldSnapshot
        )

        cachedFixture.store.handleSystemWake(now: now)
        try await waitForRequestCount(1, fetcher: cachedFetcher)
        await cachedFetcher.releaseOne()
        try await waitForRefreshToFinish(cachedFixture.store)

        XCTAssertEqual(cachedFixture.store.snapshot, oldSnapshot)
        XCTAssertEqual(
            cachedFixture.store.connectionState,
            .stale(lastSuccess: oldDate, issue: .requestTimedOut)
        )
        XCTAssertEqual(cachedFixture.store.viewedStatusPresentation.freshness, .updated(oldDate))

        let emptyFetcher = GatedRecordingFetcher(outcomes: [.failure(.requestTimedOut)])
        let emptyFixture = try makeStoreFixture(
            fetcher: emptyFetcher,
            selection: .automatic
        )

        emptyFixture.store.handleSystemWake(now: now)
        try await waitForRequestCount(1, fetcher: emptyFetcher)
        await emptyFetcher.releaseOne()
        try await waitForRefreshToFinish(emptyFixture.store)

        XCTAssertNil(emptyFixture.store.snapshot)
        XCTAssertEqual(emptyFixture.store.connectionState, .unavailable(.requestTimedOut))
        XCTAssertEqual(
            emptyFixture.store.viewedStatusPresentation.freshness,
            .noSuccessfulData
        )
    }

    func testWakeManualBackgroundAndPopoverAdjacencyNeverRunsOrQueuesAnotherFetch() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let oldSnapshot = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: now.addingTimeInterval(-120)
        )

        for adjacentTrigger in [RefreshTrigger.manual, .background, .popover] {
            let response = makeSnapshot(
                defaultLimitID: "default-v2",
                defaultUsed: 35,
                sparkUsed: nil,
                fetchedAt: now
            )
            let fetcher = GatedRecordingFetcher(outcomes: [.success(response)])
            let fixture = try makeStoreFixture(
                fetcher: fetcher,
                selection: .automatic,
                cachedSnapshot: oldSnapshot
            )

            fixture.store.handleSystemWake(now: now)
            try await waitForRequestCount(1, fetcher: fetcher)
            fixture.store.refresh(trigger: adjacentTrigger)
            fixture.store.handleSystemWake(now: now)
            fixture.store.handleSystemWake(now: now)
            try await Task.sleep(for: .milliseconds(75))

            let inFlightRequestCount = await fetcher.requestCount()
            let inFlightMaximum = await fetcher.maximumConcurrentRequests()
            XCTAssertEqual(inFlightRequestCount, 1, adjacentTrigger.rawValue)
            XCTAssertEqual(inFlightMaximum, 1, adjacentTrigger.rawValue)

            await fetcher.releaseOne()
            try await waitForRefreshToFinish(fixture.store)
            try await Task.sleep(for: .milliseconds(75))

            let finalRequestCount = await fetcher.requestCount()
            let finalMaximum = await fetcher.maximumConcurrentRequests()
            XCTAssertEqual(finalRequestCount, 1, adjacentTrigger.rawValue)
            XCTAssertEqual(finalMaximum, 1, adjacentTrigger.rawValue)
        }
    }

    func testWakeArrivingDuringManualBackgroundOrPopoverNeverRunsOrQueuesAnotherFetch() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let oldSnapshot = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: now.addingTimeInterval(-120)
        )

        for initialTrigger in [RefreshTrigger.manual, .background, .popover] {
            let response = makeSnapshot(
                defaultLimitID: "default-v2",
                defaultUsed: 35,
                sparkUsed: nil,
                fetchedAt: now
            )
            let fetcher = GatedRecordingFetcher(outcomes: [.success(response)])
            let fixture = try makeStoreFixture(
                fetcher: fetcher,
                selection: .automatic,
                cachedSnapshot: oldSnapshot
            )

            if initialTrigger == .popover {
                fixture.store.popoverWillOpen()
            } else {
                fixture.store.refresh(trigger: initialTrigger)
            }
            try await waitForRequestCount(1, fetcher: fetcher)

            fixture.store.handleSystemWake(now: now)
            fixture.store.handleSystemWake(now: now)
            fixture.store.handleSystemWake(now: now)
            try await Task.sleep(for: .milliseconds(75))

            let inFlightRequestCount = await fetcher.requestCount()
            let inFlightMaximum = await fetcher.maximumConcurrentRequests()
            XCTAssertEqual(inFlightRequestCount, 1, initialTrigger.rawValue)
            XCTAssertEqual(inFlightMaximum, 1, initialTrigger.rawValue)

            await fetcher.releaseOne()
            try await waitForRefreshToFinish(fixture.store)
            try await Task.sleep(for: .milliseconds(75))

            let finalRequestCount = await fetcher.requestCount()
            let finalMaximum = await fetcher.maximumConcurrentRequests()
            XCTAssertEqual(finalRequestCount, 1, initialTrigger.rawValue)
            XCTAssertEqual(finalMaximum, 1, initialTrigger.rawValue)
        }
    }

    func testWakeStillAllowsOneQueuedPreferenceChangeWithoutConcurrency() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let oldSnapshot = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: now.addingTimeInterval(-120)
        )
        let first = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 35,
            sparkUsed: nil,
            fetchedAt: now
        )
        let second = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 30,
            sparkUsed: 20,
            fetchedAt: now.addingTimeInterval(1)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [.success(first), .success(second)])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: oldSnapshot
        )

        fixture.store.handleSystemWake(now: now)
        try await waitForRequestCount(1, fetcher: fetcher)
        fixture.store.setIdentityMode(.quotaAndAccount)
        fixture.store.handleSystemWake(now: now)

        let firstRequestCount = await fetcher.requestCount()
        let firstMaximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(firstRequestCount, 1)
        XCTAssertEqual(firstMaximum, 1)

        await fetcher.releaseOne()
        try await waitForRequestCount(2, fetcher: fetcher)

        let queuedMaximum = await fetcher.maximumConcurrentRequests()
        let requestedModes = await fetcher.requestedModes()
        XCTAssertEqual(queuedMaximum, 1)
        XCTAssertEqual(requestedModes, [.quotaOnly, .quotaAndAccount])

        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)

        let finalRequestCount = await fetcher.requestCount()
        let finalMaximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(finalRequestCount, 2)
        XCTAssertEqual(finalMaximum, 1)
        XCTAssertEqual(fixture.store.snapshot?.fetchedAt, second.fetchedAt)
    }

    func testIndependentWakeCanRetryAfterCoalescedWakeFails() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let oldDate = now.addingTimeInterval(-120)
        let oldSnapshot = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: oldDate
        )
        let recovered = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 35,
            sparkUsed: nil,
            fetchedAt: now.addingTimeInterval(10)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [
            .failure(.requestTimedOut),
            .success(recovered)
        ])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: oldSnapshot
        )

        fixture.store.handleSystemWake(now: now)
        try await waitForRequestCount(1, fetcher: fetcher)
        fixture.store.handleSystemWake(now: now)
        fixture.store.handleSystemWake(now: now)
        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        try await Task.sleep(for: .milliseconds(75))

        let failedRequestCount = await fetcher.requestCount()
        XCTAssertEqual(failedRequestCount, 1)
        XCTAssertEqual(
            fixture.store.connectionState,
            .stale(lastSuccess: oldDate, issue: .requestTimedOut)
        )

        fixture.store.handleSystemWake(now: now.addingTimeInterval(10))
        try await waitForRequestCount(2, fetcher: fetcher)
        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)

        let finalRequestCount = await fetcher.requestCount()
        let finalMaximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(finalRequestCount, 2)
        XCTAssertEqual(finalMaximum, 1)
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertEqual(fixture.store.snapshot?.fetchedAt, recovered.fetchedAt)
    }

    func testShutdownIsIdempotentStopsRefreshAndRejectsFutureTriggers() async throws {
        let response = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 20,
            sparkUsed: nil,
            fetchedAt: Date(timeIntervalSince1970: 2_000)
        )
        let fetcher = ShutdownCompletingFetcher(snapshot: response)
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic
        )

        fixture.store.refresh(trigger: .manual)
        let deadline = Date().addingTimeInterval(2)
        while fetcher.requestCount == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(fetcher.requestCount, 1)

        fixture.store.shutdown()
        fixture.store.shutdown()
        XCTAssertEqual(fetcher.shutdownCount, 1)
        XCTAssertFalse(fixture.store.isRefreshing)

        let completionDeadline = Date().addingTimeInterval(2)
        while fetcher.completionCount == 0, Date() < completionDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(fetcher.completionCount, 1)
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cacheFileURL.path))

        fixture.store.start()
        fixture.store.refresh(trigger: .manual)
        fixture.store.popoverWillOpen()
        fixture.store.handleSystemWake(now: Date(timeIntervalSince1970: 3_000))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(fetcher.requestCount, 1)
        XCTAssertEqual(fetcher.shutdownCount, 1)
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cacheFileURL.path))
    }

    private struct StoreFixture {
        let store: AppStore
        let preferences: PreferencesStore
        let cacheFileURL: URL
    }

    private func makeStoreFixture(
        fetcher: any QuotaFetching,
        selection: MenuBarQuotaSelection,
        cachedSnapshot: QuotaSnapshot? = nil,
        hasChosenIdentityMode: Bool = true
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
        preferences.hasChosenIdentityMode = hasChosenIdentityMode
        preferences.menuBarQuotaSelection = selection

        let cacheFileURL = directory.appendingPathComponent("quota.json")
        let cache = SnapshotCache(fileURL: cacheFileURL)
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
        return StoreFixture(
            store: store,
            preferences: preferences,
            cacheFileURL: cacheFileURL
        )
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

    private func waitForRequestCount(
        _ expected: Int,
        fetcher: GatedRecordingFetcher
    ) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if await fetcher.requestCount() >= expected { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let actual = await fetcher.requestCount()
        XCTAssertEqual(actual, expected)
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

private enum FetchOutcome: Sendable {
    case success(QuotaSnapshot)
    case failure(ConnectionIssue)
}

private actor GatedRecordingFetcher: QuotaFetching {
    private let outcomes: [FetchOutcome]
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var totalRequests = 0
    private var activeRequests = 0
    private var maximumActiveRequests = 0
    private var modes: [IdentityMode] = []

    init(outcomes: [FetchOutcome]) {
        self.outcomes = outcomes
    }

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        let requestIndex = totalRequests
        totalRequests += 1
        activeRequests += 1
        maximumActiveRequests = max(maximumActiveRequests, activeRequests)
        modes.append(identityMode)

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }

        activeRequests -= 1
        guard outcomes.indices.contains(requestIndex) else {
            throw ConnectionIssue.quotaUnavailable
        }
        switch outcomes[requestIndex] {
        case let .success(snapshot):
            return snapshot
        case let .failure(issue):
            throw issue
        }
    }

    func releaseOne() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }

    func requestCount() -> Int {
        totalRequests
    }

    func maximumConcurrentRequests() -> Int {
        maximumActiveRequests
    }

    func requestedModes() -> [IdentityMode] {
        modes
    }
}

private final class ShutdownCompletingFetcher: QuotaFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshot: QuotaSnapshot
    private var continuation: CheckedContinuation<QuotaSnapshot, Error>?
    private var requests = 0
    private var completions = 0
    private var shutdowns = 0
    private var didShutDown = false

    init(snapshot: QuotaSnapshot) {
        self.snapshot = snapshot
    }

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        let result: QuotaSnapshot = try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            requests += 1
            if didShutDown {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
        recordCompletion()
        return result
    }

    private func recordCompletion() {
        lock.lock()
        completions += 1
        lock.unlock()
    }

    func shutdown() {
        lock.lock()
        guard !didShutDown else {
            lock.unlock()
            return
        }
        didShutDown = true
        shutdowns += 1
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: snapshot)
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    var shutdownCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return shutdowns
    }

    var completionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completions
    }
}
