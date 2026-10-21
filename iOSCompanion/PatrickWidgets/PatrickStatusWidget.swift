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
            Label("派大星 · \(state.settings.mood.title)", systemImage: "heart.fill")
        case .accessoryCircular:
            ZStack { AccessoryWidgetBackground(); VStack { Image(systemName: "heart.fill").widgetAccentable(); Text("\(state.care.bond)").font(.caption2) } }
        default:
            VStack(alignment: .leading, spacing: 5) {
                Label("派大星 · \(state.settings.mood.title)", systemImage: "star.fill").font(.headline).widgetAccentable()
                Text("飽足 \(Int(state.care.satiety.rounded())) · 親密 \(state.care.bond)").font(.caption)
                if let activity = state.activity, activity.status == .running, let end = activity.endsAt, end > entry.date {
                    Text(activity.kind.title).font(.caption2)
                    Text(timerInterval: activity.startedAt...end, countsDown: true).monospacedDigit()
                } else if let activity = state.activity, activity.status == .paused {
                    Text("\(activity.kind.title)已暫停").font(.caption)
                } else { Text("點一下，來陪牠").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
