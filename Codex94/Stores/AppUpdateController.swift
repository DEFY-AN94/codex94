import Combine
import Foundation

@MainActor
final class AppUpdateController: ObservableObject {
    @Published private(set) var state: AppUpdateState = .idle

    private let currentVersion: AppReleaseVersion?
    private let client: any AppUpdateFetching
    private var task: Task<Void, Never>?
    private var stopped = false

    init(
        currentVersion: String = AppMetadata.current.version,
        client: any AppUpdateFetching = AppUpdateClient()
    ) {
        self.currentVersion = AppReleaseVersion(currentVersion)
        self.client = client
    }

    deinit { task?.cancel() }

    var isChecking: Bool { state == .checking }
    var canCheckForUpdates: Bool { !stopped && !isChecking }

    /// No startup, timer, preference, or quota action calls this method.
    func checkForUpdates() {
        guard !stopped, task == nil else { return }
        guard let currentVersion else {
            state = .failed(.invalidCurrentVersion)
            return
        }
        state = .checking
        task = Task { [weak self] in
            guard let self else { return }
            defer { task = nil }
            do {
                let release = try await client.latestRelease()
                guard !Task.isCancelled, !stopped else { return }
                state = release.version > currentVersion ? .available(release) : .upToDate
            } catch {
                guard !Task.isCancelled, !stopped else { return }
                state = .failed(error as? AppUpdateIssue ?? .unavailable)
            }
        }
    }

    func shutdown() {
        stopped = true
        task?.cancel()
        task = nil
        state = .idle
    }
}
