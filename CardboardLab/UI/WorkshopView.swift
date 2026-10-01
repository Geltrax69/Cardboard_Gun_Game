import SwiftUI

/// Free mode HUD: home and workbench buttons on top, the tool palette on the left, the
/// active tool's options at the bottom and, while painting, the colour wheel on the
/// right. Everything else is open table, so touches reach the 3D bench.
struct WorkshopView: View {
    @EnvironmentObject var engine: GameEngine
    @EnvironmentObject var model: WorkshopModel
    let scale: CGFloat
    @State private var confirmClear = false

    var body: some View {
        let s = scale
        ZStack {
            VStack(spacing: 0) {
                topBar(s)
                Spacer()
                HStack(alignment: .bottom) {
                    options(s)
                    Spacer()
                }
                .padding(.leading, 120 * s)
                .padding(.trailing, 20 * s)
                .padding(.bottom, 18 * s)
            }
            HStack {
                toolPalette(s)
                Spacer()
            }
            .padding(.leading, 16 * s)
            if model.tool == .paint {
                HStack {
                    Spacer()
                    ColorWheelPanel(scale: s)
                }
                .padding(.trailing, 18 * s)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if model.showHelp {
                helpCard(s)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.tool)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.hasSelection)
        .animation(.easeOut(duration: 0.25), value: model.showHelp)
    }

    // MARK: Top bar

    private func topBar(_ s: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12 * s) {
            HomeButton(size: 64 * s) { engine.goToMenu() }
            VStack(alignment: .leading, spacing: 4 * s) {
                OutlinedText(text: "Free Mode", font: LabFont.black(32 * s), fill: .labCardboardLight, width: 2.5 * s, depth: 4 * s)
                Text(model.status.isEmpty ? model.tool.help : model.status)
                    .font(LabFont.bold(16 * s))
                    .foregroundStyle(Color.labPaper)
                    .shadow(color: .labInk, radius: 0, x: 0, y: 2)
                    .lineLimit(2)
                    .frame(maxWidth: 520 * s, alignment: .leading)
            }
            Spacer()
            barButton("arrow.uturn.backward", "Undo", s, enabled: model.canUndo) { model.send?(.undo) }
            barButton(model.topView ? "cube.fill" : "square.grid.3x3.fill", model.topView ? "3D view" : "Top view", s) {
                model.send?(.toggleView)
            }
            barButton("scope", "Re-centre", s) { model.send?(.resetView) }
            barButton("doc.badge.plus", "New sheet", s, highlight: true) { model.send?(.newSheet) }
            barButton(confirmClear ? "exclamationmark.triangle.fill" : "trash", confirmClear ? "Sure?" : "Clear", s) {
                if confirmClear {
                    confirmClear = false
                    model.send?(.clearAll)
                } else {
                    confirmClear = true
                }
            }
            barButton("questionmark", "Help", s) { model.showHelp.toggle() }
        }
        .padding(.horizontal, 20 * s)
        .padding(.top, 16 * s)
    }

    private func barButton(_ icon: String, _ title: String, _ s: CGFloat, enabled: Bool = true, highlight: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button {
            engine.sound.play(.tap)
            action()
        } label: {
            VStack(spacing: 3 * s) {
                Image(systemName: icon)
                    .font(.system(size: 20 * s, weight: .bold))
                    .foregroundStyle(highlight ? Color.labInk : Color.labPaper)
                    .frame(width: 52 * s, height: 52 * s)
                    .background(Circle().fill(highlight ? Color.labYellow : Color.labInk.opacity(0.9)))
                    .overlay(Circle().stroke(highlight ? Color.labInk : Color.labMat, lineWidth: 2))
                Text(title)
                    .font(LabFont.heavy(11 * s))
                    .foregroundStyle(Color.labPaper)
                    .shadow(color: .labInk, radius: 0, x: 0, y: 1)
            }
            .opacity(enabled && !model.busy ? 1 : 0.4)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled || model.busy)
    }

    // MARK: Tools

