import XCTest
@testable import Codex94

final class SnapshotCacheTests: XCTestCase {
    func testRoundTripUsesOwnerOnlyPermissionsAndOmitsIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94CacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("quota.json")
        let cache = SnapshotCache(fileURL: fileURL)
        let snapshot = QuotaSnapshot(
            windows: [
                QuotaWindowSnapshot(
                    kind: .weekly,
                    usedPercent: 31,
                    windowMinutes: 10_080,
                    resetsAt: Date(timeIntervalSince1970: 2_000_000_000)
                )
            ],
            planType: "pro",
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000),
            account: AccountSummary(type: "chatgpt", email: "private@example.com", planType: "pro"),
            codex: LocatedCodex(
                executableURL: URL(fileURLWithPath: "/Users/private/bin/codex"),
                version: "codex-cli 1.0",
                source: .manual
            )
        )

        try cache.save(snapshot)
        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.window(.weekly)?.usedPercent, 31)
        XCTAssertNil(loaded.account)
        XCTAssertNil(loaded.codex)

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("private@example.com"))
        XCTAssertFalse(text.contains("/Users/private"))
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }
}
