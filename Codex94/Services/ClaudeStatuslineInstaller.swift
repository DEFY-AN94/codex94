import Foundation

enum ClaudeStatuslineSetupState: Equatable, Sendable {
    case notInstalled
    case installed
    case conflict
    case differentConfiguration
}

enum ClaudeStatuslineReportEligibility: Equatable, Sendable {
    case allowed, confirmationRequired, blocked
}

struct ClaudeStatuslineInstallPreview: Sendable {
    let settingsURL: URL
    let originalCommand: String?
    let bridgeCommand: String
    let preservesExistingStatusline: Bool
    let installationID: String
    fileprivate let expectedDigest: String
    fileprivate let originalSettings: Data
    fileprivate let installedStatusline: Data
    fileprivate let previousStatusline: Data?
}

struct ClaudeStatuslineInstaller: Sendable {
    struct Manifest: Codable {
        let version: Int
        let settingsPath: String
        let cachePath: String
        let installedCommand: String
        let installedStatusline: Data
        let previousStatusline: Data?
        let originalCommand: String?
        let backupPath: String
        var installationID: String? = nil
    }

    let settingsURL: URL
    let cache: ClaudeStatuslineCache
    let executableURL: URL
    let supportDirectory: URL
    private let directories: ClaudeConfigurationDirectories
    var manifestURL: URL { supportDirectory.appendingPathComponent("statusline-installation.json") }

    init(settingsURL: URL? = nil, cache: ClaudeStatuslineCache = ClaudeStatuslineCache(),
         executableURL: URL? = nil, supportDirectory: URL? = nil,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let directories = ClaudeConfigurationDirectories(environment: environment, homeDirectory: homeDirectory)
        self.directories = directories
        self.settingsURL = settingsURL ?? directories.settingsURL
        self.cache = cache
        self.executableURL = executableURL ?? Bundle.main.executableURL
            ?? URL(fileURLWithPath: "/Applications/Codex94.app/Contents/MacOS/Codex94")
        self.supportDirectory = supportDirectory ?? cache.fileURL.deletingLastPathComponent()
    }

