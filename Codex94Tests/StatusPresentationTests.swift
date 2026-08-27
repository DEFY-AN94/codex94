import XCTest
@testable import Codex94

final class StatusPresentationTests: XCTestCase {
    private let lastSuccess = Date(timeIntervalSince1970: 1_900_000_000)

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

    func testConnectionBadgeMatrixAndCachedDataRemainUnchanged() {
        let expectations: [(ConnectionState, Bool, Date?, ConnectionBadge, Bool)] = [
            (.idle, false, nil, .none, false),
            (.refreshing, false, nil, .refreshing, false),
            (.refreshing, true, nil, .refreshing, false),
            (.connected, false, lastSuccess, .none, false),
            (.connected, true, lastSuccess, .refreshing, false),
            (
                .stale(lastSuccess: lastSuccess, issue: .requestTimedOut),
                false,
                lastSuccess,
                .stale,
                true
            ),
            (
                .stale(lastSuccess: lastSuccess, issue: .requestTimedOut),
                true,
                lastSuccess,
                .refreshing,
                true
            ),
            (.unavailable(.notLoggedIn), false, nil, .unavailable, false),
            (.unavailable(.notLoggedIn), true, nil, .refreshing, false)
        ]

        for (state, isRefreshing, timestamp, expectedBadge, expectedCached) in expectations {
            let presentation = makePresentation(
                state: state,
                isRefreshing: isRefreshing,
                lastSuccessfulFetch: timestamp
            )
            XCTAssertEqual(presentation.connectionBadge, expectedBadge)
            XCTAssertEqual(presentation.usesCachedData, expectedCached)
        }
    }

    func testFreshnessMatrixUsesSnapshotTimestamp() {
        let expectations: [(ConnectionState, Bool, Date?, FreshnessDetail)] = [
            (.idle, false, nil, .none),
            (.connected, false, lastSuccess, .updated(lastSuccess)),
            (.connected, true, lastSuccess, .lastSuccess(lastSuccess)),
            (
                .stale(lastSuccess: lastSuccess, issue: .requestTimedOut),
                false,
                lastSuccess,
                .updated(lastSuccess)
            ),
            (
                .stale(lastSuccess: lastSuccess, issue: .requestTimedOut),
                true,
                lastSuccess,
                .lastSuccess(lastSuccess)
            ),
            (.unavailable(.notLoggedIn), false, nil, .noSuccessfulData),
            (.unavailable(.notLoggedIn), true, nil, .noSuccessfulDataYet),
            (.refreshing, false, nil, .noSuccessfulDataYet)
        ]

        for (state, isRefreshing, timestamp, expectedFreshness) in expectations {
            let presentation = makePresentation(
                state: state,
                isRefreshing: isRefreshing,
                lastSuccessfulFetch: timestamp
            )
            XCTAssertEqual(presentation.freshness, expectedFreshness)
        }
    }

    func testQuotaLevelIsIndependentFromConnectionState() {
        let stale = ConnectionState.stale(
            lastSuccess: lastSuccess,
            issue: .requestTimedOut
        )
        let expectations: [(Int, QuotaLevel)] = [
            (80, .healthy),
            (40, .warning),
            (10, .critical)
        ]

        for (remainingPercent, expectedLevel) in expectations {
            let connected = makePresentation(
                remainingPercent: remainingPercent,
                state: .connected,
                lastSuccessfulFetch: lastSuccess
            )
            let cached = makePresentation(
                remainingPercent: remainingPercent,
                state: stale,
                lastSuccessfulFetch: lastSuccess
            )
            let retryingCached = makePresentation(
                remainingPercent: remainingPercent,
                state: stale,
                isRefreshing: true,
                lastSuccessfulFetch: lastSuccess
            )

            XCTAssertEqual(connected.quotaLevel, expectedLevel)
            XCTAssertEqual(cached.quotaLevel, expectedLevel)
            XCTAssertEqual(retryingCached.quotaLevel, expectedLevel)
            XCTAssertEqual(cached.connectionBadge, .stale)
            XCTAssertEqual(retryingCached.connectionBadge, .refreshing)
        }
    }

    func testUnavailableWithoutQuotaStaysUnknownAndPreservesIssue() {
        let presentation = makePresentation(
            remainingPercent: nil,
            state: .unavailable(.notLoggedIn),
            lastSuccessfulFetch: nil
        )

        XCTAssertEqual(presentation.quotaLevel, .unknown)
        XCTAssertEqual(presentation.connectionBadge, .unavailable)
        XCTAssertFalse(presentation.usesCachedData)
        XCTAssertFalse(presentation.isIdle)
        XCTAssertNil(presentation.lastSuccess)
        XCTAssertEqual(presentation.freshness, .noSuccessfulData)
        XCTAssertEqual(presentation.issue, .notLoggedIn)
    }

