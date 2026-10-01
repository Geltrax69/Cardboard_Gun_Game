import SceneKit
import UIKit

extension PaintColor {
    var uiColor: UIColor { UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1) }
}

/// The free mode workbench in 3D: one node per sheet and a PieceNode per piece, kept in
/// step with `WorkshopState`. `apply` diffs two states so live edits, commits and undo
/// all go through the same path. Glued pieces are parented to the piece they're glued to.
@MainActor
final class WorkshopScene {
    let root = SCNNode()
    let stock: CardboardStock
    private(set) var sheetNodes: [String: SCNNode] = [:]
    private(set) var pieceNodes: [String: PieceNode] = [:]
    private var state = WorkshopState()

    var t: Float { stock.thickness }

    init(stock: CardboardStock) {
        self.stock = stock
        root.name = "workshop"
    }

    // MARK: Sync

    func apply(_ new: WorkshopState) {
        let old = state
        state = new
        // Sheets.
        for (id, node) in sheetNodes where new.sheet(id) == nil {
            node.removeFromParentNode()
            sheetNodes[id] = nil
        }
        for s in new.sheets where old.sheet(s.id) != s || sheetNodes[s.id] == nil {
            buildSheet(s)
        }
        // Pieces: drop removed ones (their glued children were re-homed in the state).
        for (id, node) in pieceNodes where new.piece(id) == nil {
            node.root.removeFromParentNode()
            pieceNodes[id] = nil
        }
        var replaced = Set<String>()
        for p in gluedOrder(new) {
            let o = old.piece(p.id)
            if o == nil || pieceNodes[p.id] == nil || shape(o!) != shape(p) {
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

    /// Geometry identity of a piece (outlines and creases, not angles or paint).
    private func shape(_ p: FreePiece) -> [FreePanel] {
        p.panels.map { panel in
            var q = panel
            q.angle = 0
            q.top = nil
            q.under = nil
            return q
        }
    }

    private func buildSheet(_ s: FreeSheet) {
        sheetNodes[s.id]?.removeFromParentNode()
        let outline = s.outline
        var edges = (0..<4).map { (outline[$0], outline[($0 + 1) % 4]) }
        for h in s.holes {
            for i in 0..<h.count { edges.append((h[i], h[(i + 1) % h.count])) }
        }
        let mesh = MeshBuilder.cardboard(outline: outline, holes: s.holes, thickness: t, inkEdges: edges, inkWidth: 0.05)
        let mats = CardboardMaterials(stock: stock)
        var list = mats.array
        if let top = s.top { list[0] = Mat.lambert(top.uiColor) }
        if let under = s.under { list[1] = Mat.lambert(under.uiColor) }
        let node = SceneBridge.node(mesh, list, name: "sheet-\(s.id)")
        node.castsShadow = true
        node.setPosition(s.center)
        root.addChildNode(node)
        sheetNodes[s.id] = node
    }

    private func buildPiece(_ p: FreePiece) {
        let oldRoot = pieceNodes[p.id]?.root
        let node = PieceNode(def: p.pieceDef, stock: stock, showFoldLines: true, inkVisible: true)
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
    }

    /// World pose of a panel of a piece, as currently displayed.
    func panelWorld(_ piece: String, _ panel: String) -> Pose {
        guard let node = pieceNodes[piece] else { return .identity }
        return state.worldPose(piece) * node.rig.pose(of: panel)
    }

    /// Nearest piece face under a screen ray.
    func hitPanel(origin o: V3, dir d: V3) -> PanelHit? {
        var best: PanelHit?
        for p in state.pieces {
            guard let node = pieceNodes[p.id] else { continue }
            let base = state.worldPose(p.id)
            for panel in p.panels {
                let pose = base * node.rig.pose(of: panel.id)
                let inv = pose.inverse
                let lo = inv.apply(o), ld = inv.applyVector(d)
                guard let h = Poly.raySlab(origin: lo, dir: ld, outline: panel.outline, thickness: t) else { continue }
                if best == nil || h.distance < best!.distance {
                    let local = lo + ld * h.distance
                    best = PanelHit(piece: p.id, panel: panel.id, top: h.top, distance: h.distance, local: local, world: o + d * h.distance)
                }
            }
        }
        return best
    }

    struct SheetHit {
        var sheet: String
        /// Point in sheet coordinates (centred).
        var local: V2
        var distance: Float
        var top: Bool
    }

    /// Sheet surface under a screen ray (outside the holes).
    func hitSheet(origin o: V3, dir d: V3) -> SheetHit? {
        var best: SheetHit?
        for s in state.sheets {
            let lo = o - s.center
            guard let h = Poly.raySlab(origin: lo, dir: d, outline: s.outline, thickness: t) else { continue }
            let q = (lo + d * h.distance).xz
            if s.holes.contains(where: { Poly.contains($0, q) }) { continue }
            if best == nil || h.distance < best!.distance { best = SheetHit(sheet: s.id, local: q, distance: h.distance, top: h.top) }
        }
        return best
    }

    /// Point on a sheet's top plane under a ray (even over holes or past the edge), for
    /// drawing strokes that wander a little.
    func sheetPlanePoint(_ sheet: String, origin o: V3, dir d: V3) -> V2? {
        guard let s = state.sheet(sheet), abs(d.y) > 1e-5 else { return nil }
        let k = (s.center.y + t - o.y) / d.y
        guard k > 0 else { return nil }
        return (o + d * k - s.center).xz
    }

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
    private var selectedColor = Palette.mint

    /// Tints one piece (the selection); only the pieces that change are touched.
    func setSelected(_ id: String?, color: UIColor = Palette.mint) {
        if let old = selectedID, old != id || color != selectedColor, let node = pieceNodes[old] {
            for panel in node.def.panels { node.highlight(panel.id, color: nil) }
        }
        selectedID = id
        selectedColor = color
        if let id, let node = pieceNodes[id] {
            for panel in node.def.panels { node.highlight(panel.id, color: color) }
        }
    }
}
