import SwiftUI

/// Cardboard Lab home screen: title, cardboard stocks (3D stacks on the mat with
/// labels), tools shelf, craft projects and the CRAFT balance.
struct MenuView: View {
    @EnvironmentObject var engine: GameEngine
    @EnvironmentObject var profile: PlayerProfile
    @EnvironmentObject var icons: IconFactory
    @Binding var showSettings: Bool

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 1180, geo.size.height / 820)
            let projectsWidth = geo.size.width * 0.27
            ZStack(alignment: .topLeading) {
                stockLabels(scale: s)

                // Top row: settings + title, legend, balance.
                HStack(alignment: .top, spacing: 18 * s) {
                    RoundIconButton(systemName: "gearshape.fill", size: 58 * s) { showSettings = true }
                    CardboardTitle(scale: s * 0.92)
                        .padding(.top, 4 * s)
                    Spacer(minLength: 10 * s)
                    LegendNote(scale: s)
                        .padding(.top, 14 * s)
                    Spacer(minLength: 10 * s)
                    CoinBadge(coins: profile.coins, scale: s) {
                        engine.toast("Earn CRAFT by finishing projects", .info)
                    }
                }
                .padding(.horizontal, 24 * s)
                .padding(.top, 20 * s)

                // Right column: craft projects.
                VStack(alignment: .leading, spacing: 12 * s) {
                    HStack {
                        Text("Craft Projects")
                            .font(LabFont.heavy(24 * s))
                            .foregroundStyle(Color.labPaper)
                        Spacer()
                        Button {
                            engine.showGuide(startsCraft: false)
                        } label: {
                            HStack(spacing: 5 * s) {
                                Image(systemName: "book.fill").font(.system(size: 13 * s, weight: .bold))
                                Text("How to build").font(LabFont.heavy(13 * s))
                            }
                            .foregroundStyle(Color.labInk)
                            .padding(.horizontal, 10 * s).padding(.vertical, 6 * s)
                            .background(Capsule().fill(Color.labBlue))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    ForEach(ProjectInfo.all) { project in
                        ProjectCard(project: project, scale: s)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16 * s)
                .frame(width: projectsWidth, height: geo.size.height - 124 * s, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).fill(Color.labInk.opacity(0.88)))
                .overlay(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).stroke(Color.labMat, lineWidth: 2))
                .position(x: geo.size.width - projectsWidth / 2 - 20 * s,
                          y: 104 * s + (geo.size.height - 124 * s) / 2)

                // Bottom shelf: tools.
                ToolShelf(scale: s)
                    .frame(width: geo.size.width - projectsWidth - 64 * s)
                    .position(x: (geo.size.width - projectsWidth - 64 * s) / 2 + 22 * s,
                              y: geo.size.height - 108 * s)
            }
        }
    }

    @ViewBuilder
    private func stockLabels(scale s: CGFloat) -> some View {
        ForEach(CardboardStock.all) { stock in
            if let a = engine.menuAnchors[stock.id] {
                let unlocked = profile.isUnlocked(stock)
                let selected = profile.stock.id == stock.id
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: max(a.rect.width, 1), height: max(a.rect.height, 1))
                    .position(x: a.rect.midX, y: a.rect.midY)
                    .onTapGesture { engine.chooseStock(stock) }

                VStack(spacing: 3 * s) {
                    Text(stock.name)
                        .font(LabFont.heavy(19 * s))
                        .foregroundStyle(Color.labPaper)
                    if unlocked {
                        Text(stock.blurb)
                            .font(LabFont.semibold(15 * s))
                            .foregroundStyle(Color.labPaper.opacity(0.78))
                    } else {
                        HStack(spacing: 6 * s) {
                            Image(systemName: "lock.fill").font(.system(size: 13 * s, weight: .bold))
                            CoinIcon(size: 18 * s)
                            Text("\(stock.price)").font(LabFont.heavy(16 * s))
                        }
                        .foregroundStyle(Color.labYellow)
                    }
                }
                .padding(.horizontal, 14 * s)
                .padding(.vertical, 8 * s)
                .background(RoundedRectangle(cornerRadius: 14 * s, style: .continuous).fill(Color.labInk.opacity(0.82)))
                .overlay(RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                    .stroke(selected ? Color.labYellow : Color.clear, lineWidth: 2))
                .position(x: a.label.x, y: a.label.y + 22 * s)
                .onTapGesture { engine.chooseStock(stock) }

                if selected {
                    ZStack {
                        Circle().fill(Color.labPaper)
                        Circle().stroke(Color.labInk, lineWidth: 2.5)
                        Image(systemName: "checkmark").font(.system(size: 20 * s, weight: .black)).foregroundStyle(Color.labInk)
                    }
                    .frame(width: 42 * s, height: 42 * s)
                    .position(a.badge)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct ProjectCard: View {
    @EnvironmentObject var engine: GameEngine
    @EnvironmentObject var profile: PlayerProfile
    @EnvironmentObject var icons: IconFactory
    let project: ProjectInfo
    let scale: CGFloat

    var body: some View {
        let s = scale
        let playable = project.kind == .playable
        Button {
            switch project.kind {
            case .playable: engine.openProject(project)
            case .locked(let requirement):
                if let dep = project.unlockedBy, profile.timesCompleted(dep) > 0 {
                    engine.toast("\(project.name) blueprint is coming soon!", .info, life: 2)
                } else {
                    engine.toast(requirement, .hint, life: 2)
                }
            case .comingSoon: engine.toast("More crafts are on the way!", .info)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20 * s, style: .continuous)
                    .fill(Color.labInk)
                if let img = icons.image("project.\(project.id)") {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 118 * s, height: 118 * s)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 26 * s)
                        .opacity(playable ? 1 : 0.55)
                }
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(project.name)
                        .font(LabFont.heavy(24 * s))
                        .foregroundStyle(Color.labPaper)
                    Text(subtitle)
                        .font(LabFont.semibold(15 * s))
                        .foregroundStyle(Color.labPaper.opacity(0.75))
                }
                .padding(14 * s)
                trailingBadge(s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12 * s)
            }
            .frame(height: 128 * s)
            .overlay(RoundedRectangle(cornerRadius: 20 * s, style: .continuous)
                .stroke(playable ? Color.labYellow : Color.labMat, lineWidth: playable ? 3.5 : 2))
            .shadow(color: playable ? Color.labYellow.opacity(0.45) : .clear, radius: 8 * s)
        }
        .buttonStyle(PressableStyle())
    }

    private var subtitle: String {
        switch project.kind {
        case .playable:
            let done = profile.timesCompleted(project.id)
            return done > 0 ? "Crafted ×\(done) · \(project.steps) steps" : "Step \(max(1, profile.progress(of: project.id))) / \(project.steps)"
        case .locked:
            if let dep = project.unlockedBy, profile.timesCompleted(dep) > 0 { return "Blueprint coming soon" }
            return "Step 0 / \(project.steps)"
        case .comingSoon: return "Coming Soon"
        }
    }

    @ViewBuilder
    private func trailingBadge(_ s: CGFloat) -> some View {
        switch project.kind {
        case .playable:
            Image(systemName: "chevron.right")
                .font(.system(size: 22 * s, weight: .black))
                .foregroundStyle(Color.labPaper)
        case .locked, .comingSoon:
            Image(systemName: "lock.fill")
                .font(.system(size: 22 * s, weight: .bold))
                .foregroundStyle(Color.labPaper)
                .padding(8 * s)
                .background(Circle().fill(Color.labMat))
        }
    }
}

