import Foundation
import XCTest
@testable import Codex94

@MainActor
final class ClaudeOAuthMonitorTests: XCTestCase {
    func testUnavailableDefaultNeverCallsHTTPAndPassiveNeedsExplicitAdoption() async throws {
        let f = try fixture(credentialIssue: .integrationUnavailable)
        f.passive.set(passive(at: f.clock.date(), producer: "a", used: 70))
        f.monitor.start()
        try await wait { !f.monitor.state.isRefreshing }
        XCTAssertEqual(f.monitor.state.quotaIssue, .integrationUnavailable)
        XCTAssertNil(f.monitor.state.report)
        XCTAssertNotNil(f.monitor.state.pendingFallback)
        for trigger in [RefreshTrigger.manual, .popover, .systemWake, .background, .quotaReset, .automaticRetry] {
            f.monitor.refresh(trigger: trigger)
        }
        f.monitor.adoptPendingFallback()
        XCTAssertTrue(f.monitor.state.isUsingFallback)
        XCTAssertNil(f.monitor.state.report?.accountContext)
        let originalTime = f.monitor.state.report?.reportedAt
        f.clock.advance(15)
        try await tick(f)
        XCTAssertEqual(f.monitor.state.report?.reportedAt, originalTime)
        f.passive.set(passive(at: f.clock.date(), producer: "b", used: 99))
        try await tick(f)
        XCTAssertEqual(f.monitor.state.report?.windows.first?.usedPercentage, 70)
        XCTAssertEqual(f.monitor.state.pendingFallback?.windows.first?.usedPercentage, 99)
        f.clock.advance(601)
        try await tick(f)
        f.monitor.adoptPendingFallback()
        XCTAssertNil(f.monitor.state.report)
        XCTAssertFalse(f.monitor.state.isUsingFallback)
        XCTAssertEqual(awaitCounts(f.client), [0, 0])
        XCTAssertEqual(f.events.evaluations.count, 0)
    }

