import Darwin
import Foundation
import OSLog

protocol QuotaFetching: Sendable {
    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot
}

struct AppServerTimeouts: Sendable {
    var initialize: TimeInterval = 8
    var request: TimeInterval = 5
    var total: TimeInterval = 15
    var terminationGrace: TimeInterval = 1
    var maximumLineBytes: Int = 1_048_576
}

final class CodexAppServerClient: QuotaFetching, @unchecked Sendable {
    private let runtimeDirectory: URL
    private let timeouts: AppServerTimeouts
    private let environment: [String: String]
    private let workerQueue = DispatchQueue(label: "com.defyan94.codex94.app-server")
    private let logger = Logger(subsystem: "com.defyan94.codex94", category: "rpc")

    init(
        runtimeDirectory: URL? = nil,
        timeouts: AppServerTimeouts = AppServerTimeouts(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.runtimeDirectory = runtimeDirectory
            ?? base.appendingPathComponent("Codex94/Runtime", isDirectory: true)
        self.timeouts = timeouts
        self.environment = environment
    }

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            workerQueue.async { [self] in
                do {
                    continuation.resume(returning: try fetchSynchronously(
                        executable: executable,
                        identityMode: identityMode
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func fetchSynchronously(
        executable: LocatedCodex,
        identityMode: IdentityMode
    ) throws -> QuotaSnapshot {
        try FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable.executableURL
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server", "--stdio"]
        process.currentDirectoryURL = runtimeDirectory
        process.environment = CodexExecutableLocator.sanitizedEnvironment(from: environment)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let startedAt = Date()
        let totalDeadline = startedAt.addingTimeInterval(timeouts.total)
        logger.info("stage=start source=\(executable.source.rawValue, privacy: .public)")

        do {
            try process.run()
        } catch {
            logger.error("stage=launch result=failed")
            throw ConnectionIssue.processLaunchFailed
        }

        let channel = JSONLineChannel(
            descriptor: output.fileHandleForReading.fileDescriptor,
            maximumLineBytes: timeouts.maximumLineBytes
        )

        defer {
            try? input.fileHandleForWriting.close()
            stop(process)
            let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            logger.info(
                "stage=finish duration_ms=\(milliseconds, privacy: .public) bytes=\(channel.bytesRead, privacy: .public)"
            )
        }

        let initializeID = 1
        try write([
            "id": initializeID,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codex94",
                    "title": "Codex94",
                    "version": "0.1.0"
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ]
        ], to: input.fileHandleForWriting)

        _ = try response(
            id: initializeID,
            channel: channel,
            process: process,
            deadline: requestDeadline(seconds: timeouts.initialize, totalDeadline: totalDeadline),
            timeoutIssue: totalDeadline.timeIntervalSinceNow <= timeouts.initialize
                ? .totalTimedOut
                : .initializationTimedOut
        )

        try write(["method": "initialized"], to: input.fileHandleForWriting)

        var nextID = 2
        var accountResult: [String: Any]?
        if identityMode == .quotaAndAccount {
            try write([
                "id": nextID,
                "method": "account/read",
                "params": ["refreshToken": false]
            ], to: input.fileHandleForWriting)
            accountResult = try response(
                id: nextID,
                channel: channel,
                process: process,
                deadline: requestDeadline(seconds: timeouts.request, totalDeadline: totalDeadline),
                timeoutIssue: .requestTimedOut
            )
            if accountResult?["requiresOpenaiAuth"] as? Bool == true,
               accountResult?["account"] is NSNull {
                throw ConnectionIssue.notLoggedIn
            }
            nextID += 1
        }

        try write([
            "id": nextID,
            "method": "account/rateLimits/read"
        ], to: input.fileHandleForWriting)
        let limitsResult = try response(
            id: nextID,
            channel: channel,
            process: process,
            deadline: requestDeadline(seconds: timeouts.request, totalDeadline: totalDeadline),
            timeoutIssue: .requestTimedOut
        )

        return try RateLimitsParser.parse(
            limitsResult: limitsResult,
            accountResult: accountResult,
            executable: executable,
            fetchedAt: Date()
        )
    }

    private func write(_ object: [String: Any], to handle: FileHandle) throws {
        do {
            var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            data.append(0x0A)
            try handle.write(contentsOf: data)
        } catch {
            throw ConnectionIssue.serverExited
        }
    }

    private func response(
        id: Int,
        channel: JSONLineChannel,
        process: Process,
        deadline: Date,
        timeoutIssue: ConnectionIssue
    ) throws -> [String: Any] {
        while true {
            let object = try channel.readObject(deadline: deadline, timeoutIssue: timeoutIssue)
            guard let dictionary = object as? [String: Any] else {
                throw ConnectionIssue.malformedResponse
            }

            guard let responseID = Self.integer(dictionary["id"]) else {
                continue
            }
            guard responseID == id else {
                continue
            }
            if let error = dictionary["error"] as? [String: Any] {
                let message = (error["message"] as? String)?.lowercased() ?? ""
                if message.contains("not logged in")
                    || message.contains("authentication required")
                    || message.contains("login required") {
                    throw ConnectionIssue.notLoggedIn
                }
                throw ConnectionIssue.serverError
            }
            guard dictionary.keys.contains("result") else {
                throw ConnectionIssue.missingResult
            }
            guard let result = dictionary["result"] as? [String: Any] else {
                throw ConnectionIssue.missingResult
            }
            return result
        }
    }

    private func requestDeadline(seconds: TimeInterval, totalDeadline: Date) -> Date {
        min(Date().addingTimeInterval(seconds), totalDeadline)
    }

    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()

        let deadline = Date().addingTimeInterval(timeouts.terminationGrace)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

private final class JSONLineChannel {
    let descriptor: Int32
    let maximumLineBytes: Int
    private var buffer = Data()
    private(set) var bytesRead = 0

    init(descriptor: Int32, maximumLineBytes: Int) {
        self.descriptor = descriptor
        self.maximumLineBytes = maximumLineBytes
    }

    func readObject(deadline: Date, timeoutIssue: ConnectionIssue) throws -> Any {
        let line = try readLine(deadline: deadline, timeoutIssue: timeoutIssue)
        do {
            return try JSONSerialization.jsonObject(with: line)
        } catch {
            throw ConnectionIssue.malformedResponse
        }
    }

    private func readLine(deadline: Date, timeoutIssue: ConnectionIssue) throws -> Data {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                var line = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                if line.last == 0x0D { line = line.dropLast() }
                guard !line.isEmpty else { continue }
                return Data(line)
            }

            guard buffer.count <= maximumLineBytes else {
                throw ConnectionIssue.responseTooLarge
            }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw timeoutIssue }

            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let timeoutMilliseconds = Int32(min(Double(Int32.max), ceil(remaining * 1_000)))
            let pollResult = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)

            if pollResult == 0 { throw timeoutIssue }
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw ConnectionIssue.serverExited
            }

            var bytes = [UInt8](repeating: 0, count: 8_192)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count == 0 { throw ConnectionIssue.serverExited }
            if count < 0 {
                if errno == EINTR { continue }
                throw ConnectionIssue.serverExited
            }

            buffer.append(contentsOf: bytes.prefix(Int(count)))
            bytesRead += Int(count)
            guard buffer.count <= maximumLineBytes else {
                throw ConnectionIssue.responseTooLarge
            }
        }
    }
}