    var setupState: ClaudeStatuslineSetupState {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return .notInstalled }
        guard let observed = try? readAnyManifest() else { return .conflict }
        guard observed.settingsPath == settingsURL.path else { return .differentConfiguration }
        guard let manifest = try? readManifest(), let settings = try? readSettings(),
              let object = try? Self.object(settings),
              let line = object["statusLine"], let canonical = try? Self.encode(line) else { return .conflict }
        return canonical == manifest.installedStatusline ? .installed : .conflict
    }

    var isInstalled: Bool { setupState == .installed }

    /// A report stream has no authenticated account identity. Configuration and
    /// installation ownership are eligibility checks before stream confirmation.
    func reportEligibility(installationID: String?) -> ClaudeStatuslineReportEligibility {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return installationID == nil ? .confirmationRequired : .blocked
        }
        guard setupState == .installed, let manifest = try? readManifest() else { return .blocked }
        if let expected = manifest.installationID {
            return installationID == expected ? .allowed : .blocked
        }
        guard installationID == nil else { return .blocked }
        return directories.overrideDirectory == nil && settingsURL.path == directories.defaultSettingsURL.path
            ? .allowed : .confirmationRequired
    }

    static func validInstallationID(_ value: String?) -> Bool {
        value.map { UUID(uuidString: $0)?.uuidString == $0 } ?? true
    }

    private func bridgeCommand(installationID: String?) -> String {
        let command = Self.quote(executableURL.path) + " " + ClaudeStatuslineBridge.argument + " " + Self.quote(manifestURL.path)
        return installationID.map { command + " " + Self.quote($0) } ?? command
    }

    func previewInstall() throws -> ClaudeStatuslineInstallPreview {
        guard !FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ClaudeQuotaIssue.configurationConflict
        }
        let data = try readSettings()
        let settings = try Self.object(data)
        var line = [String: Any]()
        var originalCommand: String?
        let previous: Data?
        if let existing = settings["statusLine"] {
            guard let object = existing as? [String: Any], object["type"] as? String == "command",
                  let command = object["command"] as? String, !command.isEmpty else {
                throw ClaudeQuotaIssue.configurationConflict
            }
            line = object
            originalCommand = command
            previous = try Self.encode(object)
        } else { previous = nil }
        let installationID = UUID().uuidString
        let command = bridgeCommand(installationID: installationID)
        line["type"] = "command"
        line["command"] = command
        return ClaudeStatuslineInstallPreview(
            settingsURL: settingsURL, originalCommand: originalCommand, bridgeCommand: command,
            preservesExistingStatusline: previous != nil, installationID: installationID, expectedDigest: ClaudeLocalFile.digest(data),
            originalSettings: data, installedStatusline: try Self.encode(line), previousStatusline: previous
        )
    }

    func install(_ preview: ClaudeStatuslineInstallPreview) throws {
        try cache.withExclusiveAccess { try installLocked(preview) }
    }

    private func installLocked(_ preview: ClaudeStatuslineInstallPreview) throws {
        guard preview.settingsURL == settingsURL,
              preview.expectedDigest == ClaudeLocalFile.digest(try readSettings()),
              !FileManager.default.fileExists(atPath: manifestURL.path),
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ClaudeQuotaIssue.configurationConflict
        }
        try ClaudeLocalFile.requireNoSymlinks(executableURL)
        try ClaudeLocalFile.createPrivateDirectory(supportDirectory)
        let backup = supportDirectory.appendingPathComponent("settings-backup-\(UUID().uuidString).json")
        var backupRecord: [String: Any] = ["version": 1, "settingsDigest": preview.expectedDigest,
                                          "hadStatusline": preview.previousStatusline != nil]
        if let previous = preview.previousStatusline {
            backupRecord["statusLine"] = try JSONSerialization.jsonObject(with: previous)
        }
        try ClaudeLocalFile.write(try Self.encode(backupRecord), to: backup)
        let manifest = Manifest(
            version: 1, settingsPath: settingsURL.path, cachePath: cache.fileURL.path,
            installedCommand: preview.bridgeCommand, installedStatusline: preview.installedStatusline,
            previousStatusline: preview.previousStatusline, originalCommand: preview.originalCommand,
            backupPath: backup.path, installationID: preview.installationID
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try ClaudeLocalFile.write(manifestData, to: manifestURL)
        do {
            guard preview.expectedDigest == ClaudeLocalFile.digest(try readSettings()) else {
                throw ClaudeQuotaIssue.configurationConflict
            }
            var settings = try Self.object(preview.originalSettings)
            settings["statusLine"] = try JSONSerialization.jsonObject(with: preview.installedStatusline)
            try ClaudeLocalFile.write(try Self.encode(settings), to: settingsURL)
        } catch {
            // Remove only the manifest this invocation created; preserve the backup.
            if (try? ClaudeLocalFile.read(manifestURL, maximumBytes: 1_048_576)) == manifestData {
                try? FileManager.default.removeItem(at: manifestURL)
            }
            throw error
        }
    }

    func remove() throws {
        try cache.withExclusiveAccess { try removeLocked() }
    }

    private func removeLocked() throws {
        let manifest = try readManifest()
        let originalData = try readSettings()
        var settings = try Self.object(originalData)
        guard let current = settings["statusLine"],
              try Self.encode(current) == manifest.installedStatusline else {
            throw ClaudeQuotaIssue.configurationConflict
        }
        if let previous = manifest.previousStatusline {
            settings["statusLine"] = try JSONSerialization.jsonObject(with: previous)
        } else { settings.removeValue(forKey: "statusLine") }
        guard try readSettings() == originalData else { throw ClaudeQuotaIssue.configurationConflict }
        try ClaudeLocalFile.write(try Self.encode(settings), to: settingsURL)
        try FileManager.default.removeItem(at: manifestURL)
        // Backups and quota evidence remain user-owned recovery material.
    }

    /// Explicit conflict recovery: only forget our retired integration record.
    /// Current settings, the original backup, and quota evidence are untouched.
    func forgetConflictingInstallation() throws {
        try cache.withExclusiveAccess { try forgetConflictingInstallationLocked() }
    }

    private func forgetConflictingInstallationLocked() throws {
        let manifestData = try ClaudeLocalFile.read(manifestURL, maximumBytes: 1_048_576)
        let manifest = try recoveryManifest(from: manifestData)
        let settingsData = try readSettings()
        let settings = try Self.object(settingsData)
        if let current = settings["statusLine"] {
            guard let line = current as? [String: Any], line["type"] as? String == "command",
                  let command = line["command"] as? String,
                  !command.contains(ClaudeStatuslineBridge.argument),
                  !command.contains(manifestURL.path),
                  try Self.encode(current) != manifest.installedStatusline else {
                // Even a wrapper around the bridge still needs the manifest.
                throw ClaudeQuotaIssue.configurationConflict
            }
        }
        guard try readSettings() == settingsData,
              try ClaudeLocalFile.read(manifestURL, maximumBytes: 1_048_576) == manifestData else {
            throw ClaudeQuotaIssue.configurationConflict
        }
        try FileManager.default.removeItem(at: manifestURL)
    }

    private func recoveryManifest(from data: Data) throws -> Manifest {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.version == 1,
              Self.validInstallationID(manifest.installationID) else { throw ClaudeQuotaIssue.configurationConflict }
        let expectedCommand = bridgeCommand(installationID: manifest.installationID)
        guard
              manifest.settingsPath == settingsURL.path, manifest.cachePath == cache.fileURL.path,
              manifest.installedCommand == expectedCommand,
              let installed = try? Self.object(manifest.installedStatusline),
              installed["type"] as? String == "command", installed["command"] as? String == expectedCommand else {
            throw ClaudeQuotaIssue.configurationConflict
        }
        let backupURL = URL(fileURLWithPath: manifest.backupPath)
        let backupName = backupURL.lastPathComponent
        guard backupURL.deletingLastPathComponent().path == supportDirectory.path,
              backupName.hasPrefix("settings-backup-"), backupName.hasSuffix(".json"),
              UUID(uuidString: String(backupName.dropFirst("settings-backup-".count).dropLast(".json".count))) != nil,
              let backupData = try? ClaudeLocalFile.read(backupURL, maximumBytes: 1_048_576),
              let backup = try? Self.object(backupData),
              StrictJSONInteger.nonnegative(backup["version"]) == 1,
              let digest = backup["settingsDigest"] as? String, digest.count == 64, digest.allSatisfy(\.isHexDigit),
              let hadStatusline = backup["hadStatusline"] as? Bool,
              hadStatusline == (manifest.previousStatusline != nil) else {
            throw ClaudeQuotaIssue.configurationConflict
        }
        if let previousData = manifest.previousStatusline {
            guard let previous = try? Self.object(previousData), previous["type"] as? String == "command",
                  let command = previous["command"] as? String, command == manifest.originalCommand,
                  let backupLine = backup["statusLine"],
                  try Self.encode(backupLine) == Self.encode(previous) else {
                throw ClaudeQuotaIssue.configurationConflict
            }
        } else if manifest.originalCommand != nil || backup["statusLine"] != nil {
            throw ClaudeQuotaIssue.configurationConflict
        }
        return manifest
    }

    private func readSettings() throws -> Data {
        try ClaudeLocalFile.requireNoSymlinks(settingsURL)
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return Data("{}".utf8) }
        return try ClaudeLocalFile.read(settingsURL, maximumBytes: 1_048_576)
    }

    private func readAnyManifest() throws -> Manifest {
        let data = try ClaudeLocalFile.read(manifestURL, maximumBytes: 1_048_576)
        guard let value = try? JSONDecoder().decode(Manifest.self, from: data), value.version == 1,
              value.settingsPath.hasPrefix("/"), value.cachePath.hasPrefix("/"),
              Self.validInstallationID(value.installationID) else {
            throw ClaudeQuotaIssue.configurationConflict
        }
        return value
    }

    private func readManifest() throws -> Manifest {
        let value = try readAnyManifest()
        guard value.settingsPath == settingsURL.path, value.cachePath == cache.fileURL.path else {
            throw ClaudeQuotaIssue.configurationConflict
        }
        return value
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeQuotaIssue.invalidData
        }
        return value
    }

    private static func encode(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    }

    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
