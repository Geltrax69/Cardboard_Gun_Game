import SceneKit
import UIKit

/// A cardboard sheet printed with a craft template: the waste board (sheet minus the
/// pieces), each piece as a foldable PieceNode sitting in its hole, punch-out discs
/// filling the pieces' inner holes, and the red cut lines.
@MainActor
final class TemplateSheet {
    let template: CraftTemplate
    let stock: CardboardStock
    let root = SCNNode()
    let waste: SCNNode
    private(set) var pieces: [String: PieceNode] = [:]
    /// Outline cut line per piece id.
    private(set) var outlineCuts: [String: CutLineNode] = [:]
    /// Inner (hole) cut lines per piece id.
    private(set) var innerCuts: [String: [CutLineNode]] = [:]
    /// Punch-out discs per piece id, parallel to `innerCuts`.
    private(set) var holeDiscs: [String: [SCNNode]] = [:]

    var surfaceY: Float { stock.thickness + 0.008 }

    init(template: CraftTemplate, stock: CardboardStock) {
        self.template = template
        self.stock = stock
        root.name = "templateSheet"
        let t = stock.thickness
        let mats = CardboardMaterials(stock: stock)

        let sheetOutline = template.sheetOutline
        let holes = template.pieces.map { Poly.translate($0.outline, $0.placement) }
        let sheetEdges = (0..<4).map { (sheetOutline[$0], sheetOutline[($0 + 1) % 4]) }
        let wasteMesh = MeshBuilder.cardboard(outline: sheetOutline, holes: holes, thickness: t, inkEdges: sheetEdges, inkWidth: 0.05)
        waste = SceneBridge.node(wasteMesh, mats.array, name: "waste")
        waste.castsShadow = true
        root.addChildNode(waste)

        for def in template.pieces {
            let piece = PieceNode(def: def, stock: stock, showFoldLines: true, inkVisible: false)
            piece.pose = KnifeBlueprint.sheetPose(def)
            root.addChildNode(piece.root)
            pieces[def.id] = piece

            let y = t + 0.008
            let loop = (def.outline + [def.outline[0]]).map { ($0 + def.placement).onMat(y) }
            let cut = CutLineNode(points: loop, name: def.id)
            root.addChildNode(cut.root)
            outlineCuts[def.id] = cut

            var inner: [CutLineNode] = []
            var discs: [SCNNode] = []
            for p in def.panels {
                for hole in p.holes {
                    let ring = (hole + [hole[0]]).map { ($0 + def.placement).onMat(y) }
                    let c = CutLineNode(points: ring, name: "\(def.id)-hole")
                    root.addChildNode(c.root)
                    inner.append(c)
                    let discMesh = MeshBuilder.cardboard(outline: Poly.signedArea(hole) < 0 ? hole.reversed() : hole, thickness: t)
                    let disc = SceneBridge.node(discMesh, mats.array, name: "disc")
                    disc.castsShadow = true
                    piece.panelNodes[p.id]?.addChildNode(disc)
                    discs.append(disc)
                }
            }
            innerCuts[def.id] = inner
            holeDiscs[def.id] = discs
        }
    }

    var allCutLines: [CutLineNode] {
        Array(outlineCuts.values) + innerCuts.values.flatMap { $0 }
    }

    /// Centre of a piece's flat footprint in world space.
    func center(of pieceID: String) -> V3 {
        guard let def = template.piece(pieceID) else { return V3(0, 0, 0) }
        let b = Poly.bounds(def.outline)
        return ((b.min + b.max) / 2 + def.placement).onMat(stock.thickness)
    }

    /// Prints the template: each red line is drawn by the pencil, then the blue fold
    /// lines fade in.
    func printTemplate(pencil: SCNNode, tweener: Tweener) async throws {
        for cut in allCutLines { cut.drawIn(0) }
        for p in pieces.values { p.setFoldLinesVisible(false) }
        let rest = pencil.pose
        // Body leans up and toward the bottom-right, like a hand holding it.
        let tilt = Quat.euler(yaw: -0.7, pitch: 0, roll: 0.75)
        for def in template.pieces {
            guard let cut = outlineCuts[def.id] else { continue }
            let start = cut.path.point(at: 0)
            let hop = pencil.pose
            try await tweener.tween(0.22, ease: .inOutQuad) { k in
                let p = mix3(hop.pos, start + V3(0, 0.05, 0), k) + V3(0, sin(k * .pi) * 1.2, 0)
                pencil.setPose(Pose(rot: hop.rot.slerp(tilt, k), pos: p))
            }
            try await tweener.tween(0.75, ease: .inOutSine) { k in
                cut.drawIn(k)
                pencil.setPose(Pose(rot: tilt, pos: cut.path.point(at: cut.path.length * k) + V3(0, 0.05, 0)))
            }
            for inner in innerCuts[def.id] ?? [] { inner.drawIn(1) }
        }
        let last = pencil.pose
        tweener.start(0.5, ease: .inOutCubic) { k in
            pencil.setPose(last.lerp(rest, k))
        }
        for p in pieces.values { p.setFoldLinesVisible(true) }
        let dashNodes = pieces.values.flatMap { Array($0.dashNodes.values) }
        try await tweener.tween(0.4) { k in
            for d in dashNodes { d.opacity = CGFloat(k) }
        }
    }
}
