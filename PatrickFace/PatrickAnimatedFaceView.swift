import SwiftUI
import WatchKit

/// The 416:496 reference is an aspect ratio, never a physical-pixel point size.
@MainActor
struct PatrickAnimatedFaceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var wristDown
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: PatrickAppModel
    @StateObject private var player = PatrickAnimationPlayer()
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var showingActions = false
    @State private var requestedClip: String?
    @State private var visible = false
    @State private var timerTracker = PatrickAnimationTimerTracker()
    @StateObject private var feedback = PatrickFeedback()
    @StateObject private var clockArtwork = PatrickClockArtwork()
    @State private var outfits: [PatrickOutfitCatalog.Outfit] = []
    @State private var restingClipID: String?
    @State private var requestedCare: PatrickCareAction?
    @State private var activityKind: PatrickActivityKind = .focus
    @State private var activityMinutes = 5

    private var monitoring: Bool { visible && scenePhase == .active && !wristDown && !showingActions }

    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width / 416, geometry.size.height / 496)
            let width = 416 * unit, height = 496 * unit
            let square = width * 0.8
            ZStack(alignment: .topLeading) {
                Color.black
                if model.experience.settings.ambienceEnabled && !wristDown {
                    PatrickSceneAmbience(scene: resolvedScene, motionAllowed: monitoring && !reduceMotion && !lowPower)
                }
                if model.experience.settings.faceMode == .arms && clockArtwork.manifest != nil && !player.isPlaying {
                    PatrickOrganicClock(artwork: clockArtwork, dimmed: wristDown)
                        .frame(width: width, height: height)
                        .contentShape(Rectangle())
                        .onTapGesture { model.performCare(.pet) }
                        .onLongPressGesture(minimumDuration: 0.45) { showingActions = true }
                } else if let image = player.image {
                    let drawingWidth = square * CGFloat(min(1, player.cellAspectRatio) * player.drawingScale)
                    let drawingHeight = square * CGFloat(min(1, 1 / player.cellAspectRatio) * player.drawingScale)
                    // Same fixed square for every frame. No scale/rotation animation.
                    ZStack {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: drawingWidth, height: drawingHeight)
                            // Register source anchor to master; 0.88 is a baseline,
                            // not the centre of the image on the watch screen.
                            .position(x: square * CGFloat(player.masterAnchor[0]) + drawingWidth * CGFloat(0.5 - player.anchor[0]),
                                      y: square * CGFloat(player.masterAnchor[1]) + drawingHeight * CGFloat(0.5 - player.anchor[1]))
                    }
                    .frame(width: square, height: square)
                    .clipped()
                    .position(x: width * 0.5, y: height * 0.25 + square * 0.5)
                    .opacity(wristDown ? 0.55 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture { model.performCare(.pet) }
                    .onLongPressGesture(minimumDuration: 0.45) { showingActions = true }
                    .accessibilityLabel("摸摸派大星")
                    .accessibilityAddTraits(.isButton)
                } else {
                    Text("動作畫稿尚未準備")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: square, height: square)
                        .position(x: width * 0.5, y: height * 0.25 + square * 0.5)
                }
                PatrickIndependentClock(width: width, height: height, dimmed: wristDown, settings: model.experience.settings)
                    .allowsHitTesting(false)
                Text("\(model.experience.settings.mood.title) · \(player.isPlaying ? player.message : model.careNotice)")
                    .font(.system(size: max(8, width * 0.04)))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: width * 0.72)
                    .position(x: width * 0.46, y: height * 0.955)
                if scenePhase == .active && !wristDown {
                    Button { showingActions = true } label: {
                        Image(systemName: "ellipsis.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("動作選單")
                    .position(x: width * 0.9, y: height * 0.945)
                }
            }
            .frame(width: width, height: height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .contentShape(Rectangle())
            .accessibilityAction(named: Text("摸摸派大星")) { model.performCare(.pet) }
            .accessibilityAction(named: Text("餵一口")) { model.performCare(.feed) }
        }
        .background(.black)
        .ignoresSafeArea()
        .onAppear {
            visible = true
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
            player.load()
            clockArtwork.load()
            outfits = PatrickExperienceResources.outfits()
            player.onClipStarted = { id in
                guard !id.hasPrefix("idle-blink-") else { return }
                feedback.play(id, settings: model.experience.settings, active: monitoring && !reduceMotion && !lowPower)
            }
            model.refreshExperience(allowEffects: monitoring && !reduceMotion && !lowPower)
            refreshContext()
            configureOutfit()
            playRequestedClipIfVisible()
        }
        .onDisappear {
            visible = false
            player.suspend()
            feedback.stop()
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
        }
        .onChange(of: scenePhase) { _, _ in refreshContext(); if !monitoring { feedback.stop() } }
        .onChange(of: wristDown) { _, _ in refreshContext(); if wristDown { feedback.stop() } }
        .onChange(of: reduceMotion) { _, _ in refreshContext(); if reduceMotion { feedback.stop() } }
        .onChange(of: model.petScene) { _, _ in refreshContext() }
        .onChange(of: model.sleepMode) { _, _ in refreshContext() }
        .onChange(of: model.previewState) { _, _ in refreshContext() }
        .onChange(of: model.companionTimer) { _, _ in refreshContext() }
        .onChange(of: model.activationSequence) { _, _ in
            refreshContext()
            if let action = model.requestedAction {
                player.playEvent(action.clipID)
                if !player.isPlaying || player.currentClipID?.hasPrefix("idle-blink-") == true { feedback.play(action.rawValue, settings: model.experience.settings, active: monitoring && !reduceMotion && !lowPower) }
            }
        }
        .onChange(of: model.calendarCelebrationSequence) { _, _ in player.playEvent("celebrate") }
        .onChange(of: model.soundSequence) { _, _ in feedback.play("pet", settings: model.experience.settings, active: monitoring && !reduceMotion && !lowPower) }
        .onChange(of: model.experience.settings) { _, _ in refreshContext(); configureOutfit(); if !model.experience.settings.soundEnabled { feedback.stop() } }
        .onChange(of: model.experience.settings.scene) { _, next in
            refreshContext()
            let event = next == .sleeping ? "yawn" : next == .awake ? "wake" : next.rawValue
            if showingActions { requestedClip = player.eventClips?[event] }
            else if monitoring && (next == .bath || next == .celebrate) { player.playEvent(event) }
        }
        .onChange(of: model.experience.activity) { _, _ in refreshContext(); configureOutfit() }
        .onChange(of: model.status) { _, _ in configureOutfit() }
        .onChange(of: showingActions) { _, shown in
            refreshContext()
            if !shown { playRequestedClipIfVisible() }
            else { feedback.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            if lowPower { feedback.stop() }
            refreshContext()
        }
        .task(id: monitoring) {
            guard monitoring else { return }
            // WKInterfaceDevice exposes charging state when monitoring is enabled.
            // Poll only while the app is visible, for state entry and timer expiry.
            while !Task.isCancelled {
                model.refreshExperience(allowEffects: !reduceMotion && !lowPower)
                refreshContext()
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { return }
            }
        }
        .sheet(isPresented: $showingActions) { actionMenu }
    }

    private var actionMenu: some View {
        NavigationStack {
            List {
                Section("照顧") {
                    Text("飽足 \(Int(model.experience.care.satiety.rounded())) · 親密 \(model.experience.care.bond)")
                    ForEach(PatrickCareAction.allCases) { action in
                        Button(action.title) { requestedCare = action; showingActions = false }
                    }
                }
                Section("心情、情境與衣服") {
                    Picker("角色心情", selection: setting(\.mood)) {
                        ForEach(PatrickMood.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("情境", selection: setting(\.scene)) {
                        ForEach(PatrickExperienceScene.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("衣服", selection: setting(\.outfitID)) {
                        Text("跟隨情境").tag("auto")
                        ForEach(outfits.filter { $0.id != "auto" }) { Text($0.title).tag($0.id) }
                    }
                    Text("心情由你選；運動與泡澡是陪伴場景。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("陪伴計時") {
                    if let activity = model.experience.activity, activity.status == .running || activity.status == .paused {
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            Text("\(activity.kind.title) \(Int(activity.remaining(at: tick.date)) / 60):\(String(format: "%02d", Int(activity.remaining(at: tick.date)) % 60))").monospacedDigit()
                        }
                        Button(activity.status == .paused ? "繼續" : "暫停") {
                            model.updateExperience { if activity.status == .paused { $0.resume() } else { $0.pause() } }
                        }
                        Button("結束計時", role: .destructive) { model.updateExperience { $0.cancel() } }
                    } else {
                        Picker("種類", selection: $activityKind) { ForEach(PatrickActivityKind.allCases) { Text($0.title).tag($0) } }
                        Picker("分鐘", selection: $activityMinutes) { ForEach([1, 3, 5, 10, 15, 25, 30, 60], id: \.self) { Text("\($0)分鐘").tag($0) } }
                        Button("開始陪伴") { model.updateExperience { $0.start(activityKind, minutes: activityMinutes) }; showingActions = false }
                    }
                    Text("本機倒數，不記錄心率、距離或健身訓練。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("這套造型的動作") {
                    ForEach(availableOutfitClips) { actionButton($0) }
                    if availableOutfitClips.isEmpty { Text("這套造型暫無其他動作") }
                }
                Section("顯示與回應") {
                    Toggle("音效", isOn: setting(\.soundEnabled))
                    Toggle("觸覺", isOn: setting(\.hapticsEnabled))
                    Toggle("24小時制", isOn: setting(\.use24Hour))
                    Toggle("顯示日期", isOn: setting(\.showDate))
                    Toggle("場景點綴", isOn: setting(\.ambienceEnabled))
                    Picker("讀時", selection: setting(\.faceMode)) { ForEach(PatrickFaceMode.allCases) { Text($0.title).tag($0) } }
                    if clockArtwork.manifest == nil { Text(clockArtwork.message).font(.footnote) }
                    Text("手臂時計使用原味造型；動作時顯示所選衣服，數字時間一直保留。").font(.footnote)
                }
                PatrickSchedulePreferences(settings: Binding(get: { model.experience.settings }, set: { value in model.updateExperience { $0.settings = value } }))
                Section("最近陪伴") {
                    ForEach(model.experience.journal.suffix(10).reversed()) { entry in
                        Text("\(entry.at.formatted(date: .abbreviated, time: .shortened)) \(entry.text)").font(.footnote)
                    }
                }
                Section("自選資料") { NavigationLink("健康摘要") { PatrickHealthPanel() } }
                if reduceMotion || lowPower {
                    Text(reduceMotion ? "減少動態已開啟，目前保留靜態畫稿。" : "低耗電模式中，動作暫停。")
                        .font(.footnote)
                }
                if model.previewState != .normal {
                    Text("手機效果預覽，不代表手錶已量測到相同狀態。")
                        .font(.footnote)
                }
            }
            .navigationTitle("陪你一下")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { showingActions = false }
                }
            }
        }
    }

    private func setting<Value>(_ key: WritableKeyPath<PatrickExperienceSettings, Value>) -> Binding<Value> {
        Binding(get: { model.experience.settings[keyPath: key] }, set: { value in model.updateExperience { $0.settings[keyPath: key] = value } })
    }

    private var resolvedScene: String {
        let selection = model.experience.settings.scene
        if selection != .automatic { return selection.rawValue }
        if let activity = model.experience.activity, activity.status == .running { return activity.kind == .exercise ? "exercise" : "focus" }
        let device = WKInterfaceDevice.current()
        if device.batteryState == .charging || device.batteryState == .full || model.previewState == .charging { return "charging" }
        if model.experience.settings.isSleepTime(.now) || model.previewState == .sleeping { return "sleeping" }
        return "awake"
    }
    private var currentOutfit: PatrickOutfitCatalog.Outfit? {
        PatrickExperienceResources.outfit(model.experience.settings, scene: resolvedScene, from: outfits)
    }
    private var availableOutfitClips: [PatrickAnimationClip] {
        let ids = Set(currentOutfit?.actions?.values.flatMap { $0.clips } ?? [])
        return player.clips.filter { ids.contains($0.id) }
    }
    private func configureOutfit() {
        player.eventClips = PatrickExperienceResources.eventClips(model.experience.settings, outfit: currentOutfit, from: outfits)
        player.idleClips = currentOutfit?.idleClips ?? []
        if restingClipID != currentOutfit?.clipId {
            restingClipID = currentOutfit?.clipId
            _ = player.selectRestingClip(restingClipID)
        }
    }

    private func actionButton(_ clip: PatrickAnimationClip) -> some View {
        let reason = player.unavailableReason(for: clip)
        return Button {
            requestedClip = clip.id
            showingActions = false
        } label: {
            VStack(alignment: .leading) {
                Text(clip.title)
                if let reason { Text(reason).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .disabled(reason != nil || reduceMotion || lowPower)
    }

    private func playRequestedClipIfVisible() {
        // A watch sheet may cover the presenting view. Wait for both dismissal
        // and onAppear, in either order, before consuming its selected action.
        guard monitoring else { return }
        if let action = requestedCare {
            requestedCare = nil; model.performCare(action)
        }
        guard let id = requestedClip else { return }
        requestedClip = nil
        player.play(id)
    }

    private func refreshContext(at date: Date = .now) {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = visible && scenePhase != .background
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let charging = device.batteryState == .charging || device.batteryState == .full
            || model.previewState == .charging
        let automaticSleeping = model.experience.settings.isSleepTime(date) || model.previewState == .sleeping
        let selection = model.experience.settings.scene
        let sleeping = selection == .automatic ? automaticSleeping : selection == .sleeping
        let timer = model.experience.activity == nil ? model.companionTimer : nil
        if model.experience.activity != nil { timerTracker = PatrickAnimationTimerTracker() }
        let timerState = timerTracker.update(id: timer?.id.uuidString,
            running: timer?.status == .running, paused: timer?.status == .paused,
            endsAt: timer?.endsAt, at: date)
        let activity = model.experience.activity
        let localRunning = activity?.status == .running
        let localFocus = localRunning && activity?.kind != .exercise
        let localExercise = localRunning && activity?.kind == .exercise
        configureOutfit()
        player.update(PatrickAnimationContext(
            active: monitoring, wristDown: wristDown,
            reduceMotion: reduceMotion, lowPower: lowPower, sleeping: sleeping,
            charging: charging || selection == .charging,
            focusing: localFocus || timerState.focusing || selection == .focus,
            exercising: localExercise || selection == .exercise,
            completedTimerID: model.completedActivityID ?? timerState.completedTimerID), at: date)
        let status: PatrickFaceStatus
        if model.previewState != .normal { status = .preview }
        else if charging { status = .charging }
        else if lowPower || (device.batteryLevel >= 0 && device.batteryLevel < 0.2) { status = .lowPower }
        else if sleeping { status = .sleeping }
        else if localExercise || selection == .exercise { status = .exercise }
        else if model.petScene == .resting { status = .resting }
        else { status = .ready }
        model.setStatus(status)
        if !monitoring || reduceMotion || lowPower { model.refreshExperience(allowEffects: false) }
    }
}

private struct PatrickIndependentClock: View {
    let width: CGFloat
    let height: CGFloat
    let dimmed: Bool
    let settings: PatrickExperienceSettings

    var body: some View {
        // The clock has its own schedule; missing art, pause and errors cannot stop it.
        TimelineView(.everyMinute) { timeline in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: timeline.date)
            ZStack(alignment: .topLeading) {
            let hour = parts.hour ?? 0
            Text(String(format: "%02d:%02d", settings.use24Hour ? hour : (hour % 12 == 0 ? 12 : hour % 12), parts.minute ?? 0))
                .font(.system(size: width * 0.145, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(dimmed ? 0.72 : 1))
                .position(x: width * 0.5, y: height * 0.11)
                .accessibilityLabel("現在時間")
            if settings.showDate { Text(timeline.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                .font(.system(size: width * 0.042))
                .foregroundStyle(.secondary)
                .position(x: width * 0.5, y: height * 0.19)
            }
            }
            .frame(width: width, height: height)
        }
    }
}
