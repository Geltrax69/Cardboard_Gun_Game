import SceneKit
import UIKit

/// Low-poly props, built from flat-shaded primitives with chunky ink outlines.
enum Props {
    /// One colored, outlined part.
    static func part(_ mesh: MeshData, _ color: UIColor, outline: Float = 0.035, glossy: Bool = false,
                     castsShadow: Bool = true) -> SCNNode {
        let material = glossy ? Mat.glossy(color) : Mat.lambert(color)
        let node = SceneBridge.node(mesh, [material])
        node.castsShadow = castsShadow
        if outline > 0 {
            let hull = SceneBridge.node(mesh.inflated(by: outline), [Mat.hull])
            hull.castsShadow = false
            node.addChildNode(hull)
        }
        return node
    }

    /// Rotation taking the +y primitive axis onto +x.
    static let alongX = Pose(rot: Quat(axis: V3(0, 0, 1), angle: -.pi / 2))

    // MARK: Craft knife — origin at the blade tip, handle along +x, blade edge down (−y).

    static func craftKnife() -> SCNNode {
        let root = SCNNode()
        root.name = "craftKnife"
        let bladeShape: [V2] = [V2(0, 0), V2(0.62, 0.3), V2(1.02, 0.3), V2(1.02, 0.02)]
        let blade = MeshBuilder.extrudeXY(bladeShape, depth: 0.05).transformed(.translation(V3(0, 0, -0.025)))
        root.addChildNode(part(blade, Palette.steel, outline: 0.022, glossy: true))
        let collar = MeshBuilder.prism(sides: 6, radius: 0.2, height: 0.3, phase: .pi / 6)
            .transformed(.translation(V3(0.98, 0.16, 0)) * alongX)
        root.addChildNode(part(collar, Palette.steelDark, outline: 0.025))
        let grip = MeshBuilder.prism(sides: 6, radius: 0.24, height: 0.8, phase: .pi / 6)
            .transformed(.translation(V3(1.26, 0.16, 0)) * alongX)
        root.addChildNode(part(grip, Palette.ink, outline: 0.02))
        let handle = MeshBuilder.prism(sides: 6, radius: 0.23, height: 2.1, phase: .pi / 6)
            .transformed(.translation(V3(2.04, 0.16, 0)) * alongX)
        root.addChildNode(part(handle, Palette.yellow))
        let slider = MeshBuilder.box(V3(0.5, 0.08, 0.16), center: V3(2.5, 0.41, 0))
        root.addChildNode(part(slider, Palette.ink, outline: 0.015))
        let cap = MeshBuilder.frustum(sides: 6, bottom: 0.23, top: 0.15, height: 0.18, phase: .pi / 6)
            .transformed(.translation(V3(4.12, 0.16, 0)) * alongX)
        root.addChildNode(part(cap, Palette.ink, outline: 0.02))
        return root
    }

    // MARK: Bone folder — scoring tool. Origin at the rounded tip, body along +x.

    static func boneFolder() -> SCNNode {
        let root = SCNNode()
        root.name = "boneFolder"
        var outline: [V2] = []
        for i in 0...6 {
            let a = Float.pi / 2 + Float(i) / 6 * Float.pi
            outline.append(V2(0.22 + cos(a) * 0.22, sin(a) * 0.22))
        }
        outline.append(V2(3.4, -0.24))
        outline.append(V2(3.4, 0.24))
        let ring = outline.reversed().map { V2($0.x, $0.y) }
        let mesh = MeshBuilder.extrudeXY(Array(ring), depth: 0.1)
            .transformed(Pose(rot: Quat(axis: V3(1, 0, 0), angle: -.pi / 2), pos: V3(0, 0.05, 0)))
        root.addChildNode(part(mesh, Palette.paper, outline: 0.025))
        let band = MeshBuilder.box(V3(0.5, 0.12, 0.5), center: V3(2.6, 0.05, 0))
        root.addChildNode(part(band, Palette.blue, outline: 0.015))
        return root
    }

    // MARK: Sanding block — shapes and sharpens edges. Origin at the middle of the
    // sanding face, length along +x, grip up (+y).

