import XCTest
import UserNotifications
@testable import Codex94

final class NotificationPolicyTests: XCTestCase {
    func testFractionalQuotaCrossingsUseExactValuesBeforeFormatting() throws {
        func snapshot(_ remaining: Double, tick: TimeInterval) throws -> QuotaSnapshot {
            let window = try XCTUnwrap(QuotaWindowSnapshot(
                kind: .weekly, fractionalUsedPercent: 100 - remaining,
                windowMinutes: 10_080, resetsAt: nil
            ))
            return QuotaSnapshot(
                buckets: [QuotaBucketSnapshot(limitID: "claude", limitName: nil, planType: nil, windows: [window])],
                defaultLimitID: "claude", fetchedAt: Date(timeIntervalSince1970: 20_000 + tick),
                account: nil, codex: nil, provider: .claude
            )
        }
        var policy = QuotaNotificationPolicy()
        var preferences = NotificationPreferences()
        preferences.isEnabled = true
        preferences.recoveryEnabled = true
        XCTAssertTrue(policy.events(for: try snapshot(20.4, tick: 0), preferences: preferences).isEmpty)
        XCTAssertTrue(policy.events(for: try snapshot(20.1, tick: 1), preferences: preferences).isEmpty)
        let warning = policy.events(for: try snapshot(19.9, tick: 2), preferences: preferences)
        XCTAssertEqual(warning.map(\.kind), [.low(threshold: 20)])
        XCTAssertEqual(warning.first?.bucketName, "Claude")
        XCTAssertEqual(policy.events(for: try snapshot(20.1, tick: 3), preferences: preferences).map(\.kind), [.recovered])
        XCTAssertTrue(policy.events(for: try snapshot(10.1, tick: 4), preferences: preferences).isEmpty)
        XCTAssertEqual(policy.events(for: try snapshot(9.9, tick: 5), preferences: preferences).map(\.kind), [.low(threshold: 10)])
    }

