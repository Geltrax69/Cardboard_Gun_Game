import SceneKit
import UIKit

/// Folding a flap by dragging it. The flap rotates about its crease so that its grab
/// point stays under the finger (a 1-D search over fold progress in screen space, so it
/// works from any camera angle). A curved blue arrow shows where to go; releasing past
/// ~70% snaps it home ("Perfect fold"), otherwise it springs back.
@MainActor
final class FoldInteraction {
    struct Spec {
        /// World position of the grab point at fold progress p.
        var handle: (Float) -> V3
        /// World point on the crease near the grab point (the arrow bows away from it).
        var pivot: (Float) -> V3
        /// World outline of the flap at progress p (for touch hit-testing).
        var outline: (Float) -> [V3]
        /// Poses the flap at progress p.
        var apply: (Float) -> Void
        var from: Float = 0
        var to: Float = 1
        var snapAt: Float = 0.7
        var arrowOffset: Float = 0.55
        /// Fixed on-screen drag direction (for folds whose grab point barely moves).
        var screenDirection: V2? = nil
    }

    private unowned let session: CraftSession
    private var engine: GameEngine { session.engine }
    private let spec: Spec
    private let ghost: GhostHint
    private let hintsOn: Bool
    private var p: Float
    private var dragging = false
    private var lastFinger = V2(0, 0)
    /// Minimum finger travel (points) for a whole fold, so small flaps aren't twitchy.
    private let minThrow: Float = 160
    private var done = false
    private var settling = false
    private var frameID: Int?
    private var lastActivity: Double = 0

    init(session: CraftSession, spec: Spec, showHint: Bool) {
        self.session = session
        self.spec = spec
        self.p = spec.from
        self.ghost = GhostHint(engine: session.engine)
        self.hintsOn = showHint
    }

    func run() async throws {
        spec.apply(p)
        lastActivity = engine.time
        engine.pointerHandler = { [weak self] phase, pt in self?.pointer(phase, pt) }
        frameID = engine.onFrame { [weak self] _ in self?.frame() }
        if hintsOn { showGhost() }
        defer { finish() }
        try await session.tw.until { [weak self] in self?.done ?? true }
    }

    private func finish() {
        engine.pointerHandler = nil
        engine.removeFrameHandler(frameID)
        frameID = nil
        ghost.hide()
        engine.overlay.setArrow(nil)
    }

    private func showGhost() {
        let pts = stride(from: spec.from, through: spec.from + (spec.to - spec.from) * 0.85, by: (spec.to - spec.from) / 12)
            .map { spec.handle($0) }
        ghost.show(along: pts, duration: 1.3)
    }

    // MARK: Input

    private func grabbed(_ finger: V2) -> Bool {
        let orbit = engine.rig.orbit
        let outline = spec.outline(p).map { orbit.screen($0) }
        if outline.count > 2 && Poly.contains(outline, finger) { return true }
        return orbit.screen(spec.handle(p)).dist(finger) < 110
    }

    private func pointer(_ phase: PointerPhase, _ finger: V2) {
        guard !settling, !done else { return }
        switch phase {
        case .began:
            ghost.hide()
            lastActivity = engine.time
            if grabbed(finger) {
                dragging = true
                lastFinger = finger
            } else {
                session.hint("Drag the highlighted flap along the blue arrow")
            }
        case .moved:
            guard dragging else { return }
            lastActivity = engine.time
            let delta = finger - lastFinger
            lastFinger = finger
            p = clampf(p + progressDelta(for: delta), min(spec.from, spec.to), max(spec.from, spec.to))
            spec.apply(p)
        case .ended, .cancelled:
            guard dragging else { return }
            dragging = false
            let progress = (p - spec.from) / (spec.to - spec.from)
            if progress >= spec.snapAt {
                settle(to: spec.to, success: true)
            } else {
                settle(to: spec.from, success: false)
                if progress > 0.05 || hintsOn { session.hint("Almost! Drag the flap all the way along the arrow") }
            }
        }
    }

