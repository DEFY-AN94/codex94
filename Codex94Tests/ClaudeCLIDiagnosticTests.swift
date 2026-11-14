import XCTest
@testable import Codex94

@MainActor
final class ClaudeCLIDiagnosticTests: XCTestCase {
    func testDiagnosticBeforeAndAfterCompletionKeepsItsOwnReadTime() async throws {
        let f = try fixture(automatic: true)
        f.store.start()
        try await settle { await f.fetcher.count == 1 }
        let firstDiagnostic = diagnostic(result: .failure, issue: .timedOut, duration: 120)
        await f.fetcher.emit(firstDiagnostic, for: 1)
        XCTAssertNil(f.store.lastCLIDiagnostic, "An unfinished read has no completion time")
        await f.fetcher.complete(1, .failure(.timedOut))
        try await settle { f.store.lastCLIDiagnostic != nil && !f.store.isRefreshing }
        let firstRecord = try XCTUnwrap(f.store.lastCLIDiagnostic)
        XCTAssertEqual(firstRecord.diagnostic, firstDiagnostic)
        XCTAssertEqual(firstRecord.completedAt, f.clock.read())

        f.clock.advance(20)
        let secondCompletion = f.clock.read()
        // This test requests a diagnostic retry explicitly; ordinary automatic
        // refresh now respects the shared failure cooldown.
        f.store.readOnceWithCLI()
        try await settle { await f.fetcher.count == 2 }
        XCTAssertEqual(f.store.lastCLIDiagnostic, firstRecord, "Retry retains a clearly previous, complete record")
        XCTAssertEqual(f.store.sourceHealth(at: f.clock.read()).operationState, .reading)
        await f.fetcher.complete(2, .success(report(at: secondCompletion)))
        try await settle { !f.store.isRefreshing }
        XCTAssertEqual(f.store.lastCLIReadAt, secondCompletion)
        XCTAssertNil(f.store.lastCLIDiagnostic, "Do not pair the old diagnostic with this completion")
        let secondDiagnostic = diagnostic(result: .success, duration: 340)
        await f.fetcher.emit(firstDiagnostic, for: 1)
        await f.fetcher.emit(secondDiagnostic, for: 2)
        try await settle { f.store.lastCLIDiagnostic?.diagnostic == secondDiagnostic }
        XCTAssertEqual(f.store.lastCLIDiagnostic?.completedAt, secondCompletion)
        XCTAssertNotEqual(f.store.lastCLIDiagnostic?.completedAt, firstRecord.completedAt)
        XCTAssertEqual(f.store.lastCLIReadIssue, nil)
    }

    func testNewReadRejectsPreviousObserverBeforeAndAfterItsResult() async throws {
        let f = try fixture(automatic: true)
        f.store.start()
        try await settle { await f.fetcher.count == 1 }
        await f.fetcher.complete(1, .success(report(at: f.clock.read())))
        try await settle { !f.store.isRefreshing }
        f.store.readOnceWithCLI()
        try await settle { await f.fetcher.count == 2 }
        await f.fetcher.emit(diagnostic(result: .failure, issue: .invalidData), for: 1)
        await f.fetcher.emit(diagnostic(result: .failure, issue: .timedOut), for: 2)
        await f.fetcher.complete(2, .failure(.timedOut))
        try await settle { !f.store.isRefreshing && f.store.lastCLIDiagnostic != nil }
        XCTAssertEqual(f.store.lastCLIDiagnostic?.diagnostic.issue, .timedOut)
        await f.fetcher.emit(diagnostic(result: .success), for: 1)
        // The third read creates an observable barrier after the old observer.
        f.store.readOnceWithCLI()
        try await settle { await f.fetcher.count == 3 }
        XCTAssertEqual(f.store.lastCLIDiagnostic?.diagnostic.issue, .timedOut)
    }

