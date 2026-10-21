import SwiftUI
import WatchKit

struct PatrickFaceView: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var model: PatrickAppModel
    @State private var lastTap = Date.distantPast
    @State private var lastGesture = Date.distantPast
    @State private var lastChargingShow = Date.distantPast
    @State private var showingPetControls = false
    @State private var chargingMessage: String?
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private static let clockHub = CGPoint(
        x: PatrickClockLayout.hubX, y: PatrickClockLayout.hubY
    )
    private static let hourHandLength = CGFloat(PatrickClockLayout.hourLength)
    private static let minuteHandLength = CGFloat(PatrickClockLayout.minuteLength)

    var body: some View {
        TimelineView(
            PatrickTimelineSchedule(
                lowPower: lowPower,
                isActive: scenePhase == .active,
                isLuminanceReduced: dimmed
            )
        ) { timeline in
            let device = WKInterfaceDevice.current()
            let level = device.batteryLevel
            let physicalCharging =
                device.batteryState == .charging || device.batteryState == .full
            let physicalLowBattery = level >= 0 && level < 0.2
            let charging =
                physicalCharging || model.previewState == .charging
            let lowBattery =
                !charging && (
                    physicalLowBattery || model.previewState == .lowBattery
                )
            let sleeping = resolvedSleeping(date: timeline.date)
            let reduced = dimmed || lowPower || scenePhase != .active
            let status = sharedStatus(
                sleeping: sleeping,
                lowBattery: lowBattery,
                charging: charging
            )
            let pose = FacePose(
                date: timeline.date,
                lastTap: lastTap,
                lastGesture: lastGesture,
                lastChargingShow: lastChargingShow,
                reduced: reduced,
                sleeping: sleeping,
                lowBattery: lowBattery,
                charging: charging,
                physicalCharging: physicalCharging,
                petScene: model.petScene
            )

            Canvas { context, size in
                draw(
                    context: &context,
                    size: size,
                    date: timeline.date,
                    pose: pose,
                    theme: model.theme
                )
            }
            .contentShape(Rectangle())
            .gesture(tapGesture)
            .simultaneousGesture(longPressGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("派大星動態錶面")
            .accessibilityValue(
                "\(formattedTime(timeline.date))，\(model.petScene.title)，\(status.complicationLabel)"
            )
            .accessibilityHint("點一下互動，點兩下切換風格，長按揮手")
            .onAppear {
                model.setStatus(status)
            }
            .onChange(of: status) { _, newStatus in
                model.setStatus(newStatus)
            }
            .onChange(of: Calendar.current.component(.minute, from: timeline.date)) { _, _ in
                // Refresh the state timestamp even when the state itself is unchanged.
                model.setStatus(status)
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .onAppear {
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: scenePhase) { _, phase in
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = phase != .background
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onDisappear {
            if !showingPetControls {
                WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
            }
        }
        .onChange(of: model.activationSequence) { _, _ in
            guard interactionsEnabled else { return }
            lastTap = .now
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSProcessInfoPowerStateDidChange
            )
        ) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .overlay(alignment: .bottomTrailing) {
            if interactionsEnabled {
                Button {
                    chargingMessage = nil
                    showingPetControls = true
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("陪伴情境與互動")
            }
        }
        .sheet(isPresented: $showingPetControls) {
            petControls
                .onAppear {
                    WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
                }
        }
    }

    private var petControls: some View {
        NavigationStack {
            List {
                Section("陪伴情境") {
                    Picker("情境", selection: Binding(
                        get: { model.petScene },
                        set: { model.setPetScene($0) }
                    )) {
                        ForEach(PatrickPetScene.allCases) { scene in
                            Text(scene.title).tag(scene)
                        }
                    }
                    Text("情境預設自動。運動陪伴在手錶授權後會寫入健康；沒有授權時仍只是陪伴倒數。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("一起玩") {
                    Button("打個招呼") {
                        guard interactionsEnabled, !lowPower else { return }
                        lastGesture = .now
                        showingPetControls = false
                    }
                    .disabled(lowPower)
                    Button("充電小表演") {
                        let batteryState = WKInterfaceDevice.current().batteryState
                        guard batteryState == .charging || batteryState == .full else {
                            chargingMessage = "接上充電器後，再來一起玩。"
                            return
                        }
                        guard interactionsEnabled, !lowPower else { return }
                        lastChargingShow = .now
                        showingPetControls = false
                    }
                    .disabled(lowPower)
                    if let chargingMessage {
                        Text(chargingMessage).font(.footnote)
                    }
                    if lowPower {
                        Text("低耗電模式中，動作暫停。")
                            .font(.footnote)
                    }
                    Text("表演只在這個 App 畫面開啟時播放。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.previewState != .normal {
                    Section("手機效果預覽") {
                        Text("目前包含手機指定的效果，並不代表手錶已量測到這個狀態。")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("陪你一下")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { showingPetControls = false }
                }
            }
        }
    }

    private var interactionsEnabled: Bool {
        scenePhase == .active && !dimmed
    }

    private var tapGesture: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { result in
                guard interactionsEnabled else { return }
                switch result {
                case .first(_):
                    model.toggleTheme()
                    WKInterfaceDevice.current().play(.directionUp)
                case .second(_):
                    guard !lowPower else { return }
                    lastTap = .now
                    WKInterfaceDevice.current().play(.click)
                }
            }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in
                guard interactionsEnabled, !lowPower else { return }
                lastGesture = .now
                WKInterfaceDevice.current().play(.start)
            }
    }

    private func sharedStatus(
        sleeping: Bool,
        lowBattery: Bool,
        charging: Bool
    ) -> PatrickFaceStatus {
        if model.previewState != .normal { return .preview }
        if charging { return .charging }
        if lowPower || lowBattery { return .lowPower }
        if sleeping { return .sleeping }
        if model.petScene == .resting { return .resting }
        if model.petScene == .exercise { return .exercise }
        return .ready
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func resolvedSleeping(date: Date) -> Bool {
        let companionSleep: Bool?
        switch model.sleepMode {
        case .automatic:
            companionSleep = nil
        case .on:
            companionSleep = true
        case .off:
            companionSleep = false
        }
        return PatrickPetRules.isSleeping(
            scene: model.petScene,
            automaticNight: PatrickPetRules.isNight(date),
            companionSleep: companionSleep,
            companionPreviewSleeping: model.previewState == .sleeping
        )
    }

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        date: Date,
        pose: FacePose,
        theme: PatrickTheme
    ) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

        let scale = min(size.width / 720, size.height / 880)
        let offset = CGPoint(
            x: (size.width - 720 * scale) / 2,
            y: (size.height - 880 * scale) / 2
        )
        var scene = context
        scene.translateBy(x: offset.x, y: offset.y)
        scene.scaleBy(x: scale, y: scale)

        if pose.charging {
            let glow = Path(CGRect(x: 140, y: 170, width: 440, height: 650))
            scene.fill(
                glow,
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        .mint.opacity(0.06 + pose.chargingPulse * 0.12),
                        .clear,
                    ]),
                    startPoint: CGPoint(x: 360, y: 170),
                    endPoint: CGPoint(x: 360, y: 820)
                )
            )
        }

        drawTicks(context: &scene, reduced: pose.reduced)
        drawInformation(
            context: &scene,
            date: date,
            sleeping: pose.sleeping,
            reduced: pose.reduced,
            theme: theme
        )

        var rig = scene
        rig.opacity = pose.reduced ? 0.56 : 1
        rig.translateBy(x: 0, y: pose.tapY + pose.slump * 15)
        rig.translateBy(x: Self.clockHub.x, y: Self.clockHub.y)
        rig.scaleBy(x: pose.tapScale, y: pose.tapScale)
        rig.translateBy(x: -Self.clockHub.x, y: -Self.clockHub.y)

        if theme == .clay {
            drawToon3D(context: &rig, pose: pose)
        } else {
            drawCel(context: &rig, pose: pose)
        }

        if pose.sleeping && !pose.reduced {
            let phase = CGFloat(
                date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3.2) / 3.2
            )
            let opacity = sin(Double(phase) * .pi) * 0.7
            scene.draw(
                Text("Z")
                    .font(.system(size: 26 + phase * 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.74, green: 0.66, blue: 0.83).opacity(opacity)),
                at: CGPoint(x: 510 + phase * 50, y: 310 - phase * 75),
                anchor: .leading
            )
        }
    }

    private func drawCel(context: inout GraphicsContext, pose: FacePose) {
        let bodyHeight: CGFloat = 665
        let bodyWidth = bodyHeight * 463 / 787
        let bodyTop: CGFloat = 165
        let pivotY = bodyTop + bodyHeight * 0.47
        let breath = 1 + pose.breathing * 0.004

        var rig = context
        var body = rig
        body.translateBy(x: 360, y: pivotY)
        body.rotate(by: .degrees(pose.slump * 4.5 + pose.bodySway))
        body.scaleBy(x: breath, y: 1)
        body.translateBy(x: -360, y: -pivotY)

        let bodyRect = CGRect(
            x: 360 - bodyWidth / 2,
            y: bodyTop,
            width: bodyWidth,
            height: bodyHeight
        )
        body.draw(Image("season1-body-normal"), in: bodyRect)
        drawArm(
            context: &rig,
            image: "season1-minute-arm",
            angle: pose.minuteDegrees,
            length: Self.minuteHandLength,
            aspect: 0.36,
            pivot: Self.clockHub
        )
        drawArm(
            context: &rig,
            image: "season1-hour-arm",
            angle: pose.hourDegrees,
            length: Self.hourHandLength,
            aspect: 0.44,
            pivot: Self.clockHub
        )
        drawClockHub(context: &rig, threeDimensional: false)
    }

    private func drawToon3D(context: inout GraphicsContext, pose: FacePose) {
        let bodyHeight: CGFloat = 665
        let bodyWidth = bodyHeight * 461 / 790
        let bodyTop: CGFloat = 165
        let pivotY = bodyTop + bodyHeight * 0.48
        let breath = 1 + pose.breathing * 0.0035

        var rig = context
        var body = rig
        body.translateBy(x: 360, y: pivotY)
        body.rotate(by: .degrees(pose.slump * 4.5 + pose.bodySway))
        body.scaleBy(x: breath, y: 1)
        body.translateBy(x: -360, y: -pivotY)

        let bodyRect = CGRect(
            x: 360 - bodyWidth / 2,
            y: bodyTop,
            width: bodyWidth,
            height: bodyHeight
        )
        body.draw(Image("season1-3d-body"), in: bodyRect)
        drawArm(
            context: &rig,
            image: "season1-3d-arm",
            angle: pose.minuteDegrees,
            length: Self.minuteHandLength,
            aspect: 0.34,
            pivot: Self.clockHub
        )
        drawArm(
            context: &rig,
            image: "season1-3d-arm",
            angle: pose.hourDegrees,
            length: Self.hourHandLength,
            aspect: 0.42,
            pivot: Self.clockHub
        )
        drawClockHub(context: &rig, threeDimensional: true)
    }

    private func drawClockHub(
        context: inout GraphicsContext,
        threeDimensional: Bool
    ) {
        let radius: CGFloat = 9
        let path = Path(
            ellipseIn: CGRect(
                x: Self.clockHub.x - radius,
                y: Self.clockHub.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        context.fill(
            path,
            with: .color(
                threeDimensional
                    ? Color(red: 0.91, green: 0.36, blue: 0.33)
                    : Color(red: 0.97, green: 0.47, blue: 0.44)
            )
        )
        context.stroke(
            path,
            with: .color(Color(red: 0.33, green: 0.16, blue: 0.18)),
            lineWidth: 2.5
        )
    }

    private func drawArm(
        context: inout GraphicsContext,
        image: String,
        angle: Double,
        length: CGFloat,
        aspect: CGFloat,
        pivot: CGPoint
    ) {
        var arm = context
        arm.translateBy(x: pivot.x, y: pivot.y)
        arm.rotate(by: .degrees(angle))
        let width = length * aspect
        arm.draw(
            Image(image),
            in: CGRect(x: -width / 2, y: -length, width: width, height: length)
        )
    }

    private func drawTicks(context: inout GraphicsContext, reduced: Bool) {
        let marks: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 360, y: 27), CGPoint(x: 360, y: 43)),
            (CGPoint(x: 532, y: 52), CGPoint(x: 526, y: 64)),
            (CGPoint(x: 665, y: 208), CGPoint(x: 653, y: 214)),
            (CGPoint(x: 693, y: 440), CGPoint(x: 677, y: 440)),
            (CGPoint(x: 665, y: 672), CGPoint(x: 653, y: 666)),
            (CGPoint(x: 532, y: 828), CGPoint(x: 526, y: 816)),
            (CGPoint(x: 360, y: 853), CGPoint(x: 360, y: 837)),
            (CGPoint(x: 188, y: 828), CGPoint(x: 194, y: 816)),
            (CGPoint(x: 55, y: 672), CGPoint(x: 67, y: 666)),
            (CGPoint(x: 27, y: 440), CGPoint(x: 43, y: 440)),
            (CGPoint(x: 55, y: 208), CGPoint(x: 67, y: 214)),
            (CGPoint(x: 188, y: 52), CGPoint(x: 194, y: 64)),
        ]

        for (index, mark) in marks.enumerated() {
            let major = index.isMultiple(of: 3)
            var path = Path()
            path.move(to: mark.0)
            path.addLine(to: mark.1)
            context.stroke(
                path,
                with: .color(.white.opacity(reduced ? 0.18 : major ? 0.72 : 0.3)),
                style: StrokeStyle(lineWidth: major ? 5 : 3, lineCap: .round)
            )
        }
    }

    private func drawInformation(
        context: inout GraphicsContext,
        date: Date,
        sleeping: Bool,
        reduced: Bool,
        theme: PatrickTheme
    ) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let weekday = ["日", "一", "二", "三", "四", "五", "六"][
            calendar.component(.weekday, from: date) - 1
        ]
        let day = calendar.component(.day, from: date)

        context.draw(
            Text(String(format: "%02d:%02d", hour, minute))
                .font(.system(size: 68, weight: .light, design: .rounded))
                .foregroundStyle(
                    sleeping
                        ? Color(red: 0.73, green: 0.66, blue: 0.79)
                            .opacity(reduced ? 0.62 : 1)
                        : .white.opacity(reduced ? 0.68 : 0.95)
                ),
            at: CGPoint(x: 360, y: 83),
            anchor: .center
        )
        context.draw(
            Text("週\(weekday) \(day)")
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(reduced ? 0.25 : 0.48)),
            at: CGPoint(x: 54, y: 132),
            anchor: .leading
        )
        context.draw(
            Text(model.previewState != .normal
                 ? "效果預覽"
                 : model.petScene == .automatic ? theme.statusLabel : model.petScene.title)
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(reduced ? 0.25 : 0.48)),
            at: CGPoint(x: 666, y: 132),
            anchor: .trailing
        )
    }

}