    func testStaleRetryKeepsCachedContextWhileShowingRefresh() {
        let presentation = makePresentation(
            state: .stale(lastSuccess: lastSuccess, issue: .totalTimedOut),
            isRefreshing: true,
            lastSuccessfulFetch: lastSuccess
        )

        XCTAssertEqual(presentation.quotaLevel, .healthy)
        XCTAssertEqual(presentation.connectionBadge, .refreshing)
        XCTAssertTrue(presentation.usesCachedData)
        XCTAssertFalse(presentation.isIdle)
        XCTAssertEqual(presentation.lastSuccess, lastSuccess)
        XCTAssertEqual(presentation.freshness, .lastSuccess(lastSuccess))
        XCTAssertEqual(presentation.issue, .totalTimedOut)
    }

    func testIdleAndConnectedRemainDistinctWithoutVisibleBadge() {
        let idle = makePresentation(
            remainingPercent: nil,
            state: .idle,
            lastSuccessfulFetch: nil
        )
        let connected = makePresentation(
            state: .connected,
            lastSuccessfulFetch: lastSuccess
        )

        XCTAssertEqual(idle.connectionBadge, .none)
        XCTAssertTrue(idle.isIdle)
        XCTAssertEqual(idle.freshness, .none)
        XCTAssertEqual(connected.connectionBadge, .none)
        XCTAssertFalse(connected.isIdle)
        XCTAssertEqual(connected.freshness, .updated(lastSuccess))
    }

    func testMenuBarAccessibilitySummaryUsesEnglishQuotaConnectionAndFreshness() {
        let now = lastSuccess.addingTimeInterval(27 * 60)
        let presentation = makePresentation(
            remainingPercent: 32,
            state: .connected,
            lastSuccessfulFetch: lastSuccess
        )

        XCTAssertEqual(
            StatusAccessibilityString.quotaSummary(
                bucketName: "Codex",
                window: window(.weekly, remainingPercent: 32),
                presentation: presentation,
                now: now,
                language: .english
            ),
            "Codex, Weekly quota, 32% remaining, Connected, updated 27 minutes ago"
        )
    }

    func testMenuBarAccessibilitySummaryUsesChineseRefreshingCachedContext() {
        let now = lastSuccess.addingTimeInterval(27 * 60)
        let presentation = makePresentation(
            remainingPercent: 100,
            state: .stale(lastSuccess: lastSuccess, issue: .requestTimedOut),
            isRefreshing: true,
            lastSuccessfulFetch: lastSuccess
        )

        XCTAssertEqual(
            StatusAccessibilityString.quotaSummary(
                bucketName: "GPT-5.3-Codex-Spark",
                window: window(.fiveHour, remainingPercent: 100),
                presentation: presentation,
                now: now,
                language: .simplifiedChinese
            ),
            "GPT-5.3-Codex-Spark, 5 小时额度, 剩余 100%, 正在刷新, 缓存数据, 上次成功于 27 分钟前"
        )
    }

    func testMenuBarAccessibilitySummaryDistinguishesUnavailableAndRefreshingNoData() {
        let unavailable = makePresentation(
            remainingPercent: nil,
            state: .unavailable(.requestTimedOut),
            lastSuccessfulFetch: nil
        )
        let refreshing = makePresentation(
            remainingPercent: nil,
            state: .refreshing,
            isRefreshing: true,
            lastSuccessfulFetch: nil
        )

        XCTAssertEqual(
            StatusAccessibilityString.quotaSummary(
                bucketName: "Codex",
                window: nil,
                presentation: unavailable,
                now: lastSuccess,
                language: .english
            ),
            "Codex, Quota unavailable, Unavailable, no successful data"
        )
        XCTAssertEqual(
            StatusAccessibilityString.quotaSummary(
                bucketName: "Codex",
                window: nil,
                presentation: refreshing,
                now: lastSuccess,
                language: .english
            ),
            "Codex, Quota unavailable, Refreshing, no successful data yet"
        )
    }

    func testMenuBarAccessibilitySummaryClampsFutureTimestampToJustNow() {
        let future = lastSuccess.addingTimeInterval(60)
        let presentation = makePresentation(
            remainingPercent: 80,
            state: .connected,
            lastSuccessfulFetch: future
        )

        let label = StatusAccessibilityString.quotaSummary(
            bucketName: "Codex",
            window: window(.weekly, remainingPercent: 80),
            presentation: presentation,
            now: lastSuccess,
            language: .english
        )

        XCTAssertEqual(
            label,
            "Codex, Weekly quota, 80% remaining, Connected, updated just now"
        )
        XCTAssertFalse(label.contains("limit-id"))
        XCTAssertFalse(label.contains("@"))
        XCTAssertFalse(label.contains("/Users/"))
    }

    private func makePresentation(
        remainingPercent: Int? = 80,
        state: ConnectionState,
        isRefreshing: Bool = false,
        lastSuccessfulFetch: Date?
    ) -> StatusPresentation {
        StatusPresentation(
            remainingPercent: remainingPercent,
            connectionState: state,
            isRefreshing: isRefreshing,
            lastSuccessfulFetch: lastSuccessfulFetch
        )
    }

    private func window(
        _ kind: QuotaWindowKind,
        remainingPercent: Int
    ) -> QuotaWindowSnapshot {
        QuotaWindowSnapshot(
            kind: kind,
            usedPercent: 100 - remainingPercent,
            windowMinutes: kind == .fiveHour ? 300 : 10_080,
            resetsAt: nil
        )
    }
}
