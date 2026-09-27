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
    @Published private(set) var hasFetchedLiveSnapshot = false

    let preferences: PreferencesStore
    let usageStore: TokenUsageStore
    let updates = AppUpdateController()
    let launchAtLogin: LaunchAtLoginController
    let hotKeyController: GlobalHotKeyController
    let notificationController: NotificationController
    private var notificationPolicy = QuotaNotificationPolicy()

    private let locator: CodexExecutableLocator
    private let fetcher: any QuotaFetching
    private let cache: SnapshotCache
    private let retrySleep: @Sendable (TimeInterval) async throws -> Void
    private let logger = Logger(subsystem: "com.defyan94.codex94", category: "state")
    private var refreshTask: Task<Void, Never>?
    private var pendingRefreshTrigger: RefreshTrigger?
    private(set) var backgroundTask: Task<Void, Never>?
    private(set) var resetRefreshTask: Task<Void, Never>?
    private(set) var scheduledResetRefreshDate: Date?
    private(set) var pendingResetRefreshDate: Date?
    private(set) var consumedResetRefreshDate: Date?
    private(set) var activeRefreshStartedAt: Date?
    private var preferencesObservation: AnyCancellable?
    private var isShuttingDown = false
    private var connectionGeneration = 0
    private var automaticRetryTask: Task<Void, Never>?
    private var automaticRetryGeneration = 0
    private var automaticRetryAttempt = 0
    private var accountIdentityIsUnverified = false

    init(
        preferences: PreferencesStore = PreferencesStore(),
        launchAtLogin: LaunchAtLoginController = LaunchAtLoginController(),
        locator: CodexExecutableLocator = CodexExecutableLocator(),
        fetcher: any QuotaFetching = CodexAppServerClient(),
        cache: SnapshotCache = SnapshotCache(),
        hotKeyController: GlobalHotKeyController = GlobalHotKeyController(),
        notificationController: NotificationController = NotificationController(),
        usageStore: TokenUsageStore? = nil,
        retrySleep: @escaping @Sendable (TimeInterval) async throws -> Void = RefreshPolicy.sleepBeforeRetry
    ) {
        self.preferences = preferences
        self.usageStore = usageStore ?? TokenUsageStore(preferences: preferences)
        self.launchAtLogin = launchAtLogin
        self.locator = locator
        self.fetcher = fetcher
        self.cache = cache
        self.retrySleep = retrySleep
        self.hotKeyController = hotKeyController
        self.notificationController = notificationController

        if let cached = cache.load() {
            snapshot = cached
            viewedBucketID = cached.firstAvailableBucket?.limitID
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
        automaticRetryTask?.cancel()
        fetcher.shutdown()
        locator.shutdown()
    }

    var menuBarQuota: ResolvedQuotaWindow? {
        preferredMenuBarQuota ?? snapshot?.automaticResolvedWindow
    }

    var dualWindowBucket: QuotaBucketSnapshot? {
        guard let snapshot else { return nil }
        return preferences.dualWindowBucketSelection.resolved(in: snapshot)
            ?? snapshot.automaticResolvedWindow?.bucket
    }

    var activeMenuBarQuotas: [ResolvedQuotaWindow] {
        if preferences.menuBarLayout == .dualWindow {
            guard let bucket = dualWindowBucket else { return [] }
            return bucket.windows.sorted { $0.kind.sortOrder < $1.kind.sortOrder }
                .map { ResolvedQuotaWindow(bucket: bucket, window: $0) }
        }
        return menuBarQuota.map { [$0] } ?? []
    }

    var menuBarSelectionUsesFallback: Bool {
        preferences.menuBarQuotaSelection != .automatic && preferredMenuBarQuota == nil
    }

    var viewedBucket: QuotaBucketSnapshot? {
        guard let snapshot else { return nil }
        if let bucket = snapshot.displayableBuckets.first(where: {
            $0.limitID == viewedBucketID && !$0.windows.isEmpty
        }) {
            return bucket
        }
        return snapshot.firstAvailableBucket
    }

    var viewedWindow: QuotaWindowSnapshot? {
        viewedBucket?.mostConstrainedWindow
    }

    var menuBarStatusPresentation: StatusPresentation {
        StatusPresentation(
            remainingPercent: preferences.menuBarLayout == .dualWindow
                ? dualWindowBucket?.mostConstrainedWindow?.remainingPercent
                : menuBarQuota?.window.remainingPercent,
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
        notificationController.configure(enabled: preferences.notifications.isEnabled)
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

        // Only an accepted refresh starts a new retry cycle. Coalesced manual
        // requests share the active request and its remaining recovery budget.
        if trigger != .automaticRetry {
            cancelAutomaticRetry()
        }
        let retryGeneration = automaticRetryGeneration
        logger.info("refresh=started trigger=\(trigger.rawValue, privacy: .public)")

        consumeDueQuotaResetsForAcceptedRefresh(startedAt: startedAt)
        activeRefreshStartedAt = startedAt
        isRefreshing = true
        if snapshot == nil { connectionState = .refreshing }
        let manualPath = preferences.manualCodexPath
        let identityMode = preferences.identityMode
        let requestGeneration = connectionGeneration

        refreshTask = Task { [weak self] in
            guard let self, !isShuttingDown else { return }
            guard requestGeneration == connectionGeneration else {
                finishRefresh(successfulFetchedAt: nil, now: Date())
                return
            }
            var successfulFetchedAt: Date?
            var failureIssue: ConnectionIssue?
            do {
                let located = try await Task.detached(priority: .utility) { [locator] in
                    try locator.locate(manualPath: manualPath)
                }.value
                guard !Task.isCancelled, !isShuttingDown else { return }
                if requestGeneration == connectionGeneration {
                    let freshSnapshot = try await fetcher.fetch(
                        executable: located,
                        identityMode: identityMode
                    )
                    guard !Task.isCancelled, !isShuttingDown else { return }
                    if requestGeneration == connectionGeneration {
                        applySuccess(freshSnapshot, located: located)
                        successfulFetchedAt = freshSnapshot.fetchedAt
                        logger.info("refresh=finished trigger=\(trigger.rawValue, privacy: .public) result=success")
                    }
                }
            } catch {
                guard !Task.isCancelled, !isShuttingDown else { return }
                if requestGeneration == connectionGeneration {
                    let issue = Self.issue(from: error)
                    applyFailure(issue)
                    failureIssue = issue
                    logger.info("refresh=finished trigger=\(trigger.rawValue, privacy: .public) result=failure")
                }
            }

            // An obsolete request still releases the single-flight slot so the
            // queued request can use the latest connection preferences.
            guard !isShuttingDown else { return }
            finishRefresh(
                successfulFetchedAt: successfulFetchedAt,
                failureIssue: failureIssue,
                retryGeneration: retryGeneration,
                now: Date()
            )
        }
    }

    func popoverWillOpen(now: Date = Date()) {
        guard RefreshPolicy.shouldRefreshOnPopover(
            connectionState: connectionState,
            lastSuccessfulFetch: snapshot?.fetchedAt,
            now: now
        ) else {
            logger.info("refresh=skipped trigger=popover result=fresh")
            return
        }
        refresh(trigger: .popover, startedAt: now)
    }

    func handleSystemWake(now: Date = Date()) {
        guard !isShuttingDown else { return }
        configureBackgroundRefresh()
        guard preferences.hasChosenIdentityMode else { return }
        if reconcileQuotaResetRefresh(now: now) {
            return
        }
        guard RefreshPolicy.shouldRefreshAfterWake(
            lastSuccessfulFetch: snapshot?.fetchedAt,
            now: now
        ) else { return }

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
        cancelAutomaticRetry()

        backgroundTask?.cancel()
        backgroundTask = nil
        resetRefreshTask?.cancel()
        resetRefreshTask = nil
        scheduledResetRefreshDate = nil
        pendingResetRefreshDate = nil
        consumedResetRefreshDate = nil
        refreshTask?.cancel()
        refreshTask = nil
        activeRefreshStartedAt = nil
        isRefreshing = false

        fetcher.shutdown()
        locator.shutdown()
        notificationController.shutdown()
        usageStore.shutdown()
        updates.shutdown()
        notificationPolicy.reset()
    }

    func chooseIdentityMode(_ mode: IdentityMode, now: Date = Date()) {
        invalidateConnectionContext()
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

    func setDualWindowBucketSelection(_ selection: MenuBarBucketSelection) {
        if selection == .automatic {
            preferences.dualWindowBucketSelection = selection
        } else if let snapshot, selection.resolved(in: snapshot) != nil {
            preferences.dualWindowBucketSelection = selection
        }
    }

    @discardableResult
    func setGlobalHotKey(_ value: GlobalHotKey?) -> Bool {
        guard hotKeyController.setHotKey(value) else { return false }
        preferences.globalHotKey = value
        return true
    }

    func setNotificationPreferences(_ value: NotificationPreferences) {
        let previous = preferences.notifications
        let value = value.validated
        guard value != previous else { return }
        preferences.notifications = value
        notificationPolicy.reset()
        notificationController.configure(
            enabled: value.isEnabled,
            requestPermission: value.isEnabled && !previous.isEnabled
        )
    }

    func requestNotificationPermission() {
        guard preferences.notifications.isEnabled else { return }
        notificationController.configure(enabled: true, requestPermission: true)
    }

    func refreshNotificationAuthorization() {
        notificationController.refreshAuthorization()
    }

    func setViewedBucket(_ limitID: String) {
        guard snapshot?.displayableBuckets.contains(where: {
            $0.limitID == limitID && !$0.windows.isEmpty
        }) == true else {
            return
        }
        viewedBucketID = limitID
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        preferences.refreshInterval = interval
        configureBackgroundRefresh()
    }

    func setIdentityMode(_ mode: IdentityMode) {
        invalidateConnectionContext()
        preferences.identityMode = mode
        if mode == .quotaOnly, let snapshot {
            self.snapshot = snapshot.removingAccount()
        }
        refresh(trigger: .preferenceChange)
    }

    func setManualCodexPath(_ path: String?) {
        invalidateConnectionContext()
        preferences.manualCodexPath = path
        refresh(trigger: .preferenceChange)
    }

    private func invalidateConnectionContext() {
        connectionGeneration += 1
        cancelAutomaticRetry()
        accountIdentityIsUnverified = false
        usageStore.reset()
        notificationPolicy.reset()
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
        cancelAutomaticRetry()
        let visibleSnapshot: QuotaSnapshot
        if preferences.identityMode == .quotaOnly {
            visibleSnapshot = freshSnapshot.removingAccount()
        } else {
            visibleSnapshot = freshSnapshot
        }

        // Account for targets covered by this response before replacing the old
        // windows: a completed reset may disappear from the successful snapshot.
        consumeCoveredQuotaResets(through: visibleSnapshot.fetchedAt)
        let accountIsUnverified = preferences.identityMode == .quotaAndAccount
            && (visibleSnapshot.account == nil || visibleSnapshot.accountReadIssue != nil)
        let accountChanged = snapshot?.account != nil
            && visibleSnapshot.account != nil
            && snapshot?.account != visibleSnapshot.account
        let identityAvailabilityChanged = accountIsUnverified != accountIdentityIsUnverified
        let unverifiedUsageExists = accountIsUnverified
            && (usageStore.snapshot != nil || usageStore.isRefreshing)
        if accountChanged || identityAvailabilityChanged || unverifiedUsageExists {
            notificationPolicy.reset()
            notificationController.configure(enabled: preferences.notifications.isEnabled)
            usageStore.reset()
        }
        accountIdentityIsUnverified = accountIsUnverified
        snapshot = visibleSnapshot
        hasFetchedLiveSnapshot = true
        locatedCodex = located
        lastIssue = nil
        connectionState = .connected

        if !visibleSnapshot.displayableBuckets.contains(where: {
            $0.limitID == viewedBucketID && !$0.windows.isEmpty
        }) {
            viewedBucketID = visibleSnapshot.firstAvailableBucket?.limitID
        }

        if menuBarSelectionUsesFallback {
            preferences.menuBarQuotaSelection = .automatic
        }

        // Unknown identity must not establish or compare a notification baseline
        // that might belong to another account. Quota-only mode keeps its policy.
        if !accountIsUnverified {
            let notificationEvents = notificationPolicy.events(
                for: visibleSnapshot, preferences: preferences.notifications
            )
            notificationController.deliver(notificationEvents, language: preferences.language)
        }

        do {
            try cache.save(visibleSnapshot)
        } catch {
            logger.error("cache=write_failed")
        }
    }

    private func applyFailure(_ issue: ConnectionIssue) {
        if issue == .notLoggedIn { usageStore.reset() }
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

        cancelScheduledQuotaResetRefresh()
        let threshold = Self.latest(now, consumedResetRefreshDate) ?? now
        if let next = RefreshPolicy.earliestFutureQuotaResetDate(
            in: snapshot,
            now: threshold
        ) {
            armQuotaResetRefresh(for: next, now: now)
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

        cancelScheduledQuotaResetRefresh()
        let batchDate = Self.latest(
            expectedDate,
            RefreshPolicy.latestDueQuotaResetDate(
                in: snapshot, now: now, strictlyAfter: consumedResetRefreshDate
            )
        ) ?? expectedDate
        processDueQuotaResetBatch(batchDate, now: now)
        return true
    }

    private func finishRefresh(
        successfulFetchedAt: Date?,
        failureIssue: ConnectionIssue? = nil,
        retryGeneration: Int? = nil,
        now: Date
    ) {
        if let successfulFetchedAt {
            replaceQuotaResetScheduleAfterSuccess(fetchedAt: successfulFetchedAt)
        }

        // Reconcile while the request is still active, after removing deadlines
        // for windows that disappeared. A still-valid pre-target result can
        // queue one follow-up even when completion wins the timer race.
        _ = reconcileQuotaResetRefresh(now: now)

        let queuedTrigger = pendingRefreshTrigger
        pendingRefreshTrigger = nil
        refreshTask = nil
        activeRefreshStartedAt = nil

        if let queuedTrigger {
            refresh(trigger: queuedTrigger, startedAt: now)
        } else if pendingResetRefreshDate != nil {
            refresh(trigger: .quotaReset, startedAt: now)
        } else {
            isRefreshing = false
            if let failureIssue, let retryGeneration {
                scheduleAutomaticRetry(for: failureIssue, generation: retryGeneration)
            }
        }
    }

    private func cancelAutomaticRetry() {
        automaticRetryTask?.cancel()
        automaticRetryTask = nil
        automaticRetryGeneration += 1
        automaticRetryAttempt = 0
    }

    private func scheduleAutomaticRetry(for issue: ConnectionIssue, generation: Int) {
        guard !isShuttingDown, generation == automaticRetryGeneration,
              let delay = RefreshPolicy.automaticRetryDelay(
                for: issue, completedRetries: automaticRetryAttempt
              ) else { return }
        automaticRetryAttempt += 1
        let requestGeneration = connectionGeneration
        logger.info("refresh=retry_scheduled attempt=\(self.automaticRetryAttempt, privacy: .public)")
        automaticRetryTask = Task { [weak self, retrySleep] in
            do {
                try await retrySleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, !isShuttingDown,
                  generation == automaticRetryGeneration,
                  requestGeneration == connectionGeneration else { return }
            automaticRetryTask = nil
            refresh(trigger: .automaticRetry)
        }
    }

    private func replaceQuotaResetScheduleAfterSuccess(fetchedAt: Date) {
        consumeCoveredQuotaResets(through: fetchedAt)
        let currentTargets = RefreshPolicy.quotaResetDates(in: snapshot)
        if let pendingResetRefreshDate, !currentTargets.contains(pendingResetRefreshDate) {
            self.pendingResetRefreshDate = nil
        }
        cancelScheduledQuotaResetRefresh()
    }

    private func consumeDueQuotaResetsForAcceptedRefresh(startedAt: Date) {
        consumeCoveredQuotaResets(through: startedAt)
        configureQuotaResetRefresh(now: startedAt)
    }

    @discardableResult
    private func reconcileQuotaResetRefresh(now: Date) -> Bool {
        guard let snapshot else {
            clearQuotaResetRefreshState()
            return false
        }

        if let pendingResetRefreshDate, now < pendingResetRefreshDate {
            self.pendingResetRefreshDate = nil
        }

        if let latestDue = RefreshPolicy.latestDueQuotaResetDate(
            in: snapshot,
            now: now,
            strictlyAfter: consumedResetRefreshDate
        ) {
            processDueQuotaResetBatch(latestDue, now: now)
            return true
        }

        configureQuotaResetRefresh(now: now)
        return false
    }

    private func processDueQuotaResetBatch(_ batchDate: Date, now: Date) {
        if refreshTask != nil {
            if let activeRefreshStartedAt, activeRefreshStartedAt >= batchDate {
                consumeCoveredQuotaResets(through: activeRefreshStartedAt)
            } else {
                pendingResetRefreshDate = Self.latest(pendingResetRefreshDate, batchDate)
            }
            configureQuotaResetRefresh(now: now)
            return
        }

        refresh(trigger: .quotaReset, startedAt: now)
    }

    private func consumeCoveredQuotaResets(through coveredAt: Date) {
        let coveredTargets = [
            RefreshPolicy.latestDueQuotaResetDate(in: snapshot, now: coveredAt),
            scheduledResetRefreshDate,
            pendingResetRefreshDate
        ].compactMap { $0 }.filter { $0 <= coveredAt }
        guard let latestCovered = coveredTargets.max() else { return }

        consumedResetRefreshDate = Self.latest(consumedResetRefreshDate, latestCovered)
        if let pendingResetRefreshDate, pendingResetRefreshDate <= latestCovered {
            self.pendingResetRefreshDate = nil
        }
        if let scheduledResetRefreshDate, scheduledResetRefreshDate <= latestCovered {
            cancelScheduledQuotaResetRefresh()
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
        cancelScheduledQuotaResetRefresh()
        pendingResetRefreshDate = nil
        consumedResetRefreshDate = nil
    }

    private func cancelScheduledQuotaResetRefresh() {
        resetRefreshTask?.cancel()
        resetRefreshTask = nil
        scheduledResetRefreshDate = nil
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
