import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            ThemeControlCenterView()
                .tag(AppModel.Tab.control)
                .tabItem {
                    Label("Themes", systemImage: "paintpalette.fill")
                }

            TimerControlView()
                .tag(AppModel.Tab.timer)
                .tabItem {
                    Label("Timer", systemImage: "timer")
                }

            DiagnosticsView()
                .tag(AppModel.Tab.status)
                .tabItem {
                    Label("Status", systemImage: "applewatch.radiowaves.left.and.right")
                }
        }
        .tint(.pink)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let notice = model.notice {
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .fullScreenCover(isPresented: $model.isPresentingWatchFace) {
            NavigationStack {
                PatrickArtworkView(
                    theme: model.settings.theme,
                    state: model.settings.previewState
                )
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            model.isPresentingWatchFace = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppModel())
}
