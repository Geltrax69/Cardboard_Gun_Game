import SceneKit
import UIKit

extension PaintColor {
    var uiColor: UIColor { UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1) }

    func mixed(with o: PaintColor, _ k: Float) -> PaintColor {
        PaintColor(r: r + (o.r - r) * k, g: g + (o.g - g) * k, b: b + (o.b - b) * k)
    }

    /// Workshop tints: the selected piece and the piece waiting to be glued.
    static let selectTint = PaintColor(hex: "#97E1BE")
    static let glueTint = PaintColor(hex: "#FADC70")
}

/// The free mode workbench in 3D: a PieceNode per piece (sheets are pieces too), kept in
/// step with `WorkshopState`. `apply` diffs two states so live edits, commits and undo
/// all go through the same path. Glued pieces are parented to the piece they're glued to.
@MainActor
final class WorkshopScene {
    let root = SCNNode()
    /// Stock for pieces that don't name one.
    let defaultStock: CardboardStock
    private(set) var pieceNodes: [String: PieceNode] = [:]
    private var state = WorkshopState()

    init(stock: CardboardStock) {
        defaultStock = stock
        root.name = "workshop"
    }

    func stock(of p: FreePiece) -> CardboardStock { p.stock.map { CardboardStock.byID($0) } ?? defaultStock }

    // MARK: Sync

    func apply(_ new: WorkshopState) {
        let old = state
        state = new
        // Drop removed pieces (their glued children were re-homed in the state).
        for (id, node) in pieceNodes where new.piece(id) == nil {
            node.root.removeFromParentNode()
            pieceNodes[id] = nil
        }
        var replaced = Set<String>()
        for p in gluedOrder(new) {
            let o = old.piece(p.id)
            if o == nil || pieceNodes[p.id] == nil || shape(o!) != shape(p) || o!.stock != p.stock {
                buildPiece(p)
                replaced.insert(p.id)
            } else {
                let node = pieceNodes[p.id]!
                if o!.angles != p.angles { node.setAngles(p.angles) }
                for panel in p.panels where o!.panel(panel.id).map({ $0.top != panel.top || $0.under != panel.under }) ?? true {
                    node.setPaint(panel.id, top: panel.top?.uiColor, under: panel.under?.uiColor)
                }
            }
            let parentReplaced = p.gluedTo.map { replaced.contains($0) } ?? false
            if o == nil || replaced.contains(p.id) || parentReplaced || o!.pose != p.pose || o!.gluedTo != p.gluedTo {
                place(p)
                if parentReplaced { replaced.insert(p.id) }
            }
        }
        // Rebuilt or repainted pieces lose their tint; put it back.
        if let id = selectedID {
            if new.piece(id) == nil { selectedID = nil } else { setSelected(id, color: selectedColor) }
        }
    }

    /// Parents before the pieces glued to them.
    private func gluedOrder(_ s: WorkshopState) -> [FreePiece] {
        var out: [FreePiece] = []
        var seen = Set<String>()
        func visit(_ p: FreePiece, depth: Int) {
            guard !seen.contains(p.id), depth < 64 else { return }
            if let up = p.gluedTo, let parent = s.piece(up) { visit(parent, depth: depth + 1) }
            seen.insert(p.id)
            out.append(p)
        }
        for p in s.pieces { visit(p, depth: 0) }
        return out
    }

    /// Geometry identity of a piece (outlines, holes and creases, not angles or paint).
    private func shape(_ p: FreePiece) -> [FreePanel] {
        p.panels.map { panel in
            var q = panel
            q.angle = 0
            q.top = nil
            q.under = nil
            return q
        }
    }

    private func buildPiece(_ p: FreePiece) {
        let oldRoot = pieceNodes[p.id]?.root
        let node = PieceNode(def: p.pieceDef, stock: stock(of: p), showFoldLines: true, inkVisible: true)
        node.setAngles(p.angles)
        for panel in p.panels where panel.parent != nil { node.setCrease(panel.id, 1) }
        for panel in p.panels where panel.top != nil || panel.under != nil {
            node.setPaint(panel.id, top: panel.top?.uiColor, under: panel.under?.uiColor)
        }
        // Keep pieces glued to this one attached to the new node.
        if let oldRoot {
            for child in oldRoot.childNodes where child.name?.hasPrefix("piece-") == true {
                node.root.addChildNode(child)
            }
            oldRoot.removeFromParentNode()
        }
        pieceNodes[p.id] = node
    }

