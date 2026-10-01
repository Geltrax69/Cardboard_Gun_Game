import Foundation

/// How a board's faces look and feel: the pattern pressed into its liner.
public enum CardboardSurface: String, CaseIterable {
    /// Plain liner: faint mottling and short fibres.
    case smooth
    /// Kraft paper: long brown streaks and fibres.
    case kraft
    /// Single-face corrugated: flutes push ribs through the liner.
    case ribbed
    /// Recycled pulp: dark and light flecks.
    case speckled
    /// Clay-coated board: almost flat, very fine grain.
    case coated
    /// Scuffed and crushed: scratches, dents, rough patches.
    case rough
    /// An old shipping box: scuffs, a strip of tape, water stains and a faded stamp.
    case worn
}

/// Tileable procedural cardboard surfaces. Each surface is a height field plus a shading
/// field, turned into a detail map (white, with darker fibres, flecks and scuffs; the
/// board colour or paint is multiplied on top, so painted faces keep their texture) and
/// a normal map, so the roughness catches the light.
public enum SurfaceTexture {
    public static let size = 256
    /// World units one tile covers (cardboard faces use UV = position / 8).
    public static let tileUnits: Float = 8

    /// RGBA, 8 bits per channel, `size` × `size`, rows top to bottom.
    public struct Maps {
        public var detail: [UInt8]
        public var normal: [UInt8]
    }

    public static func maps(_ surface: CardboardSurface) -> Maps {
        var f = SurfaceField(size: size, seed: seed(surface))
        switch surface {
        case .smooth: f.smooth()
        case .kraft: f.kraft()
        case .ribbed: f.ribbed()
        case .speckled: f.speckled()
        case .coated: f.coated()
        case .rough: f.rough(scale: 1)
        case .worn: f.worn()
        }
        return Maps(detail: f.detailRGBA(), normal: f.normalRGBA(strength: strength(surface)))
    }

    /// How strongly the height field bends the light.
    static func strength(_ s: CardboardSurface) -> Float {
        switch s {
        case .smooth: return 0.9
        case .kraft: return 1.1
        case .ribbed: return 0.8
        case .speckled: return 1.0
        case .coated: return 0.6
        case .rough: return 1.4
        case .worn: return 1.2
        }
    }

    /// Fixed seeds, so every launch draws the same boards.
    static func seed(_ s: CardboardSurface) -> UInt64 {
        switch s {
        case .smooth: return 0x51A7
        case .kraft: return 0xC2AF7
        case .ribbed: return 0x21BB
        case .speckled: return 0x5BEC
        case .coated: return 0xC0A7
        case .rough: return 0x2006
        case .worn: return 0x0B0C5
        }
    }
}

/// Small deterministic random generator (SplitMix64).
struct SplitMix {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }

    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * unit() }

    mutating func chance(_ p: Float) -> Bool { unit() < p }
}

/// Value noise that wraps every `px` × `py` lattice cells, summed over octaves.
struct TileNoise {
    private var layers: [(px: Int, py: Int, values: [Float], amp: Float)] = []

    init(px: Int, py: Int, octaves: Int, gain: Float = 0.5, rng: inout SplitMix) {
        var amp: Float = 1, total: Float = 0
        var x = px, y = py
        for _ in 0..<octaves {
            let values = (0..<(x * y)).map { _ in rng.unit() * 2 - 1 }
            layers.append((x, y, values, amp))
            total += amp
            amp *= gain
            x *= 2
            y *= 2
        }
        layers = layers.map { ($0.px, $0.py, $0.values, $0.amp / total) }
    }

    /// −1…1 at tile coordinates (u, v), each wrapping at 1.
    func sample(_ u: Float, _ v: Float) -> Float {
        var sum: Float = 0
        for l in layers {
            let x = u * Float(l.px), y = v * Float(l.py)
            let fx = x - x.rounded(.down), fy = y - y.rounded(.down)
            let i = Int(x.rounded(.down)), j = Int(y.rounded(.down))
            func at(_ a: Int, _ b: Int) -> Float {
                l.values[((b % l.py + l.py) % l.py) * l.px + ((a % l.px + l.px) % l.px)]
            }
            let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
            let top = at(i, j) + (at(i + 1, j) - at(i, j)) * sx
            let bottom = at(i, j + 1) + (at(i + 1, j + 1) - at(i, j + 1)) * sx
            sum += (top + (bottom - top) * sy) * l.amp
        }
        return sum
    }
}

