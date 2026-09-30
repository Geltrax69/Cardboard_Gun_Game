import Foundation

/// Orbit camera described by target / distance / polar (angle from straight down) /
/// azimuth. Provides the camera basis, projection of world points to screen points
/// and screen rays — computed here rather than queried from SceneKit so input,
/// overlays and rendering always agree.
public struct OrbitCamera: Equatable {
    public var target: V3
    public var distance: Float
    public var polar: Float
    public var azimuth: Float
    /// Vertical field of view in radians.
    public var fovY: Float
    /// Viewport size in points.
    public var viewSize: V2

    public init(target: V3 = V3(0, 0, 0), distance: Float = 30, polar: Float = 0.1, azimuth: Float = 0,
                fovY: Float = radians(30), viewSize: V2 = V2(1180, 820)) {
        self.target = target
        self.distance = distance
        self.polar = polar
        self.azimuth = azimuth
        self.fovY = fovY
        self.viewSize = viewSize
    }

    public var back: V3 { V3(sin(polar) * sin(azimuth), cos(polar), sin(polar) * cos(azimuth)) }
    public var right: V3 { V3(cos(azimuth), 0, -sin(azimuth)) }
    public var up: V3 { back.crossp(right).unit }
    public var forward: V3 { back * -1 }
    public var eye: V3 { target + back * distance }
    public var aspect: Float { viewSize.y > 0 ? viewSize.x / viewSize.y : 1 }

    /// Orientation for a camera node (SceneKit cameras look down their local −z).
    public var orientation: Quat { Quat.fromBasis(x: right, y: up, z: back) }

    /// World → screen points (origin top-left). `z` is the view depth (> 0 in front).
    public func project(_ p: V3) -> (point: V2, depth: Float) {
        let rel = p - eye
        let z = rel.dotp(forward)
        let k = 1 / tan(fovY / 2)
        let x = rel.dotp(right) / max(z, 1e-4) * k / aspect
        let y = rel.dotp(up) / max(z, 1e-4) * k
        return (V2((x * 0.5 + 0.5) * viewSize.x, (0.5 - y * 0.5) * viewSize.y), z)
    }

    public func screen(_ p: V3) -> V2 { project(p).point }

    public func ray(_ s: V2) -> (origin: V3, dir: V3) {
        let nx = s.x / viewSize.x * 2 - 1
        let ny = 1 - s.y / viewSize.y * 2
        let t = tan(fovY / 2)
        let dir = (forward + right * (nx * t * aspect) + up * (ny * t)).unit
        return (eye, dir)
    }

    /// Intersection of the screen ray with the horizontal plane y = height.
    public func hit(_ s: V2, planeY height: Float) -> V3? {
        let (o, d) = ray(s)
        guard abs(d.y) > 1e-5 else { return nil }
        let k = (height - o.y) / d.y
        guard k > 0 else { return nil }
        return o + d * k
    }

    /// Intersection with an arbitrary plane (point + normal).
    public func hit(_ s: V2, planePoint p: V3, normal n: V3) -> V3? {
        let (o, d) = ray(s)
        let den = d.dotp(n)
        guard abs(den) > 1e-5 else { return nil }
        let k = (p - o).dotp(n) / den
        guard k > 0 else { return nil }
        return o + d * k
    }

    /// World units per screen point at a given depth.
    public func unitsPerPoint(atDepth z: Float) -> Float {
        2 * z * tan(fovY / 2) / max(viewSize.y, 1)
    }

    /// Distance at which a w×d rectangle on the mat fits the usable screen region.
    public func fitDistance(width w: Float, depth d: Float, polar p: Float,
                            safeTop: Float = 0.16, safeBottom: Float = 0.14, safeSide: Float = 0.05) -> Float {
        let t = tan(fovY / 2)
        let usableV = max(0.3, 1 - safeTop - safeBottom)
        let usableH = max(0.3, 1 - 2 * safeSide)
        let depthExtent = d * cos(p) + 0.5 * sin(p)
        let dv = depthExtent / 2 / (t * usableV)
        let dh = w / 2 / (t * aspect * usableH)
        return max(dv, dh)
    }

    public func lerp(_ o: OrbitCamera, _ k: Float) -> OrbitCamera {
        var c = self
        c.target = mix3(target, o.target, k)
        c.distance = mixf(distance, o.distance, k)
        c.polar = mixf(polar, o.polar, k)
        c.azimuth = mixf(azimuth, o.azimuth, k)
        return c
    }
}

public extension Quat {
    /// Quaternion from an orthonormal basis (columns x, y, z).
    static func fromBasis(x: V3, y: V3, z: V3) -> Quat {
        let m00 = x.x, m10 = x.y, m20 = x.z
        let m01 = y.x, m11 = y.y, m21 = y.z
        let m02 = z.x, m12 = z.y, m22 = z.z
        let trace = m00 + m11 + m22
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            return Quat(x: (m21 - m12) / s, y: (m02 - m20) / s, z: (m10 - m01) / s, w: 0.25 * s).normalized
        } else if m00 > m11 && m00 > m22 {
            let s = (1 + m00 - m11 - m22).squareRoot() * 2
            return Quat(x: 0.25 * s, y: (m01 + m10) / s, z: (m02 + m20) / s, w: (m21 - m12) / s).normalized
        } else if m11 > m22 {
            let s = (1 + m11 - m00 - m22).squareRoot() * 2
            return Quat(x: (m01 + m10) / s, y: 0.25 * s, z: (m12 + m21) / s, w: (m02 - m20) / s).normalized
        } else {
            let s = (1 + m22 - m00 - m11).squareRoot() * 2
            return Quat(x: (m02 + m20) / s, y: (m12 + m21) / s, z: 0.25 * s, w: (m10 - m01) / s).normalized
        }
    }
}
