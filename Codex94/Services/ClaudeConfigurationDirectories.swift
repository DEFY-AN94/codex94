import Foundation

/// Resolves paths only. Readers retain their own file and ownership checks.
struct ClaudeConfigurationDirectories: Sendable {
    static let environmentKey = "CLAUDE_CONFIG_DIR"
    let overrideDirectory: URL?
    let homeDirectory: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
        if let path = environment[Self.environmentKey], Self.isUsableDirectoryPath(path) {
            overrideDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else { overrideDirectory = nil }
    }

    var usageDirectory: URL { overrideDirectory ?? homeDirectory }
    var settingsURL: URL {
        (overrideDirectory ?? homeDirectory.appendingPathComponent(".claude", isDirectory: true))
            .appendingPathComponent("settings.json")
    }
    var defaultSettingsURL: URL {
        homeDirectory.appendingPathComponent(".claude/settings.json")
    }

    private static func isUsableDirectoryPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.utf8.count <= 1_024,
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let parts = path.split(separator: "/")
        return !parts.contains(".") && !parts.contains("..")
    }
}
