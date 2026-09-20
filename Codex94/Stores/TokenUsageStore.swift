import Combine
import Foundation

/// Account usage is loaded on demand, independently from quota polling.
@MainActor
final class TokenUsageStore: ObservableObject {
    @Published private(set) var snapshot: TokenUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var issue: TokenUsageIssue?

    private let preferences: PreferencesStore
    private var fetcher: any TokenUsageFetching
    private var locator = CodexExecutableLocator()
    private let fetcherFactory: @Sendable () -> any TokenUsageFetching
    private let resolve: (@Sendable (String?) async throws -> LocatedCodex)?
    private let cleanupQueue = DispatchQueue(label: "com.defyan94.codex94.usage-cleanup", qos: .utility)
    private var task: Task<Void, Never>?
    private var generation = 0
    private var stopped = false

    init(
        preferences: PreferencesStore,
        fetcherFactory: @escaping @Sendable () -> any TokenUsageFetching = { CodexAppServerClient() },
        resolve: (@Sendable (String?) async throws -> LocatedCodex)? = nil
    ) {
        self.preferences = preferences
        self.fetcherFactory = fetcherFactory
        self.fetcher = fetcherFactory()
        self.resolve = resolve
    }

    deinit {
        task?.cancel()
        if !stopped {
            fetcher.shutdown()
            locator.shutdown()
            cleanupQueue.sync {}
        }
    }

    func loadIfNeeded() {
        guard snapshot == nil, issue == nil else { return }
        refresh()
    }

    func refresh() {
        guard !stopped, task == nil, preferences.hasChosenIdentityMode else { return }
        let requestGeneration = generation
        let manualPath = preferences.manualCodexPath
        let requestFetcher = fetcher
        let requestLocator = locator
        isRefreshing = true
        issue = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let executable: LocatedCodex
                if let resolve {
                    executable = try await resolve(manualPath)
                } else {
                    executable = try await Task.detached(priority: .utility) {
                        try requestLocator.locate(manualPath: manualPath)
                    }.value
                }
                guard !Task.isCancelled, generation == requestGeneration, !stopped else { return }
                let result = try await requestFetcher.fetchUsage(executable: executable)
                guard !Task.isCancelled, generation == requestGeneration, !stopped else { return }
                // Each response replaces the prior snapshot, including same-date corrections.
                snapshot = result
            } catch {
                guard !Task.isCancelled, generation == requestGeneration, !stopped else { return }
                let mapped = Self.map(error)
                issue = mapped
                if mapped == .notLoggedIn || mapped == .unsupported {
                    snapshot = nil
                }
            }
            guard generation == requestGeneration, !stopped else { return }
            isRefreshing = false
            task = nil
        }
    }

    /// Invalidate old requests on identity or executable changes; never mix snapshots.
    func reset() {
        guard !stopped else { return }
        invalidateCurrentGeneration()
        let oldFetcher = fetcher
        let oldLocator = locator
        fetcher = fetcherFactory()
        locator = CodexExecutableLocator()
        // Never retain the store here: cleanup owns only the invalidated generation.
        cleanupQueue.async { [oldFetcher, oldLocator] in
            oldFetcher.shutdown()
            oldLocator.shutdown()
        }
    }

    func shutdown() {
        guard !stopped else { return }
        stopped = true
        invalidateCurrentGeneration()
        fetcher.shutdown()
        locator.shutdown()
        // Quitting still waits until every retired generation has been stopped.
        cleanupQueue.sync {}
    }

    private func invalidateCurrentGeneration() {
        generation += 1
        task?.cancel()
        task = nil
        snapshot = nil
        issue = nil
        isRefreshing = false
    }

    private static func map(_ error: Error) -> TokenUsageIssue {
        if let issue = error as? TokenUsageIssue { return issue }
        if let issue = error as? ConnectionIssue {
            switch issue {
            case .notLoggedIn: return .notLoggedIn
            case .malformedResponse, .missingResult: return .invalidData
            default: return .unavailable
            }
        }
        return .unavailable
    }
}
