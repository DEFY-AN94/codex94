import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var controller: AppUpdateController

    var body: some View {
        SettingsRow("updates.title") {
            VStack(alignment: .leading, spacing: 10) {
                Button("updates.check") { controller.checkForUpdates() }
                    .disabled(!controller.canCheckForUpdates)
                    .accessibilityIdentifier("check-for-app-updates")
                status
                Text("updates.manualOnly")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-update-settings")
    }

    @ViewBuilder
    private var status: some View {
        switch controller.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("updates.checking").font(.caption)
            }
        case .upToDate:
            Text("updates.upToDate").foregroundStyle(.secondary)
        case let .failed(issue):
            Text(LocalizedStringKey(issue.localizationKey))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("app-update-error")
        case let .available(release):
            Text("updates.available").font(.headline)
            Text(verbatim: release.tagName)
                .font(.system(.body, design: .monospaced))
                .accessibilityIdentifier("app-update-version")
            Link("updates.openRelease", destination: release.pageURL)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("open-app-release")
            if !release.notes.isEmpty {
                DisclosureGroup("updates.releaseNotes") {
                    ScrollView {
                        Text(verbatim: release.notes)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
    }
}