/// The height (in pixels) and darkening (0 = white) of one tile, built up from layers.
struct SurfaceField {
    let n: Int
    var height: [Float]
    var shade: [Float]
    var rng: SplitMix

    init(size: Int, seed: UInt64) {
        n = size
        height = Array(repeating: 0, count: size * size)
        shade = Array(repeating: 0, count: size * size)
        rng = SplitMix(state: seed)
    }

    private func wrap(_ i: Int) -> Int { (i % n + n) % n }

    /// Runs `f(u, v)` for every pixel and adds what it returns.
    mutating func each(_ f: (Float, Float) -> (h: Float, s: Float)) {
        let inv = 1 / Float(n)
        for y in 0..<n {
            for x in 0..<n {
                let r = f((Float(x) + 0.5) * inv, (Float(y) + 0.5) * inv)
                height[y * n + x] += r.h
                shade[y * n + x] += r.s
            }
        }
    }

    /// A soft-edged stroke from a to b (pixels, may run past the edge: it wraps).
    mutating func line(_ a: V2, _ b: V2, width w: Float, h: Float, s: Float) {
        let lo = V2(min(a.x, b.x) - w - 1, min(a.y, b.y) - w - 1)
        let hi = V2(max(a.x, b.x) + w + 1, max(a.y, b.y) + w + 1)
        let ab = b - a
        let len2 = max(ab.x * ab.x + ab.y * ab.y, 1e-6)
        for y in Int(lo.y.rounded(.down))...Int(hi.y.rounded(.up)) {
            for x in Int(lo.x.rounded(.down))...Int(hi.x.rounded(.up)) {
                let p = V2(Float(x) + 0.5, Float(y) + 0.5)
                let t = max(0, min(1, ((p - a).x * ab.x + (p - a).y * ab.y) / len2))
                let d = (p - (a + ab * t)).len
                guard d < w else { continue }
                let k = 1 - d / w
                let falloff = k * k * (3 - 2 * k)
                let i = wrap(y) * n + wrap(x)
                height[i] += h * falloff
                shade[i] += s * falloff
            }
        }
    }

    /// A round mark: `profile(r)` (r = 0 centre … 1 rim) scales the height and shade.
    mutating func disc(_ c: V2, radius: Float, h: Float, s: Float, profile: (Float) -> Float) {
        let r = Int(radius.rounded(.up)) + 1
        for y in (Int(c.y) - r)...(Int(c.y) + r) {
            for x in (Int(c.x) - r)...(Int(c.x) + r) {
                let d = V2(Float(x) + 0.5 - c.x, Float(y) + 0.5 - c.y).len / radius
                guard d < 1 else { continue }
                let k = profile(d)
                let i = wrap(y) * n + wrap(x)
                height[i] += h * k
                shade[i] += s * k
            }
        }
    }

    private mutating func point() -> V2 { V2(rng.range(0, Float(n)), rng.range(0, Float(n))) }

    /// Short fibres lying mostly along the paper's machine direction (u).
    mutating func fibres(_ count: Int, length: ClosedRange<Float>, spread: Float, width: ClosedRange<Float>, h: Float,
                         s: ClosedRange<Float>) {
        for _ in 0..<count {
            let a = point()
            let angle = rng.range(-spread, spread)
            let l = rng.range(length.lowerBound, length.upperBound)
            let b = a + V2(cos(angle), sin(angle)) * l
            line(a, b, width: rng.range(width.lowerBound, width.upperBound), h: h, s: rng.range(s.lowerBound, s.upperBound))
        }
    }

    // MARK: Surfaces

    mutating func smooth() {
        let mottle = TileNoise(px: 4, py: 4, octaves: 4, rng: &rng)
        let grain = TileNoise(px: 16, py: 96, octaves: 2, rng: &rng)
        each { u, v in
            let m = mottle.sample(u, v), g = grain.sample(u, v)
            return (0.9 * m + 0.5 * g, 0.05 * (m * 0.5 + 0.5) + 0.035 * max(0, g))
        }
        fibres(70, length: 5...16, spread: 0.35, width: 0.7...1.1, h: 0.5, s: 0.03...0.07)
    }

    mutating func kraft() {
        let mottle = TileNoise(px: 4, py: 4, octaves: 4, rng: &rng)
        let streaks = TileNoise(px: 4, py: 64, octaves: 3, rng: &rng)
        each { u, v in
            let m = mottle.sample(u, v), st = streaks.sample(u, v)
            return (1.0 * m + 0.9 * st, 0.06 * (m * 0.5 + 0.5) + 0.11 * max(0, st))
        }
        fibres(260, length: 10...42, spread: 0.22, width: 0.6...1.2, h: 0.7, s: 0.06...0.16)
        fibres(40, length: 6...18, spread: 1.4, width: 0.6...0.9, h: 0.5, s: 0.08...0.14)
    }

