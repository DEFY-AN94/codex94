import Foundation
import XCTest
@testable import Codex94

final class ClaudeQuotaFreshnessPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func report(_ source: ClaudeQuotaSource, at date: Date, used: Double = 40,
                        resetAt: TimeInterval = 5_000) -> ClaudeQuotaReport {
        ClaudeQuotaReport(source: source, reportedAt: date, receivedAt: date,
                          windows: [.init(kind: .fiveHour, usedPercentage: used,
                                          resetsAt: date.addingTimeInterval(resetAt))])
    }

    func testLocalCacheIsPrimaryAndBackupsReplaceItOnlyWhenStrictlyNewer() {
        let local = report(.localCache, at: now)
        let olderStatusline = report(.statusline, at: now.addingTimeInterval(-1))
        let sameStatusline = report(.statusline, at: now)
        let newerStatusline = report(.statusline, at: now.addingTimeInterval(1))
        let newerCLI = report(.cliUsage, at: now.addingTimeInterval(2))

        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: local, statusline: olderStatusline, cli: nil), local)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: local, statusline: sameStatusline, cli: nil), local,
                       "Equal observation times keep the primary source")
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: local, statusline: newerStatusline, cli: nil), newerStatusline)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: local, statusline: newerStatusline, cli: newerCLI), newerCLI)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: nil, statusline: olderStatusline, cli: nil), olderStatusline)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: nil, statusline: nil, cli: newerCLI), newerCLI)
        XCTAssertNil(ClaudeQuotaFreshnessPolicy.select(localCache: nil, statusline: nil, cli: nil))
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: local, statusline: nil,
                                                         cli: report(.cliUsage, at: now)), local,
                       "A CLI read that only matches the cache does not displace it")
    }

    func testFullyExpiredNewerReportCannotHideAUsableOlderReport() {
        let local = report(.localCache, at: now, resetAt: 3_600)
        let backup = report(.statusline, at: now.addingTimeInterval(1), resetAt: 30)
        let later = now.addingTimeInterval(31)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: local, statusline: backup, cli: nil, at: later), local)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: local, statusline: backup, cli: nil,
                                                         at: now.addingTimeInterval(2)), backup)
        XCTAssertNil(ClaudeQuotaFreshnessPolicy.select(localCache: local, statusline: backup, cli: nil,
                                                       at: now.addingTimeInterval(3_600)))
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: local, statusline: backup, cli: nil), backup,
                       "Unfiltered selection retains only the latest source/time diagnostic")
    }

    func testAllSourcesUseTenMinutesWithoutExtendingForSlowChecks() {
        for source in [ClaudeQuotaSource.localCache, .statusline, .cliUsage] {
            for interval in [60.0, 300, 900, 1_800] {
                XCTAssertEqual(ClaudeQuotaFreshnessPolicy.maximumAge(for: source, baseline: 600,
                                                                     refreshInterval: interval), 600)
            }
        }
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.maximumAge(for: .localCache, baseline: 600, refreshInterval: 60, localCache: 5), 5)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.maximumAge(for: .localCache, baseline: 600,
                                                             refreshInterval: 60, localCache: 3_600), 600,
                       "A legacy local cache cutoff must not extend the recent-report boundary")
    }

    func testTenMinuteBoundaryIsExclusiveForDisplayNotificationsAndDeferral() {
        for source in [ClaudeQuotaSource.localCache, .statusline, .cliUsage] {
            let value = report(source, at: now, resetAt: 10_000)
            for elapsed in [0.0, 599.999, 600, 601] {
                let date = now.addingTimeInterval(elapsed)
                let expected = elapsed < 600
                XCTAssertEqual(ClaudeQuotaFreshnessPolicy.isCurrent(value, at: date, baseline: 600,
                                                                    refreshInterval: 1_800), expected)
                XCTAssertEqual(ClaudeQuotaFreshnessPolicy.canNotify(value, at: date,
                                                                    refreshInterval: 1_800), expected)
                XCTAssertEqual(ClaudeQuotaFreshnessPolicy.canDeferAutomaticRead(value, at: date,
                                                                                refreshInterval: 1_800), expected)
            }
        }
    }

    func testFutureReportsDoNotQualifyForAnyRecentDataAction() {
        for source in [ClaudeQuotaSource.localCache, .statusline, .cliUsage] {
            let value = report(source, at: now.addingTimeInterval(1))
            XCTAssertFalse(ClaudeQuotaFreshnessPolicy.isCurrent(value, at: now, baseline: 600, refreshInterval: 300))
            XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canNotify(value, at: now))
            XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canDeferAutomaticRead(value, at: now))
        }
    }

    func testAnExpiredSharedWindowCannotNotifyOrDeferEvenWithRecentReportTime() {
        let statusline = report(.statusline, at: now, resetAt: 100)
        XCTAssertTrue(ClaudeQuotaFreshnessPolicy.isCurrent(statusline, at: now.addingTimeInterval(99), baseline: 600, refreshInterval: 300))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.isCurrent(statusline, at: now.addingTimeInterval(100), baseline: 600, refreshInterval: 300),
                       "An expired window leaves nothing current to show")
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canNotify(statusline, at: now.addingTimeInterval(100)))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canDeferAutomaticRead(statusline, at: now.addingTimeInterval(100)))
    }

    func testFiftyMinuteCacheRemainsDisplayableButCannotNotifyOrDefer() {
        let value = report(.localCache, at: now.addingTimeInterval(-3_000), resetAt: 10_000)
        XCTAssertNotNil(value.snapshot(at: now))
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.select(localCache: value, statusline: nil, cli: nil, at: now), value,
                       "Display selection retains usable old values independently of action eligibility")
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.isCurrent(value, at: now, baseline: 600, refreshInterval: 300))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canNotify(value, at: now))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canDeferAutomaticRead(value, at: now))
    }

    func testLaterReceiptDoesNotRenewARepeatedReport() {
        let original = report(.statusline, at: now.addingTimeInterval(-600), resetAt: 10_000)
        let reread = ClaudeQuotaReport(source: original.source, reportedAt: original.reportedAt,
                                      receivedAt: now, windows: original.windows)
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.isCurrent(reread, at: now, baseline: 600, refreshInterval: 300))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canNotify(reread, at: now))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canDeferAutomaticRead(reread, at: now))
        XCTAssertEqual(reread.snapshot(at: now)?.fetchedAt, original.reportedAt)
    }

    func testWeeklyOnlyReportRemainsRecentWithoutInventingFiveHourData() {
        let value = ClaudeQuotaReport(source: .localCache, reportedAt: now, receivedAt: now,
                                      windows: [.init(kind: .weekly, usedPercentage: 60,
                                                      resetsAt: now.addingTimeInterval(7_200))])
        XCTAssertTrue(ClaudeQuotaFreshnessPolicy.isCurrent(value, at: now, baseline: 600, refreshInterval: 300))
        XCTAssertTrue(ClaudeQuotaFreshnessPolicy.canNotify(value, at: now))
        XCTAssertTrue(ClaudeQuotaFreshnessPolicy.canDeferAutomaticRead(value, at: now))
        XCTAssertEqual(value.windows.map(\.kind), [.weekly])
    }

    func testNotificationWatermarkRejectsRepeatsAndOlderSourceFallbacksOnly() {
        let older = report(.localCache, at: now.addingTimeInterval(-20))
        let repeated = report(.statusline, at: now.addingTimeInterval(-10))
        let newer = report(.cliUsage, at: now)
        let watermark = repeated.reportedAt
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canNotify(older, at: now, after: watermark))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canNotify(repeated, at: now, after: watermark))
        XCTAssertTrue(ClaudeQuotaFreshnessPolicy.canNotify(newer, at: now, after: watermark))
        XCTAssertTrue(ClaudeQuotaFreshnessPolicy.canDeferAutomaticRead(repeated, at: now),
                      "A recent repeat may defer a read without creating a new notification observation")
    }

    func testNonpositiveAndNonfiniteThresholdsCannotAuthorizeRecentActions() {
        let value = report(.cliUsage, at: now)
        for cutoff in [0.0, -1, .infinity, .nan] {
            XCTAssertFalse(ClaudeQuotaFreshnessPolicy.isCurrent(value, at: now, baseline: cutoff, refreshInterval: 300))
            XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canNotify(value, at: now, baseline: cutoff))
            XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canDeferAutomaticRead(value, at: now, baseline: cutoff))
        }
    }

    func testInjectedShorterLocalCutoffAppliesToAllThreeDecisions() {
        let value = report(.localCache, at: now)
        let boundary = now.addingTimeInterval(5)
        XCTAssertTrue(ClaudeQuotaFreshnessPolicy.canNotify(value, at: now.addingTimeInterval(4), localCache: 5))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.isCurrent(value, at: boundary, baseline: 600,
                                                            refreshInterval: 300, localCache: 5))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canNotify(value, at: boundary, localCache: 5))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.canDeferAutomaticRead(value, at: boundary, localCache: 5))
    }
}
