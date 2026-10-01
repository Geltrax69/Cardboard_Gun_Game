import SceneKit
import UIKit

/// Drives the SceneKit camera from an `OrbitCamera`. Views:
///  • top-down for cutting and planning (tiny tilt so the cardboard thickness shows)
///  • three-quarter for folding, so flaps visibly rise out of the flat plane
@MainActor
final class CameraRig {
    enum Shot {
        case topDown, threeQuarter, hero, menu
        /// Low, from the player's side: for drawing on the +z faces of a held build.
        case side
        /// Free mode: tilted enough to see builds in 3D, flat enough to draw on sheets.
        case workshop

        var polar: Float {
            switch self {
            case .topDown: return 0.12
            case .threeQuarter: return 0.78
            case .hero: return 0.62
            case .menu: return 0.52
            case .side: return 1.05
            case .workshop: return 0.5
            }
        }

        var azimuth: Float {
            switch self {
            case .topDown: return 0
            case .threeQuarter: return -0.32
            case .hero: return 0.42
            case .menu: return 0
            case .side: return -0.12
            case .workshop: return -0.18
            }
        }
    }

    let node = SCNNode()
    let camera = SCNCamera()
    /// Camera chosen by the game (each step's framing).
    private(set) var base = OrbitCamera()
    /// Player orbit on top of the base camera (two-finger drag / pinch / hand mode).
    private(set) var userYaw: Float = 0
    private(set) var userPitch: Float = 0
    private(set) var userZoom: Float = 1
    /// Player move of the orbit centre (zooming toward a point, panning, walking).
    private(set) var userShift = V3(0, 0, 0)
    /// Hand mode: the camera may dip lower and fly in past the closest zoom.
    var exploring = false
    /// Fractions of the screen covered by HUD at the top and bottom.
    var safeTop: Float = 0.17
    var safeBottom: Float = 0.15
    private var shake: Float = 0

    static let minPolar: Float = 0.03
    static let maxPolar: Float = 1.35
    /// Hand mode lets the camera come down almost to table level.
    static let maxExplorePolar: Float = 1.52
    /// Closest the camera gets to the point it orbits.
    static let minDistance: Float = 1.6
    /// How far out the player can zoom, as a multiple of the step's framing.
    static let maxZoom: Float = 4
    /// The eye never goes below this height (the table top is y = 0).
    static let minEyeHeight: Float = 0.35

    private var maxPolarNow: Float { exploring ? CameraRig.maxExplorePolar : CameraRig.maxPolar }

    /// The camera actually rendered (base + player orbit). Input, overlays and toasts all
    /// project through this, so they stay correct while the view is rotated.
    var orbit: OrbitCamera {
        var o = base
        o.target = base.target + userShift
        o.azimuth = base.azimuth + userYaw
        o.polar = clampf(base.polar + userPitch, CameraRig.minPolar, maxPolarNow)
        o.distance = base.distance * userZoom
        return o
    }

    /// True while the player has turned, zoomed or moved away from the step's framing.
    var isUserAdjusted: Bool {
        abs(userYaw) > 0.02 || abs(userPitch) > 0.02 || abs(userZoom - 1) > 0.02 || userShift.len > 0.05
    }

    init() {
        camera.fieldOfView = 30
        camera.projectionDirection = .vertical
        // Near plane close in, so the camera can get right up to a build.
        camera.zNear = 0.1
        camera.zFar = 400
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
        userShift = V3(0, 0, 0)
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
        let yaw0 = userYaw, pitch0 = userPitch, zoom0 = userZoom, shift0 = userShift
        return { [weak self] k in
            guard let self else { return }
            var o = from.lerp(target, k)
            o.viewSize = self.base.viewSize
            self.base = o
            self.userYaw = yaw0 * (1 - k)
            self.userPitch = pitch0 * (1 - k)
            self.userZoom = zoom0 + (1 - zoom0) * k
            self.userShift = shift0 * (1 - k)
            self.apply()
        }
    }

    // MARK: Player orbit

    /// Rotates the view by a finger movement in points (drag right turns the board right,
    /// drag down tips it toward you).
    func userRotate(dx: Float, dy: Float) {
        userYaw -= dx * 0.0085
        let pitch = userPitch + dy * 0.0065
        userPitch = clampf(pitch, CameraRig.minPolar - base.polar, maxPolarNow - base.polar)
        keepEyeAboveTable()
        apply()
    }

