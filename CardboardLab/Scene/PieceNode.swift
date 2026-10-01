import SceneKit
import UIKit

/// SceneKit representation of one cardboard piece: a node per panel (posed by the
/// piece's FoldRig), ink outlines that appear once the piece is cut free, blue dashed
/// fold lines and crease marks that darken as a hinge is scored and folded.
@MainActor
final class PieceNode {
    let def: PieceDef
    let stock: CardboardStock
    let root = SCNNode()
    private(set) var rig: FoldRig
    private(set) var panelNodes: [String: SCNNode] = [:]
    private var inkNodes: [SCNNode] = []
    /// Blue dashed fold line per child panel id (drawn on the parent panel).
    private(set) var dashNodes: [String: SCNNode] = [:]
    /// Dark crease line per child panel id.
    private(set) var creaseNodes: [String: SCNNode] = [:]
    private var bodyMeshes: [String: MeshData] = [:]
    private let materials: CardboardMaterials
    /// Painted face colours per panel (free mode).
    private var paint: [String: (top: UIColor?, under: UIColor?)] = [:]

    /// World transform of the piece frame.
    var pose: Pose {
        get { root.pose }
        set { root.setPose(newValue) }
    }

    init(def: PieceDef, stock: CardboardStock, showFoldLines: Bool = true, inkVisible: Bool = true) {
        self.def = def
        self.stock = stock
        self.rig = FoldRig(piece: def, thickness: stock.thickness)
        self.materials = CardboardMaterials(stock: stock)
        root.name = "piece-\(def.id)"
        let t = stock.thickness

        for p in def.panels {
            let full = MeshBuilder.cardboard(outline: p.outline, holes: p.holes, thickness: t,
                                             inkEdges: def.freeEdges(of: p.id), inkWidth: 0.05)
            let body = full.extract(parts: [0, 1, 2])
            bodyMeshes[p.id] = body
            let node = SceneBridge.node(body, [materials.top, materials.under, materials.side], name: p.id)
            node.castsShadow = true
            let ink = SceneBridge.node(full.extract(parts: [3]), [Mat.ink], name: "ink")
            ink.castsShadow = false
            ink.isHidden = !inkVisible
            node.addChildNode(ink)
            inkNodes.append(ink)
            root.addChildNode(node)
            panelNodes[p.id] = node
        }

        // Fold lines live on the parent panel so they stay put while the flap rises.
        for p in def.panels {
            guard let h = p.hinge, let parent = p.parent, let parentNode = panelNodes[parent] else { continue }
            // Valley folds are dashed, mountain folds dash-dot (origami notation).
            var dash = MeshData()
            var dashUnder = MeshData()
            if h.kind == .mountain {
                MeshBuilder.dashDot(h.a.onMat(t + 0.006), h.b.onMat(t + 0.006), width: 0.06, into: &dash)
                MeshBuilder.dashDot(h.a.onMat(-0.006), h.b.onMat(-0.006), width: 0.06, normal: V3(0, -1, 0), into: &dashUnder)
            } else {
                MeshBuilder.dashes(h.a.onMat(t + 0.006), h.b.onMat(t + 0.006), width: 0.06, into: &dash)
                MeshBuilder.dashes(h.a.onMat(-0.006), h.b.onMat(-0.006), width: 0.06, normal: V3(0, -1, 0), into: &dashUnder)
            }
            dash.append(dashUnder)
            let dashNode = SceneBridge.node(dash, [Mat.unlit(Palette.blue)], name: "fold-\(p.id)")
            dashNode.castsShadow = false
            dashNode.isHidden = !showFoldLines
            parentNode.addChildNode(dashNode)
            dashNodes[p.id] = dashNode

            var crease = MeshData()
            MeshBuilder.ribbon([h.a.onMat(t + 0.004), h.b.onMat(t + 0.004)], width: 0.035, into: &crease, extend: false)
            MeshBuilder.ribbon([h.a.onMat(-0.004), h.b.onMat(-0.004)], width: 0.035, normal: V3(0, -1, 0), into: &crease, extend: false)
            let creaseNode = SceneBridge.node(crease, [Mat.unlit(Palette.cardboardDark)], name: "crease-\(p.id)")
            creaseNode.castsShadow = false
            creaseNode.opacity = 0
            parentNode.addChildNode(creaseNode)
            creaseNodes[p.id] = creaseNode
        }
        applyRig()
    }

