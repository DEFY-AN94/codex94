import XCTest
@testable import Codex94

final class SnapshotCacheTests: XCTestCase {
    func testV2RoundTripPreservesBucketsAndUsesOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94CacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("quota.json")
        let cache = SnapshotCache(fileURL: fileURL)
        let snapshot = QuotaSnapshot(
            buckets: [
                QuotaBucketSnapshot(
                    limitID: "default-v2",
                    limitName: nil,
                    planType: "pro",
                    windows: [
                        window(.weekly, used: 31, minutes: 10_080, reset: 2_000_000_000)
                    ]
                ),
                QuotaBucketSnapshot(
                    limitID: "model-special",
                    limitName: "Spark",
                    planType: "pro",
                    windows: [
                        window(.fiveHour, used: 42, minutes: 300, reset: 2_000_000_100),
                        window(.weekly, used: 18, minutes: 10_080, reset: nil)
                    ]
                )
            ],
            defaultLimitID: "default-v2",
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
        XCTAssertEqual(loaded.defaultLimitID, "default-v2")
        XCTAssertEqual(loaded.buckets.count, 2)
        XCTAssertEqual(loaded.defaultBucket?.window(.weekly)?.usedPercent, 31)
        XCTAssertEqual(loaded.defaultBucket?.window(.weekly)?.windowMinutes, 10_080)
        XCTAssertEqual(loaded.bucket(id: "model-special")?.limitName, "Spark")
        XCTAssertEqual(loaded.bucket(id: "model-special")?.window(.fiveHour)?.usedPercent, 42)
        XCTAssertEqual(loaded.bucket(id: "model-special")?.window(.weekly)?.windowMinutes, 10_080)
        XCTAssertNil(loaded.account)
        XCTAssertNil(loaded.codex)

        let data = try Data(contentsOf: fileURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "buckets", "defaultLimitID", "fetchedAt"])
        XCTAssertEqual(object["version"] as? Int, 2)
        let cachedBuckets = try XCTUnwrap(object["buckets"] as? [[String: Any]])
        XCTAssertTrue(cachedBuckets.allSatisfy {
            Set($0.keys).isSubset(of: ["limitID", "limitName", "planType", "windows"])
        })
        let cachedWindows = cachedBuckets.flatMap { $0["windows"] as? [[String: Any]] ?? [] }
        XCTAssertTrue(cachedWindows.allSatisfy {
            Set($0.keys).isSubset(of: ["kind", "usedPercent", "windowMinutes", "resetsAt"])
        })

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("private@example.com"))
        XCTAssertFalse(text.contains("/Users/private"))
        for forbiddenKey in [
            "account", "accountId", "email", "executableURL", "token", "auth", "rawResponse"
        ] {
            XCTAssertFalse(text.contains("\"\(forbiddenKey)\""))
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testLoadsUnversionedV1AsDefaultBucket() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("quota.json")
        let legacyJSON = #"""
        {
          "windows": [
            {
              "kind": "weekly",
              "usedPercent": 31,
              "resetsAt": "2033-05-18T03:33:20Z"
            }
          ],
          "planType": "plus",
          "fetchedAt": "2030-03-17T17:46:40Z"
        }
        """#
        try legacyJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let snapshot = try XCTUnwrap(SnapshotCache(fileURL: fileURL).load())

        XCTAssertEqual(snapshot.defaultLimitID, "codex")
        XCTAssertEqual(snapshot.buckets.count, 1)
        XCTAssertEqual(snapshot.defaultBucket?.limitName, nil)
        XCTAssertEqual(snapshot.defaultBucket?.planType, "plus")
        XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.usedPercent, 31)
        XCTAssertNil(snapshot.defaultBucket?.window(.weekly)?.windowMinutes)
        XCTAssertNil(snapshot.account)
        XCTAssertNil(snapshot.codex)
    }

    func testMalformedAndUnsupportedFutureCacheReturnNil() throws {
        let directory = try makeTemporaryDirectory()
        let malformedURL = directory.appendingPathComponent("malformed.json")
        try "{not-json".write(to: malformedURL, atomically: true, encoding: .utf8)
        XCTAssertNil(SnapshotCache(fileURL: malformedURL).load())

        let futureURL = directory.appendingPathComponent("future.json")
        let futureJSON = #"""
        {
          "version": 3,
          "windows": [{"kind":"weekly","usedPercent":99}],
          "buckets": [{
            "limitID": "default-v3",
            "planType": "pro",
            "windows": [{"kind":"weekly","usedPercent":10,"windowMinutes":10080}]
          }],
          "defaultLimitID": "default-v3",
          "fetchedAt": "2030-03-17T17:46:40Z"
        }
        """#
        try futureJSON.write(to: futureURL, atomically: true, encoding: .utf8)
        XCTAssertNil(SnapshotCache(fileURL: futureURL).load())

        let malformedVersionURL = directory.appendingPathComponent("malformed-version.json")
        let malformedVersionJSON = #"""
        {
          "version": "2",
          "windows": [{"kind":"weekly","usedPercent":99}],
          "fetchedAt": "2030-03-17T17:46:40Z"
        }
        """#
        try malformedVersionJSON.write(
            to: malformedVersionURL,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertNil(SnapshotCache(fileURL: malformedVersionURL).load())
    }

    func testInvalidV2BucketTopologyReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("quota.json")
        let invalidJSON = #"""
        {
          "version": 2,
          "buckets": [{
            "limitID": "some-other-bucket",
            "planType": "pro",
            "windows": [{"kind":"weekly","usedPercent":10,"windowMinutes":10080}]
          }],
          "defaultLimitID": "missing-default",
          "fetchedAt": "2030-03-17T17:46:40Z"
        }
        """#
        try invalidJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertNil(SnapshotCache(fileURL: fileURL).load())
    }

    func testV2AllowsEmptyDefaultWhenAnotherBucketHasValidQuota() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("quota.json")
        let cacheJSON = #"""
        {
          "version": 2,
          "buckets": [
            {
              "limitID": "default-empty",
              "planType": "pro",
              "windows": []
            },
            {
              "limitID": "model-special",
              "limitName": "Spark",
              "planType": "pro",
              "windows": [{"kind":"weekly","usedPercent":10,"windowMinutes":10080}]
            }
          ],
          "defaultLimitID": "default-empty",
          "fetchedAt": "2030-03-17T17:46:40Z"
        }
        """#
        try cacheJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        let snapshot = try XCTUnwrap(SnapshotCache(fileURL: fileURL).load())

        XCTAssertEqual(snapshot.defaultBucket?.windows, [])
        XCTAssertEqual(snapshot.bucket(id: "model-special")?.window(.weekly)?.usedPercent, 10)
    }

    func testV2RejectsDuplicateWindowKindsAndAllEmptySnapshots() throws {
        let directory = try makeTemporaryDirectory()
        let duplicateURL = directory.appendingPathComponent("duplicate.json")
        let duplicateJSON = #"""
        {
          "version": 2,
          "buckets": [{
            "limitID": "default-v2",
            "windows": [
              {"kind":"weekly","usedPercent":10,"windowMinutes":10080},
              {"kind":"weekly","usedPercent":20,"windowMinutes":10080}
            ]
          }],
          "defaultLimitID": "default-v2",
          "fetchedAt": "2030-03-17T17:46:40Z"
        }
        """#
        try duplicateJSON.write(to: duplicateURL, atomically: true, encoding: .utf8)
        XCTAssertNil(SnapshotCache(fileURL: duplicateURL).load())

        let emptyURL = directory.appendingPathComponent("empty.json")
        let emptyJSON = #"""
        {
          "version": 2,
          "buckets": [{"limitID":"default-empty","windows":[]}],
          "defaultLimitID": "default-empty",
          "fetchedAt": "2030-03-17T17:46:40Z"
        }
        """#
        try emptyJSON.write(to: emptyURL, atomically: true, encoding: .utf8)
        XCTAssertNil(SnapshotCache(fileURL: emptyURL).load())

        let hiddenOnlyURL = directory.appendingPathComponent("hidden-only.json")
        let hiddenOnlyJSON = #"""
        {
          "version": 2,
          "buckets": [
            {"limitID":"default-empty","windows":[]},
            {
              "limitID":"unnamed-extra",
              "windows":[{"kind":"weekly","usedPercent":10,"windowMinutes":10080}]
            }
          ],
          "defaultLimitID": "default-empty",
          "fetchedAt": "2030-03-17T17:46:40Z"
        }
        """#
        try hiddenOnlyJSON.write(to: hiddenOnlyURL, atomically: true, encoding: .utf8)
        XCTAssertNil(SnapshotCache(fileURL: hiddenOnlyURL).load())
    }

    private func window(
        _ kind: QuotaWindowKind,
        used: Int,
        minutes: Int,
        reset: TimeInterval?
    ) -> QuotaWindowSnapshot {
        QuotaWindowSnapshot(
            kind: kind,
            usedPercent: used,
            windowMinutes: minutes,
            resetsAt: reset.map(Date.init(timeIntervalSince1970:))
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94CacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
