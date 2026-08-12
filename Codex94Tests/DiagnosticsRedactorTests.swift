import XCTest
@testable import Codex94

final class DiagnosticsRedactorTests: XCTestCase {
    func testRedactsHomeDirectoryAndEmail() {
        let input = "/Users/example/Library item user@example.com"
        XCTAssertEqual(
            DiagnosticsRedactor.redact(input, homeDirectory: "/Users/example"),
            "~/Library item <redacted-email>"
        )
    }

    func testDiagnosticsContainOnlyStructuredFields() {
        let diagnostics = RedactedDiagnostics(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            connection: "connected",
            codexPath: "~/Applications/codex",
            codexVersion: "codex-cli 1.0",
            codexSource: "manual",
            identityMode: "quotaOnly",
            displayMode: "weekly",
            refreshMinutes: 5,
            lastSuccess: Date(timeIntervalSince1970: 900),
            lastError: nil
        ).text

        XCTAssertTrue(diagnostics.contains("connection: connected"))
        XCTAssertTrue(diagnostics.contains("codexPath: ~/Applications/codex"))
        XCTAssertFalse(diagnostics.contains("@"))
        XCTAssertFalse(diagnostics.lowercased().contains("payload"))
    }
}

