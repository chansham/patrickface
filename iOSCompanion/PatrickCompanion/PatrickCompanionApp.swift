import SwiftUI

@main
struct PatrickCompanionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel

    init() {
        PatrickFieldTestBackground.register()
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
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
