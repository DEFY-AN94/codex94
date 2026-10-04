import Darwin
import Foundation
import XCTest
@testable import Codex94

final class ClaudeLocalUsageCacheReaderTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeLocalUsageCacheReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testParsesSharedWindowsModelLimitsAndIgnoresPlaceholderKeys() throws {
        let reader = try writeCache(sample())
        let reading = reader.read(now: now)
        guard case let .report(report, accountID) = reading.outcome else { return XCTFail("\(reading.outcome)") }
        XCTAssertEqual(accountID, UUID(uuidString: "8C0B90AE-5C65-413B-8F72-519D7BA78A5F"))
        XCTAssertEqual(report.source, .localCache)
        XCTAssertEqual(report.reportedAt, Date(timeIntervalSince1970: 1_999_990_000.244))
        XCTAssertEqual(report.receivedAt, now)
        XCTAssertNil(report.producerID)
        XCTAssertEqual(report.windows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(report.windows[0].usedPercentage, 100)
        XCTAssertEqual(report.windows[0].resetsAt, Date(timeIntervalSince1970: 2_000_097_000.059623))
        XCTAssertEqual(report.windows[1].usedPercentage, 17)
        XCTAssertEqual(report.modelLimits, [
            ClaudeQuotaModelLimit(modelName: "Fable", usedPercentage: 33,
                                  resetsAt: Date(timeIntervalSince1970: 2_000_144_800))
        ], "Only weekly_scoped rows with a model name become limits; session and weekly_all duplicates are skipped")
        XCTAssertNotNil(reading.stamp)
    }

