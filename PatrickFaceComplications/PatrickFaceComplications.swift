import SwiftUI
import WidgetKit

private struct PatrickComplicationEntry: TimelineEntry {
    let date: Date
    let theme: PatrickTheme
    let status: PatrickFaceStatus
    var experience = PatrickExperienceState()
    var relevance: TimelineEntryRelevance? {
        let value = PatrickStackRelevance.make(experience: experience, at: date)
        return TimelineEntryRelevance(score: value.score, duration: value.duration)
    }

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
        var experience = PatrickExperienceState.load(from: PatrickSharedStore.defaults)
        _ = experience.updateCare(at: date)
        return PatrickComplicationEntry(
            date: date,
            theme: state.theme,
            status: statusIsFresh ? state.status : .ready,
            experience: experience
        )
    }
}

private struct PatrickComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PatrickComplicationEntry
    var body: some View {
        Group {
            if family == .accessoryInline {
                Label("派大星 · \(entry.experience.settings.mood.title)", systemImage: "heart.fill")
            } else if family == .accessoryCircular {
                VStack(spacing: 1) {
                    Image(systemName: "star.fill").widgetAccentable()
                    Text(entry.experience.displayedMood(at: entry.date).title).font(.caption2)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date, style: .time).monospacedDigit().font(.headline)
                    Text("派大星 · \(entry.experience.settings.mood.title)").font(.caption).widgetAccentable()
                    if let activity = entry.experience.activity, activity.status == .running, let end = activity.endsAt, end > entry.date {
                        Text(timerInterval: activity.startedAt...end, countsDown: true).monospacedDigit().font(.caption)
                    } else { Text(entry.experience.displayedMood(at: entry.date).title).font(.caption2) }
                }
            }
        }.widgetURL(entry.deepLinkURL).containerBackground(for: .widget) { Color.black }
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
        .configurationDisplayName("派大星陪伴")
        .description("數字時間、角色心情和陪伴計時。點一下開啟角色。")
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
