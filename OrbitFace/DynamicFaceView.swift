import SwiftUI

struct DynamicFaceView: View {
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TimelineView(.animation(minimumInterval: dimmed ? 1 : 1.0 / 30.0)) { timeline in
            FaceCanvas(date: timeline.date, dimmed: dimmed)
                .toolbar(.hidden, for: .navigationBar)
        }
        .ignoresSafeArea()
        .background(Color.black)
    }
}

private struct FaceCanvas: View {
    let date: Date
    let dimmed: Bool

    var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
        .background(Color.black)
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let cx = w * 0.5
        let cy = h * 0.445
        let parts = ClockParts(date)
        let breathe = 0.55 + 0.45 * sin(parts.second * .pi * 2)
        let ivory = Color(red: 0.953, green: 0.937, blue: 0.902)
        let gold = Color(red: 0.878, green: 0.761, blue: 0.478)
        let coral = Color(red: 1, green: 0.420, blue: 0.290)

        var bg = Path()
        bg.addRect(CGRect(origin: .zero, size: size))
        context.fill(bg, with: .color(Color(red: 0.03, green: 0.035, blue: 0.05)))

        let glow = Path(ellipseIn: CGRect(x: cx - w * 0.34, y: cy - w * 0.34, width: w * 0.68, height: w * 0.68))
        context.fill(glow, with: .color(gold.opacity(dimmed ? 0.04 : 0.08 + breathe * 0.06)))

        strokeCircle(context: context, center: CGPoint(x: cx, y: cy), radius: w * 0.455, color: gold.opacity(0.35), width: 1)

        if !dimmed {
            let spin = parts.second * (.pi / 30)
            strokeArc(context: context, center: CGPoint(x: cx, y: cy), radius: w * 0.40, start: spin - 0.15, end: spin + .pi * 0.72, color: gold.opacity(0.92), width: 3.5)
            strokeArc(context: context, center: CGPoint(x: cx, y: cy), radius: w * 0.335, start: -spin * 1.6 + 0.4, end: -spin * 1.6 + .pi * 0.95, color: coral.opacity(0.88), width: 2.5)
        }

        for i in 0..<60 {
            let angle = (Double(i) / 60) * .pi * 2 - .pi / 2
            let major = i % 5 == 0
            let inner = w * (major ? 0.392 : 0.418)
            let outer = w * 0.445
            strokeLine(
                context: context,
                from: point(cx, cy, angle, inner),
                to: point(cx, cy, angle, outer),
                color: ivory.opacity(major ? 0.88 : 0.28),
                width: major ? 2 : 1
            )
        }

