import SwiftUI

@main
struct CardboardLabApp: App {
    @StateObject private var engine = GameEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .preferredColorScheme(.dark)
        }
    }
}
