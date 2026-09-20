import XCTest
@testable import Codex94

final class AppUpdateModelTests: XCTestCase {
    func testVersionsUseStrictNumericSemverOrdering() throws {
        XCTAssertLessThan(try XCTUnwrap(AppReleaseVersion("v0.2.9")),
                          try XCTUnwrap(AppReleaseVersion("0.2.10")))
        XCTAssertLessThan(try XCTUnwrap(AppReleaseVersion("0.99.99")),
                          try XCTUnwrap(AppReleaseVersion("1.0.0")))
        XCTAssertEqual(AppReleaseVersion("v0.2.3"), AppReleaseVersion("0.2.3"))
        for invalid in ["", "0.2", "0.2.3.4", "0.02.3", "-1.2.3", "0.2.3-beta",
                        "0.2.3+build", " 0.2.3", "V0.2.3", "０.2.3", "999999999999999999999.0.0"] {
            XCTAssertNil(AppReleaseVersion(invalid), invalid)
        }
    }

    func testReleaseURLsMustMatchTheExactRepositoryAndTag() throws {
        let page = "https://github.com/DEFY-AN94/codex94/releases/tag/v0.2.3"
        var credentialed = URLComponents(string: page)!
        credentialed.user = "user"
        for invalid in [
            page.replacingOccurrences(of: "https:", with: "http:"),
            page.replacingOccurrences(of: "github.com", with: "github.com.evil.example"),
            credentialed.string!,
            page.replacingOccurrences(of: "github.com", with: "github.com:443"),
            page.replacingOccurrences(of: "DEFY-AN94", with: "another-owner"),
            page.replacingOccurrences(of: "v0.2.3", with: "v0.2.4"),
            page.replacingOccurrences(of: "v0.2.3", with: "v0%2E2%2E3"),
            page + "?redirect=elsewhere", page + "#fragment"
        ] {
            XCTAssertThrowsError(try AppRelease.parse(releaseData(page: invalid))) { error in
                XCTAssertEqual(error as? AppUpdateIssue, .invalidResponse)
            }
        }
        XCTAssertEqual(try AppRelease.parse(releaseData()).pageURL.absoluteString, page)
    }

    func testOnlyMatchingUniversalAssetURLsAreRetained() throws {
        let asset = "Codex94-0.2.3-macos-universal-unnotarized.dmg"
        let url = "https://github.com/DEFY-AN94/codex94/releases/download/v0.2.3/\(asset)"
        let valid = try AppRelease.parse(releaseData(assets: [["name": asset, "browser_download_url": url]]))
        XCTAssertEqual(valid.dmgURL?.absoluteString, url)
        for invalid in [
            url.replacingOccurrences(of: "github.com", with: "example.com"),
            url.replacingOccurrences(of: "/v0.2.3/", with: "/v0.2.4/"),
            url.replacingOccurrences(of: "codex94/releases", with: "other/releases"),
            url + "?token=unexpected"
        ] {
            let release = try AppRelease.parse(releaseData(assets: [
                ["name": asset, "browser_download_url": invalid]
            ]))
            XCTAssertNil(release.dmgURL)
            XCTAssertEqual(release.pageURL.host, "github.com")
        }
    }

    func testDraftPrereleaseMalformedPayloadAndLongNotesAreHandled() throws {
        for flags in [(true, false), (false, true)] {
            XCTAssertThrowsError(try AppRelease.parse(releaseData(draft: flags.0, prerelease: flags.1))) {
                XCTAssertEqual($0 as? AppUpdateIssue, .noPublishedRelease)
            }
        }
        XCTAssertThrowsError(try AppRelease.parse(Data("not-json".utf8))) {
            XCTAssertEqual($0 as? AppUpdateIssue, .invalidResponse)
        }
        let release = try AppRelease.parse(releaseData(notes: String(repeating: "x", count: 9_000)))
        XCTAssertEqual(release.notes.count, 8_000)
        let plainNotes = "**Release notes** [external text](https://example.com)"
        XCTAssertEqual(try AppRelease.parse(releaseData(notes: plainNotes)).notes, plainNotes)
    }
}

final class AppUpdateClientTests: XCTestCase {
    func testRequestAndConfigurationContainNoAuthenticationCookiesOrPersistentCache() {
        let request = AppUpdateClient.request()
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.github.com/repos/DEFY-AN94/codex94/releases/latest")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(Set(request.allHTTPHeaderFields?.keys.map { $0.lowercased() } ?? []),
                       ["accept", "x-github-api-version", "user-agent"])
        let configuration = AppUpdateClient.configuration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 20)
    }

    func testHTTPFailuresCannotBeReportedAsUpToDate() throws {
        let cases: [(Int, [String: String], AppUpdateIssue)] = [
            (404, [:], .noPublishedRelease), (429, [:], .rateLimited),
            (403, ["X-RateLimit-Remaining": "0"], .rateLimited),
            (403, ["Retry-After": "60"], .rateLimited),
            (403, [:], .unavailable), (500, [:], .unavailable), (302, [:], .invalidResponse)
        ]
        for (status, headers, issue) in cases {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: AppUpdateClient.endpoint, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: headers
            ))
            XCTAssertThrowsError(try AppUpdateClient.validateStatus(response)) {
                XCTAssertEqual($0 as? AppUpdateIssue, issue)
            }
        }
    }

    func testRedirectsAreRejectedWithoutStartingAnyNetworkTask() throws {
        let session = URLSession(configuration: AppUpdateClient.configuration())
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: AppUpdateClient.request())
        let response = try XCTUnwrap(HTTPURLResponse(
            url: AppUpdateClient.endpoint, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: [:]
        ))
        let redirected = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/update")))
        AppUpdateSessionDelegate().urlSession(
            session, task: task, willPerformHTTPRedirection: response, newRequest: redirected
        ) { request in
            XCTAssertNil(request)
        }
    }

    func testStubbedTransportHandlesValidOversizedAndOfflineResponses() async throws {
        let client = AppUpdateClient(protocolClass: AppUpdateURLProtocolStub.self)
        AppUpdateURLProtocolStub.storage.set(.init(data: try releaseData()))
        let release = try await client.latestRelease()
        XCTAssertEqual(release.version, AppReleaseVersion("0.2.3"))
        XCTAssertEqual(AppUpdateURLProtocolStub.storage.requests().last?.url, AppUpdateClient.endpoint)

        AppUpdateURLProtocolStub.storage.set(.init(
            data: Data(repeating: 120, count: AppUpdateClient.maximumResponseBytes + 1)
        ))
        do {
            _ = try await client.latestRelease()
            XCTFail("Expected the response byte limit")
        } catch {
            XCTAssertEqual(error as? AppUpdateIssue, .responseTooLarge)
        }

        AppUpdateURLProtocolStub.storage.set(.init(data: Data(), error: .notConnectedToInternet))
        do {
            _ = try await client.latestRelease()
            XCTFail("Expected an offline error")
        } catch {
            XCTAssertEqual(error as? AppUpdateIssue, .offline)
        }
    }
}

