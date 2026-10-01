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

/// An edge being shaped with the sanding block: a pulsing yellow guide along the edge
/// and, behind the block, a freshly sanded bevel (lighter board) with a bright line
/// where the edge is now sharp. The `.groove` style carves a dark fuller line with the
/// craft knife instead. Drawn in the panel's own frame; `path` is the same edge in world
/// space for tracing.
@MainActor
final class BevelNode: TraceVisual {
    enum Style { case bevel, groove }

    private(set) var path: Polyline
    let root = SCNNode()
    private let style: Style
    private let local: Polyline
    private let outer: [V3]
    private let inner: [V3]
    private let normal: V3
    private let band = SCNNode()
    private let shine = SCNNode()
    private let guide = SCNNode()
    private static let bandMat = Mat.lambert(Palette.cardboardLight)
    private static let shineMat = Mat.unlit(Palette.paper)
    private static let grooveMat = Mat.lambert(Palette.cardboardDark)
    private static let guideMat = Mat.unlit(Palette.yellow)
    private static let grooveGuideMat = Mat.unlit(Palette.red)

    /// - Parameters:
    ///   - surface: the edge in the panel's flat frame
    ///   - inner: inner border of the bevel (`SurfacePath.inset`), same count as the edge
    ///   - toWorld: current panel → world transform
    init(surface: SurfacePath, inner: [V3], toWorld: Pose, style: Style) {
        self.style = style
        normal = surface.normal
        outer = surface.points
        self.inner = inner.count == surface.points.count ? inner : surface.points
        local = Polyline(surface.points)
        path = Polyline(surface.points.map { toWorld.apply($0) })
        root.name = style == .bevel ? "bevel" : "fuller"
        for n in [band, shine, guide] {
            n.castsShadow = false
            root.addChildNode(n)
        }
        band.renderingOrder = 4
        shine.renderingOrder = 5
        guide.renderingOrder = 6
        setProgress(0)
    }

    func setProgress(_ d: Float) {
        let k = path.length > 0 ? clampf(d / path.length, 0, 1) : 0
        let ld = local.length * k
        switch style {
        case .bevel: buildBevel(upTo: ld)
        case .groove: buildGroove(upTo: ld)
        }
        buildGuide(from: ld)
    }

    func setActive(_ active: Bool, time: Double) {
        guide.isHidden = !active
        guide.opacity = CGFloat(0.55 + 0.45 * sin(time * 6))
    }

    /// Band between the edge and its inset, covering the first `ld` of the edge.
    private func buildBevel(upTo ld: Float) {
        guard ld > 0.01 else { band.geometry = nil; shine.geometry = nil; return }
        var bm = MeshData(parts: 1)
        var sm = MeshData(parts: 1)
        let lift = normal * 0.004
        for i in 0..<(outer.count - 1) {
            let d0 = local.cumulative[i], d1 = local.cumulative[i + 1]
            guard d0 < ld, d1 > d0 else { continue }
            let f = min(1, (ld - d0) / (d1 - d0))
            // Keep a sliver of the ink outline visible at the very edge.
            let o0 = mix3(outer[i], inner[i], 0.1) + lift
            let i0 = inner[i] + lift
            let o1 = mix3(mix3(outer[i], outer[i + 1], f), mix3(inner[i], inner[i + 1], f), 0.1) + lift
            let i1 = mix3(inner[i], inner[i + 1], f) + lift
            bm.quad(0, o0, o1, i1, i0, facing: normal)
            let s0 = mix3(o0, i0, 0.32) + normal * 0.002, s1 = mix3(o1, i1, 0.32) + normal * 0.002
            sm.quad(0, o0 + normal * 0.002, o1 + normal * 0.002, s1, s0, facing: normal)
        }
        band.geometry = bm.isEmpty ? nil : SceneBridge.geometry(bm, materials: [BevelNode.bandMat])
        shine.geometry = sm.isEmpty ? nil : SceneBridge.geometry(sm, materials: [BevelNode.shineMat])
    }

    private func buildGroove(upTo ld: Float) {
        guard ld > 0.01 else { band.geometry = nil; return }
        var m = MeshData()
        MeshBuilder.ribbon(local.slice(0, ld).map { $0 + normal * 0.004 }, width: 0.15, normal: normal, into: &m)
        band.geometry = SceneBridge.geometry(m, materials: [BevelNode.grooveMat])
    }

    /// Dotted guide over the stretch still to do, just inside the edge.
    private func buildGuide(from ld: Float) {
        var m = MeshData()
        var s = ld + 0.12
        while s < local.length - 0.02 {
            let p = guidePoint(at: s)
            let t = local.tangent(at: s)
            MeshBuilder.ribbon([p - t * 0.06, p + t * 0.06], width: 0.1, normal: normal, into: &m, extend: false)
            s += 0.26
        }
        guide.geometry = m.isEmpty ? nil : SceneBridge.geometry(m, materials: [style == .bevel ? BevelNode.guideMat : BevelNode.grooveGuideMat])
    }

    private func guidePoint(at s: Float) -> V3 {
        let p = local.point(at: s) + normal * 0.008
        guard style == .bevel else { return p }
        // Interpolate the inset at the same distance.
        let i = min(local.segment(at: s), inner.count - 2)
        let d0 = local.cumulative[i], d1 = local.cumulative[i + 1]
        let f = d1 > d0 ? clampf((s - d0) / (d1 - d0), 0, 1) : 0
        let q = mix3(inner[i], inner[i + 1], f) + normal * 0.008
        return mix3(p, q, 0.45)
    }
}

/// Four-pointed sparkle that flashes on a freshly sharpened tip. Faces +z; the caller
/// turns it toward the camera.
@MainActor
enum Glint {
    static func make() -> SCNNode {
        var m = MeshData(parts: 1)
        let c = V3(0, 0, 0)
        for i in 0..<4 {
            let a = Float(i) * .pi / 2
            let dir = V3(cos(a), sin(a), 0)
            let side = V3(-sin(a), cos(a), 0)
            let len: Float = i % 2 == 0 ? 1.0 : 0.7
            m.triangle(0, c - side * 0.13, c + dir * len, c + side * 0.13, facing: V3(0, 0, 1))
        }
        let node = SceneBridge.node(m, [Mat.unlit(Palette.paper, opacity: 0.95, depthWrite: false)], name: "glint")
        node.castsShadow = false
        node.renderingOrder = 40
        return node
    }
}
