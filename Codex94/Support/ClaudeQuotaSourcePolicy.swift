import Foundation

enum ClaudeQuotaSourceMode: String, CaseIterable, Identifiable, Sendable {
    case oauthPreferred, statuslineOnly, legacyCLI
    var id: String { rawValue }
}

enum ClaudeQuotaIdentityConfidence: Equatable, Sendable {
    case verifiedOAuth, unverifiedLocal, unknown
}

extension ClaudeOAuthIssue {
    var quotaIssue: ClaudeQuotaIssue {
        switch self {
        case .integrationUnavailable: .oauthNotReady
        case .notConnected: .oauthNotConnected
        case .credentialAccessDenied: .oauthCredentialsRestricted
        case .expired, .unauthorized, .invalidCredential: .oauthLoginRequired
        case .insufficientScope: .oauthScopeMissing
        case .accessDenied: .oauthAccessDenied
        case .forbidden: .oauthForbidden
        case .rateLimited: .oauthRateLimited
        case .timedOut: .oauthTimedOut
        case .network: .oauthNetwork
        case .server: .oauthServer
        case .invalidData, .noSupportedWindows, .invalidDestination, .invalidResponse, .responseTooLarge: .oauthInvalidData
        }
    }
}

/// A local session fingerprint can qualify a report for explicit selection,
/// never for automatic association with an OAuth account.
enum ClaudeQuotaSourcePolicy {
    static func isEligiblePassive(_ report: ClaudeQuotaReport, at now: Date,
                                  maximumAge: TimeInterval = 600) -> Bool {
        guard report.source == .statusline,
              ClaudeStatuslineParser.identifiableProducerID(report.producerID) != nil,
              validTimestamp(now), validTimestamp(report.reportedAt), validTimestamp(report.receivedAt),
              report.receivedAt >= report.reportedAt, maximumAge.isFinite, maximumAge >= 0,
              (0...maximumAge).contains(now.timeIntervalSince(report.reportedAt)),
              validWindows(report.windows, requiresReset: true) else { return false }
        return report.windows.contains { $0.resetsAt.map { $0 > now } ?? false }
    }

    static func validWindows(_ windows: [ClaudeQuotaWindow], requiresReset: Bool = false) -> Bool {
        !windows.isEmpty && windows.count <= 2 && Set(windows.map(\.kind)).count == windows.count
            && windows.allSatisfy { window in
                window.usedPercentage.isFinite && (0...100).contains(window.usedPercentage)
                    && (window.resetsAt.map(validTimestamp) ?? !requiresReset)
            }
    }

    static func validTimestamp(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && (0...253_402_300_799).contains(seconds)
    }
}