    func testStopRestartRejectsOldDiagnosticAndPublishesOnlyNewGeneration() async throws {
        let f = try fixture(automatic: true)
        f.store.start()
        try await settle { await f.fetcher.count == 1 }
        f.store.stop()
        f.store.start()
        await f.fetcher.emit(diagnostic(result: .failure, issue: .invalidData), for: 1)
        await f.fetcher.complete(1, .success(report(at: f.clock.read())))
        try await settle { !f.store.isRetiringCLI }
        let afterRestart = await f.fetcher.count
        XCTAssertEqual(afterRestart, 1, "Restart must not bypass the automatic minimum interval")
        f.store.readOnceWithCLI()
        try await settle { await f.fetcher.count == 2 }
        XCTAssertNil(f.store.lastCLIDiagnostic)
        f.clock.advance(5)
        let current = diagnostic(result: .success, duration: 100)
        await f.fetcher.complete(2, .success(report(at: f.clock.read())))
        await f.fetcher.emit(current, for: 2)
        try await settle { f.store.lastCLIDiagnostic?.diagnostic == current }
        XCTAssertEqual(f.store.lastCLIDiagnostic?.completedAt, f.clock.read())
        f.store.stop()
        XCTAssertNil(f.store.lastCLIDiagnostic)
        await f.fetcher.emit(diagnostic(result: .cancelled), for: 2)
        XCTAssertNil(f.store.sourceHealth(at: f.clock.read()).lastDiagnostic)
    }

    func testCLIOptionRetirementRejectsLateDiagnosticsInBothCleanupOrders() async throws {
        for shutdownFirst in [false, true] {
            let shutdownGate = DiagnosticShutdownGate()
            let f = try fixture(automatic: true, shutdownGate: shutdownGate)
            try writeLocalReport(f)
            f.store.start()
            f.store.readOnceWithCLI()
            try await settle { await f.fetcher.count == 1 }
            let first = diagnostic(result: .success, duration: 110)
            await f.fetcher.emit(first, for: 1)
            await f.fetcher.complete(1, .success(report(at: f.clock.read())))
            try await settle { !f.store.isRefreshing && f.store.lastCLIDiagnostic != nil }
            let firstCompletedAt = try XCTUnwrap(f.store.lastCLIDiagnostic?.completedAt)

            f.clock.advance(5)
            f.store.readOnceWithCLI()
            try await settle { await f.fetcher.count == 2 }
            f.store.setCLIUsageEnabled(false)
            try await settle { shutdownGate.started > 0 }
            XCTAssertNil(f.store.lastCLIDiagnostic, "Switching off retires the previous diagnostic context")
            XCTAssertEqual(f.store.source, .localCache)
            XCTAssertFalse(f.preferences.claudeCLIUsageEnabled)

            f.store.setCLIUsageEnabled(true)
            XCTAssertTrue(f.store.isRetiringCLI)
            XCTAssertFalse(f.store.canReadOnceWithCLI)
            let obsolete = diagnostic(result: .failure, issue: .timedOut, duration: 999)
            await f.fetcher.emit(obsolete, for: 2)
            if shutdownFirst {
                shutdownGate.allowShutdown()
                try await settle { shutdownGate.finished > 0 }
            } else {
                await f.fetcher.complete(2, .success(report(at: f.clock.read(), used: 99)))
                try await settle { await f.fetcher.hasReturned(2) }
            }
            XCTAssertTrue(f.store.isRetiringCLI, "Both shutdown and the cancelled fetch tail must finish")
            let whileRetiring = await f.fetcher.count
            XCTAssertEqual(whileRetiring, 2)
            XCTAssertNil(f.store.lastCLIDiagnostic)
            XCTAssertEqual(f.store.source, .localCache)

            if shutdownFirst {
                await f.fetcher.complete(2, .success(report(at: f.clock.read(), used: 99)))
            } else {
                shutdownGate.allowShutdown()
            }
            try await settle { !f.store.isRetiringCLI }
            let afterRetirement = await f.fetcher.count
            XCTAssertEqual(afterRetirement, 2,
                           "Fresh local quota suppresses the queued automatic intent after cleanup")
            XCTAssertNil(f.store.lastCLIDiagnostic)
            f.store.readOnceWithCLI()
            try await settle { await f.fetcher.count == 3 }
            XCTAssertNil(f.store.lastCLIDiagnostic)
            XCTAssertNil(f.store.lastCLIReadIssue)
            XCTAssertEqual(f.store.source, .localCache, "The retired result must not restore the CLI slot")

            f.clock.advance(20)
            let currentCompletedAt = f.clock.read()
            await f.fetcher.complete(3, .success(report(at: currentCompletedAt)))
            try await settle { !f.store.isRefreshing }
            XCTAssertNil(f.store.lastCLIDiagnostic, "Wait for this read's own event instead of reusing an old one")
            let current = diagnostic(result: .success, duration: 330)
            await f.fetcher.emit(obsolete, for: 2)
            await f.fetcher.emit(current, for: 3)
            try await settle { f.store.lastCLIDiagnostic?.diagnostic == current }
            XCTAssertEqual(f.store.lastCLIDiagnostic?.completedAt, currentCompletedAt)
            XCTAssertEqual(f.store.lastCLIReadAt, currentCompletedAt)
            XCTAssertNotEqual(currentCompletedAt, firstCompletedAt)
            XCTAssertTrue(f.preferences.claudeCLIUsageEnabled)
            XCTAssertFalse(shutdownGate.timedOut)
            f.store.stop()
            try await settle { !f.store.isRetiringCLI }
        }
    }

