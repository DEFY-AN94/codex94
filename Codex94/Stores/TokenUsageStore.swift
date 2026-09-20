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
        fetcher.shutdown()
        locator.shutdown()
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
        generation += 1
        task?.cancel()
        task = nil
        fetcher.shutdown()
        locator.shutdown()
        fetcher = fetcherFactory()
        locator = CodexExecutableLocator()
        snapshot = nil
        issue = nil
        isRefreshing = false
    }

    func shutdown() {
        guard !stopped else { return }
        reset()
        stopped = true
        fetcher.shutdown()
        locator.shutdown()
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
