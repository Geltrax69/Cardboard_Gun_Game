import SceneKit
import UIKit

/// Shared moves for every build script (weapons, guns): printing the template, cutting
/// pieces out, scoring, folding and gluing boxes and tabs, lifting the body off the mat,
/// mounting parts onto it and the finished-object celebration. Subclasses write the
/// stages as straight-line async code on top of these.
@MainActor
class BuildSession: CraftSession {
    private(set) var sheet: TemplateSheet!
    var startTime: Double = 0
    var startCoins = 0
    var perfectFolds = 0
    /// Finished build: `finishedRoot` sits at its centre (spins in place), `assembly`
    /// holds the pieces in the body's frame.
    let finishedRoot = SCNNode()
    let assembly = SCNNode()
    private var spinID: Int?
    var connectIndex = 0

    /// Bounds of the finished build in the body's frame (subclasses provide).
    var buildBounds: (min: V3, max: V3) { (V3(-5, 0, -1), V3(5, 2, 1)) }
    /// Number of parts mounted in the assembly stage (for "Connect · 2 of 5").
    var connectCount: Int { 0 }

    override func cleanup() {
        engine.removeFrameHandler(spinID)
        spinID = nil
    }

    func beginBuild(steps: Int) {
        hud.reset(steps: steps)
        startTime = engine.time
        startCoins = engine.profile.coins
    }

    // MARK: Template

    func placeTemplate(_ template: CraftTemplate, name: String) async throws {
        say("Fresh sheet", "The \(name) template is traced onto the cardboard.", tool: HUDTool.none)
        sheet = TemplateSheet(template: template, stock: stock)
        engine.craftRoot.childNodes.forEach { $0.removeFromParentNode() }
        engine.craftRoot.addChildNode(sheet.root)
        try await sheet.printTemplate(pencil: engine.workspace.pencil, tweener: tw)
    }

    // MARK: Cut

    /// Cuts the pieces in `order` (holes first), lifting each one out. Pieces for which
    /// `quick` is true are matching repeats the knife cuts by itself.
    func cutPieces(_ order: [String], n: Int, quick: (String) -> Bool = { _ in false },
                   reward pieceReward: (String) -> Int = { _ in 60 }) async throws {
        let knife = engine.workspace.knife
        var firstCut = true
        for (i, id) in order.enumerated() {
            guard let def = sheet.template.piece(id), let outline = sheet.outlineCuts[id] else { continue }
            let detail = "\(def.name) · \(i + 1) of \(order.count)"
            let inner = sheet.innerCuts[id] ?? []
            // Frame the piece so the line is big under the finger.
            let b = def.sheetBounds
            let center = ((b.min + b.max) / 2).onMat(0)
            let size = V2(max(b.max.x - b.min.x + 4, 10), max(b.max.y - b.min.y + 3, 6.5))
            glide(to: center, size: size, shot: .topDown, duration: 0.8)

            if quick(id) {
                step(n, "Same again", "Matching piece — the knife runs round it in one go.", tool: .knife, detail: detail)
                try await autoCut(outline, knife: knife)
                try await freePiece(id)
                reward(30, at: sheet.center(of: id) + V3(0, 0.6, 0))
                continue
            }
            for (k, hole) in inner.enumerated() {
                step(n, "Punch the hole", "Trace the small red outline inside the piece.", tool: .knife, detail: detail)
                try await TraceInteraction.cut(session: self, line: hole, knife: knife, showHint: hintsOn && firstCut).run()
                firstCut = false
                if let disc = sheet.holeDiscs[id]?[k] { popDisc(disc, world: hole.path.point(at: 0)) }
                reward(20, at: hole.path.point(at: 0))
            }
            step(n, "Cut out the \(def.name.lowercased())", "Follow the solid red line with the craft knife.", tool: .knife, detail: detail)
            try await TraceInteraction.cut(session: self, line: outline, knife: knife, showHint: hintsOn && firstCut).run()
            firstCut = false
            try await freePiece(id)
            reward(pieceReward(id), at: sheet.center(of: id) + V3(0, 0.6, 0))
        }
        // Tools down, scraps away.
        let from = knife.pose
        let rest = engine.workspace.knifeRest
        tw.start(0.6, ease: .inOutCubic) { k in knife.setPose(from.lerp(rest, k)) }
        try await clearWaste()
    }

