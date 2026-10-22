import ActivityKit
import SwiftUI
import WidgetKit

struct PatrickLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PatrickActivityAttributes.self) { context in
            PatrickLockScreenActivityView(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.pink)
                .widgetURL(PatrickDeepLinkRoute.timer.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PatrickHeadAvatar(slot: .activity, side: 44, decorative: true)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    PatrickActivityTimerLabel(
                        startedAt: context.attributes.startedAt,
                        state: context.state
                    )
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.pink)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(
                            context.state.statusText,
                            systemImage: context.state.visualState.symbolName
                        )
                        .font(.caption)
                        Spacer()
                        Text("陪伴計時")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                PatrickHeadAvatar(slot: .circular, side: 20, decorative: true)
            } compactTrailing: {
                PatrickActivityTimerLabel(
                    startedAt: context.attributes.startedAt,
                    state: context.state
                )
                .font(.caption2.monospacedDigit())
                .frame(maxWidth: 52)
            } minimal: {
                PatrickHeadAvatar(slot: .corner, side: 16, decorative: true)
            }
            .keylineTint(.pink)
            .widgetURL(PatrickDeepLinkRoute.timer.url)
        }
    }
}

private struct PatrickLockScreenActivityView: View {
    @Environment(\.isActivityFullscreen) private var isActivityFullscreen
    let context: ActivityViewContext<PatrickActivityAttributes>

    var body: some View {
        HStack(spacing: isActivityFullscreen ? 22 : 14) {
            PatrickHeadAvatar(
                slot: .activity,
                side: isActivityFullscreen ? 96 : 64,
                decorative: true
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(context.attributes.title)
                    .font(isActivityFullscreen ? .title2.bold() : .headline)
                    .lineLimit(1)

                Label(
                    context.state.statusText,
                    systemImage: context.state.visualState.symbolName
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                PatrickActivityTimerLabel(
                    startedAt: context.attributes.startedAt,
                    state: context.state
                )
                .font(
                    .system(
                        size: isActivityFullscreen ? 42 : 28,
                        weight: .light,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(.pink)
            }

            Spacer(minLength: 0)
        }
        .padding(isActivityFullscreen ? 24 : 14)
        .foregroundStyle(.white)
        .background(Color.black)
    }
}

private struct PatrickActivityTimerLabel: View {
    let startedAt: Date
    let state: PatrickActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text("已暫停")
        } else if let endsAt = state.endsAt {
            Text(timerInterval: startedAt ... endsAt, countsDown: true)
        } else {
            Text(state.statusText)
        }
    }
}
