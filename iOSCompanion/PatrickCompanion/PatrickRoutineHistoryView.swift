import SwiftUI

struct PatrickRoutineHistoryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var runs = PatrickRoutineStore.shared.load()
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("晚安流程紀錄").font(.headline)
                    Text("查看這次卡在哪一步。系統設定顯示捷徑回報，派大星顯示手機 App 結果；手錶是否同步仍需確認。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if runs.isEmpty {
                    Section("還沒有執行紀錄") {
                        Text("在你的晚安捷徑中加入「開始晚安流程紀錄」，把它回傳的編號傳给每一步回報，再以「讀取晚安流程結果」收尾。")
                        Text("若捷徑中途停止，未回報的步驟會留在這裡。這個頁面不會自行設定專注或鬧鐘。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(runs.reversed()) { run in
                    Section {
                        Text(run.summary).font(.headline)
                        ForEach(run.steps) { step in
                            HStack(alignment: .top) {
                                Image(systemName: symbol(step.status)).foregroundStyle(color(step.status))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.stepID.title)
                                    Text(label(step.status) + (step.attempt > 1 ? " · 第\(step.attempt)次" : ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let note = step.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        Text("手錶專注與派大星狀態尚未確認").font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Text(Date(timeIntervalSince1970: run.createdAtMS / 1000), style: .date)
                            + Text(" · ") + Text(Date(timeIntervalSince1970: run.createdAtMS / 1000), style: .time)
                    } footer: {
                        Text("流程編號：\(run.id.uuidString)").textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("生活流程")
            .toolbar { Button("清除紀錄", role: .destructive) { confirmClear = true }.disabled(runs.isEmpty) }
            .alert("清除流程紀錄？", isPresented: $confirmClear) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) { PatrickRoutineStore.shared.clear(); reload() }
            } message: { Text("只清除本機紀錄，不改動專注、鬧鐘或派大星狀態。") }
            .onReceive(NotificationCenter.default.publisher(for: PatrickRoutineStore.changed)) { _ in reload() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
            .onAppear { reload() }
        }
    }
    private func reload() { runs = PatrickRoutineStore.shared.load() }
    private func label(_ status: PatrickRoutineRun.Status) -> String {
        switch status { case .pending: "尚無回報"; case .succeeded: "已回報完成"; case .failed: "未完成"; case .skipped: "未選用" }
    }
    private func symbol(_ status: PatrickRoutineRun.Status) -> String {
        switch status { case .pending: "clock"; case .succeeded: "checkmark.circle"; case .failed: "exclamationmark.circle"; case .skipped: "minus.circle" }
    }
    private func color(_ status: PatrickRoutineRun.Status) -> Color {
        switch status { case .pending: .secondary; case .succeeded: .green; case .failed: .orange; case .skipped: .secondary }
    }
}
