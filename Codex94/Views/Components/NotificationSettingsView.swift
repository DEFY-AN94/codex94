import AppKit
import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var store: AppStore
    var provider: QuotaProviderID = .codex

    var body: some View {
        NotificationSettingsContent(
            store: store,
            controller: provider == .codex ? store.notificationController : store.claudeStore.notificationController,
            provider: provider
        )
    }
}

private struct NotificationSettingsContent: View {
    @ObservedObject var store: AppStore
    @ObservedObject var controller: NotificationController
    let provider: QuotaProviderID

    private var preferences: NotificationPreferences {
        provider == .codex ? store.preferences.notifications : store.preferences.claudeNotifications
    }

    var body: some View {
        SettingsRow(provider == .codex ? "notifications.settings" : "claude.notifications.settings") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("notifications.enable", isOn: binding(\.isEnabled))
                    .accessibilityIdentifier(provider == .codex ? "quota-notifications-enabled" : "claude-notifications-enabled")
                if preferences.isEnabled {
                    Toggle("quota.fiveHourShort", isOn: binding(\.fiveHourEnabled))
                    Toggle("quota.weeklyShort", isOn: binding(\.weeklyEnabled))
                    thresholdPicker("notifications.threshold.first", keyPath: \.warningThreshold)
                    thresholdPicker("notifications.threshold.second", keyPath: \.criticalThreshold)
                    Toggle("notifications.recovery", isOn: binding(\.recoveryEnabled))
                    Text(provider == .codex ? "notifications.defaultBucket" : "claude.notifications.defaultBucket")
                        .font(.caption).foregroundStyle(.secondary)
                    if let snapshot = store.providerSnapshot(for: provider) {
                        ForEach(snapshot.displayableBuckets.filter { $0.limitID != snapshot.defaultLimitID }) { bucket in
                            Toggle(snapshot.displayName(for: bucket), isOn: Binding(
                                get: { preferences.additionalBucketIDs.contains(bucket.limitID) },
                                set: { enabled in
                                    var value = preferences
                                    if enabled { value.additionalBucketIDs.insert(bucket.limitID) }
                                    else { value.additionalBucketIDs.remove(bucket.limitID) }
                                    store.setNotificationPreferences(value, for: provider)
                                }
                            ))
                        }
                    }
                    if controller.isRequesting { ProgressView().controlSize(.small) }
                    if controller.authorization == .denied {
                        Text("notifications.denied")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if controller.authorization == .notDetermined {
                        Button("notifications.allow") { store.requestNotificationPermission(for: provider) }
                    }
                    if controller.hasIssue {
                        Text("notifications.failed").font(.caption).foregroundStyle(.red)
                    }
                }
                Text("notifications.help")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshNotificationAuthorization(for: provider)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<NotificationPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { newValue in
                var value = preferences
                value[keyPath: keyPath] = newValue
                store.setNotificationPreferences(value, for: provider)
            }
        )
    }

    private func thresholdPicker(
        _ label: LocalizedStringKey,
        keyPath: WritableKeyPath<NotificationPreferences, Int>
    ) -> some View {
        Picker(label, selection: binding(keyPath)) {
            ForEach(NotificationPreferences.thresholdOptions, id: \.self) { value in
                if value == 0 { Text("notifications.threshold.off").tag(value) }
                else { Text(verbatim: "\(value)%").tag(value) }
            }
        }
        .frame(maxWidth: 280)
    }
}
