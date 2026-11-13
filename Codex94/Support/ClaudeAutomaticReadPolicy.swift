import Foundation

/// Process-local gates shared by automatic triggers and explicit CLI outcomes.
/// Report eligibility and the wall-clock schedule belong to ClaudeQuotaStore.
struct ClaudeAutomaticReadPolicy: Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case disabled, scheduled, recentReport, minimumInterval, cooldown, suspended, reading
    }

    static let minimumAutomaticInterval: TimeInterval = 60
    static let failureDelays: [TimeInterval] = [60, 120, 300, 600, 900]
    private static let origin = ContinuousClock.now

    private(set) var lastStartedAt: TimeInterval?
    private(set) var consecutiveFailures = 0
    private(set) var cooldownUntil: TimeInterval?
    private(set) var suspendedIssue: ClaudeQuotaIssue?

    static func monotonicTime() -> TimeInterval {
        let duration = origin.duration(to: ContinuousClock.now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    mutating func started(at instant: TimeInterval) {
        lastStartedAt = instant
    }

    mutating func completed(issue: ClaudeQuotaIssue?, at instant: TimeInterval) {
        guard let issue else {
            consecutiveFailures = 0
            cooldownUntil = nil
            suspendedIssue = nil
            return
        }
        consecutiveFailures = min(consecutiveFailures + 1, Self.failureDelays.count)
        switch issue {
        case .loginRequired, .cliUnavailable, .setupRequired, .configurationConflict:
            suspendedIssue = issue
            cooldownUntil = nil
        default:
            // A failed explicit retry must not clear a previous authentication
            // suspension. Only successful CLI observation or a real context
            // change can establish recovery.
            cooldownUntil = instant + Self.failureDelays[consecutiveFailures - 1]
        }
    }

    func remainingDelay(at instant: TimeInterval) -> TimeInterval {
        let minimum = lastStartedAt.map { $0 + Self.minimumAutomaticInterval } ?? instant
        return max(0, max(minimum, cooldownUntil ?? instant) - instant)
    }

    func waitingState(at instant: TimeInterval) -> State? {
        if suspendedIssue != nil { return .suspended }
        if let cooldownUntil, cooldownUntil > instant { return .cooldown }
        if remainingDelay(at: instant) > 0 { return .minimumInterval }
        return nil
    }
}
