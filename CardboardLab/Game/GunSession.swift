import SceneKit
import UIKit

/// Builds any gun from its `GunBlueprint`:
///   CUT       — cut every box net and fin out of the sheet, punch the holes
///   BODY      — score, fold, glue and close the slide / frame / receiver crease by crease
///   PARTS     — the other boxes fold up with one drag each; fins get their tabs glued
///   ASSEMBLE  — barrel, stock, grip, magazine, trigger guard, scope, hammer and sights go on
///   DETAILS   — draw the ejection port, serrations and grip texture with a marker
@MainActor
final class GunSession: BuildSession {
    let bp: GunBlueprint

    private enum Stage: Int { case cut = 1, body, parts, assemble, details }
    private static let stepCount = 5

    init(engine: GameEngine, project: ProjectInfo, kind: GunKind, stock: CardboardStock) {
        bp = GunBlueprint(kind: kind, thickness: stock.thickness)
        super.init(engine: engine, project: project, stock: stock)
    }

    override var buildBounds: (min: V3, max: V3) { bp.assembledBounds() }
    override var connectCount: Int { bp.parts.count - 1 }

    private var gunName: String { bp.name.lowercased() }

    override func run() async throws {
        beginBuild(steps: GunSession.stepCount)
        try await placeTemplate(bp.template, name: gunName)
        try await stageCut()
        try await stageBody()
        try await stageParts()
        try await stageAssemble()
        try await stageDetails()
        try await celebrate(name: bp.name, subtitle: "Cut · Folded · Glued · Assembled · Detailed",
                            iconKey: "gun.\(bp.kind.rawValue)")
    }

    // MARK: Cut

    private func stageCut() async throws {
        try await cutPieces(bp.parts.map { $0.id }, n: Stage.cut.rawValue, reward: { [bp] id in id == bp.body.id ? 100 : 50 })
        say("All pieces cut out!", "Next: fold the \(bp.body.name.lowercased()) into a box.", tool: .knife)
        try await waitForNext()
    }

    // MARK: Body

    private func stageBody() async throws {
        let part = bp.body
        guard let piece = sheet.pieces[part.id], let (W, H, L, front) = part.boxSize, let glue = bp.glue(part.id) else { return }
        try await buildBox(piece, W: W, H: H, L: L, front: front, glue: glue, n: Stage.body.rawValue, quick: false)
        say("\(part.name) closed!", "The core of the \(gunName). Now the other parts — they go faster.", tool: .hand)
        try await waitForNext()
    }

    // MARK: Parts

    private func stageParts() async throws {
        let n = Stage.parts.rawValue
        let rest = bp.parts.dropFirst()
        var finIndex = 0
        for (i, part) in rest.enumerated() {
            guard let piece = sheet.pieces[part.id], let glue = bp.glue(part.id) else { continue }
            let detail = "\(part.name) · \(i + 1) of \(rest.count)"
            if let (W, H, L, front) = part.boxSize {
                try await buildBox(piece, W: W, H: H, L: L, front: front, glue: glue, n: n, quick: true, detail: detail)
            } else {
                try await prepareFin(piece, glue: glue, n: n, quick: finIndex > 0, detail: detail)
                finIndex += 1
            }
        }
        say("Parts ready", "Everything is folded and glued. Time to put the \(gunName) together!", tool: .hand, detail: nil)
        try await waitForNext()
    }

    /// Scores a fin's tab crease and glues the tab while the fin lies flat (it folds
    /// over when the fin goes on). After the first fin this happens by itself.
    private func prepareFin(_ piece: PieceNode, glue: SurfacePath, n: Int, quick: Bool, detail: String) async throws {
        let f = frame(piece, min: V2(6, 4.5))
        let name = piece.def.name.lowercased()
        if quick {
            say("Same again", "The \(name)'s tab is scored and glued for you.", tool: .glue, detail: detail)
            glide(to: f.center, size: f.size, shot: .topDown, duration: 0.6)
            try await autoScore(piece, ["FT"])
            try await applyGlue(on: piece, glue, first: false, auto: true)
            return
        }
        step(n, "Score the \(name)'s tab", "Run the bone folder along the blue dashed line.", tool: .scorer, detail: detail)
        try await look(at: f.center, size: f.size, shot: .topDown, duration: 0.8)
        try await scoreCreases(piece, ["FT"], hint: false)
        step(n, "Glue the tab", "Run the glue along the tab — it folds over when the \(name) goes on.", tool: .glue, detail: detail)
        piece.highlight("FT", color: Palette.cardboardLight)
        try await applyGlue(on: piece, glue, first: false)
        piece.highlight("FT", color: nil)
    }

    // MARK: Assembly

    /// Order the parts go on: through-parts first (barrel), then the rest.
    private var assemblyOrder: [GunPart] {
        let rest = Array(bp.parts.dropFirst())
        let firstIDs = ["barrel", "stock"]
        return rest.filter { firstIDs.contains($0.id) } + rest.filter { !firstIDs.contains($0.id) }
    }