    func testDisabledAndFirstLiveSnapshotDoNotNotify() {
        var policy = QuotaNotificationPolicy()
        var preferences = NotificationPreferences()
        XCTAssertTrue(policy.events(for: snapshot(remaining: 5), preferences: preferences).isEmpty)
        preferences.isEnabled = true
        XCTAssertTrue(policy.events(for: snapshot(remaining: 5), preferences: preferences).isEmpty)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 4), preferences: preferences).isEmpty)
    }

    func testCrossingSeveralThresholdsProducesOneUrgentEventAndDeduplicates() {
        var policy = QuotaNotificationPolicy()
        let preferences = enabled()
        XCTAssertTrue(policy.events(for: snapshot(remaining: 80), preferences: preferences).isEmpty)
        let events = policy.events(for: snapshot(remaining: 5), preferences: preferences)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .low(threshold: 10))
        XCTAssertEqual(events.first?.remainingPercent, 5)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 4), preferences: preferences).isEmpty)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 30), preferences: preferences).isEmpty)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 5), preferences: preferences).isEmpty)
    }

    func testRecoveryRequiresObservedIncreaseAndOccursOncePerCycle() {
        var policy = QuotaNotificationPolicy()
        var preferences = enabled()
        preferences.recoveryEnabled = true
        XCTAssertTrue(policy.events(for: snapshot(remaining: 5), preferences: preferences).isEmpty)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 5, fetched: 20_000), preferences: preferences).isEmpty)
        XCTAssertEqual(policy.events(for: snapshot(remaining: 90, fetched: 20_001), preferences: preferences).first?.kind, .recovered)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 5, fetched: 20_002), preferences: preferences).isEmpty)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 90, fetched: 20_003), preferences: preferences).isEmpty)
    }

    func testFreshResetRearmsThresholdsButFutureTimestampAdjustmentDoesNot() {
        var policy = QuotaNotificationPolicy()
        let preferences = enabled()
        _ = policy.events(for: snapshot(remaining: 50), preferences: preferences)
        XCTAssertEqual(policy.events(for: snapshot(remaining: 19), preferences: preferences).count, 1)
        _ = policy.events(for: snapshot(remaining: 30), preferences: preferences)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 19, reset: 21_000), preferences: preferences).isEmpty)
        _ = policy.events(for: snapshot(remaining: 100, reset: 40_000, fetched: 22_000), preferences: preferences)
        XCTAssertEqual(policy.events(for: snapshot(remaining: 19, reset: 40_000, fetched: 22_001), preferences: preferences).count, 1)
    }

    func testPreferenceChangesAndClockRollbackDoNotFabricateCrossings() {
        var policy = QuotaNotificationPolicy()
        var preferences = enabled()
        _ = policy.events(for: snapshot(remaining: 50), preferences: preferences)
        preferences.warningThreshold = 40
        XCTAssertTrue(policy.events(for: snapshot(remaining: 30), preferences: preferences).isEmpty)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 5, fetched: 9_000), preferences: preferences).isEmpty)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 4, fetched: 9_001), preferences: preferences).isEmpty)
    }

    func testAdditionalBucketsAreOptInAndWindowsAreIndependent() {
        var policy = QuotaNotificationPolicy()
        var preferences = enabled()
        _ = policy.events(for: snapshot(remaining: 50, extraRemaining: 50), preferences: preferences)
        let defaultOnly = policy.events(for: snapshot(remaining: 50, extraRemaining: 5), preferences: preferences)
        XCTAssertTrue(defaultOnly.isEmpty)
        preferences.additionalBucketIDs = ["extra"]
        _ = policy.events(for: snapshot(remaining: 50, extraRemaining: 50), preferences: preferences)
        XCTAssertEqual(policy.events(for: snapshot(remaining: 50, extraRemaining: 5), preferences: preferences).first?.bucketName, "Extra")
        preferences.fiveHourEnabled = false
        _ = policy.events(for: snapshot(remaining: 50), preferences: preferences)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 5), preferences: preferences).isEmpty)
        XCTAssertEqual(policy.events(for: snapshot(remaining: 50, kind: .weekly), preferences: preferences).count, 0)
        XCTAssertEqual(policy.events(for: snapshot(remaining: 5, kind: .weekly), preferences: preferences).count, 1)
    }

    func testReturnedWindowEstablishesNewBaseline() {
        var policy = QuotaNotificationPolicy()
        let preferences = enabled()
        _ = policy.events(for: snapshot(remaining: 50), preferences: preferences)
        _ = policy.events(for: snapshot(remaining: 50, kind: .weekly), preferences: preferences)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 5), preferences: preferences).isEmpty)
    }

    func testSubstantialUndatedRefillRearmsRemindersWithoutThresholdJitter() {
        var policy = QuotaNotificationPolicy()
        var preferences = enabled()
        preferences.recoveryEnabled = true
        _ = policy.events(for: snapshot(remaining: 50, reset: nil), preferences: preferences)
        XCTAssertEqual(policy.events(for: snapshot(remaining: 15, reset: nil), preferences: preferences).first?.kind, .low(threshold: 20))
        XCTAssertEqual(policy.events(for: snapshot(remaining: 90, reset: nil), preferences: preferences).first?.kind, .recovered)
        XCTAssertEqual(policy.events(for: snapshot(remaining: 15, reset: nil), preferences: preferences).first?.kind, .low(threshold: 20))
        XCTAssertTrue(policy.events(for: snapshot(remaining: 21, reset: nil), preferences: preferences).isEmpty)
        XCTAssertTrue(policy.events(for: snapshot(remaining: 15, reset: nil), preferences: preferences).isEmpty)
    }

    private func enabled() -> NotificationPreferences {
        var preferences = NotificationPreferences()
        preferences.isEnabled = true
        return preferences
    }

    private func snapshot(
        remaining: Int,
        kind: QuotaWindowKind = .fiveHour,
        reset: TimeInterval? = 20_000,
        fetched: TimeInterval = 10_000,
        extraRemaining: Int? = nil
    ) -> QuotaSnapshot {
        func bucket(id: String, name: String?, remaining: Int) -> QuotaBucketSnapshot {
            QuotaBucketSnapshot(limitID: id, limitName: name, planType: nil, windows: [
                QuotaWindowSnapshot(kind: kind, usedPercent: 100 - remaining, windowMinutes: nil,
                                    resetsAt: reset.map { Date(timeIntervalSince1970: $0) })
            ])
        }
        var buckets = [bucket(id: "codex", name: nil, remaining: remaining)]
        if let extraRemaining { buckets.append(bucket(id: "extra", name: "Extra", remaining: extraRemaining)) }
        return QuotaSnapshot(buckets: buckets, defaultLimitID: "codex",
                             fetchedAt: Date(timeIntervalSince1970: fetched), account: nil, codex: nil)
    }
}

