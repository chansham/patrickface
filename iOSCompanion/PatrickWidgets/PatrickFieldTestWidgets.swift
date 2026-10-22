import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct PatrickFieldTestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PatrickFieldTestActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text("实测")
                    .font(.caption.weight(.semibold))
                Text("\(context.state.sequence)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .widgetAccentable()
                Text(context.state.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .foregroundStyle(.white)
            .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.sequence)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.label)
                        .font(.caption2)
                }
            } compactLeading: {
                Text("测")
            } compactTrailing: {
                Text("\(context.state.sequence)")
                    .monospacedDigit()
            } minimal: {
                Text("\(context.state.sequence)")
                    .monospacedDigit()
            }
        }
    }
}

struct PatrickFieldTestStandByEntry: TimelineEntry {
    let date: Date
}

struct PatrickFieldTestStandByProvider: TimelineProvider {
    func placeholder(in context: Context) -> PatrickFieldTestStandByEntry {
        PatrickFieldTestStandByEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PatrickFieldTestStandByEntry) -> Void) {
        completion(PatrickFieldTestStandByEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PatrickFieldTestStandByEntry>) -> Void) {
        let entry = PatrickFieldTestStandByEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 60))))
    }
}

/// StandBy night mode tints accented content red. This widget only draws.
struct PatrickFieldTestStandByWidget: Widget {
    let kind = "PatrickFieldTestStandByWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PatrickFieldTestStandByProvider()) { _ in
            PatrickFieldTestStandByView()
                .containerBackground(for: .widget) {
                    Color.black
                }
        }
        .configurationDisplayName("实测夜览")
        .description("给待机夜间红色模式看的派大星。不改陪伴状态。")
        .supportedFamilies([.systemSmall])
    }
}

private struct PatrickFieldTestStandByView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(spacing: 6) {
            Image("season1-body-normal")
                .resizable()
                .scaledToFit()
                .widgetAccentable()
            Text(caption)
                .font(.caption2)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var caption: String {
        switch renderingMode {
        case .accented:
            "强调色"
        default:
            "原色"
        }
    }
}

@available(iOS 18.0, *)
struct PatrickFieldTestToggleControl: ControlWidget {
    static let kind = "PatrickFieldTestToggleControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            provider: PatrickFieldTestToggleProvider()
        ) { isOn in
            ControlWidgetToggle(
                "实测开关",
                isOn: isOn,
                action: PatrickFieldTestToggleIntent()
            ) { value in
                Label(value ? "开" : "关", systemImage: value ? "star.fill" : "star")
            }
        }
        .displayName("实测开关")
        .description("锁屏控件。实测入口关掉时，点了也不会记住。")
    }
}

@available(iOS 18.0, *)
struct PatrickFieldTestStartControl: ControlWidget {
    static let kind = "PatrickFieldTestStartControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: PatrickFieldTestWidgetStartIntent()) {
                Label("开始实时活动", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .displayName("实测开始实时活动")
        .description("试着在不打开 App 的情况下开始一条实测实时活动。")
    }
}

@available(iOS 18.0, *)
private struct PatrickFieldTestToggleProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        guard PatrickFieldTestGate.isEnabled() else { return false }
        return PatrickFieldTestToggleStore.value()
    }
}

@available(iOS 18.0, *)
struct PatrickFieldTestToggleIntent: SetValueIntent {
    static let title: LocalizedStringResource = "实测开关"

    @Parameter(title: "开")
    var value: Bool

    func perform() async throws -> some IntentResult {
        guard PatrickFieldTestGate.isEnabled() else {
            PatrickFieldTestLog.append(
                "锁屏控件点了，但实测入口是关的，没有记住。",
                topic: "控件"
            )
            return .result()
        }
        PatrickFieldTestToggleStore.set(value)
        PatrickFieldTestLog.append(
            "锁屏控件点了，现在是\(value ? "开" : "关")。",
            topic: "控件"
        )
        return .result()
    }
}

struct PatrickFieldTestWidgetStartIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "实测：从控件开始实时活动"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = await PatrickFieldTestStarter.start(origin: "control-widget")
        return .result(dialog: "\(line)")
    }
}
