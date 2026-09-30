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
        var out: [String: UIImage] = [:]

        out["tool.knife"] = snap(turned(Props.craftKnife(), yaw: 0.55), target: V3(1.8, 0.15, -1.1), distance: 11, polar: 0.62)
        out["tool.scissors"] = snap(turned(Props.scissors(), yaw: 0.7), target: V3(0.4, 0.1, -0.3), distance: 9, polar: 0.62)
        let glue = SCNNode()
        let bottle = Props.glueBottle()
        bottle.eulerAngles.x = .pi
        bottle.position = SCNVector3(0, 2.91, 0)
        glue.addChildNode(bottle)
        out["tool.glue"] = snap(glue, target: V3(0, 1.4, 0), distance: 11, polar: 1.0)
        out["tool.ruler"] = snap(turned(Props.ruler(), yaw: 0.78), target: V3(0, 0.06, 0), distance: 17, polar: 0.62)
        out["tool.pencil"] = snap(turned(Props.pencil(), yaw: 0.62), target: V3(1.7, 0, -1.2), distance: 11, polar: 0.62)
        out["tool.tape"] = snap(Props.tapeRoll(), target: V3(0, 0.3, 0), distance: 9, polar: 0.72)

        out["project.knife"] = snap(turned(KnifeModel.assembled(stock: stock), yaw: 0.28), target: V3(0, 0, 0), distance: 22, polar: 0.72)
        out["project.pistol"] = snap(turned(Props.pistolModel(), yaw: 0.25), target: V3(0.3, 1.2, 0), distance: 14, polar: 1.05)
        out["project.rifle"] = snap(turned(Props.rifleModel(), yaw: 0.22), target: V3(-0.5, 1.4, 0), distance: 23, polar: 1.05)
        out["project.more"] = snap(turned(Props.crateModel(), yaw: 0.6), target: V3(0, 1.1, 0), distance: 11, polar: 0.9)
        images = out
    }

    private func turned(_ node: SCNNode, yaw: Float) -> SCNNode {
        let holder = SCNNode()
        node.eulerAngles.y = yaw
        holder.addChildNode(node)
        return holder
    }

    private func snap(_ model: SCNNode, target: V3, distance: Float, polar: Float, azimuth: Float = 0,
                      size: CGSize = CGSize(width: 360, height: 360)) -> UIImage? {
        guard let renderer else { return nil }
        let scene = SCNScene()
        scene.background.contents = IconFactory.cardColor
        scene.rootNode.addChildNode(model)

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