private struct PatrickTimelineSchedule: TimelineSchedule {
    let lowPower: Bool
    let isActive: Bool
    let isLuminanceReduced: Bool

    func entries(
        from startDate: Date,
        mode: TimelineScheduleMode
    ) -> PeriodicTimelineSchedule.Entries {
        let interval: TimeInterval
        if !isActive || isLuminanceReduced || mode == .lowFrequency {
            interval = 60
        } else {
            interval = lowPower ? 5 : 1.0 / 30.0
        }

        return PeriodicTimelineSchedule(from: startDate, by: interval)
            .entries(from: startDate, mode: mode)
    }
}

private struct FacePose {
    let hourDegrees: Double
    let minuteDegrees: Double
    let gestureWeight: Double
    let tapY: CGFloat
    let tapScale: CGFloat
    let breathing: Double
    let slump: CGFloat
    let chargingPulse: Double
    let bodySway: Double
    let sleeping: Bool
    let charging: Bool
    let reduced: Bool

    init(
        date: Date,
        lastTap: Date,
        lastGesture: Date,
        lastChargingShow: Date,
        reduced: Bool,
        sleeping: Bool,
        lowBattery: Bool,
        charging: Bool,
        physicalCharging: Bool,
        petScene: PatrickPetScene
    ) {
        let clock = PatrickClockAngles.make(for: date)
        let baseHour = clock.hour
        let baseMinute = clock.minute

        let periodicElapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 12)
        let manualElapsed = date.timeIntervalSince(lastGesture)
        let quiet = reduced || sleeping || lowBattery || petScene == .resting
        let periodicWeight = quiet ? 0 : Self.envelope(periodicElapsed, duration: 1.8)
        let manualWeight = reduced ? 0 : Self.envelope(manualElapsed, duration: 1.8)
        gestureWeight = max(periodicWeight, manualWeight)
        hourDegrees = baseHour - 5 * gestureWeight
        minuteDegrees = baseMinute + 19 * gestureWeight

