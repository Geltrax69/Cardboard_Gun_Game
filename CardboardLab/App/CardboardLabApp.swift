import SwiftUI

@main
struct CardboardLabApp: App {
    @StateObject private var engine = GameEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(engine.profile)
                .environmentObject(engine.icons)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .preferredColorScheme(.dark)
        }
    }
}
