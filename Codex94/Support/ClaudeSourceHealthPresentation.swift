import Foundation

/// A finished diagnostic and its own completion time. Request identity stays
/// inside the store and is never part of a presentation or exported value.
struct ClaudeCLIReadDiagnosticRecord: Equatable, Sendable {
    let diagnostic: ClaudeCLIUsageDiagnostic
    let completedAt: Date
}

/// Pure projection of already accepted state. Source checks, report selection,
/// notifications and recovery operations remain owned by ClaudeQuotaStore.
struct ClaudeSourceHealthPresentation: Equatable, Sendable {
    enum DataState: String, Equatable, Sendable {
        case disabled, current, cached, history, unavailable
    }
    enum OperationState: String, Equatable, Sendable {
        case idle, reading, retiring
    }
    enum Action: Equatable, Sendable {
        case rereadLocalReports, reviewStatusline, readOnceWithCLI, openDiagnostics
    }

    let dataState: DataState
    let operationState: OperationState
    let source: ClaudeQuotaSource?
    let reportedAt: Date?
    let localCacheState: ClaudeLocalUsageCacheState?
    let statuslineSetupState: ClaudeStatuslineSetupState
    let needsSourceConfirmation: Bool
    let pendingReportedAt: Date?
    let isCLIUsageEnabled: Bool
    let canReadOnceWithCLI: Bool
    let lastReadIssue: ClaudeQuotaIssue?
    let lastReadAt: Date?
    let lastDiagnostic: ClaudeCLIReadDiagnosticRecord?

    var actions: [Action] {
        guard dataState != .disabled else { return [.openDiagnostics] }
        var result: [Action] = [.rereadLocalReports]
        if needsSourceConfirmation || statuslineSetupState != .installed {
            result.append(.reviewStatusline)
        }
        if canReadOnceWithCLI && operationState == .idle { result.append(.readOnceWithCLI) }
        result.append(.openDiagnostics)
        return result
    }

    static func project(
        isEnabled: Bool,
        acceptedReport: ClaudeQuotaReport?,
        at date: Date,
        baseline: TimeInterval = 600,
        refreshInterval: TimeInterval = 300,
        localCacheMaximumAge: TimeInterval = ClaudeQuotaFreshnessPolicy.localCacheMaximumAge,
        localCacheState: ClaudeLocalUsageCacheState = .absent,
        statuslineSetupState: ClaudeStatuslineSetupState = .notInstalled,
        needsSourceConfirmation: Bool = false,
        pendingReportedAt: Date? = nil,
        isRefreshing: Bool = false,
        isRetiringCLI: Bool = false,
        isCLIUsageEnabled: Bool = false,
        canReadOnceWithCLI: Bool = false,
        lastReadIssue: ClaudeQuotaIssue? = nil,
        lastReadAt: Date? = nil,
        lastDiagnostic: ClaudeCLIReadDiagnosticRecord? = nil
    ) -> Self {
        let state: DataState
        if !isEnabled { state = .disabled }
        else if let acceptedReport {
            if acceptedReport.snapshot(at: date) != nil {
                state = ClaudeQuotaFreshnessPolicy.isCurrent(
                    acceptedReport, at: date, baseline: baseline,
                    refreshInterval: refreshInterval, localCache: localCacheMaximumAge
                ) ? .current : .cached
            } else {
                state = ClaudeQuotaHistoryPresentation(report: acceptedReport, at: date) == nil
                    ? .unavailable : .history
            }
        } else { state = .unavailable }

        return Self(
            dataState: state,
            operationState: !isEnabled ? .idle : (isRetiringCLI ? .retiring : (isRefreshing ? .reading : .idle)),
            source: isEnabled ? acceptedReport?.source : nil,
            reportedAt: isEnabled ? acceptedReport?.reportedAt : nil,
            localCacheState: isEnabled ? localCacheState : nil,
            statuslineSetupState: statuslineSetupState,
            needsSourceConfirmation: isEnabled && needsSourceConfirmation,
            pendingReportedAt: isEnabled && needsSourceConfirmation ? pendingReportedAt : nil,
            isCLIUsageEnabled: isCLIUsageEnabled,
            canReadOnceWithCLI: isEnabled && canReadOnceWithCLI && !isRefreshing && !isRetiringCLI,
            lastReadIssue: isEnabled ? lastReadIssue : nil,
            lastReadAt: isEnabled ? lastReadAt : nil,
            lastDiagnostic: isEnabled ? lastDiagnostic : nil
        )
    }
}