    private func toolPalette(_ s: CGFloat) -> some View {
        VStack(spacing: 8 * s) {
            ForEach(WorkshopModel.Tool.allCases, id: \.self) { tool in
                let on = model.tool == tool
                Button {
                    engine.sound.play(.tap)
                    model.tool = tool
                } label: {
                    VStack(spacing: 2 * s) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 22 * s, weight: .bold))
                            .foregroundStyle(on ? Color.labInk : toolTint(tool))
                        Text(tool.title)
                            .font(LabFont.heavy(11 * s))
                            .foregroundStyle(on ? Color.labInk : Color.labPaper)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 84 * s, height: 64 * s)
                    .background(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(on ? Color.labYellow : Color.labInk.opacity(0.92)))
                    .overlay(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).stroke(on ? Color.labInk : Color.labMat, lineWidth: 2))
                }
                .buttonStyle(PressableStyle())
                .disabled(model.busy)
            }
        }
    }

    /// Cut is red and fold lines are blue, like the lines they make.
    private func toolTint(_ tool: WorkshopModel.Tool) -> Color {
        switch tool {
        case .cut: return .labRed
        case .crease, .fold: return .labBlue
        case .paint: return Color(hue: Double(model.hue), saturation: Double(model.saturation), brightness: Double(model.brightness))
        case .glue: return .labMint
        default: return .labPaper
        }
    }

    // MARK: Options

    @ViewBuilder
    private func options(_ s: CGFloat) -> some View {
        switch model.tool {
        case .cut:
            optionBar(s) {
                ForEach(WorkshopModel.Shape.allCases, id: \.self) { shape in
                    chip(shape.title, icon: shape.symbol, on: model.shape == shape, s) { model.shape = shape }
                }
                divider(s)
                chip("Quick cut", icon: model.quickCut ? "bolt.fill" : "bolt.slash", on: model.quickCut, s) { model.quickCut.toggle() }
                if model.shape == .lines && model.linePoints > 0 {
                    divider(s)
                    chip("Undo point", icon: "delete.left", on: false, s) { model.send?(.undoPoint) }
                    if model.linePoints >= 3 {
                        chip("Close shape", icon: "checkmark", on: true, s) { model.send?(.closeShape) }
                    }
                }
            }
        case .paint:
            optionBar(s) {
                chip("One face", icon: "square.fill", on: !model.paintWhole, s) { model.paintWhole = false }
                chip("Whole piece", icon: "cube.fill", on: model.paintWhole, s) { model.paintWhole = true }
            }
        case .move:
            if model.hasSelection {
                optionBar(s) {
                    ForEach(WorkshopModel.MoveAction.allCases.filter { $0 != .unglue || model.selectionGlued }, id: \.self) { action in
                        chip(action.title, icon: action.symbol, on: false, s, danger: action == .delete) {
                            model.send?(.move(action))
                        }
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private func optionBar<C: View>(_ s: CGFloat, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 8 * s) { content() }
            .padding(8 * s)
            .background(Capsule().fill(Color.labInk.opacity(0.9)))
            .overlay(Capsule().stroke(Color.labMat, lineWidth: 2))
    }

    private func divider(_ s: CGFloat) -> some View {
        Rectangle().fill(Color.labMat).frame(width: 2, height: 30 * s)
    }

    private func chip(_ title: String, icon: String, on: Bool, _ s: CGFloat, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            engine.sound.play(.tap)
            action()
        } label: {
            HStack(spacing: 5 * s) {
                Image(systemName: icon).font(.system(size: 14 * s, weight: .bold))
                Text(title).font(LabFont.heavy(14 * s)).lineLimit(1)
            }
            .foregroundStyle(on ? Color.labInk : (danger ? Color.labRed : Color.labPaper))
            .padding(.horizontal, 12 * s)
            .frame(height: 40 * s)
            .background(Capsule().fill(on ? Color.labYellow : Color.labTable))
            .overlay(Capsule().stroke(on ? Color.labInk : Color.labMat, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
        .disabled(model.busy)
    }

    // MARK: Help

    private func helpCard(_ s: CGFloat) -> some View {
        let steps: [(String, String, String)] = [
            ("scissors", "Cut", "Pick a shape — freehand, straight lines, rectangle or circle — and draw it on a sheet. Then cut along the red line."),
            ("line.diagonal", "Fold line", "Drag a line across a piece. It becomes a blue dashed crease."),
            ("arrow.uturn.up", "Fold", "Grab the flap beside a crease and drag it up or down to any angle."),
            ("paintbrush.fill", "Paint", "Choose any colour on the wheel and brush it over faces, pieces or whole sheets."),
            ("hand.draw.fill", "Move & glue", "Drag pieces around, turn and tilt them, stack them up and glue them together."),
            ("doc.badge.plus", "Unlimited cardboard", "Tap New sheet whenever you run out. Undo fixes any slip, and your bench is saved."),
        ]
        return VStack(alignment: .leading, spacing: 12 * s) {
            OutlinedText(text: "Make anything", font: LabFont.black(30 * s), fill: .labCardboardLight, width: 2.5 * s, depth: 3 * s)
            ForEach(steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 12 * s) {
                    Image(systemName: steps[i].0)
                        .font(.system(size: 18 * s, weight: .bold))
                        .foregroundStyle(Color.labInk)
                        .frame(width: 38 * s, height: 38 * s)
                        .background(Circle().fill(i == 0 ? Color.labRed : (i < 3 ? Color.labBlue : Color.labMint)))
                    VStack(alignment: .leading, spacing: 2 * s) {
                        Text(steps[i].1).font(LabFont.heavy(17 * s)).foregroundStyle(Color.labPaper)
                        Text(steps[i].2).font(LabFont.semibold(14 * s)).foregroundStyle(Color.labPaper.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button {
                model.showHelp = false
            } label: {
                Label("Start making", systemImage: "arrow.right")
            }
            .buttonStyle(SettingsButtonStyle(fill: .labRed))
        }
        .padding(24 * s)
        .frame(width: 560 * s)
        .background(RoundedRectangle(cornerRadius: 28 * s, style: .continuous).fill(Color.labInk))
        .overlay(RoundedRectangle(cornerRadius: 28 * s, style: .continuous).stroke(Color.labMat, lineWidth: 3))
    }
}

/// Paint colour picker: a full hue/saturation wheel, a brightness slider, the current
/// colour, ready-made shades and recently used colours.
struct ColorWheelPanel: View {
    @EnvironmentObject var model: WorkshopModel
    let scale: CGFloat

    var body: some View {
        let s = scale
        let size = 230 * s
        VStack(alignment: .leading, spacing: 12 * s) {
            HStack {
                Text("Colour").font(LabFont.heavy(20 * s)).foregroundStyle(Color.labPaper)
                Spacer()
                current(s)
            }
            wheel(size: size, s)
            LabSlider(title: "Brightness", value: model.brightness, range: 0.05...1,
                      format: { "\(Int(($0 * 100).rounded()))%" }, scale: s) { model.brightness = $0 }
            swatchGrid(WorkshopModel.swatches, title: "Shades", s)
            if !model.recent.isEmpty {
                swatchGrid(model.recent, title: "Recent", s)
            }
        }
        .padding(16 * s)
        .frame(width: size + 32 * s)
        .background(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).fill(Color.labInk.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).stroke(Color.labBlue, lineWidth: 2.5))
    }

    private var currentColor: Color {
        Color(hue: Double(model.hue), saturation: Double(model.saturation), brightness: Double(model.brightness))
    }

    private func current(_ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
            .fill(currentColor)
            .frame(width: 64 * s, height: 34 * s)
            .overlay(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).stroke(Color.labPaper, lineWidth: 2.5))
    }

    /// Hue around the rim, saturation from the white centre outward; the knob shows the pick.
    private func wheel(size: CGFloat, _ s: CGFloat) -> some View {
        let hues = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) }
        let r = size / 2
        let a = CGFloat(model.hue) * 2 * .pi
        let knob = CGSize(width: cos(a) * r * CGFloat(model.saturation), height: sin(a) * r * CGFloat(model.saturation))
        return ZStack {
            Circle().fill(AngularGradient(gradient: Gradient(colors: hues), center: .center))
            Circle().fill(RadialGradient(colors: [Color.white, Color.white.opacity(0)], center: .center, startRadius: 0, endRadius: r))
            Circle().fill(Color.black.opacity(Double(1 - model.brightness)))
            Circle().stroke(Color.labInk, lineWidth: 3)
            Circle()
                .fill(currentColor)
                .frame(width: 30 * s, height: 30 * s)
                .overlay(Circle().stroke(Color.labPaper, lineWidth: 3))
                .overlay(Circle().stroke(Color.labInk, lineWidth: 1.5).padding(-2))
                .offset(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            let dx = v.location.x - r, dy = v.location.y - r
            var h = atan2(dy, dx) / (2 * .pi)
            if h < 0 { h += 1 }
            model.hue = Float(h)
            model.saturation = Float(min(1, (dx * dx + dy * dy).squareRoot() / r))
            if model.brightness < 0.15 { model.brightness = 0.9 }
        })
    }

    private func swatchGrid(_ colors: [PaintColor], title: String, _ s: CGFloat) -> some View {
        let perRow = 6
        let rows = stride(from: 0, to: colors.count, by: perRow).map { Array(colors[$0..<min($0 + perRow, colors.count)]) }
        return VStack(alignment: .leading, spacing: 6 * s) {
            Text(title).font(LabFont.heavy(13 * s)).foregroundStyle(Color.labPaper.opacity(0.7))
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6 * s) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        let c = rows[r][i]
                        let picked = c == model.color
                        Button {
                            model.pick(c)
                        } label: {
                            RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                                .fill(Color(red: Double(c.r), green: Double(c.g), blue: Double(c.b)))
                                .frame(width: 32 * s, height: 32 * s)
                                .overlay(RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                                    .stroke(picked ? Color.labPaper : Color.labMat, lineWidth: picked ? 3 : 1.5))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }
}