    private func place(_ p: FreePiece) {
        guard let node = pieceNodes[p.id] else { return }
        let parent = p.gluedTo.flatMap { pieceNodes[$0]?.root } ?? root
        if node.root.parent !== parent { parent.addChildNode(node.root) }
        node.pose = p.pose.pose
    }

    // MARK: Picking

    struct PanelHit {
        var piece: String
        var panel: String
        var top: Bool
        var distance: Float
        /// Hit point in the piece's flat frame.
        var local: V3
        var world: V3
        /// Height of the touched face in the flat frame (thickness for the top, 0 below).
        var faceY: Float
    }

    /// World pose of a panel of a piece, as currently displayed.
    func panelWorld(_ piece: String, _ panel: String) -> Pose {
        guard let node = pieceNodes[piece] else { return .identity }
        return state.worldPose(piece) * node.rig.pose(of: panel)
    }

    /// Nearest piece face under a screen ray (holes let it through).
    func hitPanel(origin o: V3, dir d: V3) -> PanelHit? {
        var best: PanelHit?
        for p in state.pieces {
            guard let node = pieceNodes[p.id] else { continue }
            let base = state.worldPose(p.id)
            let t = node.stock.thickness
            for panel in p.panels {
                let pose = base * node.rig.pose(of: panel.id)
                let inv = pose.inverse
                let lo = inv.apply(o), ld = inv.applyVector(d)
                guard let h = Poly.raySlab(origin: lo, dir: ld, outline: panel.outline, holes: panel.holes, thickness: t) else { continue }
                if best == nil || h.distance < best!.distance {
                    best = PanelHit(piece: p.id, panel: panel.id, top: h.top, distance: h.distance, local: lo + ld * h.distance,
                                    world: o + d * h.distance, faceY: h.top ? t : 0)
                }
            }
        }
        return best
    }

    /// Where a ray meets the plane of a panel's face, in the piece's flat frame (works
    /// past the panel's edges, so strokes can start and end off the piece).
    func panelPlanePoint(_ piece: String, _ panel: String, faceY: Float, origin o: V3, dir d: V3) -> V2? {
        let pose = panelWorld(piece, panel)
        let inv = pose.inverse
        let lo = inv.apply(o), ld = inv.applyVector(d)
        guard abs(ld.y) > 1e-5 else { return nil }
        let k = (faceY - lo.y) / ld.y
        guard k > 0 else { return nil }
        return (lo + ld * k).xz
    }

    func thickness(_ piece: String) -> Float { pieceNodes[piece]?.stock.thickness ?? defaultStock.thickness }

    /// World bounds of a piece and everything glued to it.
    func groupBounds(_ rootID: String) -> (min: V3, max: V3) {
        var lo = V3(repeating: .greatestFiniteMagnitude), hi = V3(repeating: -.greatestFiniteMagnitude)
        for p in state.pieces where state.groupRoot(p.id) == rootID {
            guard let node = pieceNodes[p.id] else { continue }
            let pose = state.worldPose(p.id)
            for c in node.rig.foldedCorners() {
                let q = pose.apply(c)
                lo = V3(min(lo.x, q.x), min(lo.y, q.y), min(lo.z, q.z))
                hi = V3(max(hi.x, q.x), max(hi.y, q.y), max(hi.z, q.z))
            }
        }
        return (lo, hi)
    }

    /// Footprints of every piece on the table (for placing new sheets).
    func pieceFootprints() -> [(V2, V2)] {
        state.pieces.filter { $0.gluedTo == nil }.map { p in
            let b = groupBounds(p.id)
            return (b.min.xz, b.max.xz)
        }
    }

    // MARK: Selection look

    private var selectedID: String?
    private var selectedColor = PaintColor.selectTint

    /// Tints one piece (the selection) while keeping its paint readable; only the pieces
    /// that change are touched.
    func setSelected(_ id: String?, color tint: PaintColor = PaintColor.selectTint) {
        if let old = selectedID, old != id || tint != selectedColor, let node = pieceNodes[old] {
            for panel in node.def.panels { node.highlight(panel.id, color: nil) }
        }
        selectedID = id
        selectedColor = tint
        guard let id, let node = pieceNodes[id], let piece = state.piece(id) else { return }
        let bare = PaintColor(hex: node.stock.top)
        for panel in piece.panels {
            node.highlight(panel.id, color: (panel.top ?? bare).mixed(with: tint, 0.55).uiColor)
        }
    }
}
