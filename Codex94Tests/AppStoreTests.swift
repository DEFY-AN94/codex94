import Darwin
import XCTest
@testable import Codex94

@MainActor
final class AppStoreTests: XCTestCase {
    func testIdentityUpgradeQueuesAccountRefreshWhenRefreshIsAlreadyRunning() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94StoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\necho 'codex-cli 9.4.0'\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let suiteName = "Codex94StorePreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.manualCodexPath = executable.path
        preferences.identityMode = .quotaOnly
        preferences.hasChosenIdentityMode = true

        let fetcher = IdentityRecordingFetcher()
        let store = AppStore(
            preferences: preferences,
            locator: CodexExecutableLocator(
                environment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"],
                homeDirectory: directory
            ),
            fetcher: fetcher,
            cache: SnapshotCache(fileURL: directory.appendingPathComponent("quota.json"))
        )

        store.refresh(trigger: .manual)
        store.setIdentityMode(.quotaAndAccount)

        let deadline = Date().addingTimeInterval(3)
        while store.snapshot?.account?.email != "account@example.com", Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(store.snapshot?.account?.email, "account@example.com")
        let requestedModes = await fetcher.requestedModes()
        XCTAssertEqual(requestedModes, [.quotaOnly, .quotaAndAccount])
        XCTAssertFalse(store.isRefreshing)
    }

    func testIdentityDowngradeNeverAppliesAccountFromInFlightRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex94StoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\necho 'codex-cli 9.4.0'\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(chmod(executable.path, 0o700), 0)

        let suiteName = "Codex94StorePreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.manualCodexPath = executable.path
        preferences.identityMode = .quotaAndAccount
        preferences.hasChosenIdentityMode = true

        let fetcher = IdentityRecordingFetcher()
        let store = AppStore(
            preferences: preferences,
            locator: CodexExecutableLocator(
                environment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"],
                homeDirectory: directory
            ),
            fetcher: fetcher,
            cache: SnapshotCache(fileURL: directory.appendingPathComponent("quota.json"))
        )

        store.refresh(trigger: .manual)
        store.setIdentityMode(.quotaOnly)

        let deadline = Date().addingTimeInterval(3)
        while store.isRefreshing, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertNil(store.snapshot?.account)
        let requestedModes = await fetcher.requestedModes()
        XCTAssertEqual(requestedModes, [.quotaAndAccount, .quotaOnly])
        XCTAssertFalse(store.isRefreshing)
    }
}

private actor IdentityRecordingFetcher: QuotaFetching {
    private var modes: [IdentityMode] = []

    func fetch(executable: LocatedCodex, identityMode: IdentityMode) async throws -> QuotaSnapshot {
        modes.append(identityMode)
        if modes.count == 1 {
            try await Task.sleep(for: .milliseconds(150))
        }

        return QuotaSnapshot(
            windows: [
                QuotaWindowSnapshot(
                    kind: .weekly,
                    usedPercent: 40,
                    windowMinutes: 10_080,
                    resetsAt: nil
                )
            ],
            planType: "pro",
            fetchedAt: Date(),
            account: identityMode == .quotaAndAccount
                ? AccountSummary(
                    type: "chatgpt",
                    email: "account@example.com",
                    planType: "pro"
                )
                : nil,
            codex: executable
        )
    }

    func requestedModes() -> [IdentityMode] {
        modes
    }
}
