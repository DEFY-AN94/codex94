import Darwin
import XCTest
@testable import Codex94

final class ExecutableLocatorTests: XCTestCase {
    func testCandidateOrder() {
        let home = URL(fileURLWithPath: "/tmp/codex94-home")
        let locator = CodexExecutableLocator(
            environment: ["PATH": "/custom/one:/custom/two", "HOME": home.path],
            homeDirectory: home
        )
        let candidates = locator.candidateURLs(manualPath: "/manual/codex")

        XCTAssertEqual(candidates.map(\.source), [
            .manual, .chatGPTApp, .homebrew, .usrLocal, .localBin, .path, .path
        ])
        XCTAssertEqual(candidates.first?.url.path, "/manual/codex")
        XCTAssertEqual(candidates.last?.url.path, "/custom/two/codex")
    }

    func testManualExecutableIsValidatedByVersion() throws {
        let directory = try makeTemporaryDirectory()
        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\necho 'codex-cli 9.4.0'\n".write(to: executable, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let locator = CodexExecutableLocator(
            environment: ["PATH": "", "HOME": directory.path],
            homeDirectory: directory
        )
        let result = try locator.locate(manualPath: executable.path)
        XCTAssertEqual(result.source, .manual)
        XCTAssertEqual(result.version, "codex-cli 9.4.0")
    }

    func testRejectsExecutableWithUnexpectedVersionOutput() throws {
        let directory = try makeTemporaryDirectory()
        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\necho 'not-codex 1.0'\n".write(to: executable, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let locator = CodexExecutableLocator(
            environment: ["PATH": "", "HOME": directory.path],
            homeDirectory: directory
        )
        XCTAssertThrowsError(try locator.locate(manualPath: executable.path)) { error in
            XCTAssertEqual(error as? ConnectionIssue, .invalidCodexVersion)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

