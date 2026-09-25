import SwiftUI
import WidgetKit

private struct PatrickComplicationEntry: TimelineEntry {
    let date: Date
    let theme: PatrickTheme
    let status: PatrickFaceStatus

    var deepLinkURL: URL? {
        PatrickDeepLink(
            // The shared store is authoritative. Omitting a theme here prevents
            // a delayed WidgetKit entry from restoring a stale selection.
            theme: nil,
            source: .complication
        ).url
    }
}

private struct PatrickComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> PatrickComplicationEntry {
        PatrickComplicationEntry(
            date: .now,
            theme: .cel,
            status: .ready
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PatrickComplicationEntry) -> Void
    ) {
        completion(makeEntry(for: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<PatrickComplicationEntry>) -> Void
    ) {
        let now = Date()
        let calendar = Calendar.current
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        var entries = [makeEntry(for: now)]

        // Minute entries are precomputed for one hour. WidgetKit can advance the
        // clock without spending a reload request each minute; the app explicitly
        // reloads this kind only when the shared theme or status actually changes.
        for offset in 1...60 {
            guard let date = calendar.date(
                byAdding: .minute,
                value: offset,
                to: minuteStart
            ) else {
                continue
            }
            entries.append(makeEntry(for: date))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func makeEntry(for date: Date) -> PatrickComplicationEntry {
        let state = PatrickSharedStore.load()
        let statusAge = date.timeIntervalSince(state.updatedAt)
        let statusIsFresh = statusAge >= 0 && statusAge < 30 * 60
        return PatrickComplicationEntry(
            date: date,
            theme: state.theme,
            status: statusIsFresh ? state.status : .ready
        )
    }
}

private struct PatrickComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PatrickComplicationEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circular
            case .accessoryRectangular:
                rectangular
            case .accessoryInline:
                inline
            default:
                rectangular
            }
        }
        .widgetURL(entry.deepLinkURL)
        .containerBackground(for: .widget) {
            Color.black
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(entry.theme.displayName)，\(entry.status.complicationLabel)"
        )
    }

    private var circular: some View {
        ZStack {
            Color.black
            PatrickComplicationDial(date: entry.date)
                .padding(2)
            VStack(spacing: 0) {
                Text(entry.theme == .cel ? "CEL" : "3D")
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer(minLength: 0)
                Text(entry.date, style: .time)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 4)
        }
    }

    private var rectangular: some View {
        HStack(spacing: 7) {
            PatrickComplicationDial(date: entry.date)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.date, style: .time)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(entry.theme.complicationLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(PatrickComplicationPalette.pink)
                Text(entry.status.complicationLabel)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .background(Color.black)
    }

    private var inline: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
            Text(entry.date, style: .time)
                .monospacedDigit()
            Text("· \(entry.theme.complicationLabel)")
        }
    }
}

private enum PatrickComplicationPalette {
    static let pink = Color(red: 0.88, green: 0.40, blue: 0.43)
    static let outline = Color(red: 0.24, green: 0.10, blue: 0.12)
}

private struct PatrickComplicationDial: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height * 0.52)
            let clock = PatrickClockAngles.make(for: date)

            for index in 0..<12 {
                let angle = Double(index) * Double.pi / 6 - Double.pi / 2
                let x = CGFloat(cos(angle))
                let y = CGFloat(sin(angle))
                let outerRadius = side * 0.47
                let innerRadius = side * (index.isMultiple(of: 3) ? 0.39 : 0.42)
                var marker = Path()
                marker.move(
                    to: CGPoint(
                        x: center.x + x * outerRadius,
                        y: center.y + y * outerRadius
                    )
                )
                marker.addLine(
                    to: CGPoint(
                        x: center.x + x * innerRadius,
                        y: center.y + y * innerRadius
                    )
                )
                context.stroke(
                    marker,
                    with: .color(
                        .white.opacity(index.isMultiple(of: 3) ? 0.58 : 0.2)
                    ),
                    style: StrokeStyle(
                        lineWidth: index.isMultiple(of: 3) ? 1.5 : 0.8,
                        lineCap: .round
                    )
                )
            }

            drawArm(
                context: &context,
                pivot: CGPoint(x: center.x - side * 0.025, y: center.y),
                angle: clock.hour,
                length: side * 0.28,
                width: side * 0.115
            )
            drawArm(
                context: &context,
                pivot: CGPoint(x: center.x + side * 0.025, y: center.y),
                angle: clock.minute,
                length: side * 0.37,
                width: side * 0.085
            )

            var body = Path()
            body.move(to: CGPoint(x: center.x, y: center.y - side * 0.16))
            body.addQuadCurve(
                to: CGPoint(x: center.x - side * 0.16, y: center.y + side * 0.16),
                control: CGPoint(x: center.x - side * 0.08, y: center.y)
            )
            body.addQuadCurve(
                to: CGPoint(x: center.x + side * 0.16, y: center.y + side * 0.16),
                control: CGPoint(x: center.x, y: center.y + side * 0.22)
            )
            body.addQuadCurve(
                to: CGPoint(x: center.x, y: center.y - side * 0.16),
                control: CGPoint(x: center.x + side * 0.08, y: center.y)
            )
            body.closeSubpath()
            context.fill(body, with: .color(PatrickComplicationPalette.pink))
            context.stroke(
                body,
                with: .color(PatrickComplicationPalette.outline.opacity(0.75)),
                lineWidth: max(0.7, side * 0.018)
            )

            let eyeSize = side * 0.035
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - side * 0.045,
                        y: center.y - side * 0.03,
                        width: eyeSize,
                        height: eyeSize
                    )
                ),
                with: .color(.black.opacity(0.8))
            )
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: center.x + side * 0.01,
                        y: center.y - side * 0.03,
                        width: eyeSize,
                        height: eyeSize
                    )
                ),
                with: .color(.black.opacity(0.8))
            )
        }
    }

    private func drawArm(
        context: inout GraphicsContext,
        pivot: CGPoint,
        angle: Double,
        length: CGFloat,
        width: CGFloat
    ) {
        var armContext = context
        armContext.translateBy(x: pivot.x, y: pivot.y)
        armContext.rotate(by: .degrees(angle))

        var arm = Path()
        arm.move(to: CGPoint(x: -width / 2, y: 0))
        arm.addQuadCurve(
            to: CGPoint(x: 0, y: -length),
            control: CGPoint(x: -width * 0.32, y: -length * 0.72)
        )
        arm.addQuadCurve(
            to: CGPoint(x: width / 2, y: 0),
            control: CGPoint(x: width * 0.32, y: -length * 0.72)
        )
        arm.closeSubpath()

        armContext.fill(arm, with: .color(PatrickComplicationPalette.pink))
        armContext.stroke(
            arm,
            with: .color(PatrickComplicationPalette.outline.opacity(0.72)),
            lineWidth: max(0.6, width * 0.1)
        )
    }
}

private struct PatrickFaceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: PatrickSharedStore.complicationKind,
            provider: PatrickComplicationProvider()
        ) { entry in
            PatrickComplicationView(entry: entry)
        }
        .configurationDisplayName("Patrick 1999")
        .description("真正時分手臂、數字時間與目前主題。")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}

@main
struct PatrickFaceComplicationsBundle: WidgetBundle {
    var body: some Widget {
        PatrickFaceComplication()
    }
}
