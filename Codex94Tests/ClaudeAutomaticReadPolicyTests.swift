import XCTest
@testable import Codex94

final class ClaudeAutomaticReadPolicyTests: XCTestCase {
    func testMinimumIntervalIncludesExplicitReadsAndHasAnExactBoundary() {
        var policy = ClaudeAutomaticReadPolicy()
        XCTAssertNil(policy.waitingState(at: 0))
        policy.started(at: 10)
        policy.completed(issue: nil, at: 11)
        XCTAssertEqual(policy.waitingState(at: 69.999), .minimumInterval)
        XCTAssertEqual(policy.remainingDelay(at: 69), 1)
        XCTAssertNil(policy.waitingState(at: 70))
    }

    func testFailuresCoolDownFromCompletionAndCapWithoutOverflow() {
        var policy = ClaudeAutomaticReadPolicy()
        var completed: TimeInterval = 20
        for expected in [60.0, 120, 300, 600, 900, 900, 900] {
            policy.started(at: completed - 20)
            policy.completed(issue: .timedOut, at: completed)
            XCTAssertEqual(policy.cooldownUntil, completed + expected)
            XCTAssertEqual(policy.waitingState(at: completed + expected - 0.001), .cooldown)
            XCTAssertNil(policy.waitingState(at: completed + expected))
            completed += expected + 20
        }
        XCTAssertEqual(policy.consecutiveFailures, 5)
        policy.completed(issue: nil, at: completed)
        XCTAssertEqual(policy.consecutiveFailures, 0)
        XCTAssertNil(policy.cooldownUntil)
        XCTAssertNil(policy.suspendedIssue)
    }

    func testAuthenticationSuspensionNeedsSuccessfulCLIOrContextReplacement() {
        for issue in [ClaudeQuotaIssue.loginRequired, .cliUnavailable, .setupRequired, .configurationConflict] {
            var policy = ClaudeAutomaticReadPolicy()
            policy.started(at: 0)
            policy.completed(issue: issue, at: 10)
            XCTAssertEqual(policy.waitingState(at: 1_000_000), .suspended)
            XCTAssertEqual(policy.suspendedIssue, issue)
            policy.started(at: 20) // Explicit retry is permitted by the store.
            policy.completed(issue: .timedOut, at: 30)
            XCTAssertEqual(policy.waitingState(at: 40), .suspended)
            policy.completed(issue: nil, at: 50)
            XCTAssertNil(policy.suspendedIssue)
            XCTAssertEqual(policy.waitingState(at: 50), .minimumInterval)
        }
    }

    func testPassiveDataAndSettingsHaveNoMutationThatClearsRateGates() {
        var policy = ClaudeAutomaticReadPolicy()
        policy.started(at: 100)
        policy.completed(issue: .unavailable, at: 125)
        let retained = policy
        // Wall time, quota values, timer settings and heartbeats are deliberately
        // absent from this type. Re-evaluation cannot erase a failed attempt.
        XCTAssertEqual(policy.remainingDelay(at: 150), 35)
        XCTAssertEqual(policy, retained)
    }
}
