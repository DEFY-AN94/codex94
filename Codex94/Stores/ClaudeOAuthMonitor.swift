import Foundation

/// One OAuth request slot and one coordinator timer. UI ownership stays in
/// ClaudeQuotaStore; this object never constructs a CLI or reads credentials itself.
@MainActor
final class ClaudeOAuthMonitor {
    struct State: Equatable, Sendable {
        var report: ClaudeQuotaReport?
        var quotaIssue: ClaudeOAuthIssue?
        var identityIssue: ClaudeOAuthIssue?
        var identityPending = false
        var isRefreshing = false
        var isCached = false
        var lastAttemptAt: Date?
        var nextAutomaticRefreshAt: Date?
        var retryAllowedAt: Date?
        var pendingFallback: ClaudeQuotaReport?
        var isUsingFallback = false
    }

    enum Event: Equatable, Sendable {
        case resetNotificationBaseline
        case evaluateNotifications(ClaudeQuotaReport)
    }

    private(set) var state = State()
    private let credentials: any ClaudeOAuthCredentialProvider
    private let client: any ClaudeOAuthUsageFetching
    private let cache: ClaudeOAuthQuotaCache
    private let readPassive: @Sendable () throws -> ClaudeQuotaReport?
    private let now: @Sendable () -> Date
    private let monotonicNow: @Sendable () -> TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let currentContextID: (@Sendable () async -> UUID?)?
    private let onChange: @MainActor (State, [Event]) -> Void
    private var requestTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var requestID: UUID?
    private var generation = 0
    private var running = false
    private var interval: TimeInterval = 300
    private var allowsFallback = true
    private var contextID: UUID?
    private var verifiedAccount: ClaudeOAuthAccountContext?
    private var lastOAuthReport: ClaudeQuotaReport?
    private var acceptedFallback: ClaudeQuotaReport?
    private var activeUsage: ClaudeOAuthUsageSnapshot?
    private var activeProfile: ClaudeOAuthAccountContext?
    private var profileFinished = false
    private var evaluatedRound = false
    private var nextRegular: TimeInterval?
    private var retryAt: TimeInterval?
    private var recoveryAttempts = 0
    private var cooldownUntil: TimeInterval?
    private var blockedIssue: ClaudeOAuthIssue?
    private var blockedContextID: UUID?
    private var lastSuccess: TimeInterval?
    private var resetTargets: [Date] = []
    private var resetCoveredAt: Date?
    private var pendingReplacement: RefreshTrigger?
    nonisolated private static let clockOrigin = ContinuousClock.now

    init(
        credentials: any ClaudeOAuthCredentialProvider = UnavailableClaudeOAuthCredentialProvider(),
        client: any ClaudeOAuthUsageFetching = ClaudeOAuthUsageClient(),
        cache: ClaudeOAuthQuotaCache = ClaudeOAuthQuotaCache(),
        readPassive: @escaping @Sendable () throws -> ClaudeQuotaReport? = { nil },
        now: @escaping @Sendable () -> Date = { Date() },
        monotonicNow: @escaping @Sendable () -> TimeInterval = { ClaudeOAuthMonitor.monotonicSeconds() },
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil,
        currentContextID: (@Sendable () async -> UUID?)? = nil,
        onChange: @escaping @MainActor (State, [Event]) -> Void = { _, _ in }
    ) {
        self.credentials = credentials
        self.client = client
        self.cache = cache
        self.readPassive = readPassive
        self.now = now
        self.monotonicNow = monotonicNow
        self.sleep = sleep ?? Self.sleepForCoordinator
        self.currentContextID = currentContextID
        self.onChange = onChange
    }

    deinit { requestTask?.cancel(); timerTask?.cancel() }

    func start(interval: TimeInterval = 300, allowsFallback: Bool = true) {
        if running {
            setInterval(interval)
            setAllowsFallback(allowsFallback)
            return
        }
        self.interval = Self.validInterval(interval)
        self.allowsFallback = allowsFallback
        running = true
        state.quotaIssue = blockedIssue
        nextRegular = monotonicNow()
        timerTask = Task { [weak self, sleep] in
            while !Task.isCancelled {
                do { try await sleep(15) } catch { return }
                guard !Task.isCancelled, let running = self?.running, running else { return }
                self?.tick()
            }
        }
        publish([.resetNotificationBaseline])
        refresh(trigger: .launch)
    }

