import SwiftUI

/// Minimal crafting HUD:
///   top-left Home · top-centre STEP n / N with progress segments · top-right CRAFT
///   title + short instruction · bottom-left tool chip · bottom-centre legend ·
///   bottom-right Next (only when the step is done).
struct CraftHUDView: View {
    @EnvironmentObject var engine: GameEngine
    @EnvironmentObject var hud: HUDModel
    @EnvironmentObject var profile: PlayerProfile
    @EnvironmentObject var icons: IconFactory
    let scale: CGFloat

    var body: some View {
        let s = scale
        ZStack {
            // Top bar.
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    HStack(alignment: .top) {
                        HomeButton(size: 64 * s) { engine.goToMenu() }
                        Spacer()
                        craftBadge(s)
                    }
                    VStack(spacing: 10 * s) {
                        OutlinedText(text: "STEP \(hud.stepIndex) / \(hud.stepCount)", font: LabFont.black(26 * s),
                                     fill: .labPaper, width: 2 * s, depth: 3 * s)
                        StepSegments(current: hud.stepIndex, count: hud.stepCount, scale: s)
                    }
                    .padding(.top, 4 * s)
                }
                .padding(.horizontal, 22 * s)
                .padding(.top, 18 * s)

                VStack(spacing: 6 * s) {
                    OutlinedText(text: hud.title, font: LabFont.black(36 * s), fill: .labPaper, width: 2.5 * s, depth: 4 * s)
                        .multilineTextAlignment(.center)
                    Text(hud.instruction)
                        .font(LabFont.bold(19 * s))
                        .foregroundStyle(Color.labPaper)
                        .multilineTextAlignment(.center)
                        .shadow(color: .labInk, radius: 0, x: 0, y: 2)
                    if let detail = hud.detail {
                        Text(detail)
                            .font(LabFont.heavy(15 * s))
                            .foregroundStyle(Color.labInk)
                            .padding(.horizontal, 12 * s).padding(.vertical, 5 * s)
                            .background(Capsule().fill(Color.labMint))
                            .overlay(Capsule().stroke(Color.labInk, lineWidth: 2))
                    }
                }
                .padding(.top, 6 * s)
                .id(hud.titleID)
                .transition(.asymmetric(insertion: .offset(y: -12).combined(with: .opacity), removal: .opacity))

                Spacer()

                // Bottom bar.
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom) {
                        toolChip(s)
                        Spacer()
                        if hud.nextVisible {
                            NextButton(title: hud.nextTitle, scale: s) { hud.tapNext() }
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    if hud.showLegend {
                        LegendNote(scale: s, compact: true)
                            .padding(.bottom, 4 * s)
                    }
                }
                .padding(.horizontal, 22 * s)
                .padding(.bottom, 20 * s)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: hud.nextVisible)
        .animation(.easeOut(duration: 0.3), value: hud.titleID)
    }

    private func craftBadge(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            CoinIcon(size: 34 * s)
            Text("CRAFT")
                .font(LabFont.heavy(15 * s))
                .foregroundStyle(Color.labPaper.opacity(0.8))
            Text("\(profile.coins)")
                .font(LabFont.heavy(27 * s))
                .monospacedDigit()
                .foregroundStyle(Color.labPaper)
                .contentTransition(.numericText())
        }
        .padding(.leading, 8 * s)
        .padding(.trailing, 18 * s)
        .padding(.vertical, 8 * s)
        .background(Capsule().fill(Color.labInk.opacity(0.9)))
        .overlay(Capsule().stroke(Color.labMat, lineWidth: 2))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: profile.coins)
    }

    @ViewBuilder
    private func toolChip(_ s: CGFloat) -> some View {
        if hud.tool != .none {
            HStack(spacing: 8 * s) {
                if let key = hud.tool.iconKey, let img = icons.image(key) {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 44 * s, height: 44 * s)
                        .clipShape(Circle())
                } else {
                    Image(systemName: hud.tool.symbol)
                        .font(.system(size: 20 * s, weight: .bold))
                        .foregroundStyle(Color.labYellow)
                        .frame(width: 44 * s, height: 44 * s)
                        .background(Circle().fill(Color.labInk))
                }
                Text(hud.tool.title)
                    .font(LabFont.heavy(18 * s))
                    .foregroundStyle(Color.labPaper)
            }
            .padding(.leading, 6 * s)
            .padding(.trailing, 16 * s)
            .padding(.vertical, 6 * s)
            .background(Capsule().fill(Color.labInk.opacity(0.92)))
            .overlay(Capsule().stroke(Color.labYellow, lineWidth: 2))
        }
    }
}

/// Six little segments: done = mint, current = coral, upcoming = translucent paper.
struct StepSegments: View {
    let current: Int
    let count: Int
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 8 * scale) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                let n = i + 1
                Capsule()
                    .fill(n < current ? Color.labMint : (n == current ? Color.labRed : Color.labPaper.opacity(0.3)))
                    .frame(width: 46 * scale, height: 16 * scale)
                    .overlay(Capsule().stroke(Color.labInk.opacity(n <= current ? 0.9 : 0.4), lineWidth: 2))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: current)
    }
}

/// Large coral "Next" pill.
struct NextButton: View {
    let title: String
    let scale: CGFloat
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12 * scale) {
                Text(title).font(LabFont.black(28 * scale))
                Image(systemName: "arrow.right").font(.system(size: 26 * scale, weight: .black))
            }
            .foregroundStyle(Color.labPaper)
            .padding(.horizontal, 36 * scale)
            .frame(height: 70 * scale)
            .background(Capsule().fill(Color.labRed))
            .overlay(Capsule().stroke(Color.labInk, lineWidth: 3))
            .background(Capsule().fill(Color.labInk).offset(y: 5 * scale))
            .scaleEffect(pulse ? 1.04 : 1)
        }
        .buttonStyle(PressableStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
