import Foundation

enum TokenUsageParser {
    static func parse(result: [String: Any], fetchedAt: Date) throws -> TokenUsageSnapshot {
        guard let rawSummary = result["summary"], !(rawSummary is NSNull) else {
            throw TokenUsageIssue.unavailable
        }
        guard let summary = rawSummary as? [String: Any] else {
            throw TokenUsageIssue.invalidData
        }

        return try TokenUsageSnapshot(
            summary: TokenUsageSummary(
                lifetimeTokens: optionalInteger(summary["lifetimeTokens"]),
                peakDailyTokens: optionalInteger(summary["peakDailyTokens"]),
                longestRunningTurnSec: optionalInteger(summary["longestRunningTurnSec"]),
                currentStreakDays: optionalInteger(summary["currentStreakDays"]),
                longestStreakDays: optionalInteger(summary["longestStreakDays"])
            ),
            dailyUsageBuckets: dailyBuckets(result["dailyUsageBuckets"]),
            fetchedAt: fetchedAt
        )
    }

    private static func optionalInteger(_ value: Any?) throws -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        return try nonnegativeInteger(value)
    }

    private static func nonnegativeInteger(_ value: Any) throws -> Int {
        guard let integer = StrictJSONInteger.nonnegative(value) else {
            throw TokenUsageIssue.invalidData
        }
        return integer
    }

    private static func dailyBuckets(_ value: Any?) throws -> [TokenUsageDay]? {
        guard let value, !(value is NSNull) else { return nil }
        guard let buckets = value as? [[String: Any]] else {
            throw TokenUsageIssue.invalidData
        }
        var dates = Set<String>()
        var days: [TokenUsageDay] = []
        days.reserveCapacity(buckets.count)
        for bucket in buckets {
            guard let date = bucket["startDate"] as? String,
                  SourceDay.parse(date) != nil,
                  dates.insert(date).inserted,
                  let rawTokens = bucket["tokens"] else {
                throw TokenUsageIssue.invalidData
            }
            days.append(TokenUsageDay(startDate: date, tokens: try nonnegativeInteger(rawTokens)))
        }
        // A repeated date is rejected rather than summed or silently overwritten.
        return days.sorted { $0.startDate < $1.startDate }
    }
}
