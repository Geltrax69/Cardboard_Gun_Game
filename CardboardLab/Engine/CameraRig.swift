import SceneKit
import UIKit

/// Drives the SceneKit camera from an `OrbitCamera`. Views:
///  • top-down for cutting and planning (tiny tilt so the cardboard thickness shows)
///  • three-quarter for folding, so flaps visibly rise out of the flat plane
@MainActor
final class CameraRig {
    enum Shot {
        case topDown, threeQuarter, hero, menu

        var polar: Float {
            switch self {
            case .topDown: return 0.12
            case .threeQuarter: return 0.78
            case .hero: return 0.62
            case .menu: return 0.52
            }
        }

        var azimuth: Float {
            switch self {
            case .topDown: return 0
            case .threeQuarter: return -0.32
            case .hero: return 0.42
            case .menu: return 0
            }
        }
    }

    let node = SCNNode()
    let camera = SCNCamera()
    private(set) var orbit = OrbitCamera()
    /// Fractions of the screen covered by HUD at the top and bottom.
    var safeTop: Float = 0.17
    var safeBottom: Float = 0.15
    private var shake: Float = 0

    init() {
        camera.fieldOfView = 30
        camera.projectionDirection = .vertical
        camera.zNear = 0.5
        camera.zFar = 500
        node.camera = camera
        node.name = "camera"
        apply()
    }

    func setViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        orbit.viewSize = V2(Float(size.width), Float(size.height))
        apply()
    }

    /// Screen fractions covered by UI on each side.
    struct Insets {
        var top: Float, bottom: Float, left: Float, right: Float
    }

    var hudInsets: Insets { Insets(top: safeTop, bottom: safeBottom, left: 0.02, right: 0.02) }

    /// Orbit that frames a `size` (w × d) region of the mat centred on `center`, placed in
    /// the middle of the area not covered by UI.
    func framing(center: V3, size: V2, view: Shot, zoom: Float = 1, insets: Insets? = nil) -> OrbitCamera {
        let ins = insets ?? hudInsets
        var o = orbit
        o.polar = view.polar
        o.azimuth = view.azimuth
        o.distance = o.fitDistance(width: size.x, depth: size.y, polar: view.polar,
                                   safeTop: ins.top, safeBottom: ins.bottom, safeSide: (ins.left + ins.right) / 2) * zoom
        let worldH = 2 * o.distance * tan(o.fovY / 2)
        let worldW = worldH * o.aspect
        o.target = center + o.up * ((ins.top - ins.bottom) / 2 * worldH) + o.right * ((ins.right - ins.left) / 2 * worldW)
        return o
    }

    func set(_ o: OrbitCamera) {
        var n = o
        n.viewSize = orbit.viewSize
        orbit = n
        apply()
    }

    func move(to target: OrbitCamera, duration: Double = 1.1, ease: Ease = .inOutCubic, tweener: Tweener) async throws {
        let from = orbit
        let to = target
        try await tweener.tween(duration, ease: ease) { [weak self] k in
            guard let self else { return }
            var o = from.lerp(to, k)
            o.viewSize = self.orbit.viewSize
            self.orbit = o
            self.apply()
        }
    }

    /// Starts a camera move without waiting for it.
    func glide(to target: OrbitCamera, duration: Double = 1.1, ease: Ease = .inOutCubic, tweener: Tweener) {
        let from = orbit
        let to = target
        tweener.start(duration, ease: ease, tag: "camera") { [weak self] k in
            guard let self else { return }
            var o = from.lerp(to, k)
            o.viewSize = self.orbit.viewSize
            self.orbit = o
            self.apply()
        }
    }

    func addShake(_ amount: Float) {
        shake = min(0.5, shake + amount)
    }

    func update(_ dt: Double) {
        if shake > 0 {
            shake = max(0, shake - Float(dt) * 2.2)
            apply()
        }
    }

    func apply() {
        var eye = orbit.eye
        if shake > 0 {
            let k = shake * shake * 0.25
            eye += orbit.right * Float.random(in: -k...k) + orbit.up * Float.random(in: -k...k)
        }
        node.setPose(Pose(rot: orbit.orientation, pos: eye))
    }
}