@MainActor
final class NotificationControllerTests: XCTestCase {
    func testNoPermissionOrServiceAccessUntilEnabled() async {
        let service = NotificationServiceFake()
        let controller = NotificationController(service: service)
        controller.configure(enabled: false)
        controller.deliver([event], language: .english)
        await Task.yield()
        XCTAssertEqual(service.statusReads, 0)
        XCTAssertEqual(service.permissionRequests, 0)
        XCTAssertTrue(service.messages.isEmpty)
    }

    func testExplicitOptInRequestsPermissionAndCombinesEvents() async throws {
        let service = NotificationServiceFake()
        let controller = NotificationController(service: service)
        controller.configure(enabled: true, requestPermission: true)
        try await wait { controller.authorization == .authorized }
        XCTAssertEqual(service.permissionRequests, 1)
        controller.deliver([event, event], language: .english)
        try await wait { service.messages.count == 1 }
        XCTAssertTrue(service.messages[0].contains("Codex"))
        XCTAssertEqual(service.messages[0].split(separator: "\n").count, 2)
        controller.shutdown()
    }

    func testDeniedPermissionAndDisablingSuppressDelivery() async throws {
        let service = NotificationServiceFake()
        service.status = .denied
        let controller = NotificationController(service: service)
        controller.configure(enabled: true)
        try await wait { controller.authorization == .denied }
        controller.deliver([event], language: .english)
        await Task.yield()
        XCTAssertTrue(service.messages.isEmpty)
        XCTAssertEqual(service.permissionRequests, 0)
        service.status = .authorized
        controller.deliver([event], language: .english)
        controller.configure(enabled: false)
        await Task.yield()
        XCTAssertTrue(service.messages.isEmpty)
    }

    func testDeliveryFailureIsReportedWithoutRetry() async throws {
        let service = NotificationServiceFake()
        service.status = .authorized
        service.failDelivery = true
        let controller = NotificationController(service: service)
        controller.configure(enabled: true)
        try await wait { controller.authorization == .authorized }
        controller.deliver([event], language: .simplifiedChinese)
        try await wait { controller.hasIssue }
        XCTAssertEqual(service.deliveryAttempts, 1)
        controller.shutdown()
    }

    func testActivationStatusRefreshDoesNotCancelPendingReminder() async throws {
        let service = NotificationServiceFake()
        service.status = .authorized
        let controller = NotificationController(service: service)
        controller.configure(enabled: true)
        try await wait { controller.authorization == .authorized }
        service.suspendNextStatus = true
        controller.deliver([event], language: .english)
        try await wait { service.pendingStatus != nil }
        controller.refreshAuthorization()
        await Task.yield()
        service.pendingStatus?.resume(returning: .authorized)
        service.pendingStatus = nil
        try await wait { service.messages.count == 1 }
        controller.shutdown()
    }

