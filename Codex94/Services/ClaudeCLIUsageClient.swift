import Darwin
import Foundation

/// A short-lived official CLI session. It only submits the built-in /usage command.
final class ClaudeCLIUsageClient: ClaudeQuotaFetching, @unchecked Sendable {
    private let executableURL: URL?
    private let runtimeDirectory: URL
    private let environment: [String: String]
    private let locator: ClaudeExecutableLocator
    private let timeout: TimeInterval
    private let lifecycle = ManagedSubprocessLifecycle()
    private let queue = DispatchQueue(label: "com.defyan94.codex94.claude-usage", qos: .utility)
    private let cancellationQueue = DispatchQueue(label: "com.defyan94.codex94.claude-cancellation", qos: .utility)

    init(executableURL: URL? = nil, runtimeDirectory: URL? = nil,
         environment: [String: String] = ProcessInfo.processInfo.environment, timeout: TimeInterval = 20,
         locator: ClaudeExecutableLocator? = nil) {
        self.executableURL = executableURL
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.runtimeDirectory = runtimeDirectory ?? support.appendingPathComponent("Codex94/Claude/UsageProbe")
        self.environment = environment
        self.locator = locator ?? ClaudeExecutableLocator(environment: environment)
        self.timeout = max(1, min(timeout, 60))
    }

    func fetch() async throws -> ClaudeQuotaReport {
        try Task.checkCancellation()
        do {
            let report = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    queue.async { [self] in
                        do { continuation.resume(returning: try fetchSynchronously()) }
                        catch { continuation.resume(throwing: error) }
                    }
                }
            } onCancel: { self.cancellationQueue.async { self.shutdown() } }
            try Task.checkCancellation()
            return report
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    func shutdown() { lifecycle.shutdown(gracePeriod: 0.3) }

