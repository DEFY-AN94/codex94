import XCTest
@testable import Codex94

final class ClaudeSourceHealthTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 2_000_000_000)

    func testDisabledHealthDoesNotPublishPreviousSourceChecksOrAttempts() {
        let value = ClaudeSourceHealthPresentation.project(
            isEnabled: false, acceptedReport: report(), at: instant,
            localCacheState: .valid, needsSourceConfirmation: true, pendingReportedAt: instant,
            isRefreshing: true, isRetiringCLI: true, canReadOnceWithCLI: true,
            lastReadIssue: .timedOut, lastReadAt: instant
        )
        XCTAssertEqual(value.dataState, .disabled)
        XCTAssertEqual(value.operationState, .idle)
        XCTAssertNil(value.source)
        XCTAssertNil(value.reportedAt)
        XCTAssertNil(value.localCacheState)
        XCTAssertFalse(value.needsSourceConfirmation)
        XCTAssertNil(value.pendingReportedAt)
        XCTAssertFalse(value.canReadOnceWithCLI)
        XCTAssertNil(value.lastReadIssue)
        XCTAssertNil(value.lastReadAt)
        XCTAssertEqual(value.actions, [.openDiagnostics])
    }

    func testAgeUsesAcceptedSourcePolicyInsteadOfLastOperationIssue() {
        for (source, freshThrough) in [(ClaudeQuotaSource.localCache, 3_600.0), (.statusline, 600.0), (.cliUsage, 960.0)] {
            let accepted = report(source: source)
            let fresh = ClaudeSourceHealthPresentation.project(
                isEnabled: true, acceptedReport: accepted, at: instant.addingTimeInterval(freshThrough),
                refreshInterval: 900, localCacheState: .invalid, lastReadIssue: .timedOut
            )
            XCTAssertEqual(fresh.dataState, .current)
            XCTAssertEqual(fresh.lastReadIssue, .timedOut)
            let cached = ClaudeSourceHealthPresentation.project(
                isEnabled: true, acceptedReport: accepted, at: instant.addingTimeInterval(freshThrough + 1),
                refreshInterval: 900, localCacheState: .valid
            )
            XCTAssertEqual(cached.dataState, .cached)
            XCTAssertEqual(cached.reportedAt, instant)
        }
    }

    func testHistoryIsDistinctFromCurrentAndUnavailable() {
        let accepted = report(reset: instant.addingTimeInterval(10))
        let history = ClaudeSourceHealthPresentation.project(
            isEnabled: true, acceptedReport: accepted, at: instant.addingTimeInterval(11)
        )
        XCTAssertEqual(history.dataState, .history)
        XCTAssertEqual(history.reportedAt, instant)
        XCTAssertEqual(history.source, .localCache)
        let empty = ClaudeSourceHealthPresentation.project(isEnabled: true, acceptedReport: nil, at: instant)
        XCTAssertEqual(empty.dataState, .unavailable)
        XCTAssertNil(empty.reportedAt)
    }

    func testValidCacheAndInstalledBridgeDoNotManufactureAcceptedQuota() {
        let value = ClaudeSourceHealthPresentation.project(
            isEnabled: true, acceptedReport: nil, at: instant,
            localCacheState: .valid, statuslineSetupState: .installed
        )
        XCTAssertEqual(value.dataState, .unavailable)
        XCTAssertNil(value.source)
        XCTAssertEqual(value.localCacheState, .valid)
        XCTAssertEqual(value.statuslineSetupState, .installed)
    }

    func testSourceWarningsAndLastReadFailureCanCoexistWithFreshLocalReport() {
        let value = ClaudeSourceHealthPresentation.project(
            isEnabled: true, acceptedReport: report(), at: instant,
            localCacheState: .valid, statuslineSetupState: .differentConfiguration,
            needsSourceConfirmation: true, pendingReportedAt: instant.addingTimeInterval(-20),
            canReadOnceWithCLI: true, lastReadIssue: .loginRequired
        )
        XCTAssertEqual(value.dataState, .current)
        XCTAssertEqual(value.source, .localCache)
        XCTAssertTrue(value.needsSourceConfirmation)
        XCTAssertEqual(value.statuslineSetupState, .differentConfiguration)
        XCTAssertEqual(value.lastReadIssue, .loginRequired)
        XCTAssertEqual(value.actions, [.rereadLocalReports, .reviewStatusline, .readOnceWithCLI, .openDiagnostics])
    }

    func testBusyAndRetiringStatesDisableOnlyCLIReadAction() {
        for retiring in [false, true] {
            let value = ClaudeSourceHealthPresentation.project(
                isEnabled: true, acceptedReport: report(), at: instant,
                statuslineSetupState: .installed, isRefreshing: true,
                isRetiringCLI: retiring, isCLIUsageEnabled: true, canReadOnceWithCLI: true
            )
            XCTAssertEqual(value.dataState, .current)
            XCTAssertEqual(value.operationState, retiring ? .retiring : .reading)
            XCTAssertFalse(value.canReadOnceWithCLI)
            XCTAssertEqual(value.actions, [.rereadLocalReports, .openDiagnostics])
        }
    }

    func testRepeatedProjectionPreservesOriginalReportAndDiagnosticTimes() {
        let diagnostic = ClaudeCLIUsageDiagnostic(phase: .waitingForUsage, result: .failure,
            issue: .timedOut, usageSent: true, terminalReceived: true, durationMilliseconds: 20_001)
        let record = ClaudeCLIReadDiagnosticRecord(diagnostic: diagnostic, completedAt: instant.addingTimeInterval(3))
        for elapsed in [4.0, 60, 180] {
            let value = ClaudeSourceHealthPresentation.project(
                isEnabled: true, acceptedReport: report(), at: instant.addingTimeInterval(elapsed),
                lastReadIssue: .timedOut, lastReadAt: instant.addingTimeInterval(3), lastDiagnostic: record
            )
            XCTAssertEqual(value.reportedAt, instant)
            XCTAssertEqual(value.lastDiagnostic, record)
            XCTAssertEqual(value.lastReadAt, instant.addingTimeInterval(3))
        }
    }

    private func report(source: ClaudeQuotaSource = .localCache, reset: Date? = nil) -> ClaudeQuotaReport {
        ClaudeQuotaReport(source: source, reportedAt: instant, receivedAt: instant,
            windows: [.init(kind: .fiveHour, usedPercentage: 23.5,
                            resetsAt: reset ?? instant.addingTimeInterval(10_000))])
    }
}
