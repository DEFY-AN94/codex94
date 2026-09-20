import AppKit
import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        NotificationSettingsContent(store: store, controller: store.notificationController)
    }
}

private struct NotificationSettingsContent: View {
    @ObservedObject var store: AppStore
    @ObservedObject var controller: NotificationController

    var body: some View {
        SettingsRow("notifications.settings") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("notifications.enable", isOn: binding(\.isEnabled))
                    .accessibilityIdentifier("quota-notifications-enabled")
                if store.preferences.notifications.isEnabled {
                    Toggle("quota.fiveHourShort", isOn: binding(\.fiveHourEnabled))
                    Toggle("quota.weeklyShort", isOn: binding(\.weeklyEnabled))
                    thresholdPicker("notifications.threshold.first", keyPath: \.warningThreshold)
                    thresholdPicker("notifications.threshold.second", keyPath: \.criticalThreshold)
                    Toggle("notifications.recovery", isOn: binding(\.recoveryEnabled))
                    Text("notifications.defaultBucket")
                        .font(.caption).foregroundStyle(.secondary)
                    if let snapshot = store.snapshot {
                        ForEach(snapshot.displayableBuckets.filter { $0.limitID != snapshot.defaultLimitID }) { bucket in
                            Toggle(snapshot.displayName(for: bucket), isOn: Binding(
                                get: { store.preferences.notifications.additionalBucketIDs.contains(bucket.limitID) },
                                set: { enabled in
                                    var value = store.preferences.notifications
                                    if enabled { value.additionalBucketIDs.insert(bucket.limitID) }
                                    else { value.additionalBucketIDs.remove(bucket.limitID) }
                                    store.setNotificationPreferences(value)
                                }
                            ))
                        }
                    }
                    if controller.isRequesting { ProgressView().controlSize(.small) }
                    if controller.authorization == .denied {
                        Text("notifications.denied")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if controller.authorization == .notDetermined {
                        Button("notifications.allow") { store.requestNotificationPermission() }
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
            store.refreshNotificationAuthorization()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<NotificationPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.preferences.notifications[keyPath: keyPath] },
            set: { newValue in
                var value = store.preferences.notifications
                value[keyPath: keyPath] = newValue
                store.setNotificationPreferences(value)
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
