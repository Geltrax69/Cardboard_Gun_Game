import Foundation

/// Triangle soup with flat normals, split into material "parts". Converted to an
/// SCNGeometry by SceneBridge; kept platform-free so it can be unit tested.
public struct MeshData {
    public var positions: [V3] = []
    public var normals: [V3] = []
    public var uvs: [V2] = []
    public var parts: [[UInt32]]

    public init(parts: Int = 1) {
        self.parts = Array(repeating: [], count: max(parts, 1))
    }

    public var isEmpty: Bool { parts.allSatisfy { $0.isEmpty } }
    public var triangleCount: Int { parts.reduce(0) { $0 + $1.count / 3 } }

    @discardableResult
    public mutating func vertex(_ p: V3, _ n: V3, _ uv: V2 = V2(0, 0)) -> UInt32 {
        positions.append(p)
        normals.append(n)
        uvs.append(uv)
        return UInt32(positions.count - 1)
    }

    /// Adds a triangle whose winding is corrected so its face normal matches `facing`
    /// (counter-clockwise front faces, as SceneKit expects). With `facing == nil`
    /// the geometric normal of a→b→c is used.
    public mutating func triangle(_ part: Int, _ a: V3, _ b: V3, _ c: V3,
                                  facing: V3? = nil, uv: (V2, V2, V2) = (V2(0, 0), V2(0, 0), V2(0, 0))) {
        var n = (b - a).crossp(c - a)
        if n.len < 1e-12 { return }
        n = n.unit
        var pb = b, pc = c, ub = uv.1, uc = uv.2
        if let f = facing, n.dotp(f) < 0 {
            swap(&pb, &pc)
            swap(&ub, &uc)
            n = n * -1
        }
        let i0 = vertex(a, n, uv.0), i1 = vertex(pb, n, ub), i2 = vertex(pc, n, uc)
        parts[part].append(contentsOf: [i0, i1, i2])
    }

    public mutating func quad(_ part: Int, _ a: V3, _ b: V3, _ c: V3, _ d: V3, facing: V3? = nil,
                              uv: (V2, V2, V2, V2) = (V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1))) {
        let f = facing ?? (b - a).crossp(c - a).unit
        triangle(part, a, b, c, facing: f, uv: (uv.0, uv.1, uv.2))
        triangle(part, a, c, d, facing: f, uv: (uv.0, uv.2, uv.3))
    }

    public mutating func append(_ o: MeshData, pose: Pose = .identity, partMap: [Int]? = nil) {
        let base = UInt32(positions.count)
        positions.append(contentsOf: o.positions.map { pose.apply($0) })
        normals.append(contentsOf: o.normals.map { pose.applyVector($0) })
        uvs.append(contentsOf: o.uvs)
        for (i, idx) in o.parts.enumerated() {
            let target = partMap?[i] ?? i
            while parts.count <= target { parts.append([]) }
            parts[target].append(contentsOf: idx.map { $0 + base })
        }
    }

    /// Compact copy containing only the listed parts (in the given order).
    public func extract(parts wanted: [Int]) -> MeshData {
        var m = MeshData(parts: wanted.count)
        var remap: [UInt32: UInt32] = [:]
        for (k, pi) in wanted.enumerated() where pi < parts.count {
            for idx in parts[pi] {
                if let r = remap[idx] {
                    m.parts[k].append(r)
                } else {
                    let r = m.vertex(positions[Int(idx)], normals[Int(idx)], uvs[Int(idx)])
                    remap[idx] = r
                    m.parts[k].append(r)
                }
            }
        }
        return m
    }

    public func transformed(_ pose: Pose) -> MeshData {
        var m = MeshData(parts: parts.count)
        m.append(self, pose: pose)
        return m
    }

    /// Ink shell for outlines: every vertex pushed out along the average normal of all
    /// faces sharing its position. Rendered with front-face culling.
    public func inflated(by w: Float) -> MeshData {
        var sums: [SIMD3<Int32>: V3] = [:]
        func key(_ p: V3) -> SIMD3<Int32> { SIMD3<Int32>(Int32((p.x * 1000).rounded()), Int32((p.y * 1000).rounded()), Int32((p.z * 1000).rounded())) }
        for (i, p) in positions.enumerated() { sums[key(p), default: V3(0, 0, 0)] += normals[i] }
        var m = self
        for i in m.positions.indices {
            let n = (sums[key(positions[i])] ?? normals[i]).unit
            m.positions[i] = positions[i] + n * w
        }
        m.parts = [parts.flatMap { $0 }]
        return m
    }

    public var bounds: (min: V3, max: V3) {
        var lo = V3(repeating: .greatestFiniteMagnitude), hi = V3(repeating: -.greatestFiniteMagnitude)
        for p in positions {
            lo = V3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = V3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        return (lo, hi)
    }
}

