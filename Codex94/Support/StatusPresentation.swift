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

enum FreshnessDetail: Equatable, Sendable {
    case none
    case updated(Date)
    case lastSuccess(Date)
    case noSuccessfulData
    case noSuccessfulDataYet
}

struct StatusPresentation: Equatable, Sendable {
    let quotaLevel: QuotaLevel
    let connectionBadge: ConnectionBadge
    let usesCachedData: Bool
    let isIdle: Bool
    let freshness: FreshnessDetail
    let issue: ConnectionIssue?

    var lastSuccess: Date? {
        switch freshness {
        case let .updated(date), let .lastSuccess(date): date
        case .none, .noSuccessfulData, .noSuccessfulDataYet: nil
        }
    }

    init(
        remainingPercent: Int?,
        connectionState: ConnectionState,
        isRefreshing: Bool,
        lastSuccessfulFetch: Date?
    ) {
        quotaLevel = QuotaLevel(remainingPercent: remainingPercent)

        if case let .stale(stateLastSuccess, _) = connectionState {
            assert(
                stateLastSuccess == lastSuccessfulFetch,
                "Stale connection state must mirror the current snapshot timestamp"
            )
        }

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
            issue = nil
        case .refreshing, .connected:
            isIdle = false
            usesCachedData = false
            issue = nil
        case let .stale(_, issue):
            isIdle = false
            usesCachedData = true
            self.issue = issue
        case let .unavailable(issue):
            isIdle = false
            usesCachedData = false
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

        switch connectionBadge {
        case .refreshing:
            freshness = lastSuccessfulFetch.map(FreshnessDetail.lastSuccess)
                ?? .noSuccessfulDataYet
        case .stale:
            freshness = lastSuccessfulFetch.map(FreshnessDetail.updated)
                ?? .noSuccessfulData
        case .unavailable:
            freshness = .noSuccessfulData
        case .none:
            if isIdle {
                freshness = .none
            } else {
                freshness = lastSuccessfulFetch.map(FreshnessDetail.updated)
                    ?? .noSuccessfulData
            }
        }
    }
}
