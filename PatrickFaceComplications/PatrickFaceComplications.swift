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

    private var moodTitle: String {
        entry.experience.displayedMood(at: entry.date).title
    }

    var body: some View {
        Group {
            if family == .accessoryInline {
                // Inline slots accept one SF Symbol, not a custom image.
                Label("派大星 · \(entry.experience.settings.mood.title)", systemImage: "heart.fill")
            } else if family == .accessoryCircular {
                VStack(spacing: 1) {
                    PatrickHeadAvatar(slot: .circular, side: 20)
                    Text(moodTitle).font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
                }
            } else if family == .accessoryCorner {
                PatrickHeadAvatar(slot: .corner)
                    .widgetLabel { Text(moodTitle) }
            } else {
                HStack(alignment: .center, spacing: 4) {
                    PatrickHeadAvatar(slot: .rectangular, side: 22, decorative: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date, style: .time).monospacedDigit().font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                        Text("派大星 · \(entry.experience.settings.mood.title)").font(.caption).widgetAccentable().lineLimit(1)
                        if let activity = entry.experience.activity, activity.status == .running, let end = activity.endsAt, end > entry.date {
                            Text(timerInterval: activity.startedAt...end, countsDown: true).monospacedDigit().font(.caption)
                        } else { Text(moodTitle).font(.caption2).lineLimit(1) }
                    }
                }
            }
        }.widgetURL(entry.deepLinkURL).containerBackground(for: .widget) { Color.black }
    }
}

/// Head cropped from the season-1 flat body. Accented watch faces tint the
/// skin layer and leave the face marks in the light group. Full colour and
/// vibrant rendering use the colour bitmap, whose luminance stays readable.
private struct PatrickHeadAvatar: View {
    enum Slot {
        case circular
        case rectangular
        case corner

        var imageBase: String {
            switch self {
            case .circular: "PatrickHeadCircular"
            case .rectangular: "PatrickHeadRectangular"
            case .corner: "PatrickHeadCorner"
            }
        }
    }

    var slot: Slot
    var side: CGFloat? = nil
    var decorative: Bool = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        avatar
            .frame(width: side, height: side)
            .accessibilityLabel("派大星")
            .accessibilityHidden(decorative)
    }

    @ViewBuilder private var avatar: some View {
        switch renderingMode {
        case .accented:
            ZStack {
                image("Skin").widgetAccentable()
                image("Features").widgetAccentable(false)
            }
        default:
            image("").widgetAccentable(false)
        }
    }

    private func image(_ suffix: String) -> some View {
        Image(slot.imageBase + suffix)
            .resizable()
            .interpolation(.medium)
            .scaledToFit()
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
            .accessoryCorner,
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