    func testMissingAndNullWindowsAreSkippedButNoWindowAtAllIsInvalid() throws {
        var reader = try writeCache(sample(fiveHour: "null"))
        guard case let .report(report, _) = reader.read(now: now).outcome else { return XCTFail("null window must be skipped") }
        XCTAssertEqual(report.windows.map(\.kind), [.weekly])

        reader = try writeCache(sample(fiveHour: nil, sevenDay: nil))
        XCTAssertEqual(reader.read(now: now).outcome, .invalid, "A cache without any window carries no quota")

        reader = try writeCache(#"{"numStartups": 3}"#)
        XCTAssertEqual(reader.read(now: now).outcome, .invalid, "A state file without the usage key is not a report")
    }

    func testRejectsInvalidPercentagesTimestampsAndIdentity() throws {
        for window in [
            #"{"utilization": true, "resets_at": "2033-05-10T00:00:00Z"}"#,
            #"{"utilization": 150, "resets_at": "2033-05-10T00:00:00Z"}"#,
            #"{"utilization": -1, "resets_at": "2033-05-10T00:00:00Z"}"#,
            #"{"utilization": "42", "resets_at": "2033-05-10T00:00:00Z"}"#,
            #"{"utilization": 42, "resets_at": 2000001000}"#,
            #"{"utilization": 42, "resets_at": "2033-02-30T00:00:00Z"}"#,
            #"{"utilization": 42, "resets_at": "2033-05-10T24:00:00Z"}"#,
            #"{"utilization": 42, "resets_at": "2033-05-10T00:00:00"}"#,
            #"{"utilization": 42, "resets_at": "2033-05-10 00:00:00Z"}"#,
            #"[42]"#,
        ] {
            let reader = try writeCache(sample(fiveHour: window))
            XCTAssertEqual(reader.read(now: now).outcome, .invalid, window)
        }
        for fetchedAt in ["-5", "true", "\"1999990000244\"", "3e17", "null"] {
            let reader = try writeCache(sample(fetchedAtMs: fetchedAt))
            XCTAssertEqual(reader.read(now: now).outcome, .invalid, fetchedAt)
        }
        for account in ["\"not-a-uuid\"", "42", "null", "\"8c0b90ae-5c65-413b-8f72-519d7ba78a5fZ\""] {
            let reader = try writeCache(sample(account: account))
            XCTAssertEqual(reader.read(now: now).outcome, .invalid, account)
        }
    }

    func testTimestampsAcceptFractionsOffsetsAndZulu() throws {
        XCTAssertEqual(ClaudeLocalUsageCacheReader.timestamp("2026-10-03T10:30:00.059623+00:00"),
                       Date(timeIntervalSince1970: 1_791_023_400.059623))
        XCTAssertEqual(ClaudeLocalUsageCacheReader.timestamp("2026-10-03T20:30:00+10:00"),
                       Date(timeIntervalSince1970: 1_791_023_400))
        XCTAssertEqual(ClaudeLocalUsageCacheReader.timestamp("2026-10-03T05:30:00.5-05:00"),
                       Date(timeIntervalSince1970: 1_791_023_400.5))
        XCTAssertEqual(ClaudeLocalUsageCacheReader.timestamp("2026-10-03T10:30:00Z"),
                       Date(timeIntervalSince1970: 1_791_023_400))
        XCTAssertNil(ClaudeLocalUsageCacheReader.timestamp("2026-10-03T10:30:00+25:00"))
        XCTAssertNil(ClaudeLocalUsageCacheReader.timestamp("10000-01-01T00:00:00Z"))
        XCTAssertNil(ClaudeLocalUsageCacheReader.timestamp(String(repeating: "2", count: 70)))
    }

    func testAbsentUnreadableAndUnchangedOutcomes() throws {
        let fileURL = directory.appendingPathComponent(".claude.json")
        let reader = ClaudeLocalUsageCacheReader(fileURL: fileURL)
        XCTAssertEqual(reader.read(now: now).outcome, .absent)
        XCTAssertNil(reader.read(now: now).stamp)

        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
        XCTAssertEqual(reader.read(now: now).outcome, .unreadable, "A directory is never parsed")
        try FileManager.default.removeItem(at: fileURL)

        let target = directory.appendingPathComponent("real.json")
        try Data(sample().utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: target)
        XCTAssertEqual(reader.read(now: now).outcome, .unreadable, "Symbolic links are refused")
        try FileManager.default.removeItem(at: fileURL)

        try Data(sample().utf8).write(to: fileURL)
        let first = reader.read(now: now)
        guard case .report = first.outcome, let stamp = first.stamp else { return XCTFail("\(first.outcome)") }
        XCTAssertEqual(reader.read(now: now, unchangedSince: stamp).outcome, .unchanged)

        // Any rewrite changes the stamp, even when the bytes are equivalent.
        try FileManager.default.removeItem(at: fileURL)
        usleep(20_000)
        try Data(sample(sevenDayUsed: "18").utf8).write(to: fileURL)
        let second = reader.read(now: now, unchangedSince: stamp)
        guard case let .report(report, _) = second.outcome else { return XCTFail("\(second.outcome)") }
        XCTAssertEqual(report.windows[1].usedPercentage, 18)
        XCTAssertNotEqual(second.stamp, stamp)
    }

    func testFIFOIsRejectedWithoutAWriterByLocalAndSharedReaders() throws {
        let fifo = directory.appendingPathComponent(".claude.json")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, 0o600), 0)
        let reader = ClaudeLocalUsageCacheReader(fileURL: fifo)
        let date = now
        let result = LocalReadResultBox()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let reading = reader.read(now: date)
            let sharedRejected = (try? ClaudeLocalFile.read(fifo, maximumBytes: 1_024)) == nil
            result.set(reading: reading, sharedRejected: sharedRejected)
            finished.signal()
        }
        let completion = finished.wait(timeout: .now() + 2)
        if completion == .timedOut {
            // A regression must fail rather than hang the test host forever.
            // Only after the no-writer deadline, open this test's own FIFO at
            // both ends to release an old blocking open, without supplying data.
            let rescue = Darwin.open(fifo.path, O_RDWR | O_NONBLOCK | O_CLOEXEC)
            XCTAssertGreaterThanOrEqual(rescue, 0)
            if rescue >= 0 {
                _ = finished.wait(timeout: .now() + 2)
                Darwin.close(rescue)
            }
        }
        XCTAssertEqual(completion, .success, "An untrusted file type must not wait for a FIFO writer")
        let value = try XCTUnwrap(result.value)
        XCTAssertEqual(value.reading.outcome, .unreadable)
        XCTAssertNil(value.reading.stamp)
        XCTAssertTrue(value.sharedRejected)
    }

    func testHardLinksAndSharedReadSizeLimitsRemainRejected() throws {
        let reader = try writeCache(sample())
        let alias = directory.appendingPathComponent("hard-link.json")
        try FileManager.default.linkItem(at: reader.fileURL, to: alias)
        XCTAssertEqual(reader.read(now: now).outcome, .unreadable)
        XCTAssertThrowsError(try ClaudeLocalFile.read(reader.fileURL, maximumBytes: 65_536)) {
            XCTAssertEqual($0 as? ClaudeQuotaIssue, .invalidData)
        }
        try FileManager.default.removeItem(at: alias)
        let bytes = try Data(contentsOf: reader.fileURL)
        XCTAssertEqual(try ClaudeLocalFile.read(reader.fileURL, maximumBytes: bytes.count), bytes)
        XCTAssertThrowsError(try ClaudeLocalFile.read(reader.fileURL, maximumBytes: bytes.count - 1)) {
            XCTAssertEqual($0 as? ClaudeQuotaIssue, .invalidData)
        }
        // Readable ordinary permissions remain accepted; shared reads did not
        // acquire a new 0600-only or owner-only policy as part of this refactor.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: reader.fileURL.path)
        XCTAssertEqual(try ClaudeLocalFile.read(reader.fileURL, maximumBytes: bytes.count), bytes)
        guard case .report = reader.read(now: now).outcome else { return XCTFail("Current-owner regular file remains readable") }
    }

    func testStampedReadSkipsBytesAndRejectsMutationBeforeReturningAnyStamp() throws {
        let url = directory.appendingPathComponent("read-race.json")
        try Data("first".utf8).write(to: url)
        guard case let .contents(bytes, stamp) = try ClaudeLocalFile.readStamped(url, maximumBytes: 64) else {
            return XCTFail("Expected a first stable read")
        }
        XCTAssertEqual(bytes, Data("first".utf8))
        var reads = 0
        let unchanged = try ClaudeLocalFile.readStamped(url, maximumBytes: 64, unchangedSince: stamp) { _, _ in
            reads += 1
            XCTFail("An unchanged stamp must skip the byte reader")
            return Data()
        }
        XCTAssertEqual(unchanged, .unchanged(stamp))
        XCTAssertEqual(reads, 0)
        XCTAssertThrowsError(try ClaudeLocalFile.readStamped(url, maximumBytes: 64) { handle, limit in
            reads += 1
            let oldBytes = try handle.read(upToCount: limit) ?? Data()
            let writer = try FileHandle(forWritingTo: url)
            defer { try? writer.close() }
            try writer.truncate(atOffset: 0)
            try writer.write(contentsOf: Data("completed rewrite".utf8))
            return oldBytes
        }) {
            XCTAssertEqual($0 as? ClaudeLocalFile.ReadFailure, .changedDuringRead)
        }
        XCTAssertEqual(reads, 1, "A changing file is not immediately retried")
        guard case let .contents(completed, nextStamp) = try ClaudeLocalFile.readStamped(url, maximumBytes: 64) else {
            return XCTFail("The next ordinary read must accept a completed rewrite")
        }
        XCTAssertEqual(completed, Data("completed rewrite".utf8))
        XCTAssertNotEqual(stamp, nextStamp)
    }

    func testReadFailureDuringRewriteIsTransientButUnchangedFailureIsUnavailable() throws {
        let url = directory.appendingPathComponent("failing-read.json")
        try Data("first".utf8).write(to: url)
        XCTAssertThrowsError(try ClaudeLocalFile.readStamped(url, maximumBytes: 64) { _, _ in
            throw CocoaError(.fileReadUnknown)
        }) { XCTAssertEqual($0 as? ClaudeLocalFile.ReadFailure, .unavailable) }
        XCTAssertThrowsError(try ClaudeLocalFile.readStamped(url, maximumBytes: 64) { _, _ in
            let writer = try FileHandle(forWritingTo: url)
            defer { try? writer.close() }
            _ = try writer.seekToEnd()
            try writer.write(contentsOf: Data(" changed".utf8))
            throw CocoaError(.fileReadUnknown)
        }) { XCTAssertEqual($0 as? ClaudeLocalFile.ReadFailure, .changedDuringRead) }
    }

    func testSharedPercentageValidationRetainsFractionAndRejectsBooleanCoercion() {
        for value in [0.0, 0.001, 23.5, 99.999, 100.0] {
            XCTAssertEqual(StrictJSONPercentage.value(NSNumber(value: value)), value)
            XCTAssertEqual(ClaudeLocalUsageCacheReader.percentage(NSNumber(value: value)), value)
        }
        let invalid: [Any?] = [nil, NSNull(), true, false, "23.5", -0.01, 100.01, Double.nan, Double.infinity]
        for value in invalid {
            XCTAssertNil(StrictJSONPercentage.value(value))
            XCTAssertNil(ClaudeLocalUsageCacheReader.percentage(value))
        }
    }

    func testTruncatedJSONIsUnparsableAndOversizedFilesAreUnreadable() throws {
        let truncated = String(sample().prefix(sample().count / 2))
        var reader = try writeCache(truncated)
        XCTAssertEqual(reader.read(now: now).outcome, .unparsable,
                       "Bytes that do not decode may be a rewrite in progress")
        reader = try writeCache("not json at all")
        XCTAssertEqual(reader.read(now: now).outcome, .unparsable)

        let padding = String(repeating: " ", count: ClaudeLocalUsageCacheReader.maximumBytes + 1)
        reader = try writeCache(sample() + padding)
        XCTAssertEqual(reader.read(now: now).outcome, .unreadable)
    }

    func testConfigDirectoryVariableOverridesTheHomeFileOnlyWhenUsable() throws {
        let home = URL(fileURLWithPath: "/private/tmp/example-home", isDirectory: true)
        let defaultURL = ClaudeLocalUsageCacheReader.defaultFileURL(environment: [:], homeDirectory: home)
        XCTAssertEqual(defaultURL.path, "/private/tmp/example-home/.claude.json")
        let custom = ClaudeLocalUsageCacheReader.defaultFileURL(
            environment: ["CLAUDE_CONFIG_DIR": directory.path], homeDirectory: home
        )
        XCTAssertEqual(custom.path, directory.appendingPathComponent(".claude.json").path)
        for invalid in ["relative/dir", "/tmp/../etc", "/tmp/./x", "/tmp/with\u{0007}bell", ""] {
            let resolved = ClaudeLocalUsageCacheReader.defaultFileURL(
                environment: ["CLAUDE_CONFIG_DIR": invalid], homeDirectory: home
            )
            XCTAssertEqual(resolved.path, defaultURL.path, invalid)
        }
        XCTAssertFalse(defaultURL.path.contains("/Users/"), "Paths are derived, never literal")
    }

    func testModelLimitsFallBackToLegacyKeysDeduplicateAndSkipMalformedRows() throws {
        let limits = """
        [
          {"kind": "weekly_scoped", "percent": 40, "resets_at": "2033-05-10T00:00:00Z", "scope": {"model": {"display_name": "Fable"}}},
          {"kind": "weekly_scoped", "percent": 55, "resets_at": "2033-05-10T00:00:00Z", "scope": {"model": {"display_name": "fable "}}},
          {"kind": "weekly_scoped", "percent": 500, "scope": {"model": {"display_name": "Broken"}}},
          {"kind": "weekly_scoped", "percent": 10, "scope": {"model": {"display_name": "   "}}},
          {"kind": "weekly_scoped", "percent": 20, "scope": {"model": {"display_name": "Control\\u0007"}}},
          {"kind": "weekly_scoped", "percent": 12, "resets_at": null, "scope": {"model": {"display_name": "Opus"}}},
          {"kind": "session", "percent": 99}
        ]
        """
        var reader = try writeCache(sample(limits: limits))
        guard case let .report(report, _) = reader.read(now: now).outcome else { return XCTFail("report expected") }
        XCTAssertEqual(report.modelLimits.map(\.modelName), ["Fable", "Opus"])
        XCTAssertEqual(report.modelLimits.map(\.usedPercentage), [40, 12])
        XCTAssertNil(report.modelLimits[1].resetsAt)
        XCTAssertEqual(report.modelLimits.map(\.limitID), ["claude.model.fable", "claude.model.opus"])

        reader = try writeCache(sample(
            limits: "[]",
            extra: #""seven_day_opus": {"utilization": 61, "resets_at": "2033-05-10T00:00:00Z"}, "seven_day_sonnet": {"utilization": 5.5, "resets_at": null},"#
        ))
        guard case let .report(legacy, _) = reader.read(now: now).outcome else { return XCTFail("report expected") }
        XCTAssertEqual(legacy.modelLimits.map(\.modelName), ["Opus", "Sonnet"])
        XCTAssertEqual(legacy.modelLimits.map(\.usedPercentage), [61, 5.5])
    }

    func testSnapshotProjectsModelBucketsAndDropsExpiredOnes() throws {
        let report = ClaudeQuotaReport(
            source: .localCache, reportedAt: now, receivedAt: now,
            windows: [.init(kind: .fiveHour, usedPercentage: 30.5, resetsAt: now.addingTimeInterval(100)),
                      .init(kind: .weekly, usedPercentage: 20, resetsAt: now.addingTimeInterval(1_000))],
            modelLimits: [
                .init(modelName: "Fable", usedPercentage: 90, resetsAt: now.addingTimeInterval(1_000)),
                .init(modelName: "Opus", usedPercentage: 10, resetsAt: now.addingTimeInterval(-1)),
                .init(modelName: "Sonnet", usedPercentage: 5, resetsAt: nil),
            ]
        )
        let snapshot = try XCTUnwrap(report.snapshot(at: now))
        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.defaultBucket?.windows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(snapshot.displayableBuckets.map(\.limitID), ["claude", "claude.model.fable", "claude.model.sonnet"])
        XCTAssertEqual(snapshot.displayName(for: snapshot.displayableBuckets[1]), "Fable")
        XCTAssertEqual(snapshot.bucket(id: "claude.model.fable")?.window(.weekly)?.preciseRemainingPercent, 10)
        XCTAssertNil(snapshot.bucket(id: "claude.model.fable")?.window(.fiveHour))
        XCTAssertEqual(snapshot.automaticResolvedWindow?.bucket.limitID, "claude.model.fable",
                       "The most constrained window may be a model-scoped weekly limit")
        XCTAssertEqual(ProviderScopedLimit.limits(in: snapshot).map(\.name), ["Fable", "Sonnet"])

        let later = now.addingTimeInterval(500)
        let expired = try XCTUnwrap(report.snapshot(at: later))
        XCTAssertEqual(expired.defaultBucket?.windows.map(\.kind), [.weekly])
        XCTAssertNil(report.snapshot(at: now.addingTimeInterval(2_000)), "Model limits alone never resurrect quota")
    }

    func testReportCodableKeepsModelLimitsAndOldRecordsStillDecode() throws {
        let report = ClaudeQuotaReport(
            source: .localCache, reportedAt: now, receivedAt: now,
            windows: [.init(kind: .weekly, usedPercentage: 1, resetsAt: nil)],
            modelLimits: [.init(modelName: "Fable", usedPercentage: 2, resetsAt: nil)]
        )
        let data = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(ClaudeQuotaReport.self, from: data), report)
        let legacy = Data(#"{"source":"statusline","reportedAt":1000,"receivedAt":1000,"windows":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(ClaudeQuotaReport.self, from: legacy)
        XCTAssertEqual(decoded.modelLimits, [])
        XCTAssertEqual(decoded.source, .statusline)
        XCTAssertEqual(ClaudeQuotaModelLimit.slug("Claude Opus 4.1!"), "claude-opus-4-1")
        XCTAssertEqual(ClaudeQuotaModelLimit.slug("***"), "unknown")
    }

    // MARK: Fixtures

    private func writeCache(_ json: String) throws -> ClaudeLocalUsageCacheReader {
        let fileURL = directory.appendingPathComponent(".claude.json")
        try? FileManager.default.removeItem(at: fileURL)
        try Data(json.utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return ClaudeLocalUsageCacheReader(fileURL: fileURL)
    }

    /// Mirrors the real file shape, including feature-flag placeholder keys
    /// and the account/project fields that the reader must discard.
    private func sample(
        fetchedAtMs: String = "1999990000244",
        account: String = "\"8c0b90ae-5c65-413b-8f72-519d7ba78a5f\"",
        fiveHour: String? = #"{"limit_dollars": null, "locked_reason": null, "resets_at": "2033-05-19T06:30:00.059623+00:00", "utilization": 100}"#,
        sevenDay: String? = #"{"resets_at": "2033-05-19T19:00:00+00:00", "utilization": SEVEN}"#,
        sevenDayUsed: String = "17",
        limits: String = """
        [
          {"group": "session", "is_active": true, "kind": "session", "percent": 100, "resets_at": "2033-05-19T06:30:00Z", "scope": null, "severity": "critical"},
          {"group": "weekly", "is_active": false, "kind": "weekly_all", "percent": 17, "resets_at": "2033-05-19T19:00:00Z", "scope": null, "severity": "normal"},
          {"group": "weekly", "is_active": false, "kind": "weekly_scoped", "percent": 33, "resets_at": "2033-05-19T19:46:40+00:00", "scope": {"model": {"display_name": "Fable", "id": null}, "surface": null}, "severity": "normal"}
        ]
        """,
        extra: String = ""
    ) -> String {
        var utilization = ["\"amber_cistern\": null", "\"copper_kite\": null", "\"harbor_lantern\": null", "\"member_dashboard_available\": false"]
        if let fiveHour { utilization.append("\"five_hour\": " + fiveHour) }
        if let sevenDay { utilization.append("\"seven_day\": " + sevenDay.replacingOccurrences(of: "SEVEN", with: sevenDayUsed)) }
        utilization.append("\"limits\": " + limits)
        utilization.append("\"seven_day_breakdown\": {\"rows\": [{\"display_name\": \"Chats\", \"key\": \"chat\", \"percent\": 2}]}")
        if !extra.isEmpty { utilization.append(String(extra.dropLast())) }
        return """
        {
          "numStartups": 12,
          "oauthAccount": {"emailAddress": "private@example.com", "organizationName": "Example"},
          "projects": {"/Users/example/project": {"allowedTools": []}},
          "cachedUsageUtilization": {
            "accountUuid": \(account),
            "fetchedAtMs": \(fetchedAtMs),
            "utilization": {\(utilization.joined(separator: ", "))}
          }
        }
        """
    }
}

/// The FIFO test records results on its worker without sharing mutable test state.
private final class LocalReadResultBox: @unchecked Sendable {
    struct Value: Sendable { let reading: ClaudeLocalUsageCacheReading; let sharedRejected: Bool }
    private let lock = NSLock()
    private var stored: Value?
    var value: Value? { lock.withLock { stored } }
    func set(reading: ClaudeLocalUsageCacheReading, sharedRejected: Bool) {
        lock.withLock { stored = Value(reading: reading, sharedRejected: sharedRejected) }
    }
}