    mutating func ribbed() {
        let mottle = TileNoise(px: 4, py: 4, octaves: 4, rng: &rng)
        let grain = TileNoise(px: 16, py: 96, octaves: 2, rng: &rng)
        // 16 flutes per tile: one every half unit.
        each { u, v in
            let rib = sin(u * 2 * .pi * 16)
            let m = mottle.sample(u, v), g = grain.sample(u, v)
            return (1.5 * (rib * 0.5 + 0.5) + 0.7 * m + 0.4 * g,
                    0.022 * (0.5 - 0.5 * rib) + 0.05 * (m * 0.5 + 0.5) + 0.03 * max(0, g))
        }
        fibres(50, length: 5...14, spread: 0.3, width: 0.7...1.0, h: 0.4, s: 0.03...0.06)
    }

    mutating func speckled() {
        let mottle = TileNoise(px: 4, py: 4, octaves: 5, rng: &rng)
        let grain = TileNoise(px: 32, py: 32, octaves: 2, rng: &rng)
        each { u, v in
            let m = mottle.sample(u, v), g = grain.sample(u, v)
            return (1.1 * m + 0.5 * g, 0.08 + 0.08 * (m * 0.5 + 0.5) + 0.03 * g)
        }
        for _ in 0..<700 {
            let c = point()
            if rng.chance(0.8) {
                disc(c, radius: rng.range(0.7, 2.0), h: 0.5, s: rng.range(0.2, 0.55)) { 1 - $0 * $0 }
            } else {
                // Light flecks: paper that never took the grey.
                disc(c, radius: rng.range(0.8, 2.2), h: 0.3, s: -0.1) { 1 - $0 * $0 }
            }
        }
        fibres(90, length: 4...14, spread: 1.6, width: 0.6...1.0, h: 0.4, s: 0.1...0.3)
    }

    mutating func coated() {
        let grain = TileNoise(px: 32, py: 32, octaves: 3, rng: &rng)
        let mottle = TileNoise(px: 4, py: 4, octaves: 3, rng: &rng)
        each { u, v in
            let g = grain.sample(u, v), m = mottle.sample(u, v)
            return (0.35 * g + 0.4 * m, 0.012 * (g * 0.5 + 0.5) + 0.02 * (m * 0.5 + 0.5))
        }
    }

    /// Scratches, dents and crushed patches; `scale` tones it down for older layers.
    mutating func rough(scale k: Float) {
        let lumpy = TileNoise(px: 6, py: 6, octaves: 5, gain: 0.55, rng: &rng)
        let patches = TileNoise(px: 3, py: 3, octaves: 3, rng: &rng)
        let crush = TileNoise(px: 48, py: 48, octaves: 2, rng: &rng)
        let streaks = TileNoise(px: 4, py: 64, octaves: 2, rng: &rng)
        each { u, v in
            let l = lumpy.sample(u, v), p = patches.sample(u, v), c = crush.sample(u, v), st = streaks.sample(u, v)
            let crushed = max(0, min(1, (p - 0.12) * 4))
            return (k * (2.2 * l + 2.4 * crushed * c + 0.5 * st),
                    k * (0.07 * (l * 0.5 + 0.5) + 0.12 * crushed + 0.06 * max(0, st)))
        }
        // Dents.
        for _ in 0..<Int(14 * k) {
            disc(point(), radius: rng.range(6, 18), h: -3.2 * k, s: 0.05 * k) { r in
                let q = 1 - r * r
                return q * q
            }
        }
        // Scuffs and scratches.
        for _ in 0..<Int(70 * k) {
            let a = point()
            let angle = rng.range(0, 2 * .pi)
            let l = rng.range(8, 56)
            let b = a + V2(cos(angle), sin(angle)) * l
            line(a, b, width: rng.range(0.8, 2.4), h: -1.1 * k, s: rng.range(0.1, 0.24) * k)
        }
        fibres(Int(120 * k), length: 8...30, spread: 0.3, width: 0.6...1.1, h: 0.6, s: (0.05 * k)...(0.12 * k))
    }

