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

                // Right column: level and weapons.
                VStack(alignment: .leading, spacing: 10 * s) {
                    HStack {
                        Text("Weapons")
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
                    LevelBar(scale: s)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10 * s) {
                            ForEach(menuProjects) { project in
                                ProjectCard(project: project, scale: s)
                            }
                        }
                        .padding(.bottom, 8 * s)
                    }
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

    /// Campaign weapons in unlock order, then the guns still being designed.
    private var menuProjects: [ProjectInfo] {
        [.freeCraft] + ProjectInfo.campaign
    }

    @ViewBuilder
    private func stockLabels(scale s: CGFloat) -> some View {
        if MenuScene.pageCount > 1, let a = engine.menuAnchors[MenuScene.pagerKey] {
            shelfPager(s)
                .position(x: a.label.x, y: a.label.y)
        }
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

extension MenuView {
    /// ‹ Boards 2 / 4 › — flips the shelf to more cardboard.
    func shelfPager(_ s: CGFloat) -> some View {
        let page = engine.stockPage, count = MenuScene.pageCount
        return HStack(spacing: 10 * s) {
            pagerButton("chevron.left", enabled: page > 0, s) { engine.showStockPage(page - 1) }
            VStack(spacing: 4 * s) {
                Text("Cardboard \(page + 1) / \(count)")
                    .font(LabFont.heavy(15 * s))
                    .foregroundStyle(Color.labPaper)
                HStack(spacing: 5 * s) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.labYellow : Color.labPaper.opacity(0.35))
                            .frame(width: 7 * s, height: 7 * s)
                    }
                }
            }
            pagerButton("chevron.right", enabled: page < count - 1, s) { engine.showStockPage(page + 1) }
        }
        .padding(.horizontal, 8 * s)
        .padding(.vertical, 6 * s)
        .background(Capsule().fill(Color.labInk.opacity(0.85)))
        .overlay(Capsule().stroke(Color.labMat, lineWidth: 2))
    }

    private func pagerButton(_ icon: String, enabled: Bool, _ s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16 * s, weight: .black))
                .foregroundStyle(enabled ? Color.labInk : Color.labPaper.opacity(0.4))
                .frame(width: 38 * s, height: 38 * s)
                .background(Circle().fill(enabled ? Color.labYellow : Color.labTable))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

/// Player level, XP toward the next level and what it unlocks.
private struct LevelBar: View {
    @EnvironmentObject var profile: PlayerProfile
    let scale: CGFloat

    var body: some View {
        let s = scale
        let level = profile.level
        let next = ProjectInfo.campaign.first { $0.level > level }
        HStack(spacing: 10 * s) {
            ZStack {
                Circle().fill(Color.labYellow)
                Circle().stroke(Color.labInk, lineWidth: 2.5)
                Text("\(level)").font(LabFont.black(20 * s)).foregroundStyle(Color.labInk)
            }
            .frame(width: 42 * s, height: 42 * s)
            VStack(alignment: .leading, spacing: 4 * s) {
                HStack {
                    Text("LEVEL \(level)").font(LabFont.heavy(15 * s)).foregroundStyle(Color.labPaper)
                    Spacer()
                    Text("\(profile.xpToNextLevel) XP to go")
                        .font(LabFont.semibold(12 * s))
                        .foregroundStyle(Color.labPaper.opacity(0.7))
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.labTable)
                        Capsule().fill(Color.labMint)
                            .frame(width: max(10 * s, g.size.width * CGFloat(profile.levelProgress)))
                    }
                }
                .frame(height: 12 * s)
                .overlay(Capsule().stroke(Color.labInk, lineWidth: 1.5))
                if let next {
                    Text("Next unlock: \(next.name)")
                        .font(LabFont.semibold(12 * s))
                        .foregroundStyle(Color.labYellow)
                }
            }
        }
        .padding(10 * s)
        .background(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(Color.labTable))
        .overlay(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).stroke(Color.labMat, lineWidth: 1.5))
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: profile.xp)
    }
}

