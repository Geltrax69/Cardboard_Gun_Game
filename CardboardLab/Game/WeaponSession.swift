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
final class WeaponSession: BuildSession {
    let bp: WeaponBlueprint
    var design: WeaponDesign { bp.design }

    init(engine: GameEngine, project: ProjectInfo, design: WeaponDesign, stock: CardboardStock) {
        bp = WeaponBlueprint(design: design, thickness: stock.thickness)
        super.init(engine: engine, project: project, stock: stock)
    }

    override var buildBounds: (min: V3, max: V3) { bp.assembledBounds() }

    override var connectCount: Int {
        clipIDs.count + (bp.hasBlade ? 1 : 0) + design.wraps.count
    }

    override func run() async throws {
        beginBuild(steps: design.stepCount)
        try await placeTemplate(bp.template, name: weaponName)
        try await stageCut()
        try await stageHandle()
        if bp.hasBlade { try await stageBlade() }
        if design.stages.contains(.fittings) { try await stageFittings() }
        try await stageAssemble()
        if design.stages.contains(.sharpen) { try await stageSharpen() }
        try await celebrate(name: design.name,
                            subtitle: design.stages.contains(.sharpen) ? "Cut · Folded · Glued · Assembled · Sharpened"
                                : "Cut · Folded · Glued · Assembled",
                            iconKey: engine.icons.weaponIcon(design, stock: stock))
    }

    /// HUD step number of a stage.
    private func number(_ s: WeaponStage) -> Int { (design.stages.firstIndex(of: s) ?? 0) + 1 }

    private var handleName: String { design.kind == .axe ? "Shaft" : "Handle" }
    private var weaponName: String { design.name.lowercased() }

    // MARK: Cut

    private var cutOrder: [String] {
        ["blade", "handle", "guard", "end"].filter { bp.piece($0) != nil } + design.wraps.indices.map { "wrap\($0)" }
    }

    private func stageCut() async throws {
        // Matching grip bands after the first are cut in one quick pass.
        try await cutPieces(cutOrder, n: number(.cut), quick: { $0.hasPrefix("wrap") && $0 != "wrap0" },
                            reward: { $0 == "blade" ? 100 : 60 })
        say("All pieces cut out!", "Clean edges. Next you'll fold the \(handleName.lowercased()) into a box.", tool: .knife)
        try await waitForNext()
    }

    // MARK: Handle

    private var handle: PieceNode? { sheet.pieces["handle"] }

    private func stageHandle() async throws {
        guard let handle else { return }
        try await buildBox(handle, W: bp.W, H: bp.H, L: bp.L, front: false, glue: bp.handleGlue, n: number(.handle), quick: false)
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
    private func stageAssemble() async throws {
        guard let handle else { return }
        let n = number(.assemble)
        let t = stock.thickness

        // 1. Pick the handle up (fittings wrap underneath it).
        step(n, "Pick it up", "The \(handleName.lowercased()) lifts off the mat so the parts can go on.", tool: .hand)
        try await liftBody(handle, centre: bp.assembledCentre)

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
            glide(to: mix3(band.pose.pos, bodyWorld.apply(V3(bp.L / 2, 0, 0)), 0.5), size: V2(bp.L + 9, 9), shot: .threeQuarter, duration: 0.7)
            try await applyGlue(on: band, bp.wrapGlue("wrap\(i)"), first: false, auto: true)
        } else {
            step(n, "Glue the \(name)", "Glue the end of the band where it will overlap.", tool: .glue, detail: detail)
            glide(to: band.pose.apply(bandCentre), size: V2(9, 5), shot: .threeQuarter, duration: 0.9)
            try await applyGlue(on: band, bp.wrapGlue("wrap\(i)"), first: false)
        }

        let target = bodyWorld * bp.wrapMount(i)
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
        let hw = bodyWorld
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
        let hw = bodyWorld
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
}
