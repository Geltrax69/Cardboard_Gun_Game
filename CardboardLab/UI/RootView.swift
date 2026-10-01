import SwiftUI

struct RootView: View {
    @EnvironmentObject var engine: GameEngine
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 1180, geo.size.height / 820)
            ZStack {
                GameSceneView(container: engine.container)
                    .ignoresSafeArea()

                if engine.screen == .menu && !engine.transitioning {
                    MenuView(showSettings: $showSettings)
                        .transition(.opacity)
                }

                if engine.screen == .crafting {
                    CraftHUDView(scale: s)
                        .transition(.opacity)
                }

                if engine.screen == .workshop && !engine.transitioning {
                    WorkshopView(scale: s)
                        .transition(.opacity)
                }

                ToastLayer(scale: s, defaultY: geo.size.height * 0.34)

                if engine.guideVisible {
                    GuideView(scale: s)
                        .transition(.opacity)
                }

                if showSettings {
                    SettingsPanel(isPresented: $showSettings) { engine.showGuide(startsCraft: false) }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: engine.screen)
            .animation(.easeInOut(duration: 0.35), value: engine.transitioning)
            .animation(.easeInOut(duration: 0.25), value: showSettings)
            .animation(.easeInOut(duration: 0.3), value: engine.guideVisible)
        }
        .onAppear { engine.start() }
    }
}
