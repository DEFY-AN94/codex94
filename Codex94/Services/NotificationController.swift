import Combine
import Foundation
import UserNotifications

enum NotificationAuthorization: Equatable, Sendable {
    case unknown, notDetermined, denied, authorized
}

@MainActor
protocol QuotaNotificationServing {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func deliver(title: String, body: String) async throws
}

@MainActor
protocol UserNotificationCenterAccess: AnyObject {
    func getAuthorizationStatus(completion: @escaping @Sendable (Int) -> Void)
    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping @Sendable (Bool, Error?) -> Void)
    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void)
}

@MainActor
private final class SystemUserNotificationCenterAccess: NSObject, UserNotificationCenterAccess,
    UNUserNotificationCenterDelegate {
    // Never touch the user's notification service merely by constructing a store.
    private lazy var center: UNUserNotificationCenter = {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()

    func getAuthorizationStatus(completion: @escaping @Sendable (Int) -> Void) {
        // UserNotifications calls these blocks on its own call-out queue. The
        // explicit Sendable boundary prevents inherited MainActor checks on
        // SDKs whose Objective-C completion parameters lack that annotation.
        center.getNotificationSettings { @Sendable settings in
            completion(settings.authorizationStatus.rawValue)
        }
    }

    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping @Sendable (Bool, Error?) -> Void) {
        center.requestAuthorization(options: options) { @Sendable granted, error in
            completion(granted, error)
        }
    }

    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void) {
        center.add(request) { @Sendable error in
            completion(error)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

@MainActor
final class SystemQuotaNotificationService: QuotaNotificationServing {
    private let center: any UserNotificationCenterAccess

    init(center: (any UserNotificationCenterAccess)? = nil) {
        self.center = center ?? SystemUserNotificationCenterAccess()
    }

    func authorization() async -> NotificationAuthorization {
        await withCheckedContinuation { continuation in
            center.getAuthorizationStatus { @Sendable status in
                let authorization: NotificationAuthorization
                switch status {
                case UNAuthorizationStatus.authorized.rawValue,
                     UNAuthorizationStatus.provisional.rawValue: authorization = .authorized
                case UNAuthorizationStatus.notDetermined.rawValue: authorization = .notDetermined
                default: authorization = .denied
                }
                continuation.resume(returning: authorization)
            }
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert]) { @Sendable granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func deliver(title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { @Sendable error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

@MainActor
final class NotificationController: ObservableObject {
    @Published private(set) var authorization: NotificationAuthorization = .unknown
    @Published private(set) var isRequesting = false
    @Published private(set) var hasIssue = false

    private let service: any QuotaNotificationServing
    private var isEnabled = false
    private var generation = 0
    private var settingsTask: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    init(service: any QuotaNotificationServing = SystemQuotaNotificationService()) {
        self.service = service
    }

    func configure(enabled: Bool, requestPermission: Bool = false) {
        generation += 1
        let currentGeneration = generation
        isEnabled = enabled
        settingsTask?.cancel()
        deliveryTask?.cancel()
        statusTask?.cancel()
        isRequesting = false
        hasIssue = false
        guard enabled else { return }
        isRequesting = requestPermission
        settingsTask = Task { [weak self] in
            guard let self else { return }
            var state = await service.authorization()
            guard !Task.isCancelled, generation == currentGeneration else { return }
            if requestPermission && state == .notDetermined {
                do {
                    state = try await service.requestAuthorization() ? .authorized : .denied
                } catch {
                    guard !Task.isCancelled, generation == currentGeneration else { return }
                    hasIssue = true
                }
            }
            guard !Task.isCancelled, generation == currentGeneration else { return }
            authorization = state
            isRequesting = false
        }
    }

    func refreshAuthorization() {
        guard isEnabled, !isRequesting else { return }
        let currentGeneration = generation
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            guard let self else { return }
            let state = await service.authorization()
            guard !Task.isCancelled, generation == currentGeneration else { return }
            authorization = state
        }
    }

    func deliver(_ events: [QuotaNotificationEvent], language: LanguagePreference, provider: QuotaProviderID = .codex) {
        guard isEnabled, !events.isEmpty else { return }
        let currentGeneration = generation
        deliveryTask?.cancel()
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            let state = await service.authorization()
            guard !Task.isCancelled, isEnabled, generation == currentGeneration else { return }
            authorization = state
            guard state == .authorized else { return }
            // One successful refresh produces at most one banner, even if several
            // independent windows cross a threshold together.
            let body = events.map { Self.message(for: $0, language: language) }.joined(separator: "\n")
            let applicationTitle = StatusAccessibilityString.localized(
                "notifications.title", language: language, bundle: .main
            )
            let title = provider == .codex ? applicationTitle : applicationTitle + " · " + provider.displayName
            do {
                try await service.deliver(title: title, body: body)
            } catch {
                guard !Task.isCancelled, generation == currentGeneration else { return }
                hasIssue = true
            }
        }
    }

    func shutdown() {
        configure(enabled: false)
    }

    static func message(for event: QuotaNotificationEvent, language: LanguagePreference) -> String {
        let kindKey = event.window == .fiveHour ? "quota.fiveHourShort" : "quota.weeklyShort"
        let window = StatusAccessibilityString.localized(kindKey, language: language, bundle: .main)
        let key: String = switch event.kind {
        case .low: "notifications.low %@ %@ %@"
        case .recovered: "notifications.recovered %@ %@ %@"
        }
        return StatusAccessibilityString.localized(
            key,
            arguments: [event.bucketName, window, String(event.remainingPercent)],
            language: language,
            bundle: .main
        )
    }
}