    /// The knife runs round a cut line by itself.
    func autoCut(_ line: CutLineNode, knife: SCNNode) async throws {
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
    func freePiece(_ id: String) async throws {
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
    func popDisc(_ disc: SCNNode, world: V3) {
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
    func clearWaste() async throws {
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
        glide(to: V3(0, 0, 0), size: sheet.template.sheetSize + V2(2.5, 2.2), shot: .topDown, duration: 0.9)
    }

    // MARK: Shared moves

    /// Centre and size of a piece's flat footprint, for framing.
    func frame(_ piece: PieceNode, pad: V2 = V2(3.2, 2.8), min: V2 = V2(7, 5.5)) -> (center: V3, size: V2) {
        let b = Poly.bounds(piece.def.outline)
        let size = b.max - b.min + pad
        return (piece.pose.apply(((b.min + b.max) / 2).onMat(0)), V2(Swift.max(size.x, min.x), Swift.max(size.y, min.y)))
    }

    /// Scores several hinges in turn with the bone folder, then puts it back.
    func scoreCreases(_ piece: PieceNode, _ panels: [String], hint: Bool) async throws {
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
    func scoreCrease(_ piece: PieceNode, _ panel: String, folder: SCNNode, first: Bool) async throws {
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
    func foldPanel(_ piece: PieceNode, _ panel: String, grab: V3, first: Bool,
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
    func applyGlue(on piece: PieceNode, _ surface: SurfacePath, first: Bool, auto: Bool = false) async throws -> GlueBeadNode {
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
    func flashSeam(_ points: [V3]) {
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

    // MARK: Boxes

    /// Centre of a (folded) box piece in world space.
    func boxCenter(_ piece: PieceNode, L: Float) -> V3 {
        piece.pose.apply(V3(L / 2, 0.5, 0))
    }

    /// Score, fold and glue a box net, then close its lid onto the glued tab. The first
    /// box of a build goes crease by crease; `quick` boxes are scored by the bone folder
    /// on its own and fold up with one drag.
    func buildBox(_ piece: PieceNode, W: Float, H: Float, L: Float, front: Bool, glue: SurfacePath, n: Int,
                  quick: Bool, detail: String? = nil) async throws {
        let t = stock.thickness
        let name = piece.def.name.lowercased()
        let f = frame(piece)
        if quick {
            step(n, "Score the \(name)", "Same creases as before — the bone folder runs them for you.", tool: .scorer, detail: detail)
            try await look(at: f.center, size: f.size, shot: .topDown, duration: 0.7)
            try await autoScore(piece, BoxNet.creases(front: front))
            step(n, "Fold the \(name) up", "Drag the side wall up — every wall folds with it.", tool: .hand, detail: detail)
            try await look(at: boxCenter(piece, L: L), size: V2(max(7, L + 3.4), 6.2), shot: .threeQuarter, duration: 0.8)
            try await foldAllWalls(piece, W: W, H: H, L: L, front: front)
        } else {
            step(n, "Score the fold lines", "Run the bone folder along each blue dashed line.", tool: .scorer, detail: detail)
            try await look(at: f.center, size: f.size, shot: .topDown, duration: 0.8)
            try await scoreCreases(piece, BoxNet.creases(front: front), hint: true)

            step(n, "Fold the walls up", "Drag each flap up along the blue arrow.", tool: .hand, detail: detail)
            try await look(at: boxCenter(piece, L: L), size: V2(max(8, L + 3.6), 6.5), shot: .threeQuarter, duration: 1.1)
            showRotateTip()
            var flaps: [(String, V3)] = [
                ("HS1", V3(L / 2, t, -W / 2 - H)),
                ("HS2", V3(L / 2, t, W / 2 + H - t)),
                ("EC", V3(L + H, t, 0)),
            ]
            if front { flaps.append(("FC", V3(-H, t, 0))) }
            for (i, flap) in flaps.enumerated() {
                hud.detail = "Flap \(i + 1) of \(flaps.count)"
                try await foldPanel(piece, flap.0, grab: flap.1, first: i == 0)
            }
            say("Tuck in the glue tab", "Fold the little tab over, into the box.", tool: .hand, detail: detail)
            try await foldPanel(piece, "GT", grab: V3(L / 2, t, W / 2 + H - t + BoxNet.tabDepth), first: false)
        }

        step(n, "Glue the tab", "Run the glue along the dotted guide on the tab.", tool: .glue, detail: detail)
        glide(to: boxCenter(piece, L: L), size: V2(max(6.8, L + 2.4), 5.6), shot: .threeQuarter, duration: 0.8)
        piece.highlight("GT", color: Palette.cardboardLight)
        try await applyGlue(on: piece, glue, first: !quick)
        piece.highlight("GT", color: nil)

        step(n, "Close the \(name)", "Fold the lid over onto the glued tab.", tool: .hand, detail: detail)
        // The matching surface glows mint so it's obvious where the lid lands.
        piece.highlight("GT", color: Palette.mint)
        let lidEdge = V3(L / 2, t, -W / 2 - H - W - t)
        try await foldPanel(piece, "HT", grab: lidEdge, first: !quick, successText: "Tab aligned")
        piece.highlight("GT", color: nil)
        flashSeam([0, L].map { piece.world("HT", V3($0, t, -W / 2 - H - W - t)) })
        rig.addShake(0.12)
        reward(50, at: boxCenter(piece, L: L) + V3(0, 1.2, 0))
    }

    /// The bone folder runs along each crease by itself.
    func autoScore(_ piece: PieceNode, _ panels: [String]) async throws {
        let folder = engine.workspace.boneFolder
        let raise = radians(30)
        for id in panels {
            guard let def = piece.def.panel(id), let h = def.hinge, let parent = def.parent else { continue }
            let wp = piece.worldPose(of: parent)
            let y = stock.thickness + 0.012
            let a = wp.apply(h.a.onMat(y)), b = wp.apply(h.b.onMat(y))
            let tangent = (b - a).unit
            let from = folder.pose
            let start = TraceInteraction.penPose(tip: a, tangent: tangent, raise: raise)
            try await tw.tween(0.16, ease: .inOutCubic) { k in folder.setPose(from.lerp(start, k)) }
            engine.sound.play(.score, volume: 0.5)
            try await tw.tween(0.26, ease: .inOutSine) { k in
                folder.setPose(TraceInteraction.penPose(tip: mix3(a, b, k), tangent: tangent, raise: raise))
                piece.setCrease(id, 0.55 * k)
            }
        }
        let fp = folder.pose, rest = engine.workspace.folderRest
        tw.start(0.6) { k in folder.setPose(fp.lerp(rest, k)) }
        success("Creases scored!")
    }

    /// One drag on the near wall folds every wall, the caps and the tab together.
    func foldAllWalls(_ piece: PieceNode, W: Float, H: Float, L: Float, front: Bool) async throws {
        let t = stock.thickness
        let flaps = BoxNet.walls(front: front) + ["GT"]
        let grab = V3(L / 2, t, W / 2 + H - t)
        let wall = piece.def.panel("HS2")
        func pose(_ p: Float) -> Pose {
            var rig = piece.rig
            rig.setFolded(flaps, progress: p)
            return piece.pose * rig.pose(of: "HS2")
        }
        let spec = FoldInteraction.Spec(
            handle: { pose($0).apply(grab) },
            pivot: { _ in piece.pose.apply(V3(L / 2, t, W / 2)) },
            outline: { p in (wall?.outline ?? []).map { pose(p).apply($0.onMat(t)) } },
            apply: { p in for id in flaps { piece.setFold(id, progress: p) } }
        )
        for id in flaps { piece.highlight(id, color: Palette.cardboardLight) }
        try await FoldInteraction(session: self, spec: spec, showHint: hintsOn).run()
        for id in flaps {
            piece.highlight(id, color: nil)
            piece.setCrease(id, 1)
            piece.setFoldLine(id, visible: false)
        }
        perfectFolds += 1
        success("Perfect fold", at: spec.handle(1) + V3(0, 0.7, 0))
    }

    // MARK: Assembly

    /// Body frame in world space while the build is held up.
    var bodyWorld: Pose { finishedRoot.pose * assembly.pose }

    func nextConnect() -> String {
        connectIndex += 1
        return "Connect · \(connectIndex) of \(connectCount)"
    }

    /// Picks the body piece up off the mat (parts wrap or hang underneath it), high
    /// enough to clear the folded parts still lying there, and makes it the root of the
    /// finished build. `centre` is the build's centre in the body frame.
    func liftBody(_ body: PieceNode, centre: V3) async throws {
        connectIndex = 0
        let ext = buildBounds
        let half = (ext.max - ext.min) / 2
        let tallest = sheet.pieces.values.filter { $0 !== body }.map { topY($0) }.max() ?? 0
        // Parts hang below the body; keep them clear of the mat too.
        let liftY = max(1.9, tallest + 0.7, -ext.min.y + 0.6)
        let ground = body.pose * Pose.translation(centre)
        var p = ground.pos
        p.x = clampf(p.x, -14 + half.x, max(-14 + half.x, 14 - half.x))
        p.z = clampf(p.z, -9.5 + half.z, max(-9.5 + half.z, 9.5 - half.z))
        p.y = liftY + centre.y
        let held = Pose(rot: ground.rot, pos: p)
        finishedRoot.name = "finished"
        assembly.name = "assembly"
        finishedRoot.setPose(ground)
        assembly.setPose(.translation(centre * -1))
        finishedRoot.addChildNode(assembly)
        engine.craftRoot.addChildNode(finishedRoot)
        assembly.addChildNode(body.root)
        body.pose = .identity
        glide(to: held.pos, size: V2(2 * half.x + 4, 2 * half.z + 7), shot: .threeQuarter, duration: 1.0)
        let root = finishedRoot
        try await tw.tween(0.8, ease: .outBack) { k in root.setPose(ground.lerp(held, k)) }
    }

    // MARK: Finale

    /// The finished build rises, spins and shows the completion card.
    func celebrate(name: String, subtitle: String, iconKey: String) async throws {
        say("Finished!", "Your cardboard \(name.lowercased()) is ready.", tool: HUDTool.none, detail: nil)
        hud.stepIndex = hud.stepCount + 1
        hud.showLegend = false
        let start = finishedRoot.pose
        let top = Pose(rot: start.rot, pos: start.pos + V3(0, 1.3, 0))
        let ext = buildBounds
        let span = max(ext.max.x - ext.min.x, ext.max.z - ext.min.z, ext.max.y - ext.min.y)
        rig.glide(to: rig.framing(center: top.pos, size: V2(span + 2.5, max(6, span * 0.55)), view: .hero), duration: 1.2, tweener: tw)
        let root = finishedRoot
        try await tw.tween(0.55, ease: .outBack) { k in root.setPose(start.lerp(top, k)) }
        engine.particles.confetti(at: top.pos + V3(0, 0.5, 0), count: 90)
        engine.sound.play(.pop)
        rig.addShake(0.22)
        reward(project.reward, at: top.pos + V3(0, 1.8, 0))
        let result = engine.profile.recordCompletion(project)
        engine.toast("+\(result.xp) XP", .info, at: top.pos + V3(0, 2.6, 0), life: 1.6)

        // Slow turntable spin with a gentle bob.
        var angle: Float = 0
        spinID = engine.onFrame { [weak self] dt in
            guard let self else { return }
            angle += Float(dt) * 0.7
            let bob = V3(0, 0.12 * Float(sin(self.engine.time * 2)), 0)
            self.finishedRoot.setPose(Pose(rot: Quat(axis: up3, angle: angle) * top.rot, pos: top.pos + bob))
        }
        try await tw.wait(0.8)
        var unlocked: [String] = []
        if result.leveledUp {
            unlocked = ProjectInfo.campaign.filter { $0.level > result.levelBefore && $0.level <= result.levelAfter }.map { $0.name }
            engine.sound.play(.levelUp)
            engine.particles.confetti(at: top.pos + V3(0, 1.5, 0), count: 60, power: 9)
            engine.toast("LEVEL \(result.levelAfter)!", .reward, life: 2.2)
            try await tw.wait(0.5)
        }
        hud.finish = FinishInfo(title: "\(name) crafted!",
                                subtitle: subtitle,
                                reward: engine.profile.coins - startCoins,
                                seconds: Int(engine.time - startTime),
                                perfectFolds: perfectFolds,
                                iconKey: iconKey,
                                project: project,
                                xp: result.xp,
                                levelUp: result.leveledUp ? result.levelAfter : nil,
                                unlocked: unlocked)
        let model = hud
        hud.consumeTap()
        try await tw.until { model.nextTapped }
        hud.consumeTap()
    }

    /// Highest point of a piece lying on the mat.
    func topY(_ piece: PieceNode) -> Float {
        piece.rig.foldedCorners().map { piece.pose.apply($0).y }.max() ?? 0
    }

    /// Carry a piece to its glowing ready pose next to the body, then slide it home and
    /// fix it into the assembly.
    func mount(_ piece: PieceNode, ready: Pose, seat: Pose, grabLocal: V3, seam: [V3],
               whileSliding: ((Float) -> Void)? = nil) async throws {
        let hw = bodyWorld
        let readyW = hw * ready, seatW = hw * seat
        let ext = buildBounds
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
        try await tw.tween(0.45, ease: .inOutCubic) { k in
            piece.pose = readyW.lerp(seatW, k)
            whileSliding?(k)
        }
        engine.sound.play(.snap)
        rig.addShake(0.15)
        assembly.addChildNode(piece.root)
        piece.pose = seat
        flashSeam(seam.map { hw.apply($0) })
        success("Locked in", at: seatW.pos + V3(0, 1.4, 0))
        reward(50, at: seatW.pos + V3(0, 2.0, 0))
    }

    /// A sparkle flashes on the freshly shaped tip.
    func glint(at tip: V3) async throws {
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
}
