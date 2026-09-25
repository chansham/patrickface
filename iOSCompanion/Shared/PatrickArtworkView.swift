import SwiftUI

struct PatrickArtworkView: View {
    let theme: PatrickTheme
    let state: PatrickVisualState
    var animated = true

    private static let hubYOffset: CGFloat = 0.045
    private static let hourHeightScale: CGFloat = 0.38
    private static let minuteHeightScale: CGFloat = 0.52

    var body: some View {
        TimelineView(.animation(minimumInterval: animated ? 1.0 / 12.0 : 60)) { context in
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let phase = animated
                    ? context.date.timeIntervalSinceReferenceDate
                    : 0
                let hourDegrees = hourAngle(for: context.date)
                let minuteDegrees = minuteAngle(for: context.date)

                ZStack {
                    Color.black

                    if state == .charging {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.mint.opacity(0.34 + 0.10 * sin(phase * 2)),
                                        .clear,
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: side * 0.50
                                )
                            )
                            .frame(width: side, height: side)
                    }

                    bodyLayer(side: side)

                    arm(
                        asset: theme.minuteArmAssetName,
                        angle: minuteDegrees,
                        side: side,
                        widthScale: 0.18,
                        heightScale: Self.minuteHeightScale
                    )

                    arm(
                        asset: theme.hourArmAssetName,
                        angle: hourDegrees,
                        side: side,
                        widthScale: 0.22,
                        heightScale: Self.hourHeightScale
                    )

                    Circle()
                        .fill(
                            theme == .faithful3D
                                ? Color(red: 0.91, green: 0.36, blue: 0.33)
                                : Color(red: 0.97, green: 0.47, blue: 0.44)
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color(red: 0.33, green: 0.16, blue: 0.18),
                                    lineWidth: side * 0.0035
                                )
                        }
                        .frame(width: side * 0.028, height: side * 0.028)
                        .offset(y: side * Self.hubYOffset)

                    stateOverlay(side: side, phase: phase)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .background(Color.black)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.displayName), \(state.displayName)")
    }

    private func bodyLayer(side: CGFloat) -> some View {
        Image(theme.bodyAssetName)
            .resizable()
            .scaledToFit()
            .frame(width: side * 0.45, height: side * 0.78)
            .scaleEffect(
                x: state == .lowBattery ? 1.03 : 1,
                y: state == .lowBattery ? 0.94 : 1,
                anchor: .bottom
            )
            .offset(y: state == .lowBattery ? side * 0.035 : side * 0.02)
            .opacity(state == .sleeping ? 0.72 : 1)
    }

    private func arm(
        asset: String,
        angle: Double,
        side: CGFloat,
        widthScale: CGFloat,
        heightScale: CGFloat
    ) -> some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(width: side * widthScale, height: side * heightScale)
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .offset(
                y: side * (Self.hubYOffset - heightScale / 2)
            )
            .opacity(state == .sleeping ? 0.58 : 0.94)
    }

    @ViewBuilder
    private func stateOverlay(side: CGFloat, phase: TimeInterval) -> some View {
        switch state {
        case .normal:
            EmptyView()
        case .sleeping:
            Text("Z")
                .font(.system(size: side * 0.11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.purple.opacity(0.72))
                .offset(
                    x: side * 0.28,
                    y: -side * (0.24 + 0.025 * CGFloat(sin(phase)))
                )
        case .lowBattery:
            Image(systemName: "battery.25percent")
                .font(.system(size: side * 0.075, weight: .semibold))
                .foregroundStyle(.orange)
                .offset(x: -side * 0.34, y: -side * 0.34)
        case .charging:
            Image(systemName: "bolt.fill")
                .font(.system(size: side * 0.075, weight: .bold))
                .foregroundStyle(.mint)
                .offset(x: -side * 0.34, y: -side * 0.34)
        }
    }

    private func hourAngle(for date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double((components.hour ?? 0) % 12)
        let minute = Double(components.minute ?? 0)
        return hour * 30 + minute * 0.5
    }

    private func minuteAngle(for date: Date) -> Double {
        let components = Calendar.current.dateComponents([.minute, .second], from: date)
        let minute = Double(components.minute ?? 0)
        let second = Double(components.second ?? 0)
        return minute * 6 + second * 0.1
    }

}

#Preview {
    PatrickArtworkView(theme: .cel1999, state: .charging)
        .frame(width: 340, height: 420)
        .background(.black)
}
