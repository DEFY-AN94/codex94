import AppKit
import SwiftUI

struct CopyTextButton: View {
    let text: String
    let label: LocalizedStringKey
    let copiedLabel: LocalizedStringKey
    var systemImage = "doc.on.doc"
    var accessibilityIdentifier: String? = nil
    var pasteboard: NSPasteboard = .general

    @State private var copied = false

    var body: some View {
        if let accessibilityIdentifier {
            copyButton.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            copyButton
        }
    }

    private var copyButton: some View {
        Button {
            guard Self.write(text, to: pasteboard) else { return }
            copied = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                copied = false
            }
        } label: {
            Label(copied ? copiedLabel : label, systemImage: systemImage)
        }
    }

    @discardableResult
    static func write(_ text: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