    /// Slides the view across the table by a finger movement (points): the table
    /// follows the finger.
    func userPan(dx: Float, dy: Float) {
        let o = orbit
        let k = o.unitsPerPoint(atDepth: o.distance)
        var ahead = V3(o.up.x - o.back.x, 0, o.up.z - o.back.z)
        ahead = ahead.len > 1e-4 ? ahead.unit : V3(0, 0, -1)
        userShift = userShift - o.right * (dx * k) + ahead * (dy * k)
        apply()
    }

    /// Moves the view in the screen plane (two fingers in hand mode): whatever is under
    /// the fingers follows them.
    func userPanScreen(dx: Float, dy: Float) {
        let o = orbit
        let k = o.unitsPerPoint(atDepth: o.distance)
        userShift = userShift - o.right * (dx * k) + o.up * (dy * k)
        keepEyeAboveTable()
        apply()
    }

    /// Pinch (scale > 1 zooms in) toward a world point, which stays under the fingers.
    /// Zooming in past the closest distance flies forward instead when exploring, so the
    /// camera can travel into and through a build.
    func userZoom(by scale: Float, toward focus: V3?) {
        guard scale > 0.01 else { return }
        let o = orbit
        let maxD = max(base.distance * CameraRig.maxZoom, 40)
        let wanted = o.distance / scale
        let d = clampf(wanted, CameraRig.minDistance, maxD)
        let ratio = d / o.distance
        if let p = focus {
            // Scaling the whole camera about p keeps p at the same spot on screen.
            let target = p + (o.target - p) * ratio
            userShift = userShift + (target - o.target)
        }
        if exploring, wanted < CameraRig.minDistance {
            let dir = focus.map { ($0 - o.eye).len > 1e-3 ? ($0 - o.eye).unit : o.forward } ?? o.forward
            userShift = userShift + dir * (CameraRig.minDistance - wanted)
        }
        userZoom = d / max(base.distance, 1e-3)
        keepEyeAboveTable()
        apply()
    }

    /// Walks the camera: `move.z` forward along the table, `move.x` sideways, `move.y` up,
    /// each −1…1; speed grows with how far out the camera is.
    func userWalk(_ move: V3, dt: Float) {
        let o = orbit
        var ahead = V3(o.forward.x, 0, o.forward.z)
        if ahead.len < 0.2 { ahead = V3(o.up.x, 0, o.up.z) }
        ahead = ahead.len > 1e-4 ? ahead.unit : V3(0, 0, -1)
        let speed = max(3, o.distance * 0.8) * dt
        userShift = userShift + (ahead * move.z + o.right * move.x + V3(0, 1, 0) * move.y) * speed
        keepEyeAboveTable()
        apply()
    }

    /// Glides the view so it orbits `point`, a little closer in (double tap in hand mode).
    func focus(on point: V3, tweener: Tweener) {
        let o = orbit
        let shift0 = userShift, zoom0 = userZoom
        let shift1 = userShift + (point - o.target)
        let d1 = clampf(o.distance * 0.6, CameraRig.minDistance * 1.5, max(base.distance * CameraRig.maxZoom, 40))
        let zoom1 = d1 / max(base.distance, 1e-3)
        tweener.start(0.5, ease: .inOutCubic, tag: "cameraFocus") { [weak self] k in
            guard let self else { return }
            self.userShift = mix3(shift0, shift1, k)
            self.userZoom = mixf(zoom0, zoom1, k)
            self.keepEyeAboveTable()
            self.apply()
        }
    }

    /// The camera never dips under the table.
    private func keepEyeAboveTable() {
        let low = orbit.eye.y
        if low < CameraRig.minEyeHeight { userShift.y += CameraRig.minEyeHeight - low }
    }

    /// Eases back to the step's own framing.
    func resetUserView(tweener: Tweener, duration: Double = 0.6) {
        let yaw0 = userYaw, pitch0 = userPitch, zoom0 = userZoom, shift0 = userShift
        tweener.start(duration, ease: .inOutCubic, tag: "cameraReset") { [weak self] k in
            guard let self else { return }
            self.userYaw = yaw0 * (1 - k)
            self.userPitch = pitch0 * (1 - k)
            self.userZoom = zoom0 + (1 - zoom0) * k
            self.userShift = shift0 * (1 - k)
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