    // MARK: Folding

    func setAngle(_ panel: String, _ angle: Float) {
        rig.angles[panel] = angle
        applyRig()
    }

    func setFold(_ panel: String, progress: Float) {
        guard let h = def.panel(panel)?.hinge else { return }
        rig.angles[panel] = h.signedTarget * progress
        if let crease = creaseNodes[panel] {
            crease.opacity = max(crease.opacity, CGFloat(min(1, abs(progress) * 1.6)))
        }
        applyRig()
    }

    func setAngles(_ angles: [String: Float]) {
        for (k, v) in angles { rig.angles[k] = v }
        applyRig()
    }

    func foldAll(progress: Float = 1) {
        for p in def.panels where p.hinge != nil { setFold(p.id, progress: progress) }
    }

    func applyRig() {
        let poses = rig.poses()
        for (id, node) in panelNodes { node.setPose(poses[id] ?? .identity) }
    }

    func panelPose(_ id: String) -> Pose { rig.pose(of: id) }

    /// World transform of a panel.
    func worldPose(of panel: String) -> Pose { pose * rig.pose(of: panel) }

    /// World position of a point given in flat piece space.
    func world(_ panel: String, _ p: V3) -> V3 { worldPose(of: panel).apply(p) }

    // MARK: Look

    func setInkVisible(_ visible: Bool) {
        for n in inkNodes { n.isHidden = !visible }
    }

    func setFoldLinesVisible(_ visible: Bool) {
        for n in dashNodes.values { n.isHidden = !visible }
    }

    func setFoldLine(_ panel: String, visible: Bool) {
        dashNodes[panel]?.isHidden = !visible
    }

    func setCrease(_ panel: String, _ amount: Float) {
        creaseNodes[panel]?.opacity = CGFloat(saturate(amount))
    }

    /// Temporarily recolors a panel's faces (hover / target highlight).
    func highlight(_ panel: String, color: UIColor?) {
        guard let node = panelNodes[panel] else { return }
        if let color {
            node.geometry?.materials = [materials.top(color), materials.under(color), materials.side]
        } else {
            node.geometry?.materials = baseMaterials(panel)
        }
    }

    /// Paints a panel's printed face and/or underside (nil keeps the bare cardboard).
    func setPaint(_ panel: String, top: UIColor?, under: UIColor?) {
        paint[panel] = (top, under)
        panelNodes[panel]?.geometry?.materials = baseMaterials(panel)
    }

    private func baseMaterials(_ panel: String) -> [SCNMaterial] {
        let p = paint[panel]
        return [materials.top(p?.top ?? nil), materials.under(p?.under ?? nil), materials.side]
    }

    /// Translucent copy of the piece in its current fold state (target outlines).
    func makeGhost(color: UIColor, opacity: CGFloat = 0.38) -> SCNNode {
        let ghost = SCNNode()
        ghost.name = "ghost-\(def.id)"
        let mat = Mat.unlit(color, opacity: opacity, depthWrite: false)
        let poses = rig.poses()
        for p in def.panels {
            guard let mesh = bodyMeshes[p.id] else { continue }
            let n = SceneBridge.node(mesh, [mat, mat, mat])
            n.castsShadow = false
            n.setPose(poses[p.id] ?? .identity)
            ghost.addChildNode(n)
        }
        ghost.renderingOrder = 30
        return ghost
    }

    /// World outline of the piece's flat footprint under its current root pose.
    func footprint() -> [V3] {
        let t = stock.thickness
        return def.outline.map { pose.apply($0.onMat(t)) }
    }

    func setCastsShadow(_ on: Bool) {
        for n in panelNodes.values { n.castsShadow = on }
    }

    /// Axis-aligned bounds of the folded piece in its own frame.
    var foldedBounds: (min: V3, max: V3) { rig.foldedBounds() }
}

