import Foundation
import XCTest
@testable import Codex94

@MainActor
final class ClaudeOAuthClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let token = "SYNTHETIC-OAUTH-TOKEN-NOT-A-CREDENTIAL"
    private let account = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    private let organization = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!

    func testProductionCredentialProviderIsUnavailableForEveryOperation() async {
        let provider = UnavailableClaudeOAuthCredentialProvider()
        await assertIssue(.integrationUnavailable) { _ = try await provider.credential() }
        await assertIssue(.integrationUnavailable) { _ = try await provider.renewApplicationOwnedCredential(matching: UUID()) }
        await assertIssue(.integrationUnavailable) { _ = try await provider.reloadExternalCredential(matching: UUID()) }
    }

    func testCredentialRecoveryRoutesByOwnershipOnceAndMatchesTheOldGeneration() async throws {
        for ownership in [ClaudeOAuthCredentialOwnership.applicationOwned, .externalReadOnly] {
            let original = try credential(ownership: ownership)
            let replacement = try credential(ownership: ownership)
            let provider = OAuthCredentialFake(replacement: replacement)
            let result = try await ClaudeOAuthCredentialRecovery.recover(original, using: provider)
            XCTAssertEqual(result.contextID, replacement.contextID)
            let calls = await provider.calls
            XCTAssertEqual(calls.map(\.operation), [ownership == .applicationOwned ? "renew" : "reload"])
            XCTAssertEqual(calls.map(\.contextID), [original.contextID])
        }
    }

    func testRecoveryRejectsOwnershipTransferAndRedactsUnknownProviderErrors() async throws {
        let external = try credential(ownership: .externalReadOnly)
        let replacement = try credential(ownership: .applicationOwned)
        await assertIssue(.invalidCredential) {
            _ = try await ClaudeOAuthCredentialRecovery.recover(external, using: OAuthCredentialFake(replacement: replacement))
        }
        let provider = OAuthCredentialFake(replacement: external, shouldFail: true)
        await assertIssue(.notConnected) { _ = try await ClaudeOAuthCredentialRecovery.recover(external, using: provider) }
        let calls = await provider.calls
        XCTAssertEqual(calls.map(\.operation), ["reload"], "An external credential must never enter the renewal operation")
    }

    func testCredentialDescriptionsAreRedactedAndHeaderInjectionIsRejected() throws {
        let value = try credential()
        XCTAssertEqual(String(describing: value), "ClaudeOAuthCredential(<redacted>)")
        XCTAssertFalse(String(reflecting: value).contains(token))
        for invalid in ["", "has space", "line\r\ninjection", "nonASCII-é", String(repeating: "a", count: 16_385)] {
            XCTAssertThrowsError(try ClaudeOAuthCredential(accessToken: invalid, contextID: UUID(), ownership: .externalReadOnly,
                                                          scopes: ["user:profile"])) {
                XCTAssertEqual($0 as? ClaudeOAuthIssue, .invalidCredential)
            }
        }
    }

    func testExpiredOrInsufficientScopeCredentialDoesNotReachTransport() async throws {
        let transport = OAuthTransportFake(data: weeklyData())
        let clock = now
        let client = ClaudeOAuthUsageClient(transport: transport, now: { clock })
        await assertIssue(.expired) { _ = try await client.fetchUsage(using: credential(expiresAt: now)) }
        let inferenceOnly = try credential(scopes: ["user:inference"])
        await assertIssue(.insufficientScope) { _ = try await client.fetchUsage(using: inferenceOnly) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCredentialCannotWriteAuthorizationToExternalOrMessageDestinations() throws {
        let value = try credential()
        for url in ["https://example.invalid/collect", "https://api.anthropic.com/v1/messages"] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: url)), timeoutInterval: 10)
            XCTAssertThrowsError(try value.authorize(&request, now: now)) {
                XCTAssertEqual($0 as? ClaudeOAuthIssue, .invalidDestination)
            }
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        }
        var post = URLRequest(url: ClaudeOAuthUsageClient.usageEndpoint, timeoutInterval: 10)
        post.httpMethod = "POST"
        XCTAssertThrowsError(try value.authorize(&post, now: now)) {
            XCTAssertEqual($0 as? ClaudeOAuthIssue, .invalidDestination)
        }
        XCTAssertNil(post.value(forHTTPHeaderField: "Authorization"))
        for endpoint in [ClaudeOAuthUsageClient.usageEndpoint, ClaudeOAuthUsageClient.profileEndpoint] {
            var request = URLRequest(url: endpoint, timeoutInterval: 2)
            try value.authorize(&request, now: now)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + token)
        }
    }

    func testUsageOnlyUsesExactEndpointHeadersAndPreservesReceiptTime() async throws {
        let transport = OAuthTransportFake(data: weeklyData())
        let clock = now
        let client = ClaudeOAuthUsageClient(transport: transport, now: { clock })
        let value = try await client.fetchUsage(using: credential())
        XCTAssertEqual(value.receivedAt, now)
        XCTAssertEqual(value.windows.map(\.kind), [.weekly])
        XCTAssertEqual(value.windows.first?.usedPercentage, 61.25)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1, "Quota completion does not wait for or secretly request profile")
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, ClaudeOAuthUsageClient.usageEndpoint)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + token)
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Codex94-quota-monitor")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertNil(request.httpBody)
    }

    func testUsageCompletesWhileIndependentProfileRequestRemainsPending() async throws {
        let transport = OAuthTransportFake(data: weeklyData(), holdsProfile: true)
        let clock = now
        let client = ClaudeOAuthUsageClient(transport: transport, now: { clock })
        let value = try credential()
        let profile = Task { try await client.fetchProfile(using: value) }
        defer { profile.cancel() }
        let deadline = Date().addingTimeInterval(2)
        while !(await transport.profileStarted), Date() < deadline { await Task.yield() }
        let started = await transport.profileStarted
        XCTAssertTrue(started)
        let usage = try await client.fetchUsage(using: value)
        XCTAssertEqual(usage.windows.count, 1)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url), [ClaudeOAuthUsageClient.profileEndpoint, ClaudeOAuthUsageClient.usageEndpoint])
        XCTAssertEqual(requests.map(\.timeoutInterval), [2, 10])
        profile.cancel()
        do { _ = try await profile.value; XCTFail("Expected cancellation of the still-pending profile") }
        catch is CancellationError { }
    }

    func testKnownWindowsAllowFractionsEndpointsOptionalResetAndUnknownExtensions() throws {
        let raw = #"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":100,"resets_at":"2028-02-29T23:59:59.125+01:00"},"seven_day_opus":{"new_shape":true},"extra_usage":false}"#
        let value = try ClaudeOAuthResponseParser.usage(Data(raw.utf8), receivedAt: now)
        XCTAssertEqual(value.windows.map(\.usedPercentage), [0, 100])
        XCTAssertNil(value.windows[0].resetsAt)
        XCTAssertEqual(value.windows[1].resetsAt, ClaudeOAuthResponseParser.timestamp("2028-02-29T22:59:59.125Z"))
        let weekly = try ClaudeOAuthResponseParser.usage(weeklyData(), receivedAt: now)
        XCTAssertEqual(weekly.windows.count, 1)
        XCTAssertNil(weekly.windows[0].resetsAt)
    }

    func testMissingNullWindowsAreDistinctFromMalformedKnownWindows() throws {
        for raw in [#"{}"#, #"{"five_hour":null,"seven_day":null}"#, #"{"extra_usage":{"utilization":1}}"#] {
            XCTAssertThrowsError(try ClaudeOAuthResponseParser.usage(Data(raw.utf8), receivedAt: now)) {
                XCTAssertEqual($0 as? ClaudeOAuthIssue, .noSupportedWindows)
            }
        }
        for malformed in ["true", "[]", "2", #"{"utilization":true}"#, #"{"utilization":"4"}"#,
                          #"{"utilization":-0.1}"#, #"{"utilization":100.1}"#, #"{"utilization":null}"#, "{}"] {
            let raw = "{\"five_hour\":\(malformed),\"seven_day\":{\"utilization\":20}}"
            XCTAssertThrowsError(try ClaudeOAuthResponseParser.usage(Data(raw.utf8), receivedAt: now)) {
                XCTAssertEqual($0 as? ClaudeOAuthIssue, .invalidData, "Never silently discard a corrupt known window")
            }
        }
        for raw in [#"{"five_hour":{"utilization":1e999}}"#, #"{"five_hour":{"utilization":NaN}}"#, "[]"] {
            XCTAssertThrowsError(try ClaudeOAuthResponseParser.usage(Data(raw.utf8), receivedAt: now))
        }
    }

    func testResetsRejectBooleanNumericInvalidCalendarAndMissingZone() throws {
        let invalidValues = ["true", "1800000000", #""2027-02-29T00:00:00Z""#, #""2028-02-30T00:00:00Z""#,
                             #""2028-01-01T24:00:00Z""#, #""2028-01-01T00:00:00""#, #""0000-01-01T00:00:00Z""#]
        for reset in invalidValues {
            let raw = "{\"seven_day\":{\"utilization\":12.5,\"resets_at\":\(reset)}}"
            XCTAssertThrowsError(try ClaudeOAuthResponseParser.usage(Data(raw.utf8), receivedAt: now)) {
                XCTAssertEqual($0 as? ClaudeOAuthIssue, .invalidData)
            }
        }
    }

    func testProfileRequiresUnambiguousAccountAndOrganizationAndDropsOtherData() throws {
        let raw = "{\"account\":{\"uuid\":\"\(account.uuidString.lowercased())\",\"email\":\"test@example.com\"},"
            + "\"organization\":{\"uuid\":\"\(organization.uuidString.lowercased())\"},\"account_uuid\":\"\(account.uuidString)\"}"
        let value = try ClaudeOAuthResponseParser.profile(Data(raw.utf8))
        XCTAssertEqual(value, ClaudeOAuthAccountContext(accountID: account, organizationID: organization))
        let encoded = try JSONEncoder().encode(value)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("ignored"))
        let aliases = "{\"accountUuid\":\"\(account.uuidString)\",\"organization_uuid\":\"\(organization.uuidString)\"}"
        XCTAssertEqual(try ClaudeOAuthResponseParser.profile(Data(aliases.utf8)), value)
        for bad in [#"{"account":{"uuid":true}}"#, #"{"account":{"uuid":"not-a-uuid"}}"#,
                    "{\"account_uuid\":\"\(account.uuidString)\"}",
                    raw.dropLast() + ",\"accountUuid\":\"\(organization.uuidString)\"}"] {
            XCTAssertThrowsError(try ClaudeOAuthResponseParser.profile(Data(bad.utf8))) {
                XCTAssertEqual($0 as? ClaudeOAuthIssue, .invalidData)
            }
        }
    }

    func testHTTPClassificationDoesNotRetryRenewOrReturnRawErrorBodies() async throws {
        let clock = now
        let value = try credential()
        let cases: [(Int, String, ClaudeOAuthIssue)] = [
            (401, "sensitive response", .unauthorized),
            (403, #"{"error":{"type":"insufficient_scope","message":"secret"}}"#, .insufficientScope),
            (403, #"{"error":{"type":"access_denied","message":"secret"}}"#, .accessDenied),
            (403, #"{"error":{"type":"permission_error","message":"secret"}}"#, .forbidden),
            (403, "not JSON sensitive response", .forbidden), (503, "secret", .server),
            (302, "secret", .invalidDestination), (418, "secret", .invalidResponse)
        ]
        for (status, body, expected) in cases {
            let transport = OAuthTransportFake(data: Data(body.utf8), status: status)
            let client = ClaudeOAuthUsageClient(transport: transport, now: { clock })
            await assertIssue(expected) { _ = try await client.fetchUsage(using: value) }
            let count = await transport.requests.count
            XCTAssertEqual(count, 1, "HTTP classification must not create implicit retries or credential renewal")
            XCTAssertFalse(String(reflecting: expected).contains("secret"))
        }
    }

    func testRateLimitUsesSecondsHTTPDateAndConservativeInvalidHeaderFallback() async throws {
        let clock = now
        let value = try credential()
        let cases: [(String?, Date)] = [("600", now.addingTimeInterval(600)), ("0", now),
                                      (nil, now.addingTimeInterval(300)), ("-1", now.addingTimeInterval(300)),
                                      ("NaN", now.addingTimeInterval(300)), ("1.5", now.addingTimeInterval(300))]
        for (header, expected) in cases {
            let transport = OAuthTransportFake(data: Data(), status: 429, headers: header.map { ["retry-after": $0] } ?? [:])
            let client = ClaudeOAuthUsageClient(transport: transport, now: { clock })
            await assertIssue(.rateLimited(retryNotBefore: expected)) { _ = try await client.fetchUsage(using: value) }
        }
        let date = try XCTUnwrap(ClaudeOAuthResponseParser.timestamp("2028-01-01T00:00:00Z"))
        XCTAssertEqual(ClaudeOAuthResponseParser.retryNotBefore("Sat, 01 Jan 2028 00:00:00 GMT", now: now), date)
        XCTAssertEqual(ClaudeOAuthResponseParser.retryNotBefore("Sat, 30 Feb 2028 00:00:00 GMT", now: now), now.addingTimeInterval(300))
    }

    func testTransportRejectsUnapprovedHostPathMethodQueryAndBodyBeforeSending() async throws {
        OAuthURLProtocolFake.storage.set(.init(data: weeklyData()))
        let transport = ClaudeOAuthURLSessionTransport(protocolClass: OAuthURLProtocolFake.self)
        var userInfo = URLComponents(url: ClaudeOAuthUsageClient.usageEndpoint, resolvingAgainstBaseURL: false)!
        userInfo.user = "synthetic"
        let urls = ["https://example.invalid/api/oauth/usage", "http://api.anthropic.com/api/oauth/usage",
                    "https://api.anthropic.com/v1/messages", "https://api.anthropic.com/api/oauth/usage?token=x",
                    "https://api.anthropic.com/api/oauth/usage#fragment", try XCTUnwrap(userInfo.url).absoluteString,
                    "https://api.anthropic.com:444/api/oauth/usage"]
        for url in urls {
            let request = URLRequest(url: try XCTUnwrap(URL(string: url)), timeoutInterval: 10)
            await assertIssue(.invalidDestination) { _ = try await transport.response(for: request) }
        }
        var post = URLRequest(url: ClaudeOAuthUsageClient.usageEndpoint, timeoutInterval: 10)
        post.httpMethod = "POST"
        await assertIssue(.invalidDestination) { _ = try await transport.response(for: post) }
        var body = URLRequest(url: ClaudeOAuthUsageClient.usageEndpoint, timeoutInterval: 10)
        body.httpBody = Data("{}".utf8)
        await assertIssue(.invalidDestination) { _ = try await transport.response(for: body) }
        let excessiveProfileBudget = URLRequest(url: ClaudeOAuthUsageClient.profileEndpoint, timeoutInterval: 3)
        await assertIssue(.invalidDestination) { _ = try await transport.response(for: excessiveProfileBudget) }
        XCTAssertTrue(OAuthURLProtocolFake.storage.requests().isEmpty)
    }

    func testURLProtocolExercisesRealTransportForUsageAndProfileWithoutDiskState() async throws {
        let clock = now
        let transport = ClaudeOAuthURLSessionTransport(protocolClass: OAuthURLProtocolFake.self)
        let client = ClaudeOAuthUsageClient(transport: transport, now: { clock })
        OAuthURLProtocolFake.storage.set(.init(data: weeklyData()))
        let usage = try await client.fetchUsage(using: credential())
        XCTAssertEqual(usage.windows.first?.usedPercentage, 61.25)
        let profile = "{\"account_uuid\":\"\(account.uuidString)\",\"organization_uuid\":\"\(organization.uuidString)\"}"
        OAuthURLProtocolFake.storage.set(.init(data: Data(profile.utf8)))
        let identity = try await client.fetchProfile(using: credential())
        XCTAssertEqual(identity.accountID, account)
        XCTAssertEqual(OAuthURLProtocolFake.storage.requests().map(\.url), [ClaudeOAuthUsageClient.profileEndpoint])
        let configuration = ClaudeOAuthURLSessionTransport.configuration(timeout: 2)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 2)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 2)
    }

    func testRealTransportRejectsAdvertisedAndStreamedOversizeBodies() async throws {
        let clock = now
        let client = ClaudeOAuthUsageClient(transport: ClaudeOAuthURLSessionTransport(protocolClass: OAuthURLProtocolFake.self), now: { clock })
        let value = try credential()
        OAuthURLProtocolFake.storage.set(.init(data: Data(), headers: ["Content-Length": "65537"]))
        await assertIssue(.responseTooLarge) { _ = try await client.fetchUsage(using: value) }
        OAuthURLProtocolFake.storage.set(.init(data: Data(repeating: 32, count: 65_537)))
        await assertIssue(.responseTooLarge) { _ = try await client.fetchUsage(using: value) }
    }

    func testUnexpectedResponseDestinationAndRedirectAreRejected() async throws {
        let clock = now
        let value = try credential()
        let wrong = OAuthTransportFake(data: weeklyData(), responseURL: URL(string: "https://example.invalid/quota")!)
        await assertIssue(.invalidDestination) {
            _ = try await ClaudeOAuthUsageClient(transport: wrong, now: { clock }).fetchUsage(using: value)
        }
        let client = ClaudeOAuthUsageClient(transport: ClaudeOAuthURLSessionTransport(protocolClass: OAuthURLProtocolFake.self), now: { clock })
        OAuthURLProtocolFake.storage.set(.init(data: Data(), status: 302,
                                             headers: ["Location": "https://example.invalid/redirect"]))
        await assertIssue(.invalidDestination) { _ = try await client.fetchUsage(using: value) }
        XCTAssertEqual(OAuthURLProtocolFake.storage.requests().count, 1)

        // Exercise the actual redirect delegate too, with an inert task that is
        // never resumed. No URLSession request leaves this test process.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: ClaudeOAuthUsageClient.usageEndpoint)
        let delegate = ClaudeOAuthSessionDelegate()
        let response = try XCTUnwrap(HTTPURLResponse(url: ClaudeOAuthUsageClient.usageEndpoint, statusCode: 302,
                                                   httpVersion: "HTTP/1.1", headerFields: nil))
        for target in [ClaudeOAuthUsageClient.profileEndpoint, URL(string: "https://example.invalid/redirect")!] {
            var redirected = URLRequest(url: target)
            redirected.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            var completed = false
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) { forwarded in
                completed = true
                XCTAssertNil(forwarded, "No destination receives the original credential through a redirect")
            }
            XCTAssertTrue(completed)
        }
    }

    func testNetworkErrorsAreTypedAndCancelledTasksStayCancelled() async throws {
        let clock = now
        let value = try credential()
        let client = ClaudeOAuthUsageClient(transport: ClaudeOAuthURLSessionTransport(protocolClass: OAuthURLProtocolFake.self), now: { clock })
        for (code, issue) in [(URLError.Code.timedOut, ClaudeOAuthIssue.timedOut), (.notConnectedToInternet, .network)] {
            OAuthURLProtocolFake.storage.set(.init(data: Data(), error: code))
            await assertIssue(issue) { _ = try await client.fetchUsage(using: value) }
        }
        OAuthURLProtocolFake.storage.set(.init(data: Data(), error: .cancelled))
        do { _ = try await client.fetchUsage(using: value); XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }

    private func credential(ownership: ClaudeOAuthCredentialOwnership = .externalReadOnly,
                            expiresAt: Date? = nil, scopes: Set<String> = ["user:profile"]) throws -> ClaudeOAuthCredential {
        try ClaudeOAuthCredential(accessToken: token, contextID: UUID(), ownership: ownership, expiresAt: expiresAt, scopes: scopes)
    }

    private func weeklyData() -> Data { Data(#"{"five_hour":null,"seven_day":{"utilization":61.25}}"#.utf8) }

    private func assertIssue(_ issue: ClaudeOAuthIssue, operation: () async throws -> Void,
                             file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected \(issue)", file: file, line: line) }
        catch { XCTAssertEqual(error as? ClaudeOAuthIssue, issue, file: file, line: line) }
    }
}

private actor OAuthCredentialFake: ClaudeOAuthCredentialProvider {
    struct Call: Sendable { let operation: String; let contextID: UUID }
    let replacement: ClaudeOAuthCredential
    let shouldFail: Bool
    private(set) var calls: [Call] = []
    init(replacement: ClaudeOAuthCredential, shouldFail: Bool = false) {
        self.replacement = replacement
        self.shouldFail = shouldFail
    }
    func credential() async throws -> ClaudeOAuthCredential { replacement }
    func renewApplicationOwnedCredential(matching contextID: UUID) async throws -> ClaudeOAuthCredential {
        calls.append(Call(operation: "renew", contextID: contextID))
        return try result()
    }
    func reloadExternalCredential(matching contextID: UUID) async throws -> ClaudeOAuthCredential {
        calls.append(Call(operation: "reload", contextID: contextID))
        return try result()
    }
    private func result() throws -> ClaudeOAuthCredential {
        if shouldFail { throw NSError(domain: "synthetic", code: 1, userInfo: [NSLocalizedDescriptionKey: "sensitive renewal body"]) }
        return replacement
    }
}

private actor OAuthTransportFake: ClaudeOAuthHTTPTransport {
    let data: Data
    let status: Int
    let headers: [String: String]
    let responseURL: URL?
    let holdsProfile: Bool
    private(set) var requests: [URLRequest] = []
    private(set) var profileStarted = false
    init(data: Data, status: Int = 200, headers: [String: String] = [:], responseURL: URL? = nil, holdsProfile: Bool = false) {
        self.data = data
        self.status = status
        self.headers = headers
        self.responseURL = responseURL
        self.holdsProfile = holdsProfile
    }
    func response(for request: URLRequest) async throws -> ClaudeOAuthHTTPResponse {
        requests.append(request)
        if holdsProfile && request.url == ClaudeOAuthUsageClient.profileEndpoint {
            profileStarted = true
            try await Task.sleep(for: .seconds(30))
            throw ClaudeOAuthIssue.timedOut
        }
        return ClaudeOAuthHTTPResponse(url: responseURL ?? request.url!, statusCode: status, headers: headers, data: data)
    }
}

private final class OAuthURLProtocolFake: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        let data: Data
        var status = 200
        var headers: [String: String] = [:]
        var error: URLError.Code?
    }
    final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var reply = Reply(data: Data())
        private var captured: [URLRequest] = []
        func set(_ value: Reply) { lock.withLock { reply = value; captured = [] } }
        func record(_ request: URLRequest) -> Reply { lock.withLock { captured.append(request); return reply } }
        func requests() -> [URLRequest] { lock.withLock { captured } }
    }
    static let storage = Storage()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.storage.record(request)
        if let error = reply.error { client?.urlProtocol(self, didFailWithError: URLError(error)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
