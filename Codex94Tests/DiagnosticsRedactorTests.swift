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

    func testStandardCodexSourcesUseCanonicalDiagnosticPaths() {
        XCTAssertEqual(
            DiagnosticsRedactor.codexPath(for: located(source: .chatGPTApp)),
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        )
        XCTAssertEqual(
            DiagnosticsRedactor.codexPath(for: located(source: .homebrew)),
            "/opt/homebrew/bin/codex"
        )
        XCTAssertEqual(
            DiagnosticsRedactor.codexPath(for: located(source: .usrLocal)),
            "/usr/local/bin/codex"
        )
        XCTAssertEqual(
            DiagnosticsRedactor.codexPath(for: located(source: .localBin)),
            "~/.local/bin/codex"
        )
    }

    func testManualAndPathSourcesNeverExposeDirectoryComponents() {
        let manual = located(
            path: "/Volumes/Private Work/client/account/codex",
            source: .manual
        )
        let path = located(
            path: "/Users/another-person/secret/bin/codex",
            source: .path
        )

        XCTAssertEqual(DiagnosticsRedactor.codexPath(for: manual), "<redacted-path>/codex")
        XCTAssertEqual(DiagnosticsRedactor.codexPath(for: path), "<redacted-path>/codex")
        XCTAssertEqual(DiagnosticsRedactor.codexPath(for: nil), "not-detected")
    }

    func testCodexVersionAllowsOnlyOneBoundedSafeToken() {
        XCTAssertEqual(
            DiagnosticsRedactor.codexVersion("codex-cli 0.147.0-alpha.6.5+local"),
            "codex-cli 0.147.0-alpha.6.5+local"
        )
        XCTAssertEqual(DiagnosticsRedactor.codexVersion(nil), "unknown")

        for unsafe in [
            "codex-cli 1.0 /Users/private",
            "codex-cli user@example.com",
            "codex-cli 1.0\nsecret",
            "Codex 1.0",
            "codex-cli \(String(repeating: "a", count: 65))"
        ] {
            XCTAssertEqual(
                DiagnosticsRedactor.codexVersion(unsafe),
                "codex-cli <redacted-version>"
            )
        }
    }

    func testDiagnosticsContainOnlyStructuredFields() {
        let diagnostics = RedactedDiagnostics(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            connection: "connected",
            codexPath: DiagnosticsRedactor.codexPath(for: located(
                path: "/Users/private/Applications/codex",
                source: .manual,
                version: "codex-cli user@example.com"
            )),
            codexVersion: DiagnosticsRedactor.codexVersion("codex-cli user@example.com"),
            codexSource: "manual",
            identityMode: "quotaOnly",
            displayMode: MenuBarQuotaSelection.bucket(
                limitID: "private-model-identifier",
                kind: .weekly
            ).diagnosticValue,
            refreshMinutes: 5,
            lastSuccess: Date(timeIntervalSince1970: 900),
            lastError: nil
        ).text

        XCTAssertTrue(diagnostics.contains("connection: connected"))
        XCTAssertTrue(diagnostics.contains("codexPath: <redacted-path>/codex"))
        XCTAssertTrue(diagnostics.contains("codexVersion: codex-cli <redacted-version>"))
        XCTAssertTrue(diagnostics.contains("displayMode: bucket.weekly"))
        XCTAssertFalse(diagnostics.contains("private-model-identifier"))
        XCTAssertFalse(diagnostics.contains("/Users/private"))
        XCTAssertFalse(diagnostics.contains("@"))
        XCTAssertFalse(diagnostics.lowercased().contains("payload"))
        XCTAssertFalse(diagnostics.lowercased().contains("token"))
    }

    private func located(
        path: String = "/tmp/codex",
        source: LocatedCodex.Source,
        version: String = "codex-cli 1.0"
    ) -> LocatedCodex {
        LocatedCodex(
            executableURL: URL(fileURLWithPath: path),
            version: version,
            source: source
        )
    }
}
