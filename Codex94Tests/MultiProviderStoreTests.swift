import AppKit
import Darwin
import Foundation
import XCTest
@testable import Codex94

@MainActor
final class MultiProviderStoreTests: XCTestCase {
    func testHistoricalClaudeTextDoesNotPopulateCurrentQuotaAutoOrNativeRing() async throws {
        let fixture = try makeFixture(codexEnabled: false, claudeEnabled: true, claudeCLIEnabled: false)
        let url = fixture.directory.appendingPathComponent("claude-state/.claude.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        func writeCache(expired: Bool) throws {
            let reset = formatter.string(from: referenceDate.addingTimeInterval(expired ? -1 : 3_600))
            let bytes = try JSONSerialization.data(withJSONObject: ["cachedUsageUtilization": [
                "accountUuid": "00000000-0000-4000-8000-000000000001",
                "fetchedAtMs": Int(referenceDate.addingTimeInterval(expired ? -30_000 : 0).timeIntervalSince1970 * 1_000),
                "utilization": ["five_hour": ["utilization": 24.5, "resets_at": reset],
                                "seven_day": ["utilization": 61.2, "resets_at": reset]]
            ]])
            try bytes.write(to: url, options: .atomic)
        }
        try writeCache(expired: true)
        let cacheBefore = try Data(contentsOf: url)
        fixture.preferences.language = .english
        fixture.preferences.floatingProvider = .claude
        var notifications = NotificationPreferences()
        notifications.isEnabled = true
        fixture.preferences.claudeNotifications = notifications
        fixture.store.start()
        let history = try XCTUnwrap(fixture.store.providerHistoricalReport(for: .claude))
        XCTAssertEqual(history.windows.map(\.usedPercentage), [24.5, 61.2])
        XCTAssertNil(fixture.store.providerHistoricalReport(for: .codex))
        XCTAssertNil(fixture.store.providerSnapshot(for: .claude))
        XCTAssertNil(fixture.store.providerMenuBarQuota(for: .claude))
        XCTAssertNil(fixture.store.providerDualWindowBucket(for: .claude))
        XCTAssertTrue(fixture.store.providerActiveQuotas(for: .claude).isEmpty)
        XCTAssertNil(fixture.store.floatingBucket)
        XCTAssertEqual(fixture.store.menuBarQuotaOptions(for: .claude).map(\.selection), [.automatic])

        let item = NSStatusBar.system.statusItem(withLength: 58)
        defer { NSStatusBar.system.removeStatusItem(item) }
        var imageInputs: [MenuBarStatusImageInput] = []
        let renderer = MenuBarStatusRenderer(store: fixture.store, statusItem: item, provider: .claude) { input in
            imageInputs.append(input)
            return NSImage(size: input.contentSize)
        }
        defer { renderer.shutdown() }
        renderer.update(now: referenceDate)
        XCTAssertNil(imageInputs.last?.remainingPercent, "Historical percentages cannot enter the native image input")
        XCTAssertNil(imageInputs.last?.dualWindowBucket)
        let tooltip = try XCTUnwrap(item.button?.toolTip)
        XCTAssertEqual(tooltip, item.button?.accessibilityLabel())
        XCTAssertTrue(tooltip.contains("Current quota unknown"))
        XCTAssertTrue(tooltip.contains("Last remaining 75.5%"))
        XCTAssertTrue(tooltip.contains("used 24.5%"))
        XCTAssertTrue(tooltip.contains("8 hours ago"))
        XCTAssertEqual(try Data(contentsOf: url), cacheBefore)
        XCTAssertEqual(fixture.preferences.claudeMenuBarQuotaSelection, .automatic)
        await Task.yield()
        let before = await fixture.claude.requestCount()
        XCTAssertEqual(before, 0)
        XCTAssertEqual(fixture.codex.requestCount, 0)
        XCTAssertEqual(fixture.claudeNotifications.deliveries, 0)

        try writeCache(expired: false)
        fixture.store.refreshProvider(.claude)
        renderer.update(now: referenceDate)
        XCTAssertNotNil(fixture.store.providerSnapshot(for: .claude))
        XCTAssertNil(fixture.store.providerHistoricalReport(for: .claude))
        XCTAssertNotNil(imageInputs.last?.remainingPercent)
        XCTAssertFalse(try XCTUnwrap(item.button?.toolTip).contains("Last remaining"))
        fixture.store.setMonitoringEnabled(false, for: .claude)
        XCTAssertNil(fixture.store.providerHistoricalReport(for: .claude))
        let after = await fixture.claude.requestCount()
        XCTAssertEqual(after, 0)
        XCTAssertEqual(fixture.claudeNotifications.deliveries, 0)
    }