    func testPassiveRereadNeverStartsCLIOrRewritesUnchangedSchedule() async throws {
        for automatic in [false, true] {
            let f = try fixture(automatic: automatic)
            try writeLocalReport(f)
            f.store.start()
            let startupCalls = await f.fetcher.count
            XCTAssertEqual(startupCalls, 0, "Fresh local quota does not require an automatic CLI read")
            let original = try XCTUnwrap(f.store.snapshot)
            let deadline = f.store.nextAutomaticRefreshAt
            let bytes = try Data(contentsOf: f.localURL)
            f.clock.advance(5)
            for _ in 0..<5 {
                f.store.rereadPassiveSources()
                _ = f.store.sourceHealth(at: f.clock.read())
            }
            let count = await f.fetcher.count
            XCTAssertEqual(count, 0)
            XCTAssertEqual(f.store.snapshot, original)
            XCTAssertEqual(f.store.reportedAt, original.fetchedAt)
            XCTAssertEqual(f.store.nextAutomaticRefreshAt, deadline)
            XCTAssertEqual(try Data(contentsOf: f.localURL), bytes)
            XCTAssertEqual(f.preferences.claudeCLIUsageEnabled, automatic)
            XCTAssertEqual(f.notifications.deliveries, 0)
        }
    }

    func testPassiveIdentityChangeRetiresOldReadWithoutQueueingAReplacement() async throws {
        let f = try fixture(automatic: true)
        try writeLocalReport(f)
        f.store.start()
        f.store.readOnceWithCLI()
        try await settle { await f.fetcher.count == 1 }
        f.clock.advance(3)
        try writeLocalReport(f, account: "00000000-0000-4000-8000-000000000002")
        f.store.rereadPassiveSources()
        XCTAssertTrue(f.store.isRetiringCLI)
        for _ in 0..<3 { f.store.rereadPassiveSources() }
        await f.fetcher.emit(diagnostic(result: .success), for: 1)
        await f.fetcher.complete(1, .success(report(at: f.clock.read(), used: 99)))
        try await settle { !f.store.isRetiringCLI }
        XCTAssertNil(f.store.lastCLIDiagnostic)
        XCTAssertEqual(f.store.source, .localCache)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 75)
        let calls = await f.fetcher.count
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(f.store.nextAutomaticRefreshAt,
                       f.clock.read().addingTimeInterval(f.preferences.claudeRefreshInterval.seconds))
    }

    func testPassiveIdentityChangeWithAutomaticCLIOffClearsDiagnosticWithoutReading() async throws {
        let f = try fixture(automatic: false)
        try writeLocalReport(f)
        f.store.start()
        let startupCalls = await f.fetcher.count
        XCTAssertEqual(startupCalls, 0)
        XCTAssertNil(f.store.nextAutomaticRefreshAt)

        // An explicit read establishes a real diagnostic to invalidate, without
        // enabling automatic reads or leaving a background client behind.
        f.store.readOnceWithCLI()
        try await settle { await f.fetcher.count == 1 }
        await f.fetcher.emit(diagnostic(result: .success), for: 1)
        await f.fetcher.complete(1, .success(report(at: f.clock.read())))
        try await settle { !f.store.isRefreshing && !f.store.isRetiringCLI && f.store.lastCLIDiagnostic != nil }
        XCTAssertNotNil(f.store.lastCLIReadAt)
        XCTAssertFalse(f.preferences.claudeCLIUsageEnabled)

        f.clock.advance(3)
        let replacementAt = f.clock.read()
        try writeLocalReport(f, account: "00000000-0000-4000-8000-000000000002")
        for _ in 0..<3 { f.store.rereadPassiveSources() }
        let afterIdentityChange = await f.fetcher.count
        XCTAssertEqual(afterIdentityChange, 1, "Only the earlier explicit read ran; local rereads start no CLI")
        XCTAssertFalse(f.preferences.claudeCLIUsageEnabled)
        XCTAssertNil(f.store.nextAutomaticRefreshAt)
        XCTAssertNil(f.store.lastCLIDiagnostic)
        XCTAssertNil(f.store.lastCLIReadAt)
        XCTAssertNil(f.store.lastCLIReadIssue)
        XCTAssertEqual(f.store.source, .localCache)
        XCTAssertEqual(f.store.reportedAt, replacementAt)
        XCTAssertEqual(f.store.snapshot?.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 75)
        XCTAssertEqual(f.store.sourceHealth(at: replacementAt).dataState, .current)
        XCTAssertNil(f.store.sourceHealth(at: replacementAt).lastDiagnostic)
        XCTAssertEqual(f.notifications.deliveries, 0)
    }

    func testSingleReadFailureKeepsLocalHealthAndDoesNotEnableAutomaticReads() async throws {
        let f = try fixture(automatic: false)
        try writeLocalReport(f)
        f.store.start()
        f.store.readOnceWithCLI()
        f.store.readOnceWithCLI()
        try await settle { await f.fetcher.count == 1 }
        await f.fetcher.emit(diagnostic(result: .failure, issue: .loginRequired), for: 1)
        await f.fetcher.complete(1, .failure(.loginRequired))
        try await settle { !f.store.isRetiringCLI && !f.store.isRefreshing && f.store.lastCLIDiagnostic != nil }
        let health = f.store.sourceHealth(at: f.clock.read())
        XCTAssertEqual(health.dataState, .current)
        XCTAssertEqual(health.source, .localCache)
        XCTAssertEqual(health.lastReadIssue, .loginRequired)
        XCTAssertEqual(health.lastDiagnostic?.diagnostic.issue, .loginRequired)
        XCTAssertFalse(f.preferences.claudeCLIUsageEnabled)
        XCTAssertNil(f.store.nextAutomaticRefreshAt)
        let calls = await f.fetcher.count
        XCTAssertEqual(calls, 1)
    }

    func testDiagnosticExportContainsOnlyItsFixedFieldsAndBoundTime() {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        var exported = RedactedDiagnostics(generatedAt: date, connection: "idle", codexPath: "not-detected",
            codexVersion: "unknown", codexSource: "unknown", identityMode: "quotaOnly", displayMode: "auto",
            refreshMinutes: 5, lastSuccess: nil, lastError: nil)
        exported.claudeCLIRead = .init(diagnostic: diagnostic(result: .failure, issue: .timedOut, duration: 123),
                                     completedAt: date)
        let lines = exported.text.split(separator: "\n").filter { $0.hasPrefix("claudeCLI") }.map(String.init)
        let timestamp = ISO8601DateFormatter().string(from: date)
        XCTAssertEqual(lines, [
            "claudeCLIReadAt: \(timestamp)", "claudeCLIPhase: waiting_for_usage", "claudeCLIResult: failure",
            "claudeCLIIssue: timedOut", "claudeCLIUsageSent: true", "claudeCLITerminalReceived: true",
            "claudeCLIDurationMs: 123"
        ])
        XCTAssertFalse(exported.text.contains("readID"))
        XCTAssertFalse(exported.text.contains("generation"))
        exported.claudeCLIRead = nil
        XCTAssertTrue(exported.text.contains("claudeCLIPhase: none"))
    }

    func testReusedRealClientRoutesOneFinalEventToEachInvocationObserver() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeDiagnosticClient-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("synthetic-claude")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf '2.1.999 (Claude Code)\\n'; exit 0; fi
        printf 'Not logged in\\r\\n'
        /bin/sleep 30
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let common = DiagnosticEventRecorder()
        let client = ClaudeCLIUsageClient(executableURL: executable,
            runtimeDirectory: root.appendingPathComponent("runtime"), environment: [:], timeout: 2,
            diagnosticHandler: { common.append($0) })
        defer { client.shutdown() }
        for _ in 0..<2 {
            let perRead = DiagnosticEventRecorder()
            do { _ = try await client.fetch(diagnosticObserver: { perRead.append($0) }); XCTFail("Expected synthetic login screen") }
            catch { XCTAssertEqual(error as? ClaudeQuotaIssue, .loginRequired) }
            XCTAssertEqual(perRead.events.count, 1)
            XCTAssertEqual(perRead.events.first?.issue, .loginRequired)
            XCTAssertEqual(perRead.events.first?.usageSent, false)
        }
        XCTAssertEqual(common.events.count, 2, "The normal diagnostic handler still receives exactly one final event per fetch")
    }

    private func diagnostic(result: ClaudeCLIUsageDiagnostic.Result, issue: ClaudeQuotaIssue? = nil,
                            duration: Int = 50) -> ClaudeCLIUsageDiagnostic {
        .init(phase: result == .success ? .completed : .waitingForUsage, result: result,
              issue: issue, usageSent: true, terminalReceived: true, durationMilliseconds: duration)
    }

    private func report(at date: Date, used: Double = 40) -> ClaudeQuotaReport {
        .init(source: .cliUsage, reportedAt: date, receivedAt: date,
              windows: [.init(kind: .fiveHour, usedPercentage: used, resetsAt: date.addingTimeInterval(10_000))])
    }

    private struct Fixture {
        let store: ClaudeQuotaStore
        let preferences: PreferencesStore
        let fetcher: HealthDiagnosticFetcher
        let clock: HealthDiagnosticClock
        let localURL: URL
        let notifications: HealthDiagnosticNotifications
    }

    private func fixture(automatic: Bool, shutdownGate: DiagnosticShutdownGate? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeDiagnosticStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "Codex94.DiagnosticTests.\(UUID().uuidString)"
        let preferences = PreferencesStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        preferences.claudeMonitoringEnabled = true
        preferences.claudeCLIUsageEnabled = automatic
        let fetcher = HealthDiagnosticFetcher(shutdownGate: shutdownGate)
        let clock = HealthDiagnosticClock()
        let notifications = HealthDiagnosticNotifications()
        let cache = ClaudeStatuslineCache(fileURL: root.appendingPathComponent("support/statusline-quota.json"))
        let installer = ClaudeStatuslineInstaller(cache: cache, executableURL: URL(fileURLWithPath: "/bin/echo"),
            supportDirectory: root.appendingPathComponent("support"), environment: [:], homeDirectory: root)
        let localURL = ClaudeLocalUsageCacheReader.defaultFileURL(environment: [:], homeDirectory: root)
        let store = ClaudeQuotaStore(preferences: preferences, cache: cache, installer: installer,
            localCache: ClaudeLocalUsageCacheReader(fileURL: localURL), fetcherFactory: { fetcher },
            notificationController: NotificationController(service: notifications), now: { clock.read() },
            sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        addTeardownBlock {
            shutdownGate?.allowShutdown()
            await fetcher.finishAll()
            await MainActor.run { store.shutdown() }
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return Fixture(store: store, preferences: preferences, fetcher: fetcher, clock: clock,
                       localURL: localURL, notifications: notifications)
    }

    private func writeLocalReport(_ f: Fixture, account: String = "00000000-0000-4000-8000-000000000001") throws {
        let date = f.clock.read()
        let object: [String: Any] = ["cachedUsageUtilization": [
            "accountUuid": account, "fetchedAtMs": Int64(date.timeIntervalSince1970 * 1_000),
            "utilization": ["five_hour": ["utilization": 25,
                "resets_at": ISO8601DateFormatter().string(from: date.addingTimeInterval(10_000))]]
        ]]
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: f.localURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.localURL.path)
    }

    private func settle(_ predicate: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Controlled diagnostic state did not settle")
    }
}

