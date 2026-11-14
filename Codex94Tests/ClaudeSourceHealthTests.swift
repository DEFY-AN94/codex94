import XCTest
@testable import Codex94

final class ClaudeSourceHealthTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 2_000_000_000)

    func testBridgeActivityDoesNotRenewAnOldReportOrManufactureQuota() {
        let activity = ClaudeBridgeHealthState.observed(.init(recordedAt: instant, outcome: .unchanged))
        let oldReport = ClaudeQuotaReport(
            source: .localCache, reportedAt: instant.addingTimeInterval(-3_000), receivedAt: instant,
            windows: [.init(kind: .weekly, usedPercentage: 40, resetsAt: instant.addingTimeInterval(3_600))]
        )
        let value = ClaudeSourceHealthPresentation.project(
            isEnabled: true, acceptedReport: oldReport, at: instant,
            isCLIUsageEnabled: true, bridgeHealth: activity,
            automaticReadState: .cooldown, nextAutomaticCheckAt: instant.addingTimeInterval(60)
        )
        XCTAssertEqual(value.dataState, .cached)
        XCTAssertEqual(value.reportedAt, oldReport.reportedAt)
        XCTAssertEqual(value.bridgeHealth, activity)
        XCTAssertEqual(value.automaticReadState, .cooldown)
        XCTAssertEqual(value.nextAutomaticCheckAt, instant.addingTimeInterval(60))
        let empty = ClaudeSourceHealthPresentation.project(
            isEnabled: true, acceptedReport: nil, at: instant, bridgeHealth: activity
        )
        XCTAssertEqual(empty.dataState, .unavailable)
        XCTAssertNil(empty.reportedAt)
    }

    func testDisabledMonitoringHidesBridgeActivityAndAutomaticSchedule() {
        let value = ClaudeSourceHealthPresentation.project(
            isEnabled: false, acceptedReport: report(), at: instant,
            isCLIUsageEnabled: true,
            bridgeHealth: .observed(.init(recordedAt: instant, outcome: .captured)),
            automaticReadState: .cooldown, nextAutomaticCheckAt: instant.addingTimeInterval(60)
        )
        XCTAssertEqual(value.bridgeHealth, .unavailable)
        XCTAssertEqual(value.automaticReadState, .disabled)
        XCTAssertNil(value.nextAutomaticCheckAt)
    }

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

    func testAgeUsesStrictTenMinuteBoundaryInsteadOfLastOperationIssueOrRefreshInterval() {
        for source in [ClaudeQuotaSource.localCache, .statusline, .cliUsage] {
            let accepted = report(source: source)
            let fresh = ClaudeSourceHealthPresentation.project(
                isEnabled: true, acceptedReport: accepted, at: instant.addingTimeInterval(599.999),
                refreshInterval: 900, localCacheState: .invalid, lastReadIssue: .timedOut
            )
            XCTAssertEqual(fresh.dataState, .current)
            XCTAssertEqual(fresh.lastReadIssue, .timedOut)
            let cached = ClaudeSourceHealthPresentation.project(
                isEnabled: true, acceptedReport: accepted, at: instant.addingTimeInterval(600),
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
