import SceneKit
import UIKit

/// Builds any weapon from its `WeaponBlueprint`, stage by stage (stages a design doesn't
/// need are skipped, so the HUD shows 5 or 6 steps):
///   CUT       — cut every piece out of the sheet (matching bands are cut in one pass)
///   HANDLE    — score, fold and glue the handle box, then close the lid
///   BLADE     — pinch the ridge and glue the tang, or glue and fold the twin layer
///   FITTINGS  — score, glue and fold the guard, pommel or axe head clips
///   ASSEMBLE  — guard on, blade in, pommel / axe head on, bands wrapped
///   SHARPEN   — sand the edges into bevels, shape the tip, carve the fuller
@MainActor
final class WeaponSession: CraftSession {
    let bp: WeaponBlueprint
    var design: WeaponDesign { bp.design }
    private(set) var sheet: TemplateSheet!
    private var startTime: Double = 0
    private var startCoins = 0
    private var perfectFolds = 0
    /// Finished weapon: `weaponRoot` sits at the weapon's centre (spins in place),
    /// `assembly` holds the pieces in handle space.
    private let weaponRoot = SCNNode()
    private let assembly = SCNNode()
    private var spinID: Int?
    private var connectIndex = 0

    init(engine: GameEngine, project: ProjectInfo, design: WeaponDesign, stock: CardboardStock) {
        bp = WeaponBlueprint(design: design, thickness: stock.thickness)
        super.init(engine: engine, project: project, stock: stock)
    }

    override func run() async throws {
        hud.reset(steps: design.stepCount)
        startTime = engine.time
        startCoins = engine.profile.coins
        try await placeTemplate()
        try await stageCut()
        try await stageHandle()
        if bp.hasBlade { try await stageBlade() }
        if design.stages.contains(.fittings) { try await stageFittings() }
        try await stageAssemble()
        if design.stages.contains(.sharpen) { try await stageSharpen() }
        try await finale()
    }

    override func cleanup() {
        engine.removeFrameHandler(spinID)
        spinID = nil
    }

    /// HUD step number of a stage.
    private func number(_ s: WeaponStage) -> Int { (design.stages.firstIndex(of: s) ?? 0) + 1 }

    private var handleName: String { design.kind == .axe ? "Shaft" : "Handle" }
    private var weaponName: String { design.name.lowercased() }

    // MARK: Template

    private func placeTemplate() async throws {
        say("Fresh sheet", "The \(weaponName) template is traced onto the cardboard.", tool: HUDTool.none)
        sheet = TemplateSheet(template: bp.template, stock: stock)
        engine.craftRoot.childNodes.forEach { $0.removeFromParentNode() }
        engine.craftRoot.addChildNode(sheet.root)
        try await sheet.printTemplate(pencil: engine.workspace.pencil, tweener: tw)
    }

    // MARK: Cut

    private var cutOrder: [String] {
        ["blade", "handle", "guard", "end"].filter { bp.piece($0) != nil } + design.wraps.indices.map { "wrap\($0)" }
    }

    private func stageCut() async throws {
        let n = number(.cut)
        let order = cutOrder
        let knife = engine.workspace.knife
        var firstCut = true
        for (i, id) in order.enumerated() {
            guard let def = bp.piece(id), let outline = sheet.outlineCuts[id] else { continue }
            let detail = "\(def.name) · \(i + 1) of \(order.count)"
            let inner = sheet.innerCuts[id] ?? []
            // Frame the piece so the line is big under the finger.
            let b = def.sheetBounds
            let center = ((b.min + b.max) / 2).onMat(0)
            let size = V2(max(b.max.x - b.min.x + 4, 10), max(b.max.y - b.min.y + 3, 6.5))
            glide(to: center, size: size, shot: .topDown, duration: 0.8)

            if id.hasPrefix("wrap") && id != "wrap0" {
                // Matching bands: one quick pass, the knife already knows the way.
                step(n, "Same again", "Matching band — the knife runs round it in one go.", tool: .knife, detail: detail)
                try await autoCut(outline, knife: knife)
                try await freePiece(id)
                reward(30, at: sheet.center(of: id) + V3(0, 0.6, 0))
                continue
            }
            for (k, hole) in inner.enumerated() {
                step(n, "Punch the hole", "Trace the small red circle with the knife.", tool: .knife, detail: detail)
                try await TraceInteraction.cut(session: self, line: hole, knife: knife, showHint: hintsOn && firstCut).run()
                firstCut = false
                if let disc = sheet.holeDiscs[id]?[k] { popDisc(disc, world: hole.path.point(at: 0)) }
                reward(20, at: hole.path.point(at: 0))
            }
            step(n, "Cut out the \(def.name.lowercased())", "Follow the solid red line with the craft knife.", tool: .knife, detail: detail)
            try await TraceInteraction.cut(session: self, line: outline, knife: knife, showHint: hintsOn && firstCut).run()
            firstCut = false
            try await freePiece(id)
            reward(id == "blade" ? 100 : 60, at: sheet.center(of: id) + V3(0, 0.6, 0))
        }
        // Tools down, scraps away.
        let from = knife.pose
        let rest = engine.workspace.knifeRest
        tw.start(0.6, ease: .inOutCubic) { k in knife.setPose(from.lerp(rest, k)) }
        try await clearWaste()
        say("All pieces cut out!", "Clean edges. Next you'll fold the \(handleName.lowercased()) into a box.", tool: .knife)
        try await waitForNext()
    }

