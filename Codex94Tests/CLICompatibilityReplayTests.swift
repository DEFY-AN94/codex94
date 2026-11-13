import Foundation
import XCTest
@testable import Codex94

/// Repository-owned synthetic data only. No process, settings, account or network access.
final class CLICompatibilityReplayTests: XCTestCase {
    private static let replaySeeds: [UInt64] = [0x94, 0x418, 0x420]

    func testCatalogIsPresentOnlyInTheHostedTestBundle() throws {
        let testBundle = Bundle(for: CLICompatibilityReplayTests.self)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.defyan94.codex94", "This is a hosted App test")
        XCTAssertNotEqual(testBundle.bundleURL, Bundle.main.bundleURL)
        XCTAssertNotNil(testBundle.url(forResource: "catalog", withExtension: "json",
                                        subdirectory: "CLICompatibility"))
        XCTAssertNil(Bundle.main.url(forResource: "catalog", withExtension: "json",
                                      subdirectory: "CLICompatibility"))
        XCTAssertNil(Bundle.main.url(forResource: "catalog", withExtension: "json"),
                     "The catalog must not be flattened into App resources either")
        let appResources = try XCTUnwrap(Bundle.main.resourceURL)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: appResources.appendingPathComponent("CLICompatibility", isDirectory: true).path),
            "Only the test bundle may own the fixture directory")
    }

    func testScreenFixturesUseProductionParsersAtDeclaredCheckpoints() throws {
        for fixture in try loadFixtures() where fixture.kind == .screen {
            var received = Data()
            for (index, event) in fixture.events.enumerated() {
                received.append(try event.output())
                if let complete = event.expectedComplete {
                    XCTAssertEqual(ClaudeUsageScreen.snapshot(from: received).isComplete, complete,
                                   "\(fixture.id): checkpoint \(index)")
                }
            }
            try assertScreen(received, fixture: fixture)
        }
    }

    func testScreenFixturesSurviveSeededAndFixedCutDelivery() throws {
        for fixture in try loadFixtures() where fixture.kind == .screen {
            for seed in Self.replaySeeds {
                var generator = ReplayChunkGenerator(seed: seed)
                // Split each declared event independently so its semantic
                // checkpoint is still observed, even inside a UTF-8 sequence.
                let chunks = try fixture.events.flatMap { event in
                    generator.chunks(for: try event.output())
                }
                try assertScreenDelivery(chunks, fixture: fixture,
                                         delivery: "seed 0x\(String(seed, radix: 16))")
            }

            var bytes = Data()
            var boundaries = Set<Int>()
            for event in fixture.events {
                bytes.append(try event.output())
                boundaries.insert(bytes.count)
            }
            // One additional fixed partition crosses the full report using
            // short-prefix and interior cuts, retaining all event checkpoints.
            boundaries.formUnion([1, 2, 3, 7, 17, 31, 64, 127, bytes.count / 2, bytes.count - 1])
            var start = 0
            let chunks = boundaries.filter { $0 > 0 && $0 <= bytes.count }.sorted().map { end in
                let chunk = bytes.subdata(in: start..<end)
                start = end
                return chunk
            }
            try assertScreenDelivery(chunks, fixture: fixture, delivery: "fixed cuts")
        }
    }

    func testTerminalQueryFixturesSurviveEverySingleSplitAndBytewiseDelivery() throws {
        for fixture in try loadFixtures() where fixture.kind == .queries {
            let bytes = try fixture.events.reduce(into: Data()) { result, event in
                result.append(try event.output())
            }
            let expected = try XCTUnwrap(fixture.expected.replies, fixture.id).sorted()
            // The production responder batches replies by query type. Their
            // multiplicity is invariant; ordering across batches is not promised.
            for boundary in 0...bytes.count {
                try assertReplies([Data(bytes.prefix(boundary)), Data(bytes.dropFirst(boundary))],
                                  expected: expected, id: fixture.id, delivery: "split \(boundary)")
            }
            try assertReplies(bytes.map { Data([$0]) }, expected: expected,
                              id: fixture.id, delivery: "bytewise")
            try assertReplies(fixture.events.map { try $0.output() }, expected: expected,
                              id: fixture.id, delivery: "declared events")
            for seed in Self.replaySeeds {
                var generator = ReplayChunkGenerator(seed: seed)
                // Unlike screen checkpoints, query framing must also survive
                // chunks that cross boundaries between declared output events.
                try assertReplies(generator.chunks(for: bytes), expected: expected,
                                  id: fixture.id, delivery: "seed 0x\(String(seed, radix: 16))")
            }
        }
    }

    func testIncompleteCheckpointsCannotReuseAnEarlierRecognizedPrompt() throws {
        for fixture in try loadFixtures() where fixture.kind == .screen {
            var received = Data("? for shortcuts\r\n".utf8)
            XCTAssertTrue(ClaudeUsageScreen.isReadyForUsage(ClaudeUsageScreen.text(from: received)))
            for (index, event) in fixture.events.enumerated() {
                received.append(try event.output())
                if event.expectedComplete == false {
                    XCTAssertFalse(ClaudeUsageScreen.snapshot(from: received).isComplete,
                                   "\(fixture.id): prior readiness cannot complete checkpoint \(index)")
                }
            }
        }
    }

    private func assertScreenDelivery(_ chunks: [Data], fixture: ReplayFixture, delivery: String,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        var expectedBytes = Data()
        var checkpoints: [Int: (event: Int, complete: Bool)] = [:]
        for (index, event) in fixture.events.enumerated() {
            expectedBytes.append(try event.output())
            if let complete = event.expectedComplete {
                checkpoints[expectedBytes.count] = (index, complete)
            }
        }
        var received = Data()
        var observedCheckpoints = 0
        for (index, chunk) in chunks.enumerated() {
            received.append(chunk)
            let screen = ClaudeUsageScreen.snapshot(from: received)
            if let checkpoint = checkpoints[received.count] {
                observedCheckpoints += 1
                XCTAssertEqual(screen.isComplete, checkpoint.complete,
                               "\(fixture.id): \(delivery), event \(checkpoint.event), chunk \(index)",
                               file: file, line: line)
            }
        }
        XCTAssertEqual(observedCheckpoints, checkpoints.count,
                       "\(fixture.id): \(delivery), missed declared checkpoints", file: file, line: line)
        // Compare only a boolean so a failed partition never dumps a transcript.
        XCTAssertTrue(received == expectedBytes, "\(fixture.id): \(delivery), byte reconstruction",
                      file: file, line: line)
        try assertScreen(received, fixture: fixture, delivery: delivery, file: file, line: line)
    }

    private func assertScreen(_ bytes: Data, fixture: ReplayFixture, delivery: String = "declared events",
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let context = "\(fixture.id): \(delivery)"
        let screen = ClaudeUsageScreen.snapshot(from: bytes)
        let complete = try XCTUnwrap(fixture.expected.complete, context, file: file, line: line)
        XCTAssertEqual(screen.isComplete, complete, context, file: file, line: line)
        // Completeness is a parser output, not permission to send a key. The
        // production client's input/settling gates retain their existing tests.
        guard complete, screen.isComplete else { return }
        let ready = try XCTUnwrap(fixture.expected.ready, context, file: file, line: line)
        let refreshing = try XCTUnwrap(fixture.expected.refreshing, context, file: file, line: line)
        XCTAssertEqual(ClaudeUsageScreen.isReadyForUsage(screen.text), ready,
                       context, file: file, line: line)
        XCTAssertEqual(ClaudeUsageScreen.isRefreshing(screen.text), refreshing,
                       context, file: file, line: line)
        let expected = try XCTUnwrap(fixture.expected.windows, context, file: file, line: line)
        let date = try fixture.referenceDate()
        if expected.isEmpty {
            XCTAssertThrowsError(try ClaudeUsageScreen.report(from: screen.text, at: date),
                                 context, file: file, line: line) { error in
                XCTAssertEqual(error as? ClaudeQuotaIssue, .noData, context, file: file, line: line)
            }
            return
        }
        let report = try XCTUnwrap(try? ClaudeUsageScreen.report(from: screen.text, at: date),
                                  "\(context): expected parsed report", file: file, line: line)
        XCTAssertEqual(report.source, .cliUsage, context, file: file, line: line)
        XCTAssertEqual(report.reportedAt, date, context, file: file, line: line)
        XCTAssertEqual(report.receivedAt, date, context, file: file, line: line)
        XCTAssertNil(report.producerID, context, file: file, line: line)
        XCTAssertTrue(report.modelLimits.isEmpty, context, file: file, line: line)
        let windows = try expected.map { value in
            ClaudeQuotaWindow(kind: value.kind, usedPercentage: value.usedPercentage,
                              resetsAt: try value.resetsAt.map(Self.utcDate))
        }
        XCTAssertEqual(report.windows, windows, context, file: file, line: line)
    }

    private func assertReplies(_ chunks: [Data], expected: [String], id: String, delivery: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        var responder = ClaudeTerminalQueries()
        let actual = chunks.flatMap { responder.responses(to: $0) }
            .map { String(decoding: $0, as: UTF8.self) }.sorted()
        XCTAssertEqual(actual, expected, "\(id): \(delivery)", file: file, line: line)
        XCTAssertTrue(responder.responses(to: Data()).isEmpty,
                      "\(id): \(delivery), empty delivery duplicated a reply", file: file, line: line)
        XCTAssertTrue(responder.responses(to: Data("synthetic non-query tail".utf8)).isEmpty,
                      "\(id): \(delivery), later text duplicated a reply", file: file, line: line)
    }

    private func loadFixtures() throws -> [ReplayFixture] {
        let bundle = Bundle(for: CLICompatibilityReplayTests.self)
        let catalogURL = try XCTUnwrap(bundle.url(forResource: "catalog", withExtension: "json",
                                                  subdirectory: "CLICompatibility"),
                                        "CLICompatibility must be a test-only folder resource")
        let decoder = JSONDecoder()
        let catalog = try decoder.decode(ReplayCatalog.self, from: Self.boundedData(at: catalogURL))
        guard catalog.schemaVersion == 1, !catalog.fixtures.isEmpty, catalog.fixtures.count <= 64,
              Set(catalog.fixtures).count == catalog.fixtures.count else { throw ReplayError.invalidCatalog }
        let root = catalogURL.deletingLastPathComponent()
        var ids = Set<String>()
        var totalBytes = 0
        return try catalog.fixtures.map { relative in
            guard relative.range(of: #"^claude/[a-z0-9]+(?:-[a-z0-9]+)*\.json$"#,
                                 options: .regularExpression) != nil else { throw ReplayError.invalidCatalog }
            let data = try Self.boundedData(at: root.appendingPathComponent(relative))
            totalBytes += data.count
            guard totalBytes <= 1_048_576 else { throw ReplayError.invalidCatalog }
            let fixture = try decoder.decode(ReplayFixture.self, from: data)
            guard fixture.schemaVersion == 1, fixture.provider == "claude",
                  fixture.provenance.kind == "synthetic", !fixture.provenance.sourceTests.isEmpty,
                  fixture.locale == "en_US", fixture.timezone == "UTC",
                  !fixture.events.isEmpty, fixture.events.count <= 256,
                  ids.insert(fixture.id).inserted else { throw ReplayError.invalidFixture }
            _ = try fixture.referenceDate()
            let byteCount = try fixture.events.reduce(0) { count, event in
                count + (try event.output()).count
            }
            guard byteCount <= 65_536 else { throw ReplayError.invalidFixture }
            return fixture
        }
    }

    private static func boundedData(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink == false,
              let size = values.fileSize, size <= 262_144 else { throw ReplayError.invalidFixture }
        let data = try Data(contentsOf: url)
        guard data.count <= 262_144 else { throw ReplayError.invalidFixture }
        return data
    }

    fileprivate static func utcDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            throw ReplayError.invalidFixture
        }
        return date
    }
}

