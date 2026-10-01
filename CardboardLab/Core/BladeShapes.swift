import Foundation

/// Blade outlines in blade space: the shoulder line is x = 0, the blade runs toward −x
/// (tip at x = −length), the tang toward +x, and the centre line is v = 0.
public enum BladeShapes {
    // MARK: Sampling helpers

    /// Parameter samples from shoulder (0) to tip (1), denser near the tip.
    static func samples(_ n: Int) -> [Float] {
        (0...n).map { i in
            let u = Float(i) / Float(n)
            return 1 - pow(1 - u, 1.4)
        }
    }

    /// Catmull-Rom through (s, value) keys, evaluated at `s`.
    static func spline(_ keys: [(Float, Float)], _ s: Float) -> Float {
        guard keys.count > 1 else { return keys.first?.1 ?? 0 }
        if s <= keys[0].0 { return keys[0].1 }
        if s >= keys[keys.count - 1].0 { return keys[keys.count - 1].1 }
        var i = 0
        while i < keys.count - 2 && s > keys[i + 1].0 { i += 1 }
        let p0 = keys[max(i - 1, 0)].1, p1 = keys[i].1, p2 = keys[i + 1].1, p3 = keys[min(i + 2, keys.count - 1)].1
        let t = (s - keys[i].0) / max(keys[i + 1].0 - keys[i].0, 1e-5)
        let t2 = t * t, t3 = t2 * t
        return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }

    static func linear(_ keys: [(Float, Float)], _ s: Float) -> Float {
        if s <= keys[0].0 { return keys[0].1 }
        for i in 0..<(keys.count - 1) where s <= keys[i + 1].0 {
            let t = (s - keys[i].0) / max(keys[i + 1].0 - keys[i].0, 1e-5)
            return mixf(keys[i].1, keys[i + 1].1, t)
        }
        return keys[keys.count - 1].1
    }

    // MARK: Ridge (symmetric) blades

    /// Half-width as a fraction of the shoulder half-width, s = 0 shoulder … 1 tip.
    public static func ridgeFraction(_ tip: TipStyle, _ s: Float) -> Float {
        switch tip {
        case .spear:
            return linear([(0, 1), (0.6, 1), (1, 0)], s)
        case .drop:
            if s <= 0.42 { return 1 }
            let k = (s - 0.42) / 0.58
            return max(0, (1 - k * k).squareRoot())
        case .leaf:
            return max(0, spline([(0, 0.78), (0.3, 1.0), (0.55, 1.1), (0.78, 0.82), (0.93, 0.36), (1, 0)], s))
        case .needle:
            return linear([(0, 1), (0.1, 0.82), (1, 0)], s)
        case .flame:
            let wave = (1 - 0.5 * s) * (1 + 0.17 * sin(s * 5.5 * .pi))
            return max(0, wave * min(1, (1 - s) / 0.16))
        default:
            return linear([(0, 1), (0.6, 1), (1, 0)], s)
        }
    }

    /// Upper half (v ≤ 0) of a ridge blade including its tang; the ridge is the straight
    /// edge from the tip (−length, 0) to (tangLength, 0).
    public static func ridgeUpper(_ b: BladeSpec, tangHalf: Float) -> [V2] {
        let h0 = b.width / 2
        let L = b.length
        var pts: [V2] = [V2(-L, 0)]
        // Edge from the tip back to the shoulder.
        var edge: [V2] = []
        for s in samples(26).reversed() where s < 0.999 {
            edge.append(V2(-L * s, -max(h0 * ridgeFraction(b.tip, s), 0.004)))
        }
        if b.edge == .serrated { edge = serrate(edge, from: -L * 0.42, to: -L * 0.06, depth: 0.13, outward: V2(0, -1)) }
        pts += edge
        pts += [V2(0, -tangHalf), V2(b.tangLength, -tangHalf), V2(b.tangLength, 0)]
        return dedupe(pts)
    }

    /// Edge of the upper half from shoulder to tip (sharpening path), in blade space.
    public static func ridgeEdgePath(_ b: BladeSpec) -> [V2] {
        let h0 = b.width / 2
        return samples(26).filter { $0 >= 0.04 }.map { s in V2(-b.length * s, -h0 * ridgeFraction(b.tip, s)) }
    }

    // MARK: Laminate (single-edged) blades

    public struct LaminateShape {
        public var outline: [V2]
        /// Cutting edge from near the shoulder to the tip (sharpening path).
        public var edge: [V2]
        /// Middle of the blade from shoulder to tip (glue path).
        public var centre: [V2]
    }

