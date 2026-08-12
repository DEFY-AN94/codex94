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
            for component in path.split(separator: ":") where !component.isEmpty {
                candidates.append((
                    URL(fileURLWithPath: String(component)).appendingPathComponent("codex"),
                    .path
                ))
            }
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.0.standardizedFileURL.path).inserted }
    }

    private func validatedVersion(at executableURL: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        let completion = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = ["--version"]
        process.environment = Self.sanitizedEnvironment(from: environment)
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            throw ConnectionIssue.processLaunchFailed
        }

        guard completion.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            throw ConnectionIssue.invalidCodexVersion
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix("codex-cli ") else {
            throw ConnectionIssue.invalidCodexVersion
        }
        return value
    }

    static func sanitizedEnvironment(from environment: [String: String]) -> [String: String] {
        var result: [String: String] = [
            "HOME": environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": environment["TMPDIR"] ?? NSTemporaryDirectory()
        ]
        for key in ["LANG", "LC_ALL", "LC_CTYPE"] {
            if let value = environment[key] { result[key] = value }
        }
        return result
    }
}
