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

    init(engine: GameEngine, stock: CardboardStock) {
        bp = KnifeBlueprint(thickness: stock.thickness)
        super.init(engine: engine, project: .knife, stock: stock)
    }

    override func run() async throws {
        hud.reset(steps: project.steps)
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
    private func foldPanel(_ piece: PieceNode, _ panel: String, grab: V3, first: Bool) async throws {
        piece.highlight(panel, color: Palette.cardboardLight)
        let spec = FoldInteraction.Spec.panel(piece, panel, grab: grab)
        try await FoldInteraction(session: self, spec: spec, showHint: hintsOn && first).run()
        piece.highlight(panel, color: nil)
        piece.setCrease(panel, 1)
        piece.setFoldLine(panel, visible: false)
        success("Perfect fold", at: spec.handle(1) + V3(0, 0.7, 0))
    }

    private func stepGlueTab() async throws {
        step(3, "Glue the tab", "Run the glue along the highlighted tab.", tool: .glue)
        try await waitForNext()
    }

    private func stepCloseHandle() async throws {
        step(4, "Close the handle", "Fold the lid down onto the glued tab.", tool: .hand)
        try await waitForNext()
    }

    private func stepFoldBlade() async throws {
        step(5, "Fold the blade", "Crease the ridge and glue the tang.", tool: .hand)
        try await waitForNext()
    }

    private func stepAssemble() async throws {
        step(6, "Assemble the knife", "Slide the blade in and wrap the guard band.", tool: .hand)
        try await waitForNext("Finish")
    }
}