/// Builds finished weapons for icons, the guide and the menu.
@MainActor
enum WeaponModel {
    /// The assembled weapon centred on the origin, blade along −x, edges sanded.
    static func assembled(_ design: WeaponDesign, stock: CardboardStock, sharpened: Bool = true) -> SCNNode {
        let bp = WeaponBlueprint(design: design, thickness: stock.thickness)
        let root = SCNNode()
        root.name = "weapon-\(design.id)"
        let assembly = SCNNode()
        for def in bp.template.pieces {
            let piece = PieceNode(def: def, stock: stock, showFoldLines: false)
            piece.setAngles(bp.finishedAngles(def.id))
            for p in def.panels where p.hinge != nil { piece.setCrease(p.id, 1) }
            piece.pose = bp.assembledPose(def.id)
            if sharpened { addFinish(to: piece, bp: bp) }
            assembly.addChildNode(piece.root)
        }
        assembly.setPose(.translation(bp.assembledCentre * -1))
        root.addChildNode(assembly)
        return root
    }

    /// Sanded bevels and carved fullers on a finished piece.
    static func addFinish(to piece: PieceNode, bp: WeaponBlueprint) {
        for surface in bp.sharpenPaths where surface.piece == piece.def.id {
            guard let panel = piece.def.panel(surface.panel), let node = piece.panelNodes[surface.panel] else { continue }
            let bevel = BevelNode(surface: surface, inner: surface.inset(into: panel, width: 0.3), toWorld: .identity, style: .bevel)
            bevel.setProgress(bevel.path.length)
            bevel.setActive(false, time: 0)
            node.addChildNode(bevel.root)
        }
        for surface in bp.fullerPaths where surface.piece == piece.def.id {
            guard let node = piece.panelNodes[surface.panel] else { continue }
            let groove = BevelNode(surface: surface, inner: surface.points, toWorld: .identity, style: .groove)
            groove.setProgress(groove.path.length)
            groove.setActive(false, time: 0)
            node.addChildNode(groove.root)
        }
    }

    /// Length of the finished weapon's longest side (for framing).
    static func span(_ design: WeaponDesign, stock: CardboardStock) -> Float {
        let b = WeaponBlueprint(design: design, thickness: stock.thickness).assembledBounds()
        return max(b.max.x - b.min.x, b.max.z - b.min.z)
    }
}

/// Builds the finished pistol or rifle for icons and the finale.
@MainActor
enum GunModel {
    /// The assembled gun centred on the origin, barrel along −x, details drawn on.
    static func assembled(_ kind: GunKind, stock: CardboardStock) -> SCNNode {
        let bp = GunBlueprint(kind: kind, thickness: stock.thickness)
        let root = SCNNode()
        root.name = "gun-\(kind.rawValue)"
        let assembly = SCNNode()
        var nodes: [String: PieceNode] = [:]
        for def in bp.template.pieces {
            let piece = PieceNode(def: def, stock: stock, showFoldLines: false)
            piece.setAngles(bp.finishedAngles(def.id))
            for p in def.panels where p.hinge != nil { piece.setCrease(p.id, 1) }
            piece.pose = bp.assembledPose(def.id)
            assembly.addChildNode(piece.root)
            nodes[def.id] = piece
        }
        for detail in bp.details {
            let surface = detail.path
            guard let node = nodes[surface.piece]?.panelNodes[surface.panel] else { continue }
            let ink = BevelNode(surface: surface, inner: surface.points, toWorld: .identity, style: .ink)
            ink.setProgress(ink.path.length)
            ink.setActive(false, time: 0)
            node.addChildNode(ink.root)
        }
        assembly.setPose(.translation(bp.assembledCentre * -1))
        root.addChildNode(assembly)
        return root
    }

    static func span(_ kind: GunKind, stock: CardboardStock) -> Float {
        let b = GunBlueprint(kind: kind, thickness: stock.thickness).assembledBounds()
        return max(b.max.x - b.min.x, b.max.y - b.min.y)
    }
}
