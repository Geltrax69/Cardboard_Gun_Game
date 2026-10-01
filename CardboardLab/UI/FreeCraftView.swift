import SwiftUI

/// Free Craft designer: the weapon spins on a turntable on the left; the parts panel on
/// the right picks its type, blade, tip, edge, guard, pommel or axe head, handle and grip
/// bands. Parts that aren't unlocked yet show the level they arrive at.
struct FreeCraftView: View {
    @EnvironmentObject var engine: GameEngine
    @EnvironmentObject var model: FreeCraftModel
    @EnvironmentObject var profile: PlayerProfile
    let scale: CGFloat
    /// Last drag translation / pinch magnification, to turn them into deltas.
    @State private var lastDrag: CGSize?
    @State private var lastPinch: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let s = scale
            let panelWidth = min(geo.size.width * 0.44, 560 * s)
            let stageWidth = geo.size.width - panelWidth - 36 * s
            ZStack(alignment: .topLeading) {
                // The whole area left of the panel turns the weapon: drag in any direction
                // to see it from the top, the bottom or any side; pinch to zoom.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: stageWidth, height: geo.size.height)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if let last = lastDrag {
                                engine.designerDrag(dx: Float(v.translation.width - last.width),
                                                    dy: Float(v.translation.height - last.height))
                            } else {
                                engine.designerDragBegan()
                            }
                            lastDrag = v.translation
                        }
                        .onEnded { _ in
                            lastDrag = nil
                            engine.designerDragEnded()
                        })
                    .simultaneousGesture(MagnifyGesture()
                        .onChanged { v in
                            let last = lastPinch ?? 1
                            engine.designerPinch(Float(v.magnification / max(last, 0.01)))
                            lastPinch = v.magnification
                        }
                        .onEnded { _ in lastPinch = nil })

                // Top-left: home, reset view, name of the weapon, how to turn it.
                HStack(alignment: .top, spacing: 14 * s) {
                    HomeButton(size: 64 * s) { engine.closeFreeCraft() }
                    RoundIconButton(systemName: "arrow.counterclockwise", size: 50 * s) { engine.resetDesignerView() }
                        .padding(.top, 7 * s)
                        .accessibilityLabel("Reset view")
                    VStack(alignment: .leading, spacing: 4 * s) {
                        OutlinedText(text: model.design.name, font: LabFont.black(34 * s), fill: .labCardboardLight,
                                     width: 2.5 * s, depth: 4 * s)
                        Text("FREE CRAFT · drag to turn it any way · pinch to zoom")
                            .font(LabFont.heavy(14 * s))
                            .foregroundStyle(Color.labPaper.opacity(0.85))
                            .shadow(color: .labInk, radius: 0, x: 0, y: 2)
                    }
                }
                .padding(.leading, 22 * s)
                .padding(.top, 18 * s)

                // Bottom-left: what the sheet will hold.
                statsBar(s)
                    .position(x: (geo.size.width - panelWidth) / 2, y: geo.size.height - 44 * s)

                panel(s)
                    .frame(width: panelWidth, height: geo.size.height - 36 * s)
                    .position(x: geo.size.width - panelWidth / 2 - 18 * s, y: geo.size.height / 2)
            }
        }
    }

    // MARK: Panel

    private var design: WeaponDesign { model.design }
    private var level: Int { profile.level }

    private func panel(_ s: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Parts").font(LabFont.heavy(24 * s)).foregroundStyle(Color.labPaper)
                Spacer()
                Text("Level \(level) · more parts unlock as you level up")
                    .font(LabFont.semibold(12 * s))
                    .foregroundStyle(Color.labYellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16 * s)
            .padding(.top, 14 * s)
            .padding(.bottom, 8 * s)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14 * s) {
                    section("Type", s) {
                        chips(WeaponKind.allCases, selected: design.kind, title: { $0.title },
                              level: { FreeCraftParts.level(of: $0) }, s) { model.setKind($0) }
                    }
                    if let b = design.blade {
                        bladeSection(b, s)
                        section("Guard", s) {
                            chips([WingStyle?.none] + FreeCraftParts.guardStyles.map { Optional($0) }, selected: design.guardClip?.style,
                                  title: { $0?.title ?? "None" }, level: { $0.map { FreeCraftParts.level(of: $0) } ?? 1 }, s) { model.setGuard($0) }
                            if let g = design.guardClip {
                                LabSlider(title: "Guard width", value: g.span, range: FreeCraftParts.guardSpanRange(design),
                                          format: cm, scale: s) { model.setGuardSpan($0) }
                            }
                        }
                        section("Pommel", s) {
                            chips([WingStyle?.none] + FreeCraftParts.pommelStyles.map { Optional($0) }, selected: design.endClip?.style,
                                  title: { $0?.title ?? "None" }, level: { $0.map { FreeCraftParts.level(of: $0) } ?? 1 }, s) { model.setEnd($0) }
                            if design.endClip != nil {
                                LabSlider(title: "Pommel size", value: model.endSize, range: FreeCraftParts.endSizeRange(design),
                                          format: cm, scale: s) { model.setEndSize($0) }
                            }
                        }
                    } else {
                        section("Axe head", s) {
                            chips(FreeCraftParts.axeHeads, selected: design.endClip?.style, title: { $0.title },
                                  level: { FreeCraftParts.level(of: $0) }, s) { model.setEnd($0) }
                            LabSlider(title: "Head size", value: model.endSize, range: FreeCraftParts.endSizeRange(design),
                                      format: { "\(Int(($0 * 100).rounded()))%" }, scale: s) { model.setEndSize($0) }
                        }
                    }
                    handleSection(s)
                }
                .padding(.horizontal, 16 * s)
                .padding(.bottom, 12 * s)
            }

            footer(s)
        }
        .background(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).fill(Color.labInk.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).stroke(Color.labBlue, lineWidth: 2.5))
    }

    @ViewBuilder
    private func bladeSection(_ b: BladeSpec, _ s: CGFloat) -> some View {
        section("Blade", s) {
            chips(BladeBuild.allCases, selected: b.build, title: { $0 == .ridge ? "Double edge" : "Single edge" },
                  level: { FreeCraftParts.level(of: $0) }, s) { model.setBuild($0) }
            Text("Tip").font(LabFont.heavy(13 * s)).foregroundStyle(Color.labPaper.opacity(0.7))
            chips(FreeCraftParts.tips(for: b.build), selected: b.tip, title: { $0.title },
                  level: { FreeCraftParts.level(of: $0) }, s) { model.setTip($0) }
            Text("Edge").font(LabFont.heavy(13 * s)).foregroundStyle(Color.labPaper.opacity(0.7))
            chips(EdgeStyle.allCases, selected: b.edge, title: { $0 == .plain ? "Plain" : "Serrated" },
                  level: { $0 == .plain ? 1 : FreeCraftParts.serratedLevel }, s) { model.setEdge($0) }
            LabSlider(title: "Length", value: b.length, range: FreeCraftParts.lengthRange(design), format: cm, scale: s) { model.setLength($0) }
            LabSlider(title: "Width", value: b.width, range: FreeCraftParts.widthRange, format: cm, scale: s) { model.setWidth($0) }
            if b.build == .laminate {
                LabSlider(title: "Curve", value: b.curve, range: 0...1, format: { "\(Int(($0 * 100).rounded()))%" }, scale: s) { model.setCurve($0) }
            } else {
                toggleChip("Fuller groove", on: b.fuller, level: FreeCraftParts.fullerLevel, s) { model.toggleFuller() }
            }
        }
    }

    private func handleSection(_ s: CGFloat) -> some View {
        section(design.kind == .axe ? "Shaft" : "Handle", s) {
            LabSlider(title: "Length", value: design.handleLength, range: FreeCraftParts.handleRange(design.kind),
                      format: cm, scale: s) { model.setHandleLength($0) }
            Text("Grip bands").font(LabFont.heavy(13 * s)).foregroundStyle(Color.labPaper.opacity(0.7))
            chips(Array(0...FreeCraftParts.maxWraps), selected: design.wraps.count, title: { "\($0)" }, level: { _ in 1 }, s) {
                model.setWraps($0)
            }
            if design.kind != .axe && design.endClip == nil {
                toggleChip("Lanyard hole", on: design.lanyardHole, level: 1, s) { model.toggleLanyard() }
            }
        }
    }

    private func footer(_ s: CGFloat) -> some View {
        HStack(spacing: 12 * s) {
            Button { model.randomize(); engine.sound.play(.tap) } label: {
                Label("Surprise me", systemImage: "dice.fill")
            }
            .buttonStyle(SettingsButtonStyle(fill: .labBlue))
            Button { engine.craftFreeDesign() } label: {
                HStack(spacing: 10 * s) {
                    Text("Craft it!").font(LabFont.black(24 * s))
                    Image(systemName: "arrow.right").font(.system(size: 20 * s, weight: .black))
                }
                .foregroundStyle(Color.labPaper)
                .frame(maxWidth: .infinity)
                .frame(height: 56 * s)
                .background(Capsule().fill(Color.labRed))
                .overlay(Capsule().stroke(Color.labInk, lineWidth: 3))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(14 * s)
        .background(Color.labTable.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 26 * s, style: .continuous))
    }

    private func statsBar(_ s: CGFloat) -> some View {
        let st = model.stats
        return HStack(spacing: 14 * s) {
            statChip("square.on.square", "\(st.pieces) pieces", s)
            statChip("list.number", "\(st.steps) steps", s)
            statChip("rectangle.dashed", "Sheet \(Int((st.sheet.x * 2).rounded())) × \(Int((st.sheet.y * 2).rounded())) cm", s)
        }
    }

    private func statChip(_ icon: String, _ text: String, _ s: CGFloat) -> some View {
        HStack(spacing: 6 * s) {
            Image(systemName: icon).font(.system(size: 14 * s, weight: .bold)).foregroundStyle(Color.labBlue)
            Text(text).font(LabFont.heavy(14 * s)).foregroundStyle(Color.labPaper)
        }
        .padding(.horizontal, 12 * s).padding(.vertical, 7 * s)
        .background(Capsule().fill(Color.labInk.opacity(0.88)))
        .overlay(Capsule().stroke(Color.labMat, lineWidth: 1.5))
    }

    // MARK: Building blocks

    /// Template units are about half a centimetre.
    private func cm(_ v: Float) -> String { String(format: "%.1f cm", v * 2) }

    private func section<C: View>(_ title: String, _ s: CGFloat, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text(title.uppercased())
                .font(LabFont.black(14 * s))
                .foregroundStyle(Color.labCardboardLight)
            content()
        }
        .padding(12 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18 * s, style: .continuous).fill(Color.labTable))
        .overlay(RoundedRectangle(cornerRadius: 18 * s, style: .continuous).stroke(Color.labMat, lineWidth: 1.5))
    }

    /// Rows of selectable chips (four per row). Locked ones show their unlock level.
    private func chips<T: Equatable>(_ items: [T], selected: T?, title: @escaping (T) -> String, level: @escaping (T) -> Int,
                                     _ s: CGFloat, pick: @escaping (T) -> Void) -> some View {
        let perRow = 4
        let rows = stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
        return VStack(spacing: 8 * s) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8 * s) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        let item = rows[r][i]
                        let need = level(item)
                        chip(title(item), selected: selected == item, lockedLevel: need > self.level ? need : nil, s) {
                            if need > self.level {
                                engine.toast("Unlocks at level \(need) — keep crafting!", .hint, life: 2)
                            } else {
                                engine.sound.play(.tap)
                                pick(item)
                            }
                        }
                    }
                    if rows[r].count < perRow {
                        ForEach(0..<(perRow - rows[r].count), id: \.self) { _ in Color.clear.frame(height: 1) }
                    }
                }
            }
        }
    }

    private func chip(_ text: String, selected: Bool, lockedLevel: Int?, _ s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1 * s) {
                Text(text)
                    .font(LabFont.heavy(14 * s))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let l = lockedLevel {
                    HStack(spacing: 3 * s) {
                        Image(systemName: "lock.fill").font(.system(size: 9 * s, weight: .bold))
                        Text("Lv \(l)").font(LabFont.heavy(10 * s))
                    }
                }
            }
            .foregroundStyle(selected ? Color.labInk : Color.labPaper.opacity(lockedLevel == nil ? 1 : 0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 40 * s)
            .background(Capsule().fill(selected ? Color.labYellow : Color.labInk))
            .overlay(Capsule().stroke(selected ? Color.labInk : Color.labMat, lineWidth: 2))
        }
        .buttonStyle(PressableStyle())
    }

    private func toggleChip(_ title: String, on: Bool, level need: Int, _ s: CGFloat, action: @escaping () -> Void) -> some View {
        let locked = need > level
        return Button {
            if locked {
                engine.toast("Unlocks at level \(need) — keep crafting!", .hint, life: 2)
            } else {
                engine.sound.play(.tap)
                action()
            }
        } label: {
            HStack(spacing: 10 * s) {
                Image(systemName: locked ? "lock.fill" : (on ? "checkmark.square.fill" : "square"))
                    .font(.system(size: 18 * s, weight: .bold))
                Text(locked ? "\(title) · Lv \(need)" : title).font(LabFont.heavy(15 * s))
                Spacer()
            }
            .foregroundStyle(on ? Color.labMint : Color.labPaper.opacity(locked ? 0.45 : 0.9))
            .padding(.horizontal, 12 * s)
            .frame(height: 40 * s)
            .background(Capsule().fill(Color.labInk))
            .overlay(Capsule().stroke(on ? Color.labMint : Color.labMat, lineWidth: 2))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Chunky slider: label and value on top, a draggable track below.
struct LabSlider: View {
    let title: String
    let value: Float
    let range: ClosedRange<Float>
    let format: (Float) -> String
    let scale: CGFloat
    let onChange: (Float) -> Void

    var body: some View {
        let s = scale
        let span = max(range.upperBound - range.lowerBound, 1e-4)
        let k = CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack {
                Text(title).font(LabFont.heavy(14 * s)).foregroundStyle(Color.labPaper)
                Spacer()
                Text(format(value)).font(LabFont.heavy(14 * s)).monospacedDigit().foregroundStyle(Color.labYellow)
            }
            GeometryReader { g in
                let w = g.size.width
                let knob = 28 * s
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.labInk)
                        .frame(height: 12 * s)
                    Capsule().fill(Color.labBlue)
                        .frame(width: max(12 * s, (w - knob) * k + knob / 2), height: 12 * s)
                    Circle().fill(Color.labPaper)
                        .overlay(Circle().stroke(Color.labInk, lineWidth: 2.5))
                        .frame(width: knob, height: knob)
                        .offset(x: (w - knob) * k)
                }
                .frame(height: knob)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let f = Float(min(1, max(0, (v.location.x - knob / 2) / max(w - knob, 1))))
                    onChange(range.lowerBound + span * f)
                })
            }
            .frame(height: 28 * s)
        }
    }
}
