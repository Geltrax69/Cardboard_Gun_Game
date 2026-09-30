import SceneKit
import UIKit

/// A blue fold line being scored: the whole line glows, and a darker crease grows behind
/// the bone folder. World coordinates (the piece lies still while scoring).
@MainActor
final class ScoreLineNode: TraceVisual {
    private(set) var path: Polyline
    let root = SCNNode()
    private let glow = SCNNode()
    private let crease = SCNNode()
    private static let glowMat = Mat.unlit(Palette.blue, opacity: 0.4, depthWrite: false)
    private static let creaseMat = Mat.unlit(Palette.cardboardDark)

    init(points: [V3]) {
        path = Polyline(points)
        root.name = "scoreLine"
        glow.castsShadow = false
        crease.castsShadow = false
        glow.renderingOrder = 5
        crease.renderingOrder = 6
        root.addChildNode(glow)
        root.addChildNode(crease)
        var m = MeshData()
        MeshBuilder.ribbon(path.points.map { $0 + V3(0, -0.004, 0) }, width: 0.34, into: &m)
        glow.geometry = SceneBridge.geometry(m, materials: [ScoreLineNode.glowMat])
    }

    func setProgress(_ d: Float) {
        guard d > 1e-3 else { crease.geometry = nil; return }
        var m = MeshData()
        MeshBuilder.ribbon(path.slice(0, d).map { $0 + V3(0, 0.004, 0) }, width: 0.06, into: &m)
        crease.geometry = SceneBridge.geometry(m, materials: [ScoreLineNode.creaseMat])
    }

    func setActive(_ active: Bool, time: Double) {
        glow.isHidden = !active
        glow.opacity = CGFloat(0.55 + 0.45 * sin(time * 5))
    }

    func reverse() {
        path = Polyline(path.points.reversed())
    }
}

/// Glossy wavy glue bead laid along a tab, with a dotted blue guide over the part still
/// to be glued. Drawn in the panel's own frame (so it travels with the piece later);
/// `path` is the same guide in world space for tracing.
@MainActor
final class GlueBeadNode: TraceVisual {
    private(set) var path: Polyline
    private var local: Polyline
    let root = SCNNode()
    private let bead = SCNNode()
    private let dots = SCNNode()
    private let localNormal: V3
    private static let glueMat = Mat.glossy(Palette.glue, shininess: 0.9)
    private static let dotMat = Mat.unlit(Palette.blue)

    /// - Parameters:
    ///   - localPoints: guide in the panel's flat frame, just off the glued face
    ///   - localNormal: the glued face's outward normal in that frame
    ///   - toWorld: current panel → world transform
    init(localPoints: [V3], localNormal: V3, toWorld: Pose) {
        local = Polyline(localPoints)
        path = Polyline(localPoints.map { toWorld.apply($0) })
        self.localNormal = localNormal
        root.name = "glue"
        bead.castsShadow = false
        dots.castsShadow = false
        root.addChildNode(bead)
        root.addChildNode(dots)
        setProgress(0)
    }

    func setProgress(_ d: Float) {
        let k = local.length > 0 ? clampf(d / path.length, 0, 1) : 0
        let ld = local.length * k
        // Bead: wavy line following the guide.
        if ld > 0.02 {
            var pts: [V3] = []
            let steps = max(2, Int(ld / 0.08))
            for i in 0...steps {
                let s = ld * Float(i) / Float(steps)
                let p = local.point(at: s)
                let t = local.tangent(at: s)
                let side = localNormal.crossp(t).unit
                pts.append(p + side * (sin(s * 7) * 0.09) + localNormal * 0.035)
            }
            var m = MeshData()
            MeshBuilder.sweep(pts, radius: 0.075, sides: 6, normal: localNormal, flatten: 0.6, into: &m)
            bead.geometry = SceneBridge.geometry(m, materials: [GlueBeadNode.glueMat])
        } else {
            bead.geometry = nil
        }
        // Dotted guide over the remaining stretch.
        var dm = MeshData()
        var s = ld + 0.15
        while s < local.length - 0.02 {
            let p = local.point(at: s) + localNormal * 0.01
            let t = local.tangent(at: s)
            MeshBuilder.ribbon([p - t * 0.045, p + t * 0.045], width: 0.09, normal: localNormal, into: &dm, extend: false)
            s += 0.24
        }
        dots.geometry = dm.isEmpty ? nil : SceneBridge.geometry(dm, materials: [GlueBeadNode.dotMat])
    }

    func setActive(_ active: Bool, time: Double) {
        dots.opacity = active ? CGFloat(0.6 + 0.4 * sin(time * 5)) : 1
    }

    func reverse() {
        path = Polyline(path.points.reversed())
        local = Polyline(local.points.reversed())
        setProgress(0)
    }

    /// Hides the dotted guide once the glue is down.
    func settle() {
        dots.isHidden = true
    }
}
