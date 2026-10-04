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
            Text("claude.passive.accountHelp")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("claude-passive-account-help")
            if store.passiveReportNeedsConfirmation {
                ClaudePassiveReportAdoptionView(
                    reportedAt: store.pendingPassiveReportedAt,
                    canAdopt: store.isEnabled,
                    adopt: { clearFeedback(); confirmation = .adoptReport }
                )
            }
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
        .onChange(of: store.isEnabled) { _, _ in dismissAdoptionConfirmation() }
        .onChange(of: store.passiveReportNeedsConfirmation) { _, needsConfirmation in
            if !needsConfirmation { dismissAdoptionConfirmation() }
        }
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
                Button(action.actionKey, role: action == .adoptReport ? nil : .destructive) { perform(action) }
                    .accessibilityIdentifier(action.accessibilityIdentifier)
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

    private func dismissAdoptionConfirmation() {
        if confirmation == .adoptReport { confirmation = nil }
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
            case .adoptReport:
                // The store owns the frozen pending report and may reject it
                // if expired. Its published state is the result, not a toast.
                guard store.isEnabled, store.passiveReportNeedsConfirmation else { return }
                store.adoptPendingPassiveReport()
            }
        } catch {
            operationIssue = error as? ClaudeQuotaIssue ?? .unavailable
            forgetFailed = action == .forgetRecord && operationIssue == .configurationConflict
        }
    }

    private enum SetupConfirmation: Equatable {
        case remove, forgetRecord, adoptReport
        var titleKey: LocalizedStringKey {
            switch self {
            case .remove: "claude.setup.removeConfirm"
            case .forgetRecord: "claude.setup.forgetConfirm"
            case .adoptReport: "claude.passive.adoptConfirm"
            }
        }
        var messageKey: LocalizedStringKey {
            switch self {
            case .remove: "claude.setup.removeHelp"
            case .forgetRecord: "claude.setup.forgetHelp"
            case .adoptReport: "claude.passive.adoptHelp"
            }
        }
        var actionKey: LocalizedStringKey {
            switch self {
            case .remove: "claude.setup.remove"
            case .forgetRecord: "claude.setup.forgetRecord"
            case .adoptReport: "claude.passive.adoptAction"
            }
        }
        var accessibilityIdentifier: String {
            switch self {
            case .remove: "claude-setup-confirm-remove"
            case .forgetRecord: "claude-setup-confirm-forget-record"
            case .adoptReport: "claude-passive-confirm-adopt"
            }
        }
    }
}

/// Only the pending report's local time enters this view; no session or account
/// identifier is presented as identity proof.
struct ClaudePassiveReportAdoptionView: View {
    let reportedAt: Date?
    let canAdopt: Bool
    let adopt: () -> Void
    var timeZone: TimeZone = .autoupdatingCurrent
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("claude.passive.pending", systemImage: "exclamationmark.circle")
                .font(.callout.weight(.medium)).foregroundStyle(.orange)
            if let reportedAt, let time = QuotaFormatting.absoluteReset(
                to: reportedAt, locale: locale,
                calendar: Calendar(identifier: .gregorian), timeZone: timeZone
            ) {
                Text("claude.passive.pendingTime \(time)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("claude-passive-pending-time")
            }
            Button("claude.passive.adopt", action: adopt)
                .disabled(!canAdopt)
                .accessibilityIdentifier("claude-passive-adopt-report")
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("claude-passive-pending-report")
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
