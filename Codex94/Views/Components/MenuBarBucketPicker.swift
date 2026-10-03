import SwiftUI

struct MenuBarBucketPicker: View {
    @ObservedObject var store: AppStore
    var provider: QuotaProviderID = .codex
    private var snapshot: QuotaSnapshot? { store.providerSnapshot(for: provider) }
    private var selection: MenuBarBucketSelection {
        provider == .codex ? store.preferences.dualWindowBucketSelection : store.preferences.claudeDualWindowBucketSelection
    }

    var body: some View {
        let options = MenuBarBucketOption.options(in: snapshot, selected: selection)
        HStack(spacing: 8) {
            Picker("display.dualWindow.bucket", selection: Binding(
                get: { selection },
                set: { store.setDualWindowBucketSelection($0, for: provider) }
            )) {
                ForEach(options) { option in
                    Text(verbatim: optionLabel(option))
                        .help(Text(verbatim: optionLabel(option, abbreviated: false)))
                        .accessibilityLabel(Text(verbatim: optionLabel(option, abbreviated: false)))
                        .tag(option.selection)
                        .disabled(!option.isAvailable)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityIdentifier(provider == .codex ? "dual-window-bucket-picker" : "claude-dual-window-bucket-picker")

            if options.contains(where: { $0.selection == selection && !$0.isAvailable }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("display.selectionUnavailable")
                    .accessibilityLabel(Text("display.selectionUnavailable"))
            }
        }
    }

    func optionLabel(_ option: MenuBarBucketOption, abbreviated: Bool = true) -> String {
        func localized(_ key: String) -> String {
            StatusAccessibilityString.localized(key, language: store.preferences.language, bundle: .main)
        }
        guard option.selection != .automatic else { return localized("display.auto") }
        let suffix = option.isAvailable ? "" : " · " + localized("status.unavailable")
        let fullName = option.bucketName ?? localized("display.savedQuota")
        guard abbreviated else { return fullName + suffix }

        let limit = max(1, 30 - suffix.count)
        let names = snapshot.map { QuotaFormatting.bucketMenuNames(in: $0, limit: limit) } ?? [:]
        let bucketID: String?
        switch option.selection {
        case .automatic: bucketID = nil
        case .defaultBucket: bucketID = snapshot?.defaultLimitID
        case let .bucket(limitID): bucketID = limitID
        }
        let name = bucketID.flatMap { names[$0] } ?? QuotaFormatting.shortBucketName(fullName, limit: limit)
        return name + suffix
    }
}
