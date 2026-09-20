import XCTest
@testable import Codex94

@MainActor
final class TokenUsageStoreTests: XCTestCase {
    func testResetClosesAndReplacesTheUnderlyingClient() async throws {
        let fixture = makeStore()
        fixture.preferences.hasChosenIdentityMode = true
        let factory = UsageClientFactory()
        let store = TokenUsageStore(preferences: fixture.preferences, fetcherFactory: { factory.make() }, resolve: { _ in
            LocatedCodex(executableURL: URL(fileURLWithPath: "/usr/bin/false"), version: "test", source: .manual)
        })
        defer { store.shutdown(); fixture.store.shutdown() }
        let first = factory.clients[0]
        store.refresh()
        try await wait { await first.count == 1 }
        store.reset()
        try await wait { first.shutdownCounter.value == 1 }
        XCTAssertEqual(factory.clients.count, 2)
        let second = factory.clients[1]
        store.refresh()
        try await wait { await second.count == 1 }
        // The new generation can finish while a cancelled old continuation is still unwinding.
        await second.complete(0, with: .success(snapshot(20, date: 2)))
        await first.complete(0, with: .failure(.unavailable))
        try await wait { !store.isRefreshing }
        XCTAssertEqual(store.snapshot?.summary.lifetimeTokens, 20)
        XCTAssertNil(store.issue)
    }

    func testResetDoesNotWaitForOldCleanupAndShutdownDrainsIt() async throws {
        let fixture = makeStore()
        fixture.preferences.hasChosenIdentityMode = true
        let gate = UsageShutdownGate()
        let factory = UsageClientFactory(initialShutdownGate: gate)
        let store = TokenUsageStore(preferences: fixture.preferences, fetcherFactory: { factory.make() }, resolve: { _ in
            LocatedCodex(executableURL: URL(fileURLWithPath: "/usr/bin/false"), version: "test", source: .manual)
        })
        defer {
            gate.release()
            store.shutdown()
            fixture.store.shutdown()
        }
        let first = factory.clients[0]
        store.refresh()
        try await wait { await first.count == 1 }
        store.reset()
        try await wait { gate.didEnter }
        XCTAssertFalse(gate.didTimeOut, "Reset must not block until the cleanup gate's safety timeout")
        XCTAssertEqual(first.completedShutdownCounter.value, 0)
        XCTAssertEqual(factory.clients.count, 2)

        let second = factory.clients[1]
        store.refresh()
        try await wait { await second.count == 1 }
        await second.complete(0, with: .success(snapshot(20, date: 2)))
        await first.complete(0, with: .success(snapshot(999, date: 1)))
        try await wait { !store.isRefreshing }
        XCTAssertEqual(store.snapshot?.summary.lifetimeTokens, 20)
        XCTAssertEqual(first.completedShutdownCounter.value, 0,
                       "The new request completes while the previous generation is still stopping")

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(50)) {
            gate.release()
        }
        store.shutdown()
        XCTAssertFalse(gate.didTimeOut)
        XCTAssertEqual(first.completedShutdownCounter.value, 1,
                       "Shutdown must not return before retired-generation cleanup completes")
        XCTAssertEqual(second.shutdownCounter.value, 1)
        XCTAssertEqual(factory.clients.count, 2, "Shutdown must not construct another client")
    }

    func testShutdownIsIdempotentWithoutCreatingAReplacementClient() async {
        let fixture = makeStore()
        defer { fixture.store.shutdown() }
        let factory = UsageClientFactory()
        var store: TokenUsageStore? = TokenUsageStore(
            preferences: fixture.preferences, fetcherFactory: { factory.make() }
        )
        let first = factory.clients[0]
        store?.shutdown()
        store?.shutdown()
        store?.reset()
        store?.refresh()
        store = nil
        XCTAssertEqual(factory.clients.count, 1)
        XCTAssertEqual(first.shutdownCounter.value, 1)
        let requestCount = await first.count
        XCTAssertEqual(requestCount, 0)
    }

    func testOnDemandCoalescingAndReplacement() async throws {
        let fixture = makeStore()
        defer { fixture.store.shutdown() }
        fixture.store.loadIfNeeded()
        XCTAssertFalse(fixture.store.isRefreshing)
        fixture.preferences.hasChosenIdentityMode = true
        fixture.store.refresh()
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count == 1 }
        await fixture.fetcher.complete(0, with: .success(snapshot(100, date: 1)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.snapshot?.summary.lifetimeTokens, 100)
        fixture.store.loadIfNeeded()
        let count = await fixture.fetcher.count
        XCTAssertEqual(count, 1)
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count == 2 }
        await fixture.fetcher.complete(1, with: .success(snapshot(75, date: 2)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.snapshot?.dailyUsageBuckets?.first?.tokens, 75,
                       "A corrected daily record replaces its predecessor; it is never added twice")
    }

    func testTransientFailureKeepsTimestampButLogoutClearsData() async throws {
        let fixture = makeStore()
        defer { fixture.store.shutdown() }
        fixture.preferences.hasChosenIdentityMode = true
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count == 1 }
        await fixture.fetcher.complete(0, with: .success(snapshot(100, date: 1)))
        try await wait { !fixture.store.isRefreshing }
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count == 2 }
        await fixture.fetcher.complete(1, with: .failure(.unavailable))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.snapshot?.fetchedAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(fixture.store.issue, .unavailable)
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count == 3 }
        await fixture.fetcher.complete(2, with: .failure(.notLoggedIn))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertEqual(fixture.store.issue, .notLoggedIn)
    }

    func testResetAndShutdownDiscardLateResponses() async throws {
        let fixture = makeStore()
        fixture.preferences.hasChosenIdentityMode = true
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count == 1 }
        fixture.store.reset()
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count == 2 }
        await fixture.fetcher.complete(0, with: .success(snapshot(999, date: 1)))
        XCTAssertNil(fixture.store.snapshot)
        XCTAssertTrue(fixture.store.isRefreshing)
        await fixture.fetcher.complete(1, with: .success(snapshot(10, date: 2)))
        try await wait { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.snapshot?.summary.lifetimeTokens, 10)
        fixture.store.refresh()
        try await wait { await fixture.fetcher.count == 3 }
        fixture.store.shutdown()
        await fixture.fetcher.complete(2, with: .success(snapshot(888, date: 3)))
        fixture.store.refresh()
        XCTAssertFalse(fixture.store.isRefreshing)
        XCTAssertNil(fixture.store.snapshot)
        let count = await fixture.fetcher.count
        XCTAssertEqual(count, 3)
    }

    private func makeStore() -> (store: TokenUsageStore, preferences: PreferencesStore, fetcher: ControlledUsageFetcher) {
        let suite = "Codex94.TokenUsageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        let fetcher = ControlledUsageFetcher()
        let store = TokenUsageStore(preferences: preferences, fetcherFactory: { fetcher }, resolve: { _ in
            LocatedCodex(executableURL: URL(fileURLWithPath: "/usr/bin/false"), version: "test", source: .manual)
        })
        return (store, preferences, fetcher)
    }

    private func snapshot(_ tokens: Int, date: TimeInterval) -> TokenUsageSnapshot {
        TokenUsageSnapshot(
            summary: TokenUsageSummary(lifetimeTokens: tokens, peakDailyTokens: tokens,
                                       longestRunningTurnSec: nil, currentStreakDays: nil, longestStreakDays: nil),
            dailyUsageBuckets: [TokenUsageDay(startDate: "2026-06-18", tokens: tokens)],
            fetchedAt: Date(timeIntervalSince1970: date)
        )
    }

    private func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for usage state")
    }
}

