import SceneKit
import UIKit

/// The knife build, step by step:
///   1 CUT    — cut the blade, handle and guard band out of the sheet
///   2 FOLD   — score and fold the handle walls, end cap and glue tab
///   3 GLUE   — glue the handle's tab
///   4 ALIGN  — close the lid onto the glued tab
///   5 FOLD   — fold the blade's ridge and glue its tang
///   6 ASSEMBLE — slide the blade in, wrap the guard band, finished!
@MainActor
final class KnifeSession: CraftSession {
    let bp: KnifeBlueprint
    private(set) var sheet: TemplateSheet!
    private var startTime: Double = 0
    private var startCoins = 0
    private var perfectFolds = 0
    /// Finished-knife nodes: `knifeRoot` sits at the knife's centre (spins in place),
    /// `assembly` holds the pieces in handle space.
    private let knifeRoot = SCNNode()
    private let assembly = SCNNode()
    /// Knife centre in handle space.
    private let knifeCentre = V3(-0.93, 0.64, 0)
    private var spinID: Int?

    init(engine: GameEngine, stock: CardboardStock) {
        bp = KnifeBlueprint(thickness: stock.thickness)
        super.init(engine: engine, project: .knife, stock: stock)
    }

    override func run() async throws {
        hud.reset(steps: project.steps)
        startTime = engine.time
        startCoins = engine.profile.coins
        try await placeTemplate()
        try await stepCut()
        try await stepFoldHandle()
        try await stepGlueTab()
        try await stepCloseHandle()
        try await stepFoldBlade()
        try await stepAssemble()
    }

    // MARK: Template

    private func placeTemplate() async throws {
        say("Fresh sheet", "The template is traced onto the cardboard.", tool: .none)
        sheet = TemplateSheet(template: bp.template, stock: stock)
        engine.craftRoot.childNodes.forEach { $0.removeFromParentNode() }
        engine.craftRoot.addChildNode(sheet.root)
        try await sheet.printTemplate(pencil: engine.workspace.pencil, tweener: tw)
    }

    // MARK: Steps (interactions are filled in feature by feature)

