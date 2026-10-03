import Foundation

/// Discovers executable paths only. It never opens Claude settings, credentials,
/// transcripts or VM contents; the client separately validates `--version`.
struct ClaudeExecutableLocator: Sendable {
    private let environment: [String: String]
    private let standardExecutableURLs: [URL]
    private let desktopInstallRoot: URL
    private static let cliSuffix = "claude.app/Contents/MacOS/claude"
    private static let maximumEntriesPerLevel = 32

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        standardExecutableURLs: [URL]? = nil,
        desktopInstallRoot: URL? = nil
    ) {
        self.environment = environment
        self.standardExecutableURLs = standardExecutableURLs ?? [
            homeDirectory.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        self.desktopInstallRoot = desktopInstallRoot
            ?? homeDirectory.appendingPathComponent("Library/Application Support/Claude/claude-code")
    }

    func locate(manualURL: URL? = nil) throws -> URL {
        for candidate in candidateURLs(manualURL: manualURL) {
            let resolved = candidate.resolvingSymlinksInPath()
            guard !Self.isVMPath(resolved),
                  let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  FileManager.default.isExecutableFile(atPath: resolved.path) else { continue }
            return resolved
        }
        throw ClaudeQuotaIssue.cliUnavailable
    }

    func candidateURLs(manualURL: URL? = nil) -> [URL] {
        // A supplied executable remains authoritative, even when it is missing.
        if let manualURL { return Self.isVMPath(manualURL) ? [] : [manualURL] }
        var candidates = standardExecutableURLs
        candidates += desktopCandidates()
        for path in (environment["PATH"] ?? "").split(separator: ":")
        where path.hasPrefix("/") && !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            candidates.append(URL(fileURLWithPath: String(path)).appendingPathComponent("claude"))
        }
        var seen = Set<String>()
        return candidates.filter {
            !Self.isVMPath($0) && seen.insert($0.standardizedFileURL.path).inserted
        }
    }

    private func desktopCandidates() -> [URL] {
        guard !Self.isVMPath(desktopInstallRoot), Self.isPlainDirectory(desktopInstallRoot),
              (try? ClaudeLocalFile.requireNoSymlinks(desktopInstallRoot)) != nil else { return [] }
        let versions = children(of: desktopInstallRoot)
            .filter { Self.matches($0.lastPathComponent, pattern: #"^[0-9]+\.[0-9]+\.[0-9]+$"#) }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            .prefix(Self.maximumEntriesPerLevel)
        return versions.flatMap { version -> [URL] in
            let builds = children(of: version)
                .filter { Self.matches($0.lastPathComponent, pattern: #"^[0-9a-fA-F]{8,64}$"#) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .prefix(Self.maximumEntriesPerLevel)
            return builds.map { $0.appendingPathComponent(Self.cliSuffix) }
                + [version.appendingPathComponent(Self.cliSuffix)]
        }
    }

    private func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ))?.filter(Self.isPlainDirectory) ?? []
    }

    private static func isPlainDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink == false
    }

    private static func matches(_ name: String, pattern: String) -> Bool {
        guard name.utf8.count <= 64 else { return false }
        return name.range(of: pattern, options: .regularExpression) == name.startIndex..<name.endIndex
    }

    private static func isVMPath(_ url: URL) -> Bool { url.pathComponents.contains("claude-code-vm") }
}
