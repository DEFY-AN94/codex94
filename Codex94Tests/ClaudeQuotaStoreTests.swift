import Combine
import Darwin
import Foundation
import XCTest
@testable import Codex94

@MainActor
final class ClaudeQuotaStoreTests: XCTestCase {
    func testCLIUsageOffNeverCreatesOrCallsFetcherAndKeepsPassiveCacheReadable() async throws {
        let fixture = try fixture(cliEnabled: false)
        let payload = Data(#"{"session_id":"00000000-0000-0000-0000-000000000001","rate_limits":{"five_hour":{"used_percentage":31.5,"resets_at":2000001000}}}"#.utf8)
        try fixture.cache.capture(payload, at: fixture.clock.read())
        let original = try Data(contentsOf: fixture.cache.fileURL)
        fixture.store.start()
        XCTAssertEqual(fixture.store.source, .statusline)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 68.5)
        for trigger in [RefreshTrigger.launch, .manual, .popover, .background, .quotaReset, .automaticRetry, .preferenceChange, .systemWake] {
            fixture.store.refresh(trigger: trigger)
        }
        fixture.store.popoverWillOpen(now: fixture.clock.read().addingTimeInterval(120))
        fixture.store.handleSystemWake(now: fixture.clock.read())
        fixture.store.handleSystemClockChange(now: fixture.clock.read())
        fixture.clock.advance(1_100)
        try await poll(fixture)
        XCTAssertEqual(fixture.factoryCalls.read(), 0)
        let calls = await fixture.fetcher.count()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(fixture.store.snapshot, "An expired passive report must not invent fresh quota")
        XCTAssertNil(fixture.store.nextAutomaticRefreshAt)
        XCTAssertFalse(fixture.store.isRefreshing)
        XCTAssertEqual(try Data(contentsOf: fixture.cache.fileURL), original)
    }

