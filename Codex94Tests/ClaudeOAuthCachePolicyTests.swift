import Foundation
import XCTest
@testable import Codex94

final class ClaudeOAuthCachePolicyTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_900_000_000)

    func testPassiveEligibilityRequiresRecentIdentifiableUnexpiredLocalEvidence() {
        let producer = String(repeating: "a", count: 64)
        let report = report(source: .statusline, producer: producer)
        XCTAssertTrue(ClaudeQuotaSourcePolicy.isEligiblePassive(report, at: date.addingTimeInterval(600)))
        XCTAssertFalse(ClaudeQuotaSourcePolicy.isEligiblePassive(report, at: date.addingTimeInterval(601)))
        XCTAssertFalse(ClaudeQuotaSourcePolicy.isEligiblePassive(report, at: date.addingTimeInterval(-1)))
        for identity in [nil, "invalid", ClaudeStatuslineParser.legacyUnknownProducerID] {
            XCTAssertFalse(ClaudeQuotaSourcePolicy.isEligiblePassive(self.report(source: .statusline, producer: identity), at: date))
        }
        XCTAssertFalse(ClaudeQuotaSourcePolicy.isEligiblePassive(self.report(source: .cliUsage, producer: producer), at: date))
        XCTAssertFalse(ClaudeQuotaSourcePolicy.isEligiblePassive(self.report(source: .oauth, producer: producer), at: date))
        let expired = ClaudeQuotaReport(source: .statusline, reportedAt: date, receivedAt: date,
            windows: [.init(kind: .weekly, usedPercentage: 30, resetsAt: date)], producerID: producer)
        XCTAssertFalse(ClaudeQuotaSourcePolicy.isEligiblePassive(expired, at: date))
        let unknownReset = ClaudeQuotaReport(source: .statusline, reportedAt: date, receivedAt: date,
            windows: [.init(kind: .weekly, usedPercentage: 30, resetsAt: nil)], producerID: producer)
        XCTAssertFalse(ClaudeQuotaSourcePolicy.isEligiblePassive(unknownReset, at: date))
    }

    func testOAuthCachePartitionsByAccountAndOrganizationAndPreservesQueryTime() throws {
        let cache = try cache()
        let first = context(account: 1, organization: 1)
        let anotherAccount = context(account: 2, organization: 1)
        let anotherOrganization = context(account: 1, organization: 2)
        let original = report(source: .oauth, context: first)
        try cache.save(report: original)
        XCTAssertEqual(try cache.load(context: first), original)
        XCTAssertNil(try cache.load(context: anotherAccount))
        XCTAssertNil(try cache.load(context: anotherOrganization))
        XCTAssertEqual(Set([first, anotherAccount, anotherOrganization].map {
            ClaudeOAuthQuotaCache.isolationKey(for: $0)
        }).count, 3)
        XCTAssertFalse(cache.fileURL(for: first).lastPathComponent.contains(first.accountID.uuidString))
        XCTAssertEqual(try cache.load(context: first)?.reportedAt, date)
        let attributes = try FileManager.default.attributesOfItem(atPath: cache.fileURL(for: first).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cache.fileURL(for: first))) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["version", "report"])
        let storedReport = try XCTUnwrap(json["report"] as? [String: Any])
        XCTAssertEqual(Set(storedReport.keys), ["source", "reportedAt", "receivedAt", "windows", "accountContext"])
    }

    func testCacheRejectsUnknownIdentityForeignSourceAndTamperedAccount() throws {
        let cache = try cache()
        let account = context(account: 1, organization: 1)
        XCTAssertThrowsError(try cache.save(report: report(source: .oauth)))
        XCTAssertThrowsError(try cache.save(report: report(source: .statusline, context: account)))
        XCTAssertThrowsError(try cache.save(report: report(source: .oauth, context: account, producer: String(repeating: "a", count: 64))))
        try cache.save(report: report(source: .oauth, context: account))
        let destination = context(account: 2, organization: 2)
        try FileManager.default.copyItem(at: cache.fileURL(for: account), to: cache.fileURL(for: destination))
        XCTAssertThrowsError(try cache.load(context: destination), "A renamed quota cache must not impersonate a different account")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cache.fileURL(for: account).path)
        XCTAssertThrowsError(try cache.load(context: account), "OAuth account metadata must stay owner-private")
    }

    func testWeeklyOnlyReportRemainsWeeklyAndSourceFingerprintNeverVerifiesIdentity() {
        let local = report(source: .statusline, context: context(account: 1, organization: 1), producer: String(repeating: "a", count: 64))
        XCTAssertEqual(local.identityConfidence, .unverifiedLocal)
        let oauth = report(source: .oauth, context: context(account: 1, organization: 1))
        XCTAssertEqual(oauth.identityConfidence, .verifiedOAuth)
        XCTAssertEqual(oauth.snapshot(at: date)?.defaultBucket?.windows.map(\.kind), [.weekly])
        XCTAssertEqual(report(source: .oauth).identityConfidence, .unknown)
    }

    private func report(source: ClaudeQuotaSource, context: ClaudeOAuthAccountContext? = nil,
                        producer: String? = nil) -> ClaudeQuotaReport {
        ClaudeQuotaReport(source: source, reportedAt: date, receivedAt: date,
            windows: [.init(kind: .weekly, usedPercentage: 24.5, resetsAt: date.addingTimeInterval(7_200))],
            producerID: producer, accountContext: context)
    }

    private func context(account: Int, organization: Int) -> ClaudeOAuthAccountContext {
        ClaudeOAuthAccountContext(
            accountID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", account))!,
            organizationID: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", organization))!
        )
    }

    private func cache() throws -> ClaudeOAuthQuotaCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Codex94OAuthCacheTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return ClaudeOAuthQuotaCache(directory: directory)
    }
}
