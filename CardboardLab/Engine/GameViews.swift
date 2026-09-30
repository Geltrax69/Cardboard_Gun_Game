import QuartzCore
import SceneKit
import SwiftUI
import UIKit

enum PointerPhase {
    case began, moved, ended, cancelled
}

@MainActor
protocol PointerSink: AnyObject {
    func pointer(_ phase: PointerPhase, at point: CGPoint)
}

/// SCNView that forwards single-finger / Apple Pencil touches (including coalesced
/// samples, so fast swipes stay smooth) to the game.
final class GameSCNView: SCNView {
    weak var sink: PointerSink?
    private weak var activeTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let t = touches.first else { return }
        activeTouch = t
        sink?.pointer(.began, at: t.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        let samples = event?.coalescedTouches(for: t) ?? [t]
        for s in samples { sink?.pointer(.moved, at: s.location(in: self)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        sink?.pointer(.ended, at: t.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        sink?.pointer(.cancelled, at: t.location(in: self))
    }
}

/// 2D guides drawn over the 3D scene from projected points: curved fold arrows,
/// dotted glue guides, the ghost finger used by the tutorial and alignment rings.
final class GuideOverlayView: UIView {
    private let arrowShadow = CAShapeLayer()
    private let arrow = CAShapeLayer()
    private let arrowHead = CAShapeLayer()
    private let dotted = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let fingerTrail = CAShapeLayer()
    private let finger = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for l in [arrowShadow, arrow, arrowHead, dotted, ring, fingerTrail, finger] {
            l.fillColor = UIColor.clear.cgColor
            l.lineCap = .round
            l.lineJoin = .round
            layer.addSublayer(l)
        }
        arrowShadow.strokeColor = Palette.ink.withAlphaComponent(0.55).cgColor
        arrowShadow.lineWidth = 11
        arrow.strokeColor = Palette.blue.cgColor
        arrow.lineWidth = 6
        arrowHead.fillColor = Palette.blue.cgColor
        arrowHead.strokeColor = Palette.ink.withAlphaComponent(0.55).cgColor
        arrowHead.lineWidth = 2.5
        dotted.strokeColor = Palette.blue.cgColor
        dotted.lineWidth = 5
        dotted.lineDashPattern = [0.1, 11]
        ring.strokeColor = Palette.mint.cgColor
        ring.lineWidth = 4
        ring.lineDashPattern = [10, 8]
        fingerTrail.strokeColor = Palette.paper.withAlphaComponent(0.5).cgColor
        fingerTrail.lineWidth = 10
        finger.fillColor = Palette.paper.withAlphaComponent(0.85).cgColor
        finger.strokeColor = Palette.ink.cgColor
        finger.lineWidth = 3
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func path(_ pts: [CGPoint]) -> CGPath? {
        guard pts.count > 1 else { return nil }
        let p = UIBezierPath()
        p.move(to: pts[0])
        for q in pts.dropFirst() { p.addLine(to: q) }
        return p.cgPath
    }

    private func quiet(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    /// Curved arrow along projected points; the head points along the last segment.
    func setArrow(_ pts: [CGPoint]?, alpha: CGFloat = 1) {
        quiet {
            guard let pts, pts.count > 2 else {
                arrow.path = nil; arrowShadow.path = nil; arrowHead.path = nil
                return
            }
            let body = Array(pts.dropLast())
            arrow.path = path(body)
            arrowShadow.path = path(body)
            let tip = pts[pts.count - 1], prev = pts[pts.count - 3]
            let dx = tip.x - prev.x, dy = tip.y - prev.y
            let len = max(0.001, (dx * dx + dy * dy).squareRoot())
            let ux = dx / len, uy = dy / len
            let size: CGFloat = 20
            let base = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
            let head = UIBezierPath()
            head.move(to: tip)
            head.addLine(to: CGPoint(x: base.x - uy * size * 0.62, y: base.y + ux * size * 0.62))
            head.addLine(to: CGPoint(x: base.x + uy * size * 0.62, y: base.y - ux * size * 0.62))
            head.close()
            arrowHead.path = head.cgPath
            for l in [arrow, arrowShadow, arrowHead] { l.opacity = Float(alpha) }
        }
    }

    func setDotted(_ pts: [CGPoint]?, color: UIColor = Palette.blue) {
        quiet {
            dotted.strokeColor = color.cgColor
            dotted.path = pts.flatMap { path($0) }
        }
    }

    func setRing(center: CGPoint?, radius: CGFloat = 40, phase: CGFloat = 0) {
        quiet {
            guard let c = center else { ring.path = nil; return }
            ring.path = UIBezierPath(arcCenter: c, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
            ring.lineDashPhase = phase
        }
    }

    /// Ghost finger for tutorial hints.
    func setFinger(_ p: CGPoint?, pressed: Bool = true, trail: [CGPoint] = [], alpha: CGFloat = 1) {
        quiet {
            guard let p else {
                finger.path = nil; fingerTrail.path = nil
                return
            }
            let r: CGFloat = pressed ? 17 : 22
            finger.path = UIBezierPath(arcCenter: p, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
            finger.opacity = Float(alpha)
            fingerTrail.path = path(trail)
            fingerTrail.opacity = Float(alpha)
        }
    }

    func clearAll() {
        setArrow(nil)
        setDotted(nil)
        setRing(center: nil)
        setFinger(nil)
    }
}

/// Hosts the 3D view and the guide overlay; reports size changes to the engine.
final class GameContainerView: UIView {
    let scnView: GameSCNView
    let overlay: GuideOverlayView
    var onLayout: ((CGSize) -> Void)?

    init(scnView: GameSCNView, overlay: GuideOverlayView) {
        self.scnView = scnView
        self.overlay = overlay
        super.init(frame: .zero)
        backgroundColor = Palette.table
        addSubview(scnView)
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        scnView.frame = bounds
        overlay.frame = bounds
        onLayout?(bounds.size)
    }
}

/// SwiftUI wrapper. The container is created by the engine (on the main actor) and
/// passed in, so the representable never touches actor-isolated state itself.
struct GameSceneView: UIViewRepresentable {
    let container: GameContainerView

    func makeUIView(context: Context) -> GameContainerView { container }
    func updateUIView(_ uiView: GameContainerView, context: Context) {}
}
