import Darwin
import XCTest
@testable import Codex94

final class ClaudeQuotaBackendTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 2_000_000_000)

    func testStatuslinePreservesFractionalPercentAndIgnoresPrivateFields() throws {
        let directory = try fixtureDirectory()
        let cache = ClaudeStatuslineCache(fileURL: directory.appendingPathComponent("quota.json"))
        let data = payload(session: "00000000-0000-0000-0000-000000000001", used: "23.5")
        try cache.capture(data, at: first)
        let report = try XCTUnwrap(cache.load())
        let snapshot = try XCTUnwrap(report.snapshot(at: first))
        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.defaultBucket?.window(.fiveHour)?.preciseRemainingPercent, 76.5)
        XCTAssertNil(snapshot.account)
        XCTAssertNil(snapshot.codex)
        let saved = try String(contentsOf: cache.fileURL, encoding: .utf8)
        for value in ["private@example.com", "PRIVATE_TRANSCRIPT", "PRIVATE_CWD", "PRIVATE_TOKEN",
                      "00000000-0000-0000-0000-000000000001", "spend_limit"] {
            XCTAssertFalse(saved.contains(value), value)
        }
    }

    func testUnifiedStatuslineInputKeepsWrapperContractsAndExactSourceFingerprint() throws {
        let data = payload(used: "23.5")
        let parsed = try ClaudeStatuslineParser.parse(data)
        XCTAssertEqual(parsed.windows.map(\.usedPercentage), [23.5])
        XCTAssertEqual(parsed.windows, try ClaudeStatuslineParser.windows(from: data))
        XCTAssertEqual(parsed.producerID, try ClaudeStatuslineParser.producerID(from: data))
        XCTAssertEqual(ClaudeStatuslineParser.identifiableProducerID(parsed.producerID), parsed.producerID)
        let malformedWindow = payload(used: "true")
        XCTAssertThrowsError(try ClaudeStatuslineParser.parse(malformedWindow))
        XCTAssertEqual(try ClaudeStatuslineParser.producerID(from: malformedWindow), parsed.producerID,
                       "The source-only compatibility API must not acquire quota-schema validation")
        let empty = try ClaudeStatuslineParser.parse(Data(#"{"rate_limits":null}"#.utf8))
        XCTAssertTrue(empty.windows.isEmpty)
        XCTAssertEqual(empty.producerID, ClaudeStatuslineParser.legacyUnknownProducerID)
        XCTAssertThrowsError(try ClaudeStatuslineParser.parse(Data(repeating: 32, count: 1_048_577)))
    }

    func testMissingSessionDiscriminatorCannotBeUsedAsASelectedStream() throws {
        for input in [#"{}"#, #"{"session_id":"not-a-session"}"#] {
            let producer = try ClaudeStatuslineParser.producerID(from: Data(input.utf8))
            XCTAssertEqual(producer, ClaudeStatuslineParser.legacyUnknownProducerID)
            XCTAssertNil(ClaudeStatuslineParser.identifiableProducerID(producer))
        }
        let known = try ClaudeStatuslineParser.producerID(from: payload())
        XCTAssertEqual(ClaudeStatuslineParser.identifiableProducerID(known), known)
        XCTAssertNil(ClaudeStatuslineParser.identifiableProducerID(nil))
        XCTAssertNil(ClaudeStatuslineParser.identifiableProducerID(String(repeating: "g", count: 64)))
    }

    func testNullAndAbsentWindowsStayUnknownAndExpiredWindowsDisappear() throws {
        for source in [#"{}"#, #"{"rate_limits":null}"#, #"{"rate_limits":{"five_hour":null}}"#,
                       #"{"rate_limits":{"spend_limit":{"used_percentage":150,"resets_at":2000000010}}}"#] {
            XCTAssertTrue(try ClaudeStatuslineParser.windows(from: Data(source.utf8)).isEmpty)
        }
        let report = ClaudeQuotaReport(source: .statusline, reportedAt: first, receivedAt: first, windows: [
            .init(kind: .fiveHour, usedPercentage: 50, resetsAt: first.addingTimeInterval(5)),
            .init(kind: .weekly, usedPercentage: 23.5, resetsAt: first.addingTimeInterval(10))
        ])
        let remaining = try XCTUnwrap(report.snapshot(at: first.addingTimeInterval(5)))
        XCTAssertNil(remaining.defaultBucket?.window(.fiveHour))
        XCTAssertEqual(remaining.defaultBucket?.window(.weekly)?.preciseUsedPercent, 23.5)
        XCTAssertNil(report.snapshot(at: first.addingTimeInterval(10)))
    }

    func testStatuslineCacheRejectsRecordsThatCarryModelLimits() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94BackendModelLimits-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: support) }
        let cache = ClaudeStatuslineCache(fileURL: support.appendingPathComponent("statusline-quota.json"))
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        let windows = [ClaudeQuotaWindow(kind: .fiveHour, usedPercentage: 30, resetsAt: date.addingTimeInterval(1_000))]
        func record(_ report: ClaudeQuotaReport) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "version": 1, "report": try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)),
                "producers": [:]
            ])
        }
        let plain = ClaudeQuotaReport(source: .statusline, reportedAt: date, receivedAt: date, windows: windows)
        try ClaudeLocalFile.write(try record(plain), to: cache.fileURL)
        XCTAssertEqual(try cache.load(), plain)
        let scoped = ClaudeQuotaReport(source: .statusline, reportedAt: date, receivedAt: date, windows: windows,
                                       modelLimits: [.init(modelName: "Fable", usedPercentage: 1, resetsAt: nil)])
        try ClaudeLocalFile.write(try record(scoped), to: cache.fileURL)
        XCTAssertThrowsError(try cache.load(), "Statusline reports never carry model-scoped limits")
        let foreign = ClaudeQuotaReport(source: .localCache, reportedAt: date, receivedAt: date, windows: windows)
        try ClaudeLocalFile.write(try record(foreign), to: cache.fileURL)
        XCTAssertThrowsError(try cache.load(), "The statusline cache only stores statusline reports")
    }

    func testStatuslineRejectsInvalidNumbersAndOversizedInput() {
        for number in ["true", "false", "-0.1", "100.01", "\"23\"", "1e999"] {
            XCTAssertThrowsError(try ClaudeStatuslineParser.windows(from: payload(used: number)), number)
        }
        for reset in ["true", "0.5", "-1", "\"2000000050\"", "999999999999999999999"] {
            let data = Data("{\"rate_limits\":{\"five_hour\":{\"used_percentage\":2,\"resets_at\":\(reset)}}}".utf8)
            XCTAssertThrowsError(try ClaudeStatuslineParser.windows(from: data), reset)
        }
        XCTAssertThrowsError(try ClaudeStatuslineParser.windows(from: Data(repeating: 32, count: 1_048_577)))
    }

    func testCacheRejectsOutOfRangeDatesAtEveryPersistenceBoundary() throws {
        let cache = ClaudeStatuslineCache(fileURL: try fixtureDirectory().appendingPathComponent("quota.json"))
        for field in ["report.reportedAt", "report.receivedAt", "producer.reportedAt", "producer.validUntil", "resetsAt"] {
            for seconds: TimeInterval in [-1e300, -1, 253_402_300_800, 1e300] {
                try writeTimestampCache(cache, overrides: [field: seconds])
                XCTAssertThrowsError(try cache.load(), "\(field): \(seconds)") { error in
                    XCTAssertEqual(error as? ClaudeQuotaIssue, .invalidData)
                }
            }
        }
    }

    func testCacheRejectsInconsistentObservationAndProducerTimes() throws {
        let cache = ClaudeStatuslineCache(fileURL: try fixtureDirectory().appendingPathComponent("quota.json"))
        for overrides: [String: TimeInterval] in [
            ["report.reportedAt": 2_000_000_001],
            ["producer.reportedAt": 2_000_000_001],
            ["producer.validUntil": 1_999_999_999]
        ] {
            try writeTimestampCache(cache, overrides: overrides)
            XCTAssertThrowsError(try cache.load()) { error in
                XCTAssertEqual(error as? ClaudeQuotaIssue, .invalidData)
            }
        }
    }

    func testCacheAcceptsSupportedDateEndpointsAndRetainsExpiredEvidence() throws {
        let cache = ClaudeStatuslineCache(fileURL: try fixtureDirectory().appendingPathComponent("quota.json"))
        for seconds: TimeInterval in [0, 253_402_300_799] {
            try writeTimestampCache(cache, overrides: [
                "report.reportedAt": seconds, "report.receivedAt": seconds,
                "producer.reportedAt": seconds, "producer.validUntil": seconds, "resetsAt": seconds
            ])
            let report = try XCTUnwrap(cache.load())
            XCTAssertEqual(report.reportedAt, Date(timeIntervalSince1970: seconds))
            XCTAssertEqual(report.windows.first?.resetsAt, Date(timeIntervalSince1970: seconds))
        }
        try writeTimestampCache(cache, overrides: ["resetsAt": 0])
        let expired = try XCTUnwrap(cache.load())
        XCTAssertEqual(expired.windows.count, 1)
        XCTAssertNil(expired.snapshot(at: first))
    }

    func testRepeatedAndAlternatingCachedProducersDoNotAdvanceReportAge() throws {
        let cache = ClaudeStatuslineCache(fileURL: try fixtureDirectory().appendingPathComponent("quota.json"))
        let a = payload(session: "00000000-0000-0000-0000-000000000001", used: "10")
        let b = payload(session: "00000000-0000-0000-0000-000000000002", used: "20")
        try cache.capture(a, at: first)
        try cache.capture(a, at: first.addingTimeInterval(5))
        XCTAssertEqual(try cache.load()?.reportedAt, first)
        try cache.capture(b, at: first.addingTimeInterval(10))
        for index in 1...5 {
            try cache.capture(a, at: first.addingTimeInterval(Double(20 + index)))
            try cache.capture(b, at: first.addingTimeInterval(Double(30 + index)))
        }
        XCTAssertEqual(try cache.load()?.reportedAt, first.addingTimeInterval(10))
        XCTAssertEqual(try cache.load()?.windows.first?.usedPercentage, 20)
        try cache.capture(payload(session: "00000000-0000-0000-0000-000000000002", used: "21"), at: first.addingTimeInterval(40))
        XCTAssertEqual(try cache.load()?.reportedAt, first.addingTimeInterval(40))
    }

    func testEmptyAndExpiredStatuslineEventsDoNotMutateCacheOrProducerClock() throws {
        let cache = ClaudeStatuslineCache(fileURL: try fixtureDirectory().appendingPathComponent("quota.json"))
        try cache.capture(payload(), at: first)
        let before = try Data(contentsOf: cache.fileURL)
        let modifiedAt = try FileManager.default.attributesOfItem(atPath: cache.fileURL.path)[.modificationDate] as? Date
        for input in ["{}", #"{"rate_limits":null}"#,
                      #"{"rate_limits":{"five_hour":{"used_percentage":99,"resets_at":1999999999}}}"#] {
            try cache.capture(Data(input.utf8), at: first.addingTimeInterval(20))
            XCTAssertEqual(try Data(contentsOf: cache.fileURL), before)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: cache.fileURL.path)[.modificationDate] as? Date, modifiedAt)
        }
        try cache.capture(payload(), at: first.addingTimeInterval(30))
        XCTAssertEqual(try cache.load()?.reportedAt, first)
    }

    func testInstallerPreservesOptionsAndUnrelatedSettingsWithoutBackingUpSecrets() throws {
        let fixture = try installerFixture()
        let original: [String: Any] = ["env": ["EXAMPLE_API_KEY": "PRIVATE_TOKEN"], "unrelated": [1, 2],
                                     "statusLine": ["type": "command", "command": "printf existing", "padding": 4, "refreshInterval": 8]]
        try JSONSerialization.data(withJSONObject: original).write(to: fixture.installer.settingsURL)
        let preview = try fixture.installer.previewInstall()
        XCTAssertEqual(preview.originalCommand, "printf existing")
        XCTAssertTrue(preview.preservesExistingStatusline)
        try fixture.installer.install(preview)
        XCTAssertTrue(fixture.installer.isInstalled)
        var settings = try json(fixture.installer.settingsURL)
        let line = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        XCTAssertEqual(line["padding"] as? Int, 4)
        XCTAssertEqual(line["refreshInterval"] as? Int, 8)
        XCTAssertEqual((settings["env"] as? [String: String])?["EXAMPLE_API_KEY"], "PRIVATE_TOKEN")
        for file in try FileManager.default.contentsOfDirectory(at: fixture.support, includingPropertiesForKeys: nil) {
            XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("PRIVATE_TOKEN"), file.lastPathComponent)
        }
        settings["addedAfterInstall"] = true
        try JSONSerialization.data(withJSONObject: settings).write(to: fixture.installer.settingsURL)
        try fixture.installer.remove()
        settings = try json(fixture.installer.settingsURL)
        XCTAssertEqual(settings["addedAfterInstall"] as? Bool, true)
        XCTAssertEqual((settings["statusLine"] as? [String: Any])?["command"] as? String, "printf existing")
        XCTAssertFalse(fixture.installer.isInstalled)
    }

    func testInstallerDetectsPreviewAndRemovalConflictsAndRefusesSymlinks() throws {
        let fixture = try installerFixture()
        try Data("{}".utf8).write(to: fixture.installer.settingsURL)
        let preview = try fixture.installer.previewInstall()
        try Data("{\"changed\":true}".utf8).write(to: fixture.installer.settingsURL)
        XCTAssertThrowsError(try fixture.installer.install(preview))
        let current = try fixture.installer.previewInstall()
        try fixture.installer.install(current)
        try Data(#"{"statusLine":{"type":"command","command":"printf user-change"}}"#.utf8)
            .write(to: fixture.installer.settingsURL)
        XCTAssertThrowsError(try fixture.installer.remove())
        XCTAssertEqual((try json(fixture.installer.settingsURL)["statusLine"] as? [String: String])?["command"], "printf user-change")
        let alias = fixture.support.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.installer.settingsURL)
        XCTAssertThrowsError(try ClaudeLocalFile.read(alias, maximumBytes: 1_024))
    }

    func testOnlyKnownRootOwnedTemporaryAliasesAreAccepted() throws {
        for path in ["/tmp", "/private/tmp", "/var", "/private/var"] {
            XCTAssertNoThrow(try ClaudeLocalFile.requireNoSymlinks(URL(fileURLWithPath: path)))
        }
        let directory = try fixtureDirectory()
        let alias = directory.appendingPathComponent("private-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        XCTAssertThrowsError(try ClaudeLocalFile.requireNoSymlinks(alias.appendingPathComponent("settings.json")))
    }

    func testDisabledBridgeDoesNotWriteQuotaCache() throws {
        let fixture = try installerFixture()
        let preview = try fixture.installer.previewInstall()
        try fixture.installer.install(preview)
        let environment = ["CLAUDE_CONFIG_DIR": fixture.installer.settingsURL.deletingLastPathComponent().path]
        try ClaudeStatuslineBridge.capture(payload(), manifestURL: fixture.installer.manifestURL, enabled: false, now: first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cache.fileURL.path))
        try ClaudeStatuslineBridge.capture(payload(), manifestURL: fixture.installer.manifestURL, enabled: true, now: first,
            installationID: preview.installationID, environment: environment)
        XCTAssertEqual(try fixture.cache.load()?.reportedAt, first)
    }

    func testBridgeEntryReadsItsOwnStandardPreferenceDomainAndPreservesReportAge() throws {
        let original = try helperExecutable()
        let originalBundle = original.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertEqual(originalBundle.pathExtension, "app")
        let root = try fixtureDirectory()
        let copiedBundle = root.appendingPathComponent("IsolatedBridge.app", isDirectory: true)
        try FileManager.default.copyItem(at: originalBundle, to: copiedBundle)
        let suite = "com.defyan94.codex94.bridgefixture.\(UUID().uuidString.lowercased())"
        let infoURL = copiedBundle.appendingPathComponent("Contents/Info.plist")
        var info = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any])
        info["CFBundleIdentifier"] = suite
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL, options: .atomic)
        // Only this disposable test bundle is changed and re-signed. The real
        // test host and installed application keep their identifiers and bytes.
        let signing = Process()
        signing.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signing.arguments = ["--force", "--deep", "--sign", "-", "--identifier", suite, copiedBundle.path]
        signing.standardOutput = FileHandle.nullDevice
        signing.standardError = FileHandle.nullDevice
        try signing.run()
        try waitForExit(signing, timeout: 15)
        XCTAssertEqual(signing.terminationStatus, 0)
        let executable = copiedBundle.appendingPathComponent("Contents/MacOS/Codex94")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            let isolated = UserDefaults(suiteName: suite)
            isolated?.removePersistentDomain(forName: suite)
            isolated?.synchronize()
        }
        let reset = Int(Date().addingTimeInterval(3_600).timeIntervalSince1970)
        let data = Data("{\"session_id\":\"00000000-0000-0000-0000-000000000001\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":23.5,\"resets_at\":\(reset)}}}".utf8)
        for (name, value) in [("enabled", true), ("disabled", false), ("integer", 1), ("string", "true")] as [(String, Any)] {
            defaults.set(value, forKey: "claudeMonitoringEnabled.v1")
            XCTAssertTrue(defaults.synchronize())
            let fixture = try installerFixture(executable: executable)
            let preview = try fixture.installer.previewInstall()
            XCTAssertNil(preview.originalCommand)
            try fixture.installer.install(preview)
            try runIsolatedBridge(executable, manifest: fixture.installer.manifestURL, input: data)
            if name == "enabled" {
                let first = try XCTUnwrap(fixture.cache.load())
                XCTAssertEqual(first.source, .statusline)
                XCTAssertEqual(first.windows.first?.usedPercentage, 23.5)
                XCTAssertEqual(first.windows.first?.resetsAt, Date(timeIntervalSince1970: Double(reset)))
                XCTAssertEqual(first.producerID, try ClaudeStatuslineParser.producerID(from: data))
                try runIsolatedBridge(executable, manifest: fixture.installer.manifestURL, input: data)
                let replay = try XCTUnwrap(fixture.cache.load())
                XCTAssertEqual(replay.reportedAt, first.reportedAt)
                XCTAssertGreaterThan(replay.receivedAt, first.receivedAt)
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cache.fileURL.path), name)
            }
        }
    }

    func testBridgePreservesStaticCommandOutputAndExitWhenItClosesStdinEarly() throws {
        let executable = try helperExecutable()
        let fixture = try installerFixture(executable: executable)
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command",
            "command": "exec 0<&-; printf 'original-output'; exit 0"]]).write(to: fixture.installer.settingsURL)
        try fixture.installer.install(fixture.installer.previewInstall())
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        let invocation = try bridgeInvocation(fixture.installer.manifestURL)
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let writer = input.fileHandleForWriting
        DispatchQueue.global().async {
            try? writer.write(contentsOf: Data(repeating: 32, count: 262_144))
            try? writer.close()
        }
        try waitForExit(process)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), "original-output")
    }

    func testCancellingBridgeTerminatesOriginalCommandAndDescendants() throws {
        let executable = try helperExecutable()
        let fixture = try installerFixture(executable: executable)
        let parentFile = fixture.support.appendingPathComponent("original-pid")
        let childFile = fixture.support.appendingPathComponent("child-pid")
        let command = "trap '' TERM; printf '%s' $$ > '\(parentFile.path)'; sleep 30 & printf '%s' $! > '\(childFile.path)'; wait"
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": command]])
            .write(to: fixture.installer.settingsURL)
        try fixture.installer.install(fixture.installer.previewInstall())
        let process = Process()
        let input = Pipe()
        process.executableURL = executable
        let invocation = try bridgeInvocation(fixture.installer.manifestURL)
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data("{}".utf8))
        try input.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: childFile.path), Date() < deadline { usleep(10_000) }
        let parent = try XCTUnwrap(Int32(try String(contentsOf: parentFile, encoding: .utf8)))
        let child = try XCTUnwrap(Int32(try String(contentsOf: childFile, encoding: .utf8)))
        defer { _ = kill(parent, SIGKILL); _ = kill(child, SIGKILL) }
        process.terminate()
        try waitForExit(process)
        XCTAssertEqual(process.terminationStatus, 128 + SIGTERM)
        XCTAssertEqual(kill(parent, 0), -1)
        XCTAssertEqual(kill(child, 0), -1)
    }

    func testBridgeCancellationPreservesOriginalCommandTERMTrap() throws {
        let executable = try helperExecutable()
        let fixture = try installerFixture(executable: executable)
        let parentFile = fixture.support.appendingPathComponent("original-pid")
        let childFile = fixture.support.appendingPathComponent("child-pid")
        let cleanupFile = fixture.support.appendingPathComponent("term-cleanup")
        // Publish readiness after the trap and its only child exist. The wait
        // builtin is interruptible by TERM; a foreground sleep launched after
        // the PID marker can miss the group signal and defer the shell's trap.
        let command = "trap 'printf cleaned > \"\(cleanupFile.path)\"; exit 0' TERM; sleep 30 & child=$!; printf '%s' $$ > '\(parentFile.path)'; printf '%s' \"$child\" > '\(childFile.path)'; wait \"$child\""
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": command]])
            .write(to: fixture.installer.settingsURL)
        try fixture.installer.install(fixture.installer.previewInstall())
        let process = Process()
        let input = Pipe()
        process.executableURL = executable
        let invocation = try bridgeInvocation(fixture.installer.manifestURL)
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning { process.terminate(); try? waitForExit(process) }
        }
        try input.fileHandleForWriting.write(contentsOf: Data("{}".utf8))
        try input.fileHandleForWriting.close()
        let deadline = ContinuousClock().now.advanced(by: .seconds(3))
        var ready: (parent: Int32, child: Int32)?
        while ContinuousClock().now < deadline {
            if let parentText = try? String(contentsOf: parentFile, encoding: .utf8), let parent = Int32(parentText),
               let childText = try? String(contentsOf: childFile, encoding: .utf8), let child = Int32(childText),
               parent > 1, child > 1, getpgid(parent) == parent, getpgid(child) == parent {
                ready = (parent, child)
                break
            }
            usleep(10_000)
        }
        let (parent, child) = try XCTUnwrap(ready, "The original command and its child must be ready in their owned group")
        defer { _ = kill(parent, SIGKILL); _ = kill(child, SIGKILL) }
        process.terminate()
        try waitForExit(process)
        XCTAssertEqual(process.terminationStatus, 128 + SIGTERM)
        XCTAssertEqual(try String(contentsOf: cleanupFile, encoding: .utf8), "cleaned",
                       "The original shell must receive TERM and run its own cleanup")
        XCTAssertEqual(kill(parent, 0), -1)
        XCTAssertEqual(kill(child, 0), -1)
    }

    func testTerminalQueriesSurviveEveryByteBoundaryWithoutRepeatedReplies() {
        var responder = ClaudeTerminalQueries()
        var responses: [String] = []
        for byte in Data("\u{1b}[c\u{1b}[>0q\u{1b}[6ntext".utf8) {
            responses += responder.responses(to: Data([byte])).map { String(decoding: $0, as: UTF8.self) }
        }
        XCTAssertEqual(responses, ["\u{1b}[?1;2c", "\u{1b}P>|xterm(400)\u{1b}\\", "\u{1b}[1;1R"])
        XCTAssertTrue(responder.responses(to: Data("more text".utf8)).isEmpty)
    }

    func testCLIHandshakeGatesReadyOnDeviceAttributesVersionAndCursorReplies() async throws {
        try await assertGatedCLIUsage(readyScreen: "? for shortcuts")
    }

    func testNewCLIFramedPromptBecomesReadyOnlyAfterTerminalHandshake() async throws {
        let rule = String(repeating: "─", count: 80)
        for prompt in ["❯\u{00a0}Try \"how do I log an error?\"", "❯"] {
            let screen = """
            Claude Code v2.1.286
            \(rule)
            \(prompt)
            \(rule)
            ⚠ Transcript saving is off — CLAUDE_CODE_SKIP_PROMPT_HISTORY is set
            ⏸ plan mode on (shift+tab to cycle)
            """
            try await assertGatedCLIUsage(readyScreen: screen)
        }
    }

    func testNewCLIReadyFooterAcceptsPersistentSeparatedHints() async throws {
        let rule = String(repeating: "─", count: 180)
        for suffix in ["     ◐ medium · /effort", "     Synthetic limit warning"] {
            let screen = """
            Claude Code v2.1.286
            \(rule)
            ❯ Try "show a synthetic example"
            \(rule)
            ⏸ plan mode on (shift+tab to cycle)\(suffix)
            """
            // This fixture never clears its suffix before receiving /usage.
            // Its five-second budget proves readiness does not wait for a tip
            // to expire before submitting the usage request.
            try await assertGatedCLIUsage(readyScreen: screen)
        }
    }

    func testPromptLikeDialogsNeverReceiveUsageInput() async throws {
        let rule = String(repeating: "─", count: 80)
        let framedPrompt = "\(rule)\n❯\n\(rule)"
        let mode = "⏸ plan mode on (shift+tab to cycle)"
        for (body, footer) in [
            ("\(rule)\n❯ Yes, continue\n\(rule)", mode),
            ("❯\n\(rule)", mode),
            (framedPrompt, "⏸ plan mode on (shift+tab to cycle     Synthetic hint"),
            (framedPrompt, mode + "Synthetic hint")
        ] {
            let root = try fixtureDirectory()
            let executable = root.appendingPathComponent("claude")
            let unexpectedInput = root.appendingPathComponent("unexpected-input")
            let frame = "Claude Code v2.1.286\n\(body)\n\(footer)"
                .replacingOccurrences(of: "\n", with: "\\r\\n")
            let script = """
            #!/bin/sh
            if [ "$1" = "--version" ]; then printf '2.1.286 (Claude Code)\\n'; exit 0; fi
            /bin/stty raw -echo
            printf '\\033[2J\\033[H\(frame)\\r\\n'
            /bin/dd bs=1 count=1 > '\(unexpectedInput.path)' 2>/dev/null
            sleep 30
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            let client = ClaudeCLIUsageClient(executableURL: executable, runtimeDirectory: root.appendingPathComponent("runtime"), timeout: 1)
            defer { client.shutdown() }
            do { _ = try await client.fetch(); XCTFail("A dialog is not a ready command input") }
            catch { XCTAssertEqual(error as? ClaudeQuotaIssue, .timedOut) }
            XCTAssertTrue(try Data(contentsOf: unexpectedInput).isEmpty)
        }
    }

    func testUsageParserSkipsModelScopedWindowsAndClearedTerminalFrames() throws {
        let report = try ClaudeUsageScreen.report(from: "Current session\n23.5% used\nCurrent week (all models)\n41% used\nCurrent week (Opus)\n99% used", at: first)
        XCTAssertEqual(report.windows.map(\.usedPercentage), [23.5, 41])
        XCTAssertTrue(report.windows.allSatisfy { $0.resetsAt == nil })
        let cleared = ClaudeUsageScreen.text(from: Data("Current session\r\n99% used\u{1b}[2J\u{1b}[HSelect login method".utf8))
        XCTAssertFalse(cleared.contains("99%"))
        XCTAssertThrowsError(try ClaudeUsageScreen.report(from: cleared, at: first))
    }

    func testScreenSnapshotRejectsTruncatedUTF8AndTerminalSequencesUntilCompleted() {
        let base = Data("Current week (all models)\r\n62.5% used\r\n".utf8)
        XCTAssertTrue(ClaudeUsageScreen.snapshot(from: base).isComplete)
        let character = Data("界".utf8)
        for byteCount in 1..<character.count {
            var bytes = base
            bytes.append(character.prefix(byteCount))
            XCTAssertFalse(ClaudeUsageScreen.snapshot(from: bytes).isComplete,
                           "A readable quota must not bypass an unfinished UTF-8 character")
            bytes.append(character.dropFirst(byteCount))
            let completed = ClaudeUsageScreen.snapshot(from: bytes)
            XCTAssertTrue(completed.isComplete)
            XCTAssertTrue(completed.text.contains("界"))
        }
        for (prefix, suffix) in [
            ("\u{1b}", "[0m"),
            ("\u{1b}[31", "m"),
            ("\u{1b}]0;synthetic-title", "\u{7}"),
            ("\u{1b}]0;synthetic-title\u{1b}", "\\"),
            ("\u{1b}Psynthetic-control-payload", "\u{1b}\\"),
            ("\u{1b}Psynthetic-control-payload\u{1b}", "\\")
        ] {
            var bytes = base
            bytes.append(Data(prefix.utf8))
            XCTAssertFalse(ClaudeUsageScreen.snapshot(from: bytes).isComplete,
                           "An unfinished control sequence must suspend interpretation of the screen")
            bytes.append(Data(suffix.utf8))
            let completed = ClaudeUsageScreen.snapshot(from: bytes)
            XCTAssertTrue(completed.isComplete)
            XCTAssertTrue(completed.text.contains("62.5% used"))
            XCTAssertFalse(completed.text.contains("synthetic-title"))
            XCTAssertFalse(completed.text.contains("synthetic-control-payload"))
        }
    }

    func testScreenSnapshotWaitsForSynchronizedUpdateToClose() {
        let frame = "\u{1b}[?2026h\u{1b}[2J\u{1b}[HCurrent week (all models)\r\n62.5% used"
        XCTAssertFalse(ClaudeUsageScreen.snapshot(from: Data(frame.utf8)).isComplete)
        let completed = ClaudeUsageScreen.snapshot(from: Data((frame + "\u{1b}[?2026l").utf8))
        XCTAssertTrue(completed.isComplete)
        XCTAssertTrue(completed.text.contains("62.5% used"))
        XCTAssertFalse(ClaudeUsageScreen.snapshot(from: Data((frame + "\u{1b}[?2026l\u{1b}[?2026h").utf8)).isComplete,
                       "A later open update cannot reuse an earlier frame's completion")
    }

    func testFakeCLIUsesOnlyUsageAndCleansItsProcessGroup() async throws {
        let root = try fixtureDirectory()
        let executable = root.appendingPathComponent("claude")
        let request = root.appendingPathComponent("request")
        let pid = root.appendingPathComponent("pid")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf '2.1.165 (Claude Code)\\n'; exit 0; fi
        printf '\\033[2J\\033[H? for shortcuts\\n'
        IFS= read -r request
        printf '%s' "$request" > '\(request.path)'
        printf '\\033[2J\\033[HCurrent session\\r\\n23.5%% used\\r\\nCurrent week (all models)\\r\\n41%% used\\r\\n'
        sleep 30 &
        printf '%s' "$!" > '\(pid.path)'
        wait
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let client = ClaudeCLIUsageClient(executableURL: executable, runtimeDirectory: root.appendingPathComponent("runtime"), timeout: 3)
        defer { client.shutdown() }
        let report = try await client.fetch()
        XCTAssertEqual(report.windows.first?.usedPercentage, 23.5)
        XCTAssertEqual(try String(contentsOf: request, encoding: .utf8), "/usage")
        let process = try XCTUnwrap(Int32(try String(contentsOf: pid, encoding: .utf8)))
        XCTAssertEqual(kill(process, 0), -1)
    }

    func testSplitCLIFramesReturnBothWindowsAndTheirActualResetTimes() async throws {
        let reference = Date()
        let sessionReset = Date(timeIntervalSince1970: floor(reference.addingTimeInterval(3_600).timeIntervalSince1970 / 60) * 60)
        let weeklyReset = Date(timeIntervalSince1970: floor(reference.addingTimeInterval(86_400).timeIntervalSince1970 / 60) * 60)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, yyyy, HH:mm"
        let firstFrame = "Current session\\r\\n23.5%% used\\r\\nResets \(formatter.string(from: sessionReset)) (UTC)\\r\\n"
        let secondFrame = "Current week (all models)\\r\\n41%% used\\r\\nResets \(formatter.string(from: weeklyReset)) (UTC)\\r\\n"
        let fixture = try stagedCLI(firstFrame: firstFrame, delayedFrame: secondFrame)
        defer { fixture.client.shutdown() }
        let report = try await fixture.client.fetch()
        XCTAssertEqual(report.windows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(report.windows.map(\.usedPercentage), [23.5, 41])
        XCTAssertEqual(report.windows.map(\.resetsAt), [sessionReset, weeklyReset])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.secondFrameMarker.path),
                      "A successful capture must wait for the real delayed weekly output")
        XCTAssertEqual(try String(contentsOf: fixture.requestFile, encoding: .utf8), "/usage")
        let child = try XCTUnwrap(Int32(try String(contentsOf: fixture.childPIDFile, encoding: .utf8)))
        XCTAssertEqual(kill(child, 0), -1)
    }

    func testStableSingleWindowCLIReportCompletesWithoutInventingWeeklyQuota() async throws {
        let fixture = try stagedCLI(firstFrame: "Current session\\r\\n23.5%% used\\r\\n", delayedFrame: nil)
        defer { fixture.client.shutdown() }
        let report = try await fixture.client.fetch()
        XCTAssertEqual(report.windows.map(\.kind), [.fiveHour])
        XCTAssertEqual(report.windows.first?.usedPercentage, 23.5)
        XCTAssertNil(report.snapshot(at: report.reportedAt)?.defaultBucket?.window(.weekly))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.secondFrameMarker.path))
        XCTAssertEqual(try String(contentsOf: fixture.requestFile, encoding: .utf8), "/usage")
        let child = try XCTUnwrap(Int32(try String(contentsOf: fixture.childPIDFile, encoding: .utf8)))
        XCTAssertEqual(kill(child, 0), -1)
    }

    func testRefreshingUsageFramesWaitForUpdatedWindows() async throws {
        for marker in ["Refreshing…", "Refreshing..."] {
            let cached = "Current session\\r\\n10%% used\\r\\nCurrent week (all models)\\r\\n40%% used\\r\\n\(marker)\\r\\n"
            let updated = "\\033[2J\\033[HCurrent session\\r\\n23.5%% used\\r\\nCurrent week (all models)\\r\\n41%% used\\r\\n"
            let fixture = try stagedCLI(firstFrame: cached, delayedFrame: updated, delay: 1.8)
            defer { fixture.client.shutdown() }
            let report = try await fixture.client.fetch()
            XCTAssertEqual(report.windows.map(\.usedPercentage), [23.5, 41],
                           "A cached panel must not become fresh while its refresh marker remains visible")
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.secondFrameMarker.path))
            XCTAssertEqual(try String(contentsOf: fixture.requestFile, encoding: .utf8), "/usage")
            let child = try XCTUnwrap(Int32(try String(contentsOf: fixture.childPIDFile, encoding: .utf8)))
            XCTAssertEqual(kill(child, 0), -1)
        }
    }

    func testContinuouslyRefreshingUsagePanelTimesOutWithoutReturningCachedWindows() async throws {
        for marker in ["Refreshing…", "Refreshing..."] {
            let cached = "Current session\\r\\n10%% used\\r\\nCurrent week (all models)\\r\\n40%% used\\r\\n\(marker)\\r\\n"
            let fixture = try stagedCLI(firstFrame: cached, delayedFrame: nil, timeout: 3)
            defer { fixture.client.shutdown() }
            let clock = ContinuousClock()
            let started = clock.now
            do { _ = try await fixture.client.fetch(); XCTFail("Refreshing cached quotas cannot complete the read") }
            catch { XCTAssertEqual(error as? ClaudeQuotaIssue, .timedOut) }
            XCTAssertLessThan(clock.now - started, .seconds(6))
            XCTAssertEqual(try String(contentsOf: fixture.requestFile, encoding: .utf8), "/usage")
            let child = try XCTUnwrap(Int32(try String(contentsOf: fixture.childPIDFile, encoding: .utf8)))
            XCTAssertEqual(kill(child, 0), -1)
        }
    }

    func testContinuousReadyAndUsageRedrawsReturnSingleWeeklyWindow() async throws {
        let fixture = try redrawingCLI(redrawReady: true)
        defer { fixture.client.shutdown() }
        let report = try await fixture.client.fetch()
        XCTAssertEqual(report.windows.map(\.kind), [.weekly])
        XCTAssertEqual(report.windows.map(\.usedPercentage), [62.5])
        XCTAssertNil(report.snapshot(at: report.reportedAt)?.defaultBucket?.window(.fiveHour))
        try await assertRedrawingCLICleanedUp(fixture)
        XCTAssertEqual(try Data(contentsOf: fixture.inputFile), Data("/usage\r".utf8),
                       "Continuous ready and usage paints must receive the built-in command exactly once")
        let frames = try String(contentsOf: fixture.framesFile, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertTrue(frames.contains("ready"))
        XCTAssertGreaterThan(frames.filter { $0 == "usage" }.count, 5,
                             "A successful read must settle its values while the panel is still repainting")
        try assertCLIDiagnostic(fixture.diagnostics, phase: .completed, issue: nil, usageSent: true)
    }

    func testContinuousUsageRedrawsReturnStableWeeklyWindow() async throws {
        let fixture = try redrawingCLI(redrawReady: false)
        defer { fixture.client.shutdown() }
        let report = try await fixture.client.fetch()
        XCTAssertEqual(report.windows.map(\.kind), [.weekly])
        XCTAssertEqual(report.windows.map(\.usedPercentage), [62.5])
        try await assertRedrawingCLICleanedUp(fixture)
        XCTAssertEqual(try Data(contentsOf: fixture.inputFile), Data("/usage\r".utf8))
        let frames = try String(contentsOf: fixture.framesFile, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertEqual(frames.filter { $0 == "ready" }.count, 1,
                       "This fixture isolates repainting after a quiet, recognized startup")
        XCTAssertGreaterThan(frames.filter { $0 == "usage" }.count, 5)
        try assertCLIDiagnostic(fixture.diagnostics, phase: .completed, issue: nil, usageSent: true)
    }

    func testContinuouslyRedrawnRefreshingPanelKeepsOriginalDeadline() async throws {
        for marker in ["Refreshing…", "Refreshing..."] {
            let fixture = try redrawingCLI(redrawReady: false, refreshingMarker: marker, timeout: 2)
            defer { fixture.client.shutdown() }
            let clock = ContinuousClock()
            let started = clock.now
            do { _ = try await fixture.client.fetch(); XCTFail("Repainted cached windows cannot finish a refreshing read") }
            catch { XCTAssertEqual(error as? ClaudeQuotaIssue, .timedOut) }
            XCTAssertGreaterThanOrEqual(clock.now - started, .seconds(2))
            XCTAssertLessThan(clock.now - started, .seconds(5), "Every paint must preserve the original transaction deadline")
            try await assertRedrawingCLICleanedUp(fixture)
            XCTAssertEqual(try Data(contentsOf: fixture.inputFile), Data("/usage\r".utf8))
            let frames = try String(contentsOf: fixture.framesFile, encoding: .utf8).components(separatedBy: "\n")
            XCTAssertGreaterThan(frames.filter { $0 == "usage" }.count, 5)
            try assertCLIDiagnostic(fixture.diagnostics, phase: .refreshingUsage, issue: .timedOut, usageSent: true)
        }
    }

    func testContinuouslyRedrawnUnknownStartupNeverReceivesInput() async throws {
        let fixture = try redrawingCLI(redrawReady: true, unknownStartup: true, timeout: 2)
        defer { fixture.client.shutdown() }
        let clock = ContinuousClock()
        let started = clock.now
        do { _ = try await fixture.client.fetch(); XCTFail("Unrecognized startup must not authorize command input") }
        catch { XCTAssertEqual(error as? ClaudeQuotaIssue, .timedOut) }
        XCTAssertGreaterThanOrEqual(clock.now - started, .seconds(2))
        XCTAssertLessThan(clock.now - started, .seconds(5))
        try await assertRedrawingCLICleanedUp(fixture)
        XCTAssertTrue(try Data(contentsOf: fixture.inputFile).isEmpty)
        let frames = try String(contentsOf: fixture.framesFile, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertGreaterThan(frames.filter { $0 == "ready" }.count, 5)
        XCTAssertFalse(frames.contains("usage"))
        try assertCLIDiagnostic(fixture.diagnostics, phase: .waitingForPrompt, issue: .timedOut, usageSent: false)
    }

    func testIncompleteSynchronizedFramesNeitherSendUsageNorReturnInterimQuota() async throws {
        let root = try fixtureDirectory()
        let executable = root.appendingPathComponent("claude")
        let input = root.appendingPathComponent("input")
        let frames = root.appendingPathComponent("frames")
        let parentPID = root.appendingPathComponent("parent-pid")
        let readerPID = root.appendingPathComponent("reader-pid")
        let childPID = root.appendingPathComponent("child-pid")
        let prematureInput = root.appendingPathComponent("input-before-complete")
        let completedFrame = root.appendingPathComponent("completed-frame")
        let rule = String(repeating: "─", count: 80)
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf '2.1.286 (Claude Code)\\n'; exit 0; fi
        /bin/stty raw -echo
        printf '%s' $$ > '\(parentPID.path)'
        : > '\(input.path)'
        : > '\(frames.path)'
        exec 3<&0
        /bin/cat <&3 > '\(input.path)' &
        printf '%s' $! > '\(readerPID.path)'
        /bin/sleep 30 &
        printf '%s' $! > '\(childPID.path)'
        printf '\\033[?2026h\\033[2J\\033[HClaude Code v2.1.286\\r\\n\(rule)\\r\\n❯\\r\\n\(rule)\\r\\n⏸ plan mode on (shift+tab to cycle)\\r\\n'
        /bin/sleep 0.6
        if [ -s '\(input.path)' ]; then printf 'premature' > '\(prematureInput.path)'; fi
        printf '\\033[?2026l'
        while [ ! -s '\(input.path)' ]; do /bin/sleep 0.05; done
        printf '\\033[?2026h\\033[2J\\033[HCurrent week (all models)\\r\\n10%% used\\r\\n'
        /bin/sleep 1.4
        printf '\\033[2J\\033[HCurrent week (all models)\\r\\n62.5%% used\\r\\n\\033[?2026l'
        printf 'complete' > '\(completedFrame.path)'
        wait
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let diagnostics = CLIDiagnosticRecorder()
        let fixture = RedrawingCLIFixture(
            client: ClaudeCLIUsageClient(
                executableURL: executable, runtimeDirectory: root.appendingPathComponent("runtime"), timeout: 6,
                diagnosticHandler: { diagnostics.append($0) }
            ),
            inputFile: input, framesFile: frames, parentPIDFile: parentPID, readerPIDFile: readerPID,
            childPIDFile: childPID, diagnostics: diagnostics
        )
        defer { fixture.client.shutdown() }
        let report = try await fixture.client.fetch()
        XCTAssertEqual(report.windows.map(\.kind), [.weekly])
        XCTAssertEqual(report.windows.map(\.usedPercentage), [62.5],
                       "The provisional 10% frame remains unusable even after the normal one-second settling interval")
        XCTAssertTrue(FileManager.default.fileExists(atPath: completedFrame.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: prematureInput.path),
                       "A ready-looking prompt inside an unfinished synchronized update must not receive input")
        try await assertRedrawingCLICleanedUp(fixture)
        XCTAssertEqual(try Data(contentsOf: input), Data("/usage\r".utf8))
        try assertCLIDiagnostic(diagnostics, phase: .completed, issue: nil, usageSent: true)
    }

    func testProbeSuppressesUpdatesAndHistoryOnlyInItsChildEnvironment() async throws {
        let keys = ["DISABLE_AUTOUPDATER", "CLAUDE_CODE_SKIP_PROMPT_HISTORY", "USER"]
        let before = keys.map { ProcessInfo.processInfo.environment[$0] }
        let injected = ["PATH": "/usr/bin:/bin", "DISABLE_AUTOUPDATER": "0",
                        "CLAUDE_CODE_SKIP_PROMPT_HISTORY": "0", "USER": "codex94-invalid-test-user"]
        let fixture = try stagedCLI(firstFrame: "Current session\\r\\n23.5%% used\\r\\n", delayedFrame: nil,
                                    environment: injected, requireProbeEnvironment: true)
        defer { fixture.client.shutdown() }
        let report = try await fixture.client.fetch()
        XCTAssertEqual(report.windows.first?.usedPercentage, 23.5,
                       "Both child processes require suppression flags and the OS user")
        XCTAssertTrue(keys.map { ProcessInfo.processInfo.environment[$0] } == before,
                      "The probe must not modify the parent environment")
        XCTAssertEqual(injected["DISABLE_AUTOUPDATER"], "0")
        XCTAssertEqual(injected["CLAUDE_CODE_SKIP_PROMPT_HISTORY"], "0")
        XCTAssertEqual(injected["USER"], "codex94-invalid-test-user")
    }

    func testOnboardingLoginAndUnownedTrustNeverReceiveUsageOrConfirmation() async throws {
        for (screen, expected) in [
            ("Welcome to Claude Code\\r\\nSelect theme\\r\\nDark mode", ClaudeQuotaIssue.setupRequired),
            ("Select login method", .loginRequired),
            ("Quick safety check\\r\\n/unowned-folder\\r\\n> Yes, I trust this folder", .setupRequired)
        ] {
            let root = try fixtureDirectory()
            let executable = root.appendingPathComponent("claude")
            let input = root.appendingPathComponent("unexpected-input")
            let script = """
            #!/bin/sh
            if [ "$1" = "--version" ]; then printf '2.1.165 (Claude Code)\\n'; exit 0; fi
            printf '\\033[2J\\033[H\(screen)\\r\\n'
            IFS= read -r unexpected
            printf '%s' "$unexpected" > '\(input.path)'
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            let client = ClaudeCLIUsageClient(executableURL: executable, runtimeDirectory: root.appendingPathComponent("runtime"), timeout: 3)
            defer { client.shutdown() }
            do { _ = try await client.fetch(); XCTFail("Expected an explicit setup/auth state") }
            catch { XCTAssertEqual(error as? ClaudeQuotaIssue, expected) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: input.path))
        }
    }

    func testOwnedTrustSelectionMovesTowardYesThenConfirms() async throws {
        for direction in ["down", "up"] {
            let root = try fixtureDirectory()
            let executable = root.appendingPathComponent("claude")
            let runtime = root.appendingPathComponent("runtime")
            let trace = root.appendingPathComponent("input-trace")
            let childPID = root.appendingPathComponent("child-pid")
            let initial = direction == "down"
                ? "'❯ No, exit' 'Yes, I trust this folder'"
                : "'Yes, I trust this folder' '❯ No, exit'"
            let selected = direction == "down"
                ? "'No, exit' '❯ Yes, I trust this folder'"
                : "'❯ Yes, I trust this folder' 'No, exit'"
            let arrow = direction == "down" ? "B" : "A"
            let script = """
            #!/bin/sh
            if [ "$1" = "--version" ]; then printf '2.1.286 (Claude Code)\\n'; exit 0; fi
            /bin/stty raw -echo
            printf '\\033[2J\\033[H'
            printf '%s\\r\\n' 'Quick safety check:' '\(runtime.path)' \(initial)
            key=$(/bin/dd bs=1 count=3 2>/dev/null)
            [ "$key" = "$(printf '\\033[\(arrow)')" ] || exit 73
            printf '%s\\n' '\(direction)' > '\(trace.path)'
            printf '\\033[2J\\033[H'
            printf '%s\\r\\n' 'Quick safety check:' '\(runtime.path)' \(selected)
            key=$(/bin/dd bs=1 count=1 2>/dev/null)
            [ "$key" = "$(printf '\\r')" ] || exit 74
            printf 'confirm\\n' >> '\(trace.path)'
            printf '\\033[2J\\033[H? for shortcuts\\r\\n'
            key=$(/bin/dd bs=1 count=7 2>/dev/null)
            [ "$key" = "$(printf '/usage\\r')" ] || exit 75
            printf 'usage\\n' >> '\(trace.path)'
            printf '\\033[2J\\033[HCurrent session\\r\\n23.5%% used\\r\\n'
            sleep 30 &
            printf '%s' $! > '\(childPID.path)'
            wait
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            let client = ClaudeCLIUsageClient(executableURL: executable, runtimeDirectory: runtime, timeout: 5)
            defer { client.shutdown() }
            let report = try await client.fetch()
            XCTAssertEqual(report.windows.first?.usedPercentage, 23.5)
            XCTAssertEqual(try String(contentsOf: trace, encoding: .utf8), "\(direction)\nconfirm\nusage\n")
            let child = try XCTUnwrap(Int32(try String(contentsOf: childPID, encoding: .utf8)))
            XCTAssertEqual(kill(child, 0), -1)
        }
    }

    func testTrustNeedsExactOwnedDirectoryAndAnExplicitSelectedOption() async throws {
        for unrelated in [true, false] {
            let root = try fixtureDirectory()
            let executable = root.appendingPathComponent("claude")
            let runtime = root.appendingPathComponent("runtime")
            let displayedPath = unrelated ? runtime.path + "/unrelated" : runtime.path
            let marker = unrelated ? "❯ " : ""
            let trace = root.appendingPathComponent("unexpected-input")
            let script = """
            #!/bin/sh
            if [ "$1" = "--version" ]; then printf '2.1.286 (Claude Code)\\n'; exit 0; fi
            /bin/stty raw -echo
            printf '\\033[2J\\033[H'
            printf '%s\\r\\n' 'Quick safety check:' '\(displayedPath)' '\(marker)No, exit' 'Yes, I trust this folder'
            /bin/dd bs=1 count=1 >/dev/null 2>&1
            printf unexpected > '\(trace.path)'
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            let client = ClaudeCLIUsageClient(executableURL: executable, runtimeDirectory: runtime, timeout: 3)
            defer { client.shutdown() }
            do { _ = try await client.fetch(); XCTFail("Unverified trust menus must not receive any keys") }
            catch { XCTAssertEqual(error as? ClaudeQuotaIssue, .setupRequired) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: trace.path))
        }
    }

    func testTrustMatchesOnlyCompleteKnownSystemAliasComponents() {
        for name in ["tmp", "var"] {
            let alias = "/\(name)/Codex94-owned/runtime"
            let physical = "/private/\(name)/Codex94-owned/runtime"
            XCTAssertTrue(ClaudeCLIUsageClient.matchesOwnedRuntimePath(
                physical, runtimeDirectory: URL(fileURLWithPath: alias)))
            XCTAssertTrue(ClaudeCLIUsageClient.matchesOwnedRuntimePath(
                alias, runtimeDirectory: URL(fileURLWithPath: physical)))
            for unowned in [alias + "-other", alias + "/child", physical + "/../runtime",
                            "/private/\(name)-other/Codex94-owned/runtime", "prefix " + alias,
                            alias + " suffix", "\(name)/Codex94-owned/runtime"] {
                XCTAssertFalse(ClaudeCLIUsageClient.matchesOwnedRuntimePath(
                    unowned, runtimeDirectory: URL(fileURLWithPath: alias)), unowned)
            }
        }
        XCTAssertFalse(ClaudeCLIUsageClient.matchesOwnedRuntimePath(
            "/private/Users/synthetic/runtime", runtimeDirectory: URL(fileURLWithPath: "/Users/synthetic/runtime")))
    }

    func testCancellingCLIReadStopsItsOwnedProcessGroup() async throws {
        let root = try fixtureDirectory()
        let executable = root.appendingPathComponent("claude")
        let pid = root.appendingPathComponent("pid")
        let childPID = root.appendingPathComponent("child-pid")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf '2.1.165 (Claude Code)\\n'; exit 0; fi
        printf '%s' $$ > '\(pid.path)'
        sleep 30 &
        printf '%s' $! > '\(childPID.path)'
        wait
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let client = ClaudeCLIUsageClient(executableURL: executable, runtimeDirectory: root.appendingPathComponent("runtime"), timeout: 10)
        defer { client.shutdown() }
        let request = Task { try await client.fetch() }
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: childPID.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let parent = try XCTUnwrap(Int32(try String(contentsOf: pid, encoding: .utf8)))
        let child = try XCTUnwrap(Int32(try String(contentsOf: childPID, encoding: .utf8)))
        request.cancel()
        do { _ = try await request.value; XCTFail("Cancelled reads cannot return a quota") }
        catch { XCTAssertTrue(error is CancellationError) }
        let cleanupDeadline = ContinuousClock().now.advanced(by: .seconds(3))
        while (kill(parent, 0) == 0 || kill(child, 0) == 0), ContinuousClock().now < cleanupDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(kill(parent, 0), -1)
        XCTAssertEqual(kill(child, 0), -1)
    }

    func testSilentCLIHonorsInjectedShortDeadlineAndCleansUp() async throws {
        let root = try fixtureDirectory()
        let executable = root.appendingPathComponent("claude")
        let pidFile = root.appendingPathComponent("pid")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf '2.1.165 (Claude Code)\\n'; exit 0; fi
        printf '%s' $$ > '\(pidFile.path)'
        exec /bin/sleep 30
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let client = ClaudeCLIUsageClient(executableURL: executable, runtimeDirectory: root.appendingPathComponent("runtime"), timeout: 1)
        defer { client.shutdown() }
        let clock = ContinuousClock()
        let started = clock.now
        do { _ = try await client.fetch(); XCTFail("Expected the bounded CLI timeout") }
        catch { XCTAssertEqual(error as? ClaudeQuotaIssue, .timedOut) }
        XCTAssertLessThan(clock.now - started, .seconds(4))
        let process = try XCTUnwrap(Int32(try String(contentsOf: pidFile, encoding: .utf8)))
        XCTAssertEqual(kill(process, 0), -1)
    }

    private func assertGatedCLIUsage(readyScreen: String) async throws {
        let root = try fixtureDirectory()
        let executable = root.appendingPathComponent("claude")
        let trace = root.appendingPathComponent("handshake-trace")
        let unexpectedInput = root.appendingPathComponent("unexpected-input")
        let childPID = root.appendingPathComponent("child-pid")
        let readyFrame = readyScreen.replacingOccurrences(of: "\n", with: "\\r\\n")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf '2.1.286 (Claude Code)\\n'; exit 0; fi
        /bin/stty raw -echo
        printf '\\033[c'
        expected=$(printf '\\033[?1;2c')
        reply=$(/bin/dd bs=1 count="${#expected}" 2>/dev/null)
        [ "$reply" = "$expected" ] || exit 73
        printf 'device-attributes\\n' > '\(trace.path)'
        printf '\\033[>0q'
        expected=$(printf '\\033P>|xterm(400)\\033\\\\')
        reply=$(/bin/dd bs=1 count="${#expected}" 2>/dev/null)
        [ "$reply" = "$expected" ] || exit 74
        printf 'terminal-version\\n' >> '\(trace.path)'
        printf '\\033[6n'
        expected=$(printf '\\033[1;1R')
        reply=$(/bin/dd bs=1 count="${#expected}" 2>/dev/null)
        [ "$reply" = "$expected" ] || exit 75
        printf 'cursor-position\\n' >> '\(trace.path)'
        printf '\\033[2J\\033[H\(readyFrame)\\r\\n'
        key=$(/bin/dd bs=1 count=7 2>/dev/null)
        [ "$key" = "$(printf '/usage\\r')" ] || exit 76
        printf 'usage\\n' >> '\(trace.path)'
        printf '\\033[2J\\033[HCurrent session\\r\\n23.5%% used\\r\\n'
        sleep 30 &
        printf '%s' $! > '\(childPID.path)'
        /bin/dd bs=1 count=1 > '\(unexpectedInput.path)' 2>/dev/null
        wait
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let client = ClaudeCLIUsageClient(executableURL: executable, runtimeDirectory: root.appendingPathComponent("runtime"), timeout: 5)
        defer { client.shutdown() }
        let report = try await client.fetch()
        XCTAssertEqual(report.windows.first?.usedPercentage, 23.5)
        XCTAssertEqual(try String(contentsOf: trace, encoding: .utf8),
                       "device-attributes\nterminal-version\ncursor-position\nusage\n")
        XCTAssertTrue(try Data(contentsOf: unexpectedInput).isEmpty,
                      "After terminal negotiation the probe must submit only the built-in usage command")
        let child = try XCTUnwrap(Int32(try String(contentsOf: childPID, encoding: .utf8)))
        XCTAssertEqual(kill(child, 0), -1)
    }

    private func payload(session: String = "00000000-0000-0000-0000-000000000001", used: String = "23.5") -> Data {
        Data("""
        {"session_id":"\(session)","cwd":"PRIVATE_CWD","transcript_path":"PRIVATE_TRANSCRIPT","email":"private@example.com","token":"PRIVATE_TOKEN","rate_limits":{"five_hour":{"used_percentage":\(used),"resets_at":2000001000},"spend_limit":{"used_percentage":150,"resets_at":2000002000}}}
        """.utf8)
    }

    private func writeTimestampCache(_ cache: ClaudeStatuslineCache, overrides: [String: TimeInterval]) throws {
        func date(_ key: String, fallback: TimeInterval = 2_000_000_000) -> Date {
            Date(timeIntervalSince1970: overrides[key] ?? fallback)
        }
        let producerID = String(repeating: "a", count: 64)
        let report = ClaudeQuotaReport(
            source: .statusline, reportedAt: date("report.reportedAt"), receivedAt: date("report.receivedAt"),
            windows: [.init(kind: .fiveHour, usedPercentage: 23.5, resetsAt: date("resetsAt", fallback: 2_000_001_000))],
            producerID: producerID
        )
        // Match Codable's reference-date encoding while supplying damaged, finite dates.
        let record: [String: Any] = [
            "version": 1, "report": try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)),
            "producers": [producerID: [
                "fingerprint": String(repeating: "b", count: 64),
                "reportedAt": date("producer.reportedAt").timeIntervalSinceReferenceDate,
                "validUntil": date("producer.validUntil", fallback: 2_000_604_800).timeIntervalSinceReferenceDate
            ]]
        ]
        try JSONSerialization.data(withJSONObject: record).write(to: cache.fileURL)
    }

    private func stagedCLI(firstFrame: String, delayedFrame: String?, environment: [String: String]? = nil,
                           requireProbeEnvironment: Bool = false, expectedConfigDirectory: String? = nil,
                           delay: TimeInterval = 0.4,
                           timeout: TimeInterval = 5) throws -> (
        client: ClaudeCLIUsageClient, requestFile: URL, childPIDFile: URL, secondFrameMarker: URL
    ) {
        let root = try fixtureDirectory()
        let executable = root.appendingPathComponent("claude")
        let request = root.appendingPathComponent("request")
        let childPID = root.appendingPathComponent("child-pid")
        let marker = root.appendingPathComponent("second-frame")
        let later = delayedFrame.map { frame in
            "sleep \(delay)\nprintf '\(frame)'\nprintf ready > '\(marker.path)'"
        } ?? ""
        let environmentChecks = requireProbeEnvironment ? #"""
        [ "$DISABLE_AUTOUPDATER" = "1" ] || exit 70
        [ "$CLAUDE_CODE_SKIP_PROMPT_HISTORY" = "1" ] || exit 71
        [ -n "$USER" ] && [ "$USER" = "$(/usr/bin/id -un)" ] || exit 72
        """# : ""
        let configChecks = expectedConfigDirectory.map { directory in
            let quoted = "'" + directory.replacingOccurrences(of: "'", with: "'\\''") + "'"
            return "[ \"$CLAUDE_CONFIG_DIR\" = \(quoted) ] || exit 73\n[ -z \"$CODEX94_TEST_UNRELATED_AUTH\" ] || exit 74"
        } ?? ""
        let script = """
        #!/bin/sh
        \(environmentChecks)
        \(configChecks)
        if [ "$1" = "--version" ]; then printf '2.1.165 (Claude Code)\\n'; exit 0; fi
        printf '\\033[2J\\033[H? for shortcuts\\n'
        IFS= read -r request
        printf '%s' "$request" > '\(request.path)'
        printf '\\033[2J\\033[H\(firstFrame)'
        \(later)
        sleep 30 &
        printf '%s' $! > '\(childPID.path)'
        wait
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (ClaudeCLIUsageClient(executableURL: executable, runtimeDirectory: root.appendingPathComponent("runtime"),
                                     environment: environment ?? ProcessInfo.processInfo.environment, timeout: timeout),
                request, childPID, marker)
    }

    private struct RedrawingCLIFixture {
        let client: ClaudeCLIUsageClient
        let inputFile: URL
        let framesFile: URL
        let parentPIDFile: URL
        let readerPIDFile: URL
        let childPIDFile: URL
        let diagnostics: CLIDiagnosticRecorder
    }

    private final class CLIDiagnosticRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [ClaudeCLIUsageDiagnostic] = []
        func append(_ value: ClaudeCLIUsageDiagnostic) { lock.withLock { values.append(value) } }
        func read() -> [ClaudeCLIUsageDiagnostic] { lock.withLock { values } }
    }

    private func assertCLIDiagnostic(_ recorder: CLIDiagnosticRecorder, phase: ClaudeCLIUsageDiagnostic.Phase,
                                     issue: ClaudeQuotaIssue?, usageSent: Bool,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let values = recorder.read()
        XCTAssertEqual(values.count, 1, "Each fetch must report exactly one final diagnostic", file: file, line: line)
        let diagnostic = try XCTUnwrap(values.first, file: file, line: line)
        XCTAssertEqual(diagnostic.phase, phase, file: file, line: line)
        XCTAssertEqual(diagnostic.result, issue == nil ? .success : .failure, file: file, line: line)
        XCTAssertEqual(diagnostic.issue, issue, file: file, line: line)
        XCTAssertEqual(diagnostic.usageSent, usageSent, file: file, line: line)
        XCTAssertTrue(diagnostic.terminalReceived, file: file, line: line)
        XCTAssertGreaterThan(diagnostic.durationMilliseconds, 0, file: file, line: line)
        XCTAssertLessThan(diagnostic.durationMilliseconds, 6_000, file: file, line: line)
    }

    /// The fixture continuously changes only an unrelated animation counter.
    /// Raw input is recorded independently, including any accidental duplicate
    /// command or confirmation. All processes belong to the client's fake group.
    private func redrawingCLI(redrawReady: Bool, unknownStartup: Bool = false,
                               refreshingMarker: String? = nil, timeout: TimeInterval = 4) throws -> RedrawingCLIFixture {
        let root = try fixtureDirectory()
        let executable = root.appendingPathComponent("claude")
        let input = root.appendingPathComponent("input")
        let frames = root.appendingPathComponent("frames")
        let parentPID = root.appendingPathComponent("parent-pid")
        let readerPID = root.appendingPathComponent("reader-pid")
        let childPID = root.appendingPathComponent("child-pid")
        let rule = String(repeating: "─", count: 80)
        let startup = unknownStartup ? "Unrecognized synthetic startup panel" :
            "Claude Code v2.1.286\\r\\n\(rule)\\r\\n❯\\r\\n\(rule)\\r\\n⏸ plan mode on (shift+tab to cycle)"
        let marker = refreshingMarker.map { "\\r\\n" + $0 } ?? ""
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf '2.1.286 (Claude Code)\\n'; exit 0; fi
        /bin/stty raw -echo
        printf '%s' $$ > '\(parentPID.path)'
        : > '\(input.path)'
        : > '\(frames.path)'
        exec 3<&0
        /bin/cat <&3 > '\(input.path)' &
        printf '%s' $! > '\(readerPID.path)'
        /bin/sleep 30 &
        printf '%s' $! > '\(childPID.path)'
        painted=0
        tick=0
        while :; do
            if [ -s '\(input.path)' ]; then
                printf '\\033[2J\\033[HCurrent week (all models)\\r\\n62.5%% used\(marker)\\r\\nAnimation %s\\r\\n' "$tick"
                printf 'usage\\n' >> '\(frames.path)'
            elif [ '\(redrawReady ? "1" : "0")' = 1 ] || [ "$painted" = 0 ]; then
                printf '\\033[2J\\033[H\(startup)\\r\\nAnimation %s\\r\\n' "$tick"
                printf 'ready\\n' >> '\(frames.path)'
                painted=1
            fi
            tick=$((tick + 1))
            /bin/sleep 0.05
        done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let diagnostics = CLIDiagnosticRecorder()
        return RedrawingCLIFixture(
            client: ClaudeCLIUsageClient(
                executableURL: executable, runtimeDirectory: root.appendingPathComponent("runtime"), timeout: timeout,
                diagnosticHandler: { diagnostics.append($0) }
            ),
            inputFile: input, framesFile: frames, parentPIDFile: parentPID, readerPIDFile: readerPID,
            childPIDFile: childPID, diagnostics: diagnostics
        )
    }

    private func assertRedrawingCLICleanedUp(_ fixture: RedrawingCLIFixture,
                                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let processes = try [fixture.parentPIDFile, fixture.readerPIDFile, fixture.childPIDFile].map {
            try XCTUnwrap(Int32(String(contentsOf: $0, encoding: .utf8)), file: file, line: line)
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while processes.contains(where: { kill($0, 0) == 0 }), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        for process in processes {
            XCTAssertEqual(kill(process, 0), -1, "The client must stop its entire synthetic process group", file: file, line: line)
        }
    }

    func testProbeUsesOneCustomConfigurationForVersionAndUsage() async throws {
        let root = try fixtureDirectory().appendingPathComponent("custom profile")
        let injected = ["PATH": "/usr/bin:/bin", "CLAUDE_CONFIG_DIR": root.path,
                        "CODEX94_TEST_UNRELATED_AUTH": "must-not-be-forwarded"]
        let fixture = try stagedCLI(firstFrame: "Current session\\r\\n23.5%% used\\r\\n", delayedFrame: nil,
                                    environment: injected, expectedConfigDirectory: root.path)
        defer { fixture.client.shutdown() }
        let report = try await fixture.client.fetch()
        XCTAssertEqual(report.windows.first?.usedPercentage, 23.5,
                       "Both version and usage must use the same configured profile")
    }

    func testCacheInstallationGenerationDoesNotReusePriorReportOrDeduplicationClock() throws {
        let cache = ClaudeStatuslineCache(fileURL: try fixtureDirectory().appendingPathComponent("cache.json"))
        let old = UUID().uuidString, current = UUID().uuidString
        try cache.capture(payload(), at: first.addingTimeInterval(100), installationID: old)
        try cache.capture(payload(), at: first, installationID: current)
        let entry = try XCTUnwrap(cache.loadEntry())
        XCTAssertEqual(entry.installationID, current)
        XCTAssertEqual(entry.report.reportedAt, first,
                       "Same producer/values must not inherit another installation's later observation")
        try cache.capture(payload(), at: first.addingTimeInterval(10), installationID: current)
        XCTAssertEqual(try cache.loadEntry()?.report.reportedAt, first)
        XCTAssertThrowsError(try cache.capture(payload(), installationID: "invalid"))
    }

    func testReinstalledBridgeRejectsOldInvocationAndRetiredCapture() throws {
        let fixture = try installerFixture()
        let environment = ["CLAUDE_CONFIG_DIR": fixture.installer.settingsURL.deletingLastPathComponent().path]
        let directories = ClaudeConfigurationDirectories(environment: environment)
        let old = try fixture.installer.previewInstall()
        try fixture.installer.install(old)
        let retired = try JSONDecoder().decode(ClaudeStatuslineInstaller.Manifest.self,
            from: Data(contentsOf: fixture.installer.manifestURL))
        try ClaudeStatuslineBridge.capture(payload(), manifestURL: fixture.installer.manifestURL,
            enabled: true, now: first.addingTimeInterval(100), installationID: old.installationID, environment: environment)
        try fixture.installer.remove()
        let current = try fixture.installer.previewInstall()
        try fixture.installer.install(current)
        XCTAssertNotEqual(old.installationID, current.installationID)
        XCTAssertTrue(current.bridgeCommand.contains(current.installationID))
        XCTAssertEqual(fixture.installer.reportEligibility(installationID: old.installationID), .blocked)
        XCTAssertThrowsError(try ClaudeStatuslineBridge.capture(payload(), manifestURL: fixture.installer.manifestURL,
            enabled: true, now: first, installationID: old.installationID, environment: environment))
        XCTAssertThrowsError(try ClaudeStatuslineBridge.capture(payload(), manifestURL: fixture.installer.manifestURL,
            enabled: true, now: first, environment: environment), "Old argument format cannot acquire the new installation ID")
        try ClaudeStatuslineBridge.capture(payload(), manifestURL: fixture.installer.manifestURL,
            enabled: true, now: first, installationID: current.installationID, environment: environment)
        let accepted = try XCTUnwrap(fixture.cache.loadEntry())
        XCTAssertEqual(accepted.installationID, current.installationID)
        XCTAssertEqual(accepted.report.reportedAt, first)
        XCTAssertThrowsError(try ClaudeStatuslineBridge.capture(payload(used: "90"), manifest: retired,
            manifestURL: fixture.installer.manifestURL, directories: directories, now: first.addingTimeInterval(200)))
        XCTAssertEqual(try fixture.cache.loadEntry(), accepted, "An already running old bridge cannot overwrite the new cache")
    }

    func testBridgeRefusesAnotherConfigurationEvenWithCurrentInstallationID() throws {
        let fixture = try installerFixture()
        let preview = try fixture.installer.previewInstall()
        try fixture.installer.install(preview)
        XCTAssertThrowsError(try ClaudeStatuslineBridge.capture(payload(), manifestURL: fixture.installer.manifestURL,
            enabled: true, now: first, installationID: preview.installationID,
            environment: ["CLAUDE_CONFIG_DIR": fixture.support.appendingPathComponent("other").path]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cache.fileURL.path))
    }

    func testInstallationMutationAndCaptureUseOneNonblockingLock() throws {
        let fixture = try installerFixture()
        let preview = try fixture.installer.previewInstall()
        try fixture.installer.install(preview)
        let original = try Data(contentsOf: fixture.installer.manifestURL)
        try fixture.cache.withExclusiveAccess {
            XCTAssertThrowsError(try fixture.installer.remove())
            XCTAssertThrowsError(try fixture.cache.capture(payload(), at: first, installationID: preview.installationID))
            XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), original)
        }
        try fixture.installer.remove()
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
    }

    private func fixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("Codex94ClaudeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func installerFixture(executable: URL = URL(fileURLWithPath: "/bin/echo")) throws -> (installer: ClaudeStatuslineInstaller, support: URL, cache: ClaudeStatuslineCache) {
        let root = try fixtureDirectory()
        let support = root.appendingPathComponent("support")
        let cache = ClaudeStatuslineCache(fileURL: support.appendingPathComponent("statusline-quota.json"))
        let installer = ClaudeStatuslineInstaller(settingsURL: root.appendingPathComponent("settings.json"), cache: cache,
            executableURL: executable, supportDirectory: support)
        return (installer, support, cache)
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func helperExecutable() throws -> URL {
        guard let executable = Bundle.main.executableURL, executable.lastPathComponent == "Codex94" else {
            throw XCTSkip("The bridge integration test requires the product app test host")
        }
        return executable
    }

    private func bridgeInvocation(_ url: URL) throws -> (arguments: [String], environment: [String: String]) {
        let manifest = try JSONDecoder().decode(ClaudeStatuslineInstaller.Manifest.self, from: Data(contentsOf: url))
        var arguments = [ClaudeStatuslineBridge.argument, url.path]
        if let id = manifest.installationID { arguments.append(id) }
        var environment = CodexExecutableLocator.sanitizedEnvironment(from: ProcessInfo.processInfo.environment)
        environment["CLAUDE_CONFIG_DIR"] = URL(fileURLWithPath: manifest.settingsPath).deletingLastPathComponent().path
        return (arguments, environment)
    }

    private func runIsolatedBridge(_ executable: URL, manifest: URL, input data: Data) throws {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        let invocation = try bridgeInvocation(manifest)
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate(); try? waitForExit(process) } }
        try input.fileHandleForWriting.write(contentsOf: data)
        try input.fileHandleForWriting.close()
        try waitForExit(process)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval = 4) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { usleep(10_000) }
        if process.isRunning {
            process.terminate()
            let cancellationDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < cancellationDeadline { usleep(10_000) }
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            XCTFail("Synthetic bridge exceeded the test deadline")
        }
        process.waitUntilExit()
    }
}
