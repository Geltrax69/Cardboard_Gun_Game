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
    /// Camera chosen by the game (each step's framing).
    private(set) var base = OrbitCamera()
    /// Player orbit on top of the base camera (two-finger drag / pinch).
    private(set) var userYaw: Float = 0
    private(set) var userPitch: Float = 0
    private(set) var userZoom: Float = 1
    /// Fractions of the screen covered by HUD at the top and bottom.
    var safeTop: Float = 0.17
    var safeBottom: Float = 0.15
    private var shake: Float = 0

    static let minPolar: Float = 0.03
    static let maxPolar: Float = 1.35
    static let zoomRange: ClosedRange<Float> = 0.45...2.2

    /// The camera actually rendered (base + player orbit). Input, overlays and toasts all
    /// project through this, so they stay correct while the view is rotated.
    var orbit: OrbitCamera {
        var o = base
        o.azimuth = base.azimuth + userYaw
        o.polar = clampf(base.polar + userPitch, CameraRig.minPolar, CameraRig.maxPolar)
        o.distance = base.distance * userZoom
        return o
    }

    /// True while the player has turned or zoomed away from the step's framing.
    var isUserAdjusted: Bool {
        abs(userYaw) > 0.02 || abs(userPitch) > 0.02 || abs(userZoom - 1) > 0.02
    }

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
        base.viewSize = V2(Float(size.width), Float(size.height))
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
        var o = base
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
        n.viewSize = base.viewSize
        base = n
        userYaw = 0
        userPitch = 0
        userZoom = 1
        apply()
    }

    /// Scripted move to a new framing; any player orbit eases back to neutral on the way.
    func move(to target: OrbitCamera, duration: Double = 1.1, ease: Ease = .inOutCubic, tweener: Tweener) async throws {
        let step = transition(to: target)
        try await tweener.tween(duration, ease: ease) { k in step(k) }
    }

    /// Starts a camera move without waiting for it.
    func glide(to target: OrbitCamera, duration: Double = 1.1, ease: Ease = .inOutCubic, tweener: Tweener) {
        let step = transition(to: target)
        tweener.start(duration, ease: ease, tag: "camera") { k in step(k) }
    }

    private func transition(to target: OrbitCamera) -> (Float) -> Void {
        let from = base
        let yaw0 = userYaw, pitch0 = userPitch, zoom0 = userZoom
        return { [weak self] k in
            guard let self else { return }
            var o = from.lerp(target, k)
            o.viewSize = self.base.viewSize
            self.base = o
            self.userYaw = yaw0 * (1 - k)
            self.userPitch = pitch0 * (1 - k)
            self.userZoom = zoom0 + (1 - zoom0) * k
            self.apply()
        }
    }

    // MARK: Player orbit

    /// Rotates the view by a finger movement in points (drag right turns the board right,
    /// drag down tips it toward you).
    func userRotate(dx: Float, dy: Float) {
        userYaw -= dx * 0.0085
        let pitch = userPitch + dy * 0.0065
        userPitch = clampf(pitch, CameraRig.minPolar - base.polar, CameraRig.maxPolar - base.polar)
        apply()
    }

    /// Pinch: scale > 1 zooms in.
    func userPinch(_ scale: Float) {
        guard scale > 0.01 else { return }
        userZoom = clampf(userZoom / scale, CameraRig.zoomRange.lowerBound, CameraRig.zoomRange.upperBound)
        apply()
    }

    /// Eases back to the step's own framing.
    func resetUserView(tweener: Tweener, duration: Double = 0.6) {
        let yaw0 = userYaw, pitch0 = userPitch, zoom0 = userZoom
        tweener.start(duration, ease: .inOutCubic, tag: "cameraReset") { [weak self] k in
            guard let self else { return }
            self.userYaw = yaw0 * (1 - k)
            self.userPitch = pitch0 * (1 - k)
            self.userZoom = zoom0 + (1 - zoom0) * k
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
        let o = orbit
        var eye = o.eye
        if shake > 0 {
            let k = shake * shake * 0.25
            eye += o.right * Float.random(in: -k...k) + o.up * Float.random(in: -k...k)
        }
        node.setPose(Pose(rot: o.orientation, pos: eye))
    }
}
