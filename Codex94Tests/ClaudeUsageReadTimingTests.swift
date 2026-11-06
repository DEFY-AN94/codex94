import Foundation
import XCTest
@testable import Codex94

final class ClaudeUsageReadTimingTests: XCTestCase {
    private enum Action: Equatable { case usage, confirm, trust(String) }

    func testEvaluationCadenceHasAnExactHundredMillisecondBoundary() {
        var timing = ClaudeUsageReadTiming<Action>()
        XCTAssertTrue(timing.beginEvaluation(at: .zero))
        XCTAssertFalse(timing.beginEvaluation(at: .milliseconds(99)))
        XCTAssertTrue(timing.beginEvaluation(at: .milliseconds(100)))
        XCTAssertFalse(timing.beginEvaluation(at: .milliseconds(199)))
        XCTAssertTrue(timing.beginEvaluation(at: .milliseconds(200)))
    }

    func testDelayedEvaluationDoesNotReplayMissedTicks() {
        var timing = ClaudeUsageReadTiming<Action>()
        XCTAssertTrue(timing.beginEvaluation(at: .zero))
        XCTAssertTrue(timing.beginEvaluation(at: .milliseconds(350)))
        XCTAssertFalse(timing.beginEvaluation(at: .milliseconds(350)))
        XCTAssertFalse(timing.beginEvaluation(at: .milliseconds(449)))
        XCTAssertTrue(timing.beginEvaluation(at: .milliseconds(450)))
    }

    func testUnchangedActionSettlesAtTwoHundredMillisecondsAndIsConsumed() {
        var timing = ClaudeUsageReadTiming<Action>()
        XCTAssertNil(timing.observeAction(.usage, at: .zero))
        XCTAssertNil(timing.observeAction(.usage, at: .milliseconds(199)))
        XCTAssertEqual(timing.observeAction(.usage, at: .milliseconds(200)), .usage)
        XCTAssertNil(timing.observeAction(.usage, at: .milliseconds(200)), "Consumption starts a new interval")
        XCTAssertNil(timing.observeAction(.usage, at: .milliseconds(399)))
        XCTAssertEqual(timing.observeAction(.usage, at: .milliseconds(400)), .usage)
    }

    func testChangedAndMissingActionsRestartTheirOwnStableInterval() {
        var timing = ClaudeUsageReadTiming<Action>()
        XCTAssertNil(timing.observeAction(.trust("down"), at: .zero))
        XCTAssertNil(timing.observeAction(.trust("return"), at: .milliseconds(150)))
        XCTAssertNil(timing.observeAction(.trust("return"), at: .milliseconds(349)))
        XCTAssertEqual(timing.observeAction(.trust("return"), at: .milliseconds(350)), .trust("return"))
        XCTAssertNil(timing.observeAction(.usage, at: .milliseconds(400)))
        XCTAssertNil(timing.observeAction(nil, at: .milliseconds(550)))
        XCTAssertNil(timing.observeAction(.usage, at: .milliseconds(600)))
        XCTAssertNil(timing.observeAction(.usage, at: .milliseconds(799)))
        XCTAssertEqual(timing.observeAction(.usage, at: .milliseconds(800)), .usage)
    }

    func testSingleWindowStabilityHasAnExactOneSecondBoundary() {
        var timing = ClaudeUsageReadTiming<Action>()
        let windows = reportWindows(used: 62.5)
        XCTAssertFalse(timing.observeWindows(windows, at: .zero))
        XCTAssertFalse(timing.observeWindows(windows, at: .milliseconds(999)))
        XCTAssertTrue(timing.observeWindows(windows, at: .seconds(1)))
    }

    func testChangedPercentResetOrWindowSetRestartsReportStability() {
        let initial = reportWindows(used: 62.5)
        let changes = [
            reportWindows(used: 63),
            reportWindows(used: 62.5, resetOffset: 1),
            initial + [ClaudeQuotaWindow(kind: .fiveHour, usedPercentage: 20, resetsAt: nil)],
        ]
        for changed in changes {
            var timing = ClaudeUsageReadTiming<Action>()
            XCTAssertFalse(timing.observeWindows(initial, at: .zero))
            XCTAssertFalse(timing.observeWindows(changed, at: .milliseconds(900)))
            XCTAssertFalse(timing.observeWindows(changed, at: .milliseconds(1_899)))
            XCTAssertTrue(timing.observeWindows(changed, at: .milliseconds(1_900)))
        }
    }

