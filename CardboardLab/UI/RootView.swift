import SwiftUI

struct RootView: View {
    @EnvironmentObject var engine: GameEngine
    @State private var showSettings = false
    @State private var showGuide = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 1180, geo.size.height / 820)
            ZStack {
                GameSceneView(container: engine.container)
                    .ignoresSafeArea()

                if engine.screen == .menu && !engine.transitioning {
                    MenuView(showSettings: $showSettings, showGuide: $showGuide)
                        .transition(.opacity)
                }

                if engine.screen == .crafting {
                    CraftOverlay(scale: s)
                        .transition(.opacity)
                }

                ToastLayer(scale: s, defaultY: geo.size.height * 0.34)

                if showSettings {
                    SettingsPanel(isPresented: $showSettings) { showGuide = true }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: engine.screen)
            .animation(.easeInOut(duration: 0.35), value: engine.transitioning)
            .animation(.easeInOut(duration: 0.25), value: showSettings)
        }
        .onAppear { engine.start() }
    }
}

/// Crafting overlay (the full HUD arrives with the crafting session).
struct CraftOverlay: View {
    @EnvironmentObject var engine: GameEngine
    let scale: CGFloat

    var body: some View {
        VStack {
            HStack {
                HomeButton(size: 64 * scale) { engine.goToMenu() }
                Spacer()
            }
            Spacer()
        }
        .padding(24 * scale)
    }
}