    func testUsagePublishesBeforeProfileAndSameVerifiedAccountKeepsNotificationBaseline() async throws {
        let f = try fixture()
        f.monitor.start()
        try await waitForRound(f, 1)
        await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 50)))
        try await wait { f.monitor.state.report != nil }
        XCTAssertTrue(f.monitor.state.identityPending)
        XCTAssertNil(f.monitor.state.report?.accountContext)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.cache.fileURL(for: accountA).path))
        XCTAssertTrue(f.events.evaluations.isEmpty)
        await f.client.finishProfile(.success(accountA))
        try await wait { !f.monitor.state.isRefreshing }
        XCTAssertEqual(f.monitor.state.report?.accountContext, accountA)
        XCTAssertNotNil(try f.cache.load(context: accountA))
        XCTAssertEqual(f.events.evaluations.count, 1)
        let resets = f.events.resetCount
        f.clock.advance(61)
        f.monitor.refresh()
        try await waitForRound(f, 2)
        await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 90)))
        try await wait { f.monitor.state.report?.windows.first?.usedPercentage == 90 }
        XCTAssertNil(f.monitor.state.report?.accountContext, "A prior identity must not label a pending new usage result")
        XCTAssertEqual(f.events.resetCount, resets)
        await f.client.finishProfile(.success(accountA))
        try await wait { !f.monitor.state.isRefreshing }
        XCTAssertEqual(f.events.resetCount, resets, "Resetting every round would suppress every threshold crossing")
        XCTAssertEqual(f.events.evaluations.count, 2)
        f.monitor.refresh(trigger: .popover)
        XCTAssertEqual(awaitCounts(f.client), [2, 2])
    }

    func testProfileFailureKeepsFreshQuotaUnverifiedWithoutCacheOrNotification() async throws {
        let f = try fixture()
        f.monitor.start()
        try await waitForRound(f, 1)
        await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 42)))
        await f.client.finishProfile(.failure(.network))
        try await wait { !f.monitor.state.isRefreshing }
        XCTAssertEqual(f.monitor.state.report?.windows.first?.usedPercentage, 42)
        XCTAssertNil(f.monitor.state.report?.accountContext)
        XCTAssertNil(f.monitor.state.quotaIssue)
        XCTAssertEqual(f.monitor.state.identityIssue, .network)
        XCTAssertFalse(f.monitor.state.identityPending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.cache.fileURL(for: accountA).path))
        XCTAssertTrue(f.events.evaluations.isEmpty)
        XCTAssertEqual(f.monitor.state.nextAutomaticRefreshAt, f.clock.date().addingTimeInterval(300))
    }

    func testSuccessfulQuotaKeepsPollingWhenProfileRejectsAuthenticationOrScope() async throws {
        for issue in [ClaudeOAuthIssue.unauthorized, .insufficientScope, .forbidden] {
            let f = try fixture()
            f.monitor.start()
            try await waitForRound(f, 1)
            // Exercise the profile-first ordering as well: a later successful
            // usage response must not inherit this endpoint's rejection.
            await f.client.finishProfile(.failure(issue))
            await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 45)))
            try await wait { !f.monitor.state.isRefreshing }
            XCTAssertNil(f.monitor.state.quotaIssue)
            XCTAssertEqual(f.monitor.state.identityIssue, issue)
            XCTAssertNil(f.monitor.state.report?.accountContext)
            XCTAssertEqual(f.monitor.state.report?.windows.first?.usedPercentage, 45)
            XCTAssertEqual(f.monitor.state.nextAutomaticRefreshAt, f.clock.date().addingTimeInterval(300))
            let recovery = await f.credentials.recoveryCounts()
            XCTAssertEqual(recovery, [0, 0])
            XCTAssertTrue(f.events.evaluations.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.cache.fileURL(for: accountA).path))
            f.clock.advance(300)
            try await tick(f)
            try await waitForRound(f, 2)
            await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 46)))
            await f.client.finishProfile(.failure(issue))
            try await wait { !f.monitor.state.isRefreshing }
            XCTAssertNil(f.monitor.state.quotaIssue)
            XCTAssertEqual(f.monitor.state.report?.windows.first?.usedPercentage, 46)
            let laterRecovery = await f.credentials.recoveryCounts()
            XCTAssertEqual(laterRecovery, [0, 0])
        }
    }

    func testCredentialChangeAndStopRejectLateResponsesBeforeAReplacementCanStart() async throws {
        let f = try fixture()
        f.monitor.start()
        try await waitForRound(f, 1)
        await f.credentials.replace(try credential(context: contextB))
        await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 99)))
        try await wait { !f.monitor.state.isRefreshing }
        XCTAssertNil(f.monitor.state.report)
        XCTAssertEqual(awaitCounts(f.client), [1, 1], "The retiring profile still owns the request slot")
        await f.client.finishProfile(.success(accountA))
        try await waitForRound(f, 2)
        await f.client.finishProfile(.success(accountB))
        await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 20)))
        try await wait { !f.monitor.state.isRefreshing }
        XCTAssertEqual(f.monitor.state.report?.accountContext, accountB)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.cache.fileURL(for: accountA).path))
        let cached = try f.cache.load(context: accountB)
        let evaluations = f.events.evaluations.count
        f.monitor.refresh()
        try await waitForRound(f, 3)
        f.monitor.stop()
        await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 98)))
        await f.client.finishProfile(.success(accountB))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertNil(f.monitor.state.report)
        XCTAssertNil(f.monitor.state.nextAutomaticRefreshAt)
        XCTAssertEqual(f.events.evaluations.count, evaluations)
        XCTAssertEqual(try f.cache.load(context: accountB), cached)
    }

    func testUnauthorizedRecoversAtMostOnceAndHonorsCredentialOwnership() async throws {
        for ownership in [ClaudeOAuthCredentialOwnership.applicationOwned, .externalReadOnly] {
            let f = try fixture(ownership: ownership)
            await f.credentials.setRecovery(try credential(context: contextB, ownership: ownership))
            f.monitor.start()
            try await waitForRound(f, 1)
            await failRound(f, issue: .unauthorized)
            try await waitForRound(f, 2)
            await failRound(f, issue: .unauthorized)
            try await wait { !f.monitor.state.isRefreshing }
            XCTAssertEqual(f.monitor.state.quotaIssue, .unauthorized)
            XCTAssertNil(f.monitor.state.nextAutomaticRefreshAt)
            let recovery = await f.credentials.recoveryCounts()
            switch ownership {
            case .applicationOwned: XCTAssertEqual(recovery, [1, 0])
            case .externalReadOnly: XCTAssertEqual(recovery, [0, 1])
            }
            f.clock.advance(1_000)
            f.monitor.refresh()
            f.monitor.handleWake()
            try await tick(f)
            XCTAssertEqual(awaitCounts(f.client), [2, 2])
        }
    }

    func testExpiredCredentialRecoversBeforeHTTPAndScopeFailureCannotBeManuallyBypassed() async throws {
        let f = try fixture(expiresAt: Date(timeIntervalSince1970: 1_999_999_999))
        await f.credentials.setRecovery(try credential(context: contextB))
        f.monitor.start()
        try await waitForRound(f, 1)
        let recovery = await f.credentials.recoveryCounts()
        XCTAssertEqual(recovery, [1, 0])
        await f.client.finishUsage(.failure(.network))
        await f.client.finishProfile(.failure(.insufficientScope))
        try await wait { !f.monitor.state.isRefreshing }
        XCTAssertNil(f.monitor.state.nextAutomaticRefreshAt, "A network error must not hide an explicit scope rejection")
        XCTAssertEqual(f.monitor.state.quotaIssue, .insufficientScope,
                       "The visible error must explain the actual reason automatic reads are suspended")
        f.monitor.refresh()
        f.monitor.credentialsDidChange() // The same rejected context is still current.
        try await wait { !f.monitor.state.isRefreshing }
        XCTAssertEqual(awaitCounts(f.client), [1, 1])
        await f.credentials.replace(try credential(context: UUID()))
        f.monitor.credentialsDidChange()
        try await waitForRound(f, 2)
        await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 40)))
        await f.client.finishProfile(.success(accountA))
        try await wait { !f.monitor.state.isRefreshing }
        XCTAssertEqual(f.monitor.state.report?.accountContext, accountA)
    }

    func testWakeCoalescesAfterLongSleepAndSkipsQuotaFreshInBothClocks() async throws {
        let f = try fixture()
        f.monitor.start()
        try await waitForRound(f, 1)
        await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 40)))
        await f.client.finishProfile(.success(accountA))
        try await wait { !f.monitor.state.isRefreshing }
        f.clock.advance(59)
        f.monitor.handleWake()
        f.monitor.refresh(trigger: .systemWake)
        f.monitor.refresh(trigger: .popover)
        try await tick(f)
        XCTAssertEqual(awaitCounts(f.client), [1, 1], "A quota younger than 60 seconds in both clocks needs no wake/open read")

        // Simulate a long suspension plus a wall-clock correction. The report
        // looks only 30 seconds old by Date, but continuous elapsed time wins.
        f.clock.advance(3_600, wall: -29)
        f.monitor.handleWake()
        f.monitor.handleWake()
        f.monitor.refresh(trigger: .popover)
        try await tick(f)
        try await waitForRound(f, 2)
        XCTAssertEqual(awaitCounts(f.client), [2, 2], "Wake, opening, and overdue timer share one request slot")
        await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 41)))
        await f.client.finishProfile(.success(accountA))
        try await wait { !f.monitor.state.isRefreshing }
        f.monitor.handleWake()
        f.monitor.refresh(trigger: .popover)
        try await tick(f)
        XCTAssertEqual(awaitCounts(f.client), [2, 2], "Completing the wake read must not replay overdue timer intervals")
    }

    func testWallClockChangesInvalidateRecentQuotaWithoutCreatingWakeStorms() async throws {
        for wallDelta in [120.0, -1.0] {
            let f = try fixture()
            f.monitor.start()
            try await waitForRound(f, 1)
            await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 50)))
            await f.client.finishProfile(.success(accountA))
            try await wait { !f.monitor.state.isRefreshing }
            // A small rollback remains inside the presentation's five-second
            // tolerance, but a negative query age must not count as fresh.
            f.clock.advance(1, wall: wallDelta)
            f.monitor.handleClockChange()
            XCTAssertEqual(awaitCounts(f.client), [1, 1], "Clock projection alone does not perform HTTP")
            f.monitor.handleWake()
            f.monitor.handleWake()
            f.monitor.refresh(trigger: .popover)
            try await waitForRound(f, 2)
            await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 51)))
            await f.client.finishProfile(.success(accountA))
            try await wait { !f.monitor.state.isRefreshing }
            f.monitor.handleWake()
            f.monitor.refresh(trigger: .popover)
            try await tick(f)
            XCTAssertEqual(awaitCounts(f.client), [2, 2])
        }
    }

    func testRateLimitKeepsTheLaterMonotonicDeadlineAcrossAllEntryPointsAndClockChanges() async throws {
        let f = try fixture()
        f.monitor.start()
        try await waitForRound(f, 1)
        await f.client.finishUsage(.failure(.rateLimited(retryNotBefore: f.clock.date().addingTimeInterval(300))))
        await f.client.finishProfile(.failure(.rateLimited(retryNotBefore: f.clock.date().addingTimeInterval(600))))
        try await wait { !f.monitor.state.isRefreshing }
        f.monitor.setInterval(60)
        XCTAssertEqual(f.monitor.state.nextAutomaticRefreshAt, f.clock.date().addingTimeInterval(600))
        f.clock.advance(100, wall: 3_600)
        f.monitor.handleClockChange()
        f.monitor.handleWake()
        f.monitor.handleWake()
        for trigger in [RefreshTrigger.manual, .popover, .background, .quotaReset, .systemWake] { f.monitor.refresh(trigger: trigger) }
        XCTAssertEqual(f.monitor.state.nextAutomaticRefreshAt, f.clock.date().addingTimeInterval(500))
        XCTAssertEqual(awaitCounts(f.client), [1, 1])
        f.monitor.stop()
        f.monitor.start(interval: 60)
        XCTAssertEqual(f.monitor.state.retryAllowedAt, f.clock.date().addingTimeInterval(500),
                       "A retained cooldown must remain visible even after transient error text was reset")
        f.clock.advance(499, wall: -600)
        f.monitor.handleClockChange()
        f.monitor.handleWake()
        f.monitor.refresh(trigger: .popover)
        f.monitor.refresh()
        XCTAssertEqual(awaitCounts(f.client), [1, 1])
        f.clock.advance(1)
        f.monitor.refresh()
        try await waitForRound(f, 2)
        await f.client.finishUsage(.success(usage(at: f.clock.date(), used: 50)))
        await f.client.finishProfile(.success(accountA))
        try await wait { !f.monitor.state.isRefreshing }
    }

    func testTransientFailuresUseOnlyTwoRecoveryAttemptsThenReturnToRegularInterval() async throws {
        let f = try fixture()
        f.monitor.start()
        try await waitForRound(f, 1)
        await failRound(f, issue: .network)
        try await wait { !f.monitor.state.isRefreshing }
        for round in 2...3 {
            f.clock.advance(60)
            try await tick(f)
            try await waitForRound(f, round)
            await failRound(f, issue: .server)
            try await wait { !f.monitor.state.isRefreshing }
        }
        XCTAssertEqual(f.monitor.state.nextAutomaticRefreshAt, f.clock.date().addingTimeInterval(300))
        f.clock.advance(299)
        try await tick(f)
        XCTAssertEqual(awaitCounts(f.client), [3, 3])
        f.clock.advance(1)
        try await tick(f)
        try await waitForRound(f, 4)
        await failRound(f, issue: .network)
        try await wait { !f.monitor.state.isRefreshing }
    }

    func testResetCoverageDoesNotReplayAfterClockRollbackOrInventExpiredFiveHourQuota() async throws {
        let f = try fixture()
        let began = f.clock.date()
        f.monitor.start()
        try await waitForRound(f, 1)
        let windows = [ClaudeOAuthWindow(kind: .fiveHour, usedPercentage: 100, resetsAt: began.addingTimeInterval(30)),
                       ClaudeOAuthWindow(kind: .weekly, usedPercentage: 40, resetsAt: began.addingTimeInterval(5_000))]
        await f.client.finishUsage(.success(.init(windows: windows, receivedAt: began)))
        await f.client.finishProfile(.success(accountA))
        try await wait { !f.monitor.state.isRefreshing }
        f.clock.advance(35)
        try await tick(f)
        try await waitForRound(f, 2)
        await f.client.finishUsage(.success(.init(windows: windows, receivedAt: f.clock.date())))
        await f.client.finishProfile(.success(accountA))
        try await wait { !f.monitor.state.isRefreshing }
        XCTAssertEqual(f.monitor.state.report?.windows.map(\.kind), [.weekly])
        f.clock.advance(10, wall: -100)
        f.monitor.handleClockChange()
        try await tick(f)
        XCTAssertEqual(awaitCounts(f.client), [2, 2])
    }

    private let contextA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let contextB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private var accountA: ClaudeOAuthAccountContext { .init(accountID: contextA, organizationID: contextA) }
    private var accountB: ClaudeOAuthAccountContext { .init(accountID: contextB, organizationID: contextA) }

    private func credential(context: UUID, ownership: ClaudeOAuthCredentialOwnership = .applicationOwned,
                            expiresAt: Date? = nil) throws -> ClaudeOAuthCredential {
        try .init(accessToken: "synthetic-only-token", contextID: context, ownership: ownership,
                  expiresAt: expiresAt, scopes: ["user:profile"])
    }
    private func usage(at date: Date, used: Double) -> ClaudeOAuthUsageSnapshot {
        .init(windows: [.init(kind: .weekly, usedPercentage: used, resetsAt: date.addingTimeInterval(5_000))], receivedAt: date)
    }
    private func passive(at date: Date, producer: String, used: Double) -> ClaudeQuotaReport {
        .init(source: .statusline, reportedAt: date, receivedAt: date,
              windows: [.init(kind: .fiveHour, usedPercentage: used, resetsAt: date.addingTimeInterval(5_000))],
              producerID: String(repeating: producer, count: 64))
    }
    private struct Fixture {
        let monitor: ClaudeOAuthMonitor
        let credentials: MonitorCredentials
        let client: MonitorClient
        let cache: ClaudeOAuthQuotaCache
        let clock: MonitorClock
        let sleeper: MonitorSleeper
        let passive: MonitorPassive
        let events: MonitorEvents
    }
    private func fixture(ownership: ClaudeOAuthCredentialOwnership = .applicationOwned,
                         expiresAt: Date? = nil, credentialIssue: ClaudeOAuthIssue? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Codex94OAuthMonitorTests-\(UUID())")
        let cache = ClaudeOAuthQuotaCache(directory: root.appendingPathComponent("cache"))
        let credentials = MonitorCredentials(try credential(context: contextA, ownership: ownership, expiresAt: expiresAt), issue: credentialIssue)
        let client = MonitorClient(), clock = MonitorClock(), sleeper = MonitorSleeper(), passive = MonitorPassive(), events = MonitorEvents()
        let monitor = ClaudeOAuthMonitor(credentials: credentials, client: client, cache: cache,
            readPassive: { passive.read() }, now: { clock.date() }, monotonicNow: { clock.uptime() },
            sleep: { try await sleeper.sleep($0) }, onChange: { state, emitted in events.states.append(state); events.events.append(contentsOf: emitted) })
        addTeardownBlock {
            await MainActor.run { monitor.stop() }
            await client.cancelAll()
            await sleeper.releaseAll()
            try? FileManager.default.removeItem(at: root)
        }
        return Fixture(monitor: monitor, credentials: credentials, client: client, cache: cache,
                       clock: clock, sleeper: sleeper, passive: passive, events: events)
    }
    private func waitForRound(_ f: Fixture, _ count: Int) async throws {
        try await wait { await f.client.counts() == [count, count] }
    }
    private func failRound(_ f: Fixture, issue: ClaudeOAuthIssue) async {
        await f.client.finishUsage(.failure(issue)); await f.client.finishProfile(.failure(issue))
    }
    private func tick(_ f: Fixture) async throws {
        try await wait { await f.sleeper.waiting() > 0 }
        let before = await f.sleeper.count()
        await f.sleeper.releaseAll()
        try await wait { await f.sleeper.count() > before }
    }
    private func awaitCounts(_ client: MonitorClient) -> [Int] {
        // Filled by the assertion sites through the nonisolated lock-backed view.
        client.observedCounts()
    }
    private func wait(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock().now.advanced(by: .seconds(3))
        while ContinuousClock().now < deadline {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Synthetic OAuth coordinator did not reach the expected state")
    }
}

