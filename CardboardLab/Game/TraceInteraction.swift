import SceneKit
import UIKit

/// Something drawn along a path that shows progress: a red cut line, a blue score line
/// or a glue bead.
@MainActor
protocol TraceVisual: AnyObject {
    var path: Polyline { get }
    func setProgress(_ d: Float)
    func setActive(_ active: Bool, time: Double)
    /// Flip the direction (only for open paths that may be traced either way).
    func reverse()
}

extension TraceVisual {
    func reverse() {}
}

extension CutLineNode: TraceVisual {}

/// The tool that rides the path (craft knife, bone folder, glue bottle).
struct TraceTool {
    let node: SCNNode
    /// Tool pose with its working tip at `tip`, moving along `tangent`.
    let pose: (_ tip: V3, _ tangent: V3) -> Pose
    /// Called as the tool advances: head, tangent, distance just covered.
    var onAdvance: ((V3, V3, Float) -> Void)?
}

/// Tracing a path with a tool: the tool rides the path under the player's finger or
/// Apple Pencil (never ahead of it, never skipping), the visual shows progress, and
/// straying far away gets a gentle hint — never a penalty.
@MainActor
final class TraceInteraction {
    private unowned let session: CraftSession
    private var engine: GameEngine { session.engine }
    private let visual: TraceVisual
    private let tool: TraceTool
    private var tracer: PathTracer
    private let ghost: GhostHint
    private let hintsOn: Bool
    private let allowReverse: Bool
    private let hintText: String

    private var done = false
    private var touching = false
    private var advancedThisTouch = false
    private var lastFeed: PathTracer.Feed = .holding
    private var offSince: Double?
    private var lastProgressTime: Double = 0
    private var frameID: Int?
    private var toolRot = Quat.identity
    private var toolPos = V3(0, 0, 0)
    private var lift: Float = 0

    /// Screen tolerance around the line, in points.
    let tolerance: Float = 48

    init(session: CraftSession, visual: TraceVisual, tool: TraceTool, showHint: Bool,
         allowReverse: Bool = false, hintText: String = "Try following the highlighted line") {
        self.session = session
        self.visual = visual
        self.tool = tool
        // On small closed loops the end sits next to the start; keep lookahead short so
        // the tool can't jump across the gap.
        self.tracer = PathTracer(path: visual.path, lookahead: min(2.0, visual.path.length * 0.4))
        self.ghost = GhostHint(engine: session.engine)
        self.hintsOn = showHint
        self.allowReverse = allowReverse
        self.hintText = hintText
    }

    // MARK: Tools

    /// Craft knife: tip on the line, handle trailing behind and raised.
    static func knifePose(tip: V3, tangent: V3) -> Pose {
        penPose(tip: tip, tangent: tangent, raise: radians(42))
    }

    /// Any pen-like tool whose tip is at its origin and body along +x.
    static func penPose(tip: V3, tangent: V3, raise: Float) -> Pose {
        var back = V3(-tangent.x, 0, -tangent.z)
        if back.len < 1e-4 { back = V3(1, 0, 1) }
        back = back.unit
        let yaw = atan2(-back.z, back.x)
        let rot = Quat(axis: up3, angle: yaw) * Quat(axis: V3(0, 0, 1), angle: raise)
        return Pose(rot: rot, pos: tip)
    }

    /// Glue bottle: nozzle on the line, body tilted back along the path.
    static func bottlePose(tip: V3, tangent: V3) -> Pose {
        var back = V3(-tangent.x, 0, -tangent.z)
        if back.len < 1e-4 { back = V3(1, 0, 0) }
        let body = (up3 * cos(radians(32)) + back.unit * sin(radians(32))).unit
        return Pose(rot: Quat.between(up3, body), pos: tip)
    }

    static func cut(session: CraftSession, line: CutLineNode, knife: SCNNode, showHint: Bool) -> TraceInteraction {
        let engine = session.engine
        var flakeDistance: Float = 0
        let tool = TraceTool(node: knife, pose: { knifePose(tip: $0, tangent: $1) }, onAdvance: { head, tangent, moved in
            engine.sound.play(.cut, volume: 0.7, minInterval: 0.06)
            flakeDistance += moved
            if flakeDistance > 0.28 {
                flakeDistance = 0
                engine.particles.flakes(at: head, count: 2, direction: tangent)
            }
        })
        return TraceInteraction(session: session, visual: line, tool: tool, showHint: showHint)
    }

    static func score(session: CraftSession, line: ScoreLineNode, folder: SCNNode, showHint: Bool) -> TraceInteraction {
        let engine = session.engine
        let tool = TraceTool(node: folder, pose: { penPose(tip: $0, tangent: $1, raise: radians(30)) }, onAdvance: { _, _, _ in
            engine.sound.play(.score, volume: 0.6, minInterval: 0.07)
        })
        return TraceInteraction(session: session, visual: line, tool: tool, showHint: showHint, allowReverse: true,
                                hintText: "Swipe along the blue dashed line")
    }

