import Foundation

enum RefreshPolicy {
    static let wakeMinimumAge: TimeInterval = 60
    static let quotaResetDelay: TimeInterval = 5
    static let popoverMinimumAge: TimeInterval = 60

    // Keep the async implementation out of default-argument closure lowering
    // at MainActor lazy call sites on the supported Xcode 16.4 toolchain.
    nonisolated static func sleepBeforeRetry(_ delay: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(delay))
    }

    nonisolated static func sleepBeforeBackgroundRefresh(_ delay: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    static func automaticRetryDelay(for issue: ConnectionIssue, completedRetries: Int) -> TimeInterval? {
        let delays: [TimeInterval] = [5, 20, 60]
        guard isTransientQuotaIssue(issue), delays.indices.contains(completedRetries) else { return nil }
        return delays[completedRetries]
    }

    static func isTransientQuotaIssue(_ issue: ConnectionIssue?) -> Bool {
        guard let issue else { return false }
        switch issue {
        case .initializationTimedOut, .requestTimedOut, .totalTimedOut,
             .processLaunchFailed, .serverExited, .serverError:
            return true
        default:
            return false
        }
    }

    static func nextAutomaticRefreshDate(
        issue: ConnectionIssue?,
        isRefreshing: Bool,
        nextRetryAt: Date?,
        nextBackgroundRefreshAt: Date?,
        nextQuotaResetRefreshAt: Date? = nil,
        now: Date
    ) -> Date? {
        guard isTransientQuotaIssue(issue), !isRefreshing else { return nil }
        return [nextRetryAt, nextBackgroundRefreshAt, nextQuotaResetRefreshAt]
            .compactMap { $0 }.filter { $0 > now }.min()
    }

    static func shouldRefreshOnPopover(
        connectionState: ConnectionState,
        lastSuccessfulFetch: Date?,
        now: Date
    ) -> Bool {
        guard connectionState == .connected else { return true }
        return shouldRefreshAfterWake(
            lastSuccessfulFetch: lastSuccessfulFetch,
            now: now,
            minimumAge: popoverMinimumAge
        )
    }

    static func shouldRefreshAfterWake(
        lastSuccessfulFetch: Date?,
        now: Date,
        minimumAge: TimeInterval = wakeMinimumAge
    ) -> Bool {
        precondition(minimumAge >= 0)
        guard let lastSuccessfulFetch else { return true }

        let age = now.timeIntervalSince(lastSuccessfulFetch)
        guard age >= 0 else { return true }
        return age >= minimumAge
    }

    static func earliestFutureQuotaResetDate(
        in snapshot: QuotaSnapshot?,
        now: Date,
        delay: TimeInterval = quotaResetDelay
    ) -> Date? {
        precondition(delay >= 0)
        return quotaResetDates(in: snapshot, delay: delay).first { $0 > now }
    }

    static func latestDueQuotaResetDate(
        in snapshot: QuotaSnapshot?,
        now: Date,
        strictlyAfter lowerBound: Date? = nil,
        delay: TimeInterval = quotaResetDelay
    ) -> Date? {
        precondition(delay >= 0)
        return quotaResetDates(in: snapshot, delay: delay).last { target in
            target <= now && (lowerBound.map { target > $0 } ?? true)
        }
    }

    static func quotaResetDates(
        in snapshot: QuotaSnapshot?,
        delay: TimeInterval = quotaResetDelay
    ) -> [Date] {
        precondition(delay >= 0)
        guard let snapshot else { return [] }
        return Array(Set(snapshot.displayableBuckets.flatMap { bucket in
            bucket.windows.compactMap { window in
                window.resetsAt?.addingTimeInterval(delay)
            }
        })).sorted()
    }
}