@MainActor
final class AppUpdateControllerTests: XCTestCase {
    func testChecksAreManualCoalescedAndFailuresClearTheOldCandidate() async throws {
        let client = ControlledAppUpdateClient()
        let controller = AppUpdateController(currentVersion: "0.2.2", client: client)
        defer { controller.shutdown() }
        await Task.yield()
        let initialCount = await client.count
        XCTAssertEqual(initialCount, 0)
        XCTAssertEqual(controller.state, .idle)

        controller.checkForUpdates()
        controller.checkForUpdates()
        try await wait { await client.count == 1 }
        let release = try AppRelease.parse(releaseData())
        await client.complete(0, with: .success(release))
        try await wait { !controller.isChecking }
        XCTAssertEqual(controller.state, .available(release))

        controller.checkForUpdates()
        XCTAssertEqual(controller.state, .checking)
        try await wait { await client.count == 2 }
        await client.complete(1, with: .failure(.rateLimited))
        try await wait { !controller.isChecking }
        XCTAssertEqual(controller.state, .failed(.rateLimited))
        await Task.yield()
        let finalCount = await client.count
        XCTAssertEqual(finalCount, 2)
    }

    func testEqualOrOlderPublishedVersionsDoNotOfferADowngrade() async throws {
        for current in ["0.2.3", "0.3.0"] {
            let client = ControlledAppUpdateClient()
            let controller = AppUpdateController(currentVersion: current, client: client)
            controller.checkForUpdates()
            try await wait { await client.count == 1 }
            await client.complete(0, with: .success(try AppRelease.parse(releaseData())))
            try await wait { !controller.isChecking }
            XCTAssertEqual(controller.state, .upToDate)
            controller.shutdown()
        }
    }

    func testInvalidCurrentVersionDoesNotIssueARequest() async {
        let client = ControlledAppUpdateClient()
        let controller = AppUpdateController(currentVersion: "not-a-version", client: client)
        controller.checkForUpdates()
        XCTAssertEqual(controller.state, .failed(.invalidCurrentVersion))
        let count = await client.count
        XCTAssertEqual(count, 0)
        controller.shutdown()
    }

    func testShutdownDiscardsLateResponsesAndRejectsFurtherChecks() async throws {
        let client = ControlledAppUpdateClient()
        let controller = AppUpdateController(currentVersion: "0.2.2", client: client)
        controller.checkForUpdates()
        try await wait { await client.count == 1 }
        controller.shutdown()
        await client.complete(0, with: .success(try AppRelease.parse(releaseData())))
        await Task.yield()
        controller.checkForUpdates()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.canCheckForUpdates)
        let count = await client.count
        XCTAssertEqual(count, 1)
    }

    private func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for fake update client")
    }
}

private func releaseData(
    page: String = "https://github.com/DEFY-AN94/codex94/releases/tag/v0.2.3",
    draft: Bool = false,
    prerelease: Bool = false,
    notes: String = "Synthetic release notes",
    assets: [[String: String]] = []
) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "tag_name": "v0.2.3", "name": "Synthetic release", "body": notes,
        "html_url": page, "draft": draft, "prerelease": prerelease, "assets": assets
    ])
}

private actor ControlledAppUpdateClient: AppUpdateFetching {
    private var requests: [CheckedContinuation<AppRelease, Error>?] = []
    var count: Int { requests.count }

    func latestRelease() async throws -> AppRelease {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }

    func complete(_ index: Int, with result: Result<AppRelease, AppUpdateIssue>) {
        let continuation = requests[index]
        requests[index] = nil
        switch result {
        case let .success(release): continuation?.resume(returning: release)
        case let .failure(issue): continuation?.resume(throwing: issue)
        }
    }
}

private final class AppUpdateURLProtocolStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        let data: Data
        var error: URLError.Code? = nil
    }

    final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var reply = Reply(data: Data())
        private var captured: [URLRequest] = []

        func set(_ reply: Reply) {
            lock.lock()
            defer { lock.unlock() }
            self.reply = reply
            captured = []
        }

        func record(_ request: URLRequest) -> Reply {
            lock.lock()
            defer { lock.unlock() }
            captured.append(request)
            return reply
        }

        func requests() -> [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return captured
        }
    }

    static let storage = Storage()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.storage.record(request)
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: URLError(error))
            return
        }
        let response = HTTPURLResponse(
            url: AppUpdateClient.endpoint, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