        let tapWeight = reduced ? 0 : Self.envelope(
            date.timeIntervalSince(lastTap),
            duration: 0.56
        )
        tapY = CGFloat(-9 * tapWeight)
        tapScale = CGFloat(1 + 0.045 * tapWeight)
        breathing = quiet
            ? 0
            : sin(date.timeIntervalSinceReferenceDate * .pi * 0.72)
        slump = lowBattery ? 1 : 0
        chargingPulse = reduced || !charging
            ? 0
            : (sin(date.timeIntervalSinceReferenceDate * .pi * 1.2) + 1) / 2
        let showElapsed = date.timeIntervalSince(lastChargingShow)
        let showWeight = reduced || !physicalCharging
            ? 0 : Self.envelope(showElapsed, duration: 6)
        let exerciseSway = petScene == .exercise && !quiet
            ? sin(date.timeIntervalSinceReferenceDate * .pi) * 1.5 : 0
        bodySway = sin(showElapsed * .pi * 3) * 7 * showWeight + exerciseSway
        self.sleeping = sleeping
        self.charging = charging
        self.reduced = reduced
    }

    private static func envelope(_ elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard elapsed > 0, elapsed < duration else { return 0 }
        let sine = sin(.pi * elapsed / duration)
        return sine * sine
    }
}

#Preview {
    PatrickFaceView()
        .environmentObject(PatrickAppModel())
}