// MARK: - Cardboard

public enum CardboardPart: Int {
    case top = 0, bottom, side, ink
}

public enum MeshBuilder {
    /// Extruded cardboard slab (y from 0 to thickness) with printed top, plain underside,
    /// corrugated sides (u runs along the edge in flute periods) and ink bands along
    /// `inkEdges` on both faces.
    public static func cardboard(outline: [V2], holes: [[V2]] = [], thickness t: Float,
                                 inkEdges: [(V2, V2)] = [], inkWidth: Float = 0.045,
                                 flutePeriod: Float = 0.32) -> MeshData {
        var m = MeshData(parts: 4)
        let tris = Earcut.triangulate(outer: outline, holes: holes)
        let flat = outline + holes.flatMap { $0 }
        let up = V3(0, 1, 0), down = V3(0, -1, 0)
        var k = 0
        while k + 2 < tris.count {
            let a = flat[tris[k]], b = flat[tris[k + 1]], c = flat[tris[k + 2]]
            let uv = (a / 8, b / 8, c / 8)
            m.triangle(CardboardPart.top.rawValue, a.onMat(t), b.onMat(t), c.onMat(t), facing: up, uv: uv)
            m.triangle(CardboardPart.bottom.rawValue, a.onMat(0), b.onMat(0), c.onMat(0), facing: down, uv: uv)
            k += 3
        }
        // Side walls.
        for ring in [outline] + holes {
            var run: Float = 0
            for i in 0..<ring.count {
                let p = ring[i], q = ring[(i + 1) % ring.count]
                let len = p.dist(q)
                guard len > 1e-6 else { continue }
                let n2 = outward(p, q, outline: outline, holes: holes)
                let n3 = V3(n2.x, 0, n2.y)
                let u0 = run / flutePeriod, u1 = (run + len) / flutePeriod
                m.quad(CardboardPart.side.rawValue, p.onMat(0), q.onMat(0), q.onMat(t), p.onMat(t), facing: n3,
                       uv: (V2(u0, 0), V2(u1, 0), V2(u1, 1), V2(u0, 1)))
                run += len
            }
        }
        // Ink bands on free edges (both faces so folded panels stay outlined).
        let eps: Float = 0.004
        for (p, q) in inkEdges {
            let n2 = outward(p, q, outline: outline, holes: holes)
            let inward = n2 * -inkWidth
            let dir = (q - p).unit * (inkWidth * 0.5)
            let a = p - dir, b = q + dir
            m.quad(CardboardPart.ink.rawValue, a.onMat(t + eps), b.onMat(t + eps), (b + inward).onMat(t + eps), (a + inward).onMat(t + eps), facing: up)
            m.quad(CardboardPart.ink.rawValue, a.onMat(-eps), b.onMat(-eps), (b + inward).onMat(-eps), (a + inward).onMat(-eps), facing: down)
        }
        return m
    }

    /// Unit normal of edge p→q pointing away from the material.
    public static func outward(_ p: V2, _ q: V2, outline: [V2], holes: [[V2]]) -> V2 {
        var n = (q - p).unit.perp
        let mid = (p + q) / 2
        if Poly.contains(outer: outline, holes: holes, mid + n * 0.002) { n = n * -1 }
        return n
    }

