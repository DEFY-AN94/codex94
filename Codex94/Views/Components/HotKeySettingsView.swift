import AppKit
import SwiftUI

struct HotKeySettingsView: View {
    @ObservedObject private var store: AppStore
    @ObservedObject private var controller: GlobalHotKeyController
    @State private var isRecording = false
    @State private var recordingIssue: GlobalHotKeyIssue?

    init(store: AppStore) {
        self.store = store
        self.controller = store.hotKeyController
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if isRecording {
                        Text("hotkey.recording")
                    } else if let hotKey = store.preferences.globalHotKey {
                        Text(verbatim: hotKey.displayString)
                    } else {
                        Text("hotkey.none")
                    }
                }
                .font(.system(.body, design: .monospaced))
                .accessibilityIdentifier("global-hotkey-value")
                Spacer(minLength: 0)
            }

            HStack {
                Button(isRecording ? "hotkey.cancel" : "hotkey.record") {
                    if isRecording { stopRecording() }
                    else { startRecording() }
                }
                .accessibilityIdentifier("global-hotkey-record")

                Button("hotkey.clear") {
                    stopRecording()
                    recordingIssue = nil
                    _ = store.setGlobalHotKey(nil)
                }
                .disabled(store.preferences.globalHotKey == nil)
                .accessibilityIdentifier("global-hotkey-clear")
            }

            Text("hotkey.help")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let issue = recordingIssue ?? controller.lastIssue {
                Text(LocalizedStringKey(issue.localizationKey))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("global-hotkey-error")
            }
        }
        .background(alignment: .topLeading) {
            HotKeyCaptureView(
                isRecording: isRecording,
                onShortcut: record,
                onCancel: stopRecording,
                onInvalid: { recordingIssue = .invalidShortcut }
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recordingIssue = nil
        isRecording = true
        // Carbon owns the already-registered shortcut. Re-entering it should
        // finish recording without opening the popover or releasing ownership.
        controller.beginRecording(handler: record)
    }

    private func stopRecording() {
        isRecording = false
        controller.endRecording()
    }

    private func record(_ hotKey: GlobalHotKey) {
        guard hotKey.isValid else {
            recordingIssue = .invalidShortcut
            return
        }
        stopRecording()
        recordingIssue = nil
        _ = store.setGlobalHotKey(hotKey)
    }
}

/// A temporary first responder inside the settings window. No event tap or
/// global keyboard monitor is installed, and it stops when that window resigns key.
private struct HotKeyCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let onShortcut: (GlobalHotKey) -> Void
    let onCancel: () -> Void
    let onInvalid: () -> Void

    func makeNSView(context: Context) -> RecorderView { RecorderView() }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onShortcut = onShortcut
        view.onCancel = onCancel
        view.onInvalid = onInvalid
        view.setRecording(isRecording)
    }

    static func dismantleNSView(_ view: RecorderView, coordinator: ()) {
        view.prepareForRemoval()
    }

    final class RecorderView: NSView {
        var onShortcut: (GlobalHotKey) -> Void = { _ in }
        var onCancel: () -> Void = {}
        var onInvalid: () -> Void = {}
        private var isRecording = false
        private var windowObservation: NSObjectProtocol?

        override var acceptsFirstResponder: Bool { isRecording }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeWindowObservation()
            if let window {
                windowObservation = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelRecording() }
                }
            }
            requestFocusIfNeeded()
        }

        func setRecording(_ recording: Bool) {
            guard recording != isRecording else { return }
            isRecording = recording
            if recording { requestFocusIfNeeded() }
            else if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        }

        func prepareForRemoval() {
            isRecording = false
            removeWindowObservation()
            if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned, isRecording {
                isRecording = false
                onCancel()
            }
            return resigned
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording, window?.firstResponder === self else {
                return super.performKeyEquivalent(with: event)
            }
            return capture(event)
        }

        override func keyDown(with event: NSEvent) {
            if !capture(event) { super.keyDown(with: event) }
        }

        private func capture(_ event: NSEvent) -> Bool {
            guard isRecording, event.type == .keyDown else { return false }
            guard !event.isARepeat else { return true }
            let modifiers = GlobalHotKey.Modifiers(eventFlags: event.modifierFlags)
            if modifiers.isEmpty, event.keyCode == 53 {
                cancelRecording()
                return true
            }
            if modifiers.isEmpty, event.keyCode == 48 {
                cancelRecording()
                return false
            }
            let hotKey = GlobalHotKey(keyCode: event.keyCode, modifiers: modifiers)
            if hotKey.isValid { onShortcut(hotKey) }
            else { onInvalid() }
            return true
        }

        private func requestFocusIfNeeded() {
            guard isRecording else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, isRecording, let window, window.isKeyWindow else { return }
                if !window.makeFirstResponder(self) { cancelRecording() }
            }
        }

        private func cancelRecording() {
            guard isRecording else { return }
            isRecording = false
            if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            onCancel()
        }

        private func removeWindowObservation() {
            if let windowObservation {
                NotificationCenter.default.removeObserver(windowObservation)
                self.windowObservation = nil
            }
        }
    }
}