private struct ToolShelf: View {
    @EnvironmentObject var engine: GameEngine
    @EnvironmentObject var icons: IconFactory
    let scale: CGFloat

    var body: some View {
        let s = scale
        let tool = ToolInfo.all.first { $0.id == engine.selectedTool } ?? ToolInfo.all[0]
        VStack(alignment: .leading, spacing: 10 * s) {
            HStack(alignment: .firstTextBaseline, spacing: 12 * s) {
                Text("Tools")
                    .font(LabFont.heavy(24 * s))
                    .foregroundStyle(Color.labPaper)
                Text("\(tool.name): \(tool.tip)")
                    .font(LabFont.semibold(15 * s))
                    .foregroundStyle(Color.labPaper.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 10 * s) {
                ForEach(ToolInfo.all) { t in
                    let selected = t.id == engine.selectedTool
                    Button {
                        engine.selectedTool = t.id
                    } label: {
                        VStack(spacing: 2 * s) {
                            if let img = icons.image("tool.\(t.id)") {
                                Image(uiImage: img)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(height: 70 * s)
                            } else {
                                Spacer().frame(height: 70 * s)
                            }
                            Text(t.name)
                                .font(LabFont.bold(15 * s))
                                .foregroundStyle(Color.labPaper)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.vertical, 8 * s)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(Color.labInk))
                        .overlay(RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                            .stroke(selected ? Color.labBlue : Color.labMat, lineWidth: selected ? 3.5 : 1.5))
                        .shadow(color: selected ? Color.labBlue.opacity(0.5) : .clear, radius: 7 * s)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(16 * s)
        .background(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).fill(Color.labInk.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).stroke(Color.labMat, lineWidth: 2))
    }
}

/// Settings sheet: sound, hints, guide, reset.
struct SettingsPanel: View {
    @EnvironmentObject var engine: GameEngine
    @EnvironmentObject var profile: PlayerProfile
    @Binding var isPresented: Bool
    var openGuide: () -> Void
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            Color.labTable.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Settings").font(LabFont.heavy(30)).foregroundStyle(Color.labPaper)
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark").font(.system(size: 20, weight: .black)).foregroundStyle(Color.labPaper)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.labMat))
                    }
                    .buttonStyle(PressableStyle())
                }
                settingRow("Sound effects", icon: "speaker.wave.2.fill", isOn: profile.soundOn) { profile.setSound($0) }
                settingRow("Tutorial hints", icon: "hand.point.up.left.fill", isOn: profile.hintsOn) { profile.setHints($0) }
                Button {
                    isPresented = false
                    openGuide()
                } label: {
                    Label("How to build the knife", systemImage: "book.fill")
                }
                .buttonStyle(SettingsButtonStyle(fill: .labBlue))
                Button {
                    if confirmReset {
                        profile.reset()
                        engine.chooseStock(.plain)
                        confirmReset = false
                        isPresented = false
                    } else {
                        confirmReset = true
                    }
                } label: {
                    Label(confirmReset ? "Tap again to erase progress" : "Reset progress", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SettingsButtonStyle(fill: confirmReset ? .labRed : .labMat))
            }
            .padding(28)
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.labInk))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.labMat, lineWidth: 3))
        }
    }

    private func settingRow(_ title: String, icon: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Button { set(!isOn) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20, weight: .bold)).frame(width: 30)
                Text(title).font(LabFont.bold(21))
                Spacer()
                Capsule()
                    .fill(isOn ? Color.labMint : Color.labMat)
                    .frame(width: 62, height: 34)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(Color.labPaper).frame(width: 28, height: 28).padding(3)
                    }
                    .overlay(Capsule().stroke(Color.labInk, lineWidth: 2))
            }
            .foregroundStyle(Color.labPaper)
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
    }
}

struct SettingsButtonStyle: ButtonStyle {
    var fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LabFont.heavy(19))
            .foregroundStyle(Color.labInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(Color.labInk, lineWidth: 2.5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
