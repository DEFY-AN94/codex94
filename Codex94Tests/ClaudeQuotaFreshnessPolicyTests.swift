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

    func testMaximumAgeDependsOnSourceAndRefreshInterval() {
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.maximumAge(for: .localCache, baseline: 600, refreshInterval: 60), 3_600)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.maximumAge(for: .statusline, baseline: 600, refreshInterval: 60), 600)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.maximumAge(for: .cliUsage, baseline: 600, refreshInterval: 60), 600)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.maximumAge(for: .cliUsage, baseline: 600, refreshInterval: 1_800), 1_860)
        XCTAssertEqual(ClaudeQuotaFreshnessPolicy.maximumAge(for: .localCache, baseline: 600, refreshInterval: 60, localCache: 5), 5)
    }

    func testIsCurrentRequiresAgeInsideTheWindowAndVisibleQuota() {
        let local = report(.localCache, at: now, resetAt: 10_000)
        XCTAssertTrue(ClaudeQuotaFreshnessPolicy.isCurrent(local, at: now, baseline: 600, refreshInterval: 300))
        XCTAssertTrue(ClaudeQuotaFreshnessPolicy.isCurrent(local, at: now.addingTimeInterval(3_600), baseline: 600, refreshInterval: 300))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.isCurrent(local, at: now.addingTimeInterval(3_601), baseline: 600, refreshInterval: 300))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.isCurrent(local, at: now.addingTimeInterval(-1), baseline: 600, refreshInterval: 300),
                       "A report from the future is not current")
        let statusline = report(.statusline, at: now, resetAt: 100)
        XCTAssertTrue(ClaudeQuotaFreshnessPolicy.isCurrent(statusline, at: now.addingTimeInterval(99), baseline: 600, refreshInterval: 300))
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.isCurrent(statusline, at: now.addingTimeInterval(100), baseline: 600, refreshInterval: 300),
                       "An expired window leaves nothing current to show")
        XCTAssertFalse(ClaudeQuotaFreshnessPolicy.isCurrent(statusline, at: now.addingTimeInterval(601), baseline: 600, refreshInterval: 300))
    }
}
