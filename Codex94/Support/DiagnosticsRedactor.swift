import Foundation

enum DiagnosticsRedactor {
    private static let safeVersionCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-"
    )
    private static let emailExpression = try? NSRegularExpression(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )

    static func codexPath(for locatedCodex: LocatedCodex?) -> String {
        guard let locatedCodex else { return "not-detected" }

        return switch locatedCodex.source {
        case .chatGPTApp:
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        case .homebrew:
            "/opt/homebrew/bin/codex"
        case .usrLocal:
            "/usr/local/bin/codex"
        case .localBin:
            "~/.local/bin/codex"
        case .manual, .path:
            "<redacted-path>/codex"
        }
    }

    static func codexVersion(_ value: String?) -> String {
        guard let value else { return "unknown" }

        let prefix = "codex-cli "
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.hasPrefix(prefix) else { return "codex-cli <redacted-version>" }

        let version = String(candidate.dropFirst(prefix.count))
        guard !version.isEmpty,
              version.count <= 64,
              version.unicodeScalars.allSatisfy({ safeVersionCharacters.contains($0) }) else {
            return "codex-cli <redacted-version>"
        }

        return "\(prefix)\(version)"
    }

    static func redact(_ value: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var result = value
        if !homeDirectory.isEmpty {
            result = result.replacingOccurrences(of: homeDirectory, with: "~")
        }

        guard let emailExpression else { return result }
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        return emailExpression.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: "<redacted-email>"
        )
    }
}
