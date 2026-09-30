import Foundation

/// 2D polygon helpers in template space (u right, v down on screen).
public enum Poly {
    /// Shoelace signed area (positive = counter-clockwise in a y-up frame).
    public static func signedArea(_ p: [V2]) -> Float {
        guard p.count >= 3 else { return 0 }
        var s: Float = 0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    public static func centroid(_ p: [V2]) -> V2 {
        let a = signedArea(p)
        if abs(a) < 1e-8 { return p.reduce(V2(0, 0), +) / Float(max(p.count, 1)) }
        var c = V2(0, 0)
        for i in 0..<p.count {
            let a0 = p[i], b0 = p[(i + 1) % p.count]
            let k = a0.x * b0.y - b0.x * a0.y
            c += (a0 + b0) * k
        }
        return c / (6 * a)
    }

    public static func contains(_ p: [V2], _ q: V2) -> Bool {
        var inside = false
        var j = p.count - 1
        for i in 0..<p.count {
            let a = p[i], b = p[j]
            if (a.y > q.y) != (b.y > q.y) {
                let x = (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x
                if q.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    public static func contains(outer: [V2], holes: [[V2]], _ q: V2) -> Bool {
        guard contains(outer, q) else { return false }
        for h in holes where contains(h, q) { return false }
        return true
    }

    public static func bounds(_ p: [V2]) -> (min: V2, max: V2) {
        var lo = V2(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var hi = V2(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        for q in p {
            lo = V2(min(lo.x, q.x), min(lo.y, q.y))
            hi = V2(max(hi.x, q.x), max(hi.y, q.y))
        }
        return (lo, hi)
    }

    public static func translate(_ p: [V2], _ d: V2) -> [V2] { p.map { $0 + d } }

    public static func rect(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> [V2] {
        [V2(x0, y0), V2(x1, y0), V2(x1, y1), V2(x0, y1)]
    }

    /// Regular n-gon (used for punched holes).
    public static func circle(center: V2, radius: Float, sides: Int, phase: Float = 0) -> [V2] {
        (0..<sides).map { i in
            let a = phase + Float(i) / Float(sides) * 2 * .pi
            return center + V2(cos(a), sin(a)) * radius
        }
    }

    /// Distance from point to segment and the segment parameter of the closest point.
    public static func closestOnSegment(_ p: V2, _ a: V2, _ b: V2) -> (t: Float, dist: Float) {
        let ab = b - a
        let l2 = ab.dotp(ab)
        let t = l2 > 1e-12 ? saturate((p - a).dotp(ab) / l2) : 0
        return (t, p.dist(a + ab * t))
    }

    public static func pointLineDistance(_ p: V2, _ a: V2, _ b: V2) -> Float {
        let d = (b - a).unit
        return abs((p - a).crossp(d))
    }
}

/// A polyline in 3D with arc-length parameterisation (cut paths, glue paths, …).
public struct Polyline {
    public private(set) var points: [V3]
    public private(set) var cumulative: [Float]
    public var length: Float { cumulative.last ?? 0 }

    public init(_ points: [V3]) {
        self.points = points
        var c: [Float] = [0]
        c.reserveCapacity(points.count)
        for i in 1..<max(points.count, 1) {
            c.append(c[i - 1] + points[i].dist(points[i - 1]))
        }
        cumulative = c
    }

    public var segmentCount: Int { max(points.count - 1, 0) }

    /// Index of the segment containing arc length `d`.
    public func segment(at d: Float) -> Int {
        guard points.count > 1 else { return 0 }
        let x = clampf(d, 0, length)
        var lo = 0, hi = points.count - 2
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cumulative[mid] <= x { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    public func point(at d: Float) -> V3 {
        guard points.count > 1 else { return points.first ?? V3(0, 0, 0) }
        let i = segment(at: d)
        let segLen = cumulative[i + 1] - cumulative[i]
        let t = segLen > 1e-9 ? (clampf(d, 0, length) - cumulative[i]) / segLen : 0
        return mix3(points[i], points[i + 1], t)
    }

    public func tangent(at d: Float) -> V3 {
        guard points.count > 1 else { return V3(1, 0, 0) }
        let i = segment(at: d)
        return (points[i + 1] - points[i]).unit
    }

    /// Points from arc length a to b (inclusive of interpolated ends and inner corners).
    public func slice(_ a: Float, _ b: Float) -> [V3] {
        guard b > a, points.count > 1 else { return [] }
        var out = [point(at: a)]
        let i0 = segment(at: a), i1 = segment(at: b)
        if i1 > i0 {
            for k in (i0 + 1)...i1 { out.append(points[k]) }
        }
        out.append(point(at: b))
        return out
    }

    public func transformed(_ pose: Pose) -> Polyline { Polyline(points.map { pose.apply($0) }) }
}
