import XCTest
@testable import Codex94

final class StatusPresentationTests: XCTestCase {
    func testQuotaLevelThresholds() {
        let expectations: [(Int?, QuotaLevel)] = [
            (nil, .unknown),
            (0, .critical),
            (19, .critical),
            (20, .warning),
            (49, .warning),
            (50, .healthy),
            (100, .healthy)
        ]

        for (remainingPercent, expected) in expectations {
            XCTAssertEqual(
                QuotaLevel(remainingPercent: remainingPercent),
                expected,
                "remainingPercent=\(String(describing: remainingPercent))"
            )
        }
    }

    func testConnectionBadgeMatrixAndCachedData() {
        let lastSuccess = Date(timeIntervalSince1970: 1_900_000_000)
        let expectations: [(ConnectionState, Bool, ConnectionBadge, Bool)] = [
            (.idle, false, .none, false),
            (.refreshing, false, .refreshing, false),
            (.refreshing, true, .refreshing, false),
            (.connected, false, .none, false),
            (.connected, true, .refreshing, false),
            (
                .stale(lastSuccess: lastSuccess, issue: .requestTimedOut),
                false,
                .stale,
                true
            ),
            (
                .stale(lastSuccess: lastSuccess, issue: .requestTimedOut),
                true,
                .refreshing,
                true
            ),
            (.unavailable(.notLoggedIn), false, .unavailable, false),
            (.unavailable(.notLoggedIn), true, .refreshing, false)
        ]

        for (state, isRefreshing, expectedBadge, expectedCached) in expectations {
            let presentation = StatusPresentation(
                remainingPercent: 80,
                connectionState: state,
                isRefreshing: isRefreshing
            )
            XCTAssertEqual(presentation.connectionBadge, expectedBadge)
            XCTAssertEqual(presentation.usesCachedData, expectedCached)
        }
    }

    func testQuotaLevelIsIndependentFromConnectionState() {
        let stale = ConnectionState.stale(
            lastSuccess: Date(timeIntervalSince1970: 1_900_000_000),
            issue: .requestTimedOut
        )
        let expectations: [(Int, QuotaLevel)] = [
            (80, .healthy),
            (40, .warning),
            (10, .critical)
        ]

        for (remainingPercent, expectedLevel) in expectations {
            let connected = StatusPresentation(
                remainingPercent: remainingPercent,
                connectionState: .connected,
                isRefreshing: false
            )
            let cached = StatusPresentation(
                remainingPercent: remainingPercent,
                connectionState: stale,
                isRefreshing: false
            )

            XCTAssertEqual(connected.quotaLevel, expectedLevel)
            XCTAssertEqual(cached.quotaLevel, expectedLevel)
            XCTAssertEqual(cached.connectionBadge, .stale)
        }
    }

    func testUnavailableWithoutQuotaStaysUnknownAndPreservesIssue() {
        let presentation = StatusPresentation(
            remainingPercent: nil,
            connectionState: .unavailable(.notLoggedIn),
            isRefreshing: false
        )

        XCTAssertEqual(presentation.quotaLevel, .unknown)
        XCTAssertEqual(presentation.connectionBadge, .unavailable)
        XCTAssertFalse(presentation.usesCachedData)
        XCTAssertFalse(presentation.isIdle)
        XCTAssertNil(presentation.lastSuccess)
        XCTAssertEqual(presentation.issue, .notLoggedIn)
    }

    func testStaleRetryKeepsCachedContextWhileShowingRefresh() {
        let lastSuccess = Date(timeIntervalSince1970: 1_900_000_000)
        let presentation = StatusPresentation(
            remainingPercent: 80,
            connectionState: .stale(lastSuccess: lastSuccess, issue: .totalTimedOut),
            isRefreshing: true
        )

        XCTAssertEqual(presentation.quotaLevel, .healthy)
        XCTAssertEqual(presentation.connectionBadge, .refreshing)
        XCTAssertTrue(presentation.usesCachedData)
        XCTAssertFalse(presentation.isIdle)
        XCTAssertEqual(presentation.lastSuccess, lastSuccess)
        XCTAssertEqual(presentation.issue, .totalTimedOut)
    }

    func testIdleAndConnectedRemainDistinctWithoutVisibleBadge() {
        let idle = StatusPresentation(
            remainingPercent: nil,
            connectionState: .idle,
            isRefreshing: false
        )
        let connected = StatusPresentation(
            remainingPercent: 80,
            connectionState: .connected,
            isRefreshing: false
        )

        XCTAssertEqual(idle.connectionBadge, .none)
        XCTAssertTrue(idle.isIdle)
        XCTAssertEqual(connected.connectionBadge, .none)
        XCTAssertFalse(connected.isIdle)
    }
}
