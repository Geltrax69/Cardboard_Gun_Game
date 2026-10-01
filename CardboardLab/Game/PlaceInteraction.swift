import SceneKit
import UIKit

/// Picking a piece up and dropping it onto its glowing ghost outline. The piece is
/// carried at a hover height under the finger; releasing near the target snaps it into
/// place, releasing elsewhere sets it down with a gentle hint.
@MainActor
final class PlaceInteraction {
    struct Spec {
        /// Current world pose of the carried piece.
        var current: () -> Pose
        /// Applies a world pose to the piece.
        var set: (Pose) -> Void
        /// Pose the piece snaps to.
        var target: Pose
        /// Height of the piece frame while carried.
        var hoverY: Float
        /// World outline of the piece (for touch hit-testing).
        var outline: () -> [V3]
        /// World point near the middle of the piece (for the hint and fallback grab).
        var center: () -> V3
        /// Orientation while carried (defaults to the target orientation).
        var carryRotation: Quat? = nil
        var snapRadius: Float = 1.4
    }

    private unowned let session: CraftSession
    private var engine: GameEngine { session.engine }
    private let spec: Spec
    private let ghostHint: GhostHint
    private let hintsOn: Bool
    private var carrying = false
    private var grabOffset = V3(0, 0, 0)
    private var carried = Pose.identity
    private var restY: Float = 0
    private var done = false
    private var busy = false
    private var frameID: Int?
    private var lastActivity: Double = 0

    init(session: CraftSession, spec: Spec, showHint: Bool) {
        self.session = session
        self.spec = spec
        self.ghostHint = GhostHint(engine: session.engine)
        self.hintsOn = showHint
    }

    func run() async throws {
        carried = spec.current()
        restY = carried.pos.y
        lastActivity = engine.time
        engine.pointerHandler = { [weak self] phase, p in self?.pointer(phase, p) }
        frameID = engine.onFrame { [weak self] _ in self?.frame() }
        if hintsOn { showHint() }
        defer { finish() }
        try await session.tw.until { [weak self] in self?.done ?? true }
    }

    private func finish() {
        engine.pointerHandler = nil
        engine.removeFrameHandler(frameID)
        frameID = nil
        ghostHint.hide()
        engine.overlay.setRing(center: nil)
    }

    private func showHint() {
        let from = spec.center() + V3(0, 0.2, 0)
        let to = spec.target.pos + (from - spec.current().pos)
        ghostHint.show(along: [from, mix3(from, to, 0.5) + V3(0, 0.8, 0), to], duration: 1.4)
    }

    private func grabbed(_ finger: V2) -> Bool {
        let orbit = engine.rig.orbit
        let outline = spec.outline().map { orbit.screen($0) }
        if outline.count > 2 && Poly.contains(outline, finger) { return true }
        return orbit.screen(spec.center()).dist(finger) < 120
    }

    private func pointer(_ phase: PointerPhase, _ finger: V2) {
        guard !busy, !done else { return }
        switch phase {
        case .began:
            ghostHint.hide()
            lastActivity = engine.time
            guard grabbed(finger), let hit = engine.hit(finger, planeY: spec.hoverY) else {
                session.hint("Drag the piece onto its glowing outline")
                return
            }
            carrying = true
            carried = spec.current()
            grabOffset = V3(carried.pos.x - hit.x, 0, carried.pos.z - hit.z)
        case .moved:
            guard carrying, let hit = engine.hit(finger, planeY: spec.hoverY) else { return }
            lastActivity = engine.time
            carried.pos = V3(hit.x + grabOffset.x, carried.pos.y, hit.z + grabOffset.z)
        case .ended, .cancelled:
            guard carrying else { return }
            carrying = false
            let d = V2(carried.pos.x - spec.target.pos.x, carried.pos.z - spec.target.pos.z).len
            if d < spec.snapRadius {
                snap()
            } else {
                drop(quietly: phase == .cancelled)
            }
        }
    }

    private func snap() {
        busy = true
        let from = spec.current()
        let target = spec.target
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.session.tw.tween(0.28, ease: .outCubic) { [weak self] k in
                    self?.spec.set(from.lerp(target, k))
                }
            } catch {
                return
            }
            self.engine.sound.play(.snap)
            self.done = true
        }
    }

    private func drop(quietly: Bool = false) {
        busy = true
        let from = spec.current()
        var to = from
        to.pos.y = restY
        if !quietly { session.hint("Almost — drop it on the glowing outline") }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.session.tw.tween(0.3, ease: .outBack) { [weak self] k in
                    self?.spec.set(from.lerp(to, k))
                }
            } catch {
                return
            }
            self.carried = to
            self.busy = false
        }
    }

    private func frame() {
        guard !done else { return }
        let orbit = engine.rig.orbit
        let ring = orbit.screen(spec.target.pos)
        engine.overlay.setRing(center: CGPoint(x: CGFloat(ring.x), y: CGFloat(ring.y)), radius: 46,
                               phase: CGFloat(engine.time * 30))
        guard !busy else { return }
        let current = spec.current()
        let goalY = carrying ? spec.hoverY : current.pos.y
        let rot = carrying ? current.rot.slerp(spec.carryRotation ?? spec.target.rot, 0.2) : current.rot
        var pos = carrying ? mix3(current.pos, carried.pos, 0.45) : current.pos
        pos.y = mixf(current.pos.y, goalY, 0.25)
        if carrying || abs(pos.y - current.pos.y) > 1e-4 { spec.set(Pose(rot: rot, pos: pos)) }
        if hintsOn, !carrying, !ghostHint.isShowing, engine.time - lastActivity > 5 {
            showHint()
            lastActivity = engine.time
        }
    }
}
