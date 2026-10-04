import Combine
import Foundation
import OSLog

/// Owns the three Claude sources as separate slots: Claude Code's local usage
/// cache (primary), the statusline bridge (backup) and the optional CLI reader
/// (last option). Exactly one report is projected at a time.
@MainActor
final class ClaudeQuotaStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastIssue: ClaudeQuotaIssue?
    @Published private(set) var source: ClaudeQuotaSource?
    @Published private(set) var reportedAt: Date?
    @Published private(set) var isEnabled = false
    @Published private(set) var nextAutomaticRefreshAt: Date?
    @Published private(set) var passiveReportNeedsConfirmation = false
    @Published private(set) var pendingPassiveReportedAt: Date?
    @Published private(set) var statuslineSetupState: ClaudeStatuslineSetupState = .notInstalled
    @Published private(set) var localCacheState: ClaudeLocalUsageCacheState = .absent
    @Published private(set) var lastCLIReadIssue: ClaudeQuotaIssue?
    @Published private(set) var lastCLIReadAt: Date?
    var isStatuslineInstalled: Bool { statuslineSetupState == .installed }
    var isCLIUsageEnabled: Bool { preferences.claudeCLIUsageEnabled }
    var canReadOnceWithCLI: Bool { isEnabled && !stopped && requestTask == nil }
    let notificationController: NotificationController

    private let preferences: PreferencesStore
    private let cache: ClaudeStatuslineCache
    private let installer: ClaudeStatuslineInstaller
    private let localCacheReader: ClaudeLocalUsageCacheReader
    private let fetcherFactory: @Sendable () -> any ClaudeQuotaFetching
    private var fetcher: (any ClaudeQuotaFetching)?
    /// The current fetcher exists only for one explicit read and retires afterwards.
    private var oneShotFetcher = false
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let now: @Sendable () -> Date
    private let maximumReportAge: TimeInterval
    private let localCacheMaximumAge: TimeInterval
    private var localReport: ClaudeQuotaReport?
    private var localAccountID: UUID?
    private var localStamp: ClaudeLocalUsageCacheStamp?
    private var passiveReport: ClaudeQuotaReport?
    private var passiveIssue: ClaudeQuotaIssue?
    private var cliReport: ClaudeQuotaReport?
    private var report: ClaudeQuotaReport?
    private var lastNotifiedReport: ClaudeQuotaReport?
    private var pendingPassiveReport: ClaudeQuotaReport?
    private var policy = QuotaNotificationPolicy()
    private var requestTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var generation = 0
    private var stopped = false
    private var activeReadIssue: ClaudeQuotaIssue?
    private var nextBackgroundRefreshAt: Date?
    private var resetContext: ResetContext?
    private var resetTargets: [Date] = []
    private var resetCoveredAt: Date?
    private let cleanup = DispatchQueue(label: "com.defyan94.codex94.claude-cleanup", qos: .utility)
    private let logger = Logger(subsystem: "com.defyan94.codex94", category: "claude-state")

    init(
        preferences: PreferencesStore,
        cache: ClaudeStatuslineCache = ClaudeStatuslineCache(),
        installer: ClaudeStatuslineInstaller? = nil,
        localCache: ClaudeLocalUsageCacheReader? = nil,
        fetcherFactory: @escaping @Sendable () -> any ClaudeQuotaFetching = { ClaudeCLIUsageClient() },
        notificationController: NotificationController = NotificationController(),
        maximumReportAge: TimeInterval = 600,
        localCacheMaximumAge: TimeInterval = ClaudeQuotaFreshnessPolicy.localCacheMaximumAge,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) {
        self.preferences = preferences
        self.cache = cache
        self.installer = installer ?? ClaudeStatuslineInstaller(cache: cache)
        self.localCacheReader = localCache ?? ClaudeLocalUsageCacheReader()
        self.fetcherFactory = fetcherFactory
        self.notificationController = notificationController
        self.maximumReportAge = maximumReportAge
        self.localCacheMaximumAge = localCacheMaximumAge
        self.now = now
        self.sleep = sleep ?? Self.sleepForPolling
    }

    deinit {
        requestTask?.cancel()
        pollingTask?.cancel()
        fetcher?.shutdown()
        cleanup.sync {}
    }

    func start() {
        guard !stopped, !isEnabled, preferences.claudeMonitoringEnabled else { return }
        fetcher = preferences.claudeCLIUsageEnabled ? fetcherFactory() : nil
        oneShotFetcher = false
        isEnabled = true
        logger.info("monitor=started")
        notificationController.configure(enabled: preferences.claudeNotifications.isEnabled)
        refreshSetupState()
        if let cliReport, isCLIUsageEnabled { updateResetSchedule(from: cliReport) }
        readLocalCache()
        loadBridgeReport()
        projectReport(at: now())
        armPolling()
        refresh(trigger: .launch)
    }

    /// Disable is reversible. Retired clients cannot complete into the next generation.
    func stop() {
        guard !stopped else { return }
        retireCLIRequest()
        pollingTask?.cancel()
        pollingTask = nil
        isEnabled = false
        logger.info("monitor=stopped")
        nextBackgroundRefreshAt = nil
        clearResetSchedule()
        clearPendingPassiveReport()
        nextAutomaticRefreshAt = nil
        policy.reset()
        lastNotifiedReport = nil
        notificationController.configure(enabled: false)
        // The cache is read only while monitoring is on; a disabled monitor must
        // not publish a state that was never re-examined.
        localStamp = nil
        localReport = nil
        localAccountID = nil
        localCacheState = .absent
    }

    func shutdown() {
        guard !stopped else { return }
        stop()
        stopped = true
        cleanup.sync {}
        notificationController.shutdown()
    }

    /// Passive sources are reread on every trigger. The CLI reader joins only
    /// while its option is on and no read is already in flight.
    func refresh(trigger: RefreshTrigger = .manual) {
        guard isEnabled, !stopped else { return }
        readLocalCache()
        loadBridgeReport()
        guard preferences.claudeCLIUsageEnabled, requestTask == nil, let currentFetcher = fetcher else {
            projectReport(at: now())
            updateNextAutomaticRefresh()
            return
        }
        startCLIRead(using: currentFetcher, trigger: trigger, oneShot: false)
    }

    /// One explicit CLI read, independent of the automatic option. While the
    /// option is off, the client exists only for this read and retires afterwards.
    func readOnceWithCLI() {
        guard canReadOnceWithCLI else { return }
        readLocalCache()
        loadBridgeReport()
        let client: any ClaudeQuotaFetching
        if let fetcher {
            client = fetcher
        } else {
            client = fetcherFactory()
            fetcher = client
            oneShotFetcher = true
        }
        startCLIRead(using: client, trigger: .manual, oneShot: !preferences.claudeCLIUsageEnabled)
    }

    private func startCLIRead(using currentFetcher: any ClaudeQuotaFetching, trigger: RefreshTrigger, oneShot: Bool) {
        let expectedGeneration = generation
        let startedAt = ProcessInfo.processInfo.systemUptime
        let requestStartedAt = now()
        logger.info("refresh=started trigger=\(trigger.rawValue, privacy: .public) once=\(oneShot, privacy: .public)")
        isRefreshing = true
        lastCLIReadIssue = nil
        if !oneShot {
            nextBackgroundRefreshAt = requestStartedAt.addingTimeInterval(preferences.claudeRefreshInterval.seconds)
            coverResets(through: requestStartedAt)
        }
        projectReport(at: requestStartedAt)
        updateNextAutomaticRefresh()
        requestTask = Task { [weak self] in
            guard !Task.isCancelled, self?.generation == expectedGeneration, self?.isEnabled == true else { return }
            do {
                let value = try await currentFetcher.fetch()
                guard let self, !Task.isCancelled, generation == expectedGeneration, isEnabled, !stopped else { return }
                acceptCLI(value, requestStartedAt: oneShot ? nil : requestStartedAt)
                logRefresh(trigger: trigger, startedAt: startedAt, issue: lastCLIReadIssue)
            } catch {
                guard let self, !Task.isCancelled, generation == expectedGeneration, isEnabled, !stopped else { return }
                let issue = (error as? ClaudeQuotaIssue) ?? .unavailable
                // A one-time read reports its failure beside its button only.
                if !oneShot { activeReadIssue = issue }
                lastCLIReadIssue = issue
                if issue == .loginRequired {
                    // A rejected login invalidates the CLI's own data and schedule;
                    // passive reports keep their own, separately labelled, state.
                    cliReport = nil
                    clearResetSchedule()
                    policy.reset()
                    lastNotifiedReport = nil
                    notificationController.configure(enabled: preferences.claudeNotifications.isEnabled)
                }
                projectReport(at: now())
                logRefresh(trigger: trigger, startedAt: startedAt, issue: issue)
            }
            guard let self, generation == expectedGeneration, !stopped else { return }
            lastCLIReadAt = now()
            isRefreshing = false
            requestTask = nil
            if oneShotFetcher, !preferences.claudeCLIUsageEnabled {
                let retired = fetcher
                fetcher = nil
                oneShotFetcher = false
                cleanup.async { retired?.shutdown() }
            }
            updateNextAutomaticRefresh()
        }
    }

    func popoverWillOpen(now: Date = Date()) {
        guard report.map({ now.timeIntervalSince($0.reportedAt) >= 60 }) ?? true else { return }
        refresh(trigger: .popover)
    }

    func handleSystemWake(now: Date = Date()) {
        guard isEnabled else { return }
        projectReport(at: now)
        armPolling()
        refresh(trigger: .systemWake)
    }

    func handleSystemClockChange(now: Date = Date()) {
        guard isEnabled else { return }
        projectReport(at: now)
        nextBackgroundRefreshAt = preferences.claudeCLIUsageEnabled
            ? now.addingTimeInterval(preferences.claudeRefreshInterval.seconds) : nil
        // A wall-clock rollback must not make an already attempted target new.
        updateNextAutomaticRefresh()
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        preferences.claudeRefreshInterval = interval
        if isEnabled { armPolling() }
    }

    /// Turning the option off retires the client and drops its data; the two
    /// passive sources are untouched either way.
    func setCLIUsageEnabled(_ enabled: Bool) {
        guard preferences.claudeCLIUsageEnabled != enabled else { return }
        preferences.claudeCLIUsageEnabled = enabled
        guard !stopped else { return }
        retireCLIRequest()
        activeReadIssue = nil
        lastCLIReadIssue = nil
        nextBackgroundRefreshAt = nil
        clearResetSchedule()
        cliReport = nil
        policy.reset()
        lastNotifiedReport = nil
        notificationController.configure(enabled: isEnabled && preferences.claudeNotifications.isEnabled)
        guard isEnabled else { updateNextAutomaticRefresh(); return }
        if enabled { fetcher = fetcherFactory() }
        armPolling()
        projectReport(at: now())
        if enabled { refresh(trigger: .preferenceChange) }
    }

    private func retireCLIRequest() {
        generation += 1
        requestTask?.cancel()
        requestTask = nil
        isRefreshing = false
        let retired = fetcher
        fetcher = nil
        oneShotFetcher = false
        cleanup.async { retired?.shutdown() }
    }

    func adoptPendingPassiveReport() {
        guard isEnabled, !stopped, let pending = pendingPassiveReport else { return }
        // Adopt the frozen report shown by the confirmation UI, never a newer
        // cache value that may have arrived while the dialog was open.
        clearPendingPassiveReport()
        let date = now()
        guard pending.reportedAt <= date.addingTimeInterval(5), pending.receivedAt >= pending.reportedAt else {
            passiveIssue = .invalidData
            projectReport(at: date)
            return
        }
        guard pending.snapshot(at: date) != nil else {
            if passiveReport == nil { passiveIssue = .staleData }
            projectReport(at: date)
            return
        }
        preferences.setClaudePassiveProducerID(ClaudeStatuslineParser.identifiableProducerID(pending.producerID))
        passiveReport = nil
        policy.reset()
        lastNotifiedReport = nil
        notificationController.configure(enabled: preferences.claudeNotifications.isEnabled)
        acceptPassive(pending)
        projectReport(at: date)
    }

    private func clearPendingPassiveReport() {
        pendingPassiveReport = nil
        pendingPassiveReportedAt = nil
        passiveReportNeedsConfirmation = false
    }

    private func requireConfirmation(for value: ClaudeQuotaReport) {
        guard pendingPassiveReport == nil else { return }
        pendingPassiveReport = value
        pendingPassiveReportedAt = value.reportedAt
        passiveReportNeedsConfirmation = true
        policy.reset()
        lastNotifiedReport = nil
        notificationController.configure(enabled: preferences.claudeNotifications.isEnabled)
    }

    func setNotificationPreferences(_ value: NotificationPreferences) {
        let old = preferences.claudeNotifications
        preferences.claudeNotifications = value.validated
        policy.reset()
        lastNotifiedReport = nil
        notificationController.configure(enabled: isEnabled && value.isEnabled,
                                         requestPermission: isEnabled && value.isEnabled && !old.isEnabled)
    }

    func requestNotificationPermission() {
        guard isEnabled, preferences.claudeNotifications.isEnabled else { return }
        notificationController.configure(enabled: true, requestPermission: true)
    }

    func refreshNotificationAuthorization() { notificationController.refreshAuthorization() }

    func refreshSetupState() { statuslineSetupState = installer.setupState }

    func previewStatuslineInstall() throws -> ClaudeStatuslineInstallPreview {
        defer { refreshSetupState() }
        return try installer.previewInstall()
    }

    func installStatusline(_ preview: ClaudeStatuslineInstallPreview) throws {
        defer { refreshSetupState() }
        try installer.install(preview)
    }

    func removeStatusline() throws {
        defer { refreshSetupState() }
        try installer.remove()
    }

    func forgetConflictingStatuslineInstallation() throws {
        defer { refreshSetupState() }
        try installer.forgetConflictingInstallation()
    }

    private func armPolling() {
        pollingTask?.cancel()
        let expectedGeneration = generation
        nextBackgroundRefreshAt = preferences.claudeCLIUsageEnabled
            ? now().addingTimeInterval(preferences.claudeRefreshInterval.seconds) : nil
        updateNextAutomaticRefresh()
        pollingTask = Task { [weak self, sleep] in
            while !Task.isCancelled {
                do { try await sleep(15) } catch { return }
                guard !Task.isCancelled else { return }
                guard self?.poll(generation: expectedGeneration) == true else { return }
            }
        }
    }

    private func poll(generation expectedGeneration: Int) -> Bool {
        guard isEnabled, !stopped, expectedGeneration == generation else { return false }
        readLocalCache()
        loadBridgeReport()
        let date = now()
        projectReport(at: date)
        updateNextAutomaticRefresh()
        if let nextAutomaticRefreshAt, nextAutomaticRefreshAt <= date {
            let trigger: RefreshTrigger = nextResetRefreshAt == nextAutomaticRefreshAt ? .quotaReset : .background
            refresh(trigger: trigger)
        }
        return true
    }

    // MARK: Primary source: Claude Code's local usage cache

    private func readLocalCache() {
        let date = now()
        let reading = localCacheReader.read(now: date, unchangedSince: localStamp)
        switch reading.outcome {
        case .unchanged:
            return
        case .absent:
            localStamp = nil
            localReport = nil
            localAccountID = nil
            localCacheState = .absent
        case .unreadable:
            localStamp = reading.stamp
            localReport = nil
            localAccountID = nil
            localCacheState = .unreadable
        case .unparsable:
            // A rewrite in progress or a corrupt file: keep the last good report
            // as a candidate but describe what is on disk now. A completed write
            // changes the stamp and is parsed on the next poll.
            localStamp = reading.stamp
            localCacheState = .invalid
        case .invalid:
            // The file decoded but holds no usable cache, for example after
            // `/logout` or a layout change: the previous report no longer
            // describes this file and is dropped.
            localStamp = reading.stamp
            localReport = nil
            localCacheState = .invalid
        case let .report(value, accountID):
            localStamp = reading.stamp
            guard value.reportedAt <= date.addingTimeInterval(5), value.receivedAt >= value.reportedAt else {
                // A fetch time in the future is a clock problem, not usage data.
                localCacheState = .invalid
                return
            }
            if let previous = localAccountID, previous != accountID {
                // Another login's cache is a different stream: start a fresh
                // notification baseline. The identifier itself is never stored.
                policy.reset()
                lastNotifiedReport = nil
                notificationController.configure(enabled: preferences.claudeNotifications.isEnabled)
                logger.info("source=localCache account=changed")
            }
            localAccountID = accountID
            let unchanged = localReport.map {
                $0.reportedAt == value.reportedAt && $0.windows == value.windows && $0.modelLimits == value.modelLimits
            } ?? false
            if !unchanged {
                localReport = value
                logger.info("source=localCache result=updated")
            }
            localCacheState = .valid
        }
    }

    // MARK: Backup source: statusline bridge reports

    private func loadBridgeReport() {
        // The pending candidate stays frozen, but the selected producer can
        // still publish newer values while another report awaits confirmation.
        guard let value = try? cache.load() else { return }
        guard value.snapshot(at: now()) != nil else { return }
        guard value.reportedAt <= now().addingTimeInterval(5) else { passiveIssue = .invalidData; return }
        let producer = ClaudeStatuslineParser.identifiableProducerID(value.producerID)
        let selected = ClaudeStatuslineParser.identifiableProducerID(preferences.claudePassiveProducerID)
        if producer == nil {
            // An explicitly adopted anonymous report may be reread unchanged,
            // but its shared placeholder never authorizes a different report.
            if let passiveReport, passiveReport.producerID == value.producerID,
               passiveReport.reportedAt == value.reportedAt, passiveReport.windows == value.windows { return }
            requireConfirmation(for: value)
            return
        }
        if let selected {
            guard producer == selected else { requireConfirmation(for: value); return }
        } else {
            guard passiveReport == nil else { requireConfirmation(for: value); return }
            preferences.setClaudePassiveProducerID(producer)
        }
        if passiveReport == nil || value.reportedAt > passiveReport!.reportedAt { acceptPassive(value) }
    }

    private func acceptPassive(_ value: ClaudeQuotaReport) {
        guard value.source == .statusline,
              value.reportedAt <= now().addingTimeInterval(5),
              value.receivedAt >= value.reportedAt else { passiveIssue = .invalidData; return }
        if let passiveReport, passiveReport.producerID != value.producerID {
            policy.reset()
            lastNotifiedReport = nil
            notificationController.configure(enabled: preferences.claudeNotifications.isEnabled)
        }
        passiveIssue = nil
        if passiveReport != value { logger.info("source=statusline result=reported") }
        passiveReport = value
    }

    // MARK: Last option: the CLI reader

    /// `requestStartedAt` is nil for a one-time read, whose failures are
    /// reported beside its button and never drive the card.
    private func acceptCLI(_ value: ClaudeQuotaReport, requestStartedAt: Date?) {
        let oneShot = requestStartedAt == nil
        guard value.source == .cliUsage,
              value.reportedAt <= now().addingTimeInterval(5),
              value.receivedAt >= value.reportedAt else {
            if !oneShot { activeReadIssue = .invalidData }
            lastCLIReadIssue = .invalidData
            projectReport(at: now())
            return
        }
        guard value.snapshot(at: now()) != nil else {
            // A response begun before reset can contain only expired windows.
            // Keep its scheduling evidence without presenting expired quota.
            updateResetSchedule(from: value, requestStartedAt: requestStartedAt)
            if !oneShot { activeReadIssue = .noData }
            lastCLIReadIssue = .noData
            projectReport(at: now())
            return
        }
        updateResetSchedule(from: value, requestStartedAt: requestStartedAt)
        activeReadIssue = nil
        lastCLIReadIssue = nil
        if cliReport != value { logger.info("source=cliUsage result=reported") }
        cliReport = value
        projectReport(at: now())
    }

    // MARK: Projection

    private func isCurrent(_ value: ClaudeQuotaReport, at date: Date) -> Bool {
        ClaudeQuotaFreshnessPolicy.isCurrent(
            value, at: date, baseline: maximumReportAge,
            refreshInterval: preferences.claudeRefreshInterval.seconds, localCache: localCacheMaximumAge
        )
    }

    /// Selects one report, projects it and evaluates notifications once per new
    /// current report. All tiers describe the same account's windows, so a tier
    /// switch keeps the notification baseline; only an identity change resets it
    /// (a different cache account in `readLocalCache`, a different statusline
    /// producer in `acceptPassive`/`requireConfirmation`, a rejected CLI login).
    private func projectReport(at date: Date) {
        let selected = ClaudeQuotaFreshnessPolicy.select(localCache: localReport, statusline: passiveReport, cli: cliReport)
        report = selected
        source = selected?.source
        reportedAt = selected?.reportedAt
        guard let selected else {
            snapshot = nil
            if passiveReportNeedsConfirmation { setIssue(.sourceChanged) }
            else if let activeReadIssue { setIssue(activeReadIssue) }
            else if localCacheState == .unreadable { setIssue(.localCacheUnreadable) }
            else if let passiveIssue { setIssue(passiveIssue) }
            else { lastIssue = nil; connectionState = .idle }
            return
        }
        snapshot = selected.snapshot(at: date)
        let current = isCurrent(selected, at: date)
        // An automatic CLI failure is reported while CLI data is what is shown,
        // or while the shown passive data is itself out of date: the failure
        // explains why nothing fresher exists. Current passive data keeps its
        // own state, and one-time reads never set `activeReadIssue`.
        if passiveReportNeedsConfirmation, selected.source == .statusline { setIssue(.sourceChanged) }
        else if snapshot == nil { setIssue(.noData) }
        else if let activeReadIssue, selected.source == .cliUsage || (!current && activeReadIssue != .noData) {
            setIssue(activeReadIssue)
        }
        else if current { lastIssue = nil; connectionState = .connected }
        else { setIssue(.staleData) }

        guard let snapshot, current, lastNotifiedReport != selected,
              !passiveReportNeedsConfirmation || selected.source != .statusline else { return }
        lastNotifiedReport = selected
        let events = policy.events(for: snapshot, preferences: preferences.claudeNotifications)
        notificationController.deliver(events, language: preferences.language, provider: .claude)
    }

    private func setIssue(_ issue: ClaudeQuotaIssue) {
        lastIssue = issue
        if let snapshot { connectionState = .stale(lastSuccess: snapshot.fetchedAt, issue: .quotaUnavailable) }
        else { connectionState = .unavailable(issue == .loginRequired ? .notLoggedIn : .quotaUnavailable) }
    }

    // MARK: CLI reset scheduling

    private struct ResetContext: Equatable {
        let source: ClaudeQuotaSource
        let producerID: String?
    }

    private var nextResetRefreshAt: Date? {
        resetTargets.first { target in resetCoveredAt.map { target > $0 } ?? true }
    }

    private func updateResetSchedule(from value: ClaudeQuotaReport, requestStartedAt: Date? = nil) {
        let context = ResetContext(source: value.source, producerID: value.producerID)
        if resetContext != context {
            resetContext = context
            resetCoveredAt = nil
        }
        resetTargets = Array(Set(value.windows.compactMap { window -> Date? in
            guard let reset = window.resetsAt, reset.timeIntervalSince1970.isFinite else { return nil }
            let target = reset.addingTimeInterval(RefreshPolicy.quotaResetDelay)
            return target.timeIntervalSince1970.isFinite ? target : nil
        })).sorted()
        if let requestStartedAt { coverResets(through: requestStartedAt) }
        updateNextAutomaticRefresh()
    }

    private func coverResets(through requestStartedAt: Date) {
        guard resetContext != nil else { return }
        // Only an accepted read covers due targets; completion and passive file
        // receipt times cannot consume a reset that occurred while it was busy.
        resetCoveredAt = max(resetCoveredAt ?? requestStartedAt, requestStartedAt)
    }

    private func clearResetSchedule() {
        resetContext = nil
        resetTargets = []
        resetCoveredAt = nil
    }

    private func updateNextAutomaticRefresh() {
        guard isEnabled, !stopped, preferences.claudeCLIUsageEnabled else { nextAutomaticRefreshAt = nil; return }
        // These are due times. The existing 15-second poll performs the read
        // after the earliest deadline; no additional reset timer is created.
        nextAutomaticRefreshAt = [nextBackgroundRefreshAt, nextResetRefreshAt].compactMap { $0 }.min()
    }

    private func logRefresh(trigger: RefreshTrigger, startedAt: TimeInterval, issue: ClaudeQuotaIssue?) {
        let milliseconds = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
        if let issue {
            logger.error("refresh=finished trigger=\(trigger.rawValue, privacy: .public) source=cliUsage result=failure issue=\(issue.rawValue, privacy: .public) duration_ms=\(milliseconds, privacy: .public)")
        } else {
            logger.info("refresh=finished trigger=\(trigger.rawValue, privacy: .public) source=cliUsage result=success duration_ms=\(milliseconds, privacy: .public)")
        }
    }

    nonisolated private static func sleepForPolling(_ delay: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(delay))
    }
}