    static func sandingBlock() -> SCNNode {
        let root = SCNNode()
        root.name = "sandingBlock"
        root.addChildNode(part(MeshBuilder.box(V3(1.7, 0.08, 0.95), center: V3(0, 0.04, 0)), Palette.cardboardDark, outline: 0.015))
        root.addChildNode(part(MeshBuilder.box(V3(1.6, 0.4, 0.86), center: V3(0, 0.28, 0)), Palette.red))
        let grip = MeshBuilder.prism(sides: 6, radius: 0.24, height: 1.1, phase: .pi / 6)
            .transformed(.translation(V3(-0.55, 0.66, 0)) * alongX)
        root.addChildNode(part(grip, Palette.ink, outline: 0.015))
        for x: Float in [-0.45, 0.45] {
            root.addChildNode(part(MeshBuilder.box(V3(0.14, 0.2, 0.22), center: V3(x, 0.55, 0)), Palette.ink, outline: 0.01))
        }
        return root
    }

    // MARK: Marker — draws details. Origin at the felt tip, body along +x.

    static func marker() -> SCNNode {
        let root = SCNNode()
        root.name = "marker"
        let tip = MeshBuilder.frustum(sides: 6, bottom: 0.03, top: 0.11, height: 0.32, phase: .pi / 6)
            .transformed(Pose(rot: Quat(axis: V3(0, 0, 1), angle: -.pi / 2)))
        root.addChildNode(part(tip, Palette.ink, outline: 0.015))
        root.addChildNode(part(MeshBuilder.prism(sides: 6, radius: 0.24, height: 0.5, phase: .pi / 6)
            .transformed(.translation(V3(0.3, 0, 0)) * alongX), Palette.paper))
        root.addChildNode(part(MeshBuilder.prism(sides: 6, radius: 0.26, height: 2.2, phase: .pi / 6)
            .transformed(.translation(V3(0.8, 0, 0)) * alongX), Palette.ink))
        root.addChildNode(part(MeshBuilder.prism(sides: 6, radius: 0.27, height: 0.35, phase: .pi / 6)
            .transformed(.translation(V3(1.5, 0, 0)) * alongX), Palette.yellow, outline: 0.015))
        root.addChildNode(part(MeshBuilder.frustum(sides: 6, bottom: 0.26, top: 0.18, height: 0.2, phase: .pi / 6)
            .transformed(.translation(V3(3.0, 0, 0)) * alongX), Palette.ink, outline: 0.015))
        return root
    }

    // MARK: Glue bottle — origin at the nozzle tip, body up (+y).

    static func glueBottle() -> SCNNode {
        let root = SCNNode()
        root.name = "glueBottle"
        root.addChildNode(part(MeshBuilder.frustum(sides: 6, bottom: 0.035, top: 0.13, height: 0.5), Palette.paper, outline: 0.02))
        root.addChildNode(part(MeshBuilder.frustum(sides: 6, bottom: 0.3, top: 0.24, height: 0.42)
            .transformed(.translation(V3(0, 0.46, 0))), Palette.blue))
        root.addChildNode(part(MeshBuilder.lathe([V2(0.3, 0), V2(0.62, 0.3), V2(0.62, 1.9), V2(0.5, 2.05), V2(0, 2.05)], sides: 8)
            .transformed(.translation(V3(0, 0.86, 0))), Palette.paper))
        root.addChildNode(part(MeshBuilder.prism(sides: 8, radius: 0.64, height: 0.62)
            .transformed(.translation(V3(0, 1.45, 0))), Palette.mint, outline: 0.015))
        return root
    }

    static func tapeRoll() -> SCNNode {
        let root = SCNNode()
        root.name = "tape"
        root.addChildNode(part(MeshBuilder.tube(sides: 14, inner: 0.95, outer: 1.55, height: 0.62), Palette.yellow))
        root.addChildNode(part(MeshBuilder.tube(sides: 14, inner: 0.8, outer: 0.95, height: 0.64), Palette.cardboardLight, outline: 0.015))
        return root
    }

    static func ruler() -> SCNNode {
        let root = SCNNode()
        root.name = "ruler"
        let len: Float = 9, width: Float = 1.25, h: Float = 0.12
        root.addChildNode(part(MeshBuilder.box(V3(width, h, len), center: V3(0, h / 2, 0)), Palette.yellow))
        let face = SCNPlane(width: CGFloat(width) - 0.02, height: CGFloat(len) - 0.02)
        face.materials = [Mat.textured(Textures.ruler(lengthUnits: CGFloat(len), widthUnits: CGFloat(width)))]
        let faceNode = SCNNode(geometry: face)
        faceNode.eulerAngles.x = -.pi / 2
        faceNode.position = SCNVector3(0, h + 0.004, 0)
        root.addChildNode(faceNode)
        return root
    }

