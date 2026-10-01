import Combine
import Metal
import SceneKit
import UIKit

/// Renders the low-poly 3D models into small images for the SwiftUI menus, so every
/// icon matches the look of the 3D world exactly.
@MainActor
final class IconFactory: ObservableObject {
    /// Icons are baked onto the card color (cards are drawn with the same color).
    static let cardColor = Palette.ink

    @Published private(set) var images: [String: UIImage] = [:]
    private var renderedStock: String?

    private lazy var renderer: SCNRenderer? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return SCNRenderer(device: device, options: nil)
    }()

    func image(_ key: String) -> UIImage? { images[key] }

    func renderAll(stock: CardboardStock) {
        guard renderedStock != stock.id else { return }
        renderedStock = stock.id
        var out = images

        out["tool.knife"] = snap(turned(Props.craftKnife(), yaw: 0.55), target: V3(1.8, 0.15, -1.1), distance: 11, polar: 0.62)
        out["tool.scissors"] = snap(turned(Props.scissors(), yaw: 0.7), target: V3(0.4, 0.1, -0.3), distance: 9, polar: 0.62)
        let glue = SCNNode()
        let bottle = Props.glueBottle()
        bottle.eulerAngles.x = .pi
        bottle.position = SCNVector3(0, 2.91, 0)
        glue.addChildNode(bottle)
        out["tool.glue"] = snap(glue, target: V3(0, 1.4, 0), distance: 11, polar: 1.0)
        out["tool.ruler"] = snap(turned(Props.ruler(), yaw: 0.78), target: V3(0, 0.06, 0), distance: 17, polar: 0.62)
        out["tool.pencil"] = snap(turned(Props.pencil(), yaw: 0.62), target: V3(2.3, 0, -1.6), distance: 12, polar: 0.62)
        out["tool.tape"] = snap(Props.tapeRoll(), target: V3(0, 0.3, 0), distance: 9, polar: 0.72)
        out["tool.folder"] = snap(turned(Props.boneFolder(), yaw: 0.6), target: V3(1.4, 0.05, -0.95), distance: 8.5, polar: 0.62)
        out["tool.sander"] = snap(turned(Props.sandingBlock(), yaw: 0.6), target: V3(0, 0.35, 0), distance: 7.5, polar: 0.75)

        out["project.knife"] = weaponSnap(.knife, stock: stock)
        out["weapon.knife"] = out["project.knife"]
        out["tool.marker"] = snap(turned(Props.marker(), yaw: 0.6), target: V3(1.6, 0, -1.0), distance: 8.5, polar: 0.62)
        out["project.free"] = snap(freeCraftModel(stock: stock), target: V3(0, 0.4, 0), distance: 15, polar: 0.8)
        images = out
        renderWeapons(stock: stock)
    }

    // MARK: Weapons

    private var weaponTask: Task<Void, Never>?

    /// Campaign weapon and gun icons, one per frame in campaign order (the first cards
    /// on the menu fill in first) so launch stays smooth.
    private func renderWeapons(stock: CardboardStock) {
        weaponTask?.cancel()
        weaponTask = Task { @MainActor [weak self] in
            for id in Campaign.order {
                await Task.yield()
                guard let self, !Task.isCancelled else { return }
                if let design = WeaponDesign.byID(id) {
                    self.images["weapon.\(id)"] = self.weaponSnap(design, stock: stock)
                } else if let kind = GunKind(rawValue: id) {
                    let span = GunModel.span(kind, stock: stock)
                    self.images["gun.\(id)"] = self.snap(turned(GunModel.assembled(kind, stock: stock), yaw: 0.3), target: V3(0, 0, 0),
                                                         distance: span * 1.55 + 2, polar: 1.0)
                }
            }
        }
    }

    /// Free Craft card: a sheet with a blade blank pencilled on it, pencil and ruler.
    private func freeCraftModel(stock: CardboardStock) -> SCNNode {
        let root = SCNNode()
        let t = stock.thickness
        let outline = Poly.rect(-3.4, -2.4, 3.4, 2.4)
        let sheet = SceneBridge.node(MeshBuilder.cardboard(outline: outline, thickness: t,
                                                           inkEdges: (0..<4).map { (outline[$0], outline[($0 + 1) % 4]) }, inkWidth: 0.06),
                                     CardboardMaterials(stock: stock).array)
        root.addChildNode(sheet)
        // A flame-dagger outline drawn in red, with its blue spine.
        let blade = BladeSpec(build: .ridge, tip: .flame, length: 4.2, width: 1.5, tangLength: 1.6)
        let upper = BladeShapes.ridgeUpper(blade, tangHalf: 0.35)
        let ring = upper + upper.reversed().map { V2($0.x, -$0.y) }
        var lines = MeshData()
        MeshBuilder.ribbon((ring + [ring[0]]).map { V3($0.x + 1.2, t + 0.01, $0.y - 0.4) }, width: 0.09, into: &lines)
        root.addChildNode(SceneBridge.node(lines, [Mat.unlit(Palette.red)]))
        var dash = MeshData()
        MeshBuilder.dashes(V3(-3.0, t + 0.012, -0.4), V3(2.8, t + 0.012, -0.4), into: &dash)
        root.addChildNode(SceneBridge.node(dash, [Mat.unlit(Palette.blue)]))
        let pencil = Props.pencil()
        pencil.setPose(Pose(rot: Quat(axis: V3(0, 1, 0), angle: 0.5) * Quat(axis: V3(0, 0, 1), angle: 0.25), pos: V3(-1.2, t + 0.25, 1.5)))
        root.addChildNode(pencil)
        root.eulerAngles.y = 0.3
        return root
    }

    /// Icon key for a weapon, rendering it now if needed (Free Craft designs).
    func weaponIcon(_ design: WeaponDesign, stock: CardboardStock) -> String {
        let campaign = WeaponDesign.byID(design.id) != nil
        let key = campaign ? "weapon.\(design.id)" : "weapon.custom"
        if !campaign || images[key] == nil {
            images[key] = weaponSnap(design, stock: stock)
        }
        return key
    }

    private func weaponSnap(_ design: WeaponDesign, stock: CardboardStock, size: CGSize = CGSize(width: 360, height: 360)) -> UIImage? {
        let span = WeaponModel.span(design, stock: stock)
        return snap(turned(WeaponModel.assembled(design, stock: stock), yaw: 0.28), target: V3(0, 0, 0),
                    distance: span * 1.75 + 2, polar: 0.72, size: size)
    }

    // MARK: Guide illustrations

    private var guideStock: String?

    /// Renders the eight "How to build" illustrations from the real knife pieces.
    func renderGuide(stock: CardboardStock) {
        guard guideStock != stock.id else { return }
        guideStock = stock.id
        let bp = WeaponBlueprint(design: .knife, thickness: stock.thickness)
        guard let handleDef = bp.piece("handle"), let bladeDef = bp.piece("blade"), let bandDef = bp.piece("wrap0") else { return }
        let t = stock.thickness
        let L = bp.L
        let size = CGSize(width: 480, height: 320)
        var out = images

        // 1. Cut the shape.
        do {
            let root = SCNNode()
            let sheet = TemplateSheet(template: bp.template, stock: stock)
            root.addChildNode(sheet.root)
            if let cut = sheet.outlineCuts["blade"] {
                cut.setProgress(cut.path.length * 0.42)
                let knife = Props.craftKnife()
                knife.setPose(TraceInteraction.knifePose(tip: cut.path.point(at: cut.path.length * 0.42),
                                                         tangent: cut.path.tangent(at: cut.path.length * 0.42)))
                root.addChildNode(knife)
            }
            let sheetSize = bp.template.sheetSize
            out["guide.1"] = snap(root, target: V3(0, 0, 0.3), distance: max(sheetSize.x, sheetSize.y * 1.5) * 1.35, polar: 0.5,
                                  size: size, mat: true)
        }
        // 2. Score the creases.
        do {
            let root = SCNNode()
            let handle = PieceNode(def: handleDef, stock: stock)
            root.addChildNode(handle.root)
            if let h = handleDef.panel("HS1")?.hinge {
                let line = ScoreLineNode(points: [h.a.onMat(t + 0.012), h.b.onMat(t + 0.012)])
                line.setProgress(line.path.length * 0.6)
                line.setActive(true, time: 0)
                root.addChildNode(line.root)
                let folder = Props.boneFolder()
                folder.setPose(TraceInteraction.penPose(tip: line.path.point(at: line.path.length * 0.6), tangent: V3(1, 0, 0), raise: radians(30)))
                root.addChildNode(folder)
            }
            for id in ["HS1", "HS2", "HT", "GT", "EC"] { handle.setCrease(id, 0.55) }
            out["guide.2"] = snap(root, target: V3(L / 2 + 0.5, 0, -0.6), distance: 13, polar: 0.62, azimuth: -0.25, size: size, mat: true)
        }
        // 3. Fold the walls up.
        do {
            let root = SCNNode()
            let handle = PieceNode(def: handleDef, stock: stock, showFoldLines: false)
            handle.setFold("HS1", progress: 1)
            handle.setFold("HS2", progress: 1)
            handle.setFold("EC", progress: 0.65)
            handle.setFold("GT", progress: 0.4)
            root.addChildNode(handle.root)
            out["guide.3"] = snap(root, target: V3(L / 2 + 0.1, 0.5, -0.6), distance: 11, polar: 0.82, azimuth: -0.35, size: size, mat: true)
        }
        // 4. Glue the tab.
        do {
            let root = SCNNode()
            let handle = PieceNode(def: handleDef, stock: stock, showFoldLines: false)
            for id in ["HS1", "HS2", "EC", "GT"] { handle.setFold(id, progress: 1) }
            root.addChildNode(handle.root)
            let glue = bp.handleGlue
            let bead = GlueBeadNode(localPoints: glue.points, localNormal: glue.normal, toWorld: handle.worldPose(of: "GT"))
            bead.setProgress(bead.path.length * 0.7)
            handle.panelNodes["GT"]?.addChildNode(bead.root)
            let bottle = Props.glueBottle()
            bottle.setPose(TraceInteraction.bottlePose(tip: bead.path.point(at: bead.path.length * 0.7), tangent: V3(1, 0, 0)))
            root.addChildNode(bottle)
            out["guide.4"] = snap(root, target: V3(L / 2 + 0.1, 1.0, 0), distance: 11, polar: 0.8, azimuth: -0.3, size: size, mat: true)
        }
        // 5. Close the handle.
        do {
            let root = SCNNode()
            let handle = PieceNode(def: handleDef, stock: stock, showFoldLines: false)
            for id in ["HS1", "HS2", "EC", "GT"] { handle.setFold(id, progress: 1) }
            handle.setFold("HT", progress: 0.55)
            handle.highlight("GT", color: Palette.mint)
            root.addChildNode(handle.root)
            out["guide.5"] = snap(root, target: V3(L / 2 + 0.1, 0.8, -0.3), distance: 11, polar: 0.8, azimuth: -0.3, size: size, mat: true)
        }
        // 6. Fold the blade.
        do {
            let root = SCNNode()
            let blade = PieceNode(def: bladeDef, stock: stock, showFoldLines: false)
            blade.setAngles(bp.bladeAngles(1))
            blade.pose = bp.bladeRootPose(1)
            blade.setCrease("BL", 1)
            root.addChildNode(blade.root)
            if let glue = bp.bladeGlue {
                let bead = GlueBeadNode(localPoints: glue.points, localNormal: glue.normal, toWorld: blade.worldPose(of: glue.panel))
                bead.setProgress(bead.path.length)
                bead.settle()
                blade.panelNodes[glue.panel]?.addChildNode(bead.root)
            }
            out["guide.6"] = snap(root, target: V3(-1.9, 0.2, 0), distance: 15, polar: 0.78, azimuth: -0.3, size: size, mat: true)
        }
        // 7. Connect the pieces.
        do {
            let root = SCNNode()
            let handle = PieceNode(def: handleDef, stock: stock, showFoldLines: false)
            handle.foldAll()
            let blade = PieceNode(def: bladeDef, stock: stock, showFoldLines: false)
            blade.setAngles(bp.bladeAngles(1))
            blade.pose = bp.bladeReady.lerp(bp.bladeSeated, 0.45)
            let band = PieceNode(def: bandDef, stock: stock, showFoldLines: false)
            band.setFold("C1", progress: 1)
            band.setFold("C2", progress: 0.5)
            band.pose = bp.wrapMount(0)
            for p in [handle, blade, band] { root.addChildNode(p.root) }
            let lifted = SCNNode()
            lifted.position = SCNVector3(0, 1.6, 0)
            lifted.addChildNode(root)
            out["guide.7"] = snap(lifted, target: V3(-1.9, 2.0, 0), distance: 20, polar: 0.72, azimuth: -0.35, size: size, mat: true)
        }
        // 8. Sharpen & shape: sanding block halfway down the second edge.
        do {
            let root = SCNNode()
            var pieces: [PieceNode] = []
            for def in [handleDef, bladeDef, bandDef] {
                let piece = PieceNode(def: def, stock: stock, showFoldLines: false)
                piece.setAngles(bp.finishedAngles(def.id))
                piece.pose = bp.assembledPose(def.id)
                root.addChildNode(piece.root)
                pieces.append(piece)
            }
            let blade = pieces[1]
            for (i, surface) in bp.sharpenPaths.enumerated() {
                guard let panel = bladeDef.panel(surface.panel), let node = blade.panelNodes[surface.panel] else { continue }
                let toWorld = blade.worldPose(of: surface.panel)
                let inner = surface.inset(into: panel, width: 0.3)
                let bevel = BevelNode(surface: surface, inner: inner, toWorld: toWorld, style: .bevel)
                let k: Float = i == 0 ? 1 : 0.55
                bevel.setProgress(bevel.path.length * k)
                bevel.setActive(i != 0, time: 0)
                node.addChildNode(bevel.root)
                if i == 1 {
                    let tip = bevel.path.point(at: bevel.path.length * k)
                    let tangent = bevel.path.tangent(at: bevel.path.length * k)
                    let n = toWorld.applyVector(surface.normal).unit
                    let x = (tangent - n * tangent.dotp(n)).unit
                    let mid = surface.points.count / 2
                    let inward = toWorld.applyVector(inner[mid] - surface.points[mid]).unit
                    let sander = Props.sandingBlock()
                    sander.setPose(Pose(rot: Quat.fromBasis(x: x, y: n, z: x.crossp(n)), pos: tip + inward * 0.18 + n * 0.01))
                    root.addChildNode(sander)
                }
            }
            let lifted = SCNNode()
            lifted.position = SCNVector3(0, 1.6, 0)
            lifted.addChildNode(root)
            out["guide.8"] = snap(lifted, target: V3(-2.6, 2.0, 0.2), distance: 15, polar: 0.62, azimuth: -0.2, size: size, mat: true)
        }
        images = out
    }

    private func turned(_ node: SCNNode, yaw: Float) -> SCNNode {
        let holder = SCNNode()
        node.eulerAngles.y = yaw
        holder.addChildNode(node)
        return holder
    }

    private func snap(_ model: SCNNode, target: V3, distance: Float, polar: Float, azimuth: Float = 0,
                      size: CGSize = CGSize(width: 360, height: 360), mat: Bool = false) -> UIImage? {
        guard let renderer else { return nil }
        let scene = SCNScene()
        scene.background.contents = IconFactory.cardColor
        scene.rootNode.addChildNode(model)
        if mat {
            let plane = SCNPlane(width: 60, height: 60)
            plane.materials = [Mat.lambert(Palette.mat)]
            let matNode = SCNNode(geometry: plane)
            matNode.eulerAngles.x = -.pi / 2
            matNode.position = SCNVector3(target.x, -0.01, target.z)
            scene.rootNode.addChildNode(matNode)
        }

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 640
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 520
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.position = SCNVector3(-6, 14, 8)
        sunNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sunNode)

        let orbit = OrbitCamera(target: target, distance: distance, polar: polar, azimuth: azimuth,
                                fovY: radians(30), viewSize: V2(Float(size.width), Float(size.height)))
        let cam = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.5
        camera.zFar = 200
        cam.camera = camera
        cam.setPose(Pose(rot: orbit.orientation, pos: orbit.eye))
        scene.rootNode.addChildNode(cam)

        renderer.scene = scene
        renderer.pointOfView = cam
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
}