    private func fetchSynchronously() throws -> ClaudeQuotaReport {
        let executable = try locator.locate(manualURL: executableURL)
        try validateVersion(of: executable)
        try ClaudeLocalFile.createPrivateDirectory(runtimeDirectory)
        let marker = runtimeDirectory.appendingPathComponent(".codex94-usage-probe")
        let contents = try FileManager.default.contentsOfDirectory(atPath: runtimeDirectory.path)
        guard contents.allSatisfy({ $0 == marker.lastPathComponent }) else { throw ClaudeQuotaIssue.setupRequired }
        if !FileManager.default.fileExists(atPath: marker.path) { try ClaudeLocalFile.write(Data("1\n".utf8), to: marker) }

        var master: Int32 = -1
        var slave: Int32 = -1
        var size = winsize(ws_row: 50, ws_col: 180, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw ClaudeQuotaIssue.unavailable }
        let primary = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let secondary = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        let childEnvironment = probeEnvironment
        let process: ManagedSubprocess
        do {
            process = try lifecycle.launch {
                try ManagedSubprocess.launch(
                    executableURL: executable,
                    arguments: ["--setting-sources", "", "--settings", #"{"disableAllHooks":true,"remoteControlAtStartup":false}"#,
                                "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
                                "--tools", "", "--permission-mode", "plan", "--no-chrome"],
                    currentDirectoryURL: runtimeDirectory, environment: childEnvironment,
                    standardInputHandle: secondary, standardOutputHandle: secondary, standardErrorHandle: secondary
                )
            }
        } catch { throw ClaudeQuotaIssue.unavailable }
        try? secondary.close()
        defer {
            lifecycle.stopIfActive(process, gracePeriod: 0.3)
            try? primary.close()
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        var output = Data()
        var terminalQueries = ClaudeTerminalQueries()
        var sentUsage = false
        var confirmedUsageAction = false
        var trustSteps = 0
        var lastTrustInput: String?
        var lastOutput = clock.now
        var candidateWindows: [ClaudeQuotaWindow]?
        var candidateSince: ContinuousClock.Instant?
        while clock.now < deadline {
            if lifecycle.hasShutDown { throw CancellationError() }
            var descriptor = pollfd(fd: master, events: Int16(POLLIN | POLLHUP), revents: 0)
            let result = poll(&descriptor, 1, 100)
            if result < 0 {
                if errno == EINTR { continue }
                throw ClaudeQuotaIssue.unavailable
            }
            if result > 0 {
                var bytes = [UInt8](repeating: 0, count: 8_192)
                let count = Darwin.read(master, &bytes, bytes.count)
                guard count > 0 else { throw ClaudeQuotaIssue.unavailable }
                let data = Data(bytes.prefix(count))
                output.append(data)
                guard output.count <= 1_048_576 else { throw ClaudeQuotaIssue.invalidData }
                for reply in terminalQueries.responses(to: data) { try primary.write(contentsOf: reply) }
                lastOutput = clock.now
            }
            guard clock.now - lastOutput >= .milliseconds(200) else { continue }
            let screen = ClaudeUsageScreen.text(from: output)
            let normalized = screen.lowercased().filter { !$0.isWhitespace }
            if normalized.contains("selecttheme") || normalized.contains("textstyle")
                || (normalized.contains("let’sgetstarted") && normalized.contains("darkmode")) {
                throw ClaudeQuotaIssue.setupRequired
            }
            if normalized.contains("notloggedin") || normalized.contains("selectloginmethod")
                || normalized.contains("logintoclaude") || normalized.contains("choosehowtologin") {
                throw ClaudeQuotaIssue.loginRequired
            }
            if normalized.contains("quicksafetycheck") || normalized.contains("trustthisfolder")
                || normalized.contains("doyoutrustthefiles") {
                let key = try trustInput(on: screen)
                // Wait for a changed selection, not merely more terminal bytes,
                // before sending another key to the same trust dialog.
                guard key != lastTrustInput else { continue }
                guard trustSteps < 3 else { throw ClaudeQuotaIssue.setupRequired }
                lastTrustInput = key
                try primary.write(contentsOf: Data(key.utf8)); trustSteps += 1; lastOutput = clock.now; continue
            }
            if !sentUsage, normalized.contains("?forshortcuts") {
                try primary.write(contentsOf: Data("/usage\r".utf8))
                sentUsage = true; output.removeAll(keepingCapacity: true); lastOutput = clock.now; continue
            }
            if sentUsage {
                if let report = try? ClaudeUsageScreen.report(from: screen, at: Date()) {
                    if candidateWindows != report.windows {
                        candidateWindows = report.windows
                        candidateSince = clock.now
                    }
                    // Ink may paint session and weekly rows in separate frames.
                    // Settle the recognized values rather than requiring two
                    // windows: a legitimate single-window panel also completes.
                    // This never moves the transaction's original deadline.
                    if let candidateSince, clock.now - candidateSince >= .seconds(1) {
                        if lifecycle.hasShutDown { throw CancellationError() }
                        return report
                    }
                } else {
                    candidateWindows = nil
                    candidateSince = nil
                }
                if !confirmedUsageAction, normalized.contains("showplan") {
                    try primary.write(contentsOf: Data("\r".utf8))
                    confirmedUsageAction = true; lastOutput = clock.now
                }
            }
            if process.pollForExit() { throw ClaudeQuotaIssue.unavailable }
        }
        throw ClaudeQuotaIssue.timedOut
    }

    private func trustInput(on screen: String) throws -> String {
        let lines = screen.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "│")))
        }
        var paths = Set([runtimeDirectory.path])
        // These are only the root-owned aliases already checked when creating
        // the private runtime. No arbitrary path prefix or descendant qualifies.
        for prefix in ["/var/", "/tmp/"] where runtimeDirectory.path.hasPrefix(prefix) {
            paths.insert("/private" + runtimeDirectory.path)
        }
        for prefix in ["/private/var/", "/private/tmp/"] where runtimeDirectory.path.hasPrefix(prefix) {
            paths.insert(String(runtimeDirectory.path.dropFirst("/private".count)))
        }
        guard lines.contains(where: paths.contains) else { throw ClaudeQuotaIssue.setupRequired }
        var yesRows: [Int] = []
        var selectedRows: [Int] = []
        for (index, line) in lines.enumerated() {
            var option = line
            let selected = option.hasPrefix("❯") || option.hasPrefix(">")
            if selected { option.removeFirst() }
            option = option.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"^[0-9]+[.)]\s*"#, with: "", options: .regularExpression)
            let label = option.lowercased().filter { !$0.isWhitespace }
            guard label == "yes,itrustthisfolder" || label == "no,exit" else { continue }
            if label == "yes,itrustthisfolder" { yesRows.append(index) }
            if selected { selectedRows.append(index) }
        }
        guard yesRows.count == 1, selectedRows.count == 1,
              let yes = yesRows.first, let selected = selectedRows.first else { throw ClaudeQuotaIssue.setupRequired }
        if selected == yes { return "\r" }
        return selected < yes ? "\u{1b}[B" : "\u{1b}[A"
    }

    private func validateVersion(of executable: URL) throws {
        let pipe = Pipe()
        let process: ManagedSubprocess
        do {
            process = try lifecycle.launch {
                try ManagedSubprocess.launch(executableURL: executable, arguments: ["--version"],
                    environment: probeEnvironment, standardOutput: pipe)
            }
        } catch { throw ClaudeQuotaIssue.cliUnavailable }
        defer { lifecycle.stopIfActive(process, gracePeriod: 0.2) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        var data = Data()
        while clock.now < deadline {
            if lifecycle.hasShutDown { throw CancellationError() }
            var descriptor = pollfd(fd: pipe.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0, errno == EINTR { continue }
            guard ready >= 0 else { throw ClaudeQuotaIssue.cliUnavailable }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 1_025)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            if count == 0 { break }
            guard count > 0, data.count + count <= 1_024 else { throw ClaudeQuotaIssue.cliUnavailable }
            data.append(contentsOf: bytes.prefix(count))
        }
        let version = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        while !process.pollForExit(), clock.now < deadline { usleep(10_000) }
        guard process.pollForExit(), process.terminationStatus == 0,
              version.range(of: #"^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.]+)? \(Claude Code\)$"#, options: .regularExpression) != nil else {
            throw ClaudeQuotaIssue.cliUnavailable
        }
    }

    private var probeEnvironment: [String: String] {
        var child = CodexExecutableLocator.sanitizedEnvironment(from: environment)
        child["TERM"] = "xterm-256color"
        child["LANG"] = "en_US.UTF-8"
        child["LC_ALL"] = "en_US.UTF-8"
        // Native Claude's own credential lookup needs USER even when a
        // LaunchServices-launched app has no USER in its inherited environment.
        // Resolve it through the OS rather than trusting an injected value.
        let currentUser = NSUserName()
        if !currentUser.isEmpty { child["USER"] = currentUser }
        child["DISABLE_AUTOUPDATER"] = "1"
        // Ask the official CLI not to persist probe history. Older CLI builds
        // may not honor this variable; this is not a zero-artifact guarantee.
        child["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] = "1"
        return child
    }
}

struct ClaudeTerminalQueries {
    private var tail = Data()
    private var byteCount = 0
    private var lastReplyPosition: [String: Int] = [:]

    mutating func responses(to chunk: Data) -> [Data] {
        let start = byteCount - tail.count
        byteCount += chunk.count
        tail.append(chunk)
        var replies: [Data] = []
        for (query, reply) in [("\u{1b}[6n", "\u{1b}[1;1R"), ("\u{1b}[c", "\u{1b}[?1;2c"),
                               ("\u{1b}[0c", "\u{1b}[?1;2c"), ("\u{1b}[>0q", "\u{1b}P>|xterm(400)\u{1b}\\")] {
            let needle = Data(query.utf8)
            var lower = tail.startIndex
            while lower < tail.endIndex, let match = tail.range(of: needle, in: lower..<tail.endIndex) {
                let position = start + tail.distance(from: tail.startIndex, to: match.lowerBound)
                if position > (lastReplyPosition[query] ?? -1) {
                    replies.append(Data(reply.utf8)); lastReplyPosition[query] = position
                }
                lower = match.upperBound
            }
        }
        tail = Data(tail.suffix(4))
        return replies
    }
}

enum ClaudeUsageScreen {
    static func report(from text: String, at date: Date) throws -> ClaudeQuotaReport {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var windows: [ClaudeQuotaWindow] = []
        for (index, line) in lines.enumerated() {
            let label = line.lowercased()
            let kind: QuotaWindowKind
            if label == "current session" { kind = .fiveHour }
            else if label == "current week" || label == "current week (all models)" { kind = .weekly }
            else { continue }
            let sectionLines = lines.dropFirst(index + 1).prefix(4).prefix { !$0.lowercased().hasPrefix("current ") }
            let section = sectionLines.joined(separator: " ")
            let expression = try NSRegularExpression(pattern: #"(?<![\d.])(\d+(?:\.\d+)?)%\s*used\b"#, options: .caseInsensitive)
            let range = NSRange(section.startIndex..<section.endIndex, in: section)
            guard let match = expression.firstMatch(in: section, range: range),
                  let valueRange = Range(match.range(at: 1), in: section),
                  let percentage = Double(section[valueRange]), percentage.isFinite,
                  (0...100).contains(percentage), !windows.contains(where: { $0.kind == kind }) else { continue }
            let reset = sectionLines.first { $0.lowercased().hasPrefix("resets ") }
                .flatMap { ClaudeResetTextParser.date(from: $0, kind: kind, now: date) }
            windows.append(ClaudeQuotaWindow(kind: kind, usedPercentage: percentage, resetsAt: reset))
        }
        guard !windows.isEmpty else { throw ClaudeQuotaIssue.noData }
        return ClaudeQuotaReport(source: .cliUsage, reportedAt: date, receivedAt: date, windows: windows)
    }

    /// Small VT screen replay: stale panels erased by the CLI never remain parseable.
    static func text(from data: Data) -> String {
        let scalars = Array(String(decoding: data, as: UTF8.self).unicodeScalars)
        let rows = 50, columns = 180
        var cells = Array(repeating: Array(repeating: " ", count: columns), count: rows)
        var row = 0, column = 0, index = 0
        while index < scalars.count {
            let scalar = scalars[index]; index += 1
            if scalar.value == 27 {
                guard index < scalars.count else { break }
                let next = scalars[index]; index += 1
                if next == "[" {
                    var parameters = ""
                    while index < scalars.count, !(64...126).contains(scalars[index].value) {
                        parameters.unicodeScalars.append(scalars[index]); index += 1
                    }
                    guard index < scalars.count else { break }
                    let command = scalars[index]; index += 1
                    let values = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                    let value = values.first ?? 0, amount = max(1, value)
                    switch command {
                    case "H", "f": row = min(rows - 1, amount - 1); column = min(columns - 1, max(1, values.dropFirst().first ?? 1) - 1)
                    case "A": row = max(0, row - amount)
                    case "B": row = min(rows - 1, row + amount)
                    case "C": column = min(columns - 1, column + amount)
                    case "D": column = max(0, column - amount)
                    case "G": column = min(columns - 1, amount - 1)
                    case "J", "K":
                        let start = command == "K" ? row * columns : 0
                        let end = command == "K" ? (row + 1) * columns : rows * columns
                        let cursor = row * columns + column
                        for cell in (value == 0 ? cursor : start)..<(value == 1 ? cursor + 1 : end) {
                            cells[cell / columns][cell % columns] = " "
                        }
                    default: break
                    }
                } else if next == "]" {
                    while index < scalars.count {
                        if scalars[index].value == 7 { index += 1; break }
                        if scalars[index].value == 27, index + 1 < scalars.count, scalars[index + 1] == "\\" { index += 2; break }
                        index += 1
                    }
                }
            } else if scalar == "\r" { column = 0 }
            else if scalar == "\n" {
                row += 1
                if row >= rows { cells.removeFirst(); cells.append(Array(repeating: " ", count: columns)); row = rows - 1 }
            } else if scalar.value == 8 { column = max(0, column - 1) }
            else if scalar.value >= 32 {
                cells[row][column] = String(scalar)
                column = min(columns - 1, column + 1)
            }
        }
        return cells.map { $0.joined().trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}
