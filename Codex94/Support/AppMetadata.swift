import Foundation

struct AppMetadata: Equatable {
    let name: String
    let version: String
    let build: String
    let bundleIdentifier: String
    let minimumSystemVersion: String
    let copyright: String

    static let projectURL = URL(string: "https://github.com/DEFY-AN94/codex94")!

    static var current: AppMetadata {
        AppMetadata(bundle: .main)
    }

    init(bundle: Bundle) {
        self.init(infoDictionary: bundle.infoDictionary)
    }

    init(infoDictionary: [String: Any]?) {
        let info = infoDictionary ?? [:]
        name = Self.string(in: info, keys: ["CFBundleDisplayName", "CFBundleName"])
            ?? "Codex94"
        version = Self.string(in: info, keys: ["CFBundleShortVersionString"])
            ?? "0.0.0"
        build = Self.string(in: info, keys: ["CFBundleVersion"])
            ?? "0"
        bundleIdentifier = Self.string(in: info, keys: ["CFBundleIdentifier"])
            ?? "com.defyan94.codex94"
        minimumSystemVersion = Self.string(in: info, keys: ["LSMinimumSystemVersion"])
            ?? "14.0"
        copyright = Self.string(in: info, keys: ["NSHumanReadableCopyright"])
            ?? "Copyright 2026 Codex94 contributors"
    }

    var versionAndBuild: String {
        "\(version) (\(build))"
    }

    private static func string(in info: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = info[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