    /// The knife runs round a cut line by itself.
    private func autoCut(_ line: CutLineNode, knife: SCNNode) async throws {
        let path = line.path
        let start = TraceInteraction.knifePose(tip: path.point(at: 0), tangent: path.tangent(at: 0))
        let from = knife.pose
        let hover = Pose(rot: start.rot, pos: start.pos + V3(0, 1.0, 0))
        try await tw.tween(0.3, ease: .inOutCubic) { k in knife.setPose(from.lerp(hover, k)) }
        try await tw.tween(0.12, ease: .inQuad) { k in knife.setPose(hover.lerp(start, k)) }
        let engine = self.engine
        var lastFlake: Float = 0
        try await tw.tween(1.1, ease: .inOutSine) { k in
            let d = path.length * k
            line.setProgress(d)
            line.setActive(true, time: engine.time)
            let p = path.point(at: d)
            knife.setPose(TraceInteraction.knifePose(tip: p, tangent: path.tangent(at: d)))
            if d - lastFlake > 0.4 {
                lastFlake = d
                engine.particles.flakes(at: p, count: 2, direction: path.tangent(at: d))
                engine.sound.play(.cut, volume: 0.6, minInterval: 0.06)
            }
        }
        line.setActive(false, time: engine.time)
        let end = knife.pose
        try await tw.tween(0.15, ease: .outQuad) { k in knife.setPose(Pose(rot: end.rot, pos: end.pos + V3(0, 0.6 * k, 0))) }
    }

    /// The finished piece lifts out of the sheet, shows its edges and drifts outward.
    private func freePiece(_ id: String) async throws {
        guard let piece = sheet.pieces[id], let cut = sheet.outlineCuts[id] else { return }
        let holes = sheet.innerCuts[id] ?? []
        piece.setInkVisible(true)
        let base = piece.pose
        var away = sheet.center(of: id)
        away.y = 0
        away = away.len > 0.01 ? away.unit * 0.35 : V3(0, 0, 0.35)
        engine.particles.flakes(at: sheet.center(of: id), count: 10)
        engine.sound.play(.snap, volume: 0.7)
        try await tw.tween(0.5, ease: .outBack) { k in
            piece.pose = Pose(rot: base.rot, pos: base.pos + V3(away.x * k, 0.32 * k, away.z * k))
            cut.fade(k)
            for h in holes { h.fade(k) }
        }
        success("Clean cut!", at: sheet.center(of: id) + V3(0, 0.8, 0))
    }

    /// Punched-out disc hops out of its hole and tumbles onto the mat.
    private func popDisc(_ disc: SCNNode, world: V3) {
        let start = disc.pos3
        tw.start(0.7, ease: .linear) { k in
            let p = start + V3(0.9 * k, 1.3 * sin(Float(k) * .pi) - 0.2 * k, 0.5 * k)
            disc.setPosition(p)
            disc.eulerAngles = SCNVector3(k * 5, 0, k * 3)
            disc.opacity = CGFloat(k < 0.7 ? 1 : (1 - k) / 0.3)
        }
        engine.particles.flakes(at: world, count: 4)
    }

    /// The leftover board slides off the mat; the pieces settle onto the mat.
    private func clearWaste() async throws {
        let waste = sheet.waste
        let start = waste.pose
        engine.sound.play(.whoosh)
        try await tw.tween(0.9, ease: .inCubic) { k in
            let spin = Quat(axis: up3, angle: 0.35 * k)
            waste.setPose(Pose(rot: start.rot * spin, pos: start.pos + V3(-34 * k, 0.2 * k, 4 * k)))
        }
        waste.isHidden = true
        for cut in sheet.allCutLines { cut.root.isHidden = true }
        let pieces = Array(sheet.pieces.values)
        let starts = pieces.map { $0.pose }
        try await tw.tween(0.35, ease: .inQuad) { k in
            for (p, s) in zip(pieces, starts) {
                p.pose = Pose(rot: s.rot, pos: V3(s.pos.x, s.pos.y * (1 - k), s.pos.z))
            }
        }
        rig.addShake(0.1)
        glide(to: V3(0, 0, 0), size: bp.template.sheetSize + V2(2.5, 2.2), shot: .topDown, duration: 0.9)
    }

    // MARK: Shared moves

    /// Centre and size of a piece's flat footprint, for framing.
    private func frame(_ piece: PieceNode, pad: V2 = V2(3.2, 2.8), min: V2 = V2(7, 5.5)) -> (center: V3, size: V2) {
        let b = Poly.bounds(piece.def.outline)
        let size = b.max - b.min + pad
        return (piece.pose.apply(((b.min + b.max) / 2).onMat(0)), V2(Swift.max(size.x, min.x), Swift.max(size.y, min.y)))
    }

    /// Scores several hinges in turn with the bone folder, then puts it back.
    private func scoreCreases(_ piece: PieceNode, _ panels: [String], hint: Bool) async throws {
        let folder = engine.workspace.boneFolder
        for (i, id) in panels.enumerated() {
            if panels.count > 1 { hud.detail = "Crease \(i + 1) of \(panels.count)" }
            try await scoreCrease(piece, id, folder: folder, first: hint && i == 0)
        }
        let fp = folder.pose, rest = engine.workspace.folderRest
        tw.start(0.6) { k in folder.setPose(fp.lerp(rest, k)) }
        success(panels.count > 1 ? "Creases scored!" : "Crease scored!")
    }

