import Darwin
import Foundation
import XCTest
@testable import Codex94

@MainActor
final class ClaudeQuotaStoreTests: XCTestCase {
    func testResetUsesExistingPollingAfterGraceAndNeverInventsRecoveredQuota() async throws {
        let fixture = try fixture()
        fixture.preferences.claudeRefreshInterval = .thirtyMinutes
        let began = fixture.clock.read()
        let reset = began.addingTimeInterval(30)
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        let windows = [ClaudeQuotaWindow(kind: .fiveHour, usedPercentage: 90, resetsAt: reset),
                       ClaudeQuotaWindow(kind: .weekly, usedPercentage: 85, resetsAt: reset)]
        await fixture.fetcher.complete(.success(ClaudeQuotaReport(source: .cliUsage, reportedAt: began,
            receivedAt: began, windows: windows)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, reset.addingTimeInterval(5))

        fixture.clock.advance(30)
        try await poll(fixture)
        XCTAssertNil(fixture.store.snapshot, "Expired windows disappear without pretending their remaining quota is 100%")
        XCTAssertEqual(fixture.store.lastIssue, .noData)
        var count = await fixture.fetcher.count()
        XCTAssertEqual(count, 1)
        fixture.clock.advance(4)
        try await poll(fixture)
        count = await fixture.fetcher.count()
        XCTAssertEqual(count, 1, "Reset grace has not elapsed")
        fixture.clock.advance(1)
        try await poll(fixture)
        try await wait { await fixture.fetcher.count() == 2 }
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, fixture.clock.read().addingTimeInterval(1_800))
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 77)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 23)
        fixture.clock.advance(15)
        try await poll(fixture)
        count = await fixture.fetcher.count()
        XCTAssertEqual(count, 2, "Two windows sharing one target need only one accepted read")
    }

    func testManualReadConsumesSimultaneousResetAndBackgroundDeadlineWithoutFailureLoop() async throws {
        let fixture = try fixture()
        fixture.preferences.claudeRefreshInterval = .oneMinute
        let began = fixture.clock.read()
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(report(at: began, used: 50, resetAt: began.addingTimeInterval(55))))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(60))
        fixture.clock.advance(60)
        fixture.store.refresh()
        fixture.store.refresh(trigger: .quotaReset)
        fixture.store.refresh(trigger: .background)
        try await poll(fixture)
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.failure(.timedOut))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(120))
        for _ in 0..<3 {
            fixture.clock.advance(15)
            try await poll(fixture)
            let count = await fixture.fetcher.count()
            XCTAssertEqual(count, 2, "A failed reset read must not retry every poll")
        }
        fixture.clock.advance(15)
        try await poll(fixture)
        try await wait { await fixture.fetcher.count() == 3 }
        await fixture.fetcher.complete(.failure(.timedOut))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(180))
    }

    func testReadStartedBeforeResetLeavesExactlyOneFollowupWhenOldReplyFinishesAfterReset() async throws {
        let fixture = try fixture()
        fixture.preferences.claudeRefreshInterval = .thirtyMinutes
        let began = fixture.clock.read()
        let reset = began.addingTimeInterval(30)
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(report(at: began, used: 70, resetAt: reset)))
        try await wait { !fixture.store.isRefreshing }
        fixture.clock.advance(29)
        let requestStartedAt = fixture.clock.read()
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count() == 2 }
        fixture.clock.advance(6)
        try await poll(fixture)
        var count = await fixture.fetcher.count()
        XCTAssertEqual(count, 2, "The due poll cannot overlap an accepted read")
        await fixture.fetcher.complete(.success(report(at: requestStartedAt, used: 70, resetAt: reset)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, reset.addingTimeInterval(5))
        XCTAssertNil(fixture.store.snapshot)
        fixture.clock.advance(15)
        try await poll(fixture)
        try await wait { await fixture.fetcher.count() == 3 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 12)))
        try await wait { !fixture.store.isRefreshing }
        fixture.clock.advance(15)
        try await poll(fixture)
        count = await fixture.fetcher.count()
        XCTAssertEqual(count, 3)
    }

    func testFirstCLIReplyWithAlreadyDueResetDoesNotImmediatelyRepeat() async throws {
        for hasWeekly in [false, true] {
            let fixture = try fixture()
            fixture.preferences.claudeRefreshInterval = .thirtyMinutes
            let began = fixture.clock.read()
            fixture.store.start()
            try await wait { await fixture.fetcher.count() == 1 }
            var windows = [ClaudeQuotaWindow(kind: .fiveHour, usedPercentage: 90,
                                            resetsAt: began.addingTimeInterval(-10))]
            if hasWeekly { windows.append(.init(kind: .weekly, usedPercentage: 40, resetsAt: began.addingTimeInterval(10_000))) }
            await fixture.fetcher.complete(.success(.init(source: .cliUsage, reportedAt: began,
                                                         receivedAt: began, windows: windows)))
            try await wait { !fixture.store.isRefreshing }
            XCTAssertNil(fixture.store.snapshot?.defaultBucket?.window(.fiveHour))
            XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(1_800))
            fixture.clock.advance(15)
            try await poll(fixture)
            let count = await fixture.fetcher.count()
            XCTAssertEqual(count, 1)
        }
    }

    func testFirstCLIReadCrossingResetKeepsFollowupEvenWhenNoWindowRemainsVisible() async throws {
        let fixture = try fixture()
        fixture.preferences.claudeRefreshInterval = .thirtyMinutes
        let began = fixture.clock.read()
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        fixture.clock.advance(35)
        await fixture.fetcher.complete(.success(report(at: began, used: 99, resetAt: began.addingTimeInterval(30))))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertEqual(fixture.store.lastIssue, .noData)
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(35))
        try await poll(fixture)
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 40)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 60)
    }

    func testPassiveSourceSwitchDoesNotBorrowCLIWatermarkAndCLIReplyUsesItsAcceptedStart() async throws {
        let fixture = try fixture()
        fixture.preferences.claudeRefreshInterval = .thirtyMinutes
        let began = fixture.clock.read()
        let windows = [ClaudeQuotaWindow(kind: .fiveHour, usedPercentage: 90, resetsAt: began.addingTimeInterval(55)),
                       ClaudeQuotaWindow(kind: .weekly, usedPercentage: 20, resetsAt: began.addingTimeInterval(10_000))]
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(.init(source: .cliUsage, reportedAt: began, receivedAt: began, windows: windows)))
        try await wait { !fixture.store.isRefreshing }
        fixture.clock.advance(60)
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count() == 2 }
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(1_860))
        let payload = Data(#"{"session_id":"00000000-0000-0000-0000-000000000002","rate_limits":{"five_hour":{"used_percentage":90,"resets_at":2000000055},"seven_day":{"used_percentage":20,"resets_at":2000010000}}}"#.utf8)
        try fixture.cache.capture(payload, at: fixture.clock.read())
        try await poll(fixture)
        XCTAssertEqual(fixture.store.source, .statusline)
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(60),
                       "A new passive source does not inherit another source's covered targets")
        fixture.clock.advance(5)
        await fixture.fetcher.complete(.success(.init(source: .cliUsage, reportedAt: fixture.clock.read(),
                                                     receivedAt: fixture.clock.read(), windows: windows)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.source, .cliUsage)
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(1_860),
                       "Switching back to CLI preserves this request's start-time coverage")
        fixture.clock.advance(15)
        try await poll(fixture)
        let count = await fixture.fetcher.count()
        XCTAssertEqual(count, 2)
    }

    func testClockRollbackDoesNotReplayAnAttemptedReset() async throws {
        let fixture = try fixture()
        fixture.preferences.claudeRefreshInterval = .thirtyMinutes
        let began = fixture.clock.read()
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(report(at: began, used: 70, resetAt: began.addingTimeInterval(30))))
        try await wait { !fixture.store.isRefreshing }
        fixture.clock.advance(35)
        try await poll(fixture)
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.failure(.timedOut))
        try await wait { !fixture.store.isRefreshing }
        fixture.clock.advance(-20)
        fixture.store.handleSystemClockChange(now: fixture.clock.read())
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(1_815))
        fixture.clock.advance(20)
        try await poll(fixture)
        let count = await fixture.fetcher.count()
        XCTAssertEqual(count, 2, "The same reset cannot become unconsumed after moving the wall clock back")
    }

    func testLoginFailureAndStopClearPendingResetWork() async throws {
        let fixture = try fixture()
        fixture.preferences.claudeRefreshInterval = .thirtyMinutes
        let began = fixture.clock.read()
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(report(at: began, used: 70, resetAt: began.addingTimeInterval(30))))
        try await wait { !fixture.store.isRefreshing }
        fixture.clock.advance(20)
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.failure(.loginRequired))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(1_820))
        fixture.clock.advance(15)
        try await poll(fixture)
        let count = await fixture.fetcher.count()
        XCTAssertEqual(count, 2)
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertEqual(fixture.store.lastIssue, .loginRequired)
        fixture.store.stop()
        XCTAssertNil(fixture.store.nextAutomaticRefreshAt)
        fixture.clock.advance(1_800)
        await fixture.sleeper.tick()
        fixture.store.refresh(trigger: .quotaReset)
        XCTAssertNil(fixture.store.nextAutomaticRefreshAt)
        let stoppedCount = await fixture.fetcher.count()
        XCTAssertEqual(stoppedCount, 2)
    }

    func testPollingKeepsFailureAndLongRefreshIntervalDoesNotPrematurelyAgeHealthyData() async throws {
        let fixture = try fixture()
        fixture.preferences.claudeRefreshInterval = .thirtyMinutes
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 10)))
        try await wait { !fixture.store.isRefreshing }
        fixture.clock.advance(900)
        try await wait { await fixture.sleeper.count() >= 1 }
        await fixture.sleeper.tick()
        try await wait { await fixture.sleeper.count() >= 2 }
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertNil(fixture.store.lastIssue)

        fixture.store.refresh()
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.failure(.timedOut))
        try await wait { !fixture.store.isRefreshing }
        let old = fixture.store.snapshot
        fixture.clock.advance(15)
        await fixture.sleeper.tick()
        try await wait { await fixture.sleeper.count() >= 3 }
        XCTAssertEqual(fixture.store.snapshot, old)
        XCTAssertEqual(fixture.store.lastIssue, .timedOut)
        guard case .stale = fixture.store.connectionState else { return XCTFail("Polling old data must not erase a fetch failure") }
    }

    func testExplicitLoginFailureDoesNotBorrowNewerBridgeFromUnknownIdentity() async throws {
        let fixture = try fixture()
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 10)))
        try await wait { !fixture.store.isRefreshing }
        fixture.clock.advance(20)
        let json = #"{"session_id":"00000000-0000-0000-0000-000000000002","rate_limits":{"five_hour":{"used_percentage":95,"resets_at":2000010000}}}"#
        try fixture.cache.capture(Data(json.utf8), at: fixture.clock.read())
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.failure(.loginRequired))
        try await wait { !fixture.store.isRefreshing }
        try await wait { await fixture.sleeper.count() >= 1 }
        await fixture.sleeper.tick()
        try await wait { await fixture.sleeper.count() >= 2 }
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertNil(fixture.store.source)
        XCTAssertNil(fixture.store.reportedAt)
        XCTAssertEqual(fixture.store.lastIssue, .loginRequired)
    }

    func testStoppedGenerationCannotReplaceReenabledSnapshot() async throws {
        let fixture = try fixture()
        var notifications = NotificationPreferences()
        notifications.isEnabled = true
        fixture.preferences.claudeNotifications = notifications
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        fixture.store.stop()
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 99)))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertTrue(fixture.store.isRefreshing)
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 20)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 80)
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertTrue(fixture.notifications.deliveries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cache.fileURL.path))
    }

    func testReenableImmediatelyRemovesWindowsThatExpiredWhileDisabled() async throws {
        let fixture = try fixture()
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 10)))
        try await wait { !fixture.store.isRefreshing }
        fixture.store.stop()
        fixture.clock.advance(10_001)
        fixture.store.start()
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertEqual(fixture.store.lastIssue, .noData)
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 20)))
        try await wait { !fixture.store.isRefreshing }
    }

    func testEmptyOrExpiredPassiveReportCannotReplaceFreshCLIData() async throws {
        let fixture = try fixture()
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 10)))
        try await wait { !fixture.store.isRefreshing }
        let original = fixture.store.snapshot
        try await wait { await fixture.sleeper.count() >= 1 }
        for (index, windows) in [[], [ClaudeQuotaWindow(kind: .fiveHour, usedPercentage: 99,
                                                       resetsAt: fixture.clock.read().addingTimeInterval(-1))]].enumerated() {
            fixture.clock.advance(15)
            let passive = ClaudeQuotaReport(source: .statusline, reportedAt: fixture.clock.read(),
                                           receivedAt: fixture.clock.read(), windows: windows)
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(passive))
            let raw = try JSONSerialization.data(withJSONObject: ["version": 1, "report": object, "producers": [:]])
            try ClaudeLocalFile.write(raw, to: fixture.cache.fileURL)
            await fixture.sleeper.tick()
            try await wait { await fixture.sleeper.count() >= index + 2 }
            XCTAssertEqual(fixture.store.snapshot, original)
            XCTAssertEqual(fixture.store.source, .cliUsage)
            XCTAssertEqual(fixture.store.connectionState, .connected)
        }
    }

    func testSourceChangeResetsNotificationBaselineAndCachedReplayIsSilent() async throws {
        let fixture = try fixture()
        let reset = fixture.clock.read().addingTimeInterval(10_000)
        var notifications = NotificationPreferences()
        notifications.isEnabled = true
        fixture.preferences.claudeNotifications = notifications
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 50, resetAt: reset)))
        try await wait { !fixture.store.isRefreshing && fixture.store.notificationController.authorization == .authorized }
        fixture.clock.advance(1)
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 85, resetAt: reset)))
        try await wait { fixture.notifications.deliveries.count == 1 }
        let payload = Data(#"{"session_id":"00000000-0000-0000-0000-000000000002","rate_limits":{"five_hour":{"used_percentage":95,"resets_at":2000010000}}}"#.utf8)
        fixture.clock.advance(20)
        try fixture.cache.capture(payload, at: fixture.clock.read())
        try await wait { await fixture.sleeper.count() >= 1 }
        await fixture.sleeper.tick()
        try await wait { fixture.store.source == .statusline }
        XCTAssertEqual(fixture.notifications.deliveries.count, 1, "Changing source must establish a fresh baseline")
        let observedAt = fixture.store.reportedAt
        fixture.clock.advance(15)
        try fixture.cache.capture(payload, at: fixture.clock.read())
        let bytes = try Data(contentsOf: fixture.cache.fileURL)
        await fixture.sleeper.tick()
        try await wait { await fixture.sleeper.count() >= 3 }
        XCTAssertEqual(fixture.store.reportedAt, observedAt)
        XCTAssertEqual(fixture.notifications.deliveries.count, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.cache.fileURL), bytes)
    }

    func testStopDoesNotWaitOnMainActorForCLIThatIgnoresTermination() async throws {
        let fixture = try fixture(fetcherFactory: { root in
            ClaudeCLIUsageClient(executableURL: root.appendingPathComponent("claude"),
                                 runtimeDirectory: root.appendingPathComponent("runtime"), timeout: 20)
        })
        let parentFile = fixture.directory.appendingPathComponent("pid")
        let childFile = fixture.directory.appendingPathComponent("child-pid")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf '2.1.165 (Claude Code)\\n'; exit 0; fi
        trap '' TERM
        printf '%s' $$ > '\(parentFile.path)'
        sleep 30 &
        printf '%s' $! > '\(childFile.path)'
        wait
        """
        let executable = fixture.directory.appendingPathComponent("claude")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        fixture.store.start()
        try await wait { FileManager.default.fileExists(atPath: childFile.path) }
        let parent = try XCTUnwrap(Int32(try String(contentsOf: parentFile, encoding: .utf8)))
        let child = try XCTUnwrap(Int32(try String(contentsOf: childFile, encoding: .utf8)))
        let clock = ContinuousClock()
        let began = clock.now
        fixture.store.stop()
        XCTAssertLessThan(clock.now - began, .milliseconds(200), "Disable must not wait for SIGTERM grace on MainActor")
        XCTAssertFalse(fixture.store.isRefreshing)
        try await wait { kill(parent, 0) != 0 && kill(child, 0) != 0 }
    }

    private struct Fixture {
        let directory: URL
        let store: ClaudeQuotaStore
        let preferences: PreferencesStore
        let cache: ClaudeStatuslineCache
        let fetcher: ClaudeStoreTestFetcher
        let sleeper: ClaudeStoreTestSleeper
        let clock: ClaudeStoreTestClock
        let notifications: ClaudeStoreTestNotifications
    }

    private func fixture(fetcherFactory: (@Sendable (URL) -> any ClaudeQuotaFetching)? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "Codex94.ClaudeStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let preferences = PreferencesStore(defaults: defaults)
        preferences.claudeMonitoringEnabled = true
        let cache = ClaudeStatuslineCache(fileURL: root.appendingPathComponent("support/statusline-quota.json"))
        let installer = ClaudeStatuslineInstaller(settingsURL: root.appendingPathComponent("settings.json"), cache: cache,
            executableURL: URL(fileURLWithPath: "/bin/echo"), supportDirectory: root.appendingPathComponent("support"))
        let fetcher = ClaudeStoreTestFetcher()
        let sleeper = ClaudeStoreTestSleeper()
        let clock = ClaudeStoreTestClock()
        let notifications = ClaudeStoreTestNotifications()
        let factory: @Sendable () -> any ClaudeQuotaFetching = {
            if let fetcherFactory { return fetcherFactory(root) }
            return fetcher
        }
        let store = ClaudeQuotaStore(preferences: preferences, cache: cache, installer: installer,
            fetcherFactory: factory, notificationController: NotificationController(service: notifications),
            now: { clock.read() }, sleep: { try await sleeper.sleep($0) })
        addTeardownBlock { [store] in
            await MainActor.run { store.shutdown() }
            await fetcher.finishAll()
            await sleeper.finishAll()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return Fixture(directory: root, store: store, preferences: preferences, cache: cache, fetcher: fetcher,
                       sleeper: sleeper, clock: clock, notifications: notifications)
    }

    private func report(at date: Date, used: Double, resetAt: Date? = nil) -> ClaudeQuotaReport {
        ClaudeQuotaReport(source: .cliUsage, reportedAt: date, receivedAt: date,
            windows: [.init(kind: .fiveHour, usedPercentage: used, resetsAt: resetAt ?? date.addingTimeInterval(10_000))])
    }

    private func poll(_ fixture: Fixture) async throws {
        try await wait { await fixture.sleeper.count() > 0 }
        let before = await fixture.sleeper.count()
        await fixture.sleeper.tick()
        try await wait { await fixture.sleeper.count() > before }
    }

    private func wait(_ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Synthetic Claude state did not settle")
    }
}

private actor ClaudeStoreTestFetcher: ClaudeQuotaFetching {
    private var total = 0
    private var pending: [CheckedContinuation<ClaudeQuotaReport, Error>] = []
    func count() -> Int { total }
    func fetch() async throws -> ClaudeQuotaReport {
        total += 1
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func complete(_ value: Result<ClaudeQuotaReport, ClaudeQuotaIssue>) {
        guard !pending.isEmpty else { return }
        switch value {
        case let .success(report): pending.removeFirst().resume(returning: report)
        case let .failure(issue): pending.removeFirst().resume(throwing: issue)
        }
    }
    func finishAll() { let values = pending; pending.removeAll(); values.forEach { $0.resume(throwing: CancellationError()) } }
}

private actor ClaudeStoreTestSleeper {
    private var total = 0
    private var pending: [CheckedContinuation<Void, Never>] = []
    func count() -> Int { total }
    func sleep(_ delay: TimeInterval) async throws {
        total += 1
        await withCheckedContinuation { pending.append($0) }
    }
    func tick() { if !pending.isEmpty { pending.removeFirst().resume() } }
    func finishAll() { let values = pending; pending.removeAll(); values.forEach { $0.resume() } }
}

private final class ClaudeStoreTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 2_000_000_000)
    func read() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

@MainActor
private final class ClaudeStoreTestNotifications: QuotaNotificationServing {
    private(set) var deliveries: [String] = []
    func authorization() async -> NotificationAuthorization { .authorized }
    func requestAuthorization() async throws -> Bool { XCTFail("No real permissions in tests"); return false }
    func deliver(title: String, body: String) async throws { deliveries.append(title + " " + body) }
}
