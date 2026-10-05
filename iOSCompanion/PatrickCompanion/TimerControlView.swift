import SwiftUI

struct TimerControlView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var kind: PatrickActivityKind = .focus
    @State private var minutes = 25
    var body: some View {
        NavigationStack {
            Form {
                Section("一起做一件事") {
                    Picker("種類", selection: $kind) { ForEach(PatrickActivityKind.allCases) { Text($0.title).tag($0) } }
                    Stepper("\(minutes)分鐘", value: $minutes, in: 1...120)
                    if let activity = model.experience.activity, activity.status == .running || activity.status == .paused {
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            let seconds = Int(activity.remaining(at: tick.date))
                            Text("\(activity.kind.title) · \(seconds / 60):\(String(format: "%02d", seconds % 60))")
                                .font(.largeTitle.monospacedDigit())
                        }
                        Button(activity.status == .paused ? "繼續" : "暫停") { Task { await model.toggleExperiencePause() } }
                        Button("結束計時", role: .destructive) { Task { await model.cancelExperienceActivity() } }
                    } else {
                        Button("開始陪伴") { Task { await model.startExperienceActivity(kind, minutes: minutes) } }
                    }
                    Text("這是陪伴倒數，不記錄心率、距離或Apple健身訓練。").font(.footnote).foregroundStyle(.secondary)
                }
                if let activity = model.experience.activity, activity.status == .completed { Text("已完成\(activity.kind.title)") }
                Section("手機與手錶") {
                    Text("設定會送到配對手錶；離線時等待傳送。倒數依結束時間計算，重開App仍可恢復。").font(.footnote)
                    Button("同步現在狀態") { model.syncNow() }
                }
            }.navigationTitle("陪伴計時")
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                model.refreshExperience()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
