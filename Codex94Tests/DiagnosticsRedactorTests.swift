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

    func testBundledSourcesReportOnlyTheirExactKnownPath() {
        let paths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ]
        for path in paths {
            XCTAssertEqual(DiagnosticsRedactor.codexPath(for: located(path: path, source: .chatGPTApp)), path)
            for source in [LocatedCodex.Source.manual, .path] {
                XCTAssertEqual(DiagnosticsRedactor.codexPath(for: located(path: path, source: source)),
                               "<redacted-path>/codex", "Manual/PATH sources stay redacted even at a known location")
            }
        }
    }

    func testInjectedOrNonstandardBundlePathsStayRedacted() {
        for path in [
            "/tmp/codex94-home/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Users/private/Applications/codex",
            "/Applications/ChatGPT.app/Contents/Resources/private/codex",
            "/Applications/Codex.app/Contents/Resources/codex-other"
        ] {
            XCTAssertEqual(DiagnosticsRedactor.codexPath(for: located(path: path, source: .chatGPTApp)),
                           "<redacted-path>/codex")
        }
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
            lastError: nil,
            enabledProviders: [.codex, .claude],
            menuBarServices: .both,
            claudeConnection: "stale",
            claudeSource: .cliUsage,
            claudeIssue: .timedOut,
            claudeLastReport: Date(timeIntervalSince1970: 800)
        ).text

        XCTAssertTrue(diagnostics.contains("connection: connected"))
        XCTAssertTrue(diagnostics.contains("codexPath: <redacted-path>/codex"))
        XCTAssertTrue(diagnostics.contains("codexVersion: codex-cli <redacted-version>"))
        XCTAssertTrue(diagnostics.contains("displayMode: bucket.weekly"))
        XCTAssertTrue(diagnostics.contains("enabledProviders: codex,claude"))
        XCTAssertTrue(diagnostics.contains("menuBarServices: both"))
        XCTAssertTrue(diagnostics.contains("claudeConnection: stale"))
        XCTAssertTrue(diagnostics.contains("claudeSource: cliUsage"))
        XCTAssertTrue(diagnostics.contains("claudeIssue: timedOut"))
        XCTAssertTrue(diagnostics.contains("claudeLastReport: 1970-01-01T00:13:20Z"))
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
