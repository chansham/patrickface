import SwiftUI

struct TimerControlView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var kind: PatrickActivityKind = .focus
    @State private var minutes = 25
    @State private var breakMinutes = 3
    @State private var confirmDiscard = false
    var body: some View {
        NavigationStack {
            Form {
                Section("一起做一件事") {
                    Picker("種類", selection: $kind) { ForEach(PatrickActivityKind.allCases) { Text($0.title).tag($0) } }
                    Stepper("\(minutes)分鐘", value: $minutes, in: 1...120)
                    if kind.isExercise {
                        Text("散步、跑步與肌力是陪伴倒數的種類，目前共用運動造型。").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let activity = model.experience.activity, activity.status == .running || activity.status == .paused {
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            let seconds = Int(activity.remaining(at: tick.date))
                            Text("\(activity.kind.title) · \(seconds / 60):\(String(format: "%02d", seconds % 60))")
                                .font(.largeTitle.monospacedDigit())
                        }
                        Button(activity.status == .paused ? "繼續" : "暫停") { Task { await model.toggleExperiencePause() } }
                        Button("結束計時", role: .destructive) { Task { await model.cancelExperienceActivity() } }
                    } else if model.experience.breakSession == nil {
                        Button("開始陪伴") { Task { await model.startExperienceActivity(kind, minutes: minutes) } }
                    }
                    Text("這是陪伴倒數，不記錄心率、距離或Apple健身訓練。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("休息與接續") {
                    if let saved = model.experience.breakSession {
                        let seconds = Int(saved.savedActivity.remainingSeconds.rounded(.up))
                        Text("已保存\(saved.savedActivity.kind.title) · \(seconds / 60):\(String(format: "%02d", seconds % 60))")
                        Text(saved.resumeOnReturn ? "按返回才繼續原倒數；休息結束不會自動開始。" : "原活動本來已暫停；返回後仍會保持暫停。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("返回原活動") { model.manageBreak(.returnToActivity) }
                        Button("放棄原活動", role: .destructive) { confirmDiscard = true }
                    } else if let activity = model.experience.activity, activity.status == .running || activity.status == .paused {
                        Picker("休息時間", selection: $breakMinutes) { ForEach([1, 3, 5], id: \.self) { Text("\($0)分鐘").tag($0) } }
                        Button("保存進度，休息一下") { model.manageBreak(.begin(minutes: breakMinutes)) }
                    } else { Text("先開始一段活動，便可保存進度去休息。").font(.footnote) }
                    if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }
                if let activity = model.experience.activity, activity.status == .completed { Text("已完成\(activity.kind.title)") }
                Section("手機與手錶") {
                    Text("設定會送到配對手錶；離線時等待傳送。倒數依結束時間計算，重開App仍可恢復。").font(.footnote)
                    Button("同步現在狀態") { model.syncNow() }
                }
            }.navigationTitle("陪伴計時")
                .confirmationDialog("放棄保存的原活動？當前休息計時會保留。", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("放棄原活動", role: .destructive) { model.manageBreak(.discardSaved) }
                }
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
