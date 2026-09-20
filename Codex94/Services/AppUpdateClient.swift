import Foundation

protocol AppUpdateFetching: Sendable {
    func latestRelease() async throws -> AppRelease
}

struct AppUpdateClient: AppUpdateFetching {
    static let endpoint = URL(string: "https://api.github.com/repos/DEFY-AN94/codex94/releases/latest")!
    static let maximumResponseBytes = 262_144
    private let protocolClass: URLProtocol.Type?

    init(protocolClass: URLProtocol.Type? = nil) {
        self.protocolClass = protocolClass
    }

    func latestRelease() async throws -> AppRelease {
        let configuration = Self.configuration()
        if let protocolClass { configuration.protocolClasses = [protocolClass] }
        let session = URLSession(
            configuration: configuration,
            delegate: AppUpdateSessionDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: Self.request())
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse,
                  response.url == Self.endpoint else { throw AppUpdateIssue.invalidResponse }
            try Self.validateStatus(response)
            guard response.expectedContentLength <= Int64(Self.maximumResponseBytes) else {
                throw AppUpdateIssue.responseTooLarge
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumResponseBytes else { throw AppUpdateIssue.responseTooLarge }
                data.append(byte)
            }
            return try AppRelease.parse(data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let issue as AppUpdateIssue {
            throw issue
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed:
                throw AppUpdateIssue.offline
            case .timedOut: throw AppUpdateIssue.timedOut
            default: throw AppUpdateIssue.unavailable
            }
        } catch {
            throw AppUpdateIssue.unavailable
        }
    }

    static func request() -> URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Codex94-update-check", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        return request
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        return configuration
    }

    static func validateStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200: return
        case 404: throw AppUpdateIssue.noPublishedRelease
        case 429: throw AppUpdateIssue.rateLimited
        case 403 where response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
            || response.value(forHTTPHeaderField: "Retry-After") != nil:
            throw AppUpdateIssue.rateLimited
        case 300...399: throw AppUpdateIssue.invalidResponse
        default: throw AppUpdateIssue.unavailable
        }
    }
}

/// An update check never follows redirects or supplies HTTP credentials.
final class AppUpdateSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