    /// Swipe the bone folder along a hinge; the crease darkens and the flap flexes.
    private func scoreCrease(_ piece: PieceNode, _ panel: String, folder: SCNNode, first: Bool) async throws {
        guard let def = piece.def.panel(panel), let h = def.hinge, let parent = def.parent else { return }
        let wp = piece.worldPose(of: parent)
        let y = stock.thickness + 0.012
        let line = ScoreLineNode(points: [wp.apply(h.a.onMat(y)), wp.apply(h.b.onMat(y))])
        engine.craftRoot.addChildNode(line.root)
        defer { line.root.removeFromParentNode() }
        try await TraceInteraction.score(session: self, line: line, folder: folder, showHint: hintsOn && first).run()
        piece.setCrease(panel, 0.55)
        let target = h.signedTarget
        tw.start(0.4, ease: .linear) { k in piece.setAngle(panel, target * 0.14 * sin(k * .pi)) }
    }

    /// Drag one flap about its crease until it snaps home.
    private func foldPanel(_ piece: PieceNode, _ panel: String, grab: V3, first: Bool,
                           successText: String = "Perfect fold") async throws {
        piece.highlight(panel, color: Palette.cardboardLight)
        let spec = FoldInteraction.Spec.panel(piece, panel, grab: grab)
        try await FoldInteraction(session: self, spec: spec, showHint: hintsOn && first).run()
        piece.highlight(panel, color: nil)
        piece.setCrease(panel, 1)
        piece.setFoldLine(panel, visible: false)
        perfectFolds += 1
        success(successText, at: spec.handle(1) + V3(0, 0.7, 0))
    }

    /// Lays a glue bead along a surface path. `auto` lets the bottle do it by itself.
    @discardableResult
    private func applyGlue(on piece: PieceNode, _ surface: SurfacePath, first: Bool, auto: Bool = false) async throws -> GlueBeadNode {
        let bead = GlueBeadNode(localPoints: surface.points, localNormal: surface.normal, toWorld: piece.worldPose(of: surface.panel))
        piece.panelNodes[surface.panel]?.addChildNode(bead.root)
        let bottle = engine.workspace.glue
        if auto {
            let path = bead.path
            let from = bottle.pose
            let start = TraceInteraction.bottlePose(tip: path.point(at: 0), tangent: path.tangent(at: 0))
            try await tw.tween(0.35, ease: .inOutCubic) { k in bottle.setPose(from.lerp(start, k)) }
            let engine = self.engine
            try await tw.tween(0.55, ease: .inOutSine) { k in
                let d = path.length * k
                bead.setProgress(d)
                bottle.setPose(TraceInteraction.bottlePose(tip: path.point(at: d), tangent: path.tangent(at: d)))
                engine.sound.play(.glue, volume: 0.5, minInterval: 0.12)
            }
        } else {
            try await TraceInteraction.glue(session: self, bead: bead, bottle: bottle, showHint: hintsOn && first).run()
        }
        bead.settle()
        if !auto { success("Glue applied", at: bead.path.point(at: bead.path.length / 2) + V3(0, 0.8, 0)) }
        let from = bottle.pose, rest = engine.workspace.glueRest
        tw.start(0.6, ease: .inOutCubic) { k in bottle.setPose(from.lerp(rest, k)) }
        return bead
    }

    /// Brief mint glow along a seam when two surfaces lock together.
    private func flashSeam(_ points: [V3]) {
        guard points.count > 1 else { return }
        var m = MeshData()
        MeshBuilder.ribbon(points, width: 0.2, into: &m)
        let node = SceneBridge.node(m, [Mat.unlit(Palette.mint, opacity: 0.9, depthWrite: false)], name: "seam")
        node.renderingOrder = 20
        node.castsShadow = false
        engine.craftRoot.addChildNode(node)
        for p in points { engine.particles.sparks(at: p, count: 6) }
        tw.start(0.9, ease: .inQuad) { k in
            node.opacity = CGFloat(1 - k)
            if k >= 1 { node.removeFromParentNode() }
        }
    }

    // MARK: Handle

    private var handle: PieceNode? { sheet.pieces["handle"] }

    /// Centre of the (folded) handle box in world space.
    private func handleCenter() -> V3 {
        (handle?.pose ?? .identity).apply(V3(bp.L / 2, 0.5, 0))
    }

