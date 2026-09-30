import SceneKit
import UIKit

/// A solid red cut line on the sheet. As the knife advances, the finished part turns
/// muted with a dark kerf (the slit), and the segment being cut glows.
@MainActor
final class CutLineNode {
    let path: Polyline
    let root = SCNNode()
    private let base = SCNNode()
    private let done = SCNNode()
    private let glow = SCNNode()
    private var glowSegment = -1
    private(set) var progress: Float = 0
    static let width: Float = 0.085

    private static let redMat = Mat.unlit(Palette.red)
    private static let mutedMat = Mat.unlit(Palette.redMuted)
    private static let kerfMat = Mat.unlit(Palette.ink)
    private static let glowMat = Mat.unlit(Palette.red, opacity: 0.32, depthWrite: false)

    /// `points` are world positions on the sheet surface (closed loops repeat the start).
    init(points: [V3], name: String) {
        path = Polyline(points)
        root.name = "cut-\(name)"
        for n in [glow, base, done] {
            n.castsShadow = false
            root.addChildNode(n)
        }
        glow.renderingOrder = 5
        base.renderingOrder = 6
        done.renderingOrder = 7
        drawIn(1)
    }

    /// Template printing: shows the first `k` fraction of the line.
    func drawIn(_ k: Float) {
        var m = MeshData()
        let pts = path.slice(0, path.length * saturate(k))
        if pts.count > 1 { MeshBuilder.ribbon(pts, width: CutLineNode.width, into: &m) }
        base.geometry = m.isEmpty ? nil : SceneBridge.geometry(m, materials: [CutLineNode.redMat])
    }

    func setProgress(_ d: Float) {
        progress = clampf(d, 0, path.length)
        guard progress > 1e-3 else { done.geometry = nil; return }
        let pts = path.slice(0, progress).map { $0 + V3(0, 0.002, 0) }
        var m = MeshData(parts: 2)
        MeshBuilder.ribbon(pts, width: CutLineNode.width + 0.01, part: 0, into: &m)
        MeshBuilder.ribbon(pts.map { $0 + V3(0, 0.002, 0) }, width: 0.035, part: 1, into: &m)
        done.geometry = SceneBridge.geometry(m, materials: [CutLineNode.mutedMat, CutLineNode.kerfMat])
    }

    /// Highlights the segment the knife is on (nil = no highlight).
    func setActive(_ active: Bool, time: Double = 0) {
        glow.isHidden = !active
        guard active else { return }
        let seg = path.segment(at: min(progress + 1e-3, path.length))
        if seg != glowSegment {
            glowSegment = seg
            var m = MeshData()
            let a = path.cumulative[seg], b = path.cumulative[min(seg + 1, path.points.count - 1)]
            MeshBuilder.ribbon(path.slice(a, b).map { $0 + V3(0, -0.001, 0) }, width: 0.3, into: &m)
            glow.geometry = SceneBridge.geometry(m, materials: [CutLineNode.glowMat])
        }
        glow.opacity = CGFloat(0.6 + 0.4 * sin(time * 6))
    }

    /// Fades the whole line out once the piece is free.
    func fade(_ k: Float) {
        root.opacity = CGFloat(1 - saturate(k))
    }
}