    private func stageAssemble() async throws {
        guard let body = sheet.pieces[bp.body.id] else { return }
        let n = Stage.assemble.rawValue
        let t = stock.thickness
        step(n, "Pick it up", "The \(bp.body.name.lowercased()) lifts off the mat so the parts can go on.", tool: .hand)
        try await liftBody(body, centre: bp.assembledCentre)

        for part in assemblyOrder {
            guard let piece = sheet.pieces[part.id] else { continue }
            let (title, text) = mountText(part)
            step(n, title, text, tool: .hand, detail: nextConnect())
            var grab = V3(0, t, 0)
            var seam: [V3] = []
            var sliding: ((Float) -> Void)? = nil
            if let (W, H, L, front) = part.boxSize {
                grab = V3(L / 2, (H + 2 * t) / 2, 0)
                // Glow round the end that meets the body.
                let x: Float = front ? -t : 0
                seam = [V3(x, 0, -W / 2 - t), V3(x, H + 2 * t, -W / 2 - t), V3(x, H + 2 * t, W / 2 + t), V3(x, 0, W / 2 + t)]
                    .map { part.mount.apply($0) }
                if part.id == "barrel" {
                    // The barrel glows where it enters the receiver's front.
                    let y0 = part.mount.pos.y, y1 = y0 + H + 2 * t, z = W / 2 + t, x = -t - 0.03
                    seam = [V3(x, y0, -z), V3(x, y1, -z), V3(x, y1, z), V3(x, y0, z)]
                }
            } else if let def = piece.def.panel("F0"), let tab = piece.def.panel("FT") {
                let c = Poly.centroid(def.outline)
                grab = V3(c.x, t / 2, c.y)
                seam = [tab.outline[0], tab.outline[1]].map { part.mount.apply($0.onMat(0)) }
                // The glued tab folds over as the fin slides home.
                sliding = { k in piece.setFold("FT", progress: k) }
            }
            try await mount(piece, ready: bp.ready(part.id), seat: part.mount, grabLocal: grab, seam: seam, whileSliding: sliding)
            piece.setCrease("FT", 1)
            // Glue squeezes out of the joint.
            for p in seam { engine.particles.droplet(at: bodyWorld.apply(p)) }
        }
        say("\(bp.name) assembled!", "Now the finishing touch: a few marker details.", tool: .hand, detail: nil)
        try await waitForNext()
    }

    private func mountText(_ part: GunPart) -> (String, String) {
        let body = bp.body.name.lowercased()
        switch part.id {
        case "barrel": return ("Slide the barrel in", "Push it through the square hole in the \(body).")
        case "stock": return ("Fit the stock", "Drag the stock onto the back of the \(body).")
        case "grip": return ("Attach the grip", "Drag the grip onto the glowing outline underneath.")
        case "magazine": return ("Load the magazine", "Drag the magazine into place in front of the trigger.")
        case "guard": return ("Fit the trigger guard", "Drag it under the \(body) — the tab folds over and sticks.")
        case "scope": return ("Mount the scope", "Drag the scope onto the top of the \(body).")
        case "hammer": return ("Fit the hammer", "Drag it onto the back of the \(body) — the tab folds over and sticks.")
        default: return ("Add the \(part.name.lowercased())", "Drag it onto the glowing outline on top.")
        }
    }

    // MARK: Details

    private func stageDetails() async throws {
        let n = Stage.details.rawValue
        let marker = engine.workspace.marker
        let hw = bodyWorld
        for (i, detail) in bp.details.enumerated() {
            let surface = detail.path
            guard let piece = sheet.pieces[surface.piece], let node = piece.panelNodes[surface.panel] else { continue }
            let toWorld = hw * piece.worldPose(of: surface.panel)
            let ink = BevelNode(surface: surface, inner: surface.points, toWorld: toWorld, style: .ink)
            node.addChildNode(ink.root)
            step(n, detail.name, "Draw along the yellow dots with the marker.", tool: .marker,
                 detail: "Detail \(i + 1) of \(bp.details.count)")
            let pts = ink.path.points
            let lo = pts.reduce(V3(repeating: 1e9)) { V3(min($0.x, $1.x), min($0.y, $1.y), min($0.z, $1.z)) }
            let hi = pts.reduce(V3(repeating: -1e9)) { V3(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z)) }
            let size = V2(max(hi.x - lo.x, hi.y - lo.y) + 4.5, 5)
            try await look(at: (lo + hi) / 2, size: size, shot: .side, duration: 0.9)
            try await TraceInteraction.draw(session: self, line: ink, marker: marker, normal: toWorld.applyVector(surface.normal),
                                            showHint: hintsOn && i == 0).run()
            success("Nice detail!", at: ink.path.point(at: ink.path.length / 2) + V3(0, 0.9, 0))
            reward(30, at: ink.path.point(at: ink.path.length / 2) + V3(0, 1.5, 0))
        }
        let from = marker.pose, rest = engine.workspace.markerRest
        tw.start(0.6, ease: .inOutCubic) { k in marker.setPose(from.lerp(rest, k)) }
        try await tw.wait(0.3)
    }
}
