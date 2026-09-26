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
            .manual, .chatGPTApp, .chatGPTApp, .chatGPTApp, .chatGPTApp,
            .homebrew, .usrLocal, .localBin, .path, .path
        ])
        XCTAssertEqual(candidates.first?.url.path, "/manual/codex")
        XCTAssertEqual(Array(candidates.dropFirst().prefix(4)).map(\.url.path), [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ])
        XCTAssertEqual(candidates.last?.url.path, "/custom/two/codex")
    }

    func testNestedDesktopCLIIsDiscoveredWithStandardGUIPath() throws {
        for appName in ["ChatGPT.app", "Codex.app"] {
            let directory = try makeTemporaryDirectory()
            let app = directory.appendingPathComponent("Desktop Apps/" + appName)
            let executable = app.appendingPathComponent(nestedCLIPath)
            try writeVersionExecutable(at: executable, output: "codex-cli 0.158.0-alpha.2.1")
            let locator = bundledLocator(roots: [app], home: directory)
            defer { locator.shutdown() }

            let result = try locator.locate(manualPath: nil)
            XCTAssertEqual(result.executableURL, executable.resolvingSymlinksInPath())
            XCTAssertEqual(result.source, .chatGPTApp)
            XCTAssertEqual(result.version, "codex-cli 0.158.0-alpha.2.1")
            XCTAssertEqual(try probeCount(executable), 1)
        }
    }

    func testNestedLayoutPrecedesLegacyAcrossKnownAppRoots() throws {
        let directory = try makeTemporaryDirectory()
        let chatGPT = directory.appendingPathComponent("ChatGPT.app")
        let codexApp = directory.appendingPathComponent("Codex.app")
        let legacy = chatGPT.appendingPathComponent("Contents/Resources/codex")
        let nested = codexApp.appendingPathComponent(nestedCLIPath)
        try writeVersionExecutable(at: legacy, output: "codex-cli 9.4.0")
        try writeVersionExecutable(at: nested, output: "codex-cli 9.5.0")
        let locator = bundledLocator(roots: [chatGPT, codexApp], home: directory)
        defer { locator.shutdown() }

        let result = try locator.locate(manualPath: nil)
        XCTAssertEqual(result.executableURL, nested.resolvingSymlinksInPath())
        XCTAssertEqual(result.version, "codex-cli 9.5.0")
        XCTAssertEqual(try probeCount(nested), 1)
        XCTAssertEqual(try probeCount(legacy), 0, "Do not invoke a lower-priority legacy executable")
    }

    func testMissingNestedLayoutFallsBackToLegacy() throws {
        let directory = try makeTemporaryDirectory()
        let app = directory.appendingPathComponent("ChatGPT.app")
        let executable = app.appendingPathComponent("Contents/Resources/codex")
        try writeVersionExecutable(at: executable, output: "codex-cli 9.4.0")
        let locator = bundledLocator(roots: [app], home: directory)
        defer { locator.shutdown() }

        let result = try locator.locate(manualPath: nil)
        XCTAssertEqual(result.executableURL, executable.resolvingSymlinksInPath())
        XCTAssertEqual(result.source, .chatGPTApp)
        XCTAssertEqual(try probeCount(executable), 1)
    }

    func testInvalidNestedExecutableFallsBackToValidatedLegacy() throws {
        let cases: [(String, Int, mode_t, Int)] = [
            ("not-codex 1.0", 0, 0o700, 1),
            ("codex-cli 9.5.0", 1, 0o700, 1),
            ("codex-cli 9.5.0", 0, 0o600, 0)
        ]
        for (output, status, mode, expectedProbes) in cases {
            let directory = try makeTemporaryDirectory()
            let app = directory.appendingPathComponent("Codex.app")
            let nested = app.appendingPathComponent(nestedCLIPath)
            let legacy = app.appendingPathComponent("Contents/Resources/codex")
            try writeVersionExecutable(at: nested, output: output, exitStatus: status)
            XCTAssertEqual(chmod(nested.path, mode), 0)
            try writeVersionExecutable(at: legacy, output: "codex-cli 9.4.0")
            let locator = bundledLocator(roots: [app], home: directory)
            defer { locator.shutdown() }

            let result = try locator.locate(manualPath: nil)
            XCTAssertEqual(result.executableURL, legacy.resolvingSymlinksInPath())
            XCTAssertEqual(result.version, "codex-cli 9.4.0")
            XCTAssertEqual(try probeCount(nested), expectedProbes)
            XCTAssertEqual(try probeCount(legacy), 1)
        }
    }

    func testManualOverridePrecedesAValidNestedBundle() throws {
        let directory = try makeTemporaryDirectory()
        let app = directory.appendingPathComponent("ChatGPT.app")
        let nested = app.appendingPathComponent(nestedCLIPath)
        let manual = directory.appendingPathComponent("manual/codex")
        try writeVersionExecutable(at: nested, output: "codex-cli 9.5.0")
        try writeVersionExecutable(at: manual, output: "codex-cli 9.6.0")
        let locator = bundledLocator(roots: [app], home: directory)
        defer { locator.shutdown() }

        let result = try locator.locate(manualPath: manual.path)
        XCTAssertEqual(result.source, .manual)
        XCTAssertEqual(result.executableURL, manual.resolvingSymlinksInPath())
        XCTAssertEqual(result.version, "codex-cli 9.6.0")
        XCTAssertEqual(try probeCount(manual), 1)
        XCTAssertEqual(try probeCount(nested), 0)
    }

    func testBadManualOverridesNeverFallBackToAvailableNestedBundle() throws {
        let directory = try makeTemporaryDirectory()
        let app = directory.appendingPathComponent("ChatGPT.app")
        let nested = app.appendingPathComponent(nestedCLIPath)
        let missing = directory.appendingPathComponent("missing/codex")
        let notExecutable = directory.appendingPathComponent("not-executable/codex")
        let invalid = directory.appendingPathComponent("invalid/codex")
        try writeVersionExecutable(at: nested, output: "codex-cli 9.5.0")
        try writeVersionExecutable(at: notExecutable, output: "codex-cli 9.5.0")
        XCTAssertEqual(chmod(notExecutable.path, 0o600), 0)
        try writeVersionExecutable(at: invalid, output: "not-codex 1.0")
        let locator = bundledLocator(roots: [app], home: directory)
        defer { locator.shutdown() }
        let cases: [(URL, ConnectionIssue)] = [
            (missing, .codexNotFound), (notExecutable, .codexNotExecutable), (invalid, .invalidCodexVersion)
        ]
        for (manual, expected) in cases {
            XCTAssertThrowsError(try locator.locate(manualPath: manual.path)) {
                XCTAssertEqual($0 as? ConnectionIssue, expected)
            }
        }
        XCTAssertEqual(try probeCount(nested), 0, "An invalid override must not silently select another Codex")
        XCTAssertEqual(try probeCount(notExecutable), 0)
        XCTAssertEqual(try probeCount(invalid), 1)
    }

    func testRelativePathComponentsAreIgnored() {
        let home = URL(fileURLWithPath: "/tmp/codex94-home")
        let locator = CodexExecutableLocator(
            environment: [
                "PATH": ".:relative/bin:/safe/bin::/also/safe",
                "HOME": home.path
            ],
            homeDirectory: home
        )
        let pathCandidates = locator.candidateURLs(manualPath: nil)
            .filter { $0.source == .path }

        XCTAssertEqual(pathCandidates.map(\.url.path), [
            "/safe/bin/codex",
            "/also/safe/codex"
        ])
        XCTAssertEqual(
            CodexExecutableLocator.sanitizedEnvironment(from: [
                "PATH": ".:/safe/bin:relative/bin:/also/safe"
            ])["PATH"],
            "/safe/bin:/also/safe"
        )
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

    func testRejectsMultilineVersionOutput() throws {
        let directory = try makeTemporaryDirectory()
        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\nprintf 'codex-cli 9.4.0\\nuntrusted detail\\n'\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let locator = CodexExecutableLocator(
            environment: ["PATH": "", "HOME": directory.path],
            homeDirectory: directory
        )
        XCTAssertThrowsError(try locator.locate(manualPath: executable.path)) { error in
            XCTAssertEqual(error as? ConnectionIssue, .invalidCodexVersion)
        }
    }

    func testRejectsOversizedVersionOutput() throws {
        let directory = try makeTemporaryDirectory()
        let executable = directory.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        printf 'codex-cli '
        i=0
        while [ "$i" -lt 1100 ]; do
          printf x
          i=$((i + 1))
        done
        printf '\n'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let locator = CodexExecutableLocator(
            environment: ["PATH": "", "HOME": directory.path],
            homeDirectory: directory
        )
        XCTAssertThrowsError(try locator.locate(manualPath: executable.path)) { error in
            XCTAssertEqual(error as? ConnectionIssue, .invalidCodexVersion)
        }
    }

    func testVersionProbeTimeoutStopsProcess() throws {
        let directory = try makeTemporaryDirectory()
        let executable = directory.appendingPathComponent("codex")
        let pidFile = directory.appendingPathComponent("pid")
        let descendantPIDFile = directory.appendingPathComponent("descendant-pid")
        let script = """
        #!/bin/sh
        printf '%s\n' "$$" > "\(pidFile.path)"
        sleep 30 &
        printf '%s\n' "$!" > "\(descendantPIDFile.path)"
        wait
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let locator = CodexExecutableLocator(
            environment: ["PATH": "", "HOME": directory.path],
            homeDirectory: directory
        )
        let startedAt = Date()
        XCTAssertThrowsError(try locator.locate(manualPath: executable.path)) { error in
            XCTAssertEqual(error as? ConnectionIssue, .invalidCodexVersion)
        }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 4.5)

        try assertProcessIsGone(at: pidFile)
        try assertProcessIsGone(at: descendantPIDFile)
    }

    func testShutdownStopsActiveVersionProbeAndRejectsFutureProbes() async throws {
        let directory = try makeTemporaryDirectory()
        let executable = directory.appendingPathComponent("codex")
        let pidFile = directory.appendingPathComponent("pid")
        let descendantPIDFile = directory.appendingPathComponent("descendant-pid")
        let invocationFile = directory.appendingPathComponent("invocations")
        let script = """
        #!/bin/sh
        printf 'launch\n' >> "\(invocationFile.path)"
        trap '' TERM
        printf '%s\n' "$$" > "\(pidFile.path)"
        sleep 30 &
        printf '%s\n' "$!" > "\(descendantPIDFile.path)"
        wait
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let locator = CodexExecutableLocator(
            environment: ["PATH": "", "HOME": directory.path],
            homeDirectory: directory
        )
        addTeardownBlock { locator.shutdown() }
        let locateTask = Task.detached {
            do {
                _ = try locator.locate(manualPath: executable.path)
                return false
            } catch {
                return true
            }
        }
        let parentPID = try await waitForPID(at: pidFile)
        let descendantPID = try await waitForPID(at: descendantPIDFile)
        defer {
            _ = kill(-parentPID, SIGKILL)
            _ = kill(parentPID, SIGKILL)
            _ = kill(descendantPID, SIGKILL)
        }

        let startedAt = Date()
        locator.shutdown()
        locator.shutdown()
        let shutdownDuration = Date().timeIntervalSince(startedAt)

        let locateFailed = await locateTask.value
        let completionDuration = Date().timeIntervalSince(startedAt)
        XCTAssertTrue(locateFailed)
        XCTAssertLessThan(shutdownDuration, 1.5)
        XCTAssertLessThan(completionDuration, 1.5)
        assertProcessIsGone(parentPID)
        assertProcessIsGone(descendantPID)
        assertProcessGroupIsGone(parentPID)

        XCTAssertThrowsError(try locator.locate(manualPath: executable.path)) { error in
            XCTAssertEqual(error as? ConnectionIssue, .invalidCodexVersion)
        }
        let launches = try String(contentsOf: invocationFile, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(launches.count, 1)
    }

    private var nestedCLIPath: String {
        "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    }

    private func bundledLocator(roots: [URL], home: URL) -> CodexExecutableLocator {
        CodexExecutableLocator(
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path],
            homeDirectory: home, bundledAppRoots: roots
        )
    }

    private func writeVersionExecutable(at url: URL, output: String, exitStatus: Int = 0) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // All output values are fixed synthetic literals; no host paths are embedded
        // into shell source. The marker proves which fixture was actually launched.
        let script = """
        #!/bin/sh
        [ "$#" -eq 1 ] && [ "$1" = "--version" ] || exit 91
        printf 'probe\\n' >> "$0.invocations"
        printf '%s\\n' '\(output)'
        exit \(exitStatus)
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(url.path, 0o700), 0)
    }

    private func probeCount(_ executable: URL) throws -> Int {
        let marker = executable.appendingPathExtension("invocations")
        guard FileManager.default.fileExists(atPath: marker.path) else { return 0 }
        return try String(contentsOf: marker, encoding: .utf8).split(whereSeparator: \.isNewline).count
    }

    private func waitForPID(at fileURL: URL) async throws -> pid_t {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if let contents = try? String(contentsOf: fileURL, encoding: .utf8),
               let processID = pid_t(
                   contents.trimmingCharacters(in: .whitespacesAndNewlines)
               ),
               processID > 0 {
                return processID
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let missingProcessID: pid_t? = nil
        return try XCTUnwrap(missingProcessID, "Timed out waiting for a complete PID file")
    }

    private func assertProcessIsGone(
        _ pid: pid_t,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(1)
        while kill(pid, 0) == 0, Date() < deadline {
            usleep(20_000)
        }
        let result = kill(pid, 0)
        let processError = errno
        if result == 0 { kill(pid, SIGKILL) }
        XCTAssertEqual(result, -1, "spawned process must be terminated", file: file, line: line)
        if result == -1 {
            XCTAssertEqual(processError, ESRCH, file: file, line: line)
        }
    }

    private func assertProcessGroupIsGone(
        _ processGroupID: pid_t,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(1)
        while kill(-processGroupID, 0) == 0, Date() < deadline {
            usleep(20_000)
        }
        let result = kill(-processGroupID, 0)
        let processError = errno
        if result == 0 { kill(-processGroupID, SIGKILL) }
        XCTAssertEqual(result, -1, "spawned process group must be terminated", file: file, line: line)
        if result == -1 {
            XCTAssertEqual(processError, ESRCH, file: file, line: line)
        }
    }

    private func assertProcessIsGone(
        at pidFile: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(Int32(pidText), file: file, line: line)
        let deadline = Date().addingTimeInterval(1)
        while kill(pid, 0) == 0, Date() < deadline {
            usleep(20_000)
        }
        let result = kill(pid, 0)
        if result == 0 { kill(pid, SIGKILL) }
        XCTAssertEqual(result, -1, "spawned process must be terminated", file: file, line: line)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
