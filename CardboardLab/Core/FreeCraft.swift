import Foundation

/// Free Craft: the parts a player can combine, the level each one unlocks at, and
/// helpers that keep a design buildable. A part unlocks at the level of the first
/// campaign weapon that uses it, so crafting through the campaign opens up the designer.
public enum FreeCraftParts {
    // MARK: Unlock levels

    /// Level of the first campaign weapon matching `test`, or `fallback`.
    static func firstLevel(_ fallback: Int, _ test: (WeaponDesign) -> Bool) -> Int {
        WeaponDesign.campaign.firstIndex(where: test).map { Progression.unlockLevel(index: $0) } ?? fallback
    }

    public static func level(of kind: WeaponKind) -> Int {
        firstLevel(1) { $0.kind == kind }
    }

    public static func level(of build: BladeBuild) -> Int {
        firstLevel(1) { $0.blade?.build == build }
    }

    public static func level(of tip: TipStyle) -> Int {
        let fallback: [TipStyle: Int] = [.needle: 5, .cleaver: 6]
        return firstLevel(fallback[tip] ?? 1) { $0.blade?.tip == tip }
    }

    public static func level(of wing: WingStyle) -> Int {
        let fallback: [WingStyle: Int] = [.bearded: 10]
        return firstLevel(fallback[wing] ?? 1) { $0.guardClip?.style == wing || $0.endClip?.style == wing }
    }

    public static var serratedLevel: Int { firstLevel(8) { $0.blade?.edge == .serrated } }
    public static var fullerLevel: Int { firstLevel(5) { $0.blade?.fuller == true } }
    public static let maxWraps = 4

    public static let guardStyles: [WingStyle] = [.bar, .flared, .spiked, .disc]
    public static let pommelStyles: [WingStyle] = [.diamond, .knob, .spike]
    public static let axeHeads: [WingStyle] = [.bit, .doubleBit, .bearded]

    public static func tips(for build: BladeBuild) -> [TipStyle] {
        TipStyle.allCases.filter { build == .ridge ? $0.forRidge : !$0.forRidge }
    }

    // MARK: Slider ranges (the generator clamps to these too)

    public static func lengthRange(_ d: WeaponDesign) -> ClosedRange<Float> {
        guard let b = d.blade else { return 3.5...12 }
        return b.build == .laminate ? 3.5...min(9.5, 11.8 - b.tangLength) : 3.5...12
    }

    public static let widthRange: ClosedRange<Float> = 1.3...3.2

    public static func handleRange(_ kind: WeaponKind) -> ClosedRange<Float> {
        kind == .axe ? 6...10.5 : 3.4...6.5
    }

    public static func guardSpanRange(_ d: WeaponDesign) -> ClosedRange<Float> {
        (d.handleWidth * 0.5 + 0.6)...3.0
    }

    public static func endSizeRange(_ d: WeaponDesign) -> ClosedRange<Float> {
        d.kind == .axe ? 0.5...1.0 : 0.85...1.5
    }

    // MARK: Designs

    /// A sensible starting point for each kind.
    public static func starter(_ kind: WeaponKind) -> WeaponDesign {
        var d: WeaponDesign
        switch kind {
        case .knife: d = .knife
        case .dagger: d = .dagger
        case .sword: d = .shortSword
        case .axe: d = .handAxe
        }
        d.id = "free"
        d.name = autoName(d)
        return d
    }

    /// Default blade when switching an axe back to a bladed weapon.
    public static func defaultBlade(for kind: WeaponKind, build: BladeBuild = .ridge) -> BladeSpec {
        let length: Float = kind == .sword ? 9 : (kind == .dagger ? 6.8 : 6.2)
        if build == .laminate {
            return BladeSpec(build: .laminate, tip: .clip, length: min(length, 8.4), width: 2.1, curve: 0.15,
                             tangLength: kind == .sword ? 3.6 : 3.3)
        }
        return BladeSpec(build: .ridge, tip: kind == .knife ? .drop : .spear, length: length, width: 2.0,
                         tangLength: kind == .sword ? 3.6 : 3.3)
    }

    /// "Flame Dagger", "Hooked Knife", "Double Bit Axe", …
    public static func autoName(_ d: WeaponDesign) -> String {
        if let b = d.blade {
            let word: String
            switch b.tip {
            case .spear: word = d.kind == .sword ? "Broad" : "Spear"
            case .drop: word = "Drop Point"
            case .leaf: word = "Leaf"
            case .needle: word = "Needle"
            case .flame: word = "Flame"
            case .clip: word = "Clip Point"
            case .tanto: word = "Tanto"
            case .curved: word = "Curved"
            case .hook: word = "Hooked"
            case .cleaver: word = "Cleaver"
            }
            return b.edge == .serrated ? "Serrated \(word) \(d.kind.title)" : "\(word) \(d.kind.title)"
        }
        switch d.endClip?.style {
        case .doubleBit?: return "Double Bit Axe"
        case .bearded?: return "Bearded Axe"
        default: return "Custom Axe"
        }
    }

