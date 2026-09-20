import XCTest
@testable import Codex94

final class NotificationPolicyTests: XCTestCase {
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