    func testCLIOptionCoexistsWithPassiveDataAndDisablingItKeepsThePassiveReport() async throws {
        let fixture = try fixture()
        let payload = Data(#"{"session_id":"00000000-0000-0000-0000-000000000001","rate_limits":{"five_hour":{"used_percentage":50,"resets_at":2000010000}}}"#.utf8)
        try fixture.cache.capture(payload, at: fixture.clock.read())
        let cachedAt = fixture.clock.read()
        let original = try Data(contentsOf: fixture.cache.fileURL)
        fixture.store.start()
        XCTAssertEqual(fixture.store.source, .statusline, "Passive data is shown while the first CLI read is pending")
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 50)
        XCTAssertTrue(fixture.store.isRefreshing)
        try await wait { await fixture.fetcher.count() == 1 }
        fixture.clock.advance(1)
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 30)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.source, .cliUsage, "A strictly newer CLI result replaces the passive report")
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 70)
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count() == 2 }
        fixture.store.setCLIUsageEnabled(false)
        XCTAssertFalse(fixture.preferences.claudeCLIUsageEnabled)
        XCTAssertTrue(fixture.store.isEnabled)
        XCTAssertFalse(fixture.store.isRefreshing)
        XCTAssertNil(fixture.store.nextAutomaticRefreshAt)
        XCTAssertEqual(fixture.store.source, .statusline, "Disabling the option drops only the CLI data")
        XCTAssertEqual(fixture.store.reportedAt, cachedAt)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 50)
        try await wait { fixture.fetcher.shutdowns.read() == 1 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 99)))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fixture.store.reportedAt, cachedAt, "A retired read cannot complete into the next generation")
        XCTAssertEqual(fixture.store.source, .statusline)
        XCTAssertEqual(try Data(contentsOf: fixture.cache.fileURL), original)
        XCTAssertTrue(fixture.notifications.deliveries.isEmpty)
        fixture.store.refresh()
        let disabledCalls = await fixture.fetcher.count()
        XCTAssertEqual(disabledCalls, 2)
        fixture.store.setCLIUsageEnabled(true)
        XCTAssertEqual(fixture.store.source, .statusline, "Re-enabling the option keeps the passive report visible while it reads")
        XCTAssertNotNil(fixture.store.snapshot)
        try await wait { await fixture.fetcher.count() == 3 }
        XCTAssertEqual(fixture.factoryCalls.read(), 2)
        fixture.clock.advance(1)
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 20)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.source, .cliUsage)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 80)
    }

    func testDisablingCLIUsageWithoutPassiveCacheClearsItsPreviousReport() async throws {
        let fixture = try fixture()
        fixture.store.start()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 10)))
        try await wait { !fixture.store.isRefreshing }
        fixture.store.setCLIUsageEnabled(false)
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertNil(fixture.store.source)
        XCTAssertNil(fixture.store.reportedAt)
        XCTAssertNil(fixture.store.lastIssue)
        XCTAssertNil(fixture.store.nextAutomaticRefreshAt)
        XCTAssertEqual(fixture.store.connectionState, .idle)
        XCTAssertTrue(fixture.preferences.claudeMonitoringEnabled)
    }

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

    func testNewerPassiveReportIsShownButCannotTouchTheCLIResetWatermark() async throws {
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
        XCTAssertEqual(fixture.store.source, .statusline, "A strictly newer passive report is the shown report")
        XCTAssertEqual(fixture.store.nextAutomaticRefreshAt, began.addingTimeInterval(1_860),
                       "Passive reports never alter the CLI's own schedule or reset coverage")
        fixture.clock.advance(5)
        await fixture.fetcher.complete(.success(.init(source: .cliUsage, reportedAt: fixture.clock.read(),
                                                     receivedAt: fixture.clock.read(), windows: windows)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.source, .cliUsage, "The newer CLI reply takes over again")
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

    func testPollingKeepsTheCLIFailureWhileANewerPassiveReportIsShown() async throws {
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

        try fixture.cache.capture(passivePayload(session: 2, used: 95), at: fixture.clock.read())
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.failure(.timedOut))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.lastCLIReadIssue, .timedOut)
        let shown = fixture.store.snapshot
        fixture.clock.advance(15)
        await fixture.sleeper.tick()
        try await wait { await fixture.sleeper.count() >= 3 }
        XCTAssertEqual(fixture.store.snapshot, shown)
        XCTAssertEqual(fixture.store.source, .statusline, "The newer passive report is shown instead of the failed CLI read")
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 5)
        XCTAssertNil(fixture.store.lastIssue, "A CLI failure does not taint current passive data")
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertEqual(fixture.store.lastCLIReadIssue, .timedOut, "The CLI's own failure stays reported separately")
    }

    func testLoginFailureDropsCLIDataWhileTheNewerBridgeReportStaysVisible() async throws {
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
        XCTAssertEqual(fixture.store.source, .statusline)
        XCTAssertEqual(fixture.store.reportedAt, fixture.clock.read())
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 5)
        XCTAssertNil(fixture.store.lastIssue)
        XCTAssertEqual(fixture.store.lastCLIReadIssue, .loginRequired)
        fixture.store.setCLIUsageEnabled(false)
        XCTAssertEqual(fixture.store.source, .statusline, "Disabling the failed CLI keeps the bridge report")
        XCTAssertNil(fixture.store.lastCLIReadIssue)
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

    func testPassiveProducerChangeRequiresFrozenConfirmationWhileSelectedStreamKeepsUpdating() async throws {
        let fixture = try fixture(cliEnabled: false)
        var preferences = NotificationPreferences()
        preferences.isEnabled = true
        fixture.preferences.claudeNotifications = preferences
        try fixture.cache.capture(passivePayload(session: 1, used: 50), at: fixture.clock.read())
        fixture.store.start()
        try await wait { fixture.store.notificationController.authorization == .authorized }
        let selected = fixture.preferences.claudePassiveProducerID
        let originalDate = fixture.store.reportedAt
        fixture.clock.advance(1)
        let pendingDate = fixture.clock.read()
        try fixture.cache.capture(passivePayload(session: 2, used: 99), at: pendingDate)
        fixture.store.refresh()
        XCTAssertTrue(fixture.store.passiveReportNeedsConfirmation)
        XCTAssertEqual(fixture.store.lastIssue, .sourceChanged)
        XCTAssertEqual(fixture.store.reportedAt, originalDate)
        XCTAssertEqual(fixture.preferences.claudePassiveProducerID, selected)
        let confirmationID = try XCTUnwrap(fixture.store.pendingPassiveConfirmationID)

        fixture.clock.advance(1)
        try fixture.cache.capture(passivePayload(session: 3, used: 98), at: fixture.clock.read())
        fixture.store.refresh()
        XCTAssertEqual(fixture.store.pendingPassiveReportedAt, pendingDate, "The report shown for confirmation must stay frozen")
        fixture.clock.advance(1)
        try fixture.cache.capture(passivePayload(session: 1, used: 90), at: fixture.clock.read())
        fixture.store.refresh()
        XCTAssertEqual(fixture.store.reportedAt, fixture.clock.read(), "The selected stream must continue updating")
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 10)
        XCTAssertTrue(fixture.store.passiveReportNeedsConfirmation)
        XCTAssertEqual(fixture.store.pendingPassiveReportedAt, pendingDate)
        XCTAssertTrue(fixture.notifications.deliveries.isEmpty)

        XCTAssertEqual(fixture.store.pendingPassiveConfirmationID, confirmationID)
        fixture.store.adoptPendingPassiveReport(expectedConfirmationID: confirmationID)
        XCTAssertFalse(fixture.store.passiveReportNeedsConfirmation)
        XCTAssertNil(fixture.store.pendingPassiveConfirmationID)
        XCTAssertEqual(fixture.store.reportedAt, pendingDate)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 1,
                       "Confirmation adopts the displayed producer 2 report, not the current producer 1 cache")
        XCTAssertNotEqual(fixture.preferences.claudePassiveProducerID, selected)
        XCTAssertTrue(fixture.notifications.deliveries.isEmpty, "Adoption establishes a new baseline")
        fixture.store.refresh()
        XCTAssertTrue(fixture.store.passiveReportNeedsConfirmation, "The now different cache source needs a separate confirmation")
        XCTAssertEqual(fixture.factoryCalls.read(), 0)
    }

    func testRestartRequiresConfirmationBeforeAnotherPassiveProducerCanReplaceTheSavedSelection() throws {
        let fixture = try fixture(cliEnabled: false)
        try fixture.cache.capture(passivePayload(session: 1, used: 50), at: fixture.clock.read())
        fixture.store.start()
        let selection = try XCTUnwrap(fixture.preferences.claudePassiveProducerID)
        fixture.store.stop()
        fixture.clock.advance(20)
        try fixture.cache.capture(passivePayload(session: 2, used: 95), at: fixture.clock.read())
        let preferences = PreferencesStore(defaults: fixture.defaults)
        XCTAssertEqual(preferences.claudePassiveProducerID, selection)
        let fetcher = fixture.fetcher, counter = fixture.factoryCalls, clock = fixture.clock
        let restarted = ClaudeQuotaStore(
            preferences: preferences, cache: fixture.cache,
            installer: ClaudeStatuslineInstaller(settingsURL: fixture.directory.appendingPathComponent("settings.json"),
                cache: fixture.cache, executableURL: URL(fileURLWithPath: "/bin/echo"),
                supportDirectory: fixture.directory.appendingPathComponent("support")),
            localCache: ClaudeLocalUsageCacheReader(fileURL: fixture.localCacheURL),
            fetcherFactory: { counter.increment(); return fetcher },
            notificationController: NotificationController(service: ClaudeStoreTestNotifications()),
            now: { clock.read() }, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )
        defer { restarted.shutdown() }
        restarted.start()
        XCTAssertNil(restarted.snapshot)
        XCTAssertTrue(restarted.passiveReportNeedsConfirmation)
        XCTAssertEqual(restarted.lastIssue, .sourceChanged)
        XCTAssertEqual(preferences.claudePassiveProducerID, selection)
        let confirmationID = try XCTUnwrap(restarted.pendingPassiveConfirmationID)
        restarted.adoptPendingPassiveReport(expectedConfirmationID: confirmationID)
        XCTAssertNotNil(restarted.snapshot)
        XCTAssertNotEqual(preferences.claudePassiveProducerID, selection)
        XCTAssertEqual(PreferencesStore(defaults: fixture.defaults).claudePassiveProducerID, preferences.claudePassiveProducerID)
        XCTAssertEqual(counter.read(), 0)
    }

    func testUnknownPassiveProvenanceOnlyAuthorizesTheExplicitlyAdoptedReport() throws {
        for producer in [nil, ClaudeStatuslineParser.legacyUnknownProducerID] as [String?] {
            let fixture = try fixture(cliEnabled: false)
            let date = fixture.clock.read()
            let windows = [ClaudeQuotaWindow(kind: .fiveHour, usedPercentage: 30, resetsAt: date.addingTimeInterval(1_000))]
            let report = ClaudeQuotaReport(source: .statusline, reportedAt: date, receivedAt: date,
                                           windows: windows, producerID: producer)
            try writePassiveReport(report, cache: fixture.cache)
            fixture.store.start()
            XCTAssertNil(fixture.store.snapshot)
            XCTAssertTrue(fixture.store.passiveReportNeedsConfirmation)
            let confirmationID = try XCTUnwrap(fixture.store.pendingPassiveConfirmationID)
            fixture.store.adoptPendingPassiveReport(expectedConfirmationID: confirmationID)
            XCTAssertNotNil(fixture.store.snapshot)
            XCTAssertNil(fixture.preferences.claudePassiveProducerID, "An anonymous placeholder is never a stream binding")
            fixture.clock.advance(15)
            try writePassiveReport(.init(source: .statusline, reportedAt: date, receivedAt: fixture.clock.read(),
                                          windows: windows, producerID: producer), cache: fixture.cache)
            fixture.store.refresh()
            XCTAssertFalse(fixture.store.passiveReportNeedsConfirmation)
            XCTAssertEqual(fixture.store.reportedAt, date, "Rereading the same anonymous report must not freshen it")
            try writePassiveReport(.init(source: .statusline, reportedAt: fixture.clock.read(), receivedAt: fixture.clock.read(),
                windows: [.init(kind: .fiveHour, usedPercentage: 95, resetsAt: date.addingTimeInterval(1_000))],
                producerID: producer), cache: fixture.cache)
            fixture.store.refresh()
            XCTAssertTrue(fixture.store.passiveReportNeedsConfirmation)
            XCTAssertEqual(fixture.store.reportedAt, date)
            XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 70)
            XCTAssertEqual(fixture.factoryCalls.read(), 0)
        }
    }

    func testExpiredPendingReportCannotBeAdoptedOrRebindTheSelectedStream() throws {
        let fixture = try fixture(cliEnabled: false)
        let selected = String(repeating: "a", count: 64)
        fixture.preferences.setClaudePassiveProducerID(selected)
        try fixture.cache.capture(passivePayload(session: 2, used: 95, reset: 2_000_000_005), at: fixture.clock.read())
        fixture.store.start()
        XCTAssertTrue(fixture.store.passiveReportNeedsConfirmation)
        let confirmationID = try XCTUnwrap(fixture.store.pendingPassiveConfirmationID)
        fixture.clock.advance(6)
        fixture.store.adoptPendingPassiveReport(expectedConfirmationID: confirmationID)
        XCTAssertFalse(fixture.store.passiveReportNeedsConfirmation)
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertEqual(fixture.store.lastIssue, .staleData)
        XCTAssertEqual(fixture.preferences.claudePassiveProducerID, selected)
        XCTAssertEqual(fixture.factoryCalls.read(), 0)
    }

    func testOldConfirmationCannotAdoptAReplacementStagedDuringTheSameIdentityChangePoll() async throws {
        let f = try fixture(cliEnabled: false)
        let began = f.clock.read(), reset = began.addingTimeInterval(10_000)
        try writeLocalCache(f, fiveHourUsed: 10, fetchedAt: began, resetAt: reset)
        try f.cache.capture(passivePayload(session: 1, used: 20), at: began)
        f.store.start()
        let selectedProducer = f.preferences.claudePassiveProducerID
        f.clock.advance(1)
        let pendingTime = f.clock.read()
        try f.cache.capture(passivePayload(session: 2, used: 90), at: pendingTime)
        f.store.refresh()
        let oldConfirmation = try XCTUnwrap(f.store.pendingPassiveConfirmationID)
        // A new producer can report at exactly the same timestamp. Neither the
        // visible boolean nor its date uniquely identifies the confirmed report.
        try f.cache.capture(passivePayload(session: 3, used: 80), at: pendingTime)
        try writeLocalCache(f, fiveHourUsed: 40, fetchedAt: began, resetAt: reset,
                            account: "00000000-0000-4000-8000-000000000002")
        try await poll(f)
        let currentConfirmation = try XCTUnwrap(f.store.pendingPassiveConfirmationID)
        XCTAssertNotEqual(currentConfirmation, oldConfirmation)
        XCTAssertEqual(f.store.pendingPassiveReportedAt, pendingTime)
        XCTAssertTrue(f.store.passiveReportNeedsConfirmation)
        let currentQuota = f.store.snapshot
        f.store.adoptPendingPassiveReport(expectedConfirmationID: oldConfirmation)
        XCTAssertEqual(f.store.pendingPassiveConfirmationID, currentConfirmation)
        XCTAssertTrue(f.store.passiveReportNeedsConfirmation, "Rejecting stale confirmation must not clear the new candidate")
        XCTAssertEqual(f.store.snapshot, currentQuota)
        XCTAssertEqual(f.preferences.claudePassiveProducerID, selectedProducer)
        f.store.adoptPendingPassiveReport(expectedConfirmationID: currentConfirmation)
        XCTAssertNil(f.store.pendingPassiveConfirmationID)
        XCTAssertFalse(f.store.passiveReportNeedsConfirmation)
        XCTAssertEqual(f.store.source, .statusline)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 20)
        XCTAssertNotEqual(f.preferences.claudePassiveProducerID, selectedProducer)
        let adopted = f.store.snapshot
        f.store.adoptPendingPassiveReport(expectedConfirmationID: currentConfirmation)
        XCTAssertEqual(f.store.snapshot, adopted, "A consumed confirmation cannot be replayed")
        XCTAssertEqual(f.factoryCalls.read(), 0)
        XCTAssertTrue(f.notifications.deliveries.isEmpty)
    }

    func testStopRestartInvalidatesConfirmationEvenWhenThePendingReportIsIdentical() throws {
        let f = try fixture(cliEnabled: false)
        f.preferences.setClaudePassiveProducerID(String(repeating: "a", count: 64))
        try f.cache.capture(passivePayload(session: 1, used: 25), at: f.clock.read())
        f.store.start()
        let oldConfirmation = try XCTUnwrap(f.store.pendingPassiveConfirmationID)
        f.store.stop()
        XCTAssertNil(f.store.pendingPassiveConfirmationID)
        f.store.adoptPendingPassiveReport(expectedConfirmationID: oldConfirmation)
        XCTAssertNil(f.store.snapshot)
        f.store.start()
        let currentConfirmation = try XCTUnwrap(f.store.pendingPassiveConfirmationID)
        XCTAssertNotEqual(oldConfirmation, currentConfirmation)
        f.store.adoptPendingPassiveReport(expectedConfirmationID: oldConfirmation)
        XCTAssertNil(f.store.snapshot)
        XCTAssertEqual(f.store.pendingPassiveConfirmationID, currentConfirmation)
        f.store.adoptPendingPassiveReport(expectedConfirmationID: currentConfirmation)
        XCTAssertNotNil(f.store.snapshot)
        XCTAssertNil(f.store.pendingPassiveConfirmationID)
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

    func testLocalCacheIsThePrimarySourceAndBackupsReplaceItOnlyWhenStrictlyNewer() async throws {
        let fixture = try fixture(cliEnabled: false)
        let began = fixture.clock.read()
        try writeLocalCache(fixture, fiveHourUsed: 40, fetchedAt: began.addingTimeInterval(-100),
                            resetAt: began.addingTimeInterval(5_000))
        fixture.store.start()
        XCTAssertEqual(fixture.store.source, .localCache)
        XCTAssertEqual(fixture.store.localCacheState, .valid)
        XCTAssertEqual(fixture.store.reportedAt, began.addingTimeInterval(-100))
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 60)
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertNil(fixture.store.lastIssue)
        XCTAssertEqual(fixture.factoryCalls.read(), 0)

        try fixture.cache.capture(passivePayload(session: 1, used: 70), at: began.addingTimeInterval(-200))
        fixture.store.refresh()
        XCTAssertEqual(fixture.store.source, .localCache, "An older statusline report does not replace the cache")
        fixture.clock.advance(10)
        try fixture.cache.capture(passivePayload(session: 1, used: 80), at: fixture.clock.read())
        fixture.store.refresh()
        XCTAssertEqual(fixture.store.source, .statusline, "A strictly newer statusline report becomes the shown report")
        XCTAssertEqual(fixture.store.reportedAt, fixture.clock.read())
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 20)

        try writeLocalCache(fixture, fiveHourUsed: 50, fetchedAt: fixture.clock.read(),
                            resetAt: began.addingTimeInterval(5_000))
        fixture.store.refresh()
        XCTAssertEqual(fixture.store.source, .localCache, "Equal observation times keep the primary source")
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 50)
        fixture.clock.advance(10)
        try writeLocalCache(fixture, fiveHourUsed: 55, weeklyUsed: 10, fetchedAt: fixture.clock.read(),
                            resetAt: began.addingTimeInterval(5_000), modelLimits: [("Fable", 33)])
        try await poll(fixture)
        XCTAssertEqual(fixture.store.source, .localCache)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 45)
        XCTAssertEqual(fixture.store.snapshot?.bucket(id: "claude.model.fable")?.window(.weekly)?.preciseRemainingPercent, 67)
        XCTAssertEqual(fixture.factoryCalls.read(), 0, "Passive sources never create a CLI client")
        XCTAssertNil(fixture.store.nextAutomaticRefreshAt)
    }

    func testLocalCacheAgesIntoCachedStateAndExpiredWindowsDisappearWithoutInventingQuota() async throws {
        let fixture = try fixture(cliEnabled: false)
        let began = fixture.clock.read()
        try writeLocalCache(fixture, fiveHourUsed: 40, fetchedAt: began, resetAt: began.addingTimeInterval(7_200))
        fixture.store.start()
        XCTAssertEqual(fixture.store.connectionState, .connected)
        fixture.clock.advance(3_600)
        try await poll(fixture)
        XCTAssertEqual(fixture.store.connectionState, .connected, "One hour is still current, matching Claude Code")
        fixture.clock.advance(1)
        try await poll(fixture)
        XCTAssertEqual(fixture.store.lastIssue, .staleData)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 60,
                       "Cached data stays visible with its original time")
        XCTAssertEqual(fixture.store.reportedAt, began)
        guard case .stale = fixture.store.connectionState else { return XCTFail("Aged cache must be marked cached") }
        fixture.clock.advance(3_600)
        try await poll(fixture)
        XCTAssertNil(fixture.store.snapshot, "An expired window disappears instead of showing 100%")
        XCTAssertEqual(fixture.store.lastIssue, .noData)
        XCTAssertEqual(fixture.store.source, .localCache)
        XCTAssertEqual(fixture.store.reportedAt, began)
    }

    func testLocalCacheAccountChangeResetsTheNotificationBaseline() async throws {
        let fixture = try fixture(cliEnabled: false)
        var preferences = NotificationPreferences()
        preferences.isEnabled = true
        preferences.recoveryEnabled = true
        fixture.preferences.claudeNotifications = preferences
        let began = fixture.clock.read()
        let reset = began.addingTimeInterval(20_000)
        try writeLocalCache(fixture, fiveHourUsed: 10, fetchedAt: began, resetAt: reset)
        fixture.store.start()
        try await wait { fixture.store.notificationController.authorization == .authorized }
        XCTAssertTrue(fixture.notifications.deliveries.isEmpty, "The first report establishes a baseline")
        fixture.clock.advance(10)
        try writeLocalCache(fixture, fiveHourUsed: 95, fetchedAt: fixture.clock.read(), resetAt: reset)
        try await poll(fixture)
        try await wait { fixture.notifications.deliveries.count == 1 }
        fixture.clock.advance(10)
        try writeLocalCache(fixture, fiveHourUsed: 10, fetchedAt: fixture.clock.read(), resetAt: reset,
                            account: "00000000-0000-4000-8000-000000000002")
        try await poll(fixture)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(fixture.notifications.deliveries.count, 1,
                       "Another login's cache is a new baseline, not a recovery of the previous account")
        fixture.clock.advance(10)
        try writeLocalCache(fixture, fiveHourUsed: 95, fetchedAt: fixture.clock.read(), resetAt: reset,
                            account: "00000000-0000-4000-8000-000000000002")
        try await poll(fixture)
        try await wait { fixture.notifications.deliveries.count == 2 }
    }

    func testTierSwitchesBetweenCacheAndStatuslineKeepOneNotificationBaseline() async throws {
        let fixture = try fixture(cliEnabled: false)
        var preferences = NotificationPreferences()
        preferences.isEnabled = true
        fixture.preferences.claudeNotifications = preferences
        let began = fixture.clock.read()
        let reset = began.addingTimeInterval(20_000)
        try writeLocalCache(fixture, fiveHourUsed: 10, fetchedAt: began, resetAt: reset)
        fixture.store.start()
        try await wait { fixture.store.notificationController.authorization == .authorized }
        XCTAssertTrue(fixture.notifications.deliveries.isEmpty, "The first report establishes a baseline")
        fixture.clock.advance(10)
        try fixture.cache.capture(passivePayload(session: 1, used: 95), at: fixture.clock.read())
        fixture.store.refresh()
        XCTAssertEqual(fixture.store.source, .statusline)
        try await wait { fixture.notifications.deliveries.count == 1 }
        fixture.clock.advance(10)
        try writeLocalCache(fixture, fiveHourUsed: 96, fetchedAt: fixture.clock.read(), resetAt: reset)
        try await poll(fixture)
        XCTAssertEqual(fixture.store.source, .localCache)
        fixture.clock.advance(10)
        try fixture.cache.capture(passivePayload(session: 1, used: 97), at: fixture.clock.read())
        try await poll(fixture)
        XCTAssertEqual(fixture.store.source, .statusline)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(fixture.notifications.deliveries.count, 1,
                       "Same-account tiers share one baseline: no re-seeding and no repeated alert")
    }

    func testAutomaticCLIFailureIsShownWhileThePassiveReportIsOutOfDate() async throws {
        let fixture = try fixture()
        let began = fixture.clock.read()
        try writeLocalCache(fixture, fiveHourUsed: 40, fetchedAt: began.addingTimeInterval(-7_200),
                            resetAt: began.addingTimeInterval(50_000))
        fixture.store.start()
        XCTAssertEqual(fixture.store.source, .localCache)
        XCTAssertEqual(fixture.store.lastIssue, .staleData)
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.failure(.loginRequired))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.source, .localCache, "Rejected CLI data never hides the cache")
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 60)
        XCTAssertEqual(fixture.store.lastIssue, .loginRequired,
                       "The sign-in failure explains why nothing fresher than the old cache exists")
        guard case .stale = fixture.store.connectionState else { return XCTFail("Old cache data stays marked cached") }
        fixture.clock.advance(10)
        try writeLocalCache(fixture, fiveHourUsed: 45, fetchedAt: fixture.clock.read(),
                            resetAt: began.addingTimeInterval(50_000))
        try await poll(fixture)
        XCTAssertNil(fixture.store.lastIssue, "Current passive data keeps its own state despite the CLI failure")
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertEqual(fixture.store.lastCLIReadIssue, .loginRequired, "Services still reports the failed read")
    }

    func testFailedOneTimeReadIsReportedBesideItsButtonOnly() async throws {
        let fixture = try fixture(cliEnabled: false)
        fixture.store.start()
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertNil(fixture.store.lastIssue)
        fixture.store.readOnceWithCLI()
        try await wait { await fixture.fetcher.count() == 1 }
        await fixture.fetcher.complete(.failure(.loginRequired))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.lastCLIReadIssue, .loginRequired)
        XCTAssertNil(fixture.store.lastIssue, "A one-time failure never becomes the card's state")
        XCTAssertEqual(fixture.store.connectionState, .idle)
        try await wait { fixture.fetcher.shutdowns.read() == 1 }
        fixture.store.readOnceWithCLI()
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.success(.init(source: .statusline, reportedAt: fixture.clock.read(),
                                                     receivedAt: fixture.clock.read(), windows: [])))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.lastCLIReadIssue, .invalidData)
        XCTAssertNil(fixture.store.lastIssue)
        XCTAssertEqual(fixture.store.connectionState, .idle)
    }

    func testTornCacheRewriteKeepsTheLastReportButAFileWithoutUsageDataDropsIt() async throws {
        let fixture = try fixture(cliEnabled: false)
        let began = fixture.clock.read()
        let reset = began.addingTimeInterval(50_000)
        try writeLocalCache(fixture, fiveHourUsed: 40, fetchedAt: began, resetAt: reset)
        fixture.store.start()
        XCTAssertEqual(fixture.store.localCacheState, .valid)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 60)

        try writeLocalCacheBytes(fixture, #"{"cachedUsageUtilization": {"fetchedAtMs": 1"#)
        try await poll(fixture)
        XCTAssertEqual(fixture.store.localCacheState, .invalid, "The state describes what is on disk now")
        XCTAssertEqual(fixture.store.source, .localCache, "A rewrite in progress keeps the last good report as a candidate")
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 60)
        XCTAssertNil(fixture.store.lastIssue)

        try writeLocalCacheBytes(fixture, #"{"numStartups": 3}"#)
        try await poll(fixture)
        XCTAssertEqual(fixture.store.localCacheState, .invalid)
        XCTAssertNil(fixture.store.snapshot, "A state file without usage data (for example after /logout) shows no quota")
        XCTAssertNil(fixture.store.source)
        XCTAssertNil(fixture.store.lastIssue)
        XCTAssertEqual(fixture.store.connectionState, .idle)
        try await poll(fixture)
        XCTAssertEqual(fixture.store.localCacheState, .invalid, "An unchanged file keeps its state")

        fixture.clock.advance(10)
        try writeLocalCache(fixture, fiveHourUsed: 20, fetchedAt: fixture.clock.read(), resetAt: reset)
        try await poll(fixture)
        XCTAssertEqual(fixture.store.localCacheState, .valid)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 80)
        XCTAssertEqual(fixture.store.connectionState, .connected)
    }

    func testStopForgetsTheLocalCacheReadingUntilTheNextStart() throws {
        let fixture = try fixture(cliEnabled: false)
        let began = fixture.clock.read()
        try writeLocalCache(fixture, fiveHourUsed: 40, fetchedAt: began, resetAt: began.addingTimeInterval(5_000))
        fixture.store.start()
        XCTAssertEqual(fixture.store.localCacheState, .valid)
        fixture.store.stop()
        XCTAssertEqual(fixture.store.localCacheState, .absent, "A disabled monitor publishes no cache state")
        fixture.store.start()
        XCTAssertEqual(fixture.store.localCacheState, .valid)
        XCTAssertEqual(fixture.store.source, .localCache)
    }

    func testReadOnceWithCLIRunsWithoutTheOptionAndRetiresItsClient() async throws {
        let fixture = try fixture(cliEnabled: false)
        try fixture.cache.capture(passivePayload(session: 1, used: 50), at: fixture.clock.read())
        fixture.store.start()
        XCTAssertEqual(fixture.store.source, .statusline)
        XCTAssertTrue(fixture.store.canReadOnceWithCLI)
        fixture.store.readOnceWithCLI()
        XCTAssertTrue(fixture.store.isRefreshing)
        XCTAssertFalse(fixture.store.canReadOnceWithCLI)
        XCTAssertEqual(fixture.factoryCalls.read(), 1)
        try await wait { await fixture.fetcher.count() == 1 }
        XCTAssertEqual(fixture.store.source, .statusline, "Passive data stays visible during the one-time read")
        fixture.clock.advance(1)
        await fixture.fetcher.complete(.success(report(at: fixture.clock.read(), used: 30)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.source, .cliUsage)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 70)
        XCTAssertEqual(fixture.store.lastCLIReadAt, fixture.clock.read())
        XCTAssertNil(fixture.store.lastCLIReadIssue)
        XCTAssertNil(fixture.store.nextAutomaticRefreshAt, "A one-time read does not schedule automatic CLI reads")
        XCTAssertFalse(fixture.preferences.claudeCLIUsageEnabled)
        try await wait { fixture.fetcher.shutdowns.read() == 1 }
        XCTAssertTrue(fixture.store.canReadOnceWithCLI)

        fixture.store.readOnceWithCLI()
        XCTAssertEqual(fixture.factoryCalls.read(), 2, "Each one-time read uses a fresh client")
        try await wait { await fixture.fetcher.count() == 2 }
        await fixture.fetcher.complete(.failure(.timedOut))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.lastCLIReadIssue, .timedOut)
        XCTAssertEqual(fixture.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 70,
                       "A failed one-time read keeps the previous data")
        try await wait { fixture.fetcher.shutdowns.read() == 2 }
        fixture.store.stop()
        fixture.store.readOnceWithCLI()
        XCTAssertEqual(fixture.factoryCalls.read(), 2, "A stopped monitor never launches the CLI")
    }

    func testUnreadableLocalCacheIsReportedOnlyWhenNothingElseIsShown() throws {
        let fixture = try fixture(cliEnabled: false)
        try FileManager.default.createDirectory(at: fixture.localCacheURL, withIntermediateDirectories: true)
        fixture.store.start()
        XCTAssertEqual(fixture.store.localCacheState, .unreadable)
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertEqual(fixture.store.lastIssue, .localCacheUnreadable)
        XCTAssertEqual(fixture.store.connectionState, .unavailable(.quotaUnavailable))
        try fixture.cache.capture(passivePayload(session: 1, used: 50), at: fixture.clock.read())
        fixture.store.refresh()
        XCTAssertEqual(fixture.store.source, .statusline)
        XCTAssertNil(fixture.store.lastIssue, "A readable backup hides the primary source's file problem")
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertEqual(fixture.store.localCacheState, .unreadable)
    }

    func testLostLocalIdentityQuarantinesBackupsAndRestoresOnlyANewNotificationBaseline() async throws {
        for loss in ["absent", "unreadable", "invalid"] {
            let f = try fixture(cliEnabled: false)
            var alerts = NotificationPreferences()
            alerts.isEnabled = true
            alerts.recoveryEnabled = true
            f.preferences.claudeNotifications = alerts
            let began = f.clock.read(), reset = began.addingTimeInterval(20_000)
            try writeLocalCache(f, fiveHourUsed: 10, fetchedAt: began, resetAt: reset)
            f.store.start()
            try await wait { f.store.notificationController.authorization == .authorized }
            f.clock.advance(1)
            try f.cache.capture(passivePayload(session: 1, used: 20), at: f.clock.read())
            f.store.refresh()
            XCTAssertEqual(f.store.source, .statusline)
            let savedProducer = f.preferences.claudePassiveProducerID
            try FileManager.default.removeItem(at: f.localCacheURL)
            if loss == "unreadable" {
                try FileManager.default.createDirectory(at: f.localCacheURL, withIntermediateDirectories: true)
            } else if loss == "invalid" {
                try writeLocalCacheBytes(f, #"{"numStartups": 3}"#)
            }
            try await poll(f)
            XCTAssertNil(f.store.snapshot, "Identity loss must clear the visible old account in the same poll")
            XCTAssertTrue(f.store.passiveReportNeedsConfirmation)
            XCTAssertEqual(f.preferences.claudePassiveProducerID, savedProducer)
            try await poll(f)
            XCTAssertNil(f.store.snapshot, "The unchanged old bridge cannot secretly seed the restored baseline")
            f.clock.advance(10)
            try writeLocalCache(f, fiveHourUsed: 95, fetchedAt: f.clock.read(), resetAt: reset,
                                account: "00000000-0000-4000-8000-000000000002")
            try await poll(f)
            XCTAssertEqual(f.store.source, .localCache, "The replacement generation must keep polling")
            XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 5)
            XCTAssertTrue(f.store.passiveReportNeedsConfirmation)
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertTrue(f.notifications.deliveries.isEmpty, "B's first low reading establishes a baseline, not a crossing from A")
            f.clock.advance(10)
            try writeLocalCache(f, fiveHourUsed: 10, fetchedAt: f.clock.read(), resetAt: reset,
                                account: "00000000-0000-4000-8000-000000000002")
            try await poll(f)
            try await wait { f.notifications.deliveries.count == 1 }
            XCTAssertEqual(f.factoryCalls.read(), 0)
        }
    }

    func testAccountChangeRejectsLateCLIAndOldBackupsEvenWhenNewCacheLaterExpires() async throws {
        let f = try fixture()
        let began = f.clock.read()
        try writeLocalCache(f, fiveHourUsed: 10, fetchedAt: began, resetAt: began.addingTimeInterval(10_000))
        try f.cache.capture(passivePayload(session: 1, used: 20), at: began)
        f.store.start()
        try await wait { await f.fetcher.count() == 1 }
        let producer = f.preferences.claudePassiveProducerID
        f.clock.advance(10)
        try writeLocalCache(f, fiveHourUsed: 50, fetchedAt: f.clock.read(), resetAt: began.addingTimeInterval(30),
                            account: "00000000-0000-4000-8000-000000000002")
        try await poll(f)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 50)
        XCTAssertTrue(f.store.passiveReportNeedsConfirmation)
        XCTAssertEqual(f.preferences.claudePassiveProducerID, producer)
        await f.fetcher.complete(.success(report(at: f.clock.read().addingTimeInterval(1), used: 99)))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(f.store.source, .localCache)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 50,
                       "The retired A request cannot become B's newer backup")
        f.clock.advance(21)
        try await poll(f)
        XCTAssertNil(f.store.snapshot, "Neither the old bridge nor late CLI may return when B's window expires")
        f.clock.advance(1)
        try writeLocalCache(f, fiveHourUsed: 40, fetchedAt: f.clock.read(), resetAt: began.addingTimeInterval(10_000),
                            account: "00000000-0000-4000-8000-000000000002")
        try await poll(f)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 60)
        f.store.refresh()
        try await wait { await f.fetcher.count() == 2 }
        await f.fetcher.complete(.success(report(at: f.clock.read(), used: 40)))
        try await wait { !f.store.isRefreshing }
        XCTAssertTrue(f.notifications.deliveries.isEmpty)
    }

    func testTornJSONDoesNotRetireTheCurrentAccountOrItsInFlightCLI() async throws {
        let f = try fixture()
        let began = f.clock.read()
        try writeLocalCache(f, fiveHourUsed: 40, fetchedAt: began, resetAt: began.addingTimeInterval(5_000))
        f.store.start()
        try await wait { await f.fetcher.count() == 1 }
        try writeLocalCacheBytes(f, #"{"cachedUsageUtilization": {"#)
        try await poll(f)
        XCTAssertEqual(f.store.localCacheState, .invalid)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 60)
        XCTAssertTrue(f.store.isRefreshing)
        XCTAssertEqual(f.factoryCalls.read(), 1)
        XCTAssertFalse(f.store.passiveReportNeedsConfirmation)
        f.clock.advance(1)
        await f.fetcher.complete(.success(report(at: f.clock.read(), used: 30)))
        try await wait { !f.store.isRefreshing }
        XCTAssertEqual(f.store.source, .cliUsage)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 70)
        XCTAssertEqual(f.store.lastCLIReadAt, f.clock.read())
        f.clock.advance(1)
        try writeLocalCache(f, fiveHourUsed: 35, fetchedAt: f.clock.read(), resetAt: began.addingTimeInterval(5_000),
                            account: "00000000-0000-4000-8000-000000000002")
        try await poll(f)
        XCTAssertEqual(f.store.source, .localCache)
        XCTAssertNil(f.store.lastCLIReadAt, "A's historical CLI completion must not label B's source context")
    }

    func testStopRestartCannotReassociateOldBackupsWithTheNextLocalAccount() async throws {
        let f = try fixture(cliEnabled: false)
        let began = f.clock.read()
        try writeLocalCache(f, fiveHourUsed: 10, fetchedAt: began, resetAt: began.addingTimeInterval(5_000))
        f.store.start()
        f.clock.advance(1)
        try f.cache.capture(passivePayload(session: 1, used: 95), at: f.clock.read())
        f.store.refresh()
        XCTAssertEqual(f.store.source, .statusline)
        let producer = f.preferences.claudePassiveProducerID
        f.store.stop()
        // B's valid observation is older than the old bridge, so a timestamp
        // sort alone would resurrect A after restart.
        try writeLocalCache(f, fiveHourUsed: 40, fetchedAt: began, resetAt: began.addingTimeInterval(5_000),
                            account: "00000000-0000-4000-8000-000000000002")
        f.store.start()
        XCTAssertEqual(f.store.source, .localCache)
        XCTAssertTrue(f.store.passiveReportNeedsConfirmation)
        XCTAssertEqual(f.preferences.claudePassiveProducerID, producer)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 60)
        XCTAssertEqual(f.factoryCalls.read(), 0)
    }

    func testExpiredNewerBackupFallsBackWithoutReplayingNotificationObservations() async throws {
        let f = try fixture(cliEnabled: false)
        var alerts = NotificationPreferences()
        alerts.isEnabled = true
        alerts.recoveryEnabled = true
        f.preferences.claudeNotifications = alerts
        let began = f.clock.read()
        try writeLocalCache(f, fiveHourUsed: 10, fetchedAt: began, resetAt: began.addingTimeInterval(5_000))
        f.store.start()
        try await wait { f.store.notificationController.authorization == .authorized }
        f.clock.advance(1)
        try f.cache.capture(passivePayload(session: 1, used: 95, reset: Int(began.timeIntervalSince1970 + 30)), at: f.clock.read())
        f.store.refresh()
        try await wait { f.notifications.deliveries.count == 1 }
        f.clock.advance(30)
        try await poll(f)
        XCTAssertEqual(f.store.source, .localCache)
        XCTAssertEqual(f.store.reportedAt, began, "Fallback preserves the original source time")
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 90)
        try await poll(f)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(f.notifications.deliveries.count, 1, "An old high quota is not a fresh recovery observation")
        f.clock.advance(1)
        try writeLocalCache(f, fiveHourUsed: 10, fetchedAt: f.clock.read(), resetAt: began.addingTimeInterval(5_000))
        try await poll(f)
        try await wait { f.notifications.deliveries.count == 2 }
        XCTAssertEqual(f.factoryCalls.read(), 0)
    }

    func testFutureDatedUnchangedCacheIsRecheckedAtDeadlineAndOnClockOrWake() async throws {
        for trigger in ["poll", "clock", "wake"] {
            let f = try fixture(cliEnabled: false)
            let began = f.clock.read(), future = began.addingTimeInterval(5)
            try writeLocalCache(f, fiveHourUsed: 20, fetchedAt: future, resetAt: began.addingTimeInterval(5_000))
            let bytes = try Data(contentsOf: f.localCacheURL)
            f.store.start()
            XCTAssertEqual(f.store.localCacheState, .invalid)
            XCTAssertNil(f.store.snapshot)
            f.clock.advance(4)
            f.store.handleSystemClockChange(now: f.clock.read())
            XCTAssertEqual(f.store.localCacheState, .invalid, "Five-second tolerance cannot make receivedAt precede fetchedAt")
            XCTAssertNil(f.store.snapshot)
            f.clock.advance(trigger == "poll" ? 15 : 1)
            switch trigger {
            case "clock": f.store.handleSystemClockChange(now: f.clock.read())
            case "wake": f.store.handleSystemWake(now: f.clock.read())
            default: try await poll(f)
            }
            XCTAssertEqual(f.store.localCacheState, .valid, "The identical file becomes usable after the source clock catches up")
            XCTAssertEqual(f.store.reportedAt, future)
            XCTAssertEqual(try Data(contentsOf: f.localCacheURL), bytes)
            XCTAssertEqual(f.factoryCalls.read(), 0)
        }
    }

    func testClockRollbackRevalidatesTheUnchangedFileWithoutFresheningItsTime() async throws {
        let f = try fixture(cliEnabled: false)
        let began = f.clock.read()
        try writeLocalCache(f, fiveHourUsed: 40, fetchedAt: began, resetAt: began.addingTimeInterval(5_000))
        f.store.start()
        let bytes = try Data(contentsOf: f.localCacheURL)
        f.clock.advance(-100)
        f.store.handleSystemClockChange(now: f.clock.read())
        XCTAssertEqual(f.store.localCacheState, .invalid)
        XCTAssertEqual(f.store.reportedAt, began)
        guard case .stale = f.store.connectionState else { return XCTFail("A future report is not current after rollback") }
        f.clock.advance(100)
        try await poll(f)
        XCTAssertEqual(f.store.localCacheState, .valid)
        XCTAssertEqual(f.store.connectionState, .connected)
        XCTAssertEqual(f.store.reportedAt, began)
        XCTAssertEqual(try Data(contentsOf: f.localCacheURL), bytes)
        XCTAssertEqual(f.factoryCalls.read(), 0)
    }

    func testSameTimestampValueChangeDoesNotBecomeANotificationObservation() async throws {
        let f = try fixture(cliEnabled: false)
        var alerts = NotificationPreferences()
        alerts.isEnabled = true
        f.preferences.claudeNotifications = alerts
        let began = f.clock.read(), reset = began.addingTimeInterval(5_000)
        try writeLocalCache(f, fiveHourUsed: 10, fetchedAt: began, resetAt: reset)
        f.store.start()
        try await wait { f.store.notificationController.authorization == .authorized }
        try writeLocalCache(f, fiveHourUsed: 95, fetchedAt: began, resetAt: reset)
        try await poll(f)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 5)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(f.notifications.deliveries.isEmpty)
        f.clock.advance(1)
        try writeLocalCache(f, fiveHourUsed: 95, fetchedAt: f.clock.read(), resetAt: reset)
        try await poll(f)
        try await wait { f.notifications.deliveries.count == 1 }
    }

    func testFutureDatedNewAccountClearsOldReportsBeforeItsTimeBecomesUsable() async throws {
        let f = try fixture(cliEnabled: false)
        let began = f.clock.read()
        try writeLocalCache(f, fiveHourUsed: 10, fetchedAt: began, resetAt: began.addingTimeInterval(10_000))
        try f.cache.capture(passivePayload(session: 1, used: 20), at: began)
        f.store.start()
        try writeLocalCache(f, fiveHourUsed: 95, fetchedAt: began.addingTimeInterval(60),
                            resetAt: began.addingTimeInterval(10_000), account: "00000000-0000-4000-8000-000000000002")
        try await poll(f)
        XCTAssertNil(f.store.snapshot)
        XCTAssertEqual(f.store.localCacheState, .invalid)
        XCTAssertTrue(f.store.passiveReportNeedsConfirmation)
        f.clock.advance(60)
        try await poll(f)
        XCTAssertEqual(f.store.source, .localCache)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 5)
        XCTAssertTrue(f.notifications.deliveries.isEmpty)
    }

    func testUnchangedPollsDoNotPublishButAgeAndResetBoundariesStillDo() async throws {
        let f = try fixture(cliEnabled: false)
        let began = f.clock.read()
        try writeLocalCache(f, fiveHourUsed: 40, fetchedAt: began, resetAt: began.addingTimeInterval(4_000))
        f.store.start()
        let publications = ClaudeStoreTestCounter()
        let subscription = f.store.objectWillChange.sink { publications.increment() }
        defer { subscription.cancel() }
        for _ in 0..<3 { f.clock.advance(15); try await poll(f) }
        XCTAssertEqual(publications.read(), 0, "Identical local data and projection should not invalidate the whole dashboard")
        f.clock.advance(3_556)
        try await poll(f)
        XCTAssertEqual(f.store.lastIssue, .staleData)
        let afterAge = publications.read()
        XCTAssertGreaterThan(afterAge, 0)
        try await poll(f)
        XCTAssertEqual(publications.read(), afterAge)
        f.clock.advance(400)
        try await poll(f)
        XCTAssertNil(f.store.snapshot)
        XCTAssertEqual(f.store.lastIssue, .noData)
        XCTAssertGreaterThan(publications.read(), afterAge)
    }

    private func writeLocalCacheBytes(_ fixture: Fixture, _ contents: String) throws {
        try FileManager.default.createDirectory(at: fixture.localCacheURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: fixture.localCacheURL)
        try Data(contents.utf8).write(to: fixture.localCacheURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.localCacheURL.path)
    }

    private func writeLocalCache(
        _ fixture: Fixture, fiveHourUsed: Double, weeklyUsed: Double? = nil, fetchedAt: Date, resetAt: Date,
        account: String = "00000000-0000-4000-8000-000000000001", modelLimits: [(String, Double)] = []
    ) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let reset = formatter.string(from: resetAt)
        var windows = ["\"five_hour\": {\"utilization\": \(fiveHourUsed), \"resets_at\": \"\(reset)\"}"]
        if let weeklyUsed { windows.append("\"seven_day\": {\"utilization\": \(weeklyUsed), \"resets_at\": \"\(reset)\"}") }
        let limits = modelLimits.map {
            "{\"kind\": \"weekly_scoped\", \"percent\": \($0.1), \"resets_at\": \"\(reset)\", \"scope\": {\"model\": {\"display_name\": \"\($0.0)\"}}}"
        }
        windows.append("\"limits\": [" + limits.joined(separator: ", ") + "]")
        let json = """
        {"oauthAccount": {"emailAddress": "private@example.com"}, "cachedUsageUtilization": {
          "accountUuid": "\(account)", "fetchedAtMs": \(Int64(fetchedAt.timeIntervalSince1970 * 1_000)),
          "utilization": {\(windows.joined(separator: ", "))}}}
        """
        try FileManager.default.createDirectory(at: fixture.localCacheURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: fixture.localCacheURL)
        try Data(json.utf8).write(to: fixture.localCacheURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.localCacheURL.path)
    }

    private struct Fixture {
        let directory: URL
        let store: ClaudeQuotaStore
        let preferences: PreferencesStore
        let defaults: UserDefaults
        let cache: ClaudeStatuslineCache
        let fetcher: ClaudeStoreTestFetcher
        let sleeper: ClaudeStoreTestSleeper
        let clock: ClaudeStoreTestClock
        let notifications: ClaudeStoreTestNotifications
        let factoryCalls: ClaudeStoreTestCounter
        let localCacheURL: URL
    }

    private func fixture(cliEnabled: Bool = true, fetcherFactory: (@Sendable (URL) -> any ClaudeQuotaFetching)? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "Codex94.ClaudeStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let preferences = PreferencesStore(defaults: defaults)
        preferences.claudeMonitoringEnabled = true
        preferences.claudeCLIUsageEnabled = cliEnabled
        let cache = ClaudeStatuslineCache(fileURL: root.appendingPathComponent("support/statusline-quota.json"))
        let installer = ClaudeStatuslineInstaller(settingsURL: root.appendingPathComponent("settings.json"), cache: cache,
            executableURL: URL(fileURLWithPath: "/bin/echo"), supportDirectory: root.appendingPathComponent("support"))
        let fetcher = ClaudeStoreTestFetcher()
        let sleeper = ClaudeStoreTestSleeper()
        let clock = ClaudeStoreTestClock()
        let notifications = ClaudeStoreTestNotifications()
        let factoryCalls = ClaudeStoreTestCounter()
        let factory: @Sendable () -> any ClaudeQuotaFetching = {
            factoryCalls.increment()
            if let fetcherFactory { return fetcherFactory(root) }
            return fetcher
        }
        let localCacheURL = root.appendingPathComponent("claude-config/.claude.json")
        let store = ClaudeQuotaStore(preferences: preferences, cache: cache, installer: installer,
            localCache: ClaudeLocalUsageCacheReader(fileURL: localCacheURL),
            fetcherFactory: factory, notificationController: NotificationController(service: notifications),
            now: { clock.read() }, sleep: { try await sleeper.sleep($0) })
        addTeardownBlock { [store] in
            await MainActor.run { store.shutdown() }
            await fetcher.finishAll()
            await sleeper.finishAll()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return Fixture(directory: root, store: store, preferences: preferences, defaults: defaults, cache: cache, fetcher: fetcher,
                       sleeper: sleeper, clock: clock, notifications: notifications, factoryCalls: factoryCalls,
                       localCacheURL: localCacheURL)
    }

    private func passivePayload(session: Int, used: Double, reset: Int = 2_000_010_000) -> Data {
        Data("{\"session_id\":\"00000000-0000-0000-0000-\(String(format: "%012d", session))\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":\(used),\"resets_at\":\(reset)}}}".utf8)
    }

    private func writePassiveReport(_ report: ClaudeQuotaReport, cache: ClaudeStatuslineCache) throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report))
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "report": object, "producers": [:]])
        try ClaudeLocalFile.write(data, to: cache.fileURL)
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
    nonisolated let shutdowns = ClaudeStoreTestCounter()
    private var total = 0
    private var pending: [CheckedContinuation<ClaudeQuotaReport, Error>] = []
    func count() -> Int { total }
    nonisolated func shutdown() { shutdowns.increment() }
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

private final class ClaudeStoreTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    func read() -> Int { lock.withLock { value } }
}

private actor ClaudeStoreTestSleeper {
    private var total = 0
    private var pending: [CheckedContinuation<Void, Never>] = []
    func count() -> Int { total }
    func sleep(_ delay: TimeInterval) async throws {
        total += 1
        await withCheckedContinuation { pending.append($0) }
    }
    func tick() {
        // One synthetic timer tick releases existing waits, including canceled
        // generations. A newly rearmed timer belongs to the next tick.
        let waits = pending
        pending.removeAll()
        waits.forEach { $0.resume() }
    }
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