    private func stageHandle() async throws {
        guard let handle else { return }
        let n = number(.handle)
        let t = stock.thickness
        let W = bp.W, H = bp.H, L = bp.L
        let name = handleName.lowercased()

        step(n, "Score the fold lines", "Run the bone folder along each blue dashed line.", tool: .scorer)
        let f = frame(handle)
        try await look(at: f.center, size: f.size, shot: .topDown, duration: 0.8)
        try await scoreCreases(handle, ["HS1", "HS2", "HT", "GT", "EC"], hint: true)

        step(n, "Fold the walls up", "Drag each flap up along the blue arrow.", tool: .hand)
        try await look(at: handleCenter(), size: V2(max(8, L + 3.6), 6.5), shot: .threeQuarter, duration: 1.1)
        showRotateTip()
        let flaps: [(String, V3)] = [
            ("HS1", V3(L / 2, t, -W / 2 - H)),
            ("HS2", V3(L / 2, t, W / 2 + H - t)),
            ("EC", V3(L + H, t, 0)),
        ]
        for (i, flap) in flaps.enumerated() {
            hud.detail = "Flap \(i + 1) of \(flaps.count)"
            try await foldPanel(handle, flap.0, grab: flap.1, first: i == 0)
        }
        say("Tuck in the glue tab", "Fold the little tab over, into the box.", tool: .hand)
        try await foldPanel(handle, "GT", grab: V3(L / 2, t, W / 2 + H - t + bp.tab), first: false)

        step(n, "Glue the tab", "Run the glue along the dotted guide on the tab.", tool: .glue)
        glide(to: handleCenter(), size: V2(max(6.8, L + 2.4), 5.6), shot: .threeQuarter, duration: 0.8)
        handle.highlight("GT", color: Palette.cardboardLight)
        try await applyGlue(on: handle, bp.handleGlue, first: true)
        handle.highlight("GT", color: nil)

        step(n, "Close the \(name)", "Fold the lid over onto the glued tab.", tool: .hand)
        // The matching surface glows mint so it's obvious where the lid lands.
        handle.highlight("GT", color: Palette.mint)
        let lidEdge = V3(L / 2, t, -W / 2 - H - W - t)
        try await foldPanel(handle, "HT", grab: lidEdge, first: true, successText: "Tab aligned")
        handle.highlight("GT", color: nil)
        flashSeam([0, L].map { handle.world("HT", V3($0, t, -W / 2 - H - W - t)) })
        rig.addShake(0.12)
        reward(50, at: handleCenter() + V3(0, 1.2, 0))
        say("\(handleName) closed!", bp.hasBlade ? "A sturdy little box. Now the blade." : "A long, sturdy shaft. Now the axe head.", tool: .hand)
        try await waitForNext()
    }

    // MARK: Blade

    private var blade: PieceNode? { sheet.pieces["blade"] }

    private func stageBlade() async throws {
        guard let blade, let b = design.blade else { return }
        if b.build == .ridge {
            try await ridgeBlade(blade, b)
        } else {
            try await laminateBlade(blade, b)
        }
    }

    private func ridgeBlade(_ blade: PieceNode, _ b: BladeSpec) async throws {
        let n = number(.blade)
        let t = stock.thickness
        let spot = blade.pose
        let mid = V3((b.tangLength - b.length) / 2, 0, 0)
        let size = V2(b.length + b.tangLength + 3, b.width + 3.5)
        step(n, "Score the blade's spine", "Run the bone folder along the blue dashed line.", tool: .scorer)
        try await look(at: spot.apply(mid), size: size, shot: .topDown, duration: 0.9)
        try await scoreCreases(blade, ["BL"], hint: false)

        step(n, "Fold the blade", "Drag up to pinch a ridge along the spine.", tool: .hand)
        try await look(at: spot.apply(mid), size: size * 0.92, shot: .threeQuarter, duration: 1.0)
        let bp = self.bp
        let outline = blade.def.outline
        let ridge = V3(-b.length * 0.35, t, 0), edge = V3(-b.length * 0.35, 0, -b.width / 2)
        var spec = FoldInteraction.Spec(
            handle: { p in (spot * bp.bladeRootPose(p)).apply(ridge) },
            pivot: { p in (spot * bp.bladeRootPose(p)).apply(edge) },
            outline: { p in outline.map { (spot * bp.bladeRootPose(p)).apply($0.onMat(t)) } },
            apply: { p in
                blade.setAngles(bp.bladeAngles(p))
                blade.pose = spot * bp.bladeRootPose(p)
                blade.setCrease("BL", min(1, 0.55 + p))
            }
        )
        spec.screenDirection = V2(0, -1)
        spec.arrowOffset = 0.9
        blade.highlight("BU", color: Palette.cardboardLight)
        blade.highlight("BL", color: Palette.cardboardLight)
        try await FoldInteraction(session: self, spec: spec, showHint: hintsOn).run()
        blade.highlight("BU", color: nil)
        blade.highlight("BL", color: nil)
        blade.setFoldLine("BL", visible: false)
        perfectFolds += 1
        success("Perfect fold", at: spot.apply(mid) + V3(0, 1.2, 0))

        if let glue = bp.bladeGlue {
            step(n, "Glue the tang", "Run the glue along the narrow end of the blade.", tool: .glue)
            glide(to: blade.pose.apply(V3(b.tangLength / 2, 0, 0)), size: V2(b.tangLength + 4, 4.5), shot: .threeQuarter, duration: 0.8)
            try await applyGlue(on: blade, glue, first: false)
        }
        say("Blade ready", "Ridge folded, tang glued. Next: the fittings.", tool: .hand)
        try await waitForNext()
    }

