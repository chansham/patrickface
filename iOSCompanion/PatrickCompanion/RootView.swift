import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            PatrickPhoneExperienceView()
                .tag(AppModel.Tab.control)
                .tabItem {
                    Label("陪伴", systemImage: "heart.fill")
                }

            TimerControlView()
                .tag(AppModel.Tab.timer)
                .tabItem {
                    Label("計時", systemImage: "timer")
                }

            DiagnosticsView()
                .tag(AppModel.Tab.status)
                .tabItem {
                    Label("連線", systemImage: "applewatch.radiowaves.left.and.right")
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
                PatrickPhoneExperienceView()
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
