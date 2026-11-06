import Foundation

/// Timing for one usage session after its PTY has launched. Version probing and
/// process cleanup keep their own budgets. The caller supplies monotonic elapsed
/// time; this type performs no I/O, clock reads, parsing or input authorization.
struct ClaudeUsageReadTiming<Action: Equatable> {
    private let deadline: Duration
    private var nextEvaluation: Duration = .zero
    private var pendingAction: Action?
    private var actionSince: Duration?
    private var candidateWindows: [ClaudeQuotaWindow]?
    private var candidateSince: Duration?

    init(timeout: Duration = .seconds(20)) {
        deadline = max(.zero, timeout)
    }

    func hasReachedDeadline(at elapsed: Duration) -> Bool {
        elapsed >= deadline
    }

    /// Incoming bytes never move this evaluation cadence or the session deadline.
    mutating func beginEvaluation(at elapsed: Duration) -> Bool {
        guard !hasReachedDeadline(at: elapsed), elapsed >= nextEvaluation else { return false }
        nextEvaluation = elapsed + .milliseconds(100)
        return true
    }

    /// Returns a recognized action only after it remains unchanged for 200 ms.
    /// Consuming it resets its interval, matching the reader's existing input gate.
    mutating func observeAction(_ action: Action?, at elapsed: Duration) -> Action? {
        guard !hasReachedDeadline(at: elapsed) else { return nil }
        if action != pendingAction {
            pendingAction = action
            actionSince = action == nil ? nil : elapsed
        }
        guard let action, let since = actionSince, elapsed - since >= .milliseconds(200) else { return nil }
        pendingAction = nil
        actionSince = nil
        return action
    }

    /// Uses the actual parsed windows, including resets, rather than terminal
    /// bytes. Unrelated animation therefore cannot postpone a stable report.
    mutating func observeWindows(_ windows: [ClaudeQuotaWindow]?, at elapsed: Duration) -> Bool {
        guard !hasReachedDeadline(at: elapsed) else { return false }
        if windows != candidateWindows {
            candidateWindows = windows
            candidateSince = windows == nil ? nil : elapsed
        }
        guard windows != nil, let since = candidateSince else { return false }
        return elapsed - since >= .seconds(1)
    }

    /// Incomplete encodings/control frames invalidate both kinds of evidence.
    /// Refreshing, unknown and trust screens reset only the report via nil above.
    mutating func invalidateFrame() {
        pendingAction = nil
        actionSince = nil
        candidateWindows = nil
        candidateSince = nil
    }
}