    mutating func worn() {
        rough(scale: 0.6)
        // Everything but the tape is a touch duller.
        each { _, _ in (0, 0.05) }
        // A strip of packing tape right across the tile.
        let y0 = rng.range(40, 90)
        let half: Float = 15
        let crinkle = TileNoise(px: 24, py: 6, octaves: 2, rng: &rng)
        for y in Int(y0 - half - 2)...Int(y0 + half + 2) {
            let d = abs(Float(y) + 0.5 - y0)
            for x in 0..<n {
                let i = wrap(y) * n + x
                if d < half {
                    // Tape: smooth, glossy and a little lighter, with crinkles.
                    let c = crinkle.sample(Float(x) / Float(n), Float(y) / Float(n))
                    height[i] = height[i] * 0.2 + 1.4 + 0.6 * c
                    shade[i] = max(-0.02, shade[i] * 0.25 - 0.03 + 0.03 * max(0, c))
                } else {
                    // Raised, darker tape edges.
                    let e = 1 - (d - half) / 2
                    height[i] += 0.8 * max(0, e)
                    shade[i] += 0.12 * max(0, e)
                }
            }
        }
        // Water stains: an uneven blot with a soft, darker tide mark.
        for _ in 0..<3 {
            let c = V2(rng.range(0, Float(n)), rng.range(Float(n) * 0.45, Float(n)))
            let r = rng.range(18, 34)
            let p1 = rng.range(0, 6.3), p2 = rng.range(0, 6.3)
            let reach = Int(r * 1.3) + 4
            for y in (Int(c.y) - reach)...(Int(c.y) + reach) {
                for x in (Int(c.x) - reach)...(Int(c.x) + reach) {
                    let d = V2(Float(x) + 0.5 - c.x, Float(y) + 0.5 - c.y)
                    let a = atan2(d.y, d.x)
                    let edge = r * (1 + 0.14 * sin(3 * a + p1) + 0.08 * sin(5 * a + p2))
                    let q = d.len - edge
                    let inside: Float = q < 0 ? 0.035 : 0
                    let rim = 0.09 * exp(-(q + 1.5) * (q + 1.5) / 10)
                    let i = wrap(y) * n + wrap(x)
                    shade[i] += inside + rim
                }
            }
        }
        // A faded stamp: "this way up" arrows and a ring.
        let fade = TileNoise(px: 16, py: 16, octaves: 2, rng: &rng)
        let stamp = V2(rng.range(140, 200), rng.range(150, 210))
        var ink = SurfaceField(size: n, seed: 1)
        for dx: Float in [-10, 10] {
            ink.line(stamp + V2(dx, 16), stamp + V2(dx, -12), width: 2.2, h: 0, s: 1)
            ink.line(stamp + V2(dx, -14), stamp + V2(dx - 7, -5), width: 2.2, h: 0, s: 1)
            ink.line(stamp + V2(dx, -14), stamp + V2(dx + 7, -5), width: 2.2, h: 0, s: 1)
        }
        ink.line(stamp + V2(-17, 21), stamp + V2(17, 21), width: 2.2, h: 0, s: 1)
        let ring = stamp + V2(-46, 4)
        ink.disc(ring, radius: 19, h: 0, s: 1) { q in max(0, 1 - abs(q - 0.85) * 9) }
        for i in shade.indices {
            let x = i % n, y = i / n
            let f = fade.sample(Float(x) / Float(n), Float(y) / Float(n)) * 0.5 + 0.5
            shade[i] += min(1, ink.shade[i]) * 0.42 * (0.35 + 0.65 * f)
        }
    }

    // MARK: Output

    /// White where the board is clean, darker where it's marked.
    func detailRGBA() -> [UInt8] {
        var out = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            let g = UInt8((max(0.3, min(1, 1 - shade[i])) * 255).rounded())
            out[i * 4] = g
            out[i * 4 + 1] = g
            out[i * 4 + 2] = g
        }
        return out
    }

    /// Tangent-space normals from the height field (wrapping at the edges).
    func normalRGBA(strength k: Float) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let dx = (height[y * n + wrap(x + 1)] - height[y * n + wrap(x - 1)]) / 2
                let dy = (height[wrap(y + 1) * n + x] - height[wrap(y - 1) * n + x]) / 2
                let v = V3(-dx * k, dy * k, 1).unit
                let i = (y * n + x) * 4
                out[i] = UInt8(((v.x * 0.5 + 0.5) * 255).rounded())
                out[i + 1] = UInt8(((v.y * 0.5 + 0.5) * 255).rounded())
                out[i + 2] = UInt8(((v.z * 0.5 + 0.5) * 255).rounded())
            }
        }
        return out
    }
}
