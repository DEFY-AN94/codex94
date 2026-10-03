import Foundation

enum ClaudeQuotaSource: String, Codable, Sendable {
    case oauth
    case statusline
    case cliUsage
}

enum ClaudeQuotaIssue: String, Error, Equatable, Sendable {
    case cliUnavailable, loginRequired, setupRequired, timedOut, invalidData
    case noData, staleData, sourceChanged, configurationConflict, unavailable
    case oauthNotReady, oauthNotConnected, oauthCredentialsRestricted, oauthLoginRequired
    case oauthScopeMissing, oauthAccessDenied, oauthForbidden, oauthRateLimited, oauthNetwork, oauthServer, oauthInvalidData, oauthTimedOut
}

/// An opaque report-stream selection, never proof of account identity.
enum ClaudePassiveProducerID {
    static func normalized(_ value: String?) -> String? {
        guard let value, value.utf8.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            return nil
        }
        return value.lowercased()
    }
}

struct ClaudeQuotaWindow: Codable, Equatable, Sendable {
    let kind: QuotaWindowKind
    let usedPercentage: Double
    let resetsAt: Date?
}

/// `reportedAt` is the last changed report, never the time a cache was reread.
struct ClaudeQuotaReport: Codable, Equatable, Sendable {
    let source: ClaudeQuotaSource
    let reportedAt: Date
    let receivedAt: Date
    let windows: [ClaudeQuotaWindow]
    let producerID: String?
    let accountContext: ClaudeOAuthAccountContext?

    init(source: ClaudeQuotaSource, reportedAt: Date, receivedAt: Date,
         windows: [ClaudeQuotaWindow], producerID: String? = nil,
         accountContext: ClaudeOAuthAccountContext? = nil) {
        self.source = source
        self.reportedAt = reportedAt
        self.receivedAt = receivedAt
        self.windows = windows
        self.producerID = producerID
        self.accountContext = accountContext
    }

    var identityConfidence: ClaudeQuotaIdentityConfidence {
        switch source {
        case .oauth: accountContext == nil ? .unknown : .verifiedOAuth
        case .statusline: .unverifiedLocal
        case .cliUsage: .unknown
        }
    }

    func snapshot(at now: Date) -> QuotaSnapshot? {
        let visible = windows.compactMap { window -> QuotaWindowSnapshot? in
            guard window.resetsAt.map({ $0 > now }) ?? true else { return nil }
            return QuotaWindowSnapshot(
                kind: window.kind, fractionalUsedPercent: window.usedPercentage,
                windowMinutes: window.kind == .fiveHour ? 300 : 10_080, resetsAt: window.resetsAt
            )
        }
        guard !visible.isEmpty else { return nil }
        return QuotaSnapshot(
            buckets: [QuotaBucketSnapshot(limitID: "claude", limitName: nil, planType: nil, windows: visible)],
            defaultLimitID: "claude", fetchedAt: reportedAt, account: nil, codex: nil, provider: .claude
        )
    }
}

protocol ClaudeQuotaFetching: Sendable {
    func fetch() async throws -> ClaudeQuotaReport
    func shutdown()
}

extension ClaudeQuotaFetching {
    func shutdown() {}
}
