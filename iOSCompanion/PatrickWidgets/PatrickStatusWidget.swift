import SwiftUI
import WidgetKit

struct PatrickWidgetEntry: TimelineEntry {
    let date: Date
    let settings: PatrickSettings
    let timer: PatrickTimerSnapshot
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
        .configurationDisplayName("Patrick Status")
        .description("Theme, state, and timer at a glance.")
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

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(
                "\(entry.settings.theme.displayName) · \(entry.settings.previewState.displayName)",
                systemImage: entry.settings.previewState.symbolName
            )
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        case .systemMedium:
            homeScreen(horizontal: true)
        case .systemLarge:
            largeHomeScreen
        default:
            homeScreen(horizontal: false)
        }
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: entry.settings.previewState.symbolName)
                    .font(.headline)
                    .widgetAccentable()
                Text(entry.settings.theme == .cel1999 ? "CEL" : "3D")
                    .font(.caption2.bold())
            }
        }
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(
                entry.settings.theme.displayName,
                systemImage: entry.settings.previewState.symbolName
            )
            .font(.headline)
            .widgetAccentable()

            if
                entry.timer.status == .running,
                let endsAt = entry.timer.endsAt
            {
                Text(timerInterval: entry.timer.startedAt ... endsAt, countsDown: true)
                    .font(.caption.monospacedDigit())
            } else {
                Text(entry.settings.previewState.displayName)
                    .font(.caption)
            }
        }
    }

    private func homeScreen(horizontal: Bool) -> some View {
        HStack(spacing: 10) {
            if horizontal {
                PatrickArtworkView(
                    theme: entry.settings.theme,
                    state: entry.settings.previewState,
                    animated: false
                )
                .frame(width: 112)
            }

            VStack(alignment: .leading, spacing: 5) {
                if !horizontal {
                    PatrickArtworkView(
                        theme: entry.settings.theme,
                        state: entry.settings.previewState,
                        animated: false
                    )
                    .frame(maxHeight: .infinity)
                }

                Text(entry.settings.theme.displayName)
                    .font(horizontal ? .title3.bold() : .caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Label(
                    entry.settings.previewState.displayName,
                    systemImage: entry.settings.previewState.symbolName
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                timerLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(horizontal ? 4 : 0)
    }

    private var largeHomeScreen: some View {
        VStack(spacing: 8) {
            PatrickArtworkView(
                theme: entry.settings.theme,
                state: entry.settings.previewState,
                animated: false
            )

            HStack {
                VStack(alignment: .leading) {
                    Text(entry.settings.theme.displayName)
                        .font(.headline)
                    Text(entry.settings.previewState.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                timerLabel
            }
        }
    }

    @ViewBuilder
    private var timerLabel: some View {
        if
            entry.timer.status == .running,
            let endsAt = entry.timer.endsAt
        {
            Text(timerInterval: entry.timer.startedAt ... endsAt, countsDown: true)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.pink)
        }
    }
}