private actor MonitorCredentials: ClaudeOAuthCredentialProvider {
    private var current: ClaudeOAuthCredential
    private var issue: ClaudeOAuthIssue?
    private var recovery: ClaudeOAuthCredential?
    private var renewals = 0, reloads = 0
    init(_ value: ClaudeOAuthCredential, issue: ClaudeOAuthIssue?) { current = value; self.issue = issue }
    func credential() throws -> ClaudeOAuthCredential { if let issue { throw issue }; return current }
    func replace(_ value: ClaudeOAuthCredential) { current = value; issue = nil }
    func setRecovery(_ value: ClaudeOAuthCredential) { recovery = value }
    func recoveryCounts() -> [Int] { [renewals, reloads] }
    func renewApplicationOwnedCredential(matching contextID: UUID) throws -> ClaudeOAuthCredential {
        renewals += 1
        return try recover(matching: contextID)
    }
    func reloadExternalCredential(matching contextID: UUID) throws -> ClaudeOAuthCredential {
        reloads += 1
        return try recover(matching: contextID)
    }
    private func recover(matching id: UUID) throws -> ClaudeOAuthCredential {
        guard current.contextID == id, let recovery else { throw ClaudeOAuthIssue.unauthorized }
        current = recovery; issue = nil
        return recovery
    }
}

