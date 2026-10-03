import SwiftUI

struct ClaudeStatuslineSetupView: View {
    @ObservedObject var store: ClaudeQuotaStore
    @State private var preview: ClaudeStatuslineInstallPreview?
    @State private var showingPreview = false
    @State private var confirmation: SetupConfirmation?
    @State private var operationIssue: ClaudeQuotaIssue?
    @State private var forgetFailed = false
    @State private var successMessage: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("claude.setup.help")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.statuslineSetupState == .conflict {
                VStack(alignment: .leading, spacing: 5) {
                    Label("claude.setup.conflict", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.medium)).foregroundStyle(.orange)
                    Text("claude.setup.conflictHelp")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("claude-setup-conflict")
            }
            HStack(spacing: 12) {
                Button("claude.setup.preview") {
                    clearFeedback()
                    do {
                        preview = try store.previewStatuslineInstall()
                        showingPreview = true
                    } catch {
                        operationIssue = error as? ClaudeQuotaIssue ?? .unavailable
                        store.refreshSetupState()
                    }
                }
                .disabled(store.statuslineSetupState != .notInstalled)
                .accessibilityIdentifier("claude-setup-preview")
                if store.statuslineSetupState == .installed {
                    Button("claude.setup.remove", role: .destructive) { confirmation = .remove }
                        .accessibilityIdentifier("claude-setup-remove")
                } else if store.statuslineSetupState == .conflict {
                    Button("claude.setup.forgetRecord", role: .destructive) { confirmation = .forgetRecord }
                        .accessibilityIdentifier("claude-setup-forget-record")
                }
            }
            if store.statuslineSetupState == .installed {
                Text("claude.setup.installed")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("claude-setup-installed")
            }
            if let operationIssue {
                Text(forgetFailed ? "claude.setup.forgetFailed" : operationIssue.localizedKey)
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("claude-setup-issue")
            } else if let successMessage {
                Text(successMessage)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("claude-setup-saved")
            }
        }
        .onAppear { store.refreshSetupState() }
        .sheet(isPresented: $showingPreview) {
            if let preview {
                ClaudeStatuslinePreviewView(preview: preview) {
                    clearFeedback()
                    defer { showingPreview = false; store.refreshSetupState() }
                    do {
                        try store.installStatusline(preview)
                        successMessage = "claude.setup.saved"
                    } catch {
                        operationIssue = error as? ClaudeQuotaIssue ?? .unavailable
                    }
                } cancel: {
                    showingPreview = false
                }
            }
        }
        .confirmationDialog(
            confirmation?.titleKey ?? "claude.setup.removeConfirm",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible
        ) {
            if let action = confirmation {
                Button(action.actionKey, role: .destructive) { perform(action) }
                    .accessibilityIdentifier(action == .forgetRecord
                        ? "claude-setup-confirm-forget-record" : "claude-setup-confirm-remove")
            }
            Button("claude.setup.cancel", role: .cancel) { confirmation = nil }
        } message: {
            Text(confirmation?.messageKey ?? "claude.setup.removeHelp")
        }
    }

    private func clearFeedback() {
        operationIssue = nil
        forgetFailed = false
        successMessage = nil
    }

    private func perform(_ action: SetupConfirmation) {
        clearFeedback()
        defer { confirmation = nil; store.refreshSetupState() }
        do {
            switch action {
            case .remove:
                try store.removeStatusline()
                successMessage = "claude.setup.saved"
            case .forgetRecord:
                try store.forgetConflictingStatuslineInstallation()
                successMessage = "claude.setup.recordForgotten"
            }
        } catch {
            operationIssue = error as? ClaudeQuotaIssue ?? .unavailable
            forgetFailed = action == .forgetRecord && operationIssue == .configurationConflict
        }
    }

    private enum SetupConfirmation: Equatable {
        case remove, forgetRecord
        var titleKey: LocalizedStringKey {
            self == .remove ? "claude.setup.removeConfirm" : "claude.setup.forgetConfirm"
        }
        var messageKey: LocalizedStringKey {
            self == .remove ? "claude.setup.removeHelp" : "claude.setup.forgetHelp"
        }
        var actionKey: LocalizedStringKey {
            self == .remove ? "claude.setup.remove" : "claude.setup.forgetRecord"
        }
    }
}

struct ClaudeStatuslinePreviewView: View {
    let preview: ClaudeStatuslineInstallPreview
    let install: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("claude.setup.previewTitle").font(.title2.weight(.semibold))
            Text("claude.setup.previewHelp")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("claude.setup.settingsFile").font(.caption.weight(.medium))
                Text(verbatim: preview.settingsURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            }
            if let command = preview.originalCommand {
                commandBlock("claude.setup.existingCommand", command: command)
            }
            commandBlock("claude.setup.bridgeCommand", command: preview.bridgeCommand)
            Text(preview.preservesExistingStatusline ? "claude.setup.preservesExisting" : "claude.setup.noExisting")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("claude.setup.cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("claude.setup.install", action: install)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("claude-setup-confirm-install")
            }
        }
        .padding(24)
        .frame(width: 520)
        .accessibilityIdentifier("claude-setup-preview-sheet")
    }

    private func commandBlock(_ title: LocalizedStringKey, command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium))
            ScrollView {
                Text(verbatim: command)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 110)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
