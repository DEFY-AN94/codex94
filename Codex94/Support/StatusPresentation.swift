import Foundation

enum QuotaLevel: Equatable, Sendable {
    case unknown
    case healthy
    case warning
    case critical

    init(remainingPercent: Int?) {
        guard let remainingPercent else {
            self = .unknown
            return
        }
        if remainingPercent >= 50 {
            self = .healthy
        } else if remainingPercent >= 20 {
            self = .warning
        } else {
            self = .critical
        }
    }
}

enum ConnectionBadge: Equatable, Sendable {
    case none
    case refreshing
    case stale
    case unavailable
}

struct StatusPresentation: Equatable, Sendable {
    let quotaLevel: QuotaLevel
    let connectionBadge: ConnectionBadge
    let usesCachedData: Bool
    let isIdle: Bool
    let lastSuccess: Date?
    let issue: ConnectionIssue?

    init(
        remainingPercent: Int?,
        connectionState: ConnectionState,
        isRefreshing: Bool
    ) {
        quotaLevel = QuotaLevel(remainingPercent: remainingPercent)

        let stateRequestsRefresh: Bool
        switch connectionState {
        case .refreshing:
            stateRequestsRefresh = true
        default:
            stateRequestsRefresh = false
        }

        switch connectionState {
        case .idle:
            isIdle = true
            usesCachedData = false
            lastSuccess = nil
            issue = nil
        case .refreshing, .connected:
            isIdle = false
            usesCachedData = false
            lastSuccess = nil
            issue = nil
        case let .stale(lastSuccess, issue):
            isIdle = false
            usesCachedData = true
            self.lastSuccess = lastSuccess
            self.issue = issue
        case let .unavailable(issue):
            isIdle = false
            usesCachedData = false
            lastSuccess = nil
            self.issue = issue
        }

        if isRefreshing || stateRequestsRefresh {
            connectionBadge = .refreshing
        } else if usesCachedData {
            connectionBadge = .stale
        } else if case .unavailable = connectionState {
            connectionBadge = .unavailable
        } else {
            connectionBadge = .none
        }
    }
}