    static func glue(session: CraftSession, bead: GlueBeadNode, bottle: SCNNode, showHint: Bool) -> TraceInteraction {
        let engine = session.engine
        var dropDistance: Float = 0
        let tool = TraceTool(node: bottle, pose: { bottlePose(tip: $0, tangent: $1) }, onAdvance: { head, _, moved in
            engine.sound.play(.glue, volume: 0.6, minInterval: 0.12)
            dropDistance += moved
            if dropDistance > 0.6 {
                dropDistance = 0
                engine.particles.droplet(at: head)
            }
        })
        return TraceInteraction(session: session, visual: bead, tool: tool, showHint: showHint, allowReverse: true,
                                hintText: "Drag the glue along the dotted guide")
    }

    // MARK: Run

    func run() async throws {
        let tw = session.tw
        visual.setProgress(tracer.progress)
        let node = tool.node
        let startPose = tool.pose(tracer.head, tracer.tangent)
        let from = node.pose
        let hover = Pose(rot: startPose.rot, pos: startPose.pos + V3(0, 1.2, 0))
        try await tw.tween(0.35, ease: .inOutCubic) { k in
            node.setPose(from.lerp(hover, k))
        }
        try await tw.tween(0.14, ease: .inQuad) { k in
            node.setPose(hover.lerp(startPose, k))
        }
        toolRot = startPose.rot
        toolPos = startPose.pos
        lastProgressTime = engine.time

        engine.pointerHandler = { [weak self] phase, p in self?.pointer(phase, p) }
        frameID = engine.onFrame { [weak self] dt in self?.frame(dt) }
        if hintsOn { showGhost() }
        defer { finish() }

        try await tw.until { [weak self] in self?.done ?? true }

        // Lift the tool off the board.
        let end = node.pose
        try await tw.tween(0.18, ease: .outQuad) { k in
            node.setPose(Pose(rot: end.rot, pos: end.pos + V3(0, 0.7 * k, 0)))
        }
    }

    private func finish() {
        engine.pointerHandler = nil
        engine.removeFrameHandler(frameID)
        frameID = nil
        ghost.hide()
        visual.setActive(false, time: engine.time)
    }

    private func showGhost() {
        let a = tracer.progress
        let b = min(visual.path.length, a + 2.4)
        ghost.show(along: visual.path.slice(a, b), duration: 1.2)
    }

    // MARK: Input

    private func pointer(_ phase: PointerPhase, _ p: V2) {
        switch phase {
        case .began:
            touching = true
            advancedThisTouch = false
            ghost.hide()
            maybeReverse(for: p)
            feed(p)
        case .moved:
            if touching { feed(p) }
        case .ended, .cancelled:
            if touching, !advancedThisTouch, case .offPath = lastFeed {
                session.hint(hintText)
            }
            touching = false
            offSince = nil
        }
    }

    /// Straight guides can be traced from either end: start from the end nearer the finger.
    private func maybeReverse(for p: V2) {
        guard allowReverse, tracer.progress < 1e-3, let first = visual.path.points.first,
              let last = visual.path.points.last else { return }
        let orbit = engine.rig.orbit
        if p.dist(orbit.screen(last)) < p.dist(orbit.screen(first)) {
            visual.reverse()
            tracer = PathTracer(path: visual.path, lookahead: min(2.0, visual.path.length * 0.4))
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
            visual.setProgress(tracer.progress)
            tool.onAdvance?(tracer.head, tracer.tangent, tracer.progress - before)
            if tracer.isDone { done = true }
        case .holding:
            offSince = nil
        case .offPath:
            let now = engine.time
            if let since = offSince {
                if now - since > 0.35 {
                    session.hint(hintText)
                    offSince = now + 2
                }
            } else {
                offSince = now
            }
        }
    }

    // MARK: Frame

    private func frame(_ dt: Double) {
        let target = tool.pose(tracer.head, tracer.tangent)
        toolRot = toolRot.slerp(target.rot, Float(1 - exp(-14 * dt)))
        toolPos = mix3(toolPos, target.pos, Float(1 - exp(-30 * dt)))
        // Hover a touch above the line while idle so it reads as "pick me up".
        let idle = !touching && !done
        lift += ((idle ? 0.12 + 0.06 * Float(sin(engine.time * 4)) : 0) - lift) * Float(min(1, dt * 10))
        tool.node.setPose(Pose(rot: toolRot, pos: toolPos + V3(0, lift, 0)))
        visual.setActive(!done, time: engine.time)
        // Remind idle players where to swipe.
        if hintsOn, !touching, !ghost.isShowing, engine.time - lastProgressTime > 5 {
            showGhost()
            lastProgressTime = engine.time
        }
    }
}
