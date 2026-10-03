import Combine
import Foundation
import OSLog

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
    @Published private(set) var statuslineSetupState: ClaudeStatuslineSetupState = .notInstalled
    var isStatuslineInstalled: Bool { statuslineSetupState == .installed }
    let notificationController: NotificationController

    private let preferences: PreferencesStore
    private let cache: ClaudeStatuslineCache
    private let installer: ClaudeStatuslineInstaller
    private let fetcherFactory: @Sendable () -> any ClaudeQuotaFetching
    private var fetcher: (any ClaudeQuotaFetching)?
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let now: @Sendable () -> Date
    private let maximumReportAge: TimeInterval
    private var report: ClaudeQuotaReport?
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
        fetcherFactory: @escaping @Sendable () -> any ClaudeQuotaFetching = { ClaudeCLIUsageClient() },
        notificationController: NotificationController = NotificationController(),
        maximumReportAge: TimeInterval = 600,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) {
        self.preferences = preferences
        self.cache = cache
        self.installer = installer ?? ClaudeStatuslineInstaller(cache: cache)
        self.fetcherFactory = fetcherFactory
        self.notificationController = notificationController
        self.maximumReportAge = maximumReportAge
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
        fetcher = fetcherFactory()
        isEnabled = true
        logger.info("monitor=started")
        notificationController.configure(enabled: preferences.claudeNotifications.isEnabled)
        refreshSetupState()
        if let report { updateResetSchedule(from: report) }
        projectReport(at: now())
        loadBridgeReport()
        armPolling()
        refresh(trigger: .launch)
    }

    /// Disable is reversible. Retired clients cannot complete into the next generation.
    func stop() {
        guard !stopped else { return }
        generation += 1
        requestTask?.cancel()
        pollingTask?.cancel()
        requestTask = nil
        pollingTask = nil
        isEnabled = false
        logger.info("monitor=stopped")
        isRefreshing = false
        nextBackgroundRefreshAt = nil
        clearResetSchedule()
        nextAutomaticRefreshAt = nil
        let retired = fetcher
        fetcher = nil
        cleanup.async { retired?.shutdown() }
        policy.reset()
        notificationController.configure(enabled: false)
    }

    func shutdown() {
        guard !stopped else { return }
        stop()
        stopped = true
        cleanup.sync {}
        notificationController.shutdown()
    }

    func refresh(trigger: RefreshTrigger = .manual) {
        guard isEnabled, !stopped, requestTask == nil, let currentFetcher = fetcher else { return }
        let expectedGeneration = generation
        let startedAt = ProcessInfo.processInfo.systemUptime
        let requestStartedAt = now()
        logger.info("refresh=started trigger=\(trigger.rawValue, privacy: .public)")
        isRefreshing = true
        nextBackgroundRefreshAt = requestStartedAt.addingTimeInterval(preferences.claudeRefreshInterval.seconds)
        coverResets(through: requestStartedAt)
        updateNextAutomaticRefresh()
        requestTask = Task { [weak self] in
            do {
                let value = try await currentFetcher.fetch()
                guard let self, !Task.isCancelled, generation == expectedGeneration, isEnabled, !stopped else { return }
                accept(value, requestStartedAt: requestStartedAt)
                logRefresh(trigger: trigger, startedAt: startedAt, issue: lastIssue)
            } catch {
                guard let self, !Task.isCancelled, generation == expectedGeneration, isEnabled, !stopped else { return }
                let issue = (error as? ClaudeQuotaIssue) ?? .unavailable
                activeReadIssue = issue
                if issue == .loginRequired {
                    report = nil
                    snapshot = nil
                    reportedAt = nil
                    source = nil
                    clearResetSchedule()
                    policy.reset()
                    notificationController.configure(enabled: preferences.claudeNotifications.isEnabled)
                    setIssue(issue)
                } else {
                    loadBridgeReport()
                    if report?.source != .statusline || !isCurrent(report) { setIssue(issue) }
                }
                logRefresh(trigger: trigger, startedAt: startedAt, issue: issue)
            }
            guard let self, generation == expectedGeneration, !stopped else { return }
            isRefreshing = false
            requestTask = nil
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
        nextBackgroundRefreshAt = now.addingTimeInterval(preferences.claudeRefreshInterval.seconds)
        // A wall-clock rollback must not make an already attempted target new.
        updateNextAutomaticRefresh()
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        preferences.claudeRefreshInterval = interval
        if isEnabled { armPolling() }
    }

    func setNotificationPreferences(_ value: NotificationPreferences) {
        let old = preferences.claudeNotifications
        preferences.claudeNotifications = value.validated
        policy.reset()
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
        nextBackgroundRefreshAt = now().addingTimeInterval(preferences.claudeRefreshInterval.seconds)
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

    private func loadBridgeReport() {
        guard activeReadIssue != .loginRequired else { return }
        guard let value = try? cache.load() else { return }
        guard value.snapshot(at: now()) != nil else { return }
        if report == nil || value.reportedAt > report!.reportedAt { accept(value) }
    }

    private func accept(_ value: ClaudeQuotaReport, requestStartedAt: Date? = nil) {
        guard value.reportedAt <= now().addingTimeInterval(5),
              value.receivedAt >= value.reportedAt else { setIssue(.invalidData); return }
        guard value.snapshot(at: now()) != nil else {
            if value.source == .cliUsage {
                // A response begun before reset can contain only expired windows.
                // Keep its scheduling evidence without presenting expired quota.
                updateResetSchedule(from: value, requestStartedAt: requestStartedAt)
                activeReadIssue = .noData
                setIssue(.noData)
            }
            return
        }
        updateResetSchedule(from: value, requestStartedAt: requestStartedAt)
        let isNew = report != value && (report?.reportedAt != value.reportedAt || report?.windows != value.windows)
        if report?.source != value.source || report?.producerID != value.producerID {
            policy.reset()
            notificationController.configure(enabled: preferences.claudeNotifications.isEnabled)
        }
        activeReadIssue = nil
        report = value
        reportedAt = value.reportedAt
        source = value.source
        projectReport(at: now())
        if isNew, value.source == .statusline { logger.info("source=statusline result=reported") }
        if isNew, isCurrent(value), let snapshot {
            let events = policy.events(for: snapshot, preferences: preferences.claudeNotifications)
            notificationController.deliver(events, language: preferences.language, provider: .claude)
        }
    }

    private func isCurrent(_ value: ClaudeQuotaReport?, at referenceDate: Date? = nil) -> Bool {
        guard let value else { return false }
        let date = referenceDate ?? now()
        let age = date.timeIntervalSince(value.reportedAt)
        let allowedAge = value.source == .cliUsage
            ? max(maximumReportAge, preferences.claudeRefreshInterval.seconds + 60) : maximumReportAge
        return age >= 0 && age <= allowedAge && value.snapshot(at: date) != nil
    }

    private func projectReport(at date: Date) {
        guard let report else { return }
        snapshot = report.snapshot(at: date)
        if snapshot == nil { setIssue(.noData) }
        else if let activeReadIssue, report.source != .statusline || !isCurrent(report, at: date) { setIssue(activeReadIssue) }
        else if isCurrent(report, at: date) { lastIssue = nil; connectionState = .connected }
        else { setIssue(.staleData) }
    }

    private func setIssue(_ issue: ClaudeQuotaIssue) {
        lastIssue = issue
        if let snapshot { connectionState = .stale(lastSuccess: snapshot.fetchedAt, issue: .quotaUnavailable) }
        else { connectionState = .unavailable(issue == .loginRequired ? .notLoggedIn : .quotaUnavailable) }
    }

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
        guard isEnabled, !stopped else { nextAutomaticRefreshAt = nil; return }
        // These are due times. The existing 15-second poll performs the read
        // after the earliest deadline; no additional reset timer is created.
        nextAutomaticRefreshAt = [nextBackgroundRefreshAt, nextResetRefreshAt].compactMap { $0 }.min()
    }

    private func logRefresh(trigger: RefreshTrigger, startedAt: TimeInterval, issue: ClaudeQuotaIssue?) {
        let milliseconds = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
        let sourceName = source?.rawValue ?? "none"
        if let issue {
            logger.error("refresh=finished trigger=\(trigger.rawValue, privacy: .public) source=\(sourceName, privacy: .public) result=failure issue=\(issue.rawValue, privacy: .public) duration_ms=\(milliseconds, privacy: .public)")
        } else {
            logger.info("refresh=finished trigger=\(trigger.rawValue, privacy: .public) source=\(sourceName, privacy: .public) result=success duration_ms=\(milliseconds, privacy: .public)")
        }
    }

    nonisolated private static func sleepForPolling(_ delay: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(delay))
    }
}
