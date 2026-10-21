import SwiftUI

@MainActor struct PatrickPhoneExperienceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var player = PatrickAnimationPlayer()
    @StateObject private var feedback = PatrickFeedback()
    @ObservedObject private var haptics = PatrickHaptics.shared
    @StateObject private var clockArtwork = PatrickClockArtwork()
    @State private var outfits: [PatrickOutfitCatalog.Outfit] = []
    @State private var restingID: String?
    @State private var visible = false
    @State private var showSettings = false
    @State private var surpriseExpiresAt: Date?
    @State private var completionVisibility = PatrickCompletionVisibility()
    private var active: Bool { visible && scenePhase == .active && !showSettings }
    private var scene: String {
        let activity = model.experience.activity
        let running = activity?.status == .running
        UIDevice.current.isBatteryMonitoringEnabled = true
        let battery = UIDevice.current.batteryState
        return PatrickAutomaticScene.resolve(
            selection: model.experience.settings.scene,
            activitySceneID: running ? activity?.kind.sceneID : nil,
            charging: battery == .charging || battery == .full,
            sleeping: model.experience.settings.isSleepTime(.now),
            focus: model.experience.settings.contextFocus == true,
            workout: running && activity?.kind.isExercise == true,
            meeting: model.experience.settings.contextMeeting == true
        )
    }
    private var outfit: PatrickOutfitCatalog.Outfit? {
        PatrickExperienceResources.outfit(model.experience.settings, scene: scene, from: outfits)
    }
    private var pageSurface: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        Color.black
                        if model.experience.settings.ambienceEnabled {
                            PatrickSceneAmbience(scene: scene, motionAllowed: active && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled)
                        }
                        if surpriseExpiresAt != nil && model.experience.settings.ambienceEnabled && active && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                            PatrickSceneAmbience(scene: "bath", motionAllowed: true)
                        }
                        PatrickLayoutFace(player: player, artwork: clockArtwork, experience: model.experience,
                                          active: active && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled)
                    }.aspectRatio(416.0 / 496.0, contentMode: .fit).frame(maxWidth: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 44))
                        .contentShape(Rectangle()).onTapGesture { model.performCare(.pet) }
                        .accessibilityLabel("摸摸派大星").accessibilityAddTraits(.isButton)
                    Text("\(outfit?.title ?? "派大星") · \(model.experience.displayedMood().title)").font(.headline)
                    Text("派大星叫你 \(model.experience.settings.greetingDisplayName)").font(.caption).foregroundStyle(.secondary)
                    Text(player.message).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("摸摸") { model.performCare(.pet) }.buttonStyle(.borderedProminent)
                        Button("陪 Sham 休息") { model.performCare(.rest) }.buttonStyle(.borderedProminent)
                    }
                    Button("找個小驚喜", action: findSurprise).buttonStyle(.bordered)
                    Button("我起床了") { model.reportWakeUp() }.buttonStyle(.bordered)
                    Text("起床回報只記錄這一刻。表情跟著今天，舊的飽足和親密還在存檔裡，不再顯示。").font(.caption).foregroundStyle(.secondary)
                    if let surprise = model.experience.surprise, !PatrickJournalFilter.hides(surprise.line) {
                        Text(surprise.line).font(.callout).multilineTextAlignment(.center)
                    }
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
                        Text("派大星寫的一天").font(.headline)
                        ForEach(model.experience.lifeJournal.suffix(8).reversed()) { entry in
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
                            Text("主動找你用敲三下，一天預設 6 次。完成、注意和安頓是另外三種。摸頭保持安靜。").font(.footnote)
                            Toggle("24小時制", isOn: setting(\.use24Hour))
                            Toggle("顯示日期", isOn: setting(\.showDate))
                            Toggle("場景點綴", isOn: setting(\.ambienceEnabled))
                            PatrickLayoutPicker(settings: Binding(get: { model.experience.settings }, set: { value in model.updateExperience { $0.settings = value } }))
                            Picker("讀時", selection: setting(\.faceMode)) { ForEach(PatrickFaceMode.allCases) { Text($0.title).tag($0) } }
                            if clockArtwork.manifest == nil { Text(clockArtwork.message).font(.footnote) }
                            PatrickSchedulePreferences(settings: Binding(get: { model.experience.settings }, set: { value in model.updateExperience { $0.settings = value } }))
                            Text("衣服預設跟著情境。手錶授權後會把運動寫進健康。聲音只在 App 前景播放，招呼只顯示文字。").font(.footnote)
                        }.navigationTitle("設定").toolbar { Button("完成") { showSettings = false } }
                    }
                }
        }
    }

    private var appearanceSurface: some View {
        pageSurface
        .onAppear {
            visible = true; outfits = PatrickExperienceResources.outfits(); player.load(); clockArtwork.load(); configure()
            player.onClipStarted = { id in
                guard !id.hasPrefix("idle-blink-") else { return }; feedback.play(id, settings: model.experience.settings, active: active && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled) }
        }
        .onDisappear {
            visible = false; _ = completionVisibility.update(allowsMotion: false)
            model.setSoundPresentationActive(false)
            model.setAutomationPresentationActive(false)
            surpriseExpiresAt = nil; player.suspend(); feedback.stop()
        }
        .onChange(of: scenePhase) { _, _ in configure(); if !active { feedback.stop() } }
        .onChange(of: showSettings) { _, _ in configure(); if !active { feedback.stop() } }
        .onChange(of: reduceMotion) { _, _ in configure(); if reduceMotion { feedback.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in configure(); if ProcessInfo.processInfo.isLowPowerModeEnabled { feedback.stop() } }
    }

    private var actionSurface: some View {
        appearanceSurface
        .onChange(of: model.experience.settings) { _, _ in configure(); if !model.experience.settings.soundEnabled { feedback.stop() } }
        .onChange(of: model.experience.settings.scene) { old, next in
            configure(); if next == .bath || next == .celebrate { player.playEvent(next.rawValue) }
            if next == .sleeping, old != .sleeping { haptics.play(.goodnight, settings: model.experience.settings, foreground: active) }
            if next == .awake, old == .sleeping { haptics.play(.wake, settings: model.experience.settings, foreground: active) }
        }
        .onChange(of: model.calendarCelebrationSequence) { _, _ in
            player.playEvent("celebrate")
            haptics.play(.celebrate, settings: model.experience.settings, foreground: active)
        }
        .onChange(of: model.automationSequence) { _, _ in
            configure()
            if let event = model.takeAutomationForPlayback() { player.playEvent(event.clipKey) }
        }
        .onChange(of: model.actionSequence) { _, _ in
            if let action = model.requestedCare {
                player.playEvent(action.clipID)
                if !player.isPlaying || player.currentClipID?.hasPrefix("idle-blink-") == true { feedback.play(action.rawValue, settings: model.experience.settings, active: active && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled) }
            }
        }
    }

    var body: some View {
        actionSurface
        .task(id: active) {
            guard active else { return }
            while !Task.isCancelled {
                configure()
                model.refreshExperience(allowEffects: !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled, announceCompletion: true)
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .task(id: surpriseExpiresAt) {
            guard surpriseExpiresAt != nil else { return }
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            surpriseExpiresAt = nil
        }
    }
    private func findSurprise() {
        guard model.findSurprise(), active, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        surpriseExpiresAt = .now.addingTimeInterval(3)
        if let id = outfit?.surpriseClipID,
           let clip = player.clips.first(where: { $0.id == id }),
           player.unavailableReason(for: clip) == nil, clip.durationsMs.reduce(0, +) <= 10_000 {
            player.play(id)
        }
        if !player.isPlaying || player.currentClipID?.hasPrefix("idle-blink-") == true {
            feedback.play("bubble", settings: model.experience.settings, active: true)
        }
    }
    private func configure() {
        let allowsMotion = active && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
        model.setAutomationPresentationActive(allowsMotion)
        model.setSoundPresentationActive(allowsMotion && model.experience.settings.soundEnabled)
        if !completionVisibility.update(allowsMotion: allowsMotion) {
            model.refreshExperience(allowEffects: false, observeCalendar: false)
        }
        if !active || reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled {
            surpriseExpiresAt = nil
            model.refreshExperience()
        }
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
