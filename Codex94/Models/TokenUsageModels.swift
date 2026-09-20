import Foundation

struct TokenUsageSummary: Equatable, Sendable {
    let lifetimeTokens: Int?
    let peakDailyTokens: Int?
    let longestRunningTurnSec: Int?
    let currentStreakDays: Int?
    let longestStreakDays: Int?

    init(
        lifetimeTokens: Int? = nil,
        peakDailyTokens: Int? = nil,
        longestRunningTurnSec: Int? = nil,
        currentStreakDays: Int? = nil,
        longestStreakDays: Int? = nil
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.longestRunningTurnSec = longestRunningTurnSec
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
    }
}

struct TokenUsageDay: Equatable, Identifiable, Sendable {
    let startDate: String
    let tokens: Int

    var id: String { startDate }
}

struct TokenUsageSnapshot: Equatable, Sendable {
    let summary: TokenUsageSummary
    let dailyUsageBuckets: [TokenUsageDay]?
    let fetchedAt: Date
}

enum TokenUsageIssue: Error, Equatable, Sendable {
    case unsupported
    case notLoggedIn
    case unavailable
    case invalidData
}
