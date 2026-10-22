import SwiftUI
import WidgetKit

struct PatrickWidgetEntry: TimelineEntry {
    let date: Date
    let settings: PatrickSettings
    let timer: PatrickTimerSnapshot
    var relevance: TimelineEntryRelevance? {
        let experience = settings.experience ?? PatrickExperienceState()
        let value = PatrickStackRelevance.make(experience: experience, at: date)
        return TimelineEntryRelevance(score: value.score, duration: value.duration)
    }
}

struct PatrickWidgetProvider: TimelineProvider {
    private let store = PatrickSharedStore.shared

    func placeholder(in context: Context) -> PatrickWidgetEntry {
        PatrickWidgetEntry(
            date: .now,
            settings: .defaults,
            timer: .inactive
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PatrickWidgetEntry) -> Void
    ) {
        completion(
            PatrickWidgetEntry(
                date: .now,
                settings: store.loadSettings(),
                timer: store.loadTimer()
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<PatrickWidgetEntry>) -> Void
    ) {
        let entry = PatrickWidgetEntry(
            date: .now,
            settings: store.loadSettings(),
            timer: store.loadTimer()
        )
        let nextRefresh = Calendar.current.date(
            byAdding: .minute,
            value: 15,
            to: .now
        ) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct PatrickStatusWidget: Widget {
    let kind = "PatrickStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PatrickWidgetProvider()) { entry in
            PatrickStatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.black
                }
                .widgetURL(PatrickDeepLinkRoute.openWatchFace.url)
        }
        .configurationDisplayName("派大星陪伴")
        .description("心情、照顧狀態和陪伴倒數；點一下開App。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline,
        ])
    }
}

private struct PatrickStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PatrickWidgetEntry
    private var state: PatrickExperienceState {
        var value = entry.settings.experience ?? PatrickExperienceState()
        _ = value.updateCare(at: entry.date)
        return value
    }
    var body: some View {
        switch family {
        case .accessoryInline:
            // Inline slots accept one SF Symbol, not a custom image.
            Label("派大星 · \(state.settings.mood.title)", systemImage: "heart.fill")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                PatrickHeadAvatar(slot: .circular).padding(4)
            }
        case .accessoryCorner:
            PatrickHeadAvatar(slot: .corner)
                .widgetLabel { Text(state.settings.mood.title) }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                PatrickHeadAvatar(slot: .rectangular, side: 36, decorative: true)
                statusText
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                PatrickHeadAvatar(slot: .activity, side: 52, decorative: true)
                statusText
            }
        default:
            HStack(alignment: .center, spacing: 10) {
                PatrickHeadAvatar(slot: .activity, side: family == .systemLarge ? 88 : 64, decorative: true)
                statusText
            }
        }
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("派大星 · \(state.settings.mood.title)")
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            Text(state.displayedMood(at: entry.date).title).font(.caption).lineLimit(1)
            if let activity = state.activity, activity.status == .running, let end = activity.endsAt, end > entry.date {
                Text(activity.kind.title).font(.caption2)
                Text(timerInterval: activity.startedAt...end, countsDown: true).monospacedDigit()
            } else if let activity = state.activity, activity.status == .paused {
                Text("\(activity.kind.title)已暫停").font(.caption)
            } else {
                Text("我在這").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