private actor ControlledUsageFetcher: TokenUsageFetching {
    nonisolated let shutdownCounter = UsageShutdownCounter()
    nonisolated let completedShutdownCounter = UsageShutdownCounter()
    private nonisolated let shutdownGate: UsageShutdownGate?
    private var requests: [CheckedContinuation<TokenUsageSnapshot, Error>?] = []
    var count: Int { requests.count }

    init(shutdownGate: UsageShutdownGate? = nil) {
        self.shutdownGate = shutdownGate
    }

    func fetchUsage(executable: LocatedCodex) async throws -> TokenUsageSnapshot {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }

    func complete(_ index: Int, with result: Result<TokenUsageSnapshot, TokenUsageIssue>) {
        let request = requests[index]
        requests[index] = nil
        switch result {
        case .success(let snapshot): request?.resume(returning: snapshot)
        case .failure(let issue): request?.resume(throwing: issue)
        }
    }

    nonisolated func shutdown() {
        shutdownCounter.increment()
        shutdownGate?.waitForRelease()
        completedShutdownCounter.increment()
    }
}

private final class UsageShutdownGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var entered = false
    private var released = false
    private var timedOut = false

    var didEnter: Bool { lock.withLock { entered } }
    var didTimeOut: Bool { lock.withLock { timedOut } }

    func waitForRelease() {
        lock.withLock { entered = true }
        if semaphore.wait(timeout: .now() + .seconds(2)) == .timedOut {
            lock.withLock { timedOut = true }
        }
    }

    func release() {
        let shouldRelease = lock.withLock {
            if released { return false }
            released = true
            return true
        }
        if shouldRelease { semaphore.signal() }
    }
}

private final class UsageShutdownCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class UsageClientFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ControlledUsageFetcher] = []
    private let initialShutdownGate: UsageShutdownGate?

    init(initialShutdownGate: UsageShutdownGate? = nil) {
        self.initialShutdownGate = initialShutdownGate
    }

    var clients: [ControlledUsageFetcher] { lock.withLock { values } }
    func make() -> ControlledUsageFetcher {
        lock.withLock {
            let value = ControlledUsageFetcher(shutdownGate: values.isEmpty ? initialShutdownGate : nil)
            values.append(value)
            return value
        }
    }
}
