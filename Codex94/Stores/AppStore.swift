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
    @Published private(set) var viewedBucketID: String?

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
            viewedBucketID = cached.defaultLimitID
            connectionState = .stale(lastSuccess: cached.fetchedAt, issue: .unknown)
        }

        preferencesObservation = preferences.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    deinit {
        refreshTask?.cancel()
        backgroundTask?.cancel()
    }

    var menuBarQuota: ResolvedQuotaWindow? {
        preferredMenuBarQuota ?? snapshot?.automaticResolvedWindow
    }

    var menuBarSelectionUsesFallback: Bool {
        preferences.menuBarQuotaSelection != .automatic && preferredMenuBarQuota == nil
    }

    var viewedBucket: QuotaBucketSnapshot? {
        guard let snapshot else { return nil }
        if let bucket = snapshot.displayableBuckets.first(where: { $0.limitID == viewedBucketID }) {
            return bucket
        }
        return snapshot.defaultBucket
    }

    var viewedWindow: QuotaWindowSnapshot? {
        viewedBucket?.mostConstrainedWindow
    }

    var menuBarStatusPresentation: StatusPresentation {
        StatusPresentation(
            remainingPercent: menuBarQuota?.window.remainingPercent,
            connectionState: connectionState,
            isRefreshing: isRefreshing
        )
    }

    var viewedStatusPresentation: StatusPresentation {
        StatusPresentation(
            remainingPercent: viewedWindow?.remainingPercent,
            connectionState: connectionState,
            isRefreshing: isRefreshing
        )
    }

    var menuBarQuotaOptions: [MenuBarQuotaOption] {
        var options = [
            MenuBarQuotaOption(
                selection: .automatic,
                bucketName: nil,
                kind: nil,
                isAvailable: true
            )
        ]

        guard let snapshot else {
            let preferred = preferences.menuBarQuotaSelection
            if preferred != .automatic, let kind = Self.kind(in: preferred) {
                options.append(MenuBarQuotaOption(
                    selection: preferred,
                    bucketName: nil,
                    kind: kind,
                    isAvailable: false
                ))
            }
            return options
        }

        for bucket in snapshot.displayableBuckets {
            for window in bucket.windows.sorted(by: { $0.kind.sortOrder < $1.kind.sortOrder }) {
                let selection: MenuBarQuotaSelection = bucket.limitID == snapshot.defaultLimitID
                    ? .defaultBucket(window.kind)
                    : .bucket(limitID: bucket.limitID, kind: window.kind)
                options.append(MenuBarQuotaOption(
                    selection: selection,
                    bucketName: snapshot.displayName(for: bucket),
                    kind: window.kind,
                    isAvailable: true
                ))
            }
        }

        let preferred = preferences.menuBarQuotaSelection
        if !options.contains(where: { $0.selection == preferred }),
           let kind = Self.kind(in: preferred) {
            options.append(MenuBarQuotaOption(
                selection: preferred,
                bucketName: unavailableBucketName(for: preferred, snapshot: snapshot),
                kind: kind,
                isAvailable: false
            ))
        }
        return options
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
            self.snapshot = snapshot.removingAccount()
        }
        refresh(trigger: .preferenceChange)
    }

    func setMenuBarQuotaSelection(_ selection: MenuBarQuotaSelection) {
        guard menuBarQuotaOptions.contains(where: {
            $0.selection == selection && $0.isAvailable
        }) else { return }
        preferences.menuBarQuotaSelection = selection
    }

    func setViewedBucket(_ limitID: String) {
        guard snapshot?.displayableBuckets.contains(where: { $0.limitID == limitID }) == true else {
            return
        }
        viewedBucketID = limitID
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        preferences.refreshInterval = interval
        configureBackgroundRefresh()
    }

    func setIdentityMode(_ mode: IdentityMode) {
        preferences.identityMode = mode
        if mode == .quotaOnly, let snapshot {
            self.snapshot = snapshot.removingAccount()
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
            codexPath: DiagnosticsRedactor.codexPath(for: locatedCodex),
            codexVersion: DiagnosticsRedactor.codexVersion(locatedCodex?.version),
            codexSource: locatedCodex?.source.rawValue ?? "unknown",
            identityMode: preferences.identityMode.rawValue,
            displayMode: preferences.menuBarQuotaSelection.diagnosticValue,
            refreshMinutes: preferences.refreshInterval.rawValue,
            lastSuccess: snapshot?.fetchedAt,
            lastError: lastIssue?.rawValue
        )
    }

    private func applySuccess(_ freshSnapshot: QuotaSnapshot, located: LocatedCodex) {
        let visibleSnapshot: QuotaSnapshot
        if preferences.identityMode == .quotaOnly, freshSnapshot.account != nil {
            visibleSnapshot = freshSnapshot.removingAccount()
        } else {
            visibleSnapshot = freshSnapshot
        }

        snapshot = visibleSnapshot
        locatedCodex = located
        lastIssue = nil
        connectionState = .connected

        if !visibleSnapshot.displayableBuckets.contains(where: { $0.limitID == viewedBucketID }) {
            viewedBucketID = visibleSnapshot.defaultLimitID
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

    private var preferredMenuBarQuota: ResolvedQuotaWindow? {
        guard let snapshot,
              let resolved = snapshot.resolved(preferences.menuBarQuotaSelection),
              snapshot.displayableBuckets.contains(where: {
                  $0.limitID == resolved.bucket.limitID
              }) else {
            return nil
        }
        return resolved
    }

    private func unavailableBucketName(
        for selection: MenuBarQuotaSelection,
        snapshot: QuotaSnapshot
    ) -> String? {
        switch selection {
        case .automatic:
            return nil
        case .defaultBucket:
            return "Codex"
        case let .bucket(limitID, _):
            guard let bucket = snapshot.displayableBuckets.first(where: {
                $0.limitID == limitID
            }) else {
                return nil
            }
            return snapshot.displayName(for: bucket)
        }
    }

    private static func kind(in selection: MenuBarQuotaSelection) -> QuotaWindowKind? {
        switch selection {
        case .automatic: nil
        case let .defaultBucket(kind): kind
        case let .bucket(_, kind): kind
        }
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
