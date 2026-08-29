import Foundation

enum RefreshPolicy {
    static let wakeMinimumAge: TimeInterval = 60
    static let quotaResetDelay: TimeInterval = 5

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

    private static func quotaResetDates(
        in snapshot: QuotaSnapshot?,
        delay: TimeInterval
    ) -> [Date] {
        guard let snapshot else { return [] }
        return Array(Set(snapshot.displayableBuckets.flatMap { bucket in
            bucket.windows.compactMap { window in
                window.resetsAt?.addingTimeInterval(delay)
            }
        })).sorted()
    }
}
