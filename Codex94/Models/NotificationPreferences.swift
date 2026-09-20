import Foundation

struct NotificationPreferences: Codable, Equatable, Sendable {
    var isEnabled = false
    var warningThreshold = 20
    var criticalThreshold = 10
    var recoveryEnabled = false
    var fiveHourEnabled = true
    var weeklyEnabled = true
    var additionalBucketIDs: Set<String> = []

    static let thresholdOptions = [0, 5, 10, 15, 20, 25, 30, 40, 50]

    var thresholds: [Int] {
        Array(Set([warningThreshold, criticalThreshold].filter { $0 > 0 && $0 <= 100 })).sorted()
    }

    var validated: Self {
        var value = self
        if !Self.thresholdOptions.contains(warningThreshold) { value.warningThreshold = 20 }
        if !Self.thresholdOptions.contains(criticalThreshold) { value.criticalThreshold = 10 }
        value.additionalBucketIDs = additionalBucketIDs.filter { !$0.isEmpty }
        return value
    }

    func includes(bucket: QuotaBucketSnapshot, defaultLimitID: String, kind: QuotaWindowKind) -> Bool {
        (bucket.limitID == defaultLimitID || additionalBucketIDs.contains(bucket.limitID))
            && (kind == .fiveHour ? fiveHourEnabled : weeklyEnabled)
    }
}
