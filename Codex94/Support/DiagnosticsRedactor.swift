import Foundation

enum DiagnosticsRedactor {
    private static let emailExpression = try? NSRegularExpression(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )

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