    /// Single-edged blades: glue the first layer, fold its mirrored twin over on top.
    private func laminateBlade(_ blade: PieceNode, _ b: BladeSpec) async throws {
        let n = number(.blade)
        let t = stock.thickness
        let hinge = blade.pose.apply(V3(b.tangLength, 0, 0))
        let layer = blade.pose.apply(V3((b.tangLength - b.length) / 2, 0, 0))

        step(n, "Score the fold", "Run the bone folder across the end of the tang.", tool: .scorer)
        try await look(at: hinge, size: V2(8, 5.5), shot: .topDown, duration: 0.9)
        try await scoreCreases(blade, ["LB"], hint: false)

        if let glue = bp.bladeGlue {
            step(n, "Glue the blade", "Run glue down the middle of the first layer.", tool: .glue)
            try await look(at: layer, size: V2(b.length + b.tangLength + 3, b.width + 3.5), shot: .topDown, duration: 0.9)
            try await applyGlue(on: blade, glue, first: false)
        }

        step(n, "Fold the twin over", "Drag the second layer over onto the glue.", tool: .hand)
        try await look(at: hinge + V3(0, 0.8, 0), size: V2(2 * (b.length + b.tangLength) * 0.7, 8), shot: .threeQuarter, duration: 1.0)
        blade.highlight("LA", color: Palette.mint)
        try await foldPanel(blade, "LB", grab: V3(2 * b.tangLength + b.length * 0.5, t, 0), first: hintsOn,
                            successText: "Layers aligned")
        blade.highlight("LA", color: nil)
        let centre = BladeShapes.laminate(b, tangHalf: bp.tangHalf).centre
        flashSeam(stride(from: 0, to: centre.count, by: 4).map { blade.world("LA", centre[$0].onMat(2 * t)) })
        rig.addShake(0.12)
        reward(50, at: layer + V3(0, 1.2, 0))
        say("Blade ready", "Two layers glued into one stiff blade.", tool: .hand)
        try await waitForNext()
    }

    // MARK: Fittings (guards, pommels, axe heads)

    private var clipIDs: [String] { ["guard", "end"].filter { sheet.pieces[$0] != nil } }

    private func stageFittings() async throws {
        let n = number(.fittings)
        let t = stock.thickness
        let ids = clipIDs
        for (i, id) in ids.enumerated() {
            guard let clip = sheet.pieces[id] else { continue }
            let name = clip.def.name.lowercased()
            let detail = ids.count > 1 ? "\(clip.def.name) · \(i + 1) of \(ids.count)" : clip.def.name
            let f = frame(clip, min: V2(7.5, 6))

            step(n, "Score the \(name)", "Run the bone folder along both blue dashed lines.", tool: .scorer, detail: detail)
            try await look(at: f.center, size: f.size, shot: .topDown, duration: 0.8)
            try await scoreCreases(clip, ["WA", "WB"], hint: false)
            hud.detail = detail

            if let glue = bp.clipGlue(id) {
                step(n, "Glue the \(name)", "Lay glue across the wing that will sit on top.", tool: .glue, detail: detail)
                clip.highlight("WB", color: Palette.cardboardLight)
                try await applyGlue(on: clip, glue, first: false)
                clip.highlight("WB", color: nil)
            }

            step(n, "Fold the wings up", "Drag both wings up so the \(name) becomes a U.", tool: .hand, detail: detail)
            try await look(at: f.center + V3(0, 0.6, 0), size: f.size * 0.95, shot: .threeQuarter, duration: 0.9)
            for w in ["WA", "WB"] {
                let grab = (clip.def.panel(w)?.centroid ?? V2(0, 0)).onMat(t)
                try await foldPanel(clip, w, grab: grab, first: false)
            }
            reward(40, at: f.center + V3(0, 1.4, 0))
        }
        say("Fittings ready", "Everything is folded. Time to put the \(weaponName) together!", tool: .hand)
        try await waitForNext()
    }

    // MARK: Assembly

    /// Handle frame in world space while the weapon is held up.
    private var handleWorld: Pose { weaponRoot.pose * assembly.pose }

    private var connectCount: Int {
        clipIDs.count + (bp.hasBlade ? 1 : 0) + design.wraps.count
    }

    private func nextConnect() -> String {
        connectIndex += 1
        return "Connect · \(connectIndex) of \(connectCount)"
    }

    /// Highest point of a piece lying on the mat.
    private func topY(_ piece: PieceNode) -> Float {
        piece.rig.foldedCorners().map { piece.pose.apply($0).y }.max() ?? 0
    }

