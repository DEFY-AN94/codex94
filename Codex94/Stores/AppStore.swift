import Combine
import Foundation
import OSLog

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var locatedCodex: LocatedCodex?
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastIssue: ConnectionIssue?

    let preferences: PreferencesStore
    let launchAtLogin: LaunchAtLoginController

    private let locator: CodexExecutableLocator
    private let fetcher: any QuotaFetching
    private let cache: SnapshotCache
    private let logger = Logger(subsystem: "com.defyan94.codex94", category: "state")
    private var refreshTask: Task<Void, Never>?
    private var pendingRefreshTrigger: RefreshTrigger?
    private var backgroundTask: Task<Void, Never>?
    private var preferencesObservation: AnyCancellable?

    init(
        preferences: PreferencesStore = PreferencesStore(),
        launchAtLogin: LaunchAtLoginController = LaunchAtLoginController(),
        locator: CodexExecutableLocator = CodexExecutableLocator(),
        fetcher: any QuotaFetching = CodexAppServerClient(),
        cache: SnapshotCache = SnapshotCache()
    ) {
        self.preferences = preferences
        self.launchAtLogin = launchAtLogin
        self.locator = locator
        self.fetcher = fetcher
        self.cache = cache

        if let cached = cache.load() {
            snapshot = cached
            connectionState = .stale(lastSuccess: cached.fetchedAt, issue: .unknown)
            if preferences.displayMode == .fiveHour,
               cached.window(.fiveHour) == nil {
                preferences.displayMode = .weekly
            }
        }

        preferencesObservation = preferences.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    deinit {
        refreshTask?.cancel()
        backgroundTask?.cancel()
    }

    var displayedWindow: QuotaWindowSnapshot? {
        snapshot?.window(for: preferences.displayMode)
    }

    var availableDisplayModes: [DisplayMode] {
        var modes: [DisplayMode] = [.automatic]
        if snapshot?.window(.fiveHour) != nil { modes.append(.fiveHour) }
        if snapshot?.window(.weekly) != nil { modes.append(.weekly) }
        return modes
    }

    func start() {
        configureBackgroundRefresh()
        guard preferences.hasChosenIdentityMode else { return }
        refresh(trigger: .launch)
    }

    func refresh(trigger: RefreshTrigger) {
        guard preferences.hasChosenIdentityMode else { return }
        guard refreshTask == nil else {
            if trigger == .preferenceChange {
                pendingRefreshTrigger = trigger
            }
            logger.info("refresh=coalesced trigger=\(trigger.rawValue, privacy: .public)")
            return
        }

        isRefreshing = true
        if snapshot == nil { connectionState = .refreshing }
        let manualPath = preferences.manualCodexPath
        let identityMode = preferences.identityMode

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let located = try await Task.detached(priority: .utility) { [locator] in
                    try locator.locate(manualPath: manualPath)
                }.value
                let freshSnapshot = try await fetcher.fetch(
                    executable: located,
                    identityMode: identityMode
                )
                applySuccess(freshSnapshot, located: located)
            } catch {
                applyFailure(Self.issue(from: error))
            }

            let queuedTrigger = pendingRefreshTrigger
            pendingRefreshTrigger = nil
            refreshTask = nil
            if let queuedTrigger {
                refresh(trigger: queuedTrigger)
            } else {
                isRefreshing = false
            }
        }
    }

    func popoverWillOpen() {
        refresh(trigger: .popover)
    }

    func chooseIdentityMode(_ mode: IdentityMode) {
        preferences.identityMode = mode
        preferences.hasChosenIdentityMode = true
        if mode == .quotaOnly, let snapshot {
            self.snapshot = QuotaSnapshot(
                windows: snapshot.windows,
                planType: snapshot.planType,
                fetchedAt: snapshot.fetchedAt,
                account: nil,
                codex: snapshot.codex
            )
        }
        refresh(trigger: .preferenceChange)
    }

    func setDisplayMode(_ mode: DisplayMode) {
        guard availableDisplayModes.contains(mode) else { return }
        preferences.displayMode = mode
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        preferences.refreshInterval = interval
        configureBackgroundRefresh()
    }

    func setIdentityMode(_ mode: IdentityMode) {
        preferences.identityMode = mode
        if mode == .quotaOnly, let snapshot {
            self.snapshot = QuotaSnapshot(
                windows: snapshot.windows,
                planType: snapshot.planType,
                fetchedAt: snapshot.fetchedAt,
                account: nil,
                codex: snapshot.codex
            )
        }
        refresh(trigger: .preferenceChange)
    }

    func setManualCodexPath(_ path: String?) {
        preferences.manualCodexPath = path
        refresh(trigger: .preferenceChange)
    }

    func diagnostics(now: Date = Date()) -> RedactedDiagnostics {
        RedactedDiagnostics(
            generatedAt: now,
            connection: Self.connectionLabel(connectionState),
            codexPath: DiagnosticsRedactor.redact(locatedCodex?.executableURL.path ?? "not-detected"),
            codexVersion: DiagnosticsRedactor.redact(locatedCodex?.version ?? "unknown"),
            codexSource: locatedCodex?.source.rawValue ?? "unknown",
            identityMode: preferences.identityMode.rawValue,
            displayMode: preferences.displayMode.rawValue,
            refreshMinutes: preferences.refreshInterval.rawValue,
            lastSuccess: snapshot?.fetchedAt,
            lastError: lastIssue?.rawValue
        )
    }

    private func applySuccess(_ freshSnapshot: QuotaSnapshot, located: LocatedCodex) {
        let visibleSnapshot: QuotaSnapshot
        if preferences.identityMode == .quotaOnly, freshSnapshot.account != nil {
            visibleSnapshot = QuotaSnapshot(
                windows: freshSnapshot.windows,
                planType: freshSnapshot.planType,
                fetchedAt: freshSnapshot.fetchedAt,
                account: nil,
                codex: freshSnapshot.codex
            )
        } else {
            visibleSnapshot = freshSnapshot
        }

        snapshot = visibleSnapshot
        locatedCodex = located
        lastIssue = nil
        connectionState = .connected

        if preferences.displayMode == .fiveHour,
           visibleSnapshot.window(.fiveHour) == nil {
            preferences.displayMode = .weekly
        }

        do {
            try cache.save(visibleSnapshot)
        } catch {
            logger.error("cache=write_failed")
        }
    }

    private func applyFailure(_ issue: ConnectionIssue) {
        lastIssue = issue
        if let lastSuccess = snapshot?.fetchedAt {
            connectionState = .stale(lastSuccess: lastSuccess, issue: issue)
        } else {
            connectionState = .unavailable(issue)
        }
        logger.error("refresh=failed category=\(issue.rawValue, privacy: .public)")
    }

    private func configureBackgroundRefresh() {
        backgroundTask?.cancel()
        let nanoseconds = UInt64(preferences.refreshInterval.seconds * 1_000_000_000)
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                self?.refresh(trigger: .background)
            }
        }
    }

    private static func issue(from error: Error) -> ConnectionIssue {
        if let issue = error as? ConnectionIssue { return issue }
        return .unknown
    }

    private static func connectionLabel(_ state: ConnectionState) -> String {
        switch state {
        case .idle: "idle"
        case .refreshing: "refreshing"
        case .connected: "connected"
        case .stale: "stale"
        case .unavailable: "unavailable"
        }
    }
}
