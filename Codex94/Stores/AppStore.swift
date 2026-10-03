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
    @Published private(set) var nextRetryAt: Date?
    @Published private(set) var nextBackgroundRefreshAt: Date?

    let preferences: PreferencesStore
    let usageStore: TokenUsageStore
    let claudeStore: ClaudeQuotaStore
    let updates = AppUpdateController()
    let launchAtLogin: LaunchAtLoginController
    let hotKeyController: GlobalHotKeyController
    let notificationController: NotificationController
    private var notificationPolicy = QuotaNotificationPolicy()

    private let locator: CodexExecutableLocator
    private let fetcher: any QuotaFetching
    private let cache: SnapshotCache
    private let retrySleep: @Sendable (TimeInterval) async throws -> Void
    private let backgroundSleep: @Sendable (TimeInterval) async throws -> Void
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
    private var claudeObservation: AnyCancellable?
    private var codexStopTask: Task<Void, Never>?
    private var isShuttingDown = false
    private var connectionGeneration = 0
    private var automaticRetryTask: Task<Void, Never>?
    private var automaticRetryGeneration = 0
    private var automaticRetryAttempt = 0
    private var backgroundGeneration = 0
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
        claudeStore: ClaudeQuotaStore? = nil,
        retrySleep: (@Sendable (TimeInterval) async throws -> Void)? = nil,
        backgroundSleep: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) {
        self.preferences = preferences
        self.usageStore = usageStore ?? TokenUsageStore(preferences: preferences)
        self.claudeStore = claudeStore ?? ClaudeQuotaStore(preferences: preferences)
        self.launchAtLogin = launchAtLogin
        self.locator = locator
        self.fetcher = fetcher
        self.cache = cache
        self.retrySleep = retrySleep ?? RefreshPolicy.sleepBeforeRetry
        self.backgroundSleep = backgroundSleep ?? RefreshPolicy.sleepBeforeBackgroundRefresh
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
        claudeObservation = self.claudeStore.objectWillChange.sink { [weak self] _ in
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

    /// Scheduled wall-clock estimates, not a guarantee of execution while the
    /// system is asleep or delaying this process. Reading this never starts work.
    var nextAutomaticRefreshAt: Date? {
        guard !isShuttingDown, preferences.codexMonitoringEnabled,
              preferences.hasChosenIdentityMode else { return nil }
        // After a wall-clock change an armed relative sleep may have an unknown
        // wall date. Another known deadline cannot honestly be called "next".
        guard automaticRetryTask == nil || nextRetryAt != nil,
              backgroundTask == nil || nextBackgroundRefreshAt != nil else { return nil }
        return RefreshPolicy.nextAutomaticRefreshDate(
            issue: lastIssue,
            isRefreshing: isRefreshing,
            nextRetryAt: automaticRetryTask == nil ? nil : nextRetryAt,
            nextBackgroundRefreshAt: backgroundTask == nil ? nil : nextBackgroundRefreshAt,
            nextQuotaResetRefreshAt: resetRefreshTask == nil ? nil : scheduledResetRefreshDate,
            now: Date()
        )
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
        ProviderQuotaSelection.options(snapshot: snapshot, preferred: preferences.menuBarQuotaSelection)
    }

    func start() {
        guard !isShuttingDown else { return }
        if preferences.claudeMonitoringEnabled { claudeStore.start() }
        notificationController.configure(enabled: preferences.codexMonitoringEnabled && preferences.notifications.isEnabled)
        configureBackgroundRefresh()
        guard preferences.codexMonitoringEnabled, preferences.hasChosenIdentityMode else { return }
        let now = Date()
        configureQuotaResetRefresh(now: now)
        refresh(trigger: .launch, startedAt: now)
    }

    func setMonitoringEnabled(_ enabled: Bool, for provider: QuotaProviderID) {
        guard !isShuttingDown else { return }
        if provider == .claude {
            guard preferences.claudeMonitoringEnabled != enabled else { return }
            preferences.claudeMonitoringEnabled = enabled
            enabled ? claudeStore.start() : claudeStore.stop()
            return
        }
        guard preferences.codexMonitoringEnabled != enabled else { return }
        preferences.codexMonitoringEnabled = enabled
        if enabled {
            if let snapshot {
                connectionState = .stale(lastSuccess: snapshot.fetchedAt, issue: .unknown)
            }
            notificationController.configure(enabled: preferences.notifications.isEnabled)
            configureBackgroundRefresh()
            configureQuotaResetRefresh()
            refresh(trigger: .preferenceChange)
        } else {
            // Invalidate before cancelling so even a late transport result
            // cannot repopulate state, cache, notifications or Token statistics.
            invalidateConnectionContext()
            pendingRefreshTrigger = nil
            cancelBackgroundRefresh()
            clearQuotaResetRefreshState()
            let retiringRefresh = refreshTask
            retiringRefresh?.cancel()
            refreshTask = nil
            activeRefreshStartedAt = nil
            isRefreshing = false
            hasFetchedLiveSnapshot = false
            connectionState = .idle
            lastIssue = nil
            notificationController.configure(enabled: false)
            // Transport teardown is bounded, but must not freeze the menu bar.
            let fetcher = fetcher
            let locator = locator
            let previousStop = codexStopTask
            codexStopTask = Task {
                await previousStop?.value
                await Task.detached(priority: .utility) {
                    fetcher.cancelCurrentRequest()
                    locator.cancelCurrentRequest()
                }.value
                await retiringRefresh?.value
            }
        }
    }

    func refreshAll(trigger: RefreshTrigger = .manual) {
        if preferences.codexMonitoringEnabled { refresh(trigger: trigger) }
        if preferences.claudeMonitoringEnabled { claudeStore.refresh(trigger: trigger) }
    }

    func setClaudeRefreshInterval(_ interval: RefreshInterval) {
        claudeStore.setRefreshInterval(interval)
    }

    func setClaudeCLIUsageEnabled(_ enabled: Bool) {
        guard !isShuttingDown else { return }
        claudeStore.setCLIUsageEnabled(enabled)
    }

    func setClaudeSourceMode(_ mode: ClaudeQuotaSourceMode) {
        guard !isShuttingDown else { return }
        claudeStore.setSourceMode(mode)
    }

    func setClaudeStatuslineFallbackEnabled(_ enabled: Bool) {
        guard !isShuttingDown else { return }
        claudeStore.setStatuslineFallbackEnabled(enabled)
    }

    func setClaudeNotificationPreferences(_ value: NotificationPreferences) {
        setNotificationPreferences(value, for: .claude)
    }

    func refresh(trigger: RefreshTrigger, startedAt: Date = Date()) {
        guard !isShuttingDown else { return }
        guard preferences.codexMonitoringEnabled, preferences.hasChosenIdentityMode else { return }
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
        let pendingStop = codexStopTask

        refreshTask = Task { [weak self] in
            await pendingStop?.value
            guard let self, !isShuttingDown else { return }
            guard !Task.isCancelled else { return }
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
        if preferences.claudeMonitoringEnabled { claudeStore.popoverWillOpen(now: now) }
        guard preferences.codexMonitoringEnabled else { return }
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
        if preferences.claudeMonitoringEnabled { claudeStore.handleSystemWake(now: now) }
        configureBackgroundRefresh()
        guard preferences.codexMonitoringEnabled, preferences.hasChosenIdentityMode else { return }
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
        if preferences.claudeMonitoringEnabled { claudeStore.handleSystemClockChange(now: now) }
        // Relative sleeps keep their existing budget. The old wall-clock
        // estimates are no longer reliable; publish a date when next armed.
        nextRetryAt = nil
        nextBackgroundRefreshAt = nil
        guard preferences.codexMonitoringEnabled, preferences.hasChosenIdentityMode else { return }
        _ = reconcileQuotaResetRefresh(now: now)
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        pendingRefreshTrigger = nil
        cancelAutomaticRetry()

        cancelBackgroundRefresh()
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
        claudeStore.shutdown()
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

    func setMenuBarQuotaSelection(_ selection: MenuBarQuotaSelection, for provider: QuotaProviderID = .codex) {
        guard menuBarQuotaOptions(for: provider).contains(where: {
            $0.selection == selection && $0.isAvailable
        }) else { return }
        if provider == .codex { preferences.menuBarQuotaSelection = selection }
        else { preferences.claudeMenuBarQuotaSelection = selection }
    }

    func setDualWindowBucketSelection(_ selection: MenuBarBucketSelection, for provider: QuotaProviderID = .codex) {
        guard selection == .automatic || providerSnapshot(for: provider).flatMap({ selection.resolved(in: $0) }) != nil else { return }
        if provider == .codex { preferences.dualWindowBucketSelection = selection }
        else { preferences.claudeDualWindowBucketSelection = selection }
    }

    @discardableResult
    func setGlobalHotKey(_ value: GlobalHotKey?) -> Bool {
        guard hotKeyController.setHotKey(value) else { return false }
        preferences.globalHotKey = value
        return true
    }

    func setNotificationPreferences(_ value: NotificationPreferences, for provider: QuotaProviderID = .codex) {
        if provider == .claude {
            claudeStore.setNotificationPreferences(value)
            return
        }
        let previous = preferences.notifications
        let value = value.validated
        guard value != previous else { return }
        preferences.notifications = value
        notificationPolicy.reset()
        notificationController.configure(
            enabled: preferences.codexMonitoringEnabled && value.isEnabled,
            requestPermission: preferences.codexMonitoringEnabled && value.isEnabled && !previous.isEnabled
        )
    }

    func requestNotificationPermission(for provider: QuotaProviderID = .codex) {
        if provider == .claude {
            claudeStore.requestNotificationPermission()
            return
        }
        guard preferences.codexMonitoringEnabled, preferences.notifications.isEnabled else { return }
        notificationController.configure(enabled: true, requestPermission: true)
    }

    func refreshNotificationAuthorization(for provider: QuotaProviderID = .codex) {
        if provider == .claude {
            claudeStore.notificationController.refreshAuthorization()
            return
        }
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
            lastError: lastIssue?.rawValue,
            enabledProviders: preferences.enabledProviders,
            menuBarServices: preferences.menuBarServiceMode,
            claudeConnection: preferences.claudeMonitoringEnabled
                ? Self.connectionLabel(claudeStore.connectionState) : "disabled",
            claudeSource: preferences.claudeMonitoringEnabled ? claudeStore.source : nil,
            claudeIssue: preferences.claudeMonitoringEnabled ? claudeStore.lastIssue : nil,
            claudeLastReport: preferences.claudeMonitoringEnabled ? claudeStore.reportedAt : nil
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
              preferences.codexMonitoringEnabled,
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
              preferences.codexMonitoringEnabled,
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
                scheduleAutomaticRetry(for: failureIssue, generation: retryGeneration, now: now)
            }
        }
    }

    private func cancelAutomaticRetry() {
        automaticRetryTask?.cancel()
        automaticRetryTask = nil
        if nextRetryAt != nil { nextRetryAt = nil }
        automaticRetryGeneration += 1
        automaticRetryAttempt = 0
    }

    private func scheduleAutomaticRetry(for issue: ConnectionIssue, generation: Int, now: Date) {
        guard !isShuttingDown, preferences.codexMonitoringEnabled, generation == automaticRetryGeneration,
              let delay = RefreshPolicy.automaticRetryDelay(
                for: issue, completedRetries: automaticRetryAttempt
              ) else { return }
        automaticRetryAttempt += 1
        nextRetryAt = now.addingTimeInterval(delay)
        let requestGeneration = connectionGeneration
        logger.info("refresh=retry_scheduled attempt=\(self.automaticRetryAttempt, privacy: .public)")
        automaticRetryTask = Task { [weak self, retrySleep] in
            do {
                try await retrySleep(delay)
            } catch {
                guard let self, generation == automaticRetryGeneration else { return }
                automaticRetryTask = nil
                nextRetryAt = nil
                return
            }
            guard !Task.isCancelled, let self, !isShuttingDown,
                  generation == automaticRetryGeneration,
                  requestGeneration == connectionGeneration else { return }
            automaticRetryTask = nil
            nextRetryAt = nil
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
              preferences.codexMonitoringEnabled,
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
        cancelBackgroundRefresh()
        guard !isShuttingDown, preferences.codexMonitoringEnabled else { return }
        let interval = preferences.refreshInterval.seconds
        let generation = backgroundGeneration
        backgroundTask = Task { [weak self, backgroundSleep] in
            while !Task.isCancelled {
                guard self?.armBackgroundEstimate(interval: interval, generation: generation) == true else { return }
                do {
                    try await backgroundSleep(interval)
                } catch {
                    guard let self, generation == backgroundGeneration else { return }
                    backgroundTask = nil
                    nextBackgroundRefreshAt = nil
                    return
                }
                guard !Task.isCancelled, let self, !isShuttingDown,
                      generation == backgroundGeneration else { return }
                nextBackgroundRefreshAt = nil
                refresh(trigger: .background)
            }
        }
    }

    private func cancelBackgroundRefresh() {
        backgroundTask?.cancel()
        backgroundTask = nil
        if nextBackgroundRefreshAt != nil { nextBackgroundRefreshAt = nil }
        backgroundGeneration += 1
    }

    private func armBackgroundEstimate(interval: TimeInterval, generation: Int) -> Bool {
        guard !isShuttingDown, generation == backgroundGeneration else { return false }
        nextBackgroundRefreshAt = Date().addingTimeInterval(interval)
        return true
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