    func stop() {
        running = false
        generation += 1
        requestTask?.cancel()
        timerTask?.cancel()
        timerTask = nil
        pendingReplacement = nil
        clearContext()
        nextRegular = nil
        retryAt = nil
        state = State()
        // Cooldown and a rejected credential's suspension survive stop/start.
        publish([.resetNotificationBaseline])
    }

    func refresh(trigger: RefreshTrigger = .manual) {
        beginRefresh(trigger: trigger, permitCredentialCheck: false)
    }

    func setInterval(_ value: TimeInterval) {
        interval = Self.validInterval(value)
        if running { nextRegular = monotonicNow() + interval }
        publish()
    }

    func setAllowsFallback(_ enabled: Bool) {
        guard allowsFallback != enabled else { return }
        allowsFallback = enabled
        if !enabled {
            state.pendingFallback = nil
            acceptedFallback = nil
            if state.isUsingFallback {
                state.isUsingFallback = false
                state.report = visible(lastOAuthReport)
                state.isCached = state.report != nil
                publish([.resetNotificationBaseline])
                return
            }
        } else { inspectFallback() }
        publish()
    }

    func credentialsDidChange() {
        generation += 1
        requestTask?.cancel()
        clearContext()
        retryAt = nil
        recoveryAttempts = 0
        nextRegular = nil
        state.report = nil
        state.quotaIssue = nil
        state.identityIssue = nil
        state.identityPending = false
        state.isRefreshing = false
        state.isCached = false
        publish([.resetNotificationBaseline])
        guard running else { return }
        beginRefresh(trigger: .preferenceChange, permitCredentialCheck: true)
    }

    func adoptPendingFallback() {
        guard running, allowsFallback, let pending = state.pendingFallback else { return }
        state.pendingFallback = nil
        guard ClaudeQuotaSourcePolicy.isEligiblePassive(pending, at: now()) else { publish(); return }
        acceptedFallback = unverified(pending)
        state.report = visible(acceptedFallback)
        state.isUsingFallback = true
        state.isCached = true
        state.identityPending = false
        publish([.resetNotificationBaseline])
    }

    func handleWake() {
        guard running else { return }
        expirePresentation()
        refresh(trigger: .systemWake)
    }

    func handleClockChange() {
        guard running else { return }
        expirePresentation()
        // Only the wall-clock projection changes; monotonic gates never shorten.
        publish()
    }

    private func beginRefresh(trigger: RefreshTrigger, permitCredentialCheck: Bool) {
        guard running else { return }
        expirePresentation()
        if blockedIssue != nil && !permitCredentialCheck {
            state.quotaIssue = blockedIssue
            inspectFallback()
            publish()
            return
        }
        if !permitCredentialCheck, let cooldownUntil, monotonicNow() < cooldownUntil { publish(); return }
        if trigger == .popover || trigger == .systemWake,
           let lastSuccess, let report = visible(lastOAuthReport) {
            let monotonicAge = monotonicNow() - lastSuccess
            let wallAge = now().timeIntervalSince(report.receivedAt)
            if monotonicAge >= 0, monotonicAge < 60, wallAge >= 0, wallAge < 60 { publish(); return }
        }
        guard requestTask == nil else {
            if requestTask?.isCancelled == true { pendingReplacement = trigger }
            return
        }
        if trigger == .automaticRetry { recoveryAttempts += 1 }
        else { recoveryAttempts = 0 }
        retryAt = nil
        nextRegular = monotonicNow() + interval
        let id = UUID(), expectedGeneration = generation, startedAt = now()
        requestID = id
        state.isRefreshing = true
        state.lastAttemptAt = startedAt
        state.isCached = state.report != nil
        publish()
        requestTask = Task { [weak self] in
            guard let self else { return }
            defer { finishRequest(id: id, generation: expectedGeneration) }
            await performRequest(id: id, generation: expectedGeneration, startedAt: startedAt)
        }
    }