/// A tiny, fixed SplitMix64 sequence, independent of system random sources.
/// Each draw advances by at least one byte, with chunks capped at 31 bytes.
private struct ReplayChunkGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func chunks(for bytes: Data) -> [Data] {
        var result: [Data] = []
        var offset = 0
        while offset < bytes.count {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            value ^= value >> 31
            let end = min(bytes.count, offset + Int(value % 31) + 1)
            result.append(bytes.subdata(in: offset..<end))
            offset = end
        }
        return result
    }
}

private enum ReplayError: Error { case invalidCatalog, invalidFixture }

private struct ReplayCatalog: Decodable {
    let schemaVersion: Int
    let fixtures: [String]
}

private struct ReplayFixture: Decodable {
    enum Kind: String, Decodable { case screen, queries }
    let schemaVersion: Int
    let id: String
    let provider: String
    let kind: Kind
    let scenario: String
    let provenance: Provenance
    let fixtureDeclaredVersion: String
    let referenceTime: String
    let locale: String
    let timezone: String
    let events: [Event]
    let expected: Expected

    func referenceDate() throws -> Date { try CLICompatibilityReplayTests.utcDate(referenceTime) }

    struct Provenance: Decodable {
        let kind: String
        let sourceTests: [String]
        let notes: String
    }

    struct Event: Decodable {
        let type: String
        let text: String?
        let bytes: [UInt8]?
        let expectedComplete: Bool?

        func output() throws -> Data {
            guard type == "output", (text == nil) != (bytes == nil) else { throw ReplayError.invalidFixture }
            if let text { return Data(text.utf8) }
            return Data(bytes ?? [])
        }
    }

    struct Expected: Decodable {
        let complete: Bool?
        let ready: Bool?
        let refreshing: Bool?
        let windows: [Window]?
        let replies: [String]?
    }

    struct Window: Decodable {
        let kind: QuotaWindowKind
        let usedPercentage: Double
        let resetsAt: String?
    }
}