    func testRefreshingOrUnknownReportClearsPriorStability() {
        var timing = ClaudeUsageReadTiming<Action>()
        let windows = reportWindows(used: 62.5)
        XCTAssertFalse(timing.observeWindows(windows, at: .zero))
        XCTAssertFalse(timing.observeWindows(nil, at: .milliseconds(900)))
        XCTAssertFalse(timing.observeWindows(windows, at: .seconds(1)))
        XCTAssertFalse(timing.observeWindows(windows, at: .milliseconds(1_999)))
        XCTAssertTrue(timing.observeWindows(windows, at: .seconds(2)))
    }

    func testIncompleteFrameInvalidatesBothActionAndReportEvidence() {
        var timing = ClaudeUsageReadTiming<Action>()
        let windows = reportWindows(used: 62.5)
        XCTAssertNil(timing.observeAction(.usage, at: .zero))
        XCTAssertFalse(timing.observeWindows(windows, at: .zero))
        timing.invalidateFrame()
        XCTAssertNil(timing.observeAction(.usage, at: .seconds(1)))
        XCTAssertFalse(timing.observeWindows(windows, at: .seconds(1)))
        XCTAssertNil(timing.observeAction(.usage, at: .milliseconds(1_199)))
        timing.invalidateFrame()
        XCTAssertNil(timing.observeAction(.confirm, at: .milliseconds(1_200)))
        XCTAssertFalse(timing.observeWindows(windows, at: .milliseconds(1_200)))
        XCTAssertEqual(timing.observeAction(.confirm, at: .milliseconds(1_400)), .confirm)
        XCTAssertFalse(timing.observeWindows(windows, at: .milliseconds(2_199)))
        XCTAssertTrue(timing.observeWindows(windows, at: .milliseconds(2_200)))
    }

    func testContinuousRedrawsNeitherPostponeEvaluationNorExtendDeadline() {
        var timing = ClaudeUsageReadTiming<Action>(timeout: .seconds(2))
        let windows = reportWindows(used: 62.5)
        var evaluations = 0
        var firstStable: Duration?
        // Bytes may arrive every millisecond. Only parsed windows reach this
        // helper, so an unrelated animation never changes the stable candidate.
        for milliseconds in 0...2_000 {
            let elapsed = Duration.milliseconds(milliseconds)
            guard timing.beginEvaluation(at: elapsed) else { continue }
            evaluations += 1
            if timing.observeWindows(windows, at: elapsed), firstStable == nil { firstStable = elapsed }
        }
        XCTAssertEqual(evaluations, 20)
        XCTAssertEqual(firstStable, .seconds(1))
        XCTAssertTrue(timing.hasReachedDeadline(at: .seconds(2)))
        XCTAssertFalse(timing.beginEvaluation(at: .seconds(2)))
        XCTAssertFalse(timing.observeWindows(windows, at: .seconds(2)))
    }

    func testDefaultDeadlineWinsOverExactlySettledActionOrReport() {
        var timing = ClaudeUsageReadTiming<Action>()
        let windows = reportWindows(used: 62.5)
        XCTAssertFalse(timing.hasReachedDeadline(at: .milliseconds(19_999)))
        XCTAssertFalse(timing.observeWindows(windows, at: .seconds(19)))
        XCTAssertNil(timing.observeAction(.usage, at: .milliseconds(19_800)))
        XCTAssertFalse(timing.observeWindows(windows, at: .milliseconds(19_999)))
        XCTAssertNil(timing.observeAction(.usage, at: .milliseconds(19_999)))
        XCTAssertTrue(timing.hasReachedDeadline(at: .seconds(20)))
        XCTAssertFalse(timing.beginEvaluation(at: .seconds(20)))
        XCTAssertFalse(timing.observeWindows(windows, at: .seconds(20)))
        XCTAssertNil(timing.observeAction(.usage, at: .seconds(20)))
        timing.invalidateFrame()
        XCTAssertFalse(timing.beginEvaluation(at: .seconds(21)), "Invalidation cannot renew the deadline")
    }

    func testResettingReportDoesNotResetActionOrEvaluationCadence() {
        var timing = ClaudeUsageReadTiming<Action>()
        XCTAssertTrue(timing.beginEvaluation(at: .zero))
        XCTAssertNil(timing.observeAction(.confirm, at: .zero))
        XCTAssertFalse(timing.observeWindows(reportWindows(used: 62.5), at: .zero))
        XCTAssertFalse(timing.observeWindows(nil, at: .milliseconds(50)))
        XCTAssertFalse(timing.beginEvaluation(at: .milliseconds(99)))
        XCTAssertEqual(timing.observeAction(.confirm, at: .milliseconds(200)), .confirm)
    }

    private func reportWindows(used: Double, resetOffset: TimeInterval = 0) -> [ClaudeQuotaWindow] {
        [ClaudeQuotaWindow(kind: .weekly, usedPercentage: used,
                           resetsAt: Date(timeIntervalSince1970: 2_000_010_000 + resetOffset))]
    }
}
