import SwiftUI

@main
struct PatrickCompanionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if PatrickSamplePreview.requested {
                    PatrickStarPajamasSample()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else {
                    RootView()
                }
            }
            .environmentObject(model)
            .preferredColorScheme(.dark)
            .onOpenURL { model.handle(url: $0) }
            .task { PatrickAppShortcuts.updateAppShortcutParameters() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.becameActive()
                }
            }
        }
    }
}
