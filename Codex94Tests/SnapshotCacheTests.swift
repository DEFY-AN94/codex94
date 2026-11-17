import XCTest
@testable import Codex94

final class SnapshotCacheTests: XCTestCase {
    func testAccountReadFailureIsEphemeralAndClearedForQuotaOnly() throws {
        let directory = try makeTemporaryDirectory()
        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("quota.json"))
        let snapshot = QuotaSnapshot(
            buckets: [QuotaBucketSnapshot(
                limitID: "codex", limitName: nil, planType: "pro",
                windows: [window(.weekly, used: 15, minutes: 10_080, reset: nil)]
            )],
            defaultLimitID: "codex",
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000),
            account: nil,
            codex: nil,
            accountReadIssue: .requestTimedOut
        )

        try cache.save(snapshot)
        let restored = try XCTUnwrap(cache.load())
        XCTAssertEqual(restored.buckets, snapshot.buckets)
        XCTAssertNil(restored.accountReadIssue)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: cache.fileURL)
        ) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "buckets", "defaultLimitID", "fetchedAt"])
        XCTAssertNil(snapshot.removingAccount().accountReadIssue)
        XCTAssertEqual(snapshot.removingAccount().buckets, snapshot.buckets)
    }

    func testV2ExtremePercentagesRoundTripWithoutOverflowOrSchemaChanges() throws {
        let directory = try makeTemporaryDirectory()
        let cache = SnapshotCache(fileURL: directory.appendingPathComponent("quota.json"))
        for used in [Int.min, -1, 0, 100, 101, Int.max] {
            let snapshot = QuotaSnapshot(
                buckets: [QuotaBucketSnapshot(
                    limitID: "default",
                    limitName: nil,
                    planType: "pro",
                    windows: [window(.weekly, used: used, minutes: 10_080, reset: nil)]
                )],
                defaultLimitID: "default",
                fetchedAt: Date(timeIntervalSince1970: 1_900_000_000),
                account: nil,
                codex: nil
            )
            try cache.save(snapshot)
            let restored = try XCTUnwrap(cache.load()?.defaultBucket?.window(.weekly))
            XCTAssertEqual(restored.usedPercent, used)
            XCTAssertEqual(restored.remainingPercent, used <= 0 ? 100 : 0)
        }
    }

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
            ),
            resetCreditsAvailableCount: 4
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
        XCTAssertNil(loaded.resetCreditsAvailableCount)

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
            "account", "accountId", "email", "executableURL", "token", "auth", "rawResponse",
            "resetCreditsAvailableCount", "rateLimitResetCredits", "availableCount", "credits"
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
        XCTAssertNil(snapshot.resetCreditsAvailableCount)
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

    func testSymlinkedAndHardLinkedCachesAreRefusedWithoutTouchingThem() throws {
        let directory = try makeTemporaryDirectory()
        let realDirectory = directory.appendingPathComponent("real", isDirectory: true)
        let realURL = realDirectory.appendingPathComponent("quota.json")
        let snapshot = syntheticSnapshot()
        try SnapshotCache(fileURL: realURL).save(snapshot)
        let savedData = try Data(contentsOf: realURL)
        XCTAssertEqual(SnapshotCache(fileURL: realURL).load()?.buckets, snapshot.buckets)

        // The final component is never followed, wherever the link lives: beside
        // the cache, or inside a directory that is itself reached through a link.
        let fileLink = directory.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(atPath: fileLink.path, withDestinationPath: realURL.path)
        XCTAssertNil(SnapshotCache(fileURL: fileLink).load(), "A symlinked cache file must not be followed")
        XCTAssertThrowsError(try ClaudeLocalFile.readStamped(
            fileLink, maximumBytes: SnapshotCache.maximumCacheBytes, requireCurrentOwner: true,
            allowingSymlinkedAncestors: true
        ), "The ancestor opt-out must not reach the final component") {
            XCTAssertEqual($0 as? ClaudeLocalFile.ReadFailure, .unavailable)
        }

        let directoryLink = directory.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            atPath: directoryLink.path, withDestinationPath: realDirectory.path
        )
        let nestedFileLink = directoryLink.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(
            atPath: realDirectory.appendingPathComponent("linked.json").path, withDestinationPath: realURL.path
        )
        XCTAssertNil(
            SnapshotCache(fileURL: nestedFileLink).load(),
            "A symlinked cache file behind a symlinked directory must not be followed"
        )

        let hardLink = directory.appendingPathComponent("hard-link.json")
        try FileManager.default.linkItem(at: realURL, to: hardLink)
        XCTAssertNil(SnapshotCache(fileURL: hardLink).load(), "A cache with a second link must be refused")
        XCTAssertNil(SnapshotCache(fileURL: realURL).load())

        // Refusal is read-only: nothing is removed, repaired or rewritten.
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: fileLink.path), realURL.path
        )
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: directoryLink.path), realDirectory.path
        )
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: nestedFileLink.path), realURL.path
        )
        XCTAssertEqual(try Data(contentsOf: hardLink), savedData)
        try FileManager.default.removeItem(at: hardLink)
        XCTAssertEqual(try Data(contentsOf: realURL), savedData)
        let restored = try XCTUnwrap(SnapshotCache(fileURL: realURL).load())
        XCTAssertEqual(restored.buckets, snapshot.buckets)
        XCTAssertEqual(restored.defaultLimitID, snapshot.defaultLimitID)
        XCTAssertEqual(restored.fetchedAt, snapshot.fetchedAt)
    }

    func testCacheBehindSymlinkedDirectoriesStillLoadsWhatSaveWroteThroughThem() throws {
        // A home or Application Support folder relocated behind a symlink: save()
        // writes through it, so the App-owned cache must restore through it too.
        let directory = try makeTemporaryDirectory()
        let volume = directory.appendingPathComponent("volume/home", isDirectory: true)
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        let home = directory.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: home.path, withDestinationPath: volume.path)
        let relocated = directory.appendingPathComponent("relocated-support", isDirectory: true)
        try FileManager.default.createDirectory(at: relocated, withIntermediateDirectories: false)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: false)
        let support = library.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: support.path, withDestinationPath: relocated.path)

        // One symlinked ancestor far above the file, then two on the same path.
        let snapshot = syntheticSnapshot()
        for cacheURL in [
            home.appendingPathComponent("Codex94/quota-snapshot.json"),
            support.appendingPathComponent("Codex94/quota-snapshot.json")
        ] {
            let cache = SnapshotCache(fileURL: cacheURL)
            try cache.save(snapshot)
            let restored = try XCTUnwrap(cache.load())
            XCTAssertEqual(restored.buckets, snapshot.buckets)
            XCTAssertEqual(restored.defaultLimitID, snapshot.defaultLimitID)
            XCTAssertEqual(restored.fetchedAt, snapshot.fetchedAt)

            // The opt-out is the cache's alone: the default stays strict.
            XCTAssertThrowsError(try ClaudeLocalFile.readStamped(
                cacheURL, maximumBytes: SnapshotCache.maximumCacheBytes, requireCurrentOwner: true
            )) { XCTAssertEqual($0 as? ClaudeQuotaIssue, .configurationConflict) }
            XCTAssertThrowsError(try ClaudeLocalFile.read(cacheURL, maximumBytes: SnapshotCache.maximumCacheBytes))
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: relocated.appendingPathComponent("Codex94/quota-snapshot.json").path
        ))

        // Behind the symlinked directories every other refusal still applies.
        let cacheURL = support.appendingPathComponent("Codex94/quota-snapshot.json")
        let hardLink = support.appendingPathComponent("Codex94/hard-link.json")
        try FileManager.default.linkItem(at: cacheURL, to: hardLink)
        XCTAssertNil(SnapshotCache(fileURL: cacheURL).load(), "A cache with a second link must be refused")
        try FileManager.default.removeItem(at: hardLink)
        XCTAssertNotNil(SnapshotCache(fileURL: cacheURL).load())
        let saved = try Data(contentsOf: cacheURL)
        let padding = Data(repeating: 0x20, count: SnapshotCache.maximumCacheBytes + 1 - saved.count)
        try (saved + padding).write(to: cacheURL)
        XCTAssertNil(SnapshotCache(fileURL: cacheURL).load(), "An oversized cache must be refused")
        XCTAssertNil(SnapshotCache(fileURL: cacheURL.deletingLastPathComponent()).load(), "A directory is no cache")
    }

    func testOversizedCacheIsRefusedWhileBoundarySizedV1AndV2StillLoad() throws {
        let directory = try makeTemporaryDirectory()
        let limit = SnapshotCache.maximumCacheBytes
        XCTAssertEqual(limit, 1_048_576)
        let snapshot = syntheticSnapshot()
        let sourceURL = directory.appendingPathComponent("source.json")
        try SnapshotCache(fileURL: sourceURL).save(snapshot)
        let v2 = try Data(contentsOf: sourceURL)
        let v1 = Data(#"""
        {"windows":[{"kind":"weekly","usedPercent":31,"resetsAt":"2033-05-18T03:33:20Z"}],"planType":"plus","fetchedAt":"2030-03-17T17:46:40Z"}
        """#.utf8)

        // Trailing JSON whitespace keeps every file a decodable cache, so only
        // the size bound separates the refused files from the accepted ones.
        for (name, contents) in [("v2", v2), ("v1", v1)] {
            let boundaryURL = directory.appendingPathComponent("\(name)-boundary.json")
            try (contents + Data(repeating: 0x20, count: limit - contents.count)).write(to: boundaryURL)
            let oversizedURL = directory.appendingPathComponent("\(name)-oversized.json")
            try (contents + Data(repeating: 0x20, count: limit + 1 - contents.count)).write(to: oversizedURL)

            let accepted = try XCTUnwrap(SnapshotCache(fileURL: boundaryURL).load(), name)
            XCTAssertNil(SnapshotCache(fileURL: oversizedURL).load(), name)
            if name == "v2" {
                XCTAssertEqual(accepted.buckets, snapshot.buckets)
                XCTAssertEqual(accepted.defaultLimitID, snapshot.defaultLimitID)
                XCTAssertEqual(accepted.fetchedAt, snapshot.fetchedAt)
            } else {
                XCTAssertEqual(accepted.defaultLimitID, "codex")
                XCTAssertEqual(accepted.buckets, [QuotaBucketSnapshot(
                    limitID: "codex", limitName: nil, planType: "plus",
                    windows: [QuotaWindowSnapshot(
                        kind: .weekly, usedPercent: 31, windowMinutes: nil,
                        resetsAt: Date(timeIntervalSince1970: 2_000_000_000)
                    )]
                )])
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: oversizedURL.path)
            XCTAssertEqual((attributes[.size] as? NSNumber)?.intValue, limit + 1, "Refusal must not truncate")
        }
    }

    func testNonRegularCachePathIsRefusedWithoutBlocking() async throws {
        let directory = try makeTemporaryDirectory()
        let folderURL = directory.appendingPathComponent("folder.json", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        XCTAssertNil(SnapshotCache(fileURL: directory.appendingPathComponent("absent.json")).load())

        let fifoURL = directory.appendingPathComponent("fifo.json")
        XCTAssertEqual(mkfifo(fifoURL.path, 0o600), 0)
        // load() returning nil proves little here: Foundation's own reader also
        // gives up on a FIFO or a directory on this macOS. What is pinned is the
        // reader load() goes through: it must classify both as an invalid file,
        // and must do so at once. Should it ever wait for a writer instead, the
        // task below keeps releasing every blocked open after two seconds (the
        // FIFO is opened more than once), so the duration assertion fails
        // rather than the suite hanging.
        let release = Task.detached {
            try await Task.sleep(for: .seconds(2))
            while !Task.isCancelled {
                let writer = open(fifoURL.path, O_WRONLY | O_NONBLOCK)
                if writer >= 0 { close(writer) }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        let clock = ContinuousClock()
        let startedAt = clock.now
        let outcome = await Task.detached { () -> (refused: Bool, failures: [ClaudeLocalFile.ReadFailure?]) in
            let failures = [fifoURL, folderURL].map { url -> ClaudeLocalFile.ReadFailure? in
                do {
                    _ = try ClaudeLocalFile.readStamped(
                        url, maximumBytes: SnapshotCache.maximumCacheBytes, requireCurrentOwner: true,
                        allowingSymlinkedAncestors: true
                    )
                    return nil
                } catch { return error as? ClaudeLocalFile.ReadFailure }
            }
            let caches = [SnapshotCache(fileURL: fifoURL), SnapshotCache(fileURL: folderURL)]
            return (caches.allSatisfy { $0.load() == nil }, failures)
        }.value
        let duration = clock.now - startedAt
        release.cancel()

        XCTAssertTrue(outcome.refused)
        XCTAssertEqual(outcome.failures, [.invalidFile, .invalidFile], "FIFO, then directory")
        XCTAssertLessThan(duration, .seconds(1), "Neither may be waited on")
        var info = stat()
        XCTAssertEqual(lstat(fifoURL.path, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFIFO)
    }

    private func syntheticSnapshot() -> QuotaSnapshot {
        QuotaSnapshot(
            buckets: [
                QuotaBucketSnapshot(
                    limitID: "default-v2", limitName: nil, planType: "pro",
                    windows: [window(.weekly, used: 31, minutes: 10_080, reset: 2_000_000_000)]
                ),
                QuotaBucketSnapshot(
                    limitID: "model-special", limitName: "Spark", planType: "pro",
                    windows: [
                        window(.fiveHour, used: 42, minutes: 300, reset: 2_000_000_100),
                        window(.weekly, used: 18, minutes: 10_080, reset: nil)
                    ]
                )
            ],
            defaultLimitID: "default-v2",
            fetchedAt: Date(timeIntervalSince1970: 1_900_000_000),
            account: nil,
            codex: nil
        )
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
