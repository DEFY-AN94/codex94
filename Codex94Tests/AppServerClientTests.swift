import Darwin
import XCTest
@testable import Codex94

final class AppServerClientTests: XCTestCase {
    func testFetchUsesReadOnlyNeverApprovalArguments() async throws {
        let fixture = try makeFixture(script: #"""
        [ "$#" -eq 6 ] || exit 70
        [ "$1" = "-s" ] || exit 71
        [ "$2" = "read-only" ] || exit 72
        [ "$3" = "-a" ] || exit 73
        [ "$4" = "never" ] || exit 74
        [ "$5" = "app-server" ] || exit 75
        [ "$6" = "--stdio" ] || exit 76
        case " $* " in
          *" untrusted "*) exit 77 ;;
        esac

        IFS= read -r initialize
        printf '%s\n' '{"id":1,"result":{"serverInfo":{"name":"fake"}}}'
        IFS= read -r initialized
        IFS= read -r limits
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"limitId":"default-v1","planType":"pro","primary":null,"secondary":{"usedPercent":27,"windowDurationMins":10080,"resetsAt":2000000000}}}}'
        """#)

        let snapshot = try await fixture.client.fetch(
            executable: fixture.executable,
            identityMode: .quotaOnly
        )

        XCTAssertEqual(snapshot.defaultLimitID, "default-v1")
        XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.remainingPercent, 73)
    }

    func testInitializeUsesInjectedClientVersion() async throws {
        let fixture = try makeFixture(
            script: #"""
            IFS= read -r initialize
            case "$initialize" in
              *'"version":"9.8.7"'*) ;;
              *) exit 71 ;;
            esac
            printf '%s\n' '{"id":1,"result":{"serverInfo":{"name":"fake"}}}'
            IFS= read -r initialized
            IFS= read -r limits
            printf '%s\n' '{"id":2,"result":{"rateLimits":{"planType":"pro","primary":null,"secondary":{"usedPercent":27,"windowDurationMins":10080,"resetsAt":2000000000}}}}'
            """#,
            clientVersion: "9.8.7"
        )

        let snapshot = try await fixture.client.fetch(
            executable: fixture.executable,
            identityMode: .quotaOnly
        )
        XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.remainingPercent, 73)
    }

    func testFetchKeepsDefaultCodexAndNamedSparkBucketsSeparate() async throws {
        let fixture = try makeFixture(script: #"""
        IFS= read -r initialize
        printf '%s\n' '{"id":1,"result":{"serverInfo":{"name":"fake"}}}'
        IFS= read -r initialized
        IFS= read -r limits
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"limitId":"default-v2","planType":"pro","primary":null,"secondary":{"usedPercent":63,"windowDurationMins":10080,"resetsAt":2000000000}},"rateLimitsByLimitId":{"default-v2":{"limitId":"ignored-embedded-id","planType":"pro","primary":null,"secondary":{"usedPercent":61,"windowDurationMins":10080,"resetsAt":2000000100}},"model-special":{"limitName":"Spark","planType":"pro","primary":{"usedPercent":28,"windowDurationMins":300,"resetsAt":1999990000},"secondary":{"usedPercent":16,"windowDurationMins":10080,"resetsAt":2000010000}}}}}'
        """#)

        let snapshot = try await fixture.client.fetch(
            executable: fixture.executable,
            identityMode: .quotaOnly
        )

        XCTAssertEqual(snapshot.defaultLimitID, "default-v2")
        XCTAssertEqual(snapshot.buckets.map(\.limitID), ["default-v2", "model-special"])
        XCTAssertNil(snapshot.defaultBucket?.window(.fiveHour))
        XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.usedPercent, 61)
        let spark = try XCTUnwrap(snapshot.bucket(id: "model-special"))
        XCTAssertEqual(spark.limitName, "Spark")
        XCTAssertEqual(spark.window(.fiveHour)?.usedPercent, 28)
        XCTAssertEqual(spark.window(.weekly)?.usedPercent, 16)
    }

    func testFetchIgnoresNotificationsAndMismatchedIDs() async throws {
        let fixture = try makeFixture(script: #"""
        IFS= read -r initialize
        printf '%s\n' '{"method":"server/notice","params":{"ignored":true}}'
        printf '%s\n' '{"id":999,"result":{"ignored":true}}'
        printf '%s\n' '{"id":1,"result":{"serverInfo":{"name":"fake"}}}'
        IFS= read -r initialized
        IFS= read -r account
        printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"test@example.com","planType":"pro"},"requiresOpenaiAuth":true}}'
        IFS= read -r limits
        printf '%s\n' "$$" > "__CODEX94_PID_FILE__"
        sleep 30 &
        printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
        printf '%s\n' '{"id":3,"result":{"rateLimits":{"planType":"pro","primary":null,"secondary":{"usedPercent":27,"windowDurationMins":10080,"resetsAt":2000000000}}}}'
        wait
        """#)

        let snapshot = try await fixture.client.fetch(
            executable: fixture.executable,
            identityMode: .quotaAndAccount
        )

        XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.remainingPercent, 73)
        XCTAssertNil(snapshot.defaultBucket?.window(.fiveHour))
        XCTAssertEqual(snapshot.account?.email, "test@example.com")
        XCTAssertEqual(snapshot.planType, "pro")

        try assertProcessIsGone(at: fixture.pidFile)
        try assertProcessIsGone(at: fixture.descendantPIDFile)
    }

    func testServerErrorIsClassified() async throws {
        let fixture = try makeFixture(script: #"""
        IFS= read -r initialize
        printf '%s\n' '{"id":1,"error":{"code":-32000,"message":"failed"}}'
        """#)
        await assertIssue(.serverError) {
            try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
        }
    }

    func testMissingResultIsClassified() async throws {
        let fixture = try makeFixture(script: #"""
        IFS= read -r initialize
        printf '%s\n' '{"id":1}'
        """#)
        await assertIssue(.missingResult) {
            try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
        }
    }

    func testMalformedJSONIsClassified() async throws {
        let fixture = try makeFixture(script: #"""
        IFS= read -r initialize
        printf '%s\n' 'not-json'
        """#)
        await assertIssue(.malformedResponse) {
            try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
        }
    }

    func testOversizedLineIsRejected() async throws {
        let oversized = String(repeating: "x", count: 2_048)
        let fixture = try makeFixture(
            script: "IFS= read -r initialize\nprintf '%s\\n' '\(oversized)'\n",
            maximumLineBytes: 1_024
        )
        await assertIssue(.responseTooLarge) {
            try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
        }
    }

    func testTimeoutIsClassifiedAndProcessIsStopped() async throws {
        let fixture = try makeFixture(
            script: #"""
            printf '%s\n' "$$" > "__CODEX94_PID_FILE__"
            sleep 30 &
            printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
            wait
            """#,
            initializeTimeout: 0.5,
            totalTimeout: 1
        )
        await assertIssue(.initializationTimedOut) {
            try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
        }
        try assertProcessIsGone(at: fixture.pidFile)
        try assertProcessIsGone(at: fixture.descendantPIDFile)
    }

    func testEarlyExitIsClassified() async throws {
        let fixture = try makeFixture(script: "exit 0\n")
        await assertIssue(.serverExited) {
            try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
        }
    }

    private func assertIssue(
        _ expected: ConnectionIssue,
        operation: () async throws -> QuotaSnapshot
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected.rawValue)")
        } catch {
            XCTAssertEqual(error as? ConnectionIssue, expected)
        }
    }

    private struct Fixture {
        let client: CodexAppServerClient
        let executable: LocatedCodex
        let pidFile: URL
        let descendantPIDFile: URL
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

    private func makeFixture(
        script: String,
        maximumLineBytes: Int = 1_048_576,
        initializeTimeout: TimeInterval = 1,
        totalTimeout: TimeInterval = 3,
        clientVersion: String = "test"
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94ServerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("codex")
        let pidFile = directory.appendingPathComponent("pid")
        let descendantPIDFile = directory.appendingPathComponent("descendant-pid")
        let resolvedScript = script
            .replacingOccurrences(of: "__CODEX94_PID_FILE__", with: pidFile.path)
            .replacingOccurrences(
                of: "__CODEX94_DESCENDANT_PID_FILE__",
                with: descendantPIDFile.path
            )
        try ("#!/bin/sh\n" + resolvedScript).write(
            to: executableURL,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(chmod(executableURL.path, 0o700), 0)

        let timeouts = AppServerTimeouts(
            initialize: initializeTimeout,
            request: 1,
            total: totalTimeout,
            terminationGrace: 0.05,
            maximumLineBytes: maximumLineBytes
        )
        let client = CodexAppServerClient(
            runtimeDirectory: directory.appendingPathComponent("runtime"),
            timeouts: timeouts,
            environment: [
                "HOME": directory.path,
                "PATH": "/usr/bin:/bin",
                "TMPDIR": directory.path
            ],
            clientVersion: clientVersion
        )
        let executable = LocatedCodex(
            executableURL: executableURL,
            version: "codex-cli test",
            source: .manual
        )
        return Fixture(
            client: client,
            executable: executable,
            pidFile: pidFile,
            descendantPIDFile: descendantPIDFile
        )
    }
}