    private func stageAssemble() async throws {
        guard let handle else { return }
        let n = number(.assemble)
        let t = stock.thickness
        connectIndex = 0

        // 1. Pick the handle up (fittings wrap underneath it), high enough to clear the
        //    folded parts still on the mat.
        step(n, "Pick it up", "The \(handleName.lowercased()) lifts off the mat so the parts can go on.", tool: .hand)
        let centre = bp.assembledCentre
        let ext = bp.assembledBounds()
        let half = (ext.max - ext.min) / 2
        let tallest = sheet.pieces.values.filter { $0 !== handle }.map { topY($0) }.max() ?? 0
        let liftY = max(1.9, tallest + 0.7)
        let ground = handle.pose * Pose.translation(centre)
        var p = ground.pos
        p.x = clampf(p.x, -14 + half.x, Swift.max(-14 + half.x, 14 - half.x))
        p.z = clampf(p.z, -9.5 + half.z, Swift.max(-9.5 + half.z, 9.5 - half.z))
        p.y = liftY + centre.y
        let held = Pose(rot: ground.rot, pos: p)
        weaponRoot.name = "finishedWeapon"
        assembly.name = "assembly"
        weaponRoot.setPose(ground)
        assembly.setPose(.translation(centre * -1))
        weaponRoot.addChildNode(assembly)
        engine.craftRoot.addChildNode(weaponRoot)
        assembly.addChildNode(handle.root)
        handle.pose = .identity
        glide(to: held.pos, size: V2(2 * half.x + 4, 2 * half.z + 7), shot: .threeQuarter, duration: 1.0)
        let root = weaponRoot
        try await tw.tween(0.8, ease: .outBack) { k in root.setPose(ground.lerp(held, k)) }

        // 2. Guard on the front.
        if let guardClip = sheet.pieces["guard"] {
            step(n, "Slide the guard on", "Drag the guard onto the glowing outline.", tool: .hand, detail: nextConnect())
            try await mount(guardClip, ready: bp.clipReady("guard"), seat: bp.guardMount,
                            grabLocal: V3((bp.H + 2 * t) / 2, 0, 0),
                            seam: [V3(-t - 0.02, -0.05, -bp.W / 2 - t), V3(-t - 0.02, -0.05, bp.W / 2 + t)])
        }
        // 3. Blade into the handle (through the guard's slot).
        if let blade, let b = design.blade {
            let text = design.guardClip != nil ? "Push the tang through the guard into the handle." : "Drag the blade onto the glowing outline."
            step(n, "Slide the blade in", text, tool: .hand, detail: nextConnect())
            let mouth: Float = design.guardClip != nil ? -t - 0.03 : 0.02
            try await mount(blade, ready: bp.bladeReady, seat: bp.bladeSeated,
                            grabLocal: V3(-b.length * 0.4, t, 0),
                            seam: [V3(mouth, t, -bp.W / 2), V3(mouth, bp.H + t, -bp.W / 2),
                                   V3(mouth, bp.H + t, bp.W / 2), V3(mouth, t, bp.W / 2)])
        }
        // 4. Pommel or axe head on the far end.
        if let endClip = sheet.pieces["end"] {
            let axe = design.endClip?.style.isAxeHead == true
            step(n, axe ? "Mount the axe head" : "Fit the pommel", "Drag it onto the glowing outline.", tool: .hand, detail: nextConnect())
            try await mount(endClip, ready: bp.clipReady("end"), seat: bp.endMount,
                            grabLocal: V3((bp.H + 2 * t) / 2, 0, 0),
                            seam: [V3(bp.L + t + 0.02, bp.H + 2 * t + 0.05, -bp.W / 2 - t),
                                   V3(bp.L + t + 0.02, bp.H + 2 * t + 0.05, bp.W / 2 + t)])
        }
        // 5. Bands around the grip.
        for i in design.wraps.indices {
            try await wrapBand(i, n: n)
        }
        say("\(design.name) assembled!", design.stages.contains(.sharpen) ? "Now give it a proper edge." : "Looking good.", tool: .hand, detail: nil)
        try await waitForNext()
    }

    /// Carry a piece to its glowing ready pose next to the handle, then slide it home and
    /// fix it into the assembly.
    private func mount(_ piece: PieceNode, ready: Pose, seat: Pose, grabLocal: V3, seam: [V3]) async throws {
        let hw = handleWorld
        let readyW = hw * ready, seatW = hw * seat
        let ext = bp.assembledBounds()
        glide(to: mix3(piece.pose.pos, readyW.pos, 0.5), size: V2(ext.max.x - ext.min.x + 6, 11), shot: .threeQuarter, duration: 0.9)
        let ghost = piece.makeGhost(color: Palette.mint)
        ghost.setPose(readyW)
        engine.craftRoot.addChildNode(ghost)
        let pulse = engine.onFrame { [weak self] _ in
            guard let self else { return }
            ghost.opacity = CGFloat(0.65 + 0.35 * sin(self.engine.time * 4))
        }
        defer {
            engine.removeFrameHandler(pulse)
            ghost.removeFromParentNode()
        }
        let spec = PlaceInteraction.Spec(
            current: { piece.pose },
            set: { piece.pose = $0 },
            target: readyW,
            hoverY: readyW.pos.y + 1.0,
            outline: { piece.footprint() },
            center: { piece.pose.apply(grabLocal) },
            carryRotation: readyW.rot
        )
        try await PlaceInteraction(session: self, spec: spec, showHint: hintsOn && connectIndex <= 1).run()
        engine.removeFrameHandler(pulse)
        ghost.removeFromParentNode()
        try await tw.tween(0.45, ease: .inOutCubic) { k in piece.pose = readyW.lerp(seatW, k) }
        engine.sound.play(.snap)
        rig.addShake(0.15)
        assembly.addChildNode(piece.root)
        piece.pose = seat
        flashSeam(seam.map { hw.apply($0) })
        success("Locked in", at: seatW.pos + V3(0, 1.4, 0))
        reward(50, at: seatW.pos + V3(0, 2.0, 0))
    }

