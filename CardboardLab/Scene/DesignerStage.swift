import SceneKit
import UIKit

/// Free Craft's live preview: the finished weapon floating above the mat, rebuilt (at
/// most a dozen times a second) whenever the design changes. Drags turn it freely in 3D
/// about the camera's axes, so it can be seen from any side, including underneath; a
/// flick keeps it spinning, and after a few idle seconds it drifts into a slow turntable
/// spin.
@MainActor
final class DesignerStage {
    let root = SCNNode()
    private let turntable = SCNNode()
    private let spot: SCNNode
    private var model: SCNNode?
    private var pending: (WeaponDesign, CardboardStock)?
    private var lastBuild: Double = -1
    private static let restOrientation = Quat(axis: up3, angle: 0.6)
    private var orientation = DesignerStage.restOrientation
    /// World-space angular velocity (axis × rad/s).
    private var spin = V3(0, 0, 0)
    private var dragging = false
    private var lastTouch: Double = -100
    private var lastDragTime: Double = 0
    private var resetting = false
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

    func beginDrag(time: Double) {
        dragging = true
        resetting = false
        spin = V3(0, 0, 0)
        lastTouch = time
        lastDragTime = time
    }

    /// Turns the weapon by a finger movement (points): sideways drags turn it about the
    /// camera's up axis, vertical drags tip it toward or away from the viewer.
    func drag(dx: Float, dy: Float, camera: OrbitCamera, time: Double) {
        let k: Float = 0.011
        let axis = camera.up * dx + camera.right * dy
        let len = axis.len
        guard len > 1e-4 else { return }
        let angle = len * k
        orientation = (Quat(axis: axis / len, angle: angle) * orientation).normalized
        let dt = Float(max(time - lastDragTime, 1.0 / 120))
        spin = mix3(spin, axis / len * min(angle / dt, 12), 0.5)
        lastDragTime = time
        lastTouch = time
    }

    func endDrag(time: Double) {
        dragging = false
        lastTouch = time
        // A finger that stopped before lifting shouldn't fling.
        if time - lastDragTime > 0.08 { spin = V3(0, 0, 0) }
    }

    /// Eases back to the starting angle.
    func resetOrientation() {
        resetting = true
        spin = V3(0, 0, 0)
    }

    func update(time: Double, dt: Double) {
        guard !root.isHidden else { return }
        if let (design, stock) = pending, time - lastBuild > 0.08 {
            pending = nil
            lastBuild = time
            rebuild(design, stock: stock)
        }
        if resetting {
            orientation = orientation.slerp(DesignerStage.restOrientation, Float(min(1, dt * 6)))
            let r = DesignerStage.restOrientation
            let dot = orientation.x * r.x + orientation.y * r.y + orientation.z * r.z + orientation.w * r.w
            if abs(dot) > 0.99999 { resetting = false }
            lastTouch = time
        } else if !dragging {
            // Fling, then drift into a slow turntable spin after a few idle seconds.
            let idle = time - lastTouch
            let drift = idle > 3 ? up3 * (0.35 * Float(min(1, (idle - 3) / 1.5))) : V3(0, 0, 0)
            spin = mix3(spin, drift, Float(min(1, dt * (idle > 3 ? 1.5 : 2.2))))
            let w = spin.len
            if w > 1e-4 {
                orientation = (Quat(axis: spin / w, angle: w * Float(dt)) * orientation).normalized
            }
        }
        pop += (1 - pop) * Float(min(1, dt * 14))
        let bob = V3(0, 0.12 * Float(sin(time * 1.6)), 0)
        turntable.setPose(Pose(rot: orientation, pos: DesignerStage.center + bob))
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