enum RateLimitsParser {
    static func parse(
        limitsResult: [String: Any],
        accountResult: [String: Any]?,
        executable: LocatedCodex,
        fetchedAt: Date
    ) throws -> QuotaSnapshot {
        let defaultLimits = limitsResult["rateLimits"] as? [String: Any]
        let limitsByID = limitsResult["rateLimitsByLimitId"] as? [String: Any]
        let codexLimits = limitsByID?["codex"] as? [String: Any]

        let selectedLimits: [String: Any]
        if let defaultLimits, !classifiedWindows(in: defaultLimits).isEmpty {
            selectedLimits = defaultLimits
        } else if let codexLimits {
            selectedLimits = codexLimits
        } else {
            throw ConnectionIssue.quotaUnavailable
        }

        let windows = classifiedWindows(in: selectedLimits)
        guard !windows.isEmpty else { throw ConnectionIssue.quotaUnavailable }

        let account = parseAccount(accountResult)
        let planType = selectedLimits["planType"] as? String ?? account?.planType
        return QuotaSnapshot(
            windows: windows.sorted { $0.kind.rawValue < $1.kind.rawValue },
            planType: planType,
            fetchedAt: fetchedAt,
            account: account,
            codex: executable
        )
    }

    static func classifiedWindows(in limits: [String: Any]) -> [QuotaWindowSnapshot] {
        let candidates = [limits["primary"], limits["secondary"]]
        var windowsByKind: [QuotaWindowKind: QuotaWindowSnapshot] = [:]

        for case let rawWindow as [String: Any] in candidates {
            guard let windowMinutes = integer(rawWindow["windowDurationMins"]),
                  let kind = kind(for: windowMinutes),
                  let usedPercent = integer(rawWindow["usedPercent"]) else {
                continue
            }

            let resetsAt = integer(rawWindow["resetsAt"]).map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
            windowsByKind[kind] = QuotaWindowSnapshot(
                kind: kind,
                usedPercent: usedPercent,
                windowMinutes: windowMinutes,
                resetsAt: resetsAt
            )
        }
        return Array(windowsByKind.values)
    }

    static func kind(for windowMinutes: Int) -> QuotaWindowKind? {
        switch windowMinutes {
        case 240...360: .fiveHour
        case 9_000...11_000: .weekly
        default: nil
        }
    }

    private static func parseAccount(_ result: [String: Any]?) -> AccountSummary? {
        guard let result,
              let account = result["account"] as? [String: Any],
              let type = account["type"] as? String else {
            return nil
        }
        return AccountSummary(
            type: type,
            email: account["email"] as? String,
            planType: account["planType"] as? String
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
