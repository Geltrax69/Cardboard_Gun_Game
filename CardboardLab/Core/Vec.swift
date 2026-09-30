import Foundation

// Pure-Swift math used by the whole game. Deliberately free of SceneKit / simd so it
// compiles (and is unit tested) on any platform. Member names are chosen so they
// never collide with the global functions exported by Apple's `simd` module.

public typealias V2 = SIMD2<Float>
public typealias V3 = SIMD3<Float>

public extension SIMD2 where Scalar == Float {
    var len: Float { (x * x + y * y).squareRoot() }
    var unit: V2 { let l = len; return l > 1e-9 ? self / l : V2(0, 0) }
    /// Counter-clockwise perpendicular (in a y-up frame).
    var perp: V2 { V2(-y, x) }
    func dotp(_ o: V2) -> Float { x * o.x + y * o.y }
    func crossp(_ o: V2) -> Float { x * o.y - y * o.x }
    func dist(_ o: V2) -> Float { (self - o).len }
    /// Lift a template point (u, v) onto the mat plane: x = u, z = v.
    func onMat(_ y: Float = 0) -> V3 { V3(x, y, self.y) }
}

public extension SIMD3 where Scalar == Float {
    var len: Float { (x * x + y * y + z * z).squareRoot() }
    var unit: V3 { let l = len; return l > 1e-9 ? self / l : V3(0, 0, 0) }
    func dotp(_ o: V3) -> Float { x * o.x + y * o.y + z * o.z }
    func crossp(_ o: V3) -> V3 {
        V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }
    func dist(_ o: V3) -> Float { (self - o).len }
    var xz: V2 { V2(x, z) }
}

public let up3 = V3(0, 1, 0)

@inlinable public func mixf(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inlinable public func mix3(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }
@inlinable public func mix2(_ a: V2, _ b: V2, _ t: Float) -> V2 { a + (b - a) * t }
@inlinable public func clampf(_ v: Float, _ lo: Float, _ hi: Float) -> Float { Swift.min(hi, Swift.max(lo, v)) }
@inlinable public func saturate(_ v: Float) -> Float { clampf(v, 0, 1) }
@inlinable public func smooth(_ t: Float) -> Float { let x = saturate(t); return x * x * (3 - 2 * x) }
@inlinable public func radians(_ deg: Float) -> Float { deg * .pi / 180 }

/// Unit quaternion (x, y, z, w).
public struct Quat: Equatable {
    public var x: Float, y: Float, z: Float, w: Float

    public init(x: Float, y: Float, z: Float, w: Float) {
        self.x = x; self.y = y; self.z = z; self.w = w
    }

    public static let identity = Quat(x: 0, y: 0, z: 0, w: 1)

    public init(axis: V3, angle: Float) {
        let a = axis.unit
        let s = sin(angle / 2)
        self.init(x: a.x * s, y: a.y * s, z: a.z * s, w: cos(angle / 2))
    }

    /// Yaw (about +y), then pitch (about local +x), then roll (about local +z).
    public static func euler(yaw: Float, pitch: Float, roll: Float = 0) -> Quat {
        Quat(axis: V3(0, 1, 0), angle: yaw) * Quat(axis: V3(1, 0, 0), angle: pitch) * Quat(axis: V3(0, 0, 1), angle: roll)
    }

    public static func * (a: Quat, b: Quat) -> Quat {
        Quat(
            x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
        )
    }

    public var conjugate: Quat { Quat(x: -x, y: -y, z: -z, w: w) }

    public var normalized: Quat {
        let l = (x * x + y * y + z * z + w * w).squareRoot()
        return l > 1e-9 ? Quat(x: x / l, y: y / l, z: z / l, w: w / l) : .identity
    }

    public func rotate(_ v: V3) -> V3 {
        let u = V3(x, y, z)
        let s = w
        return u * (2 * u.dotp(v)) + v * (s * s - u.dotp(u)) + u.crossp(v) * (2 * s)
    }

    public func slerp(_ to: Quat, _ t: Float) -> Quat {
        var b = to
        var cosom = x * b.x + y * b.y + z * b.z + w * b.w
        if cosom < 0 { cosom = -cosom; b = Quat(x: -b.x, y: -b.y, z: -b.z, w: -b.w) }
        var k0: Float, k1: Float
        if 1 - cosom > 1e-5 {
            let omega = acos(cosom)
            let sinom = sin(omega)
            k0 = sin((1 - t) * omega) / sinom
            k1 = sin(t * omega) / sinom
        } else {
            k0 = 1 - t
            k1 = t
        }
        return Quat(x: x * k0 + b.x * k1, y: y * k0 + b.y * k1, z: z * k0 + b.z * k1, w: w * k0 + b.w * k1).normalized
    }

    /// Rotation that turns `from` into `to` (both unit vectors).
    public static func between(_ from: V3, _ to: V3) -> Quat {
        let f = from.unit, t = to.unit
        let d = f.dotp(t)
        if d > 0.99999 { return .identity }
        if d < -0.99999 {
            var axis = V3(1, 0, 0).crossp(f)
            if axis.len < 1e-4 { axis = V3(0, 1, 0).crossp(f) }
            return Quat(axis: axis, angle: .pi)
        }
        let c = f.crossp(t)
        return Quat(x: c.x, y: c.y, z: c.z, w: 1 + d).normalized
    }
}

/// Rigid transform: p' = rot * p + pos.
public struct Pose: Equatable {
    public var rot: Quat
    public var pos: V3

    public init(rot: Quat = .identity, pos: V3 = V3(0, 0, 0)) {
        self.rot = rot
        self.pos = pos
    }

    public static let identity = Pose()

    public func apply(_ p: V3) -> V3 { rot.rotate(p) + pos }
    public func applyVector(_ v: V3) -> V3 { rot.rotate(v) }

    /// a * b applies b first, then a.
    public static func * (a: Pose, b: Pose) -> Pose {
        Pose(rot: (a.rot * b.rot).normalized, pos: a.rot.rotate(b.pos) + a.pos)
    }

    public var inverse: Pose {
        let ri = rot.conjugate
        return Pose(rot: ri, pos: ri.rotate(pos) * -1)
    }

    public static func translation(_ t: V3) -> Pose { Pose(rot: .identity, pos: t) }

    public static func rotation(about point: V3, axis: V3, angle: Float) -> Pose {
        let q = Quat(axis: axis, angle: angle)
        return Pose(rot: q, pos: point - q.rotate(point))
    }

    public func lerp(_ to: Pose, _ t: Float) -> Pose {
        Pose(rot: rot.slerp(to.rot, t), pos: mix3(pos, to.pos, t))
    }
}