        let passed = Int(parts.second) % 60
        for i in 0..<60 {
            let angle = (Double(i) / 60) * .pi * 2 - .pi / 2
            let lit = i == passed
            let radius: CGFloat = lit ? 2.5 : 1.1
            let dot = CGPoint(x: cx + CGFloat(cos(angle)) * w * 0.372, y: cy + CGFloat(sin(angle)) * w * 0.372)
            let mark = Path(ellipseIn: CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2))
            context.fill(mark, with: .color(lit ? coral : ivory.opacity(0.16)))
        }

        drawText(context: context, text: parts.weekday, size: w * 0.075, weight: .medium, color: Color(red: 0.655, green: 0.635, blue: 0.580), at: CGPoint(x: cx, y: h * 0.09))
        drawText(context: context, text: parts.dateText, size: w * 0.09, weight: .medium, color: ivory, at: CGPoint(x: cx, y: h * 0.74))

        strokeHand(context: context, center: CGPoint(x: cx, y: cy), angle: parts.hour * (.pi / 6) - .pi / 2, length: w * 0.20, tail: w * 0.035, width: w * 0.016, color: ivory)
        strokeHand(context: context, center: CGPoint(x: cx, y: cy), angle: parts.minute * (.pi / 30) - .pi / 2, length: w * 0.30, tail: w * 0.04, width: w * 0.011, color: ivory)

        if !dimmed {
            let tip = parts.second * (.pi / 30) - .pi / 2
            let orbit = w * 0.40
            for k in stride(from: 16, through: 1, by: -1) {
                let angle = tip - Double(k) * 0.05
                let radius = CGFloat(4 - Double(k) * 0.14)
                let dot = point(cx, cy, angle, orbit)
                let trail = Path(ellipseIn: CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2))
                context.fill(trail, with: .color(coral.opacity(0.28 * (1 - Double(k) / 17))))
            }
            let head = point(cx, cy, tip, orbit)
            let comet = Path(ellipseIn: CGRect(x: head.x - 4.5, y: head.y - 4.5, width: 9, height: 9))
            context.fill(comet, with: .color(coral))
        }

        let cap = Path(ellipseIn: CGRect(x: cx - 8, y: cy - 8, width: 16, height: 16))
        context.fill(cap, with: .color(Color(red: 0.067, green: 0.078, blue: 0.106)))
        let coreRadius: CGFloat = 3.5
        let core = Path(ellipseIn: CGRect(x: cx - coreRadius, y: cy - coreRadius, width: coreRadius * 2, height: coreRadius * 2))
        context.fill(core, with: .color(gold.opacity(dimmed ? 0.7 : 0.65 + breathe * 0.35)))

        drawText(context: context, text: parts.digital, size: w * 0.16, weight: .light, color: ivory, at: CGPoint(x: cx - w * 0.06, y: h * 0.875))
        drawText(context: context, text: parts.secondsText, size: w * 0.08, weight: .semibold, color: coral, at: CGPoint(x: cx + w * 0.22, y: h * 0.885))
    }

    private func point(_ cx: CGFloat, _ cy: CGFloat, _ angle: Double, _ radius: CGFloat) -> CGPoint {
        CGPoint(x: cx + CGFloat(cos(angle)) * radius, y: cy + CGFloat(sin(angle)) * radius)
    }

    private func strokeCircle(context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color, width: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: width)
    }

    private func strokeArc(context: GraphicsContext, center: CGPoint, radius: CGFloat, start: Double, end: Double, color: Color, width: CGFloat) {
        var path = Path()
        let steps = 36
        for step in 0...steps {
            let t = start + (end - start) * Double(step) / Double(steps)
            let p = CGPoint(x: center.x + CGFloat(cos(t)) * radius, y: center.y + CGFloat(sin(t)) * radius)
            if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func strokeLine(context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func strokeHand(context: GraphicsContext, center: CGPoint, angle: Double, length: CGFloat, tail: CGFloat, width: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: center.x + CGFloat(cos(angle + .pi)) * tail, y: center.y + CGFloat(sin(angle + .pi)) * tail))
        path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * length, y: center.y + CGFloat(sin(angle)) * length))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func drawText(context: GraphicsContext, text: String, size: CGFloat, weight: Font.Weight, color: Color, at point: CGPoint) {
        let resolved = context.resolve(
            Text(text)
                .font(.system(size: size, weight: weight, design: .rounded))
                .foregroundStyle(color)
        )
        context.draw(resolved, at: point, anchor: .center)
    }
}

private struct ClockParts {
    var hour: Double
    var minute: Double
    var second: Double
    var weekday: String
    var dateText: String
    var digital: String
    var secondsText: String

    init(_ date: Date) {
        let calendar = Calendar.current
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        let s = calendar.component(.second, from: date)
        let ns = calendar.component(.nanosecond, from: date)
        second = Double(s) + Double(ns) / 1_000_000_000
        minute = Double(m) + second / 60
        hour = Double(h % 12) + minute / 60
        let names = ["週日", "週一", "週二", "週三", "週四", "週五", "週六"]
        weekday = names[calendar.component(.weekday, from: date) - 1]
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        dateText = "\(month)月\(day)日"
        digital = String(format: "%02d:%02d", h, m)
        secondsText = String(format: "%02d", s)
    }
}

#Preview {
    DynamicFaceView()
}