    func testAppStoreCLIUsageSwitchRequiresOptInAndDoesNotDisableStatuslineMonitoring() async throws {
        let fixture = try makeFixture(codexEnabled: false, claudeEnabled: true, claudeCLIEnabled: false)
        fixture.store.start()
        fixture.store.refreshAll()
        let initialCalls = await fixture.claude.requestCount()
        XCTAssertEqual(initialCalls, 0)
        XCTAssertFalse(fixture.preferences.claudeCLIUsageEnabled)
        fixture.store.setClaudeCLIUsageEnabled(true)
        try await waitFor("Explicit CLI opt-in starts one isolated request") {
            await fixture.claude.requestCount() == 1
        }
        await fixture.claude.completeNext(claudeReport(used: 25.5))
        try await waitFor("The opted-in fake response is accepted") { !fixture.store.claudeStore.isRefreshing }
        XCTAssertNotNil(fixture.store.providerSnapshot(for: .claude))
        fixture.store.setClaudeCLIUsageEnabled(false)
        fixture.store.refreshProvider(.claude)
        XCTAssertNil(fixture.store.providerSnapshot(for: .claude))
        XCTAssertTrue(fixture.preferences.claudeMonitoringEnabled)
        XCTAssertTrue(fixture.store.claudeStore.isEnabled)
        XCTAssertNil(fixture.store.claudeStore.nextAutomaticRefreshAt)
        let finalCalls = await fixture.claude.requestCount()
        XCTAssertEqual(finalCalls, 1)
        XCTAssertEqual(fixture.codex.requestCount, 0)
    }