    private func performRequest(id: UUID, generation expectedGeneration: Int, startedAt: Date) async {
        var credential: ClaudeOAuthCredential
        do { credential = try await credentials.credential() }
        catch {
            guard active(id, expectedGeneration) else { return }
            fail(Self.issue(error), credentialID: nil)
            return
        }
        guard active(id, expectedGeneration), prepare(credential) else { return }
        var recovered = false
        while active(id, expectedGeneration) {
            if !credential.scopes.contains("user:profile") { fail(.insufficientScope, credentialID: credential.contextID); return }
            let expired = credential.expiresAt.map { $0 <= now() } ?? false
            if !expired {
                guard await matchesCurrent(credential.contextID, id: id, generation: expectedGeneration) else { return }
                beginRound(startedAt: startedAt)
                let outcome = await fetchRound(credential, id: id, generation: expectedGeneration)
                guard active(id, expectedGeneration), !outcome.cancelled else { return }
                guard await matchesCurrent(credential.contextID, id: id, generation: expectedGeneration) else { return }
                if let issue = outcome.issue, Self.needsRenewal(issue), !recovered {
                    // Recover once below, then repeat both reads with the new context.
                } else {
                    settle(outcome.issue, credentialID: credential.contextID)
                    return
                }
            } else if recovered { fail(.expired, credentialID: credential.contextID); return }
            guard !recovered else { return }
            recovered = true
            guard await matchesCurrent(credential.contextID, id: id, generation: expectedGeneration) else { return }
            do { credential = try await ClaudeOAuthCredentialRecovery.recover(credential, using: credentials) }
            catch {
                guard active(id, expectedGeneration) else { return }
                fail(Self.issue(error), credentialID: credential.contextID)
                return
            }
            guard active(id, expectedGeneration),
                  await matchesCurrent(credential.contextID, id: id, generation: expectedGeneration), prepare(credential) else { return }
        }
    }

    private func prepare(_ credential: ClaudeOAuthCredential) -> Bool {
        if let blockedIssue, blockedContextID == credential.contextID {
            state.quotaIssue = blockedIssue
            inspectFallback()
            publish()
            return false
        }
        blockedIssue = nil
        blockedContextID = nil
        if contextID != credential.contextID {
            clearContext()
            contextID = credential.contextID
            state.report = nil
            state.identityIssue = nil
            state.identityPending = false
            state.isCached = false
            publish([.resetNotificationBaseline])
        }
        if let cooldownUntil, monotonicNow() < cooldownUntil { publish(); return false }
        return true
    }

    private enum Branch: Sendable {
        case usage(Result<ClaudeOAuthUsageSnapshot, ClaudeOAuthIssue>)
        case profile(Result<ClaudeOAuthAccountContext, ClaudeOAuthIssue>)
        case cancelled
    }

    private struct Outcome {
        var usageSucceeded = false
        var usageIssue: ClaudeOAuthIssue?
        var profileIssue: ClaudeOAuthIssue?
        var cancelled = false
        var issue: ClaudeOAuthIssue? {
            if usageSucceeded {
                // Identity is independent of a successful quota read. A profile
                // auth/scope failure must not renew or suspend working quota.
                // Rate limits still gate all reads of this credential context.
                if case .rateLimited = profileIssue { return profileIssue }
                return nil
            }
            let issues = [usageIssue, profileIssue].compactMap { $0 }
            // A simultaneous network failure cannot hide an explicit scope or
            // authorization rejection from the other endpoint.
            if let terminal = issues.first(where: { ClaudeOAuthMonitor.suspends($0) && !ClaudeOAuthMonitor.needsRenewal($0) }) {
                return terminal
            }
            if let limit = issues.first(where: { if case .rateLimited = $0 { return true }; return false }) { return limit }
            return issues.first(where: ClaudeOAuthMonitor.needsRenewal) ?? usageIssue ?? profileIssue
        }
    }

    private func beginRound(startedAt: Date) {
        activeUsage = nil
        activeProfile = nil
        profileFinished = false
        evaluatedRound = false
        state.identityIssue = nil
        resetCoveredAt = max(resetCoveredAt ?? startedAt, startedAt)
    }