    /// Outline of one layer of a laminated blade (spine toward −v, edge toward +v).
    public static func laminate(_ b: BladeSpec, tangHalf: Float) -> LaminateShape {
        let L = b.length, w = b.width
        let a0 = w * 0.4, b0 = w * 0.6
        // Hooks curve toward the edge (claw); everything else sweeps back toward the spine.
        let bend: Float = b.tip == .hook ? 1 : -1
        let sag = b.curve * L * (b.tip == .hook ? 0.32 : 0.2)
        func centre(_ s: Float) -> V2 { V2(-L * s, bend * sag * s * s) }
        func normal(_ s: Float) -> V2 {
            let a = centre(max(0, s - 0.01)), c = centre(min(1, s + 0.01))
            let t = (c - a).unit
            return V2(t.y, -t.x)   // points to +v on a straight blade
        }
        var spineOff: (Float) -> Float
        var edgeOff: (Float) -> Float
        var frontEdge = false
        switch b.tip {
        case .clip:
            let tipY = -0.12 * w
            spineOff = { s in s <= 0.58 ? -a0 : -a0 + (tipY + a0) * pow((s - 0.58) / 0.42, 1.5) }
            edgeOff = { s in
                let base = b0 * (1 + 0.1 * sin(.pi * min(s, 0.72)))
                if s <= 0.72 { return base }
                let k = (s - 0.72) / 0.28
                return tipY + (base - tipY) * max(0, (1 - k * k).squareRoot())
            }
        case .tanto:
            let tipY = -a0 + 0.06
            spineOff = { _ in -a0 }
            edgeOff = { s in linear([(0, b0), (0.84, b0), (0.93, b0 * 0.42), (1, tipY)], s) }
        case .curved:
            let tipY = -a0 * 0.9
            spineOff = { s in -a0 * (1 - 0.15 * s) + (s > 0.9 ? (tipY + a0 * 0.85) * (s - 0.9) / 0.1 : 0) }
            edgeOff = { s in
                let belly = b0 * (1 + 0.4 * sin(.pi * pow(s, 1.2)))
                if s <= 0.78 { return belly }
                let k = (s - 0.78) / 0.22
                return tipY + (belly - tipY) * max(0, (1 - k * k).squareRoot())
            }
        case .hook:
            let tipY = -a0 * 0.55
            spineOff = { s in -a0 * (1 - 0.45 * s) }
            edgeOff = { s in
                let base = b0 * (1 - 0.45 * s)
                if s <= 0.75 { return base }
                let k = (s - 0.75) / 0.25
                return tipY + (base - tipY) * max(0, (1 - k * k).squareRoot())
            }
        case .cleaver:
            frontEdge = true
            spineOff = { _ in -a0 }
            edgeOff = { s in b0 * (1 + 0.28 * s) }
        default:
            spineOff = { s in -a0 * (1 - s) }
            edgeOff = { s in b0 * (1 - s) }
        }
        let ss = samples(28)
        var spine = ss.map { s in centre(s) + normal(s) * spineOff(s) }
        var edge = ss.map { s in centre(s) + normal(s) * edgeOff(s) }
        let middle = ss.map { s in centre(s) + normal(s) * ((spineOff(s) + edgeOff(s)) / 2) }
        if b.edge == .serrated {
            // Saw-back on the spine of single-edged blades.
            spine = serrate(spine, from: -L * 0.5, to: -L * 0.12, depth: 0.16, outward: V2(0, -1))
        }
        var outline: [V2] = spine
        if frontEdge {
            outline += edge.reversed()
        } else {
            outline += edge.reversed().dropFirst()
        }
        outline += [V2(0, tangHalf), V2(b.tangLength, tangHalf), V2(b.tangLength, -tangHalf), V2(0, -tangHalf)]
        edge = Array(edge.dropFirst(2))
        return LaminateShape(outline: dedupe(outline), edge: edge, centre: middle)
    }

    // MARK: Helpers

    /// Replaces the stretch of a polyline with x in [from, to] by saw teeth pushed
    /// along `outward`.
    static func serrate(_ line: [V2], from: Float, to: Float, depth: Float, outward: V2) -> [V2] {
        let pl = Polyline(line.map { $0.onMat() })
        var out: [V2] = []
        var inside = false
        for p in line {
            let isIn = p.x >= min(from, to) && p.x <= max(from, to)
            if isIn && !inside {
                inside = true
                // Teeth: sample the original line at a fine pitch.
                let pitch: Float = 0.3
                var d: Float = 0
                var teeth: [V2] = []
                while d <= pl.length {
                    let q = pl.point(at: d)
                    if q.x >= min(from, to) && q.x <= max(from, to) {
                        teeth.append(q.xz)
                        teeth.append(pl.point(at: min(pl.length, d + pitch * 0.5)).xz + outward * depth)
                    }
                    d += pitch
                }
                out += teeth
            }
            if !isIn {
                inside = false
                out.append(p)
            }
        }
        return out
    }

    static func dedupe(_ pts: [V2]) -> [V2] {
        var out: [V2] = []
        for p in pts where out.last.map({ $0.dist(p) > 1e-3 }) ?? true { out.append(p) }
        if let f = out.first, let l = out.last, out.count > 2, f.dist(l) < 1e-3 { out.removeLast() }
        return out
    }
}

public extension Poly {
    /// True if no two non-adjacent edges of the closed polygon intersect.
    static func isSimple(_ p: [V2]) -> Bool {
        let n = p.count
        guard n > 3 else { return true }
        func cross(_ o: V2, _ a: V2, _ b: V2) -> Float { (a - o).crossp(b - o) }
        func intersects(_ a: V2, _ b: V2, _ c: V2, _ d: V2) -> Bool {
            let d1 = cross(c, d, a), d2 = cross(c, d, b), d3 = cross(a, b, c), d4 = cross(a, b, d)
            return ((d1 > 1e-7 && d2 < -1e-7) || (d1 < -1e-7 && d2 > 1e-7)) &&
                ((d3 > 1e-7 && d4 < -1e-7) || (d3 < -1e-7 && d4 > 1e-7))
        }
        for i in 0..<n {
            let a = p[i], b = p[(i + 1) % n]
            for j in stride(from: i + 2, to: n, by: 1) {
                if i == 0 && j == n - 1 { continue }
                if intersects(a, b, p[j], p[(j + 1) % n]) { return false }
            }
        }
        return true
    }
}
