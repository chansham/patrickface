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

                Section("手錶最後電量觀測") {
                    WatchBatteryObservationCard(sync: model.watchSync)
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
                Text("Theme, timer, demo, routine history, watch battery observation, and message-deduplication state will be removed.")
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

private struct WatchBatteryObservationCard: View {
    @ObservedObject var sync: WatchSyncService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 6) {
                if sync.linkState == .demo {
                    Text("示範模式不提供真實手錶電量。")
                } else if let receipt = sync.lastWatchStatus {
                    Text("最後觀測：\(chargingTitle(receipt.observation.chargingState))")
                        .font(.headline)
                    if let level = receipt.observation.batteryLevel {
                        Text("當時電量 \(Int((level * 100).rounded()))%")
                    } else {
                        Text("當時電量未知")
                    }
                    switch receipt.freshness(at: context.date) {
                    case .recent:
                        Text("最近 5 分鐘內的觀測；不是即時狀態。")
                    case .stale:
                        Text("觀測已過期，目前是否充電未知。")
                            .foregroundStyle(.orange)
                    case .clockMismatch:
                        Text("裝置時間不一致，無法判斷新舊。")
                            .foregroundStyle(.orange)
                    }
                    Text("手錶觀測：\(receipt.observation.observedAt.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                    Text("手機收到：\(receipt.receivedAt.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                } else {
                    Text("尚未收到手錶觀測，目前電量與充電狀態未知。")
                }
                if let issue = sync.watchStatusIssue, sync.linkState != .demo {
                    Text(issue).foregroundStyle(.orange)
                }
                Text("開啟手錶上的派大星並保持畫面亮起時才會觀測；背景傳送可能延遲。充電預覽不會變成真實電量。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chargingTitle(_ state: PatrickWatchStatusObservation.ChargingState) -> String {
        switch state {
        case .unknown: "充電狀態未知"
        case .unplugged: "未接上充電器"
        case .charging: "正在充電"
        case .full: "已充滿"
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