    private func fetchRound(_ credential: ClaudeOAuthCredential, id: UUID, generation expectedGeneration: Int) async -> Outcome {
        await withTaskGroup(of: Branch.self) { group in
            group.addTask { [client] in
                do { return .usage(.success(try await client.fetchUsage(using: credential))) }
                catch is CancellationError { return .cancelled }
                catch { return .usage(.failure(Self.issue(error))) }
            }
            group.addTask { [client] in
                do { return .profile(.success(try await client.fetchProfile(using: credential))) }
                catch is CancellationError { return .cancelled }
                catch { return .profile(.failure(Self.issue(error))) }
            }
            var result = Outcome()
            for await branch in group {
                guard active(id, expectedGeneration), !Task.isCancelled else { group.cancelAll(); continue }
                guard await matchesCurrent(credential.contextID, id: id, generation: expectedGeneration) else { group.cancelAll(); continue }
                switch branch {
                case let .usage(.success(usage)):
                    activeUsage = usage
                    resetTargets = usage.windows.compactMap { $0.resetsAt?.addingTimeInterval(5) }.sorted()
                    let report = makeReport(usage, account: activeProfile)
                    if visible(report) == nil {
                        result.usageIssue = .noSupportedWindows
                        state.quotaIssue = .noSupportedWindows
                        state.report = visible(lastOAuthReport)
                        state.isCached = state.report != nil
                    } else {
                        result.usageSucceeded = true
                        let returningFromFallback = state.isUsingFallback
                        acceptedFallback = nil
                        state.pendingFallback = nil
                        state.isUsingFallback = false
                        state.quotaIssue = nil
                        state.report = visible(report)
                        state.isCached = false
                        state.identityPending = !profileFinished
                        lastOAuthReport = report
                        lastSuccess = monotonicNow()
                        publish(returningFromFallback ? [.resetNotificationBaseline] : [])
                        publishVerifiedIfReady()
                    }
                case let .usage(.failure(issue)):
                    result.usageIssue = issue
                    state.quotaIssue = issue
                    state.isCached = state.report != nil
                    if case .rateLimited = issue { installCooldown(issue) }
                case let .profile(.success(account)):
                    profileFinished = true
                    state.identityPending = false
                    state.identityIssue = nil
                    activeProfile = account
                    if let previous = verifiedAccount, previous != account {
                        lastOAuthReport = nil
                        acceptedFallback = nil
                        state.report = nil
                        state.pendingFallback = nil
                        state.isUsingFallback = false
                        publish([.resetNotificationBaseline])
                    }
                    verifiedAccount = account
                    if activeUsage == nil, lastOAuthReport == nil, let cached = try? cache.load(context: account) {
                        lastOAuthReport = cached
                        state.report = visible(cached)
                        state.isCached = state.report != nil
                        publish([.resetNotificationBaseline])
                    }
                    publishVerifiedIfReady()
                case let .profile(.failure(issue)):
                    profileFinished = true
                    result.profileIssue = issue
                    state.identityPending = false
                    state.identityIssue = issue
                    if case .rateLimited = issue { installCooldown(issue) }
                case .cancelled:
                    result.cancelled = true
                    group.cancelAll()
                }
                publish()
            }
            return result
        }
    }

    private func publishVerifiedIfReady() {
        guard !evaluatedRound, let usage = activeUsage, let account = activeProfile else { return }
        let report = makeReport(usage, account: account)
        guard let displayed = visible(report) else { return }
        evaluatedRound = true
        lastOAuthReport = report
        state.report = displayed
        state.isCached = false
        state.identityPending = false
        try? cache.save(report: report)
        publish([.evaluateNotifications(report)])
    }

    private func matchesCurrent(_ expected: UUID, id: UUID, generation expectedGeneration: Int) async -> Bool {
        let current: UUID?
        do {
            if let currentContextID { current = await currentContextID() }
            else { current = try await credentials.credential().contextID }
        } catch {
            guard active(id, expectedGeneration) else { return false }
            invalidateContext(issue: Self.issue(error), replacement: false)
            return false
        }
        guard active(id, expectedGeneration) else { return false }
        guard current == expected else {
            invalidateContext(issue: current == nil ? .notConnected : nil, replacement: current != nil)
            return false
        }
        return true
    }