    private var event: QuotaNotificationEvent {
        QuotaNotificationEvent(kind: .low(threshold: 20), bucketName: "Codex", window: .weekly, remainingPercent: 15)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class NotificationServiceFake: QuotaNotificationServing {
    var status: NotificationAuthorization = .notDetermined
    var statusReads = 0
    var permissionRequests = 0
    var messages: [String] = []
    var deliveryAttempts = 0
    var failDelivery = false
    var suspendNextStatus = false
    var pendingStatus: CheckedContinuation<NotificationAuthorization, Never>?

    func authorization() async -> NotificationAuthorization {
        statusReads += 1
        if suspendNextStatus {
            suspendNextStatus = false
            return await withCheckedContinuation { pendingStatus = $0 }
        }
        return status
    }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; status = .authorized; return true }
    func deliver(title: String, body: String) async throws {
        deliveryAttempts += 1
        if failDelivery { throw CocoaError(.featureUnsupported) }
        messages.append(body)
    }
}

@MainActor
final class SystemQuotaNotificationServiceTests: XCTestCase {
    func testAuthorizationMapsStatusesFromBackgroundCallbacks() async {
        let center = BackgroundNotificationCenterFake()
        let service = SystemQuotaNotificationService(center: center)
        let cases: [(Int, NotificationAuthorization)] = [
            (UNAuthorizationStatus.notDetermined.rawValue, .notDetermined),
            (UNAuthorizationStatus.denied.rawValue, .denied),
            (UNAuthorizationStatus.authorized.rawValue, .authorized),
            (UNAuthorizationStatus.provisional.rawValue, .authorized),
            (Int.max, .denied)
        ]
        for (rawStatus, expected) in cases {
            center.authorizationStatus = rawStatus
            let actual = await service.authorization()
            XCTAssertEqual(actual, expected)
            XCTAssertTrue(Thread.isMainThread, "The awaiting MainActor caller must resume on its executor")
        }
        XCTAssertEqual(center.statusReads, cases.count)
        assertBackgroundCallbacks(center, expected: Array(repeating: "authorization", count: cases.count))
    }

    func testPermissionResultsResumeFromBackgroundWithoutChangingRequestedOptions() async throws {
        let center = BackgroundNotificationCenterFake()
        let service = SystemQuotaNotificationService(center: center)
        for granted in [true, false] {
            center.permissionGranted = granted
            let actual = try await service.requestAuthorization()
            XCTAssertEqual(actual, granted)
            XCTAssertTrue(Thread.isMainThread)
        }
        XCTAssertEqual(center.requestedOptions, [[.alert], [.alert]])
        assertBackgroundCallbacks(center, expected: ["permission", "permission"])
    }

    func testPermissionErrorFromBackgroundIsPropagated() async {
        let center = BackgroundNotificationCenterFake()
        center.permissionError = CocoaError(.userCancelled)
        let service = SystemQuotaNotificationService(center: center)
        do {
            _ = try await service.requestAuthorization()
            XCTFail("Expected the asynchronous permission error")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, CocoaError.Code.userCancelled.rawValue)
            XCTAssertTrue(Thread.isMainThread)
        }
        assertBackgroundCallbacks(center, expected: ["permission"])
    }

