import SwiftUI

struct RootView: View {
    @EnvironmentObject var engine: GameEngine
    @State private var started = false

    var body: some View {
        ZStack {
            GameSceneView(container: engine.container)
                .ignoresSafeArea()

            if !started {
                VStack(spacing: 18) {
                    Text("CARDBOARD LAB")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(Color.labCardboardLight)
                        .shadow(color: .labInk, radius: 0, x: 0, y: 5)
                    Text("CUT · FOLD · GLUE · CREATE")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(Color.labPaper)
                    Button {
                        started = true
                        Task { try? await engine.showWorkbench(stock: .plain) }
                    } label: {
                        Text("Start crafting")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.labPaper)
                            .padding(.horizontal, 34)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Color.labRed))
                            .overlay(Capsule().stroke(Color.labInk, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: started)
        .onAppear { engine.start() }
    }
}
