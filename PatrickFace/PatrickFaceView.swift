import SwiftUI
import WatchKit
import Intents

@MainActor
final class FocusChecker: ObservableObject {
    @Published private(set) var isFocused = false
    private var timer: Timer?

    init() {
        INFocusStatusCenter.default.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        refresh()
        setMonitoring(true)
    }

    func setMonitoring(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        isFocused = INFocusStatusCenter.default.focusStatus.isFocused ?? false
    }

    deinit { timer?.invalidate() }
}

struct PatrickFaceView: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var model: PatrickAppModel
    @StateObject private var focus = FocusChecker()
    @State private var lastTap = Date.distantPast
    @State private var lastGesture = Date.distantPast
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private static let clockHub = CGPoint(x: 360, y: 498)
    private static let hourHandLength: CGFloat = 250
    private static let minuteHandLength: CGFloat = 340

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
            let sleeping = resolvedSleeping(
                automatic: focus.isFocused || isNight(timeline.date)
            )
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
                reduced: reduced,
                sleeping: sleeping,
                lowBattery: lowBattery,
                charging: charging
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
                "\(formattedTime(timeline.date))，\(model.theme.displayName)，\(status.complicationLabel)"
            )
            .accessibilityHint("點一下互動，點兩下切換風格，長按揮手")
            .onAppear {
                model.setStatus(status)
            }
            .onChange(of: status) { _, newStatus in
                model.setStatus(newStatus)
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .onAppear {
            focus.setMonitoring(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            focus.setMonitoring(phase == .active)
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
        if charging { return .charging }
        if lowPower || lowBattery { return .lowPower }
        if sleeping { return .sleeping }
        return .ready
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func resolvedSleeping(automatic: Bool) -> Bool {
        if model.previewState == .sleeping {
            return true
        }
        switch model.sleepMode {
        case .automatic:
            return automatic
        case .on:
            return true
        case .off:
            return false
        }
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
        rig.translateBy(x: 360, y: 490)
        rig.rotate(by: .degrees(pose.slump * 4.5))
        rig.scaleBy(x: pose.tapScale, y: pose.tapScale)
        rig.translateBy(x: -360, y: -490)

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
        rig.translateBy(x: 360, y: pivotY)
        rig.scaleBy(x: breath, y: 1)
        rig.translateBy(x: -360, y: -pivotY)

        let bodyRect = CGRect(
            x: 360 - bodyWidth / 2,
            y: bodyTop,
            width: bodyWidth,
            height: bodyHeight
        )
        rig.draw(Image("season1-body-normal"), in: bodyRect)
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
        rig.translateBy(x: 360, y: pivotY)
        rig.scaleBy(x: breath, y: 1)
        rig.translateBy(x: -360, y: -pivotY)

        let bodyRect = CGRect(
            x: 360 - bodyWidth / 2,
            y: bodyTop,
            width: bodyWidth,
            height: bodyHeight
        )
        rig.draw(Image("season1-3d-body"), in: bodyRect)
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
            Text(theme.statusLabel)
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(reduced ? 0.25 : 0.48)),
            at: CGPoint(x: 666, y: 132),
            anchor: .trailing
        )
    }

    private func isNight(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let hour = Double(calendar.component(.hour, from: date))
        let minute = Double(calendar.component(.minute, from: date)) / 60
        let value = hour + minute
        return value >= 22 || value < 5.5
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
    let sleeping: Bool
    let charging: Bool
    let reduced: Bool

    init(
        date: Date,
        lastTap: Date,
        lastGesture: Date,
        reduced: Bool,
        sleeping: Bool,
        lowBattery: Bool,
        charging: Bool
    ) {
        let clock = PatrickClockAngles.make(for: date)
        let baseHour = clock.hour
        let baseMinute = clock.minute

        let periodicElapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 12)
        let manualElapsed = date.timeIntervalSince(lastGesture)
        let periodicWeight = reduced ? 0 : Self.envelope(periodicElapsed, duration: 1.8)
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
        breathing = reduced || sleeping
            ? 0
            : sin(date.timeIntervalSinceReferenceDate * .pi * 0.72)
        slump = lowBattery ? 1 : 0
        chargingPulse = reduced || !charging
            ? 0
            : (sin(date.timeIntervalSinceReferenceDate * .pi * 1.2) + 1) / 2
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