/// One row in the weapons list.
private struct ProjectCard: View {
    @EnvironmentObject var engine: GameEngine
    @EnvironmentObject var profile: PlayerProfile
    @EnvironmentObject var icons: IconFactory
    let project: ProjectInfo
    let scale: CGFloat

    private var unlocked: Bool { project.kind != .comingSoon && profile.isUnlocked(project) }
    private var crafted: Int { profile.timesCompleted(project.id) }
    private var isNew: Bool { unlocked && (project.kind == .weapon || project.kind == .gun) && crafted == 0 }

    var body: some View {
        let s = scale
        Button {
            switch project.kind {
            case .comingSoon:
                engine.toast("\(project.name) blueprint is on the drawing board!", .info, life: 2)
            case .weapon, .gun, .freeCraft:
                if unlocked {
                    engine.openProject(project)
                } else {
                    engine.toast("Reach level \(project.level) to unlock the \(project.name)", .hint, life: 2.2)
                }
            }
        } label: {
            HStack(spacing: 10 * s) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14 * s, style: .continuous).fill(Color.labTable)
                    if let img = icons.image(project.iconKey) {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .opacity(unlocked ? 1 : 0.35)
                    }
                    if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20 * s, weight: .bold))
                            .foregroundStyle(Color.labPaper)
                    }
                }
                .frame(width: 78 * s, height: 78 * s)
                .clipShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))

                VStack(alignment: .leading, spacing: 3 * s) {
                    HStack(spacing: 6 * s) {
                        Text(project.name)
                            .font(LabFont.heavy(19 * s))
                            .foregroundStyle(Color.labPaper.opacity(unlocked ? 1 : 0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if isNew {
                            Text("NEW")
                                .font(LabFont.black(11 * s))
                                .foregroundStyle(Color.labInk)
                                .padding(.horizontal, 6 * s).padding(.vertical, 2 * s)
                                .background(Capsule().fill(Color.labYellow))
                        }
                    }
                    Text(project.blurb)
                        .font(LabFont.semibold(12 * s))
                        .foregroundStyle(Color.labPaper.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(status)
                        .font(LabFont.heavy(12 * s))
                        .foregroundStyle(unlocked ? Color.labMint : Color.labYellow.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: unlocked ? "chevron.right" : "lock.fill")
                    .font(.system(size: 16 * s, weight: .black))
                    .foregroundStyle(Color.labPaper.opacity(unlocked ? 1 : 0.5))
            }
            .padding(8 * s)
            .background(RoundedRectangle(cornerRadius: 18 * s, style: .continuous).fill(Color.labInk))
            .overlay(RoundedRectangle(cornerRadius: 18 * s, style: .continuous)
                .stroke(borderColor, lineWidth: isNew ? 3 : 1.5))
            .shadow(color: isNew ? Color.labYellow.opacity(0.4) : .clear, radius: 7 * s)
        }
        .buttonStyle(PressableStyle())
    }

    private var borderColor: Color {
        if project.kind == .freeCraft { return .labBlue }
        if isNew { return .labYellow }
        return .labMat
    }

    private var status: String {
        switch project.kind {
        case .comingSoon: return "Coming soon"
        case .freeCraft: return "Make anything you like"
        case .weapon, .gun:
            guard unlocked else { return "Reach level \(project.level)" }
            if crafted > 0 { return "Crafted ×\(crafted) · \(project.steps) steps" }
            let step = profile.progress(of: project.id)
            return step > 0 ? "Step \(step) / \(project.steps)" : "\(project.steps) steps · +\(project.xp(firstTime: true)) XP"
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
                    profile.unlockAll()
                    engine.toast("Everything unlocked — have fun testing!", .success, life: 2)
                    isPresented = false
                } label: {
                    Label("Unlock all projects", systemImage: "lock.open.fill")
                }
                .buttonStyle(SettingsButtonStyle(fill: .labYellow))
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
