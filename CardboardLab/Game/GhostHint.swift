import UIKit

/// Tutorial ghost finger: presses, swipes along a world-space path (projected every
/// frame so it follows the camera), lifts, pauses, repeats. Hidden on first touch.
@MainActor
final class GhostHint {
    private unowned let engine: GameEngine
    private var frameID: Int?
    private var path: Polyline?
    private var travel: Double = 1.3
    private var start: Double = 0

    init(engine: GameEngine) {
        self.engine = engine
    }

    var isShowing: Bool { frameID != nil }

    func show(along points: [V3], duration: Double = 1.3) {
        guard points.count > 1 else { return }
        path = Polyline(points)
        travel = duration
        start = engine.time
        if frameID == nil {
            frameID = engine.onFrame { [weak self] _ in self?.tick() }
        }
    }

    func hide() {
        engine.removeFrameHandler(frameID)
        frameID = nil
        engine.overlay.setFinger(nil)
    }

    private func tick() {
        guard let path else { return }
        let period = travel + 1.1
        let t = (engine.time - start).truncatingRemainder(dividingBy: period)
        let press = 0.25
        var k: Double
        var alpha: CGFloat
        var pressed = true
        if t < press {
            k = 0
            alpha = CGFloat(t / press)
            pressed = false
        } else if t < press + travel {
            k = (t - press) / travel
            alpha = 1
        } else if t < press + travel + 0.3 {
            k = 1
            alpha = CGFloat(1 - (t - press - travel) / 0.3)
            pressed = false
        } else {
            engine.overlay.setFinger(nil)
            return
        }
        let ease = Ease.inOutSine
        let eased = ease(Float(k))
        let d = path.length * eased
        let head = engine.toScreen(path.point(at: d))
        let trail = path.slice(0, d).map { engine.toScreen($0) }
        engine.overlay.setFinger(head, pressed: pressed, trail: trail, alpha: alpha)
    }
}
