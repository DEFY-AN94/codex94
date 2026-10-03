import Foundation

protocol ClaudeOAuthCredentialProvider: Sendable {
    func credential() async throws -> ClaudeOAuthCredential

    /// Implementations must serialize renewal and compare the current generation
    /// before atomically replacing their own credentials. No foreign item writes.
    func renewApplicationOwnedCredential(matching contextID: UUID) async throws -> ClaudeOAuthCredential

    /// A single approved read may discover externally rotated credentials;
    /// never refresh, write, delete, or start a CLI for the external owner.
    func reloadExternalCredential(matching contextID: UUID) async throws -> ClaudeOAuthCredential
}

/// Shipping default until an authorized integration is established. Constructing
/// or querying this provider does not access Keychain, files, browsers or CLI.
struct UnavailableClaudeOAuthCredentialProvider: ClaudeOAuthCredentialProvider {
    func credential() async throws -> ClaudeOAuthCredential { throw ClaudeOAuthIssue.integrationUnavailable }
    func renewApplicationOwnedCredential(matching contextID: UUID) async throws -> ClaudeOAuthCredential {
        throw ClaudeOAuthIssue.integrationUnavailable
    }
    func reloadExternalCredential(matching contextID: UUID) async throws -> ClaudeOAuthCredential {
        throw ClaudeOAuthIssue.integrationUnavailable
    }
}

enum ClaudeOAuthCredentialRecovery {
    /// One explicit recovery operation, without a retry loop. The coordinator
    /// owns the per-refresh budget and must reject results of obsolete tasks.
    static func recover(_ credential: ClaudeOAuthCredential,
                        using provider: any ClaudeOAuthCredentialProvider) async throws -> ClaudeOAuthCredential {
        try Task.checkCancellation()
        do {
            let replacement: ClaudeOAuthCredential
            switch credential.ownership {
            case .applicationOwned:
                replacement = try await provider.renewApplicationOwnedCredential(matching: credential.contextID)
            case .externalReadOnly:
                replacement = try await provider.reloadExternalCredential(matching: credential.contextID)
            }
            try Task.checkCancellation()
            guard replacement.ownership == credential.ownership else { throw ClaudeOAuthIssue.invalidCredential }
            return replacement
        } catch is CancellationError {
            throw CancellationError()
        } catch let issue as ClaudeOAuthIssue {
            throw issue
        } catch {
            // A provider must not leak a platform/renewal error's userInfo.
            throw ClaudeOAuthIssue.notConnected
        }
    }
}
