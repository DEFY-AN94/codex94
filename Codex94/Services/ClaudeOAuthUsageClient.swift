import Foundation

struct ClaudeOAuthHTTPResponse: Sendable {
    let url: URL
    let statusCode: Int
    let headers: [String: String]
    let data: Data

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

protocol ClaudeOAuthHTTPTransport: Sendable {
    func response(for request: URLRequest) async throws -> ClaudeOAuthHTTPResponse
}

struct ClaudeOAuthUsageClient: ClaudeOAuthUsageFetching {
    static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    static let usageTimeout: TimeInterval = 10
    static let profileTimeout: TimeInterval = 2
    private let transport: any ClaudeOAuthHTTPTransport
    private let now: @Sendable () -> Date

    init(transport: (any ClaudeOAuthHTTPTransport)? = nil, now: (@Sendable () -> Date)? = nil) {
        self.transport = transport ?? ClaudeOAuthURLSessionTransport()
        self.now = now ?? { Date() }
    }

    func fetchUsage(using credential: ClaudeOAuthCredential) async throws -> ClaudeOAuthUsageSnapshot {
        let response = try await response(endpoint: Self.usageEndpoint, timeout: Self.usageTimeout, credential: credential)
        return try ClaudeOAuthResponseParser.usage(response.data, receivedAt: now())
    }

    /// Deliberately independent: callers may publish usage immediately and
    /// verify identity separately. A slow/failed profile never blocks usage here.
    func fetchProfile(using credential: ClaudeOAuthCredential) async throws -> ClaudeOAuthAccountContext {
        let response = try await response(endpoint: Self.profileEndpoint, timeout: Self.profileTimeout, credential: credential)
        return try ClaudeOAuthResponseParser.profile(response.data)
    }

    private func response(endpoint: URL, timeout: TimeInterval,
                          credential: ClaudeOAuthCredential) async throws -> ClaudeOAuthHTTPResponse {
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        // Identify this app honestly; never impersonate Claude Code or run it to
        // discover a version. Actual permitted authentication is still gated.
        request.setValue("Codex94-quota-monitor", forHTTPHeaderField: "User-Agent")
        try credential.authorize(&request, now: now())
        do {
            let response = try await transport.response(for: request)
            try Task.checkCancellation()
            guard response.url == endpoint else { throw ClaudeOAuthIssue.invalidDestination }
            guard response.data.count <= ClaudeOAuthResponseParser.maximumResponseBytes else { throw ClaudeOAuthIssue.responseTooLarge }
            switch response.statusCode {
            case 200: return response
            case 401: throw ClaudeOAuthIssue.unauthorized
            case 403: throw ClaudeOAuthResponseParser.forbidden(response.data)
            case 429: throw ClaudeOAuthIssue.rateLimited(
                retryNotBefore: ClaudeOAuthResponseParser.retryNotBefore(response.header("Retry-After"), now: now())
            )
            case 300...399: throw ClaudeOAuthIssue.invalidDestination
            case 500...599: throw ClaudeOAuthIssue.server
            default: throw ClaudeOAuthIssue.invalidResponse
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let issue as ClaudeOAuthIssue {
            throw issue
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw ClaudeOAuthIssue.timedOut
            default: throw ClaudeOAuthIssue.network
            }
        } catch {
            throw ClaudeOAuthIssue.network
        }
    }

    static func isAllowed(_ request: URLRequest) -> Bool {
        let maximumTimeout: TimeInterval
        switch request.url {
        case usageEndpoint: maximumTimeout = usageTimeout
        case profileEndpoint: maximumTimeout = profileTimeout
        default: return false
        }
        return request.httpMethod == "GET" && request.httpBody == nil && request.httpBodyStream == nil
            && request.timeoutInterval.isFinite && request.timeoutInterval > 0
            && request.timeoutInterval <= maximumTimeout
    }
}

struct ClaudeOAuthURLSessionTransport: ClaudeOAuthHTTPTransport {
    private let protocolClass: URLProtocol.Type?
    init(protocolClass: URLProtocol.Type? = nil) { self.protocolClass = protocolClass }

    func response(for request: URLRequest) async throws -> ClaudeOAuthHTTPResponse {
        guard ClaudeOAuthUsageClient.isAllowed(request) else { throw ClaudeOAuthIssue.invalidDestination }
        try Task.checkCancellation()
        let configuration = Self.configuration(timeout: request.timeoutInterval)
        if let protocolClass { configuration.protocolClasses = [protocolClass] }
        let session = URLSession(configuration: configuration, delegate: ClaudeOAuthSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, rawResponse) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = rawResponse as? HTTPURLResponse, response.url == request.url else {
            throw ClaudeOAuthIssue.invalidDestination
        }
        guard !(300...399).contains(response.statusCode) else { throw ClaudeOAuthIssue.invalidDestination }
        let limit = ClaudeOAuthResponseParser.maximumResponseBytes
        guard response.expectedContentLength <= Int64(limit) else { throw ClaudeOAuthIssue.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw ClaudeOAuthIssue.responseTooLarge }
            data.append(byte)
        }
        var headers: [String: String] = [:]
        // Retry-After is the only response header retained outside URLSession.
        if let value = response.value(forHTTPHeaderField: "Retry-After"), value.utf8.count <= 128 {
            headers["Retry-After"] = value
        }
        return ClaudeOAuthHTTPResponse(url: request.url!, statusCode: response.statusCode, headers: headers, data: data)
    }

    static func configuration(timeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return configuration
    }
}

/// Deny every redirect, even same-host redirects: a bearer token belongs only
/// to the two exact approved GET destinations. Never supply ambient HTTP auth.
final class ClaudeOAuthSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}
