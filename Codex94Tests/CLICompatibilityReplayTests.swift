import Foundation
import XCTest
@testable import Codex94

/// Repository-owned synthetic data only. No process, settings, account or network access.
final class CLICompatibilityReplayTests: XCTestCase {
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

    private func assertScreen(_ bytes: Data, fixture: ReplayFixture,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let screen = ClaudeUsageScreen.snapshot(from: bytes)
        let complete = try XCTUnwrap(fixture.expected.complete, fixture.id, file: file, line: line)
        XCTAssertEqual(screen.isComplete, complete, fixture.id, file: file, line: line)
        // Completeness is a parser output, not permission to send a key. The
        // production client's input/settling gates retain their existing tests.
        guard complete, screen.isComplete else { return }
        let ready = try XCTUnwrap(fixture.expected.ready, fixture.id, file: file, line: line)
        let refreshing = try XCTUnwrap(fixture.expected.refreshing, fixture.id, file: file, line: line)
        XCTAssertEqual(ClaudeUsageScreen.isReadyForUsage(screen.text), ready,
                       fixture.id, file: file, line: line)
        XCTAssertEqual(ClaudeUsageScreen.isRefreshing(screen.text), refreshing,
                       fixture.id, file: file, line: line)
        let expected = try XCTUnwrap(fixture.expected.windows, fixture.id, file: file, line: line)
        let date = try fixture.referenceDate()
        if expected.isEmpty {
            XCTAssertThrowsError(try ClaudeUsageScreen.report(from: screen.text, at: date),
                                 fixture.id, file: file, line: line) { error in
                XCTAssertEqual(error as? ClaudeQuotaIssue, .noData, fixture.id, file: file, line: line)
            }
            return
        }
        let report = try ClaudeUsageScreen.report(from: screen.text, at: date)
        XCTAssertEqual(report.source, .cliUsage, fixture.id, file: file, line: line)
        XCTAssertEqual(report.reportedAt, date, fixture.id, file: file, line: line)
        XCTAssertEqual(report.receivedAt, date, fixture.id, file: file, line: line)
        XCTAssertNil(report.producerID, fixture.id, file: file, line: line)
        XCTAssertTrue(report.modelLimits.isEmpty, fixture.id, file: file, line: line)
        let windows = try expected.map { value in
            ClaudeQuotaWindow(kind: value.kind, usedPercentage: value.usedPercentage,
                              resetsAt: try value.resetsAt.map(Self.utcDate))
        }
        XCTAssertEqual(report.windows, windows, fixture.id, file: file, line: line)
    }

    private func assertReplies(_ chunks: [Data], expected: [String], id: String, delivery: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        var responder = ClaudeTerminalQueries()
        let actual = chunks.flatMap { responder.responses(to: $0) }
            .map { String(decoding: $0, as: UTF8.self) }.sorted()
        XCTAssertEqual(actual, expected, "\(id): \(delivery)", file: file, line: line)
        XCTAssertTrue(responder.responses(to: Data()).isEmpty,
                      "\(id): empty delivery duplicated a reply", file: file, line: line)
        XCTAssertTrue(responder.responses(to: Data("synthetic non-query tail".utf8)).isEmpty,
                      "\(id): later text duplicated a reply", file: file, line: line)
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
