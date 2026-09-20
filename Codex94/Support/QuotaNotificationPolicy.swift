import Foundation

struct QuotaNotificationEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case low(threshold: Int)
        case recovered
    }

    let kind: Kind
    let bucketName: String
    let window: QuotaWindowKind
    let remainingPercent: Int
}

/// Only successful live responses enter this policy. Its baseline and deduplication
/// state are session-only and never reuse the refresh scheduler's Reset watermark.
struct QuotaNotificationPolicy {
    private struct Key: Hashable {
        let bucketID: String
        let window: QuotaWindowKind
    }

    private struct WindowState {
        var remaining: Int
        var reset: Date?
        var alertedThresholds: Set<Int>
        var recoverySent = false
    }

    private var configuration: NotificationPreferences?
    private var windows: [Key: WindowState] = [:]
    private var lastFetch: Date?

    mutating func reset() {
        configuration = nil
        windows.removeAll()
        lastFetch = nil
    }

    mutating func events(
        for snapshot: QuotaSnapshot,
        preferences: NotificationPreferences
    ) -> [QuotaNotificationEvent] {
        if configuration != preferences {
            reset()
            configuration = preferences
        }
        guard preferences.isEnabled else { return [] }

        let clockMovedBack = lastFetch.map { snapshot.fetchedAt < $0 } ?? false
        lastFetch = snapshot.fetchedAt
        let recoveryBoundary = preferences.thresholds.max() ?? 0
        var current: [Key: WindowState] = [:]
        var events: [QuotaNotificationEvent] = []

        for bucket in snapshot.displayableBuckets {
            for window in bucket.windows where preferences.includes(
                bucket: bucket, defaultLimitID: snapshot.defaultLimitID, kind: window.kind
            ) {
                let key = Key(bucketID: bucket.limitID, window: window.kind)
                let remaining = window.remainingPercent
                guard var state = windows[key] else {
                    current[key] = WindowState(
                        remaining: remaining,
                        reset: window.resetsAt,
                        alertedThresholds: Set(preferences.thresholds.filter { remaining <= $0 })
                    )
                    continue
                }

                // An adjusted future timestamp alone is not evidence of a new cycle.
                let resetAdvanced = state.reset != window.resetsAt
                    && ((state.reset.map { $0 <= snapshot.fetchedAt } ?? false)
                        || remaining > state.remaining)
                // Some compatible clients omit Reset dates. A substantial refill
                // is still useful cycle evidence; small threshold oscillations are not.
                let undatedRefill = state.reset == nil && window.resetsAt == nil
                    && state.remaining <= recoveryBoundary && remaining >= 80
                    && remaining - state.remaining >= 50
                if (resetAdvanced || undatedRefill) && !clockMovedBack {
                    state.alertedThresholds.removeAll()
                    state.recoverySent = false
                }

                if !clockMovedBack {
                    if preferences.recoveryEnabled,
                       !state.recoverySent,
                       state.remaining <= recoveryBoundary,
                       remaining > recoveryBoundary {
                        events.append(QuotaNotificationEvent(
                            kind: .recovered,
                            bucketName: snapshot.displayName(for: bucket),
                            window: window.kind,
                            remainingPercent: remaining
                        ))
                        state.recoverySent = true
                    }

                    let crossed = preferences.thresholds.filter {
                        state.remaining > $0 && remaining <= $0 && !state.alertedThresholds.contains($0)
                    }
                    if let mostUrgent = crossed.min() {
                        events.append(QuotaNotificationEvent(
                            kind: .low(threshold: mostUrgent),
                            bucketName: snapshot.displayName(for: bucket),
                            window: window.kind,
                            remainingPercent: remaining
                        ))
                        state.alertedThresholds.formUnion(crossed)
                    }
                }

                state.remaining = remaining
                state.reset = window.resetsAt
                current[key] = state
            }
        }
        // A bucket/window returning after an absence establishes a fresh baseline.
        windows = current
        return events
    }
}