    private func invalidateContext(issue: ClaudeOAuthIssue?, replacement: Bool) {
        generation += 1
        requestTask?.cancel()
        let previous = contextID
        clearContext()
        state.report = nil
        state.isRefreshing = false
        state.identityPending = false
        state.identityIssue = nil
        state.quotaIssue = issue
        state.isCached = false
        nextRegular = nil
        retryAt = nil
        if let issue { blockedIssue = issue; blockedContextID = previous }
        pendingReplacement = replacement ? .preferenceChange : nil
        inspectFallback()
        publish([.resetNotificationBaseline])
    }

    private func finishRequest(id: UUID, generation expectedGeneration: Int) {
        guard requestID == id else { return }
        requestID = nil
        requestTask = nil
        if expectedGeneration == generation {
            state.isRefreshing = false
            state.identityPending = false
            expirePresentation()
            publish()
        }
        if running, let replacement = pendingReplacement {
            pendingReplacement = nil
            beginRefresh(trigger: replacement, permitCredentialCheck: true)
        }
    }

    private func settle(_ issue: ClaudeOAuthIssue?, credentialID: UUID) {
        if let issue {
            // When quota itself failed, publish the same final reason that
            // suspends or schedules it. A successful quota with profile-only
            // rate limiting keeps its independent identity error instead.
            if state.quotaIssue != nil { state.quotaIssue = issue }
            if Self.suspends(issue) { blockedIssue = issue; blockedContextID = credentialID; retryAt = nil }
            else if case .rateLimited = issue { installCooldown(issue); retryAt = nil }
            else if Self.isTransient(issue), recoveryAttempts < 2 { retryAt = monotonicNow() + 60 }
            inspectFallback()
        } else {
            recoveryAttempts = 0
            retryAt = nil
        }
        publish()
    }

    private func fail(_ issue: ClaudeOAuthIssue, credentialID: UUID?) {
        state.quotaIssue = issue
        state.identityPending = false
        state.isCached = state.report != nil
        if Self.suspends(issue) { blockedIssue = issue; blockedContextID = credentialID; retryAt = nil }
        else if case .rateLimited = issue { installCooldown(issue) }
        else if Self.isTransient(issue), recoveryAttempts < 2 { retryAt = monotonicNow() + 60 }
        inspectFallback()
        publish()
    }

    private func installCooldown(_ issue: ClaudeOAuthIssue) {
        guard case let .rateLimited(date) = issue else { return }
        let delta = date.timeIntervalSince(now())
        let safeDelay = delta.isFinite && delta >= 0 ? min(delta, 253_402_300_799) : 300
        cooldownUntil = max(cooldownUntil ?? 0, monotonicNow() + max(1, safeDelay))
    }

    private func tick() {
        guard running else { return }
        expirePresentation()
        inspectFallback()
        if requestTask == nil, blockedIssue == nil, let due = nextDue(), due <= monotonicNow() {
            let trigger: RefreshTrigger
            if let retryAt, retryAt <= monotonicNow() { trigger = .automaticRetry }
            else if resetIsDue { trigger = .quotaReset }
            else { trigger = .background }
            refresh(trigger: trigger)
        } else { publish() }
    }

    private func inspectFallback() {
        guard running, allowsFallback, state.quotaIssue != nil || state.isUsingFallback else { return }
        guard let report = try? readPassive(), ClaudeQuotaSourcePolicy.isEligiblePassive(report, at: now()) else { return }
        let local = unverified(report)
        if let acceptedFallback, local.producerID == acceptedFallback.producerID {
            if local.reportedAt > acceptedFallback.reportedAt {
                self.acceptedFallback = local
                state.report = visible(local)
                state.isCached = true
            }
        } else if state.pendingFallback == nil { state.pendingFallback = local }
    }

    private func expirePresentation() {
        if let acceptedFallback, !ClaudeQuotaSourcePolicy.isEligiblePassive(acceptedFallback, at: now()) {
            self.acceptedFallback = nil
            state.isUsingFallback = false
            state.report = visible(lastOAuthReport)
            state.isCached = state.report != nil
            publish([.resetNotificationBaseline])
        } else { state.report = visible(state.report) }
    }

    private func clearContext() {
        contextID = nil
        verifiedAccount = nil
        lastOAuthReport = nil
        acceptedFallback = nil
        activeUsage = nil
        activeProfile = nil
        lastSuccess = nil
        resetTargets = []
        resetCoveredAt = nil
        state.pendingFallback = nil
        state.isUsingFallback = false
    }