    private func settle(to target: Float, success: Bool) {
        settling = true
        let start = p
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.session.tw.tween(success ? 0.22 : 0.35, ease: success ? .outCubic : .outBack) { [weak self] k in
                    guard let self else { return }
                    self.p = start + (target - start) * k
                    self.spec.apply(self.p)
                }
            } catch {
                return
            }
            self.settling = false
            if success {
                self.engine.rig.addShake(0.06)
                self.engine.particles.sparks(at: self.spec.pivot(target), count: 10)
                self.done = true
            }
        }
    }

    /// Geared drag: the flap follows the finger along its on-screen direction of motion,
    /// 1:1 where that motion is large, and at least `minThrow` points per full fold.
    private func progressDelta(for delta: V2) -> Float {
        let orbit = engine.rig.orbit
        let lo = min(spec.from, spec.to), hi = max(spec.from, spec.to)
        let span = spec.to - spec.from
        if let dir = spec.screenDirection {
            return delta.dotp(dir.unit) / (minThrow / max(abs(span), 1e-4)) * (span >= 0 ? 1 : -1)
        }
        let a = clampf(p - 0.04 * span, lo, hi), b = clampf(p + 0.04 * span, lo, hi)
        var tangent = orbit.screen(spec.handle(b)) - orbit.screen(spec.handle(a))
        var speed = tangent.len / max(abs(b - a), 1e-4)
        if tangent.len < 1 {
            tangent = orbit.screen(spec.handle(spec.to)) - orbit.screen(spec.handle(p))
            speed = 0
        }
        guard tangent.len > 1e-3 else { return 0 }
        let along = delta.dotp(tangent.unit)
        // `speed` is points per unit of progress; a full fold spans |span| units.
        return along / max(speed, minThrow / max(abs(span), 1e-4))
    }

    // MARK: Frame

    private func frame() {
        guard !done else { return }
        // Curved arrow from the flap's current position to where it should end up.
        let orbit = engine.rig.orbit
        let start = p + (spec.to - p) * 0.06
        var pts: [CGPoint] = []
        let steps = 16
        for i in 0...steps {
            let q = start + (spec.to - start) * Float(i) / Float(steps)
            let h = spec.handle(q)
            let pivot = spec.pivot(q)
            let r = (h - pivot).len
            let out = (h - pivot).unit
            let s = orbit.screen(pivot + out * max(r + spec.arrowOffset, 1.4) + V3(0, 0.15, 0))
            pts.append(CGPoint(x: CGFloat(s.x), y: CGFloat(s.y)))
        }
        let remaining = abs(spec.to - p) / max(abs(spec.to - spec.from), 1e-4)
        engine.overlay.setArrow(remaining > 0.04 ? pts : nil, alpha: dragging ? 0.55 : 1)
        if hintsOn, !dragging, !settling, !ghost.isShowing, engine.time - lastActivity > 5 {
            showGhost()
            lastActivity = engine.time
        }
    }
}

extension FoldInteraction.Spec {
    /// Spec for folding `panel` of a piece about its hinge. `grab` is a point on the
    /// flap in flat piece space (usually the middle of its far edge).
    @MainActor
    static func panel(_ piece: PieceNode, _ panel: String, grab: V3) -> FoldInteraction.Spec {
        let def = piece.def
        let panelDef = def.panel(panel)
        let hinge = panelDef?.hinge
        let parent = panelDef?.parent ?? panel
        let t = piece.stock.thickness
        let target = hinge?.signedTarget ?? 0
        func poseAt(_ p: Float) -> Pose {
            var rig = piece.rig
            rig.angles[panel] = target * p
            return piece.pose * rig.pose(of: panel)
        }
        return FoldInteraction.Spec(
            handle: { poseAt($0).apply(grab) },
            pivot: { _ in
                let mid = hinge?.midpoint ?? V2(0, 0)
                return piece.worldPose(of: parent).apply(mid.onMat(t))
            },
            outline: { p in
                let pose = poseAt(p)
                return (panelDef?.outline ?? []).map { pose.apply($0.onMat(t)) }
            },
            apply: { piece.setFold(panel, progress: $0) }
        )
    }
}