    /// Glue a band, drop it across the top of the grip and let it wrap itself around.
    /// Bands after the first go on by themselves.
    private func wrapBand(_ i: Int, n: Int) async throws {
        guard let band = sheet.pieces["wrap\(i)"] else { return }
        let t = stock.thickness
        let auto = i > 0
        let detail = nextConnect()
        let name = i == 0 && design.kind == .knife ? "guard band" : "grip band"
        let bandCentre = V3(1.6, t, bp.bandWidth / 2)
        if auto {
            say("Same again", "The next band glues and wraps itself.", tool: .glue, detail: detail)
            glide(to: mix3(band.pose.pos, handleWorld.apply(V3(bp.L / 2, 0, 0)), 0.5), size: V2(bp.L + 9, 9), shot: .threeQuarter, duration: 0.7)
            try await applyGlue(on: band, bp.wrapGlue("wrap\(i)"), first: false, auto: true)
        } else {
            step(n, "Glue the \(name)", "Glue the end of the band where it will overlap.", tool: .glue, detail: detail)
            glide(to: band.pose.apply(bandCentre), size: V2(9, 5), shot: .threeQuarter, duration: 0.9)
            try await applyGlue(on: band, bp.wrapGlue("wrap\(i)"), first: false)
        }

        let target = handleWorld * bp.wrapMount(i)
        if auto {
            let from = band.pose
            try await tw.tween(0.6, ease: .inOutCubic) { k in
                let p = from.lerp(target, k)
                band.pose = Pose(rot: p.rot, pos: p.pos + V3(0, 1.4 * sin(k * .pi), 0))
            }
        } else {
            step(n, "Wrap the \(name)", "Drag the band onto the top of the \(handleName.lowercased()).", tool: .hand, detail: detail)
            glide(to: mix3(band.pose.pos, target.pos, 0.5), size: V2(13, 8.5), shot: .threeQuarter, duration: 1.0)
            let ghost = band.makeGhost(color: Palette.mint)
            ghost.setPose(target)
            engine.craftRoot.addChildNode(ghost)
            defer { ghost.removeFromParentNode() }
            let spec = PlaceInteraction.Spec(
                current: { band.pose },
                set: { band.pose = $0 },
                target: target,
                hoverY: target.pos.y + 0.8,
                outline: { band.footprint() },
                center: { band.pose.apply(bandCentre) },
                carryRotation: target.rot
            )
            try await PlaceInteraction(session: self, spec: spec, showHint: hintsOn && connectIndex <= 1).run()
            ghost.removeFromParentNode()
            glide(to: target.pos, size: V2(9, 6.5), shot: .threeQuarter, duration: 0.8)
        }
        for id in ["C1", "C2", "C3", "C4"] {
            try await tw.tween(auto ? 0.16 : 0.24, ease: .inOutCubic) { k in band.setFold(id, progress: k) }
            if let h = band.def.panel(id)?.hinge {
                engine.particles.sparks(at: band.world(id, h.midpoint.onMat(0)), count: 5)
            }
        }
        engine.sound.play(.fold)
        let hw = handleWorld
        assembly.addChildNode(band.root)
        band.pose = bp.wrapMount(i)
        let inset = design.wraps[i]
        flashSeam([hw.apply(V3(inset, bp.H + 3 * t, -bp.W / 2)), hw.apply(V3(inset + bp.bandWidth, bp.H + 3 * t, -bp.W / 2))])
        rig.addShake(0.1)
        success("Tab aligned", at: hw.apply(V3(inset, bp.H + 1.2, 0)))
        reward(auto ? 25 : 50, at: hw.apply(V3(inset, bp.H + 2, 0)))
    }

    // MARK: Sharpen & shape

    private func stageSharpen() async throws {
        let n = number(.sharpen)
        let sander = engine.workspace.sander
        let hw = handleWorld
        let paths = bp.sharpenPaths
        var tip: V3?
        for (i, surface) in paths.enumerated() {
            guard let piece = sheet.pieces[surface.piece], let panel = piece.def.panel(surface.panel),
                  let node = piece.panelNodes[surface.panel] else { continue }
            let toWorld = hw * piece.worldPose(of: surface.panel)
            let inner = surface.inset(into: panel, width: 0.3)
            let bevel = BevelNode(surface: surface, inner: inner, toWorld: toWorld, style: .bevel)
            node.addChildNode(bevel.root)
            let axe = design.blade == nil
            let title = axe ? (paths.count > 1 && i > 0 ? "Now the other bit" : "Sharpen the axe head")
                : (i == 0 ? "Sharpen the edge" : "Now the other edge")
            let text = axe ? "Rub the sanding block along the yellow guide." : "Rub the sanding block along the yellow guide, right out to the tip."
            step(n, title, text, tool: .sander, detail: paths.count > 1 ? "Edge \(i + 1) of \(paths.count)" : nil)
            let pts = bevel.path.points
            let lo = pts.reduce(V3(repeating: 1e9)) { V3(min($0.x, $1.x), min($0.y, $1.y), min($0.z, $1.z)) }
            let hi = pts.reduce(V3(repeating: -1e9)) { V3(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z)) }
            try await look(at: (lo + hi) / 2, size: V2(hi.x - lo.x + 4, hi.z - lo.z + 4.5), shot: .topDown, duration: 0.9)
            let mid = surface.points.count / 2
            let inward = toWorld.applyVector(inner[mid] - surface.points[mid]).unit
            try await TraceInteraction.sand(session: self, bevel: bevel, block: sander,
                                            normal: toWorld.applyVector(surface.normal), inward: inward,
                                            showHint: hintsOn && i == 0).run()
            success(axe ? "Bit sharpened" : "Edge sharpened", at: bevel.path.point(at: bevel.path.length / 2) + V3(0, 0.9, 0))
            reward(40, at: bevel.path.point(at: bevel.path.length / 2) + V3(0, 1.5, 0))
            tip = pts.last
        }
        let from = sander.pose, rest = engine.workspace.sanderRest
        tw.start(0.6, ease: .inOutCubic) { k in sander.setPose(from.lerp(rest, k)) }
        if let tip, design.blade != nil {
            try await glint(at: tip)
            success("Tip shaped — razor sharp!", at: tip + V3(0, 1.0, 0))
            try await tw.wait(0.4)
        }

