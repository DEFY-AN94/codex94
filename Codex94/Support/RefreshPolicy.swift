import Foundation

enum RefreshPolicy {
    static let wakeMinimumAge: TimeInterval = 60

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
}
