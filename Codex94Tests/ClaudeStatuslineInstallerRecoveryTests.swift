import Foundation
import XCTest
@testable import Codex94

final class ClaudeStatuslineInstallerRecoveryTests: XCTestCase {
    func testConflictRecoveryPreservesCurrentSettingsAndBackupsThenWrapsCurrentCommand() throws {
        let fixture = try fixture()
        let oldMarker = fixture.root.appendingPathComponent("old-command-ran")
        let newMarker = fixture.root.appendingPathComponent("new-command-ran")
        let oldCommand = "touch '\(oldMarker.path)'"
        let newCommand = "touch '\(newMarker.path)'"
        try writeSettings(["statusLine": ["type": "command", "command": oldCommand, "padding": 2],
                           "unrelated": ["kept": true]], fixture: fixture)
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
        try fixture.installer.install(fixture.installer.previewInstall())
        XCTAssertEqual(fixture.installer.setupState, .installed)
        let originalBackups = try backups(in: fixture)
        XCTAssertEqual(originalBackups.count, 1)

        let edited: [String: Any] = ["statusLine": ["type": "command", "command": newCommand, "padding": 7],
                                     "unrelated": ["kept": true], "addedAfterInstall": "retained"]
        try writeSettings(edited, fixture: fixture)
        let editedBytes = try Data(contentsOf: fixture.installer.settingsURL)
        XCTAssertEqual(fixture.installer.setupState, .conflict)
        XCTAssertFalse(fixture.installer.isInstalled)
        XCTAssertThrowsError(try fixture.installer.previewInstall())
        XCTAssertThrowsError(try fixture.installer.remove())

        try fixture.installer.forgetConflictingInstallation()
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installer.manifestURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), editedBytes)
        XCTAssertEqual(try backups(in: fixture), originalBackups)
        let preview = try fixture.installer.previewInstall()
        XCTAssertEqual(preview.originalCommand, newCommand)
        XCTAssertTrue(preview.preservesExistingStatusline)
        try fixture.installer.install(preview)
        XCTAssertEqual(fixture.installer.setupState, .installed)
        let manifest = try JSONDecoder().decode(ClaudeStatuslineInstaller.Manifest.self,
                                                from: Data(contentsOf: fixture.installer.manifestURL))
        XCTAssertEqual(manifest.originalCommand, newCommand)
        let installed = try settings(fixture)
        XCTAssertEqual((installed["statusLine"] as? [String: Any])?["padding"] as? Int, 7)
        XCTAssertEqual(installed["addedAfterInstall"] as? String, "retained")
        XCTAssertEqual((installed["unrelated"] as? [String: Bool])?["kept"], true)
        for (name, data) in originalBackups { XCTAssertEqual(try backups(in: fixture)[name], data) }
        XCTAssertEqual(try backups(in: fixture).count, 2)
        try fixture.installer.remove()
        XCTAssertEqual((try settings(fixture)["statusLine"] as? [String: Any])?["command"] as? String, newCommand)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldMarker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newMarker.path), "Recovery and preview never execute either command")
    }

    func testRecoveryAfterUserDeletesSettingsDoesNotRecreateThem() throws {
        let fixture = try fixture()
        try fixture.installer.install(fixture.installer.previewInstall())
        let originalBackups = try backups(in: fixture)
        try FileManager.default.removeItem(at: fixture.installer.settingsURL)
        XCTAssertEqual(fixture.installer.setupState, .conflict)
        try fixture.installer.forgetConflictingInstallation()
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installer.settingsURL.path))
        XCTAssertEqual(try backups(in: fixture), originalBackups)
        XCTAssertNil(try fixture.installer.previewInstall().originalCommand)
    }

    func testRecoveryRefusesInstalledOrStillReferencedBridge() throws {
        let fixture = try fixture()
        let preview = try fixture.installer.previewInstall()
        try fixture.installer.install(preview)
        let manifestBytes = try Data(contentsOf: fixture.installer.manifestURL)
        for command in [preview.bridgeCommand, "printf prefix; " + preview.bridgeCommand] {
            try writeSettings(["statusLine": ["type": "command", "command": command, "padding": 9]], fixture: fixture)
            let settingsBytes = try Data(contentsOf: fixture.installer.settingsURL)
            XCTAssertEqual(fixture.installer.setupState, .conflict)
            XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation()) {
                XCTAssertEqual($0 as? ClaudeQuotaIssue, .configurationConflict)
            }
            XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), manifestBytes)
            XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), settingsBytes)
        }
        try writeSettings(["statusLine": ["type": "command", "command": preview.bridgeCommand]], fixture: fixture)
        XCTAssertEqual(fixture.installer.setupState, .installed)
        XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation())
        XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), manifestBytes)
    }

    func testRecoveryRefusesForeignOrMalformedManifestWithoutDeletingIt() throws {
        for mutation in ["settingsPath", "cachePath", "installedCommand", "installedStatusline", "backupPath", "originalCommand"] {
            let fixture = try fixture()
            try fixture.installer.install(fixture.installer.previewInstall())
            try writeSettings(["statusLine": ["type": "command", "command": "printf user-change"]], fixture: fixture)
            var manifest = try json(fixture.installer.manifestURL)
            if mutation == "installedStatusline" {
                manifest[mutation] = try JSONSerialization.data(withJSONObject: ["type": "command", "command": "printf foreign"])
                    .base64EncodedString()
            } else { manifest[mutation] = "foreign-record" }
            let bytes = try JSONSerialization.data(withJSONObject: manifest)
            try bytes.write(to: fixture.installer.manifestURL)
            XCTAssertEqual(fixture.installer.setupState, .conflict)
            XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation(), mutation)
            XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), bytes, mutation)
            XCTAssertEqual((try settings(fixture)["statusLine"] as? [String: String])?["command"], "printf user-change")
        }
        let fixture = try fixture()
        try FileManager.default.createDirectory(at: fixture.installer.supportDirectory, withIntermediateDirectories: true)
        let bytes = Data("not a manifest".utf8)
        try bytes.write(to: fixture.installer.manifestURL)
        XCTAssertEqual(fixture.installer.setupState, .conflict)
        XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation())
        XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), bytes)
    }

    func testRecoveryRequiresOriginalBackupAndPreservesMalformedCurrentSettings() throws {
        let fixture = try fixture()
        try writeSettings(["statusLine": ["type": "command", "command": "printf original"]], fixture: fixture)
        try fixture.installer.install(fixture.installer.previewInstall())
        let manifestBytes = try Data(contentsOf: fixture.installer.manifestURL)
        let manifest = try JSONDecoder().decode(ClaudeStatuslineInstaller.Manifest.self, from: manifestBytes)
        let backupURL = URL(fileURLWithPath: manifest.backupPath)
        let backupBytes = try Data(contentsOf: backupURL)
        try writeSettings(["statusLine": ["type": "command", "command": "printf user-change"]], fixture: fixture)
        var backup = try json(backupURL)
        backup["statusLine"] = ["type": "command", "command": "printf unrelated"]
        try JSONSerialization.data(withJSONObject: backup).write(to: backupURL)
        XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation())
        XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), manifestBytes)
        try backupBytes.write(to: backupURL)
        let invalidSettings = Data("unfinished settings edit".utf8)
        try invalidSettings.write(to: fixture.installer.settingsURL)
        XCTAssertEqual(fixture.installer.setupState, .conflict)
        XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation())
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), invalidSettings)
        XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), manifestBytes)
        XCTAssertEqual(try Data(contentsOf: backupURL), backupBytes)
    }

    private struct Fixture {
        let root: URL
        let installer: ClaudeStatuslineInstaller
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("synthetic-app")
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let support = root.appendingPathComponent("support")
        let cache = ClaudeStatuslineCache(fileURL: support.appendingPathComponent("statusline-quota.json"))
        let installer = ClaudeStatuslineInstaller(settingsURL: root.appendingPathComponent("settings.json"),
            cache: cache, executableURL: executable, supportDirectory: support)
        return Fixture(root: root, installer: installer)
    }

    private func writeSettings(_ value: [String: Any], fixture: Fixture) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: fixture.installer.settingsURL)
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func settings(_ fixture: Fixture) throws -> [String: Any] { try json(fixture.installer.settingsURL) }

    private func backups(in fixture: Fixture) throws -> [String: Data] {
        let files = try FileManager.default.contentsOfDirectory(at: fixture.installer.supportDirectory, includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: files.filter { $0.lastPathComponent.hasPrefix("settings-backup-") }
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
}