        // Fullers: a groove carved down each face of the blade.
        let fullers = bp.fullerPaths
        let knife = engine.workspace.knife
        for (i, surface) in fullers.enumerated() {
            guard let piece = sheet.pieces[surface.piece], let node = piece.panelNodes[surface.panel] else { continue }
            let toWorld = hw * piece.worldPose(of: surface.panel)
            let groove = BevelNode(surface: surface, inner: surface.points, toWorld: toWorld, style: .groove)
            node.addChildNode(groove.root)
            step(n, "Carve the fuller", "Draw the craft knife along the red dashes.", tool: .knife, detail: "Groove \(i + 1) of \(fullers.count)")
            if i == 0 {
                let pts = groove.path.points
                let c = pts.reduce(V3(0, 0, 0), +) / Float(max(pts.count, 1))
                try await look(at: c, size: V2((design.blade?.length ?? 8) + 3, 6), shot: .topDown, duration: 0.8)
            }
            try await TraceInteraction.carve(session: self, groove: groove, knife: knife, showHint: hintsOn && i == 0).run()
            success("Fuller carved", at: groove.path.point(at: groove.path.length / 2) + V3(0, 0.9, 0))
            reward(30)
        }
        if !fullers.isEmpty {
            let kp = knife.pose, rest = engine.workspace.knifeRest
            tw.start(0.6, ease: .inOutCubic) { k in knife.setPose(kp.lerp(rest, k)) }
        }
    }

    /// A sparkle flashes on the freshly shaped tip.
    private func glint(at tip: V3) async throws {
        let g = Glint.make()
        engine.craftRoot.addChildNode(g)
        defer { g.removeFromParentNode() }
        engine.sound.play(.success)
        engine.particles.sparks(at: tip, count: 14)
        rig.glide(to: rig.framing(center: tip, size: V2(7, 5), view: .threeQuarter), duration: 0.8, tweener: tw)
        let rig = self.rig
        try await tw.tween(0.9, ease: .linear) { k in
            g.setPose(Pose(rot: rig.orbit.orientation * Quat(axis: V3(0, 0, 1), angle: k * 1.6), pos: tip + V3(0, 0.12, 0)))
            g.setUniformScale(max(0.001, sin(k * .pi) * 1.1))
        }
    }

    // MARK: Finale

    private func finale() async throws {
        say("Finished!", "Your cardboard \(weaponName) is ready.", tool: HUDTool.none, detail: nil)
        hud.stepIndex = design.stepCount + 1
        hud.showLegend = false
        let start = weaponRoot.pose
        let top = Pose(rot: start.rot, pos: start.pos + V3(0, 1.3, 0))
        let ext = bp.assembledBounds()
        let span = max(ext.max.x - ext.min.x, ext.max.z - ext.min.z)
        rig.glide(to: rig.framing(center: top.pos, size: V2(span + 2.5, max(6, span * 0.5)), view: .hero), duration: 1.2, tweener: tw)
        let root = weaponRoot
        try await tw.tween(0.55, ease: .outBack) { k in root.setPose(start.lerp(top, k)) }
        engine.particles.confetti(at: top.pos + V3(0, 0.5, 0), count: 90)
        engine.sound.play(.pop)
        rig.addShake(0.22)
        reward(project.reward, at: top.pos + V3(0, 1.8, 0))
        engine.profile.recordCompletion(project.id)

        // Slow turntable spin with a gentle bob.
        var angle: Float = 0
        spinID = engine.onFrame { [weak self] dt in
            guard let self else { return }
            angle += Float(dt) * 0.7
            let bob = V3(0, 0.12 * Float(sin(self.engine.time * 2)), 0)
            self.weaponRoot.setPose(Pose(rot: Quat(axis: up3, angle: angle) * top.rot, pos: top.pos + bob))
        }
        try await tw.wait(0.8)
        let icon = engine.icons.weaponIcon(design, stock: stock)
        hud.finish = FinishInfo(title: "\(design.name) crafted!",
                                subtitle: design.stages.contains(.sharpen) ? "Cut · Folded · Glued · Assembled · Sharpened"
                                    : "Cut · Folded · Glued · Assembled",
                                reward: engine.profile.coins - startCoins,
                                seconds: Int(engine.time - startTime),
                                perfectFolds: perfectFolds,
                                iconKey: icon,
                                project: project)
        let model = hud
        hud.consumeTap()
        try await tw.until { model.nextTapped }
        hud.consumeTap()
    }
}
