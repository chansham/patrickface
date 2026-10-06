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
    @State private var completionVisibility = PatrickCompletionVisibility()
    @StateObject private var feedback = PatrickFeedback()
    @StateObject private var clockArtwork = PatrickClockArtwork()
    @State private var outfits: [PatrickOutfitCatalog.Outfit] = []
    @State private var restingClipID: String?
    @State private var requestedCare: PatrickCareAction?
    @State private var requestedSurprise = false
    @State private var surpriseExpiresAt: Date?
    @State private var activityKind: PatrickActivityKind = .focus
    @State private var activityMinutes = 5

    private var monitoring: Bool { visible && scenePhase == .active && !wristDown && !showingActions }

    private var faceSurface: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width / 416, geometry.size.height / 496)
            let width = 416 * unit, height = 496 * unit
            ZStack(alignment: .topLeading) {
                Color.black
                if model.experience.settings.ambienceEnabled && !wristDown {
                    PatrickSceneAmbience(scene: resolvedScene, motionAllowed: monitoring && !reduceMotion && !lowPower)
                }
                if surpriseExpiresAt != nil && model.experience.settings.ambienceEnabled && monitoring && !reduceMotion && !lowPower {
                    PatrickSceneAmbience(scene: "bath", motionAllowed: true)
                }
                PatrickLayoutFace(player: player, artwork: clockArtwork, experience: model.experience,
                                  dimmed: wristDown, active: monitoring && !reduceMotion && !lowPower)
                    .frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .onTapGesture { model.performCare(.pet) }
                    .onLongPressGesture(minimumDuration: 0.45) { showingActions = true }
                    .accessibilityLabel("摸摸派大星")
                    .accessibilityAddTraits(.isButton)
                if PatrickFaceLayoutSpec.presentationID(model.experience.settings) != "theater" {
                Text("\(model.experience.settings.mood.title) · \(player.isPlaying && surpriseExpiresAt == nil ? player.message : model.careNotice)")
                    .font(.system(size: max(8, width * 0.04)))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: width * 0.72)
                    .position(x: width * 0.46, y: height * 0.955)
                }
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
            #if DEBUG && targetEnvironment(simulator)
            .modifier(PatrickWatchGeometryProbe(geometry: geometry,
                layoutID: PatrickFaceLayoutSpec.presentationID(model.experience.settings),
                phase: scenePhase, visible: visible, wristDown: wristDown, monitoring: monitoring,
                reduceMotion: reduceMotion, lowPower: lowPower))
            #endif
        }
    }

    private var appearanceSurface: some View {
        faceSurface
        // Keep the digital clock and fixed-aspect artwork below watchOS's time.
        // Only the backdrop extends behind the system status area and corners.
        .background { Color.black.ignoresSafeArea() }
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
            refreshContext()
            model.refreshExperience(allowEffects: monitoring && !reduceMotion && !lowPower)
            configureOutfit()
            playRequestedClipIfVisible()
        }
        .onDisappear {
            visible = false
            _ = completionVisibility.update(allowsMotion: false)
            surpriseExpiresAt = nil
            player.suspend()
            feedback.stop()
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
        }
    }

    private var environmentSurface: some View {
        appearanceSurface
        .onChange(of: scenePhase) { _, _ in
            if scenePhase != .active { consumeQuietRequests() }
            refreshContext(); if !monitoring { feedback.stop() }
        }
        .onChange(of: wristDown) { _, _ in
            if wristDown { consumeQuietRequests(); feedback.stop() }
            refreshContext()
        }
        .onChange(of: reduceMotion) { _, _ in
            if reduceMotion { consumeQuietRequests(); feedback.stop() }
            refreshContext()
        }
        .onChange(of: model.petScene) { _, _ in refreshContext() }
        .onChange(of: model.sleepMode) { _, _ in refreshContext() }
        .onChange(of: model.previewState) { _, _ in refreshContext() }
        .onChange(of: model.companionTimer) { _, _ in refreshContext() }
    }

    private var actionSurface: some View {
        environmentSurface
        .onChange(of: model.activationSequence) { _, _ in
            refreshContext()
            if let action = model.requestedAction {
                player.playEvent(action.clipID)
                if !player.isPlaying || player.currentClipID?.hasPrefix("idle-blink-") == true { feedback.play(action.rawValue, settings: model.experience.settings, active: monitoring && !reduceMotion && !lowPower) }
            }
        }
        .onChange(of: model.calendarCelebrationSequence) { _, _ in player.playEvent("celebrate") }
        .onChange(of: model.soundSequence) { _, _ in feedback.play("pet", settings: model.experience.settings, active: monitoring && !reduceMotion && !lowPower) }
    }

    private var settingsSurface: some View {
        actionSurface
        .onChange(of: model.experience.settings) { _, _ in refreshContext(); configureOutfit(); if !model.experience.settings.soundEnabled { feedback.stop() } }
        .onChange(of: model.experience.settings.scene) { _, next in
            refreshContext()
            let event = next == .sleeping ? "yawn" : next == .awake ? "wake" : next.rawValue
            if scenePhase != .active || wristDown || reduceMotion || lowPower { requestedClip = nil }
            else if showingActions { requestedClip = player.eventClips?[event] }
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
            if lowPower { consumeQuietRequests(); feedback.stop() }
            refreshContext()
        }
    }

    var body: some View {
        settingsSurface
        .task(id: monitoring) {
            guard monitoring else { return }
            // WKInterfaceDevice exposes charging state when monitoring is enabled.
            // Poll only while the app is visible, for state entry and timer expiry.
            while !Task.isCancelled {
                refreshContext()
                model.refreshExperience(allowEffects: !reduceMotion && !lowPower)
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { return }
            }
        }
        .task(id: surpriseExpiresAt) {
            guard surpriseExpiresAt != nil else { return }
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            surpriseExpiresAt = nil
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
                    Button("找個小驚喜") { requestedSurprise = true; showingActions = false }
                    if let surprise = model.experience.surprise { Text(surprise.line).font(.footnote).foregroundStyle(.secondary) }
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
                            model.controlActivity(activity.status == .paused ? .resume : .pause)
                        }
                        Button("結束計時", role: .destructive) { model.controlActivity(.cancel) }
                    } else {
                        Picker("種類", selection: $activityKind) { ForEach(PatrickActivityKind.allCases) { Text($0.title).tag($0) } }
                        Picker("分鐘", selection: $activityMinutes) { ForEach([1, 3, 5, 10, 15, 25, 30, 60], id: \.self) { Text("\($0)分鐘").tag($0) } }
                        Button("開始陪伴") {
                            model.updateExperience { $0.start(activityKind, minutes: activityMinutes) }
                            configureOutfit()
                            requestedClip = player.eventClips?[activityKind.clipID]
                            showingActions = false
                        }
                    }
                    Text("本機倒數，不記錄心率、距離或健身訓練。散步、跑步與肌力目前共用運動造型。").font(.footnote).foregroundStyle(.secondary)
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
                    PatrickLayoutPicker(settings: Binding(get: { model.experience.settings }, set: { value in model.updateExperience { $0.settings = value } }))
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
        if let activity = model.experience.activity, activity.status == .running { return activity.kind.sceneID }
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
        if wristDown || scenePhase != .active { consumeQuietRequests(); return }
        guard monitoring else { return }
        if let action = requestedCare {
            requestedCare = nil; model.performCare(action, allowEffects: !reduceMotion && !lowPower)
        }
        if requestedSurprise {
            requestedSurprise = false; findSurprise()
        }
        guard !reduceMotion && !lowPower else { requestedClip = nil; return }
        guard let id = requestedClip else { return }
        requestedClip = nil
        player.play(id)
    }

    private func consumeQuietRequests() {
        requestedClip = nil
        requestedSurprise = false
        if let action = requestedCare {
            requestedCare = nil
            model.performCare(action, allowEffects: false)
        }
    }

    private func findSurprise() {
        guard model.findSurprise(), monitoring, !reduceMotion, !lowPower else { return }
        surpriseExpiresAt = .now.addingTimeInterval(3)
        // Own-outfit reaction only. This does not claim a new animation exists.
        if let id = currentOutfit?.surpriseClipID,
           let clip = player.clips.first(where: { $0.id == id }),
           player.unavailableReason(for: clip) == nil, clip.durationsMs.reduce(0, +) <= 10_000 {
            player.play(id)
        }
        if !player.isPlaying || player.currentClipID?.hasPrefix("idle-blink-") == true {
            feedback.play("bubble", settings: model.experience.settings, active: true)
        }
    }

    private func refreshContext(at date: Date = .now) {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = visible && scenePhase != .background
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let allowsMotion = monitoring && !reduceMotion && !lowPower
        let continuous = completionVisibility.update(allowsMotion: allowsMotion)
        if !continuous {
            // Reconcile only deadlines before admitting new foreground effects.
            // Birthday/holiday entry remains a separate, visible-date decision.
            model.refreshExperience(at: date, allowEffects: false, observeCalendar: false)
        }
        let charging = device.batteryState == .charging || device.batteryState == .full
            || model.previewState == .charging
        let automaticSleeping = model.experience.settings.isSleepTime(date) || model.previewState == .sleeping
        let selection = model.experience.settings.scene
        let sleeping = selection == .automatic ? automaticSleeping : selection == .sleeping
        let timer = model.experience.activity == nil ? model.companionTimer : nil
        if model.experience.activity != nil { timerTracker = PatrickAnimationTimerTracker() }
        let timerState = timerTracker.update(id: timer?.id.uuidString,
            running: timer?.status == .running, paused: timer?.status == .paused,
            endsAt: timer?.endsAt, at: date, allowCompletion: continuous)
        let activity = model.experience.activity
        let localRunning = activity?.status == .running
        let localFocus = localRunning && activity?.kind.isExercise == false
        let localExercise = localRunning && activity?.kind.isExercise == true
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
        if !monitoring || reduceMotion || lowPower {
            surpriseExpiresAt = nil
            model.refreshExperience(allowEffects: false)
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Diagnostics only: never compiled into device or Release products, and never
/// writes preferences, changes scene state, or changes the available geometry.
@MainActor private struct PatrickWatchGeometryProbe: ViewModifier {
    let geometry: GeometryProxy
    let layoutID: String
    let phase: ScenePhase
    let visible: Bool
    let wristDown: Bool
    let monitoring: Bool
    let reduceMotion: Bool
    let lowPower: Bool

    private struct Observation: Codable, Equatable {
        let layoutID: String
        let scenePhase: String
        let geometrySizePoints: [String: Double]
        let geometryFrameGlobalPoints: [String: Double]
        let safeAreaInsetsPoints: [String: Double]
        let outerUnit416: Double
        let innerUnit832: Double
        let stageSizePoints: [String: Double]
        let stageOriginInGeometryPoints: [String: Double]
        let stageSizePixels: [String: Double]
        let screenBoundsPoints: [String: Double]
        let screenScale: Double
        let visible: Bool
        let wristDown: Bool
        let monitoring: Bool
        let reduceMotion: Bool
        let lowPower: Bool
    }

    private struct Record: Encodable {
        let schemaVersion = 1
        let kind = "patrick-watch-geometry"
        let debugSimulator = true
        let bundleID: String
        let processID: Int32
        let recordedAt: String
        let recordedAtEpochMS: Double
        let event: String
        let observation: Observation
    }

    private var observation: Observation {
        let size = geometry.size, insets = geometry.safeAreaInsets
        let global = geometry.frame(in: .global)
        let device = WKInterfaceDevice.current()
        let screen = device.screenBounds, scale = Double(device.screenScale)
        let unit = min(Double(size.width) / 416, Double(size.height) / 496)
        let width = 416 * unit, height = 496 * unit
        let phaseName: String
        switch phase {
        case .active: phaseName = "active"
        case .inactive: phaseName = "inactive"
        case .background: phaseName = "background"
        @unknown default: phaseName = "unknown"
        }
        return Observation(layoutID: layoutID, scenePhase: phaseName,
            geometrySizePoints: ["width": Double(size.width), "height": Double(size.height)],
            geometryFrameGlobalPoints: ["x": Double(global.minX), "y": Double(global.minY), "width": Double(global.width), "height": Double(global.height)],
            safeAreaInsetsPoints: ["top": Double(insets.top), "leading": Double(insets.leading), "bottom": Double(insets.bottom), "trailing": Double(insets.trailing)],
            outerUnit416: unit, innerUnit832: unit / 2,
            stageSizePoints: ["width": width, "height": height],
            stageOriginInGeometryPoints: ["x": (Double(size.width) - width) / 2, "y": (Double(size.height) - height) / 2],
            stageSizePixels: ["width": width * scale, "height": height * scale],
            screenBoundsPoints: ["x": Double(screen.minX), "y": Double(screen.minY), "width": Double(screen.width), "height": Double(screen.height)],
            screenScale: scale, visible: visible, wristDown: wristDown, monitoring: monitoring,
            reduceMotion: reduceMotion, lowPower: lowPower)
    }

    func body(content: Content) -> some View {
        content
            .onAppear { write(event: "appear") }
            .onChange(of: observation) { _, _ in write(event: "change") }
    }

    private func write(event: String) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        do {
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            let date = Date.now
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let record = Record(bundleID: Bundle.main.bundleIdentifier ?? "unknown",
                processID: ProcessInfo.processInfo.processIdentifier,
                recordedAt: formatter.string(from: date), recordedAtEpochMS: date.timeIntervalSince1970 * 1000,
                event: event, observation: observation)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(record).write(to: documents.appendingPathComponent("patrick-watch-geometry.json"), options: .atomic)
        } catch {
            print("Patrick simulator geometry probe unavailable: \(error.localizedDescription)")
        }
    }
}
#endif