    /// Evenly spaced grip bands between the fittings.
    public static func wraps(count: Int, for d: WeaponDesign) -> [Float] {
        guard count > 0 else { return [] }
        let front = (d.guardClip?.depth ?? 0) + 0.15
        let back = d.handleLength - (d.endClip?.depth ?? 0) - 0.95
        guard back > front else { return [front] }
        if count == 1 { return [d.kind == .knife && d.guardClip == nil ? front : (front + back) / 2] }
        return (0..<count).map { front + (back - front) * Float($0) / Float(count - 1) }
    }

    /// Swaps any part that isn't unlocked at `level` for the nearest one that is, and
    /// keeps the design consistent (axes have no blade, tips match the blade build, …).
    public static func clamp(_ raw: WeaponDesign, level: Int) -> WeaponDesign {
        var d = raw
        if FreeCraftParts.level(of: d.kind) > level { d = starter(.knife) }
        if d.kind == .axe {
            d.blade = nil
            d.guardClip = nil
            if d.endClip == nil || !(d.endClip!.style.isAxeHead) || FreeCraftParts.level(of: d.endClip!.style) > level {
                d.endClip = ClipSpec(.bit, span: 3.0, depth: 2.6)
            }
            d.lanyardHole = false
        } else {
            var b = d.blade ?? defaultBlade(for: d.kind)
            if FreeCraftParts.level(of: b.build) > level { b.build = .ridge }
            if b.tip.forRidge != (b.build == .ridge) || FreeCraftParts.level(of: b.tip) > level {
                b.tip = b.build == .ridge ? .drop : .clip
            }
            if b.edge == .serrated && serratedLevel > level { b.edge = .plain }
            if b.fuller && (fullerLevel > level || b.build != .ridge) { b.fuller = false }
            d.blade = b
            if let g = d.guardClip, !g.style.isGuard || FreeCraftParts.level(of: g.style) > level { d.guardClip = nil }
            if let e = d.endClip, !e.style.isPommel || FreeCraftParts.level(of: e.style) > level { d.endClip = nil }
            if d.endClip != nil { d.lanyardHole = false }
        }
        if d.wraps.count > maxWraps { d.wraps = Array(d.wraps.prefix(maxWraps)) }
        d.id = "free"
        return d.sanitized()
    }

    /// A random design from the parts unlocked at `level`.
    public static func random<G: RandomNumberGenerator>(level: Int, using rng: inout G) -> WeaponDesign {
        let kinds = WeaponKind.allCases.filter { FreeCraftParts.level(of: $0) <= level }
        let kind = kinds.randomElement(using: &rng) ?? .knife
        var d = starter(kind)
        if kind == .axe {
            let heads = axeHeads.filter { FreeCraftParts.level(of: $0) <= level }
            d.handleLength = Float.random(in: handleRange(.axe), using: &rng)
            let size = Float.random(in: 0.6...1.0, using: &rng)
            d.endClip = ClipSpec(heads.randomElement(using: &rng) ?? .bit, span: 4.0 * size, depth: 3.4 * size)
        } else {
            let builds = BladeBuild.allCases.filter { FreeCraftParts.level(of: $0) <= level }
            let build = builds.randomElement(using: &rng) ?? .ridge
            var b = defaultBlade(for: kind, build: build)
            b.tip = tips(for: build).filter { FreeCraftParts.level(of: $0) <= level }.randomElement(using: &rng) ?? b.tip
            let range = kind == .sword ? Float(8)...12 : (kind == .dagger ? Float(5.5)...8 : Float(4.5)...7.5)
            b.length = Float.random(in: range, using: &rng)
            b.width = Float.random(in: 1.6...2.6, using: &rng)
            b.curve = build == .laminate ? Float.random(in: 0...0.8, using: &rng) : 0
            b.edge = serratedLevel <= level && Int.random(in: 0..<4, using: &rng) == 0 ? .serrated : .plain
            b.fuller = build == .ridge && fullerLevel <= level && Bool.random(using: &rng)
            d.blade = b
            let guards = guardStyles.filter { FreeCraftParts.level(of: $0) <= level }
            let skipGuard = kind == .knife && Bool.random(using: &rng)
            if let style = guards.randomElement(using: &rng), !skipGuard {
                d.guardClip = ClipSpec(style, span: Float.random(in: 1.4...2.8, using: &rng), depth: 0.55)
            } else {
                d.guardClip = nil
            }
            let pommels = pommelStyles.filter { FreeCraftParts.level(of: $0) <= level }
            let skipPommel = Bool.random(using: &rng)
            if let style = pommels.randomElement(using: &rng), !skipPommel {
                d.endClip = ClipSpec(style, span: Float.random(in: 0.9...1.4, using: &rng), depth: 0.7)
            } else {
                d.endClip = nil
            }
            d.handleLength = Float.random(in: kind == .sword ? Float(4.6)...6.4 : Float(3.8)...5, using: &rng)
            d.lanyardHole = d.endClip == nil && Bool.random(using: &rng)
        }
        d.wraps = wraps(count: Int.random(in: 0...(kind == .knife ? 2 : 3), using: &rng), for: d)
        d.name = autoName(d)
        return clamp(d, level: level)
    }
}