    /// Pencil — origin at the graphite tip, body along +x.
    static func pencil() -> SCNNode {
        let root = SCNNode()
        root.name = "pencil"
        let body = SCNNode()
        body.position = SCNVector3(0.71, 0, 0)
        root.addChildNode(body)
        let r: Float = 0.2
        body.addChildNode(part(MeshBuilder.prism(sides: 6, radius: r, height: 4.2, phase: .pi / 6).transformed(alongX), Palette.yellow))
        body.addChildNode(part(MeshBuilder.frustum(sides: 6, bottom: r, top: 0.06, height: 0.55, phase: .pi / 6)
            .transformed(Pose(rot: Quat(axis: V3(0, 0, 1), angle: .pi / 2))), Palette.cardboardLight))
        body.addChildNode(part(MeshBuilder.frustum(sides: 6, bottom: 0.065, top: 0.0, height: 0.18, phase: .pi / 6)
            .transformed(Pose(rot: Quat(axis: V3(0, 0, 1), angle: .pi / 2), pos: V3(-0.53, 0, 0))), Palette.ink, outline: 0.015))
        body.addChildNode(part(MeshBuilder.prism(sides: 6, radius: r + 0.015, height: 0.32, phase: .pi / 6)
            .transformed(.translation(V3(4.2, 0, 0)) * alongX), Palette.steelDark))
        body.addChildNode(part(MeshBuilder.prism(sides: 6, radius: r, height: 0.38, phase: .pi / 6)
            .transformed(.translation(V3(4.52, 0, 0)) * alongX), Palette.red))
        return root
    }

    static func scissors() -> SCNNode {
        let root = SCNNode()
        root.name = "scissors"
        for side: Float in [-1, 1] {
            let blade = MeshBuilder.extrudeXY([V2(0, -0.12), V2(2.3, -0.02 * side), V2(0, 0.12)], depth: 0.06)
            let bladeNode = part(blade.transformed(Pose(rot: Quat(axis: V3(1, 0, 0), angle: -.pi / 2))), Palette.steel, outline: 0.02, glossy: true)
            bladeNode.eulerAngles.y = side * 0.16
            bladeNode.position = SCNVector3(0, 0.1 + (side > 0 ? 0.07 : 0), 0)
            root.addChildNode(bladeNode)
            let loop = part(MeshBuilder.tube(sides: 8, inner: 0.34, outer: 0.55, height: 0.16), Palette.red)
            loop.position = SCNVector3(-0.8, 0.05, side * 0.52)
            root.addChildNode(loop)
        }
        let pivot = part(MeshBuilder.prism(sides: 6, radius: 0.1, height: 0.3), Palette.ink, outline: 0.01)
        root.addChildNode(pivot)
        return root
    }

    /// A stack of sheets of the given stock.
    static func cardboardStack(width: Float, depth: Float, sheets: Int, stock: CardboardStock, seed: Int = 0) -> SCNNode {
        let root = SCNNode()
        root.name = "stack"
        let mats = CardboardMaterials(stock: stock)
        let t = max(stock.thickness * 1.6, 0.2)
        var y: Float = 0
        for i in 0..<sheets {
            let jitter = Float((i * 37 + seed * 11) % 7 - 3) * 0.035
            let outline = Poly.rect(-width / 2, -depth / 2, width / 2, depth / 2)
            var m = MeshBuilder.cardboard(outline: outline, thickness: t,
                                          inkEdges: (0..<4).map { (outline[$0], outline[($0 + 1) % 4]) }, inkWidth: 0.06)
            m = m.transformed(Pose(rot: Quat(axis: V3(0, 1, 0), angle: jitter), pos: V3(jitter * 2, y, jitter)))
            let n = SceneBridge.node(m, mats.array)
            n.castsShadow = true
            root.addChildNode(n)
            y += t
        }
        return root
    }

    static func scrap(size: Float, stock: CardboardStock = .plain, seed: Int) -> SCNNode {
        let a = Float(seed % 5) * 0.4
        let tri: [V2] = [V2(0, 0), V2(size, size * (0.15 + 0.1 * Float(seed % 3))), V2(size * (0.3 + 0.1 * Float(seed % 4)), size * 0.9)]
            .map { V2($0.x * cos(a) - $0.y * sin(a), $0.x * sin(a) + $0.y * cos(a)) }
        let ring = Poly.signedArea(tri) < 0 ? tri.reversed() : tri
        let m = MeshBuilder.cardboard(outline: ring, thickness: stock.thickness,
                                      inkEdges: (0..<3).map { (ring[$0], ring[($0 + 1) % 3]) }, inkWidth: 0.04)
        let n = SceneBridge.node(m, CardboardMaterials(stock: stock).array)
        n.castsShadow = true
        n.name = "scrap"
        return n
    }
}
