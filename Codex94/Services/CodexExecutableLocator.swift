import Darwin
import Foundation

struct CodexExecutableLocator: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func locate(manualPath: String?) throws -> LocatedCodex {
        if let manualPath,
           !manualPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try locateManual(path: manualPath)
        }

        var sawExistingFile = false

        for candidate in candidateURLs(manualPath: manualPath) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: candidate.url.path,
                isDirectory: &isDirectory
            ) else { continue }

            sawExistingFile = true
            guard !isDirectory.boolValue,
                  FileManager.default.isExecutableFile(atPath: candidate.url.path) else {
                continue
            }

            guard let version = try? validatedVersion(at: candidate.url) else {
                continue
            }

            return LocatedCodex(
                executableURL: candidate.url.resolvingSymlinksInPath(),
                version: version,
                source: candidate.source
            )
        }

        throw sawExistingFile
            ? ConnectionIssue.invalidCodexVersion
            : ConnectionIssue.codexNotFound
    }

    private func locateManual(path: String) throws -> LocatedCodex {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ConnectionIssue.codexNotFound
        }
        guard !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ConnectionIssue.codexNotExecutable
        }

        let version: String
        do {
            version = try validatedVersion(at: url)
        } catch {
            throw ConnectionIssue.invalidCodexVersion
        }
        return LocatedCodex(
            executableURL: url.resolvingSymlinksInPath(),
            version: version,
            source: .manual
        )
    }

    func candidateURLs(manualPath: String?) -> [(url: URL, source: LocatedCodex.Source)] {
        var candidates: [(URL, LocatedCodex.Source)] = []

        if let manualPath, !manualPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = NSString(string: manualPath).expandingTildeInPath
            candidates.append((URL(fileURLWithPath: expanded), .manual))
        }

        candidates.append((
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            .chatGPTApp
        ))
        candidates.append((URL(fileURLWithPath: "/opt/homebrew/bin/codex"), .homebrew))
        candidates.append((URL(fileURLWithPath: "/usr/local/bin/codex"), .usrLocal))
        candidates.append((homeDirectory.appendingPathComponent(".local/bin/codex"), .localBin))

        if let path = environment["PATH"] {
            for component in Self.absolutePathComponents(path) {
                candidates.append((
                    URL(fileURLWithPath: component).appendingPathComponent("codex"),
                    .path
                ))
            }
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.0.standardizedFileURL.path).inserted }
    }

    private func validatedVersion(at executableURL: URL) throws -> String {
        let output = Pipe()
        let deadline = Date().addingTimeInterval(3)

        let process: ManagedSubprocess
        do {
            process = try ManagedSubprocess.launch(
                executableURL: executableURL,
                arguments: ["--version"],
                environment: Self.sanitizedEnvironment(from: environment),
                standardOutput: output
            )
        } catch {
            throw ConnectionIssue.processLaunchFailed
        }
        defer { ProcessTerminator.stop(process, gracePeriod: 0.5) }

        let data: Data
        do {
            data = try Self.readBoundedOutput(
                descriptor: output.fileHandleForReading.fileDescriptor,
                deadline: deadline,
                maximumBytes: 1_024
            )
            guard process.waitUntilExit(before: deadline) else {
                throw ConnectionIssue.invalidCodexVersion
            }
        } catch {
            throw ConnectionIssue.invalidCodexVersion
        }

        guard process.terminationStatus == 0,
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              value.count <= 128,
              value.hasPrefix("codex-cli "),
              value.unicodeScalars.allSatisfy({ 0x20 <= $0.value && $0.value <= 0x7E }) else {
            throw ConnectionIssue.invalidCodexVersion
        }
        return value
    }

    static func sanitizedEnvironment(from environment: [String: String]) -> [String: String] {
        var result: [String: String] = [
            "HOME": environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": sanitizedPath(environment["PATH"]),
            "TMPDIR": environment["TMPDIR"] ?? NSTemporaryDirectory()
        ]
        for key in ["LANG", "LC_ALL", "LC_CTYPE"] {
            if let value = environment[key] { result[key] = value }
        }
        return result
    }

    private static func sanitizedPath(_ path: String?) -> String {
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        guard let path else { return fallback }
        let components = absolutePathComponents(path)
        return components.isEmpty ? fallback : components.joined(separator: ":")
    }

    private static func absolutePathComponents(_ path: String) -> [String] {
        path.split(separator: ":").compactMap { rawComponent in
            let component = String(rawComponent)
            guard component.hasPrefix("/"),
                  component.rangeOfCharacter(from: .controlCharacters) == nil else {
                return nil
            }
            return component
        }
    }

    private static func readBoundedOutput(
        descriptor: Int32,
        deadline: Date,
        maximumBytes: Int
    ) throws -> Data {
        var data = Data()
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw ConnectionIssue.invalidCodexVersion }

            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let timeoutMilliseconds = Int32(min(Double(Int32.max), ceil(remaining * 1_000)))
            let pollResult = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
            if pollResult == 0 { throw ConnectionIssue.invalidCodexVersion }
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw ConnectionIssue.invalidCodexVersion
            }

            var bytes = [UInt8](repeating: 0, count: 512)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                throw ConnectionIssue.invalidCodexVersion
            }

            guard data.count + Int(count) <= maximumBytes else {
                throw ConnectionIssue.invalidCodexVersion
            }
            data.append(contentsOf: bytes.prefix(Int(count)))
        }
    }

}
