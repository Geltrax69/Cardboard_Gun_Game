import SceneKit
import UIKit

/// Cutting along one red line with the craft knife. The knife tip rides the line under
/// the player's finger (never ahead of it, never skipping), the finished stretch turns
/// muted with a kerf, fibres fly, and straying far off the line gets a gentle hint.
@MainActor
final class CutInteraction {
    private unowned let session: CraftSession
    private var engine: GameEngine { session.engine }
    private let line: CutLineNode
    private let knife: SCNNode
    private var tracer: PathTracer
    private let ghost: GhostHint
    private let hintsOn: Bool

    private var done = false
    private var touching = false
    private var advancedThisTouch = false
    private var lastFeed: PathTracer.Feed = .holding
    private var offSince: Double?
    private var lastProgressTime: Double = 0
    private var frameID: Int?
    private var knifeRot = Quat.identity
    private var lift: Float = 0
    private var flakeDistance: Float = 0

    /// Screen tolerance around the line, in points.
    let tolerance: Float = 48

    init(session: CraftSession, line: CutLineNode, knife: SCNNode, showHint: Bool) {
        self.session = session
        self.line = line
        self.knife = knife
        // On small closed loops the end sits next to the start; keep lookahead short so
        // the tool can't jump across the gap.
        self.tracer = PathTracer(path: line.path, lookahead: min(2.0, line.path.length * 0.4))
        self.ghost = GhostHint(engine: session.engine)
        self.hintsOn = showHint
    }

    /// Knife pose with its tip at arc length `d`, handle trailing behind and raised.
    static func knifePose(tip: V3, tangent: V3, lift: Float = 0) -> Pose {
        var back = V3(-tangent.x, 0, -tangent.z)
        if back.len < 1e-4 { back = V3(1, 0, 1) }
        back = back.unit
        let yaw = atan2(-back.z, back.x)
        let rot = Quat(axis: up3, angle: yaw) * Quat(axis: V3(0, 0, 1), angle: radians(42))
        return Pose(rot: rot, pos: tip + V3(0, lift, 0))
    }

    func run() async throws {
        let tw = session.tw
        line.setProgress(tracer.progress)
        // Pick the knife up and set it on the start of the line.
        let startPose = CutInteraction.knifePose(tip: tracer.head, tangent: tracer.tangent)
        let from = knife.pose
        let hover = Pose(rot: startPose.rot, pos: startPose.pos + V3(0, 1.2, 0))
        try await tw.tween(0.35, ease: .inOutCubic) { [knife] k in
            knife.setPose(from.lerp(hover, k))
        }
        try await tw.tween(0.14, ease: .inQuad) { [knife] k in
            knife.setPose(hover.lerp(startPose, k))
        }
        knifeRot = startPose.rot
        lastProgressTime = engine.time

        engine.pointerHandler = { [weak self] phase, p in self?.pointer(phase, p) }
        frameID = engine.onFrame { [weak self] dt in self?.frame(dt) }
        if hintsOn { showGhost() }
        defer { finish() }

        try await tw.until { [weak self] in self?.done ?? true }

        // Lift the knife off the board.
        let end = knife.pose
        try await tw.tween(0.18, ease: .outQuad) { [knife] k in
            knife.setPose(Pose(rot: end.rot, pos: end.pos + V3(0, 0.7 * k, 0)))
        }
    }

    private func finish() {
        engine.pointerHandler = nil
        engine.removeFrameHandler(frameID)
        frameID = nil
        ghost.hide()
        line.setActive(false)
    }

    private func showGhost() {
        let a = tracer.progress
        let b = min(line.path.length, a + 2.4)
        ghost.show(along: line.path.slice(a, b), duration: 1.2)
    }

    // MARK: Input

    private func pointer(_ phase: PointerPhase, _ p: V2) {
        switch phase {
        case .began:
            touching = true
            advancedThisTouch = false
            ghost.hide()
            feed(p)
        case .moved:
            if touching { feed(p) }
        case .ended, .cancelled:
            if touching, !advancedThisTouch, case .offPath = lastFeed {
                session.hint()
            }
            touching = false
            offSince = nil
        }
    }

    private func feed(_ p: V2) {
        let orbit = engine.rig.orbit
        let before = tracer.progress
        let result = tracer.feed(finger: p, tolerance: tolerance, project: { orbit.screen($0) })
        lastFeed = result
        switch result {
        case .advanced:
            advancedThisTouch = true
            offSince = nil
            lastProgressTime = engine.time
            line.setProgress(tracer.progress)
            let moved = tracer.progress - before
            flakeDistance += moved
            if flakeDistance > 0.28 {
                flakeDistance = 0
                engine.particles.flakes(at: tracer.head, count: 2, direction: tracer.tangent)
            }
            if tracer.isDone { done = true }
        case .holding:
            offSince = nil
        case .offPath:
            let now = engine.time
            if let since = offSince {
                if now - since > 0.35 {
                    session.hint()
                    offSince = now + 2
                }
            } else {
                offSince = now
            }
        }
    }

    // MARK: Frame

    private func frame(_ dt: Double) {
        let target = CutInteraction.knifePose(tip: tracer.head, tangent: tracer.tangent)
        let k = Float(1 - exp(-14 * dt))
        knifeRot = knifeRot.slerp(target.rot, k)
        // Hover a touch above the line while idle so it reads as "pick me up".
        let idle = !touching && !done
        lift += ((idle ? 0.12 + 0.06 * Float(sin(engine.time * 4)) : 0) - lift) * Float(min(1, dt * 10))
        knife.setPose(Pose(rot: knifeRot, pos: target.pos + V3(0, lift, 0)))
        line.setActive(!done, time: engine.time)
        // Remind idle players where to swipe.
        if hintsOn, !touching, !ghost.isShowing, engine.time - lastProgressTime > 5 {
            showGhost()
            lastProgressTime = engine.time
        }
    }
}
