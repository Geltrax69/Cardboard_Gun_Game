import SceneKit
import UIKit

/// Free Craft's live preview: the finished weapon floating above the mat on a slow
/// turntable, rebuilt (at most a dozen times a second) whenever the design changes.
/// One-finger drags spin it.
@MainActor
final class DesignerStage {
    let root = SCNNode()
    private let turntable = SCNNode()
    private let spot: SCNNode
    private var model: SCNNode?
    private var pending: (WeaponDesign, CardboardStock)?
    private var lastBuild: Double = -1
    private var yaw: Float = 0.6
    private var dragging = false
    private var pop: Float = 1
    /// Longest side of the weapon on show (for camera framing).
    private(set) var span: Float = 11

    static let center = V3(0, 2.6, 0.4)

    init() {
        root.name = "designer"
        root.isHidden = true
        root.addChildNode(turntable)
        // A soft ring on the mat under the turntable.
        var ring = MeshData()
        let pts = (0...40).map { i -> V3 in
            let a = Float(i) / 40 * 2 * .pi
            return V3(cos(a) * 4.2, 0.015, sin(a) * 4.2 + DesignerStage.center.z)
        }
        MeshBuilder.ribbon(pts, width: 0.22, into: &ring)
        spot = SceneBridge.node(ring, [Mat.unlit(Palette.matLine)], name: "designerSpot")
        spot.castsShadow = false
        root.addChildNode(spot)
    }

    func show() {
        root.isHidden = false
        root.opacity = 1
    }

    func hide() {
        root.isHidden = true
        model?.removeFromParentNode()
        model = nil
        pending = nil
    }

    /// Queues a rebuild for the next frame slot.
    func request(_ design: WeaponDesign, stock: CardboardStock) {
        pending = (design, stock)
    }

    func setDragging(_ on: Bool) { dragging = on }

    func drag(dx: Float) { yaw += dx * 0.012 }

    func update(time: Double, dt: Double) {
        guard !root.isHidden else { return }
        if let (design, stock) = pending, time - lastBuild > 0.08 {
            pending = nil
            lastBuild = time
            rebuild(design, stock: stock)
        }
        if !dragging { yaw += Float(dt) * 0.35 }
        pop += (1 - pop) * Float(min(1, dt * 14))
        let bob = V3(0, 0.12 * Float(sin(time * 1.6)), 0)
        turntable.setPose(Pose(rot: Quat(axis: up3, angle: yaw), pos: DesignerStage.center + bob))
        turntable.setUniformScale(pop)
    }

    private func rebuild(_ design: WeaponDesign, stock: CardboardStock) {
        let fresh = WeaponModel.assembled(design, stock: stock)
        model?.removeFromParentNode()
        turntable.addChildNode(fresh)
        model = fresh
        span = WeaponModel.span(design, stock: stock)
        pop = 0.94
    }
}
