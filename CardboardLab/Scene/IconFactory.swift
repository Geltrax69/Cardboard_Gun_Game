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

        out["project.knife"] = snap(turned(KnifeModel.assembled(stock: stock), yaw: 0.28), target: V3(0, 0, 0), distance: 22, polar: 0.72)
        out["project.pistol"] = snap(turned(Props.pistolModel(), yaw: 0.25), target: V3(0.3, 1.2, 0), distance: 14, polar: 1.05)
        out["project.rifle"] = snap(turned(Props.rifleModel(), yaw: 0.22), target: V3(-0.5, 1.4, 0), distance: 23, polar: 1.05)
        out["project.more"] = snap(turned(Props.crateModel(), yaw: 0.6), target: V3(0, 1.1, 0), distance: 11, polar: 0.9)
        images = out
    }

    // MARK: Guide illustrations

    private var guideStock: String?

    /// Renders the eight "How to build the knife" illustrations from the real pieces.
    func renderGuide(stock: CardboardStock) {
        guard guideStock != stock.id else { return }
        guideStock = stock.id
        let bp = KnifeBlueprint(thickness: stock.thickness)
        let t = stock.thickness
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
            out["guide.1"] = snap(root, target: V3(0, 0, 0.4), distance: 24, polar: 0.5, size: size, mat: true)
        }
        // 2. Score the creases.
        do {
            let root = SCNNode()
            let handle = PieceNode(def: bp.handle, stock: stock)
            root.addChildNode(handle.root)
            if let h = bp.handle.panel("HS1")?.hinge {
                let line = ScoreLineNode(points: [h.a.onMat(t + 0.012), h.b.onMat(t + 0.012)])
                line.setProgress(line.path.length * 0.6)
                line.setActive(true, time: 0)
                root.addChildNode(line.root)
                let folder = Props.boneFolder()
                folder.setPose(TraceInteraction.penPose(tip: line.path.point(at: line.path.length * 0.6), tangent: V3(1, 0, 0), raise: radians(30)))
                root.addChildNode(folder)
            }
            for id in ["HS1", "HS2", "HT", "GT", "EC"] { handle.setCrease(id, 0.55) }
            out["guide.2"] = snap(root, target: V3(2.7, 0, -0.6), distance: 13, polar: 0.62, azimuth: -0.25, size: size, mat: true)
        }
        // 3. Fold the walls up.
        do {
            let root = SCNNode()
            let handle = PieceNode(def: bp.handle, stock: stock, showFoldLines: false)
            handle.setFold("HS1", progress: 1)
            handle.setFold("HS2", progress: 1)
            handle.setFold("EC", progress: 0.65)
            handle.setFold("GT", progress: 0.4)
            root.addChildNode(handle.root)
            out["guide.3"] = snap(root, target: V3(2.3, 0.5, -0.6), distance: 11, polar: 0.82, azimuth: -0.35, size: size, mat: true)
        }
        // 4. Glue the tab.
        do {
            let root = SCNNode()
            let handle = PieceNode(def: bp.handle, stock: stock, showFoldLines: false)
            for id in ["HS1", "HS2", "EC", "GT"] { handle.setFold(id, progress: 1) }
            root.addChildNode(handle.root)
            let bead = GlueBeadNode(localPoints: bp.handleGluePath, localNormal: V3(0, -1, 0), toWorld: handle.worldPose(of: "GT"))
            bead.setProgress(bead.path.length * 0.7)
            handle.panelNodes["GT"]?.addChildNode(bead.root)
            let bottle = Props.glueBottle()
            bottle.setPose(TraceInteraction.bottlePose(tip: bead.path.point(at: bead.path.length * 0.7), tangent: V3(1, 0, 0)))
            root.addChildNode(bottle)
            out["guide.4"] = snap(root, target: V3(2.3, 1.0, 0), distance: 11, polar: 0.8, azimuth: -0.3, size: size, mat: true)
        }
        // 5. Close the handle.
        do {
            let root = SCNNode()
            let handle = PieceNode(def: bp.handle, stock: stock, showFoldLines: false)
            for id in ["HS1", "HS2", "EC", "GT"] { handle.setFold(id, progress: 1) }
            handle.setFold("HT", progress: 0.55)
            handle.highlight("GT", color: Palette.mint)
            root.addChildNode(handle.root)
            out["guide.5"] = snap(root, target: V3(2.3, 0.8, -0.3), distance: 11, polar: 0.8, azimuth: -0.3, size: size, mat: true)
        }
        // 6. Fold the blade.
        do {
            let root = SCNNode()
            let blade = PieceNode(def: bp.blade, stock: stock, showFoldLines: false)
            blade.setAngles(bp.bladeAngles(1))
            blade.pose = bp.bladeRootPose(1)
            blade.setCrease("BL", 1)
            root.addChildNode(blade.root)
            let bead = GlueBeadNode(localPoints: bp.tangGluePath, localNormal: V3(0, 1, 0), toWorld: blade.worldPose(of: "BU"))
            bead.setProgress(bead.path.length)
            bead.settle()
            blade.panelNodes["BU"]?.addChildNode(bead.root)
            out["guide.6"] = snap(root, target: V3(-1.9, 0.2, 0), distance: 15, polar: 0.78, azimuth: -0.3, size: size, mat: true)
        }
        // 7. Connect the pieces.
        do {
            let root = SCNNode()
            let handle = PieceNode(def: bp.handle, stock: stock, showFoldLines: false)
            handle.foldAll()
            let blade = PieceNode(def: bp.blade, stock: stock, showFoldLines: false)
            blade.setAngles(bp.bladeAngles(1))
            blade.pose = bp.bladeReady.lerp(bp.bladeSeated, 0.45)
            let band = PieceNode(def: bp.guardBand, stock: stock, showFoldLines: false)
            band.setFold("C1", progress: 1)
            band.setFold("C2", progress: 0.5)
            band.pose = bp.guardOnHandle
            for p in [handle, blade, band] { root.addChildNode(p.root) }
            let lifted = SCNNode()
            lifted.position = SCNVector3(0, 1.6, 0)
            lifted.addChildNode(root)
            out["guide.7"] = snap(lifted, target: V3(-1.9, 2.0, 0), distance: 20, polar: 0.72, azimuth: -0.35, size: size, mat: true)
        }
        // 8. Finished.
        out["guide.8"] = snap(turned(KnifeModel.assembled(stock: stock), yaw: 0.3), target: V3(0, 0, 0), distance: 16,
                              polar: 0.75, size: size, mat: false)
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
