import Darwin
import XCTest
@testable import Codex94

final class AppServerClientTests: XCTestCase {
    func testQueuedQuotaCancelledBeforeSpawnDoesNotCancelNewGeneration() async throws {
        try await assertQueuedCancellation(usage: false)
    }

    func testQueuedUsageCancelledBeforeSpawnDoesNotCancelNewGeneration() async throws {
        try await assertQueuedCancellation(usage: true)
    }

    func testShutdownRejectsQueuedAndFutureRequestsBeforeSpawning() async throws {
        let queue = DispatchQueue(label: "Codex94Tests.shutdown-blocked-worker")
        let gate = AppServerQueueGate()
        queue.async { gate.blockWorker() }
        defer { gate.releaseWorker() }
        try await waitForQueueGate("Worker must be blocked before fetching") { gate.isBlocked }
        let fixture = try makeFixture(
            script: #"printf '%s\n' "$$" > "__CODEX94_PID_FILE__""#,
            workerQueue: queue, requestEnqueued: { gate.recordEnqueue() }
        )
        let pending = Task<Void, Error> {
            _ = try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
        }
        try await waitForQueueGate("The request must actually enter the blocked queue") { gate.enqueuedCount == 1 }
        fixture.client.shutdown()
        gate.releaseWorker()
        await assertIssue(.serverExited) { try await pending.value }
        await assertIssue(.serverExited) {
            _ = try await fixture.client.fetchUsage(executable: fixture.executable)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.pidFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.invocationFile.path))
        XCTAssertFalse(gate.didTimeOut)
    }

    /// Use the real dispatch queue and synthetic subprocess, not a fake ticket
    /// predicate. Enqueue acknowledgement makes cancellation deterministic.
    private func assertQueuedCancellation(usage: Bool) async throws {
        let queue = DispatchQueue(label: "Codex94Tests.cancel-blocked-worker")
        let gate = AppServerQueueGate()
        queue.async { gate.blockWorker() }
        defer { gate.releaseWorker() }
        try await waitForQueueGate("Worker must be blocked before enqueueing") { gate.isBlocked }
        let fixture = try makeFixture(script: #"""
        printf '%s\n' "$$" > "__CODEX94_PID_FILE__"
        IFS= read -r initialize
        printf '%s\n' "$initialize" >> "__CODEX94_INVOCATION_FILE__"
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        printf '%s\n' "$initialized" >> "__CODEX94_INVOCATION_FILE__"
        IFS= read -r request
        printf '%s\n' "$request" >> "__CODEX94_INVOCATION_FILE__"
        case "$request" in
          *'"method":"account/usage/read"'*|*'"method":"account\/usage\/read"'*)
            printf '%s\n' '{"id":2,"result":{"summary":{"lifetimeTokens":42},"dailyUsageBuckets":[]}}' ;;
          *'"method":"account/rateLimits/read"'*|*'"method":"account\/rateLimits\/read"'*)
            printf '%s\n' '{"id":2,"result":{"rateLimits":{"secondary":{"usedPercent":27,"windowDurationMins":10080}}}}' ;;
          *) exit 74 ;;
        esac
        """#, workerQueue: queue, requestEnqueued: { gate.recordEnqueue() })
        let operation: @Sendable () async throws -> Int = {
            if usage {
                return try await fixture.client.fetchUsage(executable: fixture.executable).summary.lifetimeTokens ?? -1
            }
            return try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
                .defaultBucket?.window(.weekly)?.remainingPercent ?? -1
        }
        let cancelled = Task { try await operation() }
        try await waitForQueueGate("The old request must already be queued before cancellation") { gate.enqueuedCount == 1 }
        fixture.client.cancelCurrentRequest()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.pidFile.path))

        // Queue a new ticket while the old cancelled work is still blocked.
        let current = Task { try await operation() }
        try await waitForQueueGate("The new generation must also be queued") { gate.enqueuedCount == 2 }
        gate.releaseWorker()
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled queued work must not launch a subprocess")
        } catch is CancellationError {
            // Expected: nonterminal cancellation does not poison the next ticket.
        } catch {
            XCTFail("Queued cancellation must have its own cancellation outcome")
        }
        let value = try await current.value
        XCTAssertEqual(value, usage ? 42 : 73)
        XCTAssertEqual(try recordedRequests(fixture).compactMap { $0["method"] as? String }, [
            "initialize", "initialized", usage ? "account/usage/read" : "account/rateLimits/read"
        ], "Only the new generation may execute the synthetic server")
        try assertProcessIsGone(at: fixture.pidFile)
        XCTAssertFalse(gate.didTimeOut)
    }

    private func waitForQueueGate(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), message)
        if !condition() { throw CancellationError() }
    }

    func testUsageFetchSendsOnlyReadOnlyUsageMethodWithoutParameters() async throws {
        let fixture = try makeFixture(script: #"""
        [ "$#" -eq 6 ] || exit 70
        [ "$1" = "-s" ] && [ "$2" = "read-only" ] || exit 71
        [ "$3" = "-a" ] && [ "$4" = "never" ] || exit 72
        [ "$5" = "app-server" ] && [ "$6" = "--stdio" ] || exit 73
        IFS= read -r initialize
        printf '%s\n' "$initialize" >> "__CODEX94_INVOCATION_FILE__"
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        printf '%s\n' "$initialized" >> "__CODEX94_INVOCATION_FILE__"
        IFS= read -r usage
        printf '%s\n' "$usage" >> "__CODEX94_INVOCATION_FILE__"
        printf '%s\n' '{"method":"usage/notice","params":{"ignored":true}}'
        printf '%s\n' '{"id":99,"result":{"ignored":true}}'
        printf '%s\n' '{"id":2,"result":{"summary":{"lifetimeTokens":123456,"peakDailyTokens":7890,"longestRunningTurnSec":91,"currentStreakDays":0,"longestStreakDays":6},"dailyUsageBuckets":[{"startDate":"2024-02-29","tokens":120},{"startDate":"2024-02-27","tokens":0}],"threadUsage":[{"threadId":"ignored-private-id"}]}}'
        while IFS= read -r extra; do
          printf '%s\n' "$extra" >> "__CODEX94_INVOCATION_FILE__"
        done
        """#)

        let snapshot = try await fixture.client.fetchUsage(executable: fixture.executable)
        XCTAssertEqual(snapshot.summary.lifetimeTokens, 123_456)
        XCTAssertEqual(snapshot.summary.currentStreakDays, 0)
        XCTAssertEqual(snapshot.dailyUsageBuckets?.map(\.startDate), ["2024-02-27", "2024-02-29"])
        let requests = try String(contentsOf: fixture.invocationFile, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { line in
                try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            }
        XCTAssertEqual(requests.compactMap { $0["method"] as? String }, [
            "initialize", "initialized", "account/usage/read"
        ])
        XCTAssertNil(requests.last?["params"])
    }

    func testUnsupportedUsageDoesNotDisableSubsequentQuotaReads() async throws {
        let fixture = try makeFixture(script: #"""
        IFS= read -r initialize
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r request
        # Both slash representations are valid JSON strings.
        case "$request" in
          *'"method":"account/usage/read"'*|*'"method":"account\/usage\/read"'*)
            printf '%s\n' '{"id":2,"error":{"code":-32601,"message":"Method not found"}}' ;;
          *'"method":"account/rateLimits/read"'*|*'"method":"account\/rateLimits\/read"'*)
            printf '%s\n' '{"id":2,"result":{"rateLimits":{"secondary":{"usedPercent":27,"windowDurationMins":10080}}}}' ;;
          *) exit 74 ;;
        esac
        """#)

        do {
            _ = try await fixture.client.fetchUsage(executable: fixture.executable)
            XCTFail("Expected an unsupported usage method")
        } catch {
            XCTAssertEqual(error as? TokenUsageIssue, .unsupported)
        }
        let quota = try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
        XCTAssertEqual(quota.defaultBucket?.window(.weekly)?.remainingPercent, 73)
    }

    func testUsageAuthenticationAndInvalidDataAreDistinct() async throws {
        let responses: [(String, TokenUsageIssue)] = [
            (#"{"id":2,"error":{"code":-32000,"message":"Authentication required"}}"#, .notLoggedIn),
            (#"{"id":2,"result":{"summary":null}}"#, .unavailable),
            (#"{"id":2,"result":{"summary":{"lifetimeTokens":true}}}"#, .invalidData)
        ]
        for (response, expected) in responses {
            let fixture = try makeFixture(script: """
            IFS= read -r initialize
            printf '%s\\n' '{"id":1,"result":{}}'
            IFS= read -r initialized
            IFS= read -r usage
            printf '%s\\n' '\(response)'
            """)
            do {
                _ = try await fixture.client.fetchUsage(executable: fixture.executable)
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? TokenUsageIssue, expected)
            }
        }
    }

    func testUsageRequestTimeoutStopsTheEntireProcessGroup() async throws {
        let fixture = try makeFixture(script: #"""
        IFS= read -r initialize
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r usage
        printf '%s\n' "$$" > "__CODEX94_PID_FILE__"
        sleep 30 &
        printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
        wait
        """#,
            requestTimeout: 0.2,
            totalTimeout: 2,
            quotaRequestTimeout: 3,
            quotaTotalTimeout: 4
        )

        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            _ = try await fixture.client.fetchUsage(executable: fixture.executable)
            XCTFail("Expected a bounded usage timeout")
        } catch {
            XCTAssertEqual(error as? ConnectionIssue, .requestTimedOut)
        }
        XCTAssertLessThan(clock.now - startedAt, .seconds(2), "Usage must not inherit the quota request budget")
        try assertProcessIsGone(at: fixture.pidFile)
        try assertProcessIsGone(at: fixture.descendantPIDFile)
    }

    func testUsageTransactionBudgetDoesNotInheritQuotaBudget() async throws {
        let fixture = try makeFixture(
            script: #"""
            IFS= read -r initialize
            sleep 0.25
            printf '%s\n' '{"id":1,"result":{}}'
            IFS= read -r initialized
            IFS= read -r usage
            printf '%s\n' "$$" > "__CODEX94_PID_FILE__"
            sleep 30 &
            printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
            wait
            """#,
            initializeTimeout: 3,
            requestTimeout: 5,
            totalTimeout: 2,
            quotaRequestTimeout: 6,
            quotaTotalTimeout: 8
        )
        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            _ = try await fixture.client.fetchUsage(executable: fixture.executable)
            XCTFail("Expected the independent usage transaction limit")
        } catch {
            XCTAssertEqual(error as? ConnectionIssue, .requestTimedOut)
        }
        XCTAssertLessThan(clock.now - startedAt, .seconds(3), "Usage total must remain below either request budget")
        try assertProcessIsGone(at: fixture.pidFile)
        try assertProcessIsGone(at: fixture.descendantPIDFile)
    }

    func testUsageResponseUsesExistingOutputSizeLimit() async throws {
        let oversized = String(repeating: "x", count: 2_048)
        let fixture = try makeFixture(
            script: """
            IFS= read -r initialize
            printf '%s\\n' '{"id":1,"result":{}}'
            IFS= read -r initialized
            IFS= read -r usage
            printf '%s\\n' '\(oversized)'
            """,
            maximumLineBytes: 1_024
        )
        do {
            _ = try await fixture.client.fetchUsage(executable: fixture.executable)
            XCTFail("Expected a bounded usage response")
        } catch {
            XCTAssertEqual(error as? ConnectionIssue, .responseTooLarge)
        }
    }

    func testResetCreditsAreReadFromQuotaResponseWithoutAdditionalRequests() async throws {
        for (rawCount, expected) in [("0", Optional(0)), ("3", Optional(3)), ("null", nil)] {
            let fixture = try makeFixture(script: """
            IFS= read -r initialize
            printf '%s\\n' "$initialize" >> "__CODEX94_INVOCATION_FILE__"
            printf '%s\\n' '{"id":1,"result":{"serverInfo":{"name":"fake"}}}'
            IFS= read -r initialized
            printf '%s\\n' "$initialized" >> "__CODEX94_INVOCATION_FILE__"
            IFS= read -r limits
            printf '%s\\n' "$limits" >> "__CODEX94_INVOCATION_FILE__"
            printf '%s\\n' '{"id":2,"result":{"rateLimits":{"secondary":{"usedPercent":27,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":\(rawCount),"credits":[{"id":"private-credit-id"}],"hasMore":true}}}'
            while IFS= read -r extra; do
              printf '%s\\n' "$extra" >> "__CODEX94_INVOCATION_FILE__"
            done
            """)

            let snapshot = try await fixture.client.fetch(
                executable: fixture.executable,
                identityMode: .quotaOnly
            )
            XCTAssertEqual(snapshot.resetCreditsAvailableCount, expected)
            XCTAssertNil(snapshot.account)
            XCTAssertNil(snapshot.accountReadIssue)
            let requests = try String(contentsOf: fixture.invocationFile, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map { line in
                    try XCTUnwrap(
                        JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                    )
                }
            XCTAssertEqual(requests.compactMap { $0["method"] as? String }, [
                "initialize", "initialized", "account/rateLimits/read"
            ])
        }
    }

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

    func testDefaultQuotaBudgetAcceptsResponseAfterFormerFiveSecondDeadline() async throws {
        let defaults = AppServerTimeouts()
        XCTAssertEqual(defaults.quotaRequest, 10)
        XCTAssertEqual(defaults.quotaTotal, 20)
        XCTAssertEqual(defaults.request, 5)
        XCTAssertEqual(defaults.total, 15)
        XCTAssertEqual(defaults.initialize, 8)
        XCTAssertEqual(defaults.optionalAccount, 2)
        let fixture = try makeFixture(
            script: quotaFirstScript(accountScript: "exit 80", quotaDelay: 5.2),
            quotaRequestTimeout: defaults.quotaRequest,
            quotaTotalTimeout: defaults.quotaTotal
        )
        let clock = ContinuousClock()
        let startedAt = clock.now
        let snapshot = try await fixture.client.fetch(
            executable: fixture.executable, identityMode: .quotaOnly
        )
        XCTAssertGreaterThan(clock.now - startedAt, .seconds(5))
        XCTAssertLessThan(clock.now - startedAt, .seconds(12))
        XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.remainingPercent, 73)
        XCTAssertNil(snapshot.account)
        XCTAssertNil(snapshot.accountReadIssue)
        XCTAssertEqual(try recordedRequests(fixture).compactMap { $0["method"] as? String }, [
            "initialize", "initialized", "account/rateLimits/read"
        ])
        try assertProcessIsGone(at: fixture.pidFile)
        try assertProcessIsGone(at: fixture.descendantPIDFile)
    }

    func testQuotaRequestAndWholeTransactionLimitsRemainBounded() async throws {
        let scenarios: [(initializeDelay: TimeInterval, responseDelay: TimeInterval,
                         requestLimit: TimeInterval, totalLimit: TimeInterval)] = [
            (0, 0.6, 0.2, 3),
            // Leave startup headroom, then exceed total well before the request limit.
            (0.25, 3, 5, 2)
        ]
        for scenario in scenarios {
            let fixture = try makeFixture(
                script: quotaFirstScript(
                    accountScript: "exit 80",
                    initializeDelay: scenario.initializeDelay,
                    quotaDelay: scenario.responseDelay
                ),
                initializeTimeout: 3,
                requestTimeout: 3,
                totalTimeout: 4,
                quotaRequestTimeout: scenario.requestLimit,
                quotaTotalTimeout: scenario.totalLimit
            )
            let clock = ContinuousClock()
            let startedAt = clock.now
            await assertIssue(.requestTimedOut) {
                try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaAndAccount)
            }
            XCTAssertLessThan(clock.now - startedAt, .seconds(3))
            XCTAssertEqual(try recordedRequests(fixture).compactMap { $0["method"] as? String }, [
                "initialize", "initialized", "account/rateLimits/read"
            ])
            try assertProcessIsGone(at: fixture.pidFile)
            try assertProcessIsGone(at: fixture.descendantPIDFile)
        }
    }

    func testFetchIgnoresNotificationsAndMismatchedIDs() async throws {
        let fixture = try makeFixture(script: #"""
        IFS= read -r initialize
        printf '%s\n' "$initialize" >> "__CODEX94_INVOCATION_FILE__"
        printf '%s\n' '{"method":"server/notice","params":{"ignored":true}}'
        printf '%s\n' '{"id":999,"result":{"ignored":true}}'
        printf '%s\n' '{"id":1,"result":{"serverInfo":{"name":"fake"}}}'
        IFS= read -r initialized
        printf '%s\n' "$initialized" >> "__CODEX94_INVOCATION_FILE__"
        IFS= read -r limits
        printf '%s\n' "$limits" >> "__CODEX94_INVOCATION_FILE__"
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":null,"secondary":{"usedPercent":27,"windowDurationMins":10080,"resetsAt":2000000000}}}}'
        IFS= read -r account
        printf '%s\n' "$account" >> "__CODEX94_INVOCATION_FILE__"
        printf '%s\n' "$$" > "__CODEX94_PID_FILE__"
        sleep 30 &
        printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
        sleep 0.2
        printf 'responding\n' > "__CODEX94_HEARTBEAT_FILE__"
        printf '%s\n' '{"method":"account/notice","params":{"ignored":true}}'
        printf '%s\n' '{"id":2,"result":{"ignored":true}}'
        printf '%s\n' '{"id":3,"result":{"account":{"type":"chatgpt","email":"test@example.com","planType":"pro"},"requiresOpenaiAuth":true}}'
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
        XCTAssertNil(snapshot.accountReadIssue)
        let requests = try recordedRequests(fixture)
        XCTAssertEqual(requests.compactMap { $0["method"] as? String }, [
            "initialize", "initialized", "account/rateLimits/read", "account/read"
        ])
        XCTAssertEqual(requests.compactMap { $0["id"] as? Int }, [1, 2, 3])
        XCTAssertEqual((requests.last?["params"] as? [String: Bool])?["refreshToken"], false)
        let responseMarker = try FileManager.default.attributesOfItem(
            atPath: fixture.heartbeatFile.path
        )
        let accountResponseTime = try XCTUnwrap(responseMarker[.modificationDate] as? Date)
        XCTAssertGreaterThan(accountResponseTime.timeIntervalSince(snapshot.fetchedAt), 0.1,
                             "Quota must retain its timestamp from before the optional account wait")

        try assertProcessIsGone(at: fixture.pidFile)
        try assertProcessIsGone(at: fixture.descendantPIDFile)
    }

    func testSlowAndUnresponsiveAccountReadsKeepFreshQuotaAndStopTheirProcesses() async throws {
        let accountScripts = [
            #"""
            sleep 1 &
            printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
            wait
            printf '%s\n' '{"id":3,"result":{"account":{"type":"chatgpt","email":"late@example.com"}}}'
            """#,
            #"""
            sleep 30 &
            printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
            wait
            """#
        ]
        for script in accountScripts {
            let fixture = try makeFixture(
                script: quotaFirstScript(accountScript: script),
                optionalAccountTimeout: 0.15
            )
            let snapshot = try await fixture.client.fetch(
                executable: fixture.executable, identityMode: .quotaAndAccount
            )
            XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.remainingPercent, 73)
            XCTAssertEqual(snapshot.resetCreditsAvailableCount, 3)
            XCTAssertNil(snapshot.account)
            XCTAssertEqual(snapshot.accountReadIssue, .requestTimedOut)
            XCTAssertEqual(try recordedRequests(fixture).compactMap { $0["method"] as? String }, [
                "initialize", "initialized", "account/rateLimits/read", "account/read"
            ])
            try assertProcessIsGone(at: fixture.pidFile)
            try assertProcessIsGone(at: fixture.descendantPIDFile)
        }
    }

    func testOptionalAccountTransportAndMalformedResponsesDoNotDiscardQuota() async throws {
        let responses: [(String, ConnectionIssue)] = [
            ("exit 0", .serverExited),
            (#"printf '%s\n' 'not-json'"#, .malformedResponse),
            (#"printf '%s\n' '{"id":3,"result":null}'"#, .missingResult),
            (#"printf '%s\n' '{"id":3,"error":{"code":-32000,"message":"failed"}}'"#, .serverError),
            ("printf '%s\\n' '" + String(repeating: "x", count: 2_048) + "'", .responseTooLarge)
        ]
        for (script, expected) in responses {
            let fixture = try makeFixture(
                script: quotaFirstScript(accountScript: script), maximumLineBytes: 1_024
            )
            let snapshot = try await fixture.client.fetch(
                executable: fixture.executable, identityMode: .quotaAndAccount
            )
            XCTAssertEqual(snapshot.defaultBucket?.window(.weekly)?.remainingPercent, 73)
            XCTAssertEqual(snapshot.accountReadIssue, expected)
            XCTAssertNil(snapshot.account)
            try assertProcessIsGone(at: fixture.pidFile)
        }
    }

    func testExplicitAccountAuthenticationFailuresStillFailTheFetch() async throws {
        let responses = [
            #"{"id":3,"result":{"requiresOpenaiAuth":true,"account":null}}"#,
            #"{"id":3,"error":{"code":-32000,"message":"Authentication required"}}"#
        ]
        for response in responses {
            let fixture = try makeFixture(script: quotaFirstScript(
                accountScript: "printf '%s\\n' '\(response)'"
            ))
            await assertIssue(.notLoggedIn) {
                try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaAndAccount)
            }
            XCTAssertEqual(try recordedRequests(fixture).last?["method"] as? String, "account/read")
            try assertProcessIsGone(at: fixture.pidFile)
        }
    }

    func testQuotaFailuresDoNotAttemptOptionalAccountRead() async throws {
        let responses: [(String, ConnectionIssue)] = [
            (#"{"id":2,"error":{"code":-32000,"message":"failed"}}"#, .serverError),
            (#"{"id":2,"error":{"code":-32000,"message":"Not logged in"}}"#, .notLoggedIn),
            (#"{"id":2,"result":{}}"#, .quotaUnavailable),
            (#"{"id":2,"result":null}"#, .missingResult),
            ("not-json", .malformedResponse),
            ("", .requestTimedOut)
        ]
        for (response, expected) in responses {
            let fixture = try makeFixture(script: quotaFirstScript(
                accountScript: "exit 80", limitsResponse: response
            ))
            await assertIssue(expected) {
                try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaAndAccount)
            }
            XCTAssertEqual(try recordedRequests(fixture).compactMap { $0["method"] as? String }, [
                "initialize", "initialized", "account/rateLimits/read"
            ])
            try assertProcessIsGone(at: fixture.pidFile)
        }
    }

    func testOptionalAccountReadStillRespectsTheTotalBudget() async throws {
        let fixture = try makeFixture(
            script: quotaFirstScript(accountScript: #"""
            sleep 30 &
            printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
            wait
            """#),
            quotaTotalTimeout: 0.75,
            optionalAccountTimeout: 10
        )
        let clock = ContinuousClock()
        let start = clock.now
        let snapshot = try await fixture.client.fetch(
            executable: fixture.executable, identityMode: .quotaAndAccount
        )
        XCTAssertEqual(snapshot.accountReadIssue, .requestTimedOut)
        XCTAssertLessThan(clock.now - start, .seconds(2), "Optional metadata cannot extend the total budget")
        try assertProcessIsGone(at: fixture.pidFile)
        try assertProcessIsGone(at: fixture.descendantPIDFile)
    }

    func testOptionalAccountBudgetDoesNotShortenUsageRequests() async throws {
        let fixture = try makeFixture(
            script: #"""
            IFS= read -r initialize
            printf '%s\n' '{"id":1,"result":{}}'
            IFS= read -r initialized
            IFS= read -r usage
            printf '%s\n' "$usage" > "__CODEX94_INVOCATION_FILE__"
            sleep 0.2
            printf '%s\n' '{"id":2,"result":{"summary":{"lifetimeTokens":123}}}'
            """#,
            optionalAccountTimeout: 0.05
        )
        let snapshot = try await fixture.client.fetchUsage(executable: fixture.executable)
        XCTAssertEqual(snapshot.summary.lifetimeTokens, 123)
        XCTAssertEqual(try recordedRequests(fixture).compactMap { $0["method"] as? String }, [
            "account/usage/read"
        ])
    }

    func testShutdownDuringOptionalAccountDoesNotReturnPartialSuccess() async throws {
        let fixture = try makeFixture(
            script: quotaFirstScript(accountScript: #"""
            sleep 30 &
            printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
            wait
            """#),
            optionalAccountTimeout: 2
        )
        let fetch = Task {
            try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaAndAccount)
        }
        _ = try await waitForPID(at: fixture.descendantPIDFile)
        fixture.client.shutdown()
        await assertIssue(.serverExited) { try await fetch.value }
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
            initializeTimeout: 1,
            quotaTotalTimeout: 2
        )
        await assertIssue(.initializationTimedOut) {
            try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
        }
        try assertProcessIsGone(at: fixture.pidFile)
        try assertProcessIsGone(at: fixture.descendantPIDFile)
    }

    func testShutdownTerminatesActiveProcessGroupAndRejectsFutureFetch() async throws {
        let fixture = try makeFixture(
            script: #"""
            printf 'launch\n' >> "__CODEX94_INVOCATION_FILE__"
            trap '' TERM
            printf '%s\n' "$$" > "__CODEX94_PID_FILE__"
            (
              trap '' TERM
              heartbeat=0
              while :; do
                heartbeat=$((heartbeat + 1))
                if [ "$heartbeat" -ge 5000 ]; then
                  printf 'heartbeat\n' >> "__CODEX94_HEARTBEAT_FILE__"
                  heartbeat=0
                fi
              done
            ) &
            printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
            wait
            """#,
            initializeTimeout: 3,
            quotaTotalTimeout: 3
        )

        let fetchTask = Task {
            try await fixture.client.fetch(
                executable: fixture.executable,
                identityMode: .quotaOnly
            )
        }
        let parentPID = try await waitForPID(at: fixture.pidFile)
        let descendantPID = try await waitForPID(at: fixture.descendantPIDFile)
        defer {
            _ = kill(-parentPID, SIGKILL)
            _ = kill(parentPID, SIGKILL)
            _ = kill(descendantPID, SIGKILL)
        }
        try await waitForFile(at: fixture.heartbeatFile)

        let startedAt = Date()
        fixture.client.shutdown()
        fixture.client.shutdown()
        let shutdownDuration = Date().timeIntervalSince(startedAt)

        switch await fetchTask.result {
        case .success:
            XCTFail("An interrupted fetch must not produce a snapshot")
        case .failure:
            break
        }
        let completionDuration = Date().timeIntervalSince(startedAt)
        XCTAssertLessThan(shutdownDuration, 1.0)
        XCTAssertLessThan(completionDuration, 1.5)
        assertProcessIsGone(parentPID)
        assertProcessIsGone(descendantPID)
        assertProcessGroupIsGone(parentPID)

        let heartbeatSize = try fileSize(at: fixture.heartbeatFile)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(try fileSize(at: fixture.heartbeatFile), heartbeatSize)

        await assertIssue(.serverExited) {
            try await fixture.client.fetch(
                executable: fixture.executable,
                identityMode: .quotaOnly
            )
        }
        let launches = try String(contentsOf: fixture.invocationFile, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(launches.count, 1)
    }

    func testShutdownWaitsForProcessGroupAfterParentExitsOnTerm() async throws {
        let fixture = try makeFixture(
            script: #"""
            printf 'launch\n' >> "__CODEX94_INVOCATION_FILE__"
            printf '%s\n' "$$" > "__CODEX94_PID_FILE__"
            (
              trap '' TERM
              heartbeat=0
              while :; do
                heartbeat=$((heartbeat + 1))
                if [ "$heartbeat" -ge 5000 ]; then
                  printf 'heartbeat\n' >> "__CODEX94_HEARTBEAT_FILE__"
                  heartbeat=0
                fi
              done
            ) &
            printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
            exec /bin/sleep 30
            """#,
            initializeTimeout: 3,
            quotaTotalTimeout: 3
        )

        let fetchTask = Task {
            try await fixture.client.fetch(
                executable: fixture.executable,
                identityMode: .quotaOnly
            )
        }
        let parentPID = try await waitForPID(at: fixture.pidFile)
        let descendantPID = try await waitForPID(at: fixture.descendantPIDFile)
        defer {
            _ = kill(-parentPID, SIGKILL)
            _ = kill(parentPID, SIGKILL)
            _ = kill(descendantPID, SIGKILL)
        }
        try await waitForFile(at: fixture.heartbeatFile)

        let clock = ContinuousClock()
        let startedAt = clock.now
        fixture.client.shutdown()
        let shutdownDuration = clock.now - startedAt

        switch await fetchTask.result {
        case .success:
            XCTFail("An interrupted fetch must not produce a snapshot")
        case .failure:
            break
        }
        XCTAssertLessThan(shutdownDuration, .seconds(1.5))
        assertProcessIsGone(parentPID)
        assertProcessIsGone(descendantPID)
        assertProcessGroupIsGone(parentPID)
    }

    func testEarlyExitIsClassified() async throws {
        let fixture = try makeFixture(script: "exit 0\n")
        await assertIssue(.serverExited) {
            try await fixture.client.fetch(executable: fixture.executable, identityMode: .quotaOnly)
        }
    }

    private func assertIssue<Value: Sendable>(
        _ expected: ConnectionIssue,
        operation: () async throws -> Value
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
        let invocationFile: URL
        let heartbeatFile: URL
    }

    private func recordedRequests(_ fixture: Fixture) throws -> [[String: Any]] {
        try String(contentsOf: fixture.invocationFile, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    }

    private func quotaFirstScript(
        accountScript: String,
        limitsResponse: String = #"{"id":2,"result":{"rateLimits":{"secondary":{"usedPercent":27,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":3}}}"#,
        initializeDelay: TimeInterval = 0,
        quotaDelay: TimeInterval = 0
    ) -> String {
        let waitForInitialize = initializeDelay > 0 ? "sleep \(initializeDelay)" : ""
        let waitForQuota = quotaDelay > 0 ? #"""
        sleep \#(quotaDelay) &
        printf '%s\n' "$!" > "__CODEX94_DESCENDANT_PID_FILE__"
        wait
        """# : ""
        return #"""
        IFS= read -r initialize
        printf '%s\n' "$initialize" >> "__CODEX94_INVOCATION_FILE__"
        \#(waitForInitialize)
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        printf '%s\n' "$initialized" >> "__CODEX94_INVOCATION_FILE__"
        IFS= read -r limits
        printf '%s\n' "$limits" >> "__CODEX94_INVOCATION_FILE__"
        case "$limits" in
          *'"method":"account/rateLimits/read"'*|*'"method":"account\/rateLimits\/read"'*) ;;
          *) exit 74 ;;
        esac
        printf '%s\n' "$$" > "__CODEX94_PID_FILE__"
        \#(waitForQuota)
        printf '%s\n' '\#(limitsResponse)'
        if IFS= read -r account; then
          printf '%s\n' "$account" >> "__CODEX94_INVOCATION_FILE__"
          case "$account" in
            *'"method":"account/read"'*|*'"method":"account\/read"'*) ;;
            *) exit 75 ;;
          esac
          \#(accountScript)
        fi
        """#
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

    private func waitForFile(at fileURL: URL) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: fileURL.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func fileSize(at fileURL: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return try XCTUnwrap(attributes[.size] as? NSNumber).uint64Value
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

    private func makeFixture(
        script: String,
        maximumLineBytes: Int = 1_048_576,
        initializeTimeout: TimeInterval = 1,
        requestTimeout: TimeInterval = 1,
        totalTimeout: TimeInterval = 3,
        quotaRequestTimeout: TimeInterval = 1,
        quotaTotalTimeout: TimeInterval = 3,
        optionalAccountTimeout: TimeInterval = 1,
        clientVersion: String = "test",
        workerQueue: DispatchQueue? = nil,
        requestEnqueued: (@Sendable () -> Void)? = nil
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94ServerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("codex")
        let pidFile = directory.appendingPathComponent("pid")
        let descendantPIDFile = directory.appendingPathComponent("descendant-pid")
        let invocationFile = directory.appendingPathComponent("invocations")
        let heartbeatFile = directory.appendingPathComponent("heartbeats")
        let resolvedScript = script
            .replacingOccurrences(of: "__CODEX94_PID_FILE__", with: pidFile.path)
            .replacingOccurrences(
                of: "__CODEX94_DESCENDANT_PID_FILE__",
                with: descendantPIDFile.path
            )
            .replacingOccurrences(
                of: "__CODEX94_INVOCATION_FILE__",
                with: invocationFile.path
            )
            .replacingOccurrences(
                of: "__CODEX94_HEARTBEAT_FILE__",
                with: heartbeatFile.path
            )
        try ("#!/bin/sh\n" + resolvedScript).write(
            to: executableURL,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(chmod(executableURL.path, 0o700), 0)

        let timeouts = AppServerTimeouts(
            initialize: initializeTimeout,
            request: requestTimeout,
            total: totalTimeout,
            quotaRequest: quotaRequestTimeout,
            quotaTotal: quotaTotalTimeout,
            optionalAccount: optionalAccountTimeout,
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
            clientVersion: clientVersion,
            workerQueue: workerQueue,
            requestEnqueued: requestEnqueued
        )
        addTeardownBlock { client.shutdown() }
        let executable = LocatedCodex(
            executableURL: executableURL,
            version: "codex-cli test",
            source: .manual
        )
        return Fixture(
            client: client,
            executable: executable,
            pidFile: pidFile,
            descendantPIDFile: descendantPIDFile,
            invocationFile: invocationFile,
            heartbeatFile: heartbeatFile
        )
    }
}

private final class AppServerQueueGate: @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var blocked = false
    private var enqueued = 0
    private var timedOut = false

    var isBlocked: Bool { lock.withLock { blocked } }
    var enqueuedCount: Int { lock.withLock { enqueued } }
    var didTimeOut: Bool { lock.withLock { timedOut } }

    func recordEnqueue() { lock.withLock { enqueued += 1 } }

    func blockWorker() {
        lock.withLock { blocked = true }
        let result = release.wait(timeout: .now() + 10)
        lock.withLock {
            timedOut = result == .timedOut
            blocked = false
        }
    }

    func releaseWorker() { release.signal() }
}