private actor HealthDiagnosticFetcher: ClaudeQuotaFetching {
    private nonisolated let shutdownGate: DiagnosticShutdownGate?
    private(set) var count = 0
    private var returned: Set<Int> = []
    private var continuations: [Int: CheckedContinuation<ClaudeQuotaReport, Error>] = [:]
    private var observers: [Int: @Sendable (ClaudeCLIUsageDiagnostic) -> Void] = [:]
    init(shutdownGate: DiagnosticShutdownGate? = nil) { self.shutdownGate = shutdownGate }
    nonisolated func shutdown() { shutdownGate?.waitForRelease() }
    func fetch() async throws -> ClaudeQuotaReport { try await fetch(diagnosticObserver: { _ in }) }
    func fetch(diagnosticObserver: @escaping @Sendable (ClaudeCLIUsageDiagnostic) -> Void) async throws -> ClaudeQuotaReport {
        count += 1
        let index = count
        observers[index] = diagnosticObserver
        defer { returned.insert(index) }
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }
    func hasReturned(_ index: Int) -> Bool { returned.contains(index) }
    func emit(_ diagnostic: ClaudeCLIUsageDiagnostic, for index: Int) { observers[index]?(diagnostic) }
    func complete(_ index: Int, _ result: Result<ClaudeQuotaReport, ClaudeQuotaIssue>) {
        guard let continuation = continuations.removeValue(forKey: index) else { return }
        switch result {
        case let .success(value): continuation.resume(returning: value)
        case let .failure(issue): continuation.resume(throwing: issue)
        }
    }
    func finishAll() {
        let pending = Array(continuations.values)
        continuations.removeAll()
        pending.forEach { $0.resume(throwing: CancellationError()) }
    }
}

