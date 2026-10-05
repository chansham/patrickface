import SwiftUI

@MainActor struct PatrickPhoneExperienceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var player = PatrickAnimationPlayer()
    @StateObject private var feedback = PatrickFeedback()
    @StateObject private var clockArtwork = PatrickClockArtwork()
    @State private var outfits: [PatrickOutfitCatalog.Outfit] = []
    @State private var restingID: String?
    @State private var visible = false
    @State private var showSettings = false
    private var active: Bool { visible && scenePhase == .active && !showSettings }
    private var scene: String {
        if model.experience.settings.scene != .automatic { return model.experience.settings.scene.rawValue }
        if let value = model.experience.activity, value.status == .running { return value.kind == .exercise ? "exercise" : "focus" }
        return model.experience.settings.isSleepTime(.now) ? "sleeping" : "awake"
    }
    private var outfit: PatrickOutfitCatalog.Outfit? {
        PatrickExperienceResources.outfit(model.experience.settings, scene: scene, from: outfits)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TimelineView(.everyMinute) { tick in
                        VStack(spacing: 5) {
                            Text(time(tick.date)).font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
                            if model.experience.settings.showDate { Text(tick.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary) }
                        }
                    }
                    GeometryReader { geo in
                        let side = min(geo.size.width, geo.size.height)
                        if model.experience.settings.ambienceEnabled {
                            PatrickSceneAmbience(scene: scene, motionAllowed: active && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled)
                        }
                        if model.experience.settings.faceMode == .arms && clockArtwork.manifest != nil && !player.isPlaying {
                            PatrickOrganicClock(artwork: clockArtwork, dimmed: false)
                                .frame(width: side, height: side * 496 / 416)
                                .offset(y: -side * 0.19)
                        } else if let image = player.image {
                            let w = side * CGFloat(min(1, player.cellAspectRatio) * player.drawingScale)
                            let h = side * CGFloat(min(1, 1 / player.cellAspectRatio) * player.drawingScale)
                            Image(decorative: image, scale: 1).resizable().interpolation(.high)
                                .frame(width: w, height: h)
                                .position(x: side * CGFloat(player.masterAnchor[0]) + w * CGFloat(0.5 - player.anchor[0]),
                                          y: side * CGFloat(player.masterAnchor[1]) + h * CGFloat(0.5 - player.anchor[1]))
                        } else { Text("這套造型的素材尚未載入").frame(width: side, height: side) }
                    }.frame(width: 300, height: 300).clipped()
                        .contentShape(Rectangle()).onTapGesture { model.performCare(.pet) }
                        .accessibilityLabel("摸摸派大星").accessibilityAddTraits(.isButton)
                    Text("\(outfit?.title ?? "派大星") · \(model.experience.settings.mood.title)").font(.headline)
                    Text(player.message).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        ForEach(PatrickCareAction.allCases) { action in
                            Button(action.title) { model.performCare(action) }.buttonStyle(.borderedProminent)
                        }
                    }
                    HStack { Text("飽足 \(Int(model.experience.care.satiety.rounded()))"); Spacer(); Text("親密 \(model.experience.care.bond)") }
                    Picker("角色心情", selection: setting(\.mood)) { ForEach(PatrickMood.allCases) { Text($0.title).tag($0) } }
                    Picker("陪伴情境", selection: setting(\.scene)) { ForEach(PatrickExperienceScene.allCases) { Text($0.title).tag($0) } }
                    Picker("衣服", selection: setting(\.outfitID)) {
                        Text("跟隨情境").tag("auto")
                        ForEach(outfits.filter { $0.id != "auto" }) { Text($0.title).tag($0.id) }
                    }
                    Menu("這套造型的動作") {
                        ForEach(player.clips.filter { Set(outfit?.actions?.values.flatMap { $0.clips } ?? []).contains($0.id) }) { clip in
                            Button(clip.title) { player.play(clip.id) }.disabled(player.unavailableReason(for: clip) != nil || reduceMotion)
                        }
                    }.buttonStyle(.bordered)
                    Button("同步到手錶") { model.syncNow() }.buttonStyle(.bordered)
                    Text(model.watchSync.linkState.detail).font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近陪伴").font(.headline)
                        ForEach(model.experience.journal.suffix(8).reversed()) { entry in
                            Text("\(entry.at.formatted(date: .abbreviated, time: .shortened)) · \(entry.text)").font(.caption)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding()
            }.navigationTitle("派大星陪你")
                .toolbar { Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("設定") }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        Form {
                            Toggle("音效", isOn: setting(\.soundEnabled))
                            Toggle("觸覺", isOn: setting(\.hapticsEnabled))
                            Toggle("24小時制", isOn: setting(\.use24Hour))
                            Toggle("顯示日期", isOn: setting(\.showDate))
                            Toggle("場景點綴", isOn: setting(\.ambienceEnabled))
                            Picker("讀時", selection: setting(\.faceMode)) { ForEach(PatrickFaceMode.allCases) { Text($0.title).tag($0) } }
                            if clockArtwork.manifest == nil { Text(clockArtwork.message).font(.footnote) }
                            PatrickSchedulePreferences(settings: Binding(get: { model.experience.settings }, set: { value in model.updateExperience { $0.settings = value } }))
                            Text("手臂時計使用原味造型；動作時顯示所選衣服。運動是陪伴倒數；心情由你選。聲音只在App前景播放。").font(.footnote)
                        }.navigationTitle("設定").toolbar { Button("完成") { showSettings = false } }
                    }
                }
        }
        .onAppear {
            visible = true; outfits = PatrickExperienceResources.outfits(); player.load(); clockArtwork.load(); configure()
            player.onClipStarted = { id in
                guard !id.hasPrefix("idle-blink-") else { return }; feedback.play(id, settings: model.experience.settings, active: active && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled) }
        }
        .onDisappear { visible = false; player.suspend(); feedback.stop() }
        .onChange(of: scenePhase) { _, _ in configure(); if !active { feedback.stop() } }
        .onChange(of: showSettings) { _, _ in configure(); if !active { feedback.stop() } }
        .onChange(of: reduceMotion) { _, _ in configure(); if reduceMotion { feedback.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in configure(); if ProcessInfo.processInfo.isLowPowerModeEnabled { feedback.stop() } }
        .onChange(of: model.experience.settings) { _, _ in configure(); if !model.experience.settings.soundEnabled { feedback.stop() } }
        .onChange(of: model.experience.settings.scene) { _, next in
            configure(); if next == .bath || next == .celebrate { player.playEvent(next.rawValue) }
        }
        .onChange(of: model.calendarCelebrationSequence) { _, _ in player.playEvent("celebrate") }
        .onChange(of: model.actionSequence) { _, _ in
            if let action = model.requestedCare {
                player.playEvent(action.clipID)
                if !player.isPlaying || player.currentClipID?.hasPrefix("idle-blink-") == true { feedback.play(action.rawValue, settings: model.experience.settings, active: active && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled) }
            }
        }
        .task(id: active) {
            guard active else { return }
            while !Task.isCancelled {
                model.refreshExperience(allowEffects: !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled); configure()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    private func configure() {
        if !active || reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled { model.refreshExperience() }
        player.eventClips = PatrickExperienceResources.eventClips(model.experience.settings, outfit: outfit, from: outfits)
        player.idleClips = outfit?.idleClips ?? []
        if restingID != outfit?.clipId { restingID = outfit?.clipId; _ = player.selectRestingClip(restingID) }
        player.update(PatrickAnimationContext(active: active, reduceMotion: reduceMotion,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, sleeping: scene == "sleeping",
            charging: scene == "charging", focusing: scene == "focus", exercising: scene == "exercise", completedTimerID: model.completedActivityID))
    }
    private func setting<Value>(_ key: WritableKeyPath<PatrickExperienceSettings, Value>) -> Binding<Value> {
        Binding(get: { model.experience.settings[keyPath: key] }, set: { value in model.updateExperience { $0.settings[keyPath: key] = value } })
    }
    private func time(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date), hour = parts.hour ?? 0
        return String(format: "%02d:%02d", model.experience.settings.use24Hour ? hour : (hour % 12 == 0 ? 12 : hour % 12), parts.minute ?? 0)
    }
}
