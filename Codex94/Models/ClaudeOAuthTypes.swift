import Foundation

/// Fixed classifications only: never retain a response body, credential or
/// underlying network error in state that may reach UI, diagnostics or logs.
enum ClaudeOAuthIssue: Error, Equatable, Sendable {
    case integrationUnavailable, notConnected, credentialAccessDenied, invalidCredential, expired
    case insufficientScope, accessDenied, forbidden, unauthorized
    case rateLimited(retryNotBefore: Date)
    case timedOut, network, server, invalidData, noSupportedWindows
    case invalidDestination, invalidResponse, responseTooLarge
}

enum ClaudeOAuthCredentialOwnership: Sendable {
    case applicationOwned
    case externalReadOnly
}

/// A process-local credential generation, NOT an account identifier. There is
/// intentionally no Codable conformance or refresh-token field.
struct ClaudeOAuthCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let contextID: UUID
    let ownership: ClaudeOAuthCredentialOwnership
    let expiresAt: Date?
    let scopes: Set<String>
    private let accessToken: String

    init(accessToken: String, contextID: UUID, ownership: ClaudeOAuthCredentialOwnership,
         expiresAt: Date? = nil, scopes: Set<String>) throws {
        // Restrict credentials to an ASCII header value, excluding whitespace,
        // control characters and separators outside the bearer-token grammar.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~+/=")
        guard !accessToken.isEmpty, accessToken.utf8.count <= 16_384,
              accessToken.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              expiresAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else {
            throw ClaudeOAuthIssue.invalidCredential
        }
        self.accessToken = accessToken
        self.contextID = contextID
        self.ownership = ownership
        self.expiresAt = expiresAt
        self.scopes = scopes
    }

    var description: String { "ClaudeOAuthCredential(<redacted>)" }
    var debugDescription: String { description }

    func authorize(_ request: inout URLRequest, now: Date) throws {
        guard ClaudeOAuthUsageClient.isAllowed(request) else { throw ClaudeOAuthIssue.invalidDestination }
        guard scopes.contains("user:profile") else { throw ClaudeOAuthIssue.insufficientScope }
        guard expiresAt.map({ $0 > now }) ?? true else { throw ClaudeOAuthIssue.expired }
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
    }
}

struct ClaudeOAuthWindow: Equatable, Sendable {
    let kind: QuotaWindowKind
    let usedPercentage: Double
    let resetsAt: Date?
}

/// receivedAt is the local HTTP completion time, never a fabricated server
/// measurement time. This DTO carries no account association or cached value.
struct ClaudeOAuthUsageSnapshot: Equatable, Sendable {
    let windows: [ClaudeOAuthWindow]
    let receivedAt: Date
}

/// Only a successfully validated profile may supply account/cache isolation.
/// UUID values normalize case and cannot contain an email or bearer token.
struct ClaudeOAuthAccountContext: Codable, Equatable, Sendable {
    let accountID: UUID
    let organizationID: UUID
}

protocol ClaudeOAuthUsageFetching: Sendable {
    func fetchUsage(using credential: ClaudeOAuthCredential) async throws -> ClaudeOAuthUsageSnapshot
    func fetchProfile(using credential: ClaudeOAuthCredential) async throws -> ClaudeOAuthAccountContext
}
