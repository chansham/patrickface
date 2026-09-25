import SwiftUI

struct PatrickMotionLabView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = MotionController()
    @State private var showRig = false

    private let manifest = AnchorManifest.load()

    var body: some View {
        TimelineView(MotionTimelineSchedule(lowPower: controller.lowPowerMode)) { timeline in
            let date = controller.renderDate(from: timeline.date)
            let tier = performanceTier
            let pose = MotionMath.makePose(
                date: date,
                tier: tier,
                currentMode: controller.mode,
                previousMode: controller.previousMode,
                modeChangedAt: controller.modeChangedAt,
                crown: controller.crown,
                lowBattery: controller.lowBattery,
                charging: controller.charging,
                idleStartedAt: controller.idleStartedAt,
                tapStartedAt: controller.tapStartedAt,
                blinkStartedAt: controller.blinkStartedAt,
                spriteStartedAt: controller.spriteStartedAt
            )

            ZStack {
                Canvas { context, size in
                    drawScene(context: &context, size: size, date: date, pose: pose)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.triggerTap(at: date)
                }
                .onLongPressGesture(minimumDuration: 0.55) {
                    controller.triggerSprite(at: date)
                }

                if tier == .active {
                    VStack(spacing: 0) {
                        Spacer()
                        controlStrip(date: date)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 3)
                }
            }
            .focusable()
            .digitalCrownRotation(
                $controller.crown,
                from: 0,
                through: 1,
                by: 0.02,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .background(Color.black)
            .ignoresSafeArea()
            .accessibilityLabel("Patrick motion lab")
            .accessibilityValue(
                "\(controller.mode.rawValue), \(tier.rawValue), hand return error \(pose.maximumHandError)"
            )
        }
    }

    private var performanceTier: MotionPerformanceTier {
        if controller.lowPowerMode { return .lowPower }
        if isLuminanceReduced || scenePhase != .active { return .alwaysOn }
        return .active
    }

    @ViewBuilder
    private func controlStrip(date: Date) -> some View {
        HStack(spacing: 7) {
            labButton("hand.wave.fill", label: "Gesture") {
                controller.triggerIdle(at: date)
            }
            labButton("moon.stars.fill", label: "Mode") {
                controller.cycleMode(at: date)
            }
            labButton("battery.25percent", label: "Power") {
                controller.cyclePowerState()
            }
            labButton("square.grid.3x3.fill", label: "Frame clip") {
                controller.triggerSprite(at: date)
            }
            labButton(showRig ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted", label: "Rig") {
                showRig.toggle()
            }
            Button {
                controller.runVerification()
            } label: {
                Text(controller.verificationLabel)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(controller.verificationLabel.hasPrefix("PASS") ? .mint : .white)
                    .frame(minWidth: 29, minHeight: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Run exact hand return verification")
        }
        .padding(.horizontal, 7)
        .background(.black.opacity(0.46), in: Capsule())
    }

    private func labButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 18, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func drawScene(
        context: inout GraphicsContext,
        size: CGSize,
        date: Date,
        pose: MotionPose
    ) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

        let scale = min(size.width / 360, size.height / 440)
        let offset = CGPoint(
            x: (size.width - 360 * scale) / 2,
            y: (size.height - 440 * scale) / 2
        )
        var scene = context
        scene.translateBy(x: offset.x, y: offset.y)
        scene.scaleBy(x: scale, y: scale)

        drawBackdrop(context: &scene, pose: pose)
        drawTicks(context: &scene, dimmed: pose.tier != .active)
        drawTime(context: &scene, date: date, pose: pose)

        let hourPivot = manifest.point("hourArmPivot", default: CGPoint(x: 180, y: 240))
        let minutePivot = manifest.point("minuteArmPivot", default: CGPoint(x: 180, y: 240))

        var rig = scene
        rig.translateBy(x: 0, y: CGFloat(-9 * pose.tapWeight + 12 * pose.slump))
        rig.translateBy(x: 180, y: 240)
        rig.rotate(by: .degrees(4.5 * pose.slump))
        let tapScale = CGFloat(1 + 0.045 * pose.tapWeight)
        rig.scaleBy(x: tapScale, y: tapScale)
        rig.translateBy(x: -180, y: -240)

        drawHand(
            context: &rig,
            pivot: minutePivot,
            degrees: pose.minuteActual,
            length: 149,
            width: 30,
            color: Color(red: 0.94, green: 0.54, blue: 0.63)
        )
        drawHand(
            context: &rig,
            pivot: hourPivot,
            degrees: pose.hourActual,
            length: 115,
            width: 34,
            color: Color(red: 0.91, green: 0.47, blue: 0.57)
        )

        let points = deformedBodyPoints(pose: pose)
        drawBody(context: &rig, points: points)
        drawShorts(context: &rig, crown: pose.crown)
        drawFace(context: &rig, date: date, pose: pose)
        drawFrameLoopClip(context: &rig, frame: pose.spriteFrame)

        if showRig && pose.tier == .active {
            drawRigOverlay(context: &rig, points: points, pivot: hourPivot)
        }
    }

    private func drawBackdrop(context: inout GraphicsContext, pose: MotionPose) {
        let base = Path(CGRect(x: 0, y: 0, width: 360, height: 440))
        let activeColor = Color(red: 0.025, green: 0.09, blue: 0.135)
        context.fill(base, with: .color(activeColor))

        if pose.focusAmount > 0 {
            context.fill(base, with: .color(.indigo.opacity(0.24 * pose.focusAmount)))
        }
        if pose.sleepAmount > 0 {
            context.fill(base, with: .color(Color(red: 0.01, green: 0.015, blue: 0.07).opacity(0.74 * pose.sleepAmount)))
        }
        if pose.tier != .active {
            context.fill(base, with: .color(.black.opacity(pose.tier == .lowPower ? 0.72 : 0.48)))
        }

        let glow = Path(ellipseIn: CGRect(x: 68, y: 100, width: 224, height: 270))
        context.fill(
            glow,
            with: .radialGradient(
                Gradient(colors: [.cyan.opacity(pose.tier == .active ? 0.17 : 0.04), .clear]),
                center: CGPoint(x: 180, y: 235),
                startRadius: 5,
                endRadius: 142
            )
        )

        if pose.chargingPulse > 0 {
            let radius = CGFloat(137 + 7 * pose.chargingPulse)
            let ring = Path(ellipseIn: CGRect(
                x: 180 - radius,
                y: 236 - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.stroke(ring, with: .color(.mint.opacity(0.18 + 0.48 * pose.chargingPulse)), lineWidth: 5)
        }
    }

    private func drawTicks(context: inout GraphicsContext, dimmed: Bool) {
        for index in 0..<12 {
            let angle = Double(index) * .pi / 6 - .pi / 2
            let major = index.isMultiple(of: 3)
            let outer = CGPoint(
                x: 180 + cos(angle) * 158,
                y: 236 + sin(angle) * 158
            )
            let innerRadius = major ? 145.0 : 151.0
            let inner = CGPoint(
                x: 180 + cos(angle) * innerRadius,
                y: 236 + sin(angle) * innerRadius
            )
            var path = Path()
            path.move(to: inner)
            path.addLine(to: outer)
            context.stroke(
                path,
                with: .color(.white.opacity(dimmed ? 0.24 : (major ? 0.78 : 0.35))),
                style: StrokeStyle(lineWidth: major ? 3 : 2, lineCap: .round)
            )
        }
    }

    private func drawTime(context: inout GraphicsContext, date: Date, pose: MotionPose) {
        let time = date.formatted(date: .omitted, time: .shortened)
        context.draw(
            Text(time)
                .font(.system(size: 27, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(pose.tier == .lowPower ? 0.58 : 0.95)),
            at: CGPoint(x: 180, y: 34),
            anchor: .center
        )
        context.draw(
            Text("\(pose.tier.rawValue.uppercased()) · \(controller.mode.rawValue.uppercased())")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42)),
            at: CGPoint(x: 180, y: 57),
            anchor: .center
        )
    }

    private func drawHand(
        context: inout GraphicsContext,
        pivot: CGPoint,
        degrees: Double,
        length: CGFloat,
        width: CGFloat,
        color: Color
    ) {
        var arm = context
        arm.translateBy(x: pivot.x, y: pivot.y)
        arm.rotate(by: .degrees(degrees))

        var path = Path()
        path.move(to: CGPoint(x: -width / 2, y: 3))
        path.addCurve(
            to: CGPoint(x: -width * 0.27, y: -length + 9),
            control1: CGPoint(x: -width * 0.72, y: -length * 0.28),
            control2: CGPoint(x: -width * 0.49, y: -length * 0.74)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.27, y: -length + 9),
            control1: CGPoint(x: -width * 0.14, y: -length - 7),
            control2: CGPoint(x: width * 0.14, y: -length - 7)
        )
        path.addCurve(
            to: CGPoint(x: width / 2, y: 3),
            control1: CGPoint(x: width * 0.49, y: -length * 0.74),
            control2: CGPoint(x: width * 0.72, y: -length * 0.28)
        )
        path.closeSubpath()
        arm.fill(path, with: .color(color))
        arm.stroke(path, with: .color(Color(red: 0.34, green: 0.16, blue: 0.25)), lineWidth: 4)

        let tip = Path(ellipseIn: CGRect(
            x: -width * 0.38,
            y: -length - width * 0.38,
            width: width * 0.76,
            height: width * 0.76
        ))
        arm.fill(tip, with: .color(color))
        arm.stroke(tip, with: .color(Color(red: 0.34, green: 0.16, blue: 0.25)), lineWidth: 4)
    }

    private func deformedBodyPoints(pose: MotionPose) -> [CGPoint] {
        let source = manifest.bodyControlPoints.isEmpty
            ? AnchorManifest.fallback.bodyControlPoints
            : manifest.bodyControlPoints
        let breath = pose.breath * 2.5
        return source.enumerated().map { index, point in
            let verticalWeight = max(0, 1 - abs(point.y - 225) / 170)
            let side = point.x == 180 ? 0 : (point.x > 180 ? 1.0 : -1.0)
            var next = point
            next.x += side * breath * verticalWeight
            if index == 0 { next.y -= breath * 0.8 }
            if pose.slump > 0 {
                next.x += point.y < 230 ? 5 : 1
                next.y += point.y < 240 ? 7 : 3
            }
            return next
        }
    }

    private func bodyPath(points: [CGPoint]) -> Path {
        guard let first = points.first, let last = points.last else { return Path() }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        var path = Path()
        path.move(to: midpoint(last, first))
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(to: midpoint(points[index], next), control: points[index])
        }
        path.closeSubpath()
        return path
    }

    private func drawBody(context: inout GraphicsContext, points: [CGPoint]) {
        let body = bodyPath(points: points)
        context.fill(
            body,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1, green: 0.60, blue: 0.68),
                    Color(red: 0.72, green: 0.27, blue: 0.39)
                ]),
                startPoint: CGPoint(x: 125, y: 115),
                endPoint: CGPoint(x: 245, y: 340)
            )
        )
        context.stroke(body, with: .color(Color(red: 0.34, green: 0.16, blue: 0.25)), lineWidth: 4)
    }

    private func drawShorts(context: inout GraphicsContext, crown: Double) {
        var path = Path()
        path.move(to: CGPoint(x: 116, y: 319))
        path.addQuadCurve(to: CGPoint(x: 244, y: 319), control: CGPoint(x: 180, y: 342))
        path.addLine(to: CGPoint(x: 241, y: 371))
        path.addQuadCurve(to: CGPoint(x: 199, y: 369), control: CGPoint(x: 218, y: 382))
        path.addLine(to: CGPoint(x: 190, y: 348))
        path.addLine(to: CGPoint(x: 170, y: 348))
        path.addLine(to: CGPoint(x: 161, y: 369))
        path.addQuadCurve(to: CGPoint(x: 118, y: 371), control: CGPoint(x: 140, y: 382))
        path.closeSubpath()

        let green = Color(
            hue: MotionMath.lerp(0.21, 0.54, crown),
            saturation: 0.62,
            brightness: 0.78
        )
        context.fill(path, with: .color(green))
        context.stroke(path, with: .color(Color(red: 0.30, green: 0.18, blue: 0.29)), lineWidth: 4)

        context.fill(
            Path(ellipseIn: CGRect(x: 125, y: 335, width: 28, height: 30)),
            with: .color(.purple.opacity(0.78))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: 200, y: 334, width: 31, height: 28)),
            with: .color(.purple.opacity(0.78))
        )
    }

    private func drawFace(context: inout GraphicsContext, date: Date, pose: MotionPose) {
        let eyeScale = max(0.075, 1 - max(pose.blink * 0.94, pose.sleepAmount * 0.925))
        let attention = date.timeIntervalSinceReferenceDate
        let attentionX = sin(attention * 0.65) * 4 * (1 - pose.sleepAmount)
        let attentionY = cos(attention * 0.43) * 2 * (1 - pose.sleepAmount)

        for centerX in [158.0, 202.0] {
            let eyeRect = CGRect(
                x: centerX - 22,
                y: 188 - 25 * eyeScale,
                width: 44,
                height: 50 * eyeScale
            )
            let eye = Path(ellipseIn: eyeRect)
            context.fill(eye, with: .color(Color(red: 0.96, green: 0.95, blue: 0.82)))
            context.stroke(eye, with: .color(Color(red: 0.33, green: 0.16, blue: 0.24)), lineWidth: 3)
            if eyeScale > 0.2 {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: centerX + attentionX - 3,
                        y: 188 + attentionY - 2,
                        width: 12,
                        height: 12
                    )),
                    with: .color(Color(red: 0.08, green: 0.05, blue: 0.08))
                )
            }
        }

        let browLift = MotionMath.lerp(0, -5, pose.crown) - 2 * pose.focusAmount
        for (start, end) in [(137.0, 175.0), (185.0, 223.0)] {
            var brow = Path()
            brow.move(to: CGPoint(x: start, y: 157 + browLift))
            brow.addQuadCurve(
                to: CGPoint(x: end, y: 157 + browLift),
                control: CGPoint(x: (start + end) / 2, y: 149 + browLift)
            )
            context.stroke(
                brow,
                with: .color(Color(red: 0.33, green: 0.16, blue: 0.24)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
        }

        var mouth = Path()
        mouth.move(to: CGPoint(x: 149, y: 232))
        mouth.addQuadCurve(
            to: CGPoint(x: 211, y: 232),
            control: CGPoint(x: 180, y: 250 + pose.crown * 8 - pose.sleepAmount * 2)
        )
        context.stroke(
            mouth,
            with: .color(Color(red: 0.33, green: 0.16, blue: 0.24)),
            style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )

        if pose.sleepAmount > 0.01 {
            let pulse = (sin(attention * 2.2) + 1) * 2.2
            let bubble = Path(ellipseIn: CGRect(
                x: 215 - pulse,
                y: 213 - pulse,
                width: (5 + pulse) * 2,
                height: (5 + pulse) * 2
            ))
            context.fill(bubble, with: .color(.cyan.opacity(0.45 * pose.sleepAmount)))
        }
    }

    private func drawFrameLoopClip(context: inout GraphicsContext, frame: Int?) {
        guard let frame else { return }
        let progress = Double(frame) / Double(max(1, MotionMath.spriteFrameCount - 1))
        let center = CGPoint(x: 242 + cos(progress * .pi) * 12, y: 128 - progress * 20)
        let radius = CGFloat(5 + frame)
        context.stroke(
            Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )),
            with: .color(.cyan.opacity(0.85 - progress * 0.5)),
            lineWidth: 2
        )
        if frame >= 2 {
            var sparkle = Path()
            sparkle.move(to: CGPoint(x: 223, y: 109))
            sparkle.addLine(to: CGPoint(x: 228, y: 120))
            sparkle.addLine(to: CGPoint(x: 239, y: 125))
            sparkle.addLine(to: CGPoint(x: 228, y: 130))
            sparkle.addLine(to: CGPoint(x: 223, y: 141))
            sparkle.addLine(to: CGPoint(x: 218, y: 130))
            sparkle.addLine(to: CGPoint(x: 207, y: 125))
            sparkle.addLine(to: CGPoint(x: 218, y: 120))
            sparkle.closeSubpath()
            context.fill(sparkle, with: .color(.yellow.opacity(1 - progress * 0.45)))
        }
    }

    private func drawRigOverlay(
        context: inout GraphicsContext,
        points: [CGPoint],
        pivot: CGPoint
    ) {
        let outline = bodyPath(points: points)
        context.stroke(
            outline,
            with: .color(.mint.opacity(0.9)),
            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
        )
        for point in points {
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                with: .color(.mint)
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: pivot.x - 6, y: pivot.y - 6, width: 12, height: 12)),
            with: .color(.yellow)
        )
    }
}

#Preview {
    PatrickMotionLabView()
}
