import Darwin
import XCTest
@testable import Codex94

@MainActor
final class AppStoreTests: XCTestCase {
    func testDisplayPreferencesAndResetFormattingDoNotFetchOrRewriteQuotaCache() async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let snapshot = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: 85,
            fetchedAt: now,
            defaultResetsAt: now.addingTimeInterval(86_400),
            sparkResetsAt: now.addingTimeInterval(3_600)
        )
        let selection = MenuBarQuotaSelection.bucket(limitID: "model-special", kind: .weekly)
        let fetcher = SnapshotSequenceFetcher([snapshot])
        let fixture = try makeStoreFixture(fetcher: fetcher, selection: selection)
        fixture.preferences.theme = .terminalLight
        fixture.preferences.language = .simplifiedChinese
        fixture.preferences.refreshInterval = .fifteenMinutes
        let manualPath = try XCTUnwrap(fixture.preferences.manualCodexPath)
        XCTAssertEqual(
            manualPath,
            fixture.cacheFileURL.deletingLastPathComponent().appendingPathComponent("codex").path
        )

        // This one explicit refresh establishes the successful-data baseline.
        try await refreshAndWait(fixture.store)
        let baseline = try captureDisplayBaseline(fixture)
        XCTAssertNotNil(baseline.cache)
        let windowState = DashboardWindowState()
        windowState.select(section: .display)
        let dimensions = windowState.currentDimensions
        let sizePreset = windowState.selectedPreset

        for layout in MenuBarLayout.allCases {
            fixture.preferences.menuBarLayout = layout
            XCTAssertEqual(fixture.preferences.menuBarLayout, layout)
            try assertDisplayBaselineUnchanged(fixture, baseline: baseline)
        }

        let colors: [(StatusAccentRole, String)] = [
            (.healthy, "12A678"),
            (.warning, "D49316"),
            (.critical, "CF365B"),
            (.error, "754ACD")
        ]
        for (role, hex) in colors {
            let color = try XCTUnwrap(StatusAccentColor(hex: hex))
            fixture.preferences.statusAccentOverrides[role] = color
            XCTAssertEqual(fixture.preferences.statusAccentOverrides[role], color)
            try assertDisplayBaselineUnchanged(fixture, baseline: baseline)
        }

        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let languages: [(LanguagePreference, String)] = [
            (.english, "en_US"),
            (.simplifiedChinese, "zh-Hans-CN")
        ]
        let elapsedValues: [TimeInterval] = [0, 30, 90]
        for (language, localeID) in languages {
            for elapsed in elapsedValues {
                let reset = QuotaResetPresentation(
                    resetsAt: fixture.store.menuBarQuota?.window.resetsAt,
                    now: now.addingTimeInterval(elapsed),
                    language: language,
                    locale: Locale(identifier: localeID),
                    calendar: Calendar(identifier: .gregorian),
                    timeZone: timeZone
                )
                XCTAssertTrue(reset.accessibilityLabel.contains(reset.absolute))
                try assertDisplayBaselineUnchanged(fixture, baseline: baseline)
            }
        }

        fixture.preferences.restoreDefaultColors()

        XCTAssertTrue(fixture.preferences.statusAccentOverrides.isEmpty)
        for role in StatusAccentRole.allCases {
            XCTAssertNil(fixture.preferences.statusAccentOverrides[role])
        }
        XCTAssertEqual(fixture.preferences.menuBarLayout, .ringOnly)
        XCTAssertEqual(fixture.preferences.manualCodexPath, manualPath)
        XCTAssertEqual(fixture.preferences.identityMode, .quotaOnly)
        XCTAssertTrue(fixture.preferences.hasChosenIdentityMode)
        XCTAssertEqual(fixture.preferences.theme, .terminalLight)
        XCTAssertEqual(fixture.preferences.language, .simplifiedChinese)
        XCTAssertEqual(fixture.preferences.refreshInterval, .fifteenMinutes)
        XCTAssertEqual(fixture.preferences.menuBarQuotaSelection, selection)
        XCTAssertEqual(windowState.selection, .display)
        XCTAssertEqual(windowState.currentDimensions, dimensions)
        XCTAssertEqual(windowState.selectedPreset, sizePreset)
        try await Task.sleep(for: .milliseconds(75))
        try assertDisplayBaselineUnchanged(fixture, baseline: baseline)

        let requestCount = await fetcher.requestCount()
        let executablePaths = await fetcher.requestedExecutablePaths()
        XCTAssertEqual(requestCount, 1, "Only the explicit baseline manual refresh may fetch")
        XCTAssertEqual(executablePaths, [manualPath])
    }

    func testRecoveryNavigationPreservesStaleAndUnavailableStateWithoutFetching() async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: now,
            defaultResetsAt: now.addingTimeInterval(86_400)
        )

        for useCache in [false, true] {
            let fetcher = SnapshotSequenceFetcher([])
            let fixture = try makeStoreFixture(
                fetcher: fetcher,
                selection: .automatic,
                cachedSnapshot: useCache ? cached : nil
            )
            fixture.store.refresh(trigger: .manual)
            try await waitForRefreshToFinish(fixture.store)
            XCTAssertEqual(
                fixture.store.connectionState,
                useCache
                    ? .stale(lastSuccess: now, issue: .quotaUnavailable)
                    : .unavailable(.quotaUnavailable)
            )
            let baseline = try captureDisplayBaseline(fixture)
            XCTAssertEqual(baseline.cache != nil, useCache)
            let windowState = DashboardWindowState()
            let issue = try XCTUnwrap(fixture.store.lastIssue)

            windowState.select(section: issue.recoveryDestination.dashboardSection)
            XCTAssertEqual(windowState.selection, .diagnostics)
            windowState.select(section: nil)
            XCTAssertEqual(windowState.selection, .diagnostics)
            windowState.select(
                section: ConnectionIssue.notLoggedIn.recoveryDestination.dashboardSection
            )
            XCTAssertEqual(windowState.selection, .connection)
            windowState.select(section: nil)
            XCTAssertEqual(windowState.selection, .connection)
            fixture.preferences.statusAccentOverrides[.error] = try XCTUnwrap(
                StatusAccentColor(hex: "754ACD")
            )
            fixture.preferences.restoreDefaultColors()

            try await Task.sleep(for: .milliseconds(75))
            try assertDisplayBaselineUnchanged(fixture, baseline: baseline)
            let requestCount = await fetcher.requestCount()
            let executablePaths = await fetcher.requestedExecutablePaths()
            XCTAssertEqual(requestCount, 1, "Recovery navigation is not a retry")
            XCTAssertEqual(executablePaths, [try XCTUnwrap(fixture.preferences.manualCodexPath)])
        }
    }

    func testBrowsingAndResetProjectionKeepMenuBarFallbackAndRestoredSelectionIndependent() async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let defaultReset = now.addingTimeInterval(3 * 86_400)
        let sparkReset = now.addingTimeInterval(3_600)
        let restoredReset = now.addingTimeInterval(5_400)
        let snapshots = [
            makeSnapshot(
                defaultLimitID: "default-v2", defaultUsed: 30, sparkUsed: 80,
                fetchedAt: now, defaultResetsAt: defaultReset, sparkResetsAt: sparkReset
            ),
            makeSnapshot(
                defaultLimitID: "default-v2", defaultUsed: 35, sparkUsed: nil,
                fetchedAt: now.addingTimeInterval(60), defaultResetsAt: defaultReset
            ),
            makeSnapshot(
                defaultLimitID: "default-v2", defaultUsed: 35, sparkUsed: 85,
                fetchedAt: now.addingTimeInterval(120),
                defaultResetsAt: defaultReset, sparkResetsAt: restoredReset
            )
        ]
        let expectedResets = [sparkReset, defaultReset, restoredReset]
        let selection = MenuBarQuotaSelection.bucket(limitID: "model-special", kind: .weekly)
        let fetcher = SnapshotSequenceFetcher(snapshots)
        let fixture = try makeStoreFixture(fetcher: fetcher, selection: selection)
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        for index in snapshots.indices {
            // Each snapshot transition is an explicit manual refresh, not a UI side effect.
            try await refreshAndWait(fixture.store)
            let baseline = try captureDisplayBaseline(fixture)
            XCTAssertNotNil(baseline.cache)
            let usesFallback = index == 1
            XCTAssertEqual(fixture.store.menuBarSelectionUsesFallback, usesFallback)
            XCTAssertEqual(
                fixture.store.menuBarQuota?.bucket.limitID,
                usesFallback ? "default-v2" : "model-special"
            )
            XCTAssertEqual(fixture.preferences.menuBarQuotaSelection, selection)

            fixture.store.setViewedBucket("default-v2")
            XCTAssertEqual(fixture.store.viewedBucket?.limitID, "default-v2")
            let menuBarReset = QuotaResetPresentation(
                resetsAt: fixture.store.menuBarQuota?.window.resetsAt,
                now: now,
                language: .english,
                locale: Locale(identifier: "en_GB"),
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            )
            let expectedReset = QuotaResetPresentation(
                resetsAt: expectedResets[index],
                now: now,
                language: .english,
                locale: Locale(identifier: "en_GB"),
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            )
            let viewedReset = QuotaResetPresentation(
                resetsAt: fixture.store.viewedWindow?.resetsAt,
                now: now,
                language: .english,
                locale: Locale(identifier: "en_GB"),
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            )
            XCTAssertEqual(menuBarReset, expectedReset)
            if usesFallback {
                XCTAssertEqual(menuBarReset, viewedReset)
            } else {
                XCTAssertNotEqual(menuBarReset.absolute, viewedReset.absolute)
            }

            fixture.store.setViewedBucket("model-special")
            XCTAssertEqual(
                fixture.store.viewedBucket?.limitID,
                usesFallback ? "default-v2" : "model-special"
            )
            fixture.store.setViewedBucket("default-v2")
            XCTAssertEqual(fixture.preferences.menuBarQuotaSelection, selection)
            try await Task.sleep(for: .milliseconds(75))
            try assertDisplayBaselineUnchanged(fixture, baseline: baseline)

            let requestCount = await fetcher.requestCount()
            let executablePaths = await fetcher.requestedExecutablePaths()
            let manualPath = try XCTUnwrap(fixture.preferences.manualCodexPath)
            XCTAssertEqual(requestCount, index + 1)
            XCTAssertEqual(executablePaths, Array(repeating: manualPath, count: index + 1))
        }
    }

    func testDisplayChangesDuringRefreshDoNotChangeStateOrQueueAnotherRequest() async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let first = makeSnapshot(
            defaultLimitID: "default-v2", defaultUsed: 40, sparkUsed: 80,
            fetchedAt: now, defaultResetsAt: now.addingTimeInterval(86_400)
        )
        let second = makeSnapshot(
            defaultLimitID: "default-v2", defaultUsed: 35, sparkUsed: 75,
            fetchedAt: now.addingTimeInterval(60),
            defaultResetsAt: now.addingTimeInterval(86_400)
        )
        let fetcher = DelayedSnapshotSequenceFetcher([first, second])
        let fixture = try makeStoreFixture(fetcher: fetcher, selection: .defaultBucket(.weekly))
        try await refreshAndWait(fixture.store)

        fixture.store.refresh(trigger: .manual)
        XCTAssertTrue(fixture.store.isRefreshing)
        let baseline = try captureDisplayBaseline(fixture)
        XCTAssertNotNil(baseline.cache)

        for layout in MenuBarLayout.allCases {
            fixture.preferences.menuBarLayout = layout
        }
        fixture.preferences.statusAccentOverrides[.healthy] = try XCTUnwrap(
            StatusAccentColor(hex: "12A678")
        )
        fixture.preferences.restoreDefaultColors()
        let windowState = DashboardWindowState()
        windowState.select(
            section: ConnectionIssue.requestTimedOut.recoveryDestination.dashboardSection
        )
        windowState.select(section: nil)
        let reset = QuotaResetPresentation(
            resetsAt: fixture.store.menuBarQuota?.window.resetsAt,
            now: now.addingTimeInterval(30),
            language: .english,
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        )
        XCTAssertTrue(reset.accessibilityLabel.contains(reset.absolute))
        try assertDisplayBaselineUnchanged(fixture, baseline: baseline)

        // The already-running manual refresh may now finish and update its cache.
        try await waitForRefreshToFinish(fixture.store)
        let requestCount = await fetcher.totalRequestCount()
        XCTAssertEqual(requestCount, 2, "Only the two explicit manual refreshes may fetch")
        XCTAssertEqual(fixture.store.snapshot, second)
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertNil(fixture.store.lastIssue)
    }

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

    func testFreshSystemWakeRearmsBackgroundAndResetWithoutFetching() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let resetTarget = now.addingTimeInterval(3_600)
        let fetchedAt = now.addingTimeInterval(-59)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: fetchedAt,
            defaultResetsAt: resetTarget.addingTimeInterval(-5)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached,
            hasChosenIdentityMode: false
        )

        fixture.store.start()
        let originalBackgroundTask = try XCTUnwrap(fixture.store.backgroundTask)
        XCTAssertFalse(originalBackgroundTask.isCancelled)
        originalBackgroundTask.cancel()
        XCTAssertTrue(originalBackgroundTask.isCancelled)

        fixture.preferences.hasChosenIdentityMode = true
        fixture.store.handleSystemWake(now: now)

        let replacementBackgroundTask = try XCTUnwrap(fixture.store.backgroundTask)
        XCTAssertFalse(replacementBackgroundTask.isCancelled)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, resetTarget)
        XCTAssertNotNil(fixture.store.resetRefreshTask)
        let requestCount = await fetcher.requestCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertFalse(fixture.store.isRefreshing)
        XCTAssertEqual(fixture.store.snapshot?.fetchedAt, fetchedAt)
        fixture.store.shutdown()
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

    func testResetScheduleArmsEarliestAndSuccessfulSnapshotReplacesTarget() async throws {
        let base = Date(timeIntervalSince1970: 4_000_000_000)
        let originalTarget = base.addingTimeInterval(100)
        let replacementTarget = base.addingTimeInterval(50)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: base,
            defaultResetsAt: originalTarget.addingTimeInterval(-5)
        )
        let replacement = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 35,
            sparkUsed: nil,
            fetchedAt: base.addingTimeInterval(2),
            defaultResetsAt: replacementTarget.addingTimeInterval(-5)
        )
        let fixture = try makeStoreFixture(
            fetcher: SnapshotSequenceFetcher([replacement]),
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, originalTarget)
        XCTAssertNotNil(fixture.store.resetRefreshTask)

        fixture.store.refresh(trigger: .manual, startedAt: base.addingTimeInterval(1))
        try await waitForRefreshToFinish(fixture.store)

        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, replacementTarget)
        XCTAssertNotNil(fixture.store.resetRefreshTask)
        fixture.store.shutdown()
    }

    func testQuotaResetRemainsDisabledDuringOnboardingWithoutChosenIdentity() async throws {
        let base = Date(timeIntervalSince1970: 4_000_000_000)
        let target = base.addingTimeInterval(100)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: base,
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached,
            hasChosenIdentityMode: false
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        fixture.store.handleSystemClockChange(now: target)
        fixture.store.handleSystemWake(now: target)
        fixture.store.handleQuotaResetRefreshTimer(expectedDate: target, now: target)

        let requestCount = await fetcher.requestCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertNil(fixture.store.resetRefreshTask)
        XCTAssertNil(fixture.store.scheduledResetRefreshDate)
        XCTAssertNil(fixture.store.pendingResetRefreshDate)
        fixture.store.shutdown()
    }

    func testChoosingIdentityArmsCachedResetScheduleAndStartsOneRefresh() async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let target = now.addingTimeInterval(3_600)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: now,
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [.failure(.requestTimedOut)])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached,
            hasChosenIdentityMode: false
        )

        fixture.store.configureQuotaResetRefresh(now: now)
        XCTAssertNil(fixture.store.scheduledResetRefreshDate)
        XCTAssertNil(fixture.store.resetRefreshTask)

        fixture.store.chooseIdentityMode(.quotaOnly, now: now)
        try await waitForRequestCount(1, fetcher: fetcher)

        XCTAssertTrue(fixture.preferences.hasChosenIdentityMode)
        XCTAssertEqual(fixture.preferences.identityMode, .quotaOnly)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, target)
        XCTAssertNotNil(fixture.store.resetRefreshTask)

        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        let requestCount = await fetcher.requestCount()
        let maximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, target)
        XCTAssertNotNil(fixture.store.resetRefreshTask)
        fixture.store.shutdown()
    }

    func testConsecutiveDistinctResetTargetsEachProduceOneAttempt() async throws {
        let base = Date(timeIntervalSince1970: 4_000_000_000)
        let firstTarget = base.addingTimeInterval(100)
        let secondTarget = base.addingTimeInterval(200)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: 30,
            fetchedAt: base,
            defaultResetsAt: firstTarget.addingTimeInterval(-5),
            sparkResetsAt: secondTarget.addingTimeInterval(-5)
        )
        let afterFirstReset = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 35,
            sparkUsed: 25,
            fetchedAt: firstTarget.addingTimeInterval(1),
            sparkResetsAt: secondTarget.addingTimeInterval(-5)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [
            .success(afterFirstReset),
            .failure(.requestTimedOut)
        ])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, firstTarget)

        fixture.store.handleQuotaResetRefreshTimer(expectedDate: firstTarget, now: firstTarget)
        try await waitForRequestCount(1, fetcher: fetcher)
        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, secondTarget)
        XCTAssertNotNil(fixture.store.resetRefreshTask)

        fixture.store.handleQuotaResetRefreshTimer(expectedDate: secondTarget, now: secondTarget)
        try await waitForRequestCount(2, fetcher: fetcher)
        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        fixture.store.handleQuotaResetRefreshTimer(expectedDate: secondTarget, now: secondTarget)
        fixture.store.handleSystemClockChange(now: secondTarget.addingTimeInterval(1))

        let requestCount = await fetcher.requestCount()
        let maximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, secondTarget)
        XCTAssertNil(fixture.store.resetRefreshTask)
        fixture.store.shutdown()
    }

    func testSameInstantAcrossMultipleWindowsProducesOneResetAttempt() async throws {
        let base = Date(timeIntervalSince1970: 1_500_000_000)
        let target = base.addingTimeInterval(100)
        let reset = target.addingTimeInterval(-5)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: 30,
            fetchedAt: base,
            defaultResetsAt: reset,
            sparkResetsAt: reset
        )
        let fetcher = GatedRecordingFetcher(outcomes: [.failure(.requestTimedOut)])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        fixture.store.handleQuotaResetRefreshTimer(expectedDate: target, now: target)
        try await waitForRequestCount(1, fetcher: fetcher)
        fixture.store.handleQuotaResetRefreshTimer(expectedDate: target, now: target)
        fixture.store.handleSystemWake(now: target)

        let inFlightCount = await fetcher.requestCount()
        let inFlightMaximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(inFlightCount, 1)
        XCTAssertEqual(inFlightMaximum, 1)

        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        let finalCount = await fetcher.requestCount()
        XCTAssertEqual(finalCount, 1)
        fixture.store.shutdown()
    }

    func testResetBatchIsConsumedAfterSuccessOrFailureAndClockRollbackDoesNotRearmIt() async throws {
        let base = Date(timeIntervalSince1970: 1_500_000_000)
        let target = base.addingTimeInterval(100)
        let sameExpiredReset = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 35,
            sparkUsed: nil,
            fetchedAt: target.addingTimeInterval(1),
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let cases: [(String, FetchOutcome)] = [
            ("success", .success(sameExpiredReset)),
            ("failure", .failure(.requestTimedOut))
        ]

        for (name, outcome) in cases {
            let cached = makeSnapshot(
                defaultLimitID: "default-v2",
                defaultUsed: 40,
                sparkUsed: nil,
                fetchedAt: base,
                defaultResetsAt: target.addingTimeInterval(-5)
            )
            let fetcher = GatedRecordingFetcher(outcomes: [outcome])
            let fixture = try makeStoreFixture(
                fetcher: fetcher,
                selection: .automatic,
                cachedSnapshot: cached
            )

            fixture.store.configureQuotaResetRefresh(now: base)
            fixture.store.handleQuotaResetRefreshTimer(
                expectedDate: target,
                now: target.addingTimeInterval(-0.001)
            )
            let earlyRequestCount = await fetcher.requestCount()
            XCTAssertEqual(earlyRequestCount, 0, name)

            let scheduledTask = try XCTUnwrap(fixture.store.resetRefreshTask)
            fixture.store.handleQuotaResetRefreshTimer(expectedDate: target, now: target)
            XCTAssertTrue(scheduledTask.isCancelled, name)
            try await waitForRequestCount(1, fetcher: fetcher)
            await fetcher.releaseOne()
            try await waitForRefreshToFinish(fixture.store)

            XCTAssertEqual(fixture.store.scheduledResetRefreshDate, target, name)
            XCTAssertNil(fixture.store.resetRefreshTask, name)
            fixture.store.handleSystemClockChange(now: base)
            fixture.store.handleQuotaResetRefreshTimer(
                expectedDate: target,
                now: target.addingTimeInterval(1)
            )
            try await Task.sleep(for: .milliseconds(50))
            let finalRequestCount = await fetcher.requestCount()
            XCTAssertEqual(finalRequestCount, 1, name)
            XCTAssertNil(fixture.store.resetRefreshTask, name)
            fixture.store.shutdown()
        }
    }

    func testResetDueDuringManualBackgroundPopoverAndWakeQueuesOneFollowUpWithoutConcurrency() async throws {
        let base = Date(timeIntervalSince1970: 1_500_000_000)
        let target = base.addingTimeInterval(100)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: base,
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let recovered = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 30,
            sparkUsed: nil,
            fetchedAt: target.addingTimeInterval(1)
        )

        for initialTrigger in [
            RefreshTrigger.manual,
            .background,
            .popover,
            .systemWake
        ] {
            let fetcher = GatedRecordingFetcher(outcomes: [
                .failure(.requestTimedOut),
                .success(recovered)
            ])
            let fixture = try makeStoreFixture(
                fetcher: fetcher,
                selection: .automatic,
                cachedSnapshot: cached
            )

            fixture.store.configureQuotaResetRefresh(now: base)
            if initialTrigger == .systemWake {
                fixture.store.handleSystemWake(now: target.addingTimeInterval(-1))
            } else {
                fixture.store.refresh(
                    trigger: initialTrigger,
                    startedAt: target.addingTimeInterval(-1)
                )
            }
            try await waitForRequestCount(1, fetcher: fetcher)
            fixture.store.handleQuotaResetRefreshTimer(expectedDate: target, now: target)
            XCTAssertEqual(
                fixture.store.pendingResetRefreshDate,
                target,
                initialTrigger.rawValue
            )
            let initialMaximum = await fetcher.maximumConcurrentRequests()
            XCTAssertEqual(initialMaximum, 1, initialTrigger.rawValue)

            await fetcher.releaseOne()
            try await waitForRequestCount(2, fetcher: fetcher)
            XCTAssertNil(fixture.store.pendingResetRefreshDate, initialTrigger.rawValue)
            let followUpMaximum = await fetcher.maximumConcurrentRequests()
            XCTAssertEqual(followUpMaximum, 1, initialTrigger.rawValue)

            await fetcher.releaseOne()
            try await waitForRefreshToFinish(fixture.store)
            let finalRequestCount = await fetcher.requestCount()
            let finalMaximum = await fetcher.maximumConcurrentRequests()
            XCTAssertEqual(finalRequestCount, 2, initialTrigger.rawValue)
            XCTAssertEqual(finalMaximum, 1, initialTrigger.rawValue)
            fixture.store.shutdown()
        }
    }

    func testPreTargetCompletionReconcilesDueResetBeforeReplacingItsSchedule() async throws {
        let base = Date(timeIntervalSince1970: 1_500_000_000)
        let target = base.addingTimeInterval(100)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: base,
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let earlySnapshot = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 35,
            sparkUsed: nil,
            fetchedAt: target.addingTimeInterval(-1),
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let recovered = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 30,
            sparkUsed: nil,
            fetchedAt: target.addingTimeInterval(1)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [
            .success(earlySnapshot),
            .success(recovered)
        ])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        // Model the timer becoming ready without its MainActor handler winning
        // the race against this request's completion continuation.
        fixture.store.resetRefreshTask?.cancel()
        fixture.store.refresh(trigger: .manual, startedAt: target.addingTimeInterval(-1))
        try await waitForRequestCount(1, fetcher: fetcher)

        await fetcher.releaseOne()
        try await waitForRequestCount(2, fetcher: fetcher)
        let followUpMaximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(followUpMaximum, 1)

        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        let finalRequestCount = await fetcher.requestCount()
        let finalMaximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(finalRequestCount, 2)
        XCTAssertEqual(finalMaximum, 1)
        XCTAssertNil(fixture.store.pendingResetRefreshDate)
        fixture.store.shutdown()
    }

    func testPreTargetSuccessFetchedAtTargetSatisfiesPendingReset() async throws {
        let base = Date(timeIntervalSince1970: 1_500_000_000)
        let target = base.addingTimeInterval(100)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: base,
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let covered = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 35,
            sparkUsed: nil,
            fetchedAt: target,
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [.success(covered)])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        fixture.store.refresh(trigger: .manual, startedAt: target.addingTimeInterval(-1))
        try await waitForRequestCount(1, fetcher: fetcher)
        fixture.store.handleQuotaResetRefreshTimer(expectedDate: target, now: target)
        XCTAssertEqual(fixture.store.pendingResetRefreshDate, target)

        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        try await Task.sleep(for: .milliseconds(50))

        let requestCount = await fetcher.requestCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertNil(fixture.store.pendingResetRefreshDate)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, target)
        XCTAssertNil(fixture.store.resetRefreshTask)
        fixture.store.shutdown()
    }

    func testPostTargetActiveFailureConsumesResetWithoutFollowUp() async throws {
        let base = Date(timeIntervalSince1970: 1_500_000_000)
        let target = base.addingTimeInterval(100)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: base,
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [.failure(.requestTimedOut)])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        fixture.store.refresh(trigger: .manual, startedAt: target)
        try await waitForRequestCount(1, fetcher: fetcher)
        fixture.store.handleQuotaResetRefreshTimer(expectedDate: target, now: target)
        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        try await Task.sleep(for: .milliseconds(50))

        let requestCount = await fetcher.requestCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, target)
        XCTAssertNil(fixture.store.resetRefreshTask)
        fixture.store.shutdown()
    }

    func testPreferenceChangeFollowUpHasPriorityAndAlsoConsumesPendingReset() async throws {
        let base = Date(timeIntervalSince1970: 1_500_000_000)
        let target = base.addingTimeInterval(100)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: base,
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let updated = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 30,
            sparkUsed: 20,
            fetchedAt: target.addingTimeInterval(1)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [
            .failure(.requestTimedOut),
            .success(updated)
        ])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        fixture.store.refresh(trigger: .manual, startedAt: target.addingTimeInterval(-1))
        try await waitForRequestCount(1, fetcher: fetcher)
        fixture.store.handleQuotaResetRefreshTimer(expectedDate: target, now: target)
        fixture.store.setIdentityMode(.quotaAndAccount)

        await fetcher.releaseOne()
        try await waitForRequestCount(2, fetcher: fetcher)
        let requestedModes = await fetcher.requestedModes()
        let queuedMaximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(requestedModes, [.quotaOnly, .quotaAndAccount])
        XCTAssertEqual(queuedMaximum, 1)

        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        try await Task.sleep(for: .milliseconds(50))
        let finalRequestCount = await fetcher.requestCount()
        XCTAssertEqual(finalRequestCount, 2)
        XCTAssertNil(fixture.store.pendingResetRefreshDate)
        fixture.store.shutdown()
    }

    func testClockForwardUsesLatestDueAndBackwardRearmsWithoutEarlyFollowUp() async throws {
        let base = Date(timeIntervalSince1970: 4_000_000_000)
        let firstTarget = base.addingTimeInterval(100)
        let secondTarget = base.addingTimeInterval(200)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: 30,
            fetchedAt: base,
            defaultResetsAt: firstTarget.addingTimeInterval(-5),
            sparkResetsAt: secondTarget.addingTimeInterval(-5)
        )
        let recovered = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 25,
            sparkUsed: nil,
            fetchedAt: secondTarget.addingTimeInterval(1)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [
            .failure(.requestTimedOut),
            .success(recovered)
        ])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        fixture.store.refresh(trigger: .manual, startedAt: firstTarget.addingTimeInterval(-1))
        try await waitForRequestCount(1, fetcher: fetcher)

        fixture.store.handleSystemClockChange(now: secondTarget)
        XCTAssertEqual(fixture.store.pendingResetRefreshDate, secondTarget)
        let forwardRequestCount = await fetcher.requestCount()
        XCTAssertEqual(forwardRequestCount, 1)

        fixture.store.handleSystemClockChange(now: base.addingTimeInterval(25))
        XCTAssertNil(fixture.store.pendingResetRefreshDate)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, secondTarget)
        XCTAssertNotNil(fixture.store.resetRefreshTask)

        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        let rolledBackRequestCount = await fetcher.requestCount()
        XCTAssertEqual(rolledBackRequestCount, 1)

        fixture.store.handleQuotaResetRefreshTimer(
            expectedDate: secondTarget,
            now: secondTarget
        )
        try await waitForRequestCount(2, fetcher: fetcher)
        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)

        let finalRequestCount = await fetcher.requestCount()
        let finalMaximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(finalRequestCount, 2)
        XCTAssertEqual(finalMaximum, 1)
        fixture.store.shutdown()
    }

    func testWakeAtResetAndWakeFreshnessShareOneRequest() async throws {
        let base = Date(timeIntervalSince1970: 1_500_000_000)
        let target = base.addingTimeInterval(100)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: target.addingTimeInterval(-120),
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let updated = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 30,
            sparkUsed: nil,
            fetchedAt: target.addingTimeInterval(1)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [.success(updated)])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        fixture.store.handleSystemWake(now: target)
        try await waitForRequestCount(1, fetcher: fetcher)
        fixture.store.handleSystemWake(now: target)
        try await Task.sleep(for: .milliseconds(50))

        let requestCount = await fetcher.requestCount()
        let maximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(maximum, 1)
        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        fixture.store.shutdown()
    }

    func testWakeBeforeResetDoesNotFetchAndWakeAfterResetFetchesOnce() async throws {
        let base = Date(timeIntervalSince1970: 1_500_000_000)
        let target = base.addingTimeInterval(100)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: target.addingTimeInterval(-20),
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [.failure(.requestTimedOut)])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        fixture.store.handleSystemWake(now: target.addingTimeInterval(-10))
        XCTAssertFalse(fixture.store.isRefreshing)
        try await Task.sleep(for: .milliseconds(50))
        let beforeTargetCount = await fetcher.requestCount()
        XCTAssertEqual(beforeTargetCount, 0)
        XCTAssertEqual(fixture.store.scheduledResetRefreshDate, target)
        XCTAssertNotNil(fixture.store.resetRefreshTask)

        fixture.store.handleSystemWake(now: target.addingTimeInterval(0.001))
        try await waitForRequestCount(1, fetcher: fetcher)
        fixture.store.handleSystemWake(now: target.addingTimeInterval(1))
        try await Task.sleep(for: .milliseconds(50))

        let duringRequestCount = await fetcher.requestCount()
        let duringRequestMaximum = await fetcher.maximumConcurrentRequests()
        XCTAssertEqual(duringRequestCount, 1)
        XCTAssertEqual(duringRequestMaximum, 1)

        await fetcher.releaseOne()
        try await waitForRefreshToFinish(fixture.store)
        let finalRequestCount = await fetcher.requestCount()
        XCTAssertEqual(finalRequestCount, 1)
        fixture.store.shutdown()
    }

    func testShutdownClearsResetStateAndRejectsTimerClockAndWake() async throws {
        let base = Date(timeIntervalSince1970: 4_000_000_000)
        let target = base.addingTimeInterval(100)
        let cached = makeSnapshot(
            defaultLimitID: "default-v2",
            defaultUsed: 40,
            sparkUsed: nil,
            fetchedAt: base,
            defaultResetsAt: target.addingTimeInterval(-5)
        )
        let fetcher = GatedRecordingFetcher(outcomes: [])
        let fixture = try makeStoreFixture(
            fetcher: fetcher,
            selection: .automatic,
            cachedSnapshot: cached
        )

        fixture.store.configureQuotaResetRefresh(now: base)
        XCTAssertNotNil(fixture.store.resetRefreshTask)
        fixture.store.shutdown()

        XCTAssertNil(fixture.store.resetRefreshTask)
        XCTAssertNil(fixture.store.scheduledResetRefreshDate)
        XCTAssertNil(fixture.store.pendingResetRefreshDate)
        XCTAssertNil(fixture.store.activeRefreshStartedAt)

        fixture.store.handleQuotaResetRefreshTimer(expectedDate: target, now: target)
        fixture.store.handleSystemClockChange(now: target)
        fixture.store.handleSystemWake(now: target)
        try await Task.sleep(for: .milliseconds(50))
        let requestCount = await fetcher.requestCount()
        XCTAssertEqual(requestCount, 0)
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

    private struct CacheFingerprint: Equatable {
        let bytes: Data
        let modifiedAt: Date
        let fileNumber: UInt64
    }

    private struct DisplaySideEffectBaseline {
        let snapshot: QuotaSnapshot?
        let connectionState: ConnectionState
        let isRefreshing: Bool
        let lastIssue: ConnectionIssue?
        let cache: CacheFingerprint?
    }

    private func captureDisplayBaseline(_ fixture: StoreFixture) throws -> DisplaySideEffectBaseline {
        DisplaySideEffectBaseline(
            snapshot: fixture.store.snapshot,
            connectionState: fixture.store.connectionState,
            isRefreshing: fixture.store.isRefreshing,
            lastIssue: fixture.store.lastIssue,
            cache: try cacheFingerprint(at: fixture.cacheFileURL)
        )
    }

    private func assertDisplayBaselineUnchanged(
        _ fixture: StoreFixture,
        baseline: DisplaySideEffectBaseline,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(fixture.store.snapshot, baseline.snapshot, file: file, line: line)
        XCTAssertEqual(fixture.store.connectionState, baseline.connectionState, file: file, line: line)
        XCTAssertEqual(fixture.store.isRefreshing, baseline.isRefreshing, file: file, line: line)
        XCTAssertEqual(fixture.store.lastIssue, baseline.lastIssue, file: file, line: line)
        XCTAssertEqual(
            try cacheFingerprint(at: fixture.cacheFileURL), baseline.cache, file: file, line: line
        )
    }

    private func cacheFingerprint(at fileURL: URL) throws -> CacheFingerprint? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return CacheFingerprint(
            bytes: try Data(contentsOf: fileURL),
            modifiedAt: try XCTUnwrap(attributes[.modificationDate] as? Date),
            fileNumber: try XCTUnwrap(attributes[.systemFileNumber] as? NSNumber).uint64Value
        )
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
        fetchedAt: Date,
        defaultResetsAt: Date? = nil,
        sparkResetsAt: Date? = nil
    ) -> QuotaSnapshot {
        var buckets = [
            bucket(
                id: defaultLimitID,
                name: nil,
                windows: [window(.weekly, used: defaultUsed, resetsAt: defaultResetsAt)]
            )
        ]
        if let sparkUsed {
            buckets.append(bucket(
                id: "model-special",
                name: "Spark",
                windows: [window(.weekly, used: sparkUsed, resetsAt: sparkResetsAt)]
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

    private func window(
        _ kind: QuotaWindowKind,
        used: Int,
        resetsAt: Date? = nil
    ) -> QuotaWindowSnapshot {
        QuotaWindowSnapshot(
            kind: kind,
            usedPercent: used,
            windowMinutes: kind == .fiveHour ? 300 : 10_080,
            resetsAt: resetsAt
        )
    }
}

private actor SnapshotSequenceFetcher: QuotaFetching {
    private var snapshots: [QuotaSnapshot]
    private var executablePaths: [String] = []

    init(_ snapshots: [QuotaSnapshot]) {
        self.snapshots = snapshots
    }

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        executablePaths.append(executable.executableURL.path)
        guard !snapshots.isEmpty else { throw ConnectionIssue.quotaUnavailable }
        return snapshots.removeFirst()
    }

    func requestCount() -> Int { executablePaths.count }

    func requestedExecutablePaths() -> [String] { executablePaths }
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

    func totalRequestCount() -> Int { requestCount }
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
