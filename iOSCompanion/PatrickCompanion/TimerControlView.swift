import SwiftUI

struct TimerControlView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedMinutes = 15

    private let presets = [5, 15, 25, 45]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.09), lineWidth: 18)
                        Circle()
                            .trim(from: 0, to: model.timer.status == .running ? 0.74 : 0.02)
                            .stroke(
                                AngularGradient(
                                    colors: [.pink, .purple, .pink],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 18, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 8) {
                            Image(systemName: model.timer.status == .running ? "star.fill" : "timer")
                                .font(.title)
                                .foregroundStyle(.pink)

                            if
                                model.timer.status == .running,
                                let endsAt = model.timer.endsAt
                            {
                                Text(
                                    timerInterval: model.timer.startedAt ... endsAt,
                                    countsDown: true
                                )
                                .font(.system(size: 38, weight: .light, design: .rounded))
                                .monospacedDigit()
                            } else {
                                Text("\(selectedMinutes):00")
                                    .font(.system(size: 38, weight: .light, design: .rounded))
                                    .monospacedDigit()
                            }

                            Text(model.timer.status == .running ? "LIVE ACTIVITY" : "READY")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.secondary)
                                .tracking(1)
                        }
                    }
                    .frame(width: 260, height: 260)
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("DURATION")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            ForEach(presets, id: \.self) { minutes in
                                Button {
                                    selectedMinutes = minutes
                                } label: {
                                    Text("\(minutes)m")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                            selectedMinutes == minutes
                                                ? Color.pink
                                                : Color.white.opacity(0.08),
                                            in: RoundedRectangle(
                                                cornerRadius: 13,
                                                style: .continuous
                                            )
                                        )
                                        .foregroundStyle(
                                            selectedMinutes == minutes
                                                ? Color.black
                                                : Color.white
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if model.timer.status == .running {
                        Button(role: .destructive) {
                            Task { await model.stopTimer() }
                        } label: {
                            Label("End Timer", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            Task { await model.startTimer(minutes: selectedMinutes) }
                        } label: {
                            Label("Start Live Activity", systemImage: "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            model.activityController.authorizationEnabled
                                ? "Live Activities allowed"
                                : "Live Activities disabled",
                            systemImage: model.activityController.authorizationEnabled
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(
                            model.activityController.authorizationEnabled
                                ? Color.green
                                : Color.orange
                        )

                        Text(
                            "The Lock Screen presentation also scales into StandBy. "
                            + "Dynamic Island layouts appear only on supported iPhone models."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        if let error = model.activityController.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Patrick Timer")
            .toolbarBackground(.black, for: .navigationBar)
        }
    }
}