/// Controls only the fake client's synchronous shutdown half. The continuation
/// in HealthDiagnosticFetcher independently controls the fetch-return half.
private final class DiagnosticShutdownGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private var starts = 0
    private var finishes = 0
    private var expired = false
    var started: Int { condition.lock(); defer { condition.unlock() }; return starts }
    var finished: Int { condition.lock(); defer { condition.unlock() }; return finishes }
    var timedOut: Bool { condition.lock(); defer { condition.unlock() }; return expired }

    func waitForRelease() {
        condition.lock()
        defer { condition.unlock() }
        starts += 1
        let deadline = Date().addingTimeInterval(10)
        while !released {
            if !condition.wait(until: deadline) {
                expired = true
                break
            }
        }
        finishes += 1
    }

    func allowShutdown() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class HealthDiagnosticClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 2_000_000_000)
    func read() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

@MainActor
private final class HealthDiagnosticNotifications: QuotaNotificationServing {
    private(set) var deliveries = 0
    func authorization() async -> NotificationAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { XCTFail("No permission requests in fixtures"); return false }
    func deliver(title: String, body: String) async throws { deliveries += 1 }
}

private final class DiagnosticEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ClaudeCLIUsageDiagnostic] = []
    var events: [ClaudeCLIUsageDiagnostic] { lock.withLock { values } }
    func append(_ value: ClaudeCLIUsageDiagnostic) { lock.withLock { values.append(value) } }
}