    private var resetIsDue: Bool {
        resetTargets.contains { target in
            target <= now() && (resetCoveredAt.map { target > $0 } ?? true)
        }
    }

    private func nextDue() -> TimeInterval? {
        guard running, blockedIssue == nil else { return nil }
        let current = monotonicNow()
        var due = retryAt ?? nextRegular
        if retryAt == nil, let reset = resetTargets.first(where: { target in resetCoveredAt.map { target > $0 } ?? true }) {
            let resetDue = current + max(0, reset.timeIntervalSince(now()))
            due = min(due ?? resetDue, resetDue)
        }
        if let cooldownUntil, cooldownUntil > current { due = max(due ?? cooldownUntil, cooldownUntil) }
        return due
    }

    private func publish(_ events: [Event] = []) {
        if running, let cooldownUntil, cooldownUntil > monotonicNow() {
            let seconds = now().timeIntervalSince1970 + cooldownUntil - monotonicNow()
            state.retryAllowedAt = seconds.isFinite
                ? Date(timeIntervalSince1970: min(253_402_300_799, max(0, seconds))) : nil
        } else { state.retryAllowedAt = nil }
        if let due = nextDue() {
            let seconds = now().timeIntervalSince1970 + max(0, due - monotonicNow())
            state.nextAutomaticRefreshAt = seconds.isFinite
                ? Date(timeIntervalSince1970: min(253_402_300_799, max(0, seconds))) : nil
        } else { state.nextAutomaticRefreshAt = nil }
        onChange(state, events)
    }

    private func visible(_ report: ClaudeQuotaReport?) -> ClaudeQuotaReport? {
        guard let report, ClaudeQuotaSourcePolicy.validTimestamp(report.reportedAt),
              report.reportedAt <= now().addingTimeInterval(5) else { return nil }
        let windows = report.windows.filter { $0.resetsAt.map { $0 > now() } ?? true }
        guard !windows.isEmpty else { return nil }
        return ClaudeQuotaReport(source: report.source, reportedAt: report.reportedAt, receivedAt: report.receivedAt,
                                 windows: windows, producerID: report.producerID, accountContext: report.accountContext)
    }

    private func makeReport(_ usage: ClaudeOAuthUsageSnapshot, account: ClaudeOAuthAccountContext?) -> ClaudeQuotaReport {
        ClaudeQuotaReport(source: .oauth, reportedAt: usage.receivedAt, receivedAt: usage.receivedAt,
                          windows: usage.windows.map { .init(kind: $0.kind, usedPercentage: $0.usedPercentage, resetsAt: $0.resetsAt) },
                          accountContext: account)
    }

    private func unverified(_ report: ClaudeQuotaReport) -> ClaudeQuotaReport {
        ClaudeQuotaReport(source: .statusline, reportedAt: report.reportedAt, receivedAt: report.receivedAt,
                          windows: report.windows, producerID: report.producerID)
    }

    private func active(_ id: UUID, _ expectedGeneration: Int) -> Bool {
        running && generation == expectedGeneration && requestID == id && !Task.isCancelled
    }

    nonisolated private static func issue(_ error: Error) -> ClaudeOAuthIssue {
        (error as? ClaudeOAuthIssue) ?? .network
    }
    nonisolated private static func needsRenewal(_ issue: ClaudeOAuthIssue) -> Bool { issue == .unauthorized || issue == .expired }
    nonisolated private static func isTransient(_ issue: ClaudeOAuthIssue) -> Bool { [.network, .timedOut, .server].contains(issue) }
    nonisolated private static func suspends(_ issue: ClaudeOAuthIssue) -> Bool {
        [.integrationUnavailable, .notConnected, .credentialAccessDenied, .invalidCredential, .expired,
         .insufficientScope, .accessDenied, .forbidden, .unauthorized].contains(issue)
    }
    nonisolated private static func validInterval(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? min(86_400, max(60, value)) : 300
    }
    nonisolated private static func monotonicSeconds() -> TimeInterval {
        // ContinuousClock includes system sleep; the origin is process-local.
        let duration = clockOrigin.duration(to: ContinuousClock.now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
    nonisolated private static func sleepForCoordinator(_ seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
