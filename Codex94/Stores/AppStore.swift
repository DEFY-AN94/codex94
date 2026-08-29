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
    private(set) var resetRefreshTask: Task<Void, Never>?
    private(set) var scheduledResetRefreshDate: Date?
    private(set) var pendingResetRefreshDate: Date?
    private(set) var activeRefreshStartedAt: Date?
    private var preferencesObservation: AnyCancellable?
    private var isShuttingDown = false

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
        resetRefreshTask?.cancel()
        fetcher.shutdown()
        locator.shutdown()
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
            isRefreshing: isRefreshing,
            lastSuccessfulFetch: snapshot?.fetchedAt
        )
    }

    var viewedStatusPresentation: StatusPresentation {
        StatusPresentation(
            remainingPercent: viewedWindow?.remainingPercent,
            connectionState: connectionState,
            isRefreshing: isRefreshing,
            lastSuccessfulFetch: snapshot?.fetchedAt
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
        guard !isShuttingDown else { return }
        configureBackgroundRefresh()
        guard preferences.hasChosenIdentityMode else { return }
        let now = Date()
        configureQuotaResetRefresh(now: now)
        refresh(trigger: .launch, startedAt: now)
    }

    func refresh(trigger: RefreshTrigger, startedAt: Date = Date()) {
        guard !isShuttingDown else { return }
        guard preferences.hasChosenIdentityMode else { return }
        guard refreshTask == nil else {
            if trigger == .preferenceChange {
                pendingRefreshTrigger = trigger
            }
            logger.info("refresh=coalesced trigger=\(trigger.rawValue, privacy: .public)")
            return
        }

        consumeDueQuotaResetsForAcceptedRefresh(startedAt: startedAt)
        activeRefreshStartedAt = startedAt
        isRefreshing = true
        if snapshot == nil { connectionState = .refreshing }
        let manualPath = preferences.manualCodexPath
        let identityMode = preferences.identityMode

        refreshTask = Task { [weak self] in
            guard let self, !isShuttingDown else { return }
            var successfulFetchedAt: Date?
            do {
                let located = try await Task.detached(priority: .utility) { [locator] in
                    try locator.locate(manualPath: manualPath)
                }.value
                guard !Task.isCancelled, !isShuttingDown else { return }
                let freshSnapshot = try await fetcher.fetch(
                    executable: located,
                    identityMode: identityMode
                )
                guard !Task.isCancelled, !isShuttingDown else { return }
                applySuccess(freshSnapshot, located: located)
                successfulFetchedAt = freshSnapshot.fetchedAt
            } catch {
                guard !Task.isCancelled, !isShuttingDown else { return }
                applyFailure(Self.issue(from: error))
            }

            guard !isShuttingDown else { return }
            finishRefresh(successfulFetchedAt: successfulFetchedAt, now: Date())
        }
    }

    func popoverWillOpen() {
        refresh(trigger: .popover)
    }

    func handleSystemWake(now: Date = Date()) {
        guard !isShuttingDown else { return }
        guard preferences.hasChosenIdentityMode else { return }
        if reconcileQuotaResetRefresh(now: now) {
            configureBackgroundRefresh()
            return
        }
        guard RefreshPolicy.shouldRefreshAfterWake(
            lastSuccessfulFetch: snapshot?.fetchedAt,
            now: now
        ) else { return }

        configureBackgroundRefresh()
        refresh(trigger: .systemWake, startedAt: now)
    }

    func handleSystemClockChange(now: Date = Date()) {
        guard !isShuttingDown else { return }
        guard preferences.hasChosenIdentityMode else { return }
        _ = reconcileQuotaResetRefresh(now: now)
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        pendingRefreshTrigger = nil

        backgroundTask?.cancel()
        backgroundTask = nil
        resetRefreshTask?.cancel()
        resetRefreshTask = nil
        scheduledResetRefreshDate = nil
        pendingResetRefreshDate = nil
        refreshTask?.cancel()
        refreshTask = nil
        activeRefreshStartedAt = nil
        isRefreshing = false

        fetcher.shutdown()
        locator.shutdown()
    }

    func chooseIdentityMode(_ mode: IdentityMode, now: Date = Date()) {
        preferences.identityMode = mode
        preferences.hasChosenIdentityMode = true
        if mode == .quotaOnly, let snapshot {
            self.snapshot = snapshot.removingAccount()
        }
        configureQuotaResetRefresh(now: now)
        refresh(trigger: .preferenceChange, startedAt: now)
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

    func configureQuotaResetRefresh(now: Date = Date()) {
        guard !isShuttingDown,
              preferences.hasChosenIdentityMode,
              snapshot != nil else {
            clearQuotaResetRefreshState()
            return
        }

        let consumedFrontier = resetRefreshTask == nil && pendingResetRefreshDate == nil
            ? scheduledResetRefreshDate
            : nil
        resetRefreshTask?.cancel()
        resetRefreshTask = nil

        let threshold = Self.latest(now, consumedFrontier) ?? now
        if let next = RefreshPolicy.earliestFutureQuotaResetDate(
            in: snapshot,
            now: threshold
        ) {
            armQuotaResetRefresh(for: next, now: now)
        } else {
            scheduledResetRefreshDate = Self.latest(
                consumedFrontier,
                RefreshPolicy.latestDueQuotaResetDate(in: snapshot, now: threshold)
            )
        }
    }

    @discardableResult
    func handleQuotaResetRefreshTimer(
        expectedDate: Date,
        now: Date = Date()
    ) -> Bool {
        guard !isShuttingDown,
              preferences.hasChosenIdentityMode,
              snapshot != nil,
              resetRefreshTask != nil,
              scheduledResetRefreshDate == expectedDate else {
            return false
        }

        if now < expectedDate {
            armQuotaResetRefresh(for: expectedDate, now: now)
            return false
        }

        resetRefreshTask?.cancel()
        resetRefreshTask = nil
        let batchDate = Self.latest(
            expectedDate,
            RefreshPolicy.latestDueQuotaResetDate(in: snapshot, now: now)
        ) ?? expectedDate
        advanceQuotaResetFrontier(consuming: batchDate, now: now)
        processDueQuotaResetBatch(batchDate, now: now)
        return true
    }

    private func finishRefresh(successfulFetchedAt: Date?, now: Date) {
        // A reset timer and a request completion can become runnable together.
        // Reconcile while this request is still marked active so a pre-target
        // result cannot cancel a newly due target before it becomes pending.
        _ = reconcileQuotaResetRefresh(now: now)

        if let successfulFetchedAt {
            if let pendingResetRefreshDate,
               successfulFetchedAt >= pendingResetRefreshDate {
                self.pendingResetRefreshDate = nil
            }
            replaceQuotaResetScheduleAfterSuccess(
                fetchedAt: successfulFetchedAt,
                now: now
            )
        }

        let queuedTrigger = pendingRefreshTrigger
        pendingRefreshTrigger = nil
        refreshTask = nil
        activeRefreshStartedAt = nil

        if let pendingResetRefreshDate, now < pendingResetRefreshDate {
            self.pendingResetRefreshDate = nil
            armQuotaResetRefresh(for: pendingResetRefreshDate, now: now)
        }

        if let queuedTrigger {
            refresh(trigger: queuedTrigger, startedAt: now)
        } else if pendingResetRefreshDate != nil {
            refresh(trigger: .quotaReset, startedAt: now)
        } else {
            isRefreshing = false
        }
    }

    private func replaceQuotaResetScheduleAfterSuccess(
        fetchedAt: Date,
        now: Date
    ) {
        let consumedFrontier = resetRefreshTask == nil && pendingResetRefreshDate == nil
            ? scheduledResetRefreshDate
            : nil
        resetRefreshTask?.cancel()
        resetRefreshTask = nil

        let threshold = Self.latest(Self.latest(now, fetchedAt), consumedFrontier) ?? now
        if let next = RefreshPolicy.earliestFutureQuotaResetDate(
            in: snapshot,
            now: threshold
        ) {
            armQuotaResetRefresh(for: next, now: now)
        } else {
            scheduledResetRefreshDate = Self.latest(
                consumedFrontier,
                RefreshPolicy.latestDueQuotaResetDate(in: snapshot, now: threshold)
            )
        }
    }

    private func consumeDueQuotaResetsForAcceptedRefresh(startedAt: Date) {
        if let pendingResetRefreshDate, pendingResetRefreshDate <= startedAt {
            self.pendingResetRefreshDate = nil
        }

        let latestDue = RefreshPolicy.latestDueQuotaResetDate(in: snapshot, now: startedAt)
        if resetRefreshTask != nil,
           let scheduledResetRefreshDate,
           scheduledResetRefreshDate <= startedAt {
            let batchDate = Self.latest(scheduledResetRefreshDate, latestDue)
                ?? scheduledResetRefreshDate
            advanceQuotaResetFrontier(consuming: batchDate, now: startedAt)
            return
        }

        guard resetRefreshTask == nil, let latestDue else { return }
        if let consumedFrontier = scheduledResetRefreshDate,
           latestDue <= consumedFrontier {
            return
        }
        advanceQuotaResetFrontier(consuming: latestDue, now: startedAt)
    }

    @discardableResult
    private func reconcileQuotaResetRefresh(now: Date) -> Bool {
        guard let snapshot else {
            clearQuotaResetRefreshState()
            return false
        }

        if let pendingResetRefreshDate, now < pendingResetRefreshDate {
            self.pendingResetRefreshDate = nil
            armQuotaResetRefresh(for: pendingResetRefreshDate, now: now)
            return false
        }
        if pendingResetRefreshDate != nil {
            return true
        }

        if let expectedDate = scheduledResetRefreshDate, resetRefreshTask != nil {
            if now < expectedDate {
                armQuotaResetRefresh(for: expectedDate, now: now)
                return false
            }
            return handleQuotaResetRefreshTimer(expectedDate: expectedDate, now: now)
        }

        let consumedFrontier = scheduledResetRefreshDate
        if let latestDue = RefreshPolicy.latestDueQuotaResetDate(
            in: snapshot,
            now: now,
            strictlyAfter: consumedFrontier
        ) {
            advanceQuotaResetFrontier(consuming: latestDue, now: now)
            processDueQuotaResetBatch(latestDue, now: now)
            return true
        }

        let threshold = Self.latest(now, consumedFrontier) ?? now
        if let next = RefreshPolicy.earliestFutureQuotaResetDate(
            in: snapshot,
            now: threshold
        ) {
            armQuotaResetRefresh(for: next, now: now)
        } else if consumedFrontier == nil {
            scheduledResetRefreshDate = RefreshPolicy.latestDueQuotaResetDate(
                in: snapshot,
                now: threshold
            )
        }
        return false
    }

    private func processDueQuotaResetBatch(_ batchDate: Date, now: Date) {
        if refreshTask != nil {
            if let activeRefreshStartedAt, activeRefreshStartedAt >= batchDate {
                if let pendingResetRefreshDate,
                   pendingResetRefreshDate <= activeRefreshStartedAt {
                    self.pendingResetRefreshDate = nil
                }
                return
            }
            pendingResetRefreshDate = Self.latest(pendingResetRefreshDate, batchDate)
            return
        }

        refresh(trigger: .quotaReset, startedAt: now)
    }

    private func advanceQuotaResetFrontier(consuming batchDate: Date, now: Date) {
        resetRefreshTask?.cancel()
        resetRefreshTask = nil
        if let next = RefreshPolicy.earliestFutureQuotaResetDate(
            in: snapshot,
            now: now
        ) {
            armQuotaResetRefresh(for: next, now: now)
        } else {
            scheduledResetRefreshDate = batchDate
        }
    }

    private func armQuotaResetRefresh(for targetDate: Date, now: Date) {
        resetRefreshTask?.cancel()
        resetRefreshTask = nil
        scheduledResetRefreshDate = targetDate
        guard !isShuttingDown,
              preferences.hasChosenIdentityMode,
              targetDate > now else {
            return
        }

        let delay = targetDate.timeIntervalSince(now)
        resetRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.handleQuotaResetRefreshTimer(expectedDate: targetDate)
        }
    }

    private func clearQuotaResetRefreshState() {
        resetRefreshTask?.cancel()
        resetRefreshTask = nil
        scheduledResetRefreshDate = nil
        pendingResetRefreshDate = nil
    }

    private static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): max(lhs, rhs)
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case (nil, nil): nil
        }
    }

    private func configureBackgroundRefresh() {
        backgroundTask?.cancel()
        backgroundTask = nil
        guard !isShuttingDown else { return }
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