private final class MonitorCounts: @unchecked Sendable {
    let lock = NSLock()
    var values = [0, 0]
    func increment(_ index: Int) { lock.withLock { values[index] += 1 } }
    func read() -> [Int] { lock.withLock { values } }
}
private actor MonitorClient: ClaudeOAuthUsageFetching {
    nonisolated private let requests = MonitorCounts()
    private var usage: [CheckedContinuation<ClaudeOAuthUsageSnapshot, Error>] = []
    private var profile: [CheckedContinuation<ClaudeOAuthAccountContext, Error>] = []
    func counts() -> [Int] { requests.read() }
    nonisolated func observedCounts() -> [Int] { requests.read() }
    func fetchUsage(using credential: ClaudeOAuthCredential) async throws -> ClaudeOAuthUsageSnapshot {
        requests.increment(0)
        return try await withCheckedThrowingContinuation { usage.append($0) }
    }
    func fetchProfile(using credential: ClaudeOAuthCredential) async throws -> ClaudeOAuthAccountContext {
        requests.increment(1)
        return try await withCheckedThrowingContinuation { profile.append($0) }
    }
    func finishUsage(_ result: Result<ClaudeOAuthUsageSnapshot, ClaudeOAuthIssue>) {
        guard !usage.isEmpty else { return }
        switch result { case let .success(value): usage.removeFirst().resume(returning: value)
        case let .failure(issue): usage.removeFirst().resume(throwing: issue) }
    }
    func finishProfile(_ result: Result<ClaudeOAuthAccountContext, ClaudeOAuthIssue>) {
        guard !profile.isEmpty else { return }
        switch result { case let .success(value): profile.removeFirst().resume(returning: value)
        case let .failure(issue): profile.removeFirst().resume(throwing: issue) }
    }
    func cancelAll() {
        let u = usage, p = profile; usage.removeAll(); profile.removeAll()
        u.forEach { $0.resume(throwing: CancellationError()) }; p.forEach { $0.resume(throwing: CancellationError()) }
    }
}
private actor MonitorSleeper {
    private var total = 0
    private var pending: [CheckedContinuation<Void, Never>] = []
    func waiting() -> Int { pending.count }
    func count() -> Int { total }
    func sleep(_ seconds: TimeInterval) async throws {
        total += 1
        await withCheckedContinuation { pending.append($0) }
        try Task.checkCancellation()
    }
    func releaseAll() { let values = pending; pending.removeAll(); values.forEach { $0.resume() } }
}
private final class MonitorClock: @unchecked Sendable {
    private let lock = NSLock()
    private var wall = Date(timeIntervalSince1970: 2_000_000_000)
    private var mono: TimeInterval = 1_000
    func date() -> Date { lock.withLock { wall } }
    func uptime() -> TimeInterval { lock.withLock { mono } }
    func advance(_ seconds: TimeInterval, wall wallDelta: TimeInterval? = nil) {
        lock.withLock { mono += seconds; wall = wall.addingTimeInterval(wallDelta ?? seconds) }
    }
}
private final class MonitorPassive: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ClaudeQuotaReport?
    func set(_ value: ClaudeQuotaReport?) { lock.withLock { self.value = value } }
    func read() -> ClaudeQuotaReport? { lock.withLock { value } }
}
@MainActor
private final class MonitorEvents {
    var states: [ClaudeOAuthMonitor.State] = []
    var events: [ClaudeOAuthMonitor.Event] = []
    var resetCount: Int { events.filter { $0 == .resetNotificationBaseline }.count }
    var evaluations: [ClaudeQuotaReport] { events.compactMap { if case let .evaluateNotifications(report) = $0 { return report }; return nil } }
}