    private func stepCut() async throws {
        let order = ["blade", "handle", "guard"]
        let knife = engine.workspace.knife
        var firstCut = true
        for (i, id) in order.enumerated() {
            guard let def = bp.template.piece(id), let outline = sheet.outlineCuts[id] else { continue }
            let detail = "\(def.name) · \(i + 1) of \(order.count)"
            let inner = sheet.innerCuts[id] ?? []
            // Frame the piece so the line is big under the finger.
            let b = def.sheetBounds
            let center = ((b.min + b.max) / 2).onMat(0)
            let size = V2(max(b.max.x - b.min.x + 4, 10), max(b.max.y - b.min.y + 3, 6.5))
            glide(to: center, size: size, shot: .topDown, duration: 0.8)

            for (k, hole) in inner.enumerated() {
                step(1, "Punch the hole", "Trace the small red circle with the knife.", tool: .knife, detail: detail)
                try await TraceInteraction.cut(session: self, line: hole, knife: knife, showHint: hintsOn && firstCut).run()
                firstCut = false
                if let disc = sheet.holeDiscs[id]?[k] { popDisc(disc, world: hole.path.point(at: 0)) }
                reward(20, at: hole.path.point(at: 0))
            }
            step(1, "Cut the solid edge", "Follow the red line with the craft knife.", tool: .knife, detail: detail)
            try await TraceInteraction.cut(session: self, line: outline, knife: knife, showHint: hintsOn && firstCut).run()
            firstCut = false
            try await freePiece(id)
            reward(100, at: sheet.center(of: id) + V3(0, 0.6, 0))
        }
        // Tools down, scraps away.
        let from = knife.pose
        let rest = engine.workspace.knifeRest
        tw.start(0.6, ease: .inOutCubic) { k in knife.setPose(from.lerp(rest, k)) }
        try await clearWaste()
        say("All pieces cut out!", "Clean edges. Next you'll fold the handle into a box.", tool: .knife)
        try await waitForNext()
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
        try await tw.tween(0.9, ease: .inCubic) { k in
            let spin = Quat(axis: up3, angle: 0.35 * k)
            waste.setPose(Pose(rot: start.rot * spin, pos: start.pos + V3(-28 * k, 0.2 * k, 4 * k)))
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
        // Spread the pieces out on the mat: handle in the middle, blade above, band below.
        if let band = sheet.pieces["guard"] { try await slide(band, to: guardSpot, duration: 0.45) }
        if let handle = sheet.pieces["handle"], let blade = sheet.pieces["blade"] {
            let h0 = handle.pose, b0 = blade.pose
            let hs = handleSpot, bs = bladeSpot
            try await tw.tween(0.55, ease: .inOutCubic) { k in
                handle.pose = h0.lerp(hs, k)
                blade.pose = b0.lerp(bs, k)
            }
        }
    }

    private let handleSpot = Pose.translation(V3(-2.3, 0, 0.9))
    private let bladeSpot = Pose.translation(V3(1.2, 0, -5.9))
    private let guardSpot = Pose.translation(V3(4.6, 0, 4.4))

    private func slide(_ piece: PieceNode, to target: Pose, duration: Double) async throws {
        let start = piece.pose
        try await tw.tween(duration, ease: .inOutCubic) { k in
            let lift = V3(0, 0.25 * sin(k * .pi), 0)
            let p = start.lerp(target, k)
            piece.pose = Pose(rot: p.rot, pos: p.pos + lift)
        }
    }

    private var handle: PieceNode? { sheet.pieces["handle"] }

    /// Centre of the (folded) handle box in world space.
    private func handleCenter() -> V3 {
        (handle?.pose ?? .identity).apply(V3(bp.L / 2, 0.5, 0))
    }

    private func stepFoldHandle() async throws {
        guard let handle else { return }
        let t = stock.thickness
        step(2, "Score the fold lines", "Run the bone folder along each blue dashed line.", tool: .scorer)
        try await look(at: handle.pose.apply(V3(2.7, 0, -0.56)), size: V2(9.5, 8.2), shot: .topDown, duration: 0.8)
        let folder = engine.workspace.boneFolder
        let creases = ["HS1", "HS2", "HT", "GT", "EC"]
        for (i, id) in creases.enumerated() {
            hud.detail = "Crease \(i + 1) of \(creases.count)"
            try await scoreCrease(handle, id, folder: folder, first: i == 0)
        }
        let fp = folder.pose, rest = engine.workspace.folderRest
        tw.start(0.6) { k in folder.setPose(fp.lerp(rest, k)) }
        success("Creases scored!")

        step(2, "Fold the walls up", "Drag each flap up along the blue arrow.", tool: .hand)
        try await look(at: handleCenter(), size: V2(8, 6.5), shot: .threeQuarter, duration: 1.1)
        let flaps: [(String, V3)] = [
            ("HS1", V3(bp.L / 2, t, -bp.W / 2 - bp.H)),
            ("HS2", V3(bp.L / 2, t, bp.W / 2 + bp.H - t)),
            ("EC", V3(bp.L + bp.H, t, 0)),
        ]
        for (i, flap) in flaps.enumerated() {
            hud.detail = "Flap \(i + 1) of \(flaps.count)"
            try await foldPanel(handle, flap.0, grab: flap.1, first: i == 0)
        }
        say("Tuck in the glue tab", "Fold the little tab over, into the box.", tool: .hand)
        try await foldPanel(handle, "GT", grab: V3(bp.L / 2, t, bp.W / 2 + bp.H - t + bp.tab), first: false)
        say("The box is taking shape", "Walls up, tab tucked in. Time for glue.", tool: .hand)
        try await waitForNext()
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

    // MARK: Glue

    /// Lays a glue bead along `path` (flat piece space, on the face that points up).
    @discardableResult
    private func applyGlue(on piece: PieceNode, panel: String, path: [V3], normal: V3, first: Bool) async throws -> GlueBeadNode {
        let bead = GlueBeadNode(localPoints: path, localNormal: normal, toWorld: piece.worldPose(of: panel))
        piece.panelNodes[panel]?.addChildNode(bead.root)
        let bottle = engine.workspace.glue
        try await TraceInteraction.glue(session: self, bead: bead, bottle: bottle, showHint: hintsOn && first).run()
        bead.settle()
        success("Glue applied", at: bead.path.point(at: bead.path.length / 2) + V3(0, 0.8, 0))
        let from = bottle.pose, rest = engine.workspace.glueRest
        tw.start(0.6, ease: .inOutCubic) { k in bottle.setPose(from.lerp(rest, k)) }
        return bead
    }

    /// Brief mint glow along a seam when two surfaces lock together.
    private func flashSeam(_ points: [V3]) {
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

    private func stepGlueTab() async throws {
        guard let handle else { return }
        step(3, "Glue the tab", "Run the glue along the dotted guide on the tab.", tool: .glue)
        glide(to: handleCenter(), size: V2(6.8, 5.6), shot: .threeQuarter, duration: 0.8)
        handle.highlight("GT", color: Palette.cardboardLight)
        try await applyGlue(on: handle, panel: "GT", path: bp.handleGluePath, normal: V3(0, -1, 0), first: true)
        handle.highlight("GT", color: nil)
        say("Glue's on", "Close the lid onto the tab before it dries.", tool: .glue)
        try await waitForNext()
    }

    private func stepCloseHandle() async throws {
        guard let handle else { return }
        let t = stock.thickness
        step(4, "Close the handle", "Fold the lid over onto the glued tab.", tool: .hand)
        // The matching surface glows mint so it's obvious where the lid lands.
        handle.highlight("GT", color: Palette.mint)
        let lidEdge = V3(bp.L / 2, t, -bp.W / 2 - bp.H - bp.W - t)
        try await foldPanel(handle, "HT", grab: lidEdge, first: true, successText: "Tab aligned")
        handle.highlight("GT", color: nil)
        let seam = [0, bp.L].map { handle.world("HT", V3($0, t, -bp.W / 2 - bp.H - bp.W - t)) }
        flashSeam(seam)
        rig.addShake(0.12)
        reward(50, at: handleCenter() + V3(0, 1.2, 0))
        say("Handle closed!", "A sturdy little box. Now the blade.", tool: .hand)
        try await waitForNext()
    }

    // MARK: Blade

    private var blade: PieceNode? { sheet.pieces["blade"] }

    private func stepFoldBlade() async throws {
        guard let blade else { return }
        let t = stock.thickness
        let spot = blade.pose
        let mid = V3(-1.55, 0, 0)
        step(5, "Score the blade's spine", "Run the bone folder along the blue dashed line.", tool: .scorer)
        try await look(at: spot.apply(mid), size: V2(12.5, 5.5), shot: .topDown, duration: 0.9)
        let folder = engine.workspace.boneFolder
        try await scoreCrease(blade, "BL", folder: folder, first: false)
        let fp = folder.pose, rest = engine.workspace.folderRest
        tw.start(0.6) { k in folder.setPose(fp.lerp(rest, k)) }

        step(5, "Fold the blade", "Drag up to pinch a ridge along the spine.", tool: .hand)
        try await look(at: spot.apply(mid), size: V2(11, 5), shot: .threeQuarter, duration: 1.0)
        let bp = self.bp
        let outline = bp.blade.outline
        let ridge = V3(-2.6, t, 0), edge = V3(-2.6, 0, -bp.halfWidth)
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

        step(5, "Glue the tang", "Run the glue along the narrow end of the blade.", tool: .glue)
        glide(to: blade.pose.apply(V3(1.6, 0, 0)), size: V2(7, 4.5), shot: .threeQuarter, duration: 0.8)
        try await applyGlue(on: blade, panel: "BU", path: bp.tangGluePath, normal: V3(0, 1, 0), first: false)
        say("Blade ready", "Ridge folded, tang glued. Time to put it together!", tool: .hand)
        try await waitForNext()
    }

    // MARK: Assembly

    override func cleanup() {
        engine.removeFrameHandler(spinID)
        spinID = nil
    }

    private func stepAssemble() async throws {
        guard let handle, let blade, let band = sheet.pieces["guard"] else { return }
        let t = stock.thickness

        // 1. Blade into the handle.
        step(6, "Slide the blade in", "Drag the blade onto the glowing outline.", tool: .hand, detail: "Connect · 1 of 2")
        let hw = handle.pose
        let ready = hw * bp.bladeReady
        let seated = hw * bp.bladeSeated
        glide(to: hw.apply(V3(-1.8, 0.3, -1.6)), size: V2(15, 8.5), shot: .threeQuarter, duration: 1.0)
        let bladeGhost = blade.makeGhost(color: Palette.mint)
        bladeGhost.setPose(ready)
        engine.craftRoot.addChildNode(bladeGhost)
        let pulse = engine.onFrame { [weak self] _ in
            guard let self else { return }
            bladeGhost.opacity = CGFloat(0.65 + 0.35 * sin(self.engine.time * 4))
        }
        let bladeSpec = PlaceInteraction.Spec(
            current: { blade.pose },
            set: { blade.pose = $0 },
            target: ready,
            hoverY: ready.pos.y + 1.1,
            outline: { blade.footprint() },
            center: { blade.pose.apply(V3(-1.5, t, 0)) }
        )
        try await PlaceInteraction(session: self, spec: bladeSpec, showHint: hintsOn).run()
        engine.removeFrameHandler(pulse)
        bladeGhost.removeFromParentNode()
        try await tw.tween(0.5, ease: .inOutCubic) { k in blade.pose = ready.lerp(seated, k) }
        rig.addShake(0.15)
        flashSeam([hw.apply(V3(0.02, t, -bp.W / 2)), hw.apply(V3(0.02, bp.H + t, -bp.W / 2)),
                   hw.apply(V3(0.02, bp.H + t, bp.W / 2)), hw.apply(V3(0.02, t, bp.W / 2))])
        success("Tab aligned", at: hw.apply(V3(0, 1.6, 0)))
        reward(50, at: hw.apply(V3(0, 2.2, 0)))

        // 2. Pick the knife up so the band can wrap underneath.
        say("Blade locked in!", "Lift the knife — the guard band goes around the front.", tool: .hand, detail: nil)
        knifeRoot.name = "finishedKnife"
        assembly.name = "assembly"
        knifeRoot.setPose(hw * .translation(knifeCentre))
        assembly.setPose(.translation(knifeCentre * -1))
        knifeRoot.addChildNode(assembly)
        engine.craftRoot.addChildNode(knifeRoot)
        assembly.addChildNode(handle.root)
        handle.pose = .identity
        assembly.addChildNode(blade.root)
        blade.pose = bp.bladeSeated
        let ground = knifeRoot.pose
        let held = Pose(rot: ground.rot, pos: ground.pos + V3(0, 1.9, 0))
        try await tw.tween(0.7, ease: .outBack) { [knifeRoot] k in knifeRoot.setPose(ground.lerp(held, k)) }

        // 3. Glue the band.
        step(6, "Glue the guard band", "Glue the end of the band where it will overlap.", tool: .glue, detail: "Connect · 2 of 2")
        glide(to: band.pose.apply(V3(3.1, 0, 0.4)), size: V2(9, 5), shot: .threeQuarter, duration: 0.9)
        try await applyGlue(on: band, panel: "C0", path: bp.guardGluePath, normal: V3(0, 1, 0), first: false)

        // 4. Drop the band across the handle; it wraps itself around.
        step(6, "Wrap the guard band", "Drag the band onto the front of the handle.", tool: .hand, detail: "Connect · 2 of 2")
        let knifeWorld = held * .translation(knifeCentre * -1)
        let bandTarget = knifeWorld * bp.guardOnHandle
        glide(to: mix3(band.pose.pos, bandTarget.pos, 0.5), size: V2(13, 8), shot: .threeQuarter, duration: 1.0)
        let bandGhost = band.makeGhost(color: Palette.mint)
        bandGhost.setPose(bandTarget)
        engine.craftRoot.addChildNode(bandGhost)
        let bandSpec = PlaceInteraction.Spec(
            current: { band.pose },
            set: { band.pose = $0 },
            target: bandTarget,
            hoverY: bandTarget.pos.y + 0.8,
            outline: { band.footprint() },
            center: { band.pose.apply(V3(3.1, t, 0.4)) },
            carryRotation: bandTarget.rot
        )
        try await PlaceInteraction(session: self, spec: bandSpec, showHint: hintsOn).run()
        bandGhost.removeFromParentNode()
        glide(to: held.pos, size: V2(9, 6), shot: .threeQuarter, duration: 0.8)
        for id in ["C1", "C2", "C3", "C4"] {
            try await tw.tween(0.24, ease: .inOutCubic) { k in band.setFold(id, progress: k) }
            if let h = band.def.panel(id)?.hinge {
                engine.particles.sparks(at: band.world(id, h.midpoint.onMat(0)), count: 5)
            }
        }
        assembly.addChildNode(band.root)
        band.pose = bp.guardOnHandle
        flashSeam([knifeWorld.apply(V3(bp.bandInset, bp.H + 3 * t, -bp.W / 2)),
                   knifeWorld.apply(V3(bp.bandInset + bp.bandWidth, bp.H + 3 * t, -bp.W / 2))])
        rig.addShake(0.12)
        success("Tab aligned", at: held.pos + V3(0, 1.3, 0))
        reward(50, at: held.pos + V3(0, 2.0, 0))

        try await finale()
    }

    // MARK: Finale

    private func finale() async throws {
        step(6, "Finished!", "Your cardboard knife is ready.", tool: .none)
        hud.showLegend = false
        let start = knifeRoot.pose
        let top = Pose(rot: start.rot, pos: start.pos + V3(0, 1.3, 0))
        rig.glide(to: rig.framing(center: top.pos, size: V2(12.5, 6), view: .hero), duration: 1.2, tweener: tw)
        try await tw.tween(0.55, ease: .outBack) { [knifeRoot] k in knifeRoot.setPose(start.lerp(top, k)) }
        engine.particles.confetti(at: top.pos + V3(0, 0.5, 0), count: 90)
        rig.addShake(0.22)
        reward(project.reward, at: top.pos + V3(0, 1.8, 0))
        engine.profile.recordCompletion(project.id)

        // Slow turntable spin with a gentle bob.
        var angle: Float = 0
        spinID = engine.onFrame { [weak self] dt in
            guard let self else { return }
            angle += Float(dt) * 0.7
            let bob = V3(0, 0.12 * Float(sin(self.engine.time * 2)), 0)
            self.knifeRoot.setPose(Pose(rot: Quat(axis: up3, angle: angle) * top.rot, pos: top.pos + bob))
        }
        try await tw.wait(0.8)
        hud.finish = FinishInfo(title: "Knife crafted!",
                                subtitle: "Cut · Scored · Folded · Glued · Assembled",
                                reward: engine.profile.coins - startCoins,
                                seconds: Int(engine.time - startTime),
                                perfectFolds: perfectFolds,
                                iconKey: "project.knife")
        let model = hud
        hud.consumeTap()
        try await tw.until { model.nextTapped }
        hud.consumeTap()
    }
}
