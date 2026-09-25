import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section("WatchConnectivity") {
                    WatchStatusCard(sync: model.watchSync)

                    Button {
                        model.syncNow()
                    } label: {
                        Label("Send Current Snapshot", systemImage: "arrow.up.circle")
                    }
                }

                Section("Device-free inspection") {
                    Toggle(
                        "Demo watch",
                        isOn: Binding(
                            get: { model.settings.demoMode },
                            set: model.setDemoMode
                        )
                    )
                    Text(
                        "Demo mode exercises the same command envelopes and returns "
                        + "a local acknowledgement after a short delay."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Label("Settings stay in the local App Group", systemImage: "lock.fill")
                    Label("No analytics or advertising SDK", systemImage: "hand.raised.fill")
                    Label("No account, location, contacts, or health data", systemImage: "person.crop.circle.badge.checkmark")

                    Button("Reset Local Data", role: .destructive) {
                        confirmReset = true
                    }
                }

                Section("Official-channel limits") {
                    Text(
                        "This app controls Patrick content inside the Patrick iPhone "
                        + "and watch apps. It cannot replace the iOS theme, install a "
                        + "third-party system watch face, or bypass watchOS foreground rules."
                    )
                    Text(
                        "“Open Watch Face” requests the custom in-app face. Public APIs "
                        + "do not let an iPhone app select a system watch face or guarantee "
                        + "launching an arbitrary watch app."
                    )
                    Text(
                        "NFC support is through a user-created Shortcuts Personal "
                        + "Automation that runs one of the included App Intents."
                    )
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Section("Deep links") {
                    deepLinkRow(
                        "Control Center",
                        PatrickDeepLinkRoute.controlCenter.url
                    )
                    deepLinkRow(
                        "1999 CEL",
                        PatrickDeepLinkRoute.setTheme(.cel1999).url
                    )
                    deepLinkRow(
                        "Faithful 3D",
                        PatrickDeepLinkRoute.setTheme(.faithful3D).url
                    )
                    deepLinkRow(
                        "Open in-app face",
                        PatrickDeepLinkRoute.openWatchFace.url
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Status")
            .alert("Reset local data?", isPresented: $confirmReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    model.resetLocalData()
                }
            } message: {
                Text("Theme, timer, demo, and message-deduplication state will be removed.")
            }
        }
    }

    private func deepLinkRow(_ title: String, _ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(url.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct WatchStatusCard: View {
    @ObservedObject var sync: WatchSyncService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(sync.linkState.title, systemImage: symbolName)
                .font(.headline)
                .foregroundStyle(tint)
            Text(sync.linkState.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let acknowledgement = sync.lastAcknowledgement {
                Divider()
                Text(acknowledgement)
                    .font(.caption)
            }

            if let date = sync.lastDeliveryAt {
                Text("Last delivery: \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var symbolName: String {
        switch sync.linkState {
        case .reachable, .demo: "checkmark.circle.fill"
        case .backgroundDelivery, .activating: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        default: "applewatch.slash"
        }
    }

    private var tint: Color {
        switch sync.linkState {
        case .reachable, .demo: .green
        case .backgroundDelivery, .activating: .orange
        case .failed: .red
        default: .secondary
        }
    }
}