    func testDeliverySuccessAndErrorResumeFromBackground() async throws {
        let center = BackgroundNotificationCenterFake()
        let service = SystemQuotaNotificationService(center: center)
        try await service.deliver(title: "Synthetic title", body: "Synthetic body")
        XCTAssertTrue(Thread.isMainThread)
        center.deliveryError = CocoaError(.featureUnsupported)
        do {
            try await service.deliver(title: "Second title", body: "Second body")
            XCTFail("Expected the asynchronous delivery error")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, CocoaError.Code.featureUnsupported.rawValue)
            XCTAssertTrue(Thread.isMainThread)
        }
        XCTAssertEqual(center.requests.map(\.title), ["Synthetic title", "Second title"])
        XCTAssertEqual(center.requests.map(\.body), ["Synthetic body", "Second body"])
        XCTAssertTrue(center.requests.allSatisfy(\.hasNoTrigger))
        XCTAssertEqual(Set(center.requests.map(\.identifier)).count, 2)
        assertBackgroundCallbacks(center, expected: ["delivery", "delivery"])
    }

    func testControllerOptInUsesSystemServiceWithBackgroundCenterCallbacks() async throws {
        let center = BackgroundNotificationCenterFake()
        let controller = NotificationController(service: SystemQuotaNotificationService(center: center))
        defer { controller.shutdown() }
        controller.configure(enabled: false)
        await Task.yield()
        XCTAssertEqual(center.statusReads, 0)
        XCTAssertTrue(center.requestedOptions.isEmpty)
        XCTAssertTrue(center.requests.isEmpty)

        controller.configure(enabled: true, requestPermission: true)
        try await wait { controller.authorization == .authorized }
        XCTAssertFalse(controller.isRequesting)
        XCTAssertFalse(controller.hasIssue)
        let event = QuotaNotificationEvent(kind: .low(threshold: 20), bucketName: "Claude",
                                          window: .fiveHour, remainingPercent: 10)
        controller.deliver([event], language: .english, provider: .claude)
        try await wait { center.callbackProbe.entries.count == 4 }
        XCTAssertEqual(center.statusReads, 2)
        XCTAssertEqual(center.requestedOptions, [[.alert]])
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertTrue(center.requests[0].title.contains("Claude"))
        XCTAssertTrue(center.requests[0].body.contains("10"))
        assertBackgroundCallbacks(center, expected: ["authorization", "permission", "authorization", "delivery"])
    }

    private func assertBackgroundCallbacks(_ center: BackgroundNotificationCenterFake, expected: [String],
                                           file: StaticString = #filePath, line: UInt = #line) {
        let entries = center.callbackProbe.entries
        XCTAssertEqual(entries.map(\.operation), expected, file: file, line: line)
        XCTAssertTrue(entries.allSatisfy { !$0.ranOnMainThread },
                      "The injected center must reproduce UserNotifications' off-main completion boundary",
                      file: file, line: line)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
}

/// The fake sits below SystemQuotaNotificationService's continuation bridges.
/// It never constructs a UNUserNotificationCenter or accesses system permission.
@MainActor
private final class BackgroundNotificationCenterFake: UserNotificationCenterAccess {
    struct Request {
        let title: String
        let body: String
        let identifier: String
        let hasNoTrigger: Bool
    }

    var authorizationStatus = UNAuthorizationStatus.notDetermined.rawValue
    var permissionGranted = true
    var permissionError: Error?
    var deliveryError: Error?
    private(set) var statusReads = 0
    private(set) var requestedOptions: [UNAuthorizationOptions] = []
    private(set) var requests: [Request] = []
    let callbackProbe = NotificationCallbackProbe()
    private let callbackQueue = DispatchQueue(label: "Codex94Tests.synthetic-notification-call-out")

    func getAuthorizationStatus(completion: @escaping @Sendable (Int) -> Void) {
        statusReads += 1
        let status = authorizationStatus, probe = callbackProbe
        callbackQueue.async {
            probe.record("authorization")
            completion(status)
        }
    }

    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping @Sendable (Bool, Error?) -> Void) {
        requestedOptions.append(options)
        let granted = permissionGranted, error = permissionError, probe = callbackProbe
        if error == nil { authorizationStatus = (granted ? UNAuthorizationStatus.authorized : .denied).rawValue }
        callbackQueue.async {
            probe.record("permission")
            completion(granted, error)
        }
    }

    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void) {
        requests.append(Request(title: request.content.title, body: request.content.body,
                                identifier: request.identifier, hasNoTrigger: request.trigger == nil))
        let error = deliveryError, probe = callbackProbe
        callbackQueue.async {
            probe.record("delivery")
            completion(error)
        }
    }
}

/// Records the callback thread before resuming; the lock protects all reads and writes.
private final class NotificationCallbackProbe: @unchecked Sendable {
    struct Entry: Sendable {
        let operation: String
        let ranOnMainThread: Bool
    }

    private let lock = NSLock()
    private var recorded: [Entry] = []
    var entries: [Entry] { lock.withLock { recorded } }
    func record(_ operation: String) {
        lock.withLock { recorded.append(Entry(operation: operation, ranOnMainThread: Thread.isMainThread)) }
    }
}