    func testDisablingCodexCancelsSchedulesAndTokenButKeepsClaudeState() async throws {
        let fixture = try makeFixture(claudeEnabled: true, cached: codexSnapshot(used: 40))
        fixture.store.start()
        try await waitFor("Both enabled providers must start independently") {
            let claudeCount = await fixture.claude.requestCount()
            return fixture.codex.requestCount == 1 && claudeCount == 1
        }
        fixture.codex.completeNext(.failure(ConnectionIssue.requestTimedOut))
        await fixture.claude.completeNext(claudeReport(used: 25.5))
        try await waitFor("Codex must wait for its retry while Claude succeeds") {
            !fixture.store.isRefreshing && fixture.store.nextRetryAt != nil
                && fixture.store.claudeStore.connectionState == .connected
        }
        fixture.store.usageStore.refresh()
        try await waitFor("Synthetic Token usage must load before disabling Codex") {
            fixture.store.usageStore.snapshot?.summary.lifetimeTokens == 42
        }
        let claudeSnapshot = fixture.store.claudeStore.snapshot
        let cache = try Data(contentsOf: fixture.cacheURL)
        XCTAssertNotNil(fixture.store.backgroundTask)
        XCTAssertNotNil(fixture.store.resetRefreshTask)

        fixture.store.setMonitoringEnabled(false, for: .codex)
        try await waitFor("Codex transport cancellation must be dispatched") { fixture.codex.cancelCount == 1 }
        XCTAssertNil(fixture.store.backgroundTask)
        XCTAssertNil(fixture.store.resetRefreshTask)
        XCTAssertNil(fixture.store.nextRetryAt)
        XCTAssertNil(fixture.store.nextBackgroundRefreshAt)
        XCTAssertNil(fixture.store.providerSnapshot(for: .codex))
        XCTAssertNil(fixture.store.usageStore.snapshot)
        XCTAssertFalse(fixture.store.usageStore.isRefreshing)
        XCTAssertEqual(fixture.store.claudeStore.snapshot, claudeSnapshot)
        XCTAssertEqual(fixture.store.providerSnapshot(for: .claude), claudeSnapshot)
        XCTAssertEqual(fixture.store.claudeStore.connectionState, .connected)
        fixture.store.usageStore.refresh()
        XCTAssertFalse(fixture.store.usageStore.isRefreshing)
        await fixture.retry.releaseAll()
        await fixture.background.releaseAll()
        try await Task.sleep(for: .milliseconds(75))
        XCTAssertEqual(fixture.codex.requestCount, 1)
        let claudeCount = await fixture.claude.requestCount()
        XCTAssertEqual(claudeCount, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.cacheURL), cache)
    }

    func testDisabledLateSuccessCannotWriteCacheNormalizeSelectionOrNotify() async throws {
        let baseline = codexSnapshot(used: 40, includeExtra: true)
        let fixture = try makeFixture(cached: baseline)
        fixture.preferences.menuBarQuotaSelection = .bucket(limitID: "extra", kind: .weekly)
        var notifications = NotificationPreferences()
        notifications.isEnabled = true
        fixture.store.setNotificationPreferences(notifications)
        fixture.store.start()
        try await waitFor("Initial Codex request must start") { fixture.codex.requestCount == 1 }
        fixture.codex.completeNext(.success(baseline))
        try await waitFor("Initial Codex baseline must finish") { !fixture.store.isRefreshing }
        let originalCache = try Data(contentsOf: fixture.cacheURL)
        XCTAssertEqual(fixture.notifications.deliveries, 0)

        fixture.store.refresh(trigger: .manual)
        try await waitFor("Second Codex response is held before disabling") { fixture.codex.requestCount == 2 }
        fixture.store.setMonitoringEnabled(false, for: .codex)
        try await waitFor("Nonterminal cancel must be requested") { fixture.codex.cancelCount == 1 }
        fixture.codex.completeNext(.success(codexSnapshot(used: 99)))
        try await Task.sleep(for: .milliseconds(75))
        XCTAssertEqual(fixture.store.snapshot, baseline)
        XCTAssertEqual(fixture.preferences.menuBarQuotaSelection, .bucket(limitID: "extra", kind: .weekly))
        XCTAssertEqual(try Data(contentsOf: fixture.cacheURL), originalCache)
        XCTAssertEqual(fixture.notifications.deliveries, 0)
        XCTAssertEqual(fixture.store.connectionState, .idle)
        XCTAssertFalse(fixture.store.hasFetchedLiveSnapshot)
        XCTAssertNil(fixture.store.lastIssue)
        XCTAssertNil(fixture.store.providerSnapshot(for: .codex))
    }

    func testRapidReenableWaitsForCancellationAndRetiringRequestBeforeNewFetch() async throws {
        let fixture = try makeFixture(holdCodexCancellation: true)
        fixture.store.start()
        try await waitFor("First Codex request must start") { fixture.codex.requestCount == 1 }
        fixture.store.setMonitoringEnabled(false, for: .codex)
        try await waitFor("Transport cancellation must reach its controlled barrier") { fixture.codex.cancelCount == 1 }
        fixture.store.setMonitoringEnabled(true, for: .codex)
        try await Task.sleep(for: .milliseconds(75))
        XCTAssertEqual(fixture.codex.requestCount, 1, "Reenable must wait for cancellation to finish")

        fixture.codex.releaseCancellation()
        try await waitFor("The nonterminal cancellation call must return") { fixture.codex.completedCancelCount == 1 }
        try await Task.sleep(for: .milliseconds(75))
        XCTAssertEqual(fixture.codex.requestCount, 1, "The old fetch must also leave the single-flight slot")
        fixture.codex.completeNext(.success(codexSnapshot(used: 95)))
        try await waitFor("Only the new generation may now start") { fixture.codex.requestCount == 2 }
        XCTAssertNil(fixture.store.snapshot, "The disabled generation cannot become the reenabled baseline")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cacheURL.path))
        let accepted = codexSnapshot(used: 25)
        fixture.codex.completeNext(.success(accepted))
        try await waitFor("Reenabled provider must accept a new response") { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.snapshot, accepted)
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertEqual(fixture.codex.maximumConcurrentRequests, 1)
        XCTAssertEqual(fixture.codex.shutdownCount, 0, "A reversible disable must not permanently shut down the client")
        XCTAssertFalse(fixture.codex.cancelWaitTimedOut)
    }

    func testProviderSingleFlightsAndStatusProjectionsRemainIndependent() async throws {
        let fixture = try makeFixture(claudeEnabled: true, cached: codexSnapshot(used: 35))
        fixture.store.start()
        try await waitFor("Each provider must have its own first request") {
            let claudeCount = await fixture.claude.requestCount()
            return fixture.codex.requestCount == 1 && claudeCount == 1
        }
        fixture.store.refreshAll()
        fixture.store.refreshProvider(.claude)
        fixture.store.refreshProvider(.codex)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fixture.codex.requestCount, 1)
        let pendingClaudeCount = await fixture.claude.requestCount()
        XCTAssertEqual(pendingClaudeCount, 1)

        await fixture.claude.completeNext(claudeReport(used: 50.1))
        try await waitFor("Claude may complete while Codex is still held") { !fixture.store.claudeStore.isRefreshing }
        XCTAssertTrue(fixture.store.isRefreshing)
        XCTAssertEqual(fixture.store.providerSnapshot(for: .claude)?.provider, .claude)
        XCTAssertEqual(fixture.store.providerSnapshot(for: .codex)?.provider, .codex)
        let remaining = try XCTUnwrap(fixture.store.providerMenuBarQuota(for: .claude)?.window.preciseRemainingPercent)
        XCTAssertEqual(remaining, 49.9, accuracy: 0.000_001)
        XCTAssertEqual(fixture.store.providerStatusPresentation(for: .claude).quotaLevel, .warning)
        XCTAssertEqual(fixture.store.providerStatusPresentation(for: .claude).connectionBadge, .none)
        XCTAssertEqual(fixture.store.providerStatusPresentation(for: .codex).connectionBadge, .refreshing)

        fixture.store.setMonitoringEnabled(false, for: .claude)
        XCTAssertNil(fixture.store.providerSnapshot(for: .claude))
        XCTAssertTrue(fixture.store.isRefreshing)
        XCTAssertEqual(fixture.codex.cancelCount, 0)
        fixture.codex.completeNext(.success(codexSnapshot(used: 30)))
        try await waitFor("Codex must still finish normally") { !fixture.store.isRefreshing }
        XCTAssertEqual(fixture.store.connectionState, .connected)
        XCTAssertFalse(fixture.store.claudeStore.isEnabled)
    }

    func testBothDisabledStartsNoQuotaProbeAndKeepsNeutralProjections() async throws {
        let fixture = try makeFixture(codexEnabled: false)
        fixture.store.start()
        fixture.store.refreshAll()
        fixture.store.popoverWillOpen()
        fixture.store.handleSystemWake()
        fixture.store.handleSystemClockChange()
        fixture.store.usageStore.refresh()
        try await Task.sleep(for: .milliseconds(75))
        XCTAssertEqual(fixture.codex.requestCount, 0)
        let claudeCount = await fixture.claude.requestCount()
        XCTAssertEqual(claudeCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("version-probed").path))
        XCTAssertNil(fixture.store.backgroundTask)
        XCTAssertNil(fixture.store.resetRefreshTask)
        XCTAssertNil(fixture.store.nextAutomaticRefreshAt)
        XCTAssertNil(fixture.store.providerSnapshot(for: .codex))
        XCTAssertNil(fixture.store.providerSnapshot(for: .claude))
        XCTAssertNil(fixture.store.floatingProvider)
        XCTAssertEqual(fixture.preferences.menuBarProviders, [])
        XCTAssertFalse(fixture.store.usageStore.isRefreshing)
    }

    func testProviderSelectionOptionsKeepMissingWindowsUnavailableAndCorrectlyNamed() throws {
        let snapshot = try XCTUnwrap(claudeReport(used: 25.5).snapshot(at: referenceDate))
        let options = ProviderQuotaSelection.options(snapshot: snapshot, preferred: .defaultBucket(.fiveHour))
        XCTAssertEqual(options.map(\.selection), [.automatic, .defaultBucket(.weekly), .defaultBucket(.fiveHour)])
        XCTAssertEqual(options.map(\.isAvailable), [true, true, false])
        XCTAssertEqual(options.last?.bucketName, "Claude")
        XCTAssertEqual(options[1].bucketName, "Claude")
        let absent = ProviderQuotaSelection.options(snapshot: nil, preferred: .defaultBucket(.weekly))
        XCTAssertEqual(absent.map(\.isAvailable), [true, false])
        XCTAssertNil(absent.last?.bucketName, "No source must not imply Codex or borrow another provider's label")
    }

    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    private func codexSnapshot(used: Int, includeExtra: Bool = false) -> QuotaSnapshot {
        let quota = QuotaWindowSnapshot(kind: .weekly, usedPercent: used, windowMinutes: 10_080,
                                       resetsAt: referenceDate.addingTimeInterval(86_400))
        var buckets = [QuotaBucketSnapshot(limitID: "default", limitName: nil, planType: "pro", windows: [quota])]
        if includeExtra {
            buckets.append(QuotaBucketSnapshot(limitID: "extra", limitName: "Synthetic model", planType: nil,
                                               windows: [QuotaWindowSnapshot(kind: .weekly, usedPercent: 20,
                                                                            windowMinutes: 10_080, resetsAt: nil)]))
        }
        return QuotaSnapshot(buckets: buckets, defaultLimitID: "default", fetchedAt: referenceDate,
                             account: nil, codex: nil)
    }

    private func claudeReport(used: Double) -> ClaudeQuotaReport {
        ClaudeQuotaReport(source: .cliUsage, reportedAt: referenceDate, receivedAt: referenceDate,
                          windows: [ClaudeQuotaWindow(kind: .weekly, usedPercentage: used,
                                                      resetsAt: referenceDate.addingTimeInterval(86_400))])
    }

    private struct Fixture {
        let directory: URL
        let cacheURL: URL
        let preferences: PreferencesStore
        let store: AppStore
        let codex: MultiProviderQuotaFetcher
        let claude: MultiProviderClaudeFetcher
        let retry: MultiProviderSleep
        let background: MultiProviderSleep
        let notifications: MultiProviderNotificationService
        let claudeNotifications: MultiProviderNotificationService
    }

    private func makeFixture(
        codexEnabled: Bool = true, claudeEnabled: Bool = false, claudeCLIEnabled: Bool = true,
        cached: QuotaSnapshot? = nil, holdCodexCancellation: Bool = false
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("Codex94MultiProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let executable = directory.appendingPathComponent("codex")
        try #"""
        #!/bin/sh
        printf '%s\n' version >> "${0%/*}/version-probed"
        printf '%s\n' 'codex-cli 9.4.0-fixture'
        """#.write(to: executable, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(executable.path, 0o700), 0)
        let suite = "Codex94MultiProviderPreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let preferences = PreferencesStore(defaults: defaults)
        preferences.codexMonitoringEnabled = codexEnabled
        preferences.claudeMonitoringEnabled = claudeEnabled
        preferences.claudeCLIUsageEnabled = claudeCLIEnabled
        preferences.hasChosenIdentityMode = true
        preferences.identityMode = .quotaOnly
        preferences.manualCodexPath = executable.path
        let cacheURL = directory.appendingPathComponent("codex-quota.json")
        let cache = SnapshotCache(fileURL: cacheURL)
        if let cached { try cache.save(cached) }
        let codex = MultiProviderQuotaFetcher(holdCancellation: holdCodexCancellation)
        let claude = MultiProviderClaudeFetcher()
        let retry = MultiProviderSleep()
        let background = MultiProviderSleep()
        let claudeSleep = MultiProviderSleep()
        let notifications = MultiProviderNotificationService()
        let claudeNotifications = MultiProviderNotificationService()
        let claudeCache = ClaudeStatuslineCache(fileURL: directory.appendingPathComponent("claude-quota.json"))
        let installer = ClaudeStatuslineInstaller(
            settingsURL: directory.appendingPathComponent("synthetic-settings.json"), cache: claudeCache,
            executableURL: executable, supportDirectory: directory.appendingPathComponent("synthetic-support")
        )
        let now = referenceDate
        let claudeStore = ClaudeQuotaStore(
            preferences: preferences, cache: claudeCache, installer: installer,
            localCache: ClaudeLocalUsageCacheReader(fileURL: directory.appendingPathComponent("claude-state/.claude.json")),
            fetcherFactory: { claude }, notificationController: NotificationController(service: claudeNotifications),
            now: { now }, sleep: { try await claudeSleep.sleep($0) }
        )
        let usage = TokenUsageStore(
            preferences: preferences, fetcherFactory: { MultiProviderUsageFetcher(now: now) },
            resolve: { _ in LocatedCodex(executableURL: executable, version: "9.4.0-fixture", source: .manual) }
        )
        let store = AppStore(
            preferences: preferences,
            launchAtLogin: LaunchAtLoginController(
                readStatus: { .notRegistered }, register: { XCTFail("No real login-item action in provider tests") },
                unregister: { XCTFail("No real login-item action in provider tests") }, stableInstall: { false }
            ),
            locator: CodexExecutableLocator(environment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"],
                                             homeDirectory: directory, bundledAppRoots: []),
            fetcher: codex, cache: cache, notificationController: NotificationController(service: notifications),
            usageStore: usage, claudeStore: claudeStore,
            retrySleep: { try await retry.sleep($0) }, backgroundSleep: { try await background.sleep($0) }
        )
        addTeardownBlock {
            codex.releaseCancellation()
            await MainActor.run { store.shutdown() }
            await claude.failAll()
            await retry.releaseAll()
            await background.releaseAll()
            await claudeSleep.releaseAll()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return Fixture(directory: directory, cacheURL: cacheURL, preferences: preferences, store: store,
                       codex: codex, claude: claude, retry: retry, background: background,
                       notifications: notifications, claudeNotifications: claudeNotifications)
    }

    private func waitFor(_ message: String, _ condition: @MainActor () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let passed = await condition()
        XCTAssertTrue(passed, message)
        if !passed { throw MultiProviderTestFailure.timedOut }
    }
}

private enum MultiProviderTestFailure: Error { case timedOut }

private final class MultiProviderQuotaFetcher: QuotaFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let cancellation = DispatchSemaphore(value: 0)
    private let holdCancellation: Bool
    private var pending: [CheckedContinuation<QuotaSnapshot, Error>] = []
    private var requests = 0
    private var active = 0
    private var maximumActive = 0
    private var cancels = 0
    private var completedCancels = 0
    private var shutdowns = 0
    private var timedOut = false
    private var stopped = false

    init(holdCancellation: Bool) { self.holdCancellation = holdCancellation }

    var requestCount: Int { lock.withLock { requests } }
    var cancelCount: Int { lock.withLock { cancels } }
    var completedCancelCount: Int { lock.withLock { completedCancels } }
    var shutdownCount: Int { lock.withLock { shutdowns } }
    var maximumConcurrentRequests: Int { lock.withLock { maximumActive } }
    var cancelWaitTimedOut: Bool { lock.withLock { timedOut } }

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if stopped { continuation.resume(throwing: ConnectionIssue.serverExited); return }
                requests += 1
                active += 1
                maximumActive = max(maximumActive, active)
                pending.append(continuation)
            }
        }
    }

    func completeNext(_ result: Result<QuotaSnapshot, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<QuotaSnapshot, Error>? in
            guard !pending.isEmpty else { return nil }
            active -= 1
            return pending.removeFirst()
        }
        continuation?.resume(with: result)
    }

    func cancelCurrentRequest() {
        lock.withLock { cancels += 1 }
        if holdCancellation, cancellation.wait(timeout: .now() + 10) == .timedOut {
            lock.withLock { timedOut = true }
        }
        lock.withLock { completedCancels += 1 }
        // Test code independently delivers the retiring request's late result.
    }

    func releaseCancellation() { cancellation.signal() }

    func shutdown() {
        releaseCancellation()
        let all = lock.withLock { () -> [CheckedContinuation<QuotaSnapshot, Error>] in
            guard !stopped else { return [] }
            stopped = true
            shutdowns += 1
            let all = pending
            pending.removeAll()
            active = 0
            return all
        }
        all.forEach { $0.resume(throwing: CancellationError()) }
    }
}

private actor MultiProviderClaudeFetcher: ClaudeQuotaFetching {
    private var requests = 0
    private var pending: [CheckedContinuation<ClaudeQuotaReport, Error>] = []
    func requestCount() -> Int { requests }
    func fetch() async throws -> ClaudeQuotaReport {
        requests += 1
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func completeNext(_ value: ClaudeQuotaReport) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: value)
    }
    func failAll() {
        let all = pending
        pending.removeAll()
        all.forEach { $0.resume(throwing: CancellationError()) }
    }
}

private actor MultiProviderSleep {
    private var pending: [CheckedContinuation<Void, Never>] = []
    func sleep(_ seconds: TimeInterval) async throws {
        await withCheckedContinuation { pending.append($0) }
    }
    func releaseAll() {
        let all = pending
        pending.removeAll()
        all.forEach { $0.resume() }
    }
}

private struct MultiProviderUsageFetcher: TokenUsageFetching {
    let now: Date
    func fetchUsage(executable: LocatedCodex) async throws -> TokenUsageSnapshot {
        TokenUsageSnapshot(summary: TokenUsageSummary(lifetimeTokens: 42), dailyUsageBuckets: [], fetchedAt: now)
    }
}

@MainActor
private final class MultiProviderNotificationService: QuotaNotificationServing {
    private(set) var deliveries = 0
    func authorization() async -> NotificationAuthorization { .authorized }
    func requestAuthorization() async throws -> Bool {
        XCTFail("Provider tests must not request system notification permission")
        return false
    }
    func deliver(title: String, body: String) async throws { deliveries += 1 }
}
