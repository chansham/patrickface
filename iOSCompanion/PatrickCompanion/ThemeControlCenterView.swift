import SwiftUI

struct ThemeControlCenterView: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    PatrickArtworkView(
                        theme: model.settings.theme,
                        state: model.settings.previewState
                    )
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.settings.theme.displayName)
                                .font(.title3.bold())
                            Text(model.settings.previewState.displayName.uppercased())
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.10))
                    }

                    section("Theme") {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(PatrickTheme.allCases) { theme in
                                ThemeChoiceCard(
                                    theme: theme,
                                    isSelected: model.settings.theme == theme
                                ) {
                                    model.setTheme(theme)
                                }
                            }
                        }
                    }

                    section("Preview state") {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(PatrickVisualState.allCases) { state in
                                Button {
                                    model.setVisualState(state)
                                } label: {
                                    Label(state.displayName, systemImage: state.symbolName)
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(
                                            model.settings.previewState == state
                                                ? Color.black
                                                : Color.white
                                        )
                                        .background(
                                            model.settings.previewState == state
                                                ? Color.pink
                                                : Color.white.opacity(0.08),
                                            in: RoundedRectangle(
                                                cornerRadius: 13,
                                                style: .continuous
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    section("Sleep mode") {
                        Picker(
                            "Sleep mode",
                            selection: Binding(
                                get: { model.settings.sleepMode },
                                set: { model.setSleepMode($0) }
                            )
                        ) {
                            ForEach(PatrickSleepMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(
                            "Auto asks the watch app to use its local Focus/night logic. "
                            + "On and Off are explicit overrides."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        Button {
                            model.openWatchFace()
                        } label: {
                            Label("Open In-App Watch Face", systemImage: "applewatch")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)

                        HStack(spacing: 12) {
                            Button {
                                model.playThemeSound()
                            } label: {
                                Label("Theme Sound", systemImage: "speaker.wave.2.fill")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                model.syncNow()
                            } label: {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.black)
            .navigationTitle("Patrick Control")
            .toolbarBackground(.black, for: .navigationBar)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThemeChoiceCard: View {
    let theme: PatrickTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(theme.displayName)
                        .font(.headline)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.pink)
                    }
                }
                Text(theme.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                isSelected ? Color.pink.opacity(0.16) : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.pink : Color.white.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
    }
}