    /// Flat ribbon along a polyline lying in the plane with normal `normal`.
    public static func ribbon(_ pts: [V3], width: Float, normal: V3 = V3(0, 1, 0), part: Int = 0,
                              into m: inout MeshData, extend: Bool = true) {
        guard pts.count > 1 else { return }
        let hw = width / 2
        for i in 0..<(pts.count - 1) {
            var a = pts[i], b = pts[i + 1]
            let d = (b - a)
            if d.len < 1e-6 { continue }
            let dir = d.unit
            if extend {
                a = a - dir * hw
                b = b + dir * hw
            }
            let side = normal.crossp(dir).unit * hw
            m.quad(part, a - side, b - side, b + side, a + side, facing: normal,
                   uv: (V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)))
        }
    }

    /// Evenly spaced dashes along a segment (blue fold lines).
    public static func dashes(_ a: V3, _ b: V3, dash: Float = 0.2, gap: Float = 0.13, width: Float = 0.055,
                              normal: V3 = V3(0, 1, 0), into m: inout MeshData, part: Int = 0) {
        let len = a.dist(b)
        guard len > 1e-4 else { return }
        let dir = (b - a).unit
        let count = max(1, Int(((len + gap) / (dash + gap)).rounded(.down)))
        let used = Float(count) * dash + Float(count - 1) * gap
        var s = (len - used) / 2
        for _ in 0..<count {
            ribbon([a + dir * s, a + dir * (s + dash)], width: width, normal: normal, part: part, into: &m, extend: false)
            s += dash + gap
        }
    }

    // MARK: Low-poly primitives (flat shaded)

    /// Prism along +y from 0 to `height`, `sides`-gon cross-section.
    public static func prism(sides: Int, radius: Float, height: Float, phase: Float = 0) -> MeshData {
        frustum(sides: sides, bottom: radius, top: radius, height: height, phase: phase)
    }

    public static func frustum(sides: Int, bottom r0: Float, top r1: Float, height h: Float, phase: Float = 0) -> MeshData {
        lathe([V2(r0, 0), V2(r1, h)], sides: sides, phase: phase, capBottom: r0 > 0, capTop: r1 > 0)
    }

    /// Revolve a (radius, y) profile around +y.
    public static func lathe(_ profile: [V2], sides: Int, phase: Float = 0, capBottom: Bool = true, capTop: Bool = true) -> MeshData {
        var m = MeshData()
        func ring(_ r: Float, _ y: Float) -> [V3] {
            (0..<sides).map { i in
                let a = phase + Float(i) / Float(sides) * 2 * .pi
                return V3(cos(a) * r, y, sin(a) * r)
            }
        }
        let rings = profile.map { ring($0.x, $0.y) }
        for j in 0..<(profile.count - 1) {
            let r0 = rings[j], r1 = rings[j + 1]
            for i in 0..<sides {
                let i2 = (i + 1) % sides
                let mid = (r0[i] + r0[i2] + r1[i] + r1[i2]) / 4
                let out = V3(mid.x, 0, mid.z).unit
                let slope = profile[j + 1].x < profile[j].x ? V3(0, 1, 0) : V3(0, -1, 0)
                let facing = (out + slope * 0.001).unit
                if profile[j].x > 1e-5 && profile[j + 1].x > 1e-5 {
                    m.quad(0, r0[i], r0[i2], r1[i2], r1[i], facing: facing)
                } else if profile[j].x > 1e-5 {
                    m.triangle(0, r0[i], r0[i2], r1[i], facing: facing)
                } else if profile[j + 1].x > 1e-5 {
                    m.triangle(0, r0[i], r1[i2], r1[i], facing: facing)
                }
            }
        }
        if capBottom, let first = profile.first, first.x > 1e-5 {
            let c = V3(0, first.y, 0)
            let r = rings[0]
            for i in 0..<sides { m.triangle(0, c, r[i], r[(i + 1) % sides], facing: V3(0, -1, 0)) }
        }
        if capTop, let last = profile.last, last.x > 1e-5 {
            let c = V3(0, last.y, 0)
            let r = rings[rings.count - 1]
            for i in 0..<sides { m.triangle(0, c, r[i], r[(i + 1) % sides], facing: V3(0, 1, 0)) }
        }
        return m
    }

    /// Ring (washer) — used for the tape roll.
    public static func tube(sides: Int, inner: Float, outer: Float, height h: Float) -> MeshData {
        var m = MeshData()
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * .pi, a1 = Float(i + 1) / Float(sides) * 2 * .pi
            let c0 = V3(cos(a0), 0, sin(a0)), c1 = V3(cos(a1), 0, sin(a1))
            let o0 = c0 * outer, o1 = c1 * outer, i0 = c0 * inner, i1 = c1 * inner
            let yv = V3(0, h, 0)
            let mid = (c0 + c1).unit
            m.quad(0, o0, o1, o1 + yv, o0 + yv, facing: mid)
            m.quad(0, i0, i1, i1 + yv, i0 + yv, facing: mid * -1)
            m.quad(0, o0 + yv, o1 + yv, i1 + yv, i0 + yv, facing: V3(0, 1, 0))
            m.quad(0, o0, o1, i1, i0, facing: V3(0, -1, 0))
        }
        return m
    }

    public static func box(_ size: V3, center: V3 = V3(0, 0, 0)) -> MeshData {
        var m = MeshData()
        let h = size / 2
        let c = center
        let p = [V3(-h.x, -h.y, -h.z), V3(h.x, -h.y, -h.z), V3(h.x, h.y, -h.z), V3(-h.x, h.y, -h.z),
                 V3(-h.x, -h.y, h.z), V3(h.x, -h.y, h.z), V3(h.x, h.y, h.z), V3(-h.x, h.y, h.z)].map { $0 + c }
        m.quad(0, p[4], p[5], p[6], p[7], facing: V3(0, 0, 1))
        m.quad(0, p[1], p[0], p[3], p[2], facing: V3(0, 0, -1))
        m.quad(0, p[5], p[1], p[2], p[6], facing: V3(1, 0, 0))
        m.quad(0, p[0], p[4], p[7], p[3], facing: V3(-1, 0, 0))
        m.quad(0, p[7], p[6], p[2], p[3], facing: V3(0, 1, 0))
        m.quad(0, p[0], p[1], p[5], p[4], facing: V3(0, -1, 0))
        return m
    }

    /// Straight extrusion of a 2D outline (x, y) along +z by `depth` (single part).
    public static func extrudeXY(_ outline: [V2], depth: Float) -> MeshData {
        var m = MeshData()
        let ring = Poly.signedArea(outline) < 0 ? outline.reversed() : outline
        let tris = Earcut.triangulate(outer: ring)
        var k = 0
        while k + 2 < tris.count {
            let a = ring[tris[k]], b = ring[tris[k + 1]], c = ring[tris[k + 2]]
            m.triangle(0, V3(a.x, a.y, depth), V3(b.x, b.y, depth), V3(c.x, c.y, depth), facing: V3(0, 0, 1))
            m.triangle(0, V3(a.x, a.y, 0), V3(b.x, b.y, 0), V3(c.x, c.y, 0), facing: V3(0, 0, -1))
            k += 3
        }
        for i in 0..<ring.count {
            let p = ring[i], q = ring[(i + 1) % ring.count]
            let d = (q - p).unit
            let n = V2(d.y, -d.x) // outward for positive-area rings
            m.quad(0, V3(p.x, p.y, 0), V3(q.x, q.y, 0), V3(q.x, q.y, depth), V3(p.x, p.y, depth), facing: V3(n.x, n.y, 0))
        }
        return m
    }
}
