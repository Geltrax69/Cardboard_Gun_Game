import Foundation

// MARK: - Weapon designs
//
// A weapon is described by a handful of parameters; `WeaponBlueprint` turns a design
// into cut-out pieces, fold targets and assembly poses. Every campaign weapon and
// every Free Craft creation goes through the same generator.

/// How the blade is made from cardboard.
public enum BladeBuild: String, Codable, CaseIterable {
    /// Symmetric outline with a centre crease, pinched into a ridge (daggers, swords).
    case ridge
    /// Outline plus a mirrored twin hinged at the tang, folded over and glued into a
    /// double-thickness blade — any silhouette, including curved single-edged blades.
    case laminate
}

public enum TipStyle: String, Codable, CaseIterable {
    // Ridge (symmetric) tips.
    case spear, drop, leaf, needle, flame
    // Laminate (single-edged) tips.
    case clip, tanto, curved, hook, cleaver

    public var forRidge: Bool { [.spear, .drop, .leaf, .needle, .flame].contains(self) }

    public var title: String {
        switch self {
        case .spear: return "Spear"
        case .drop: return "Drop point"
        case .leaf: return "Leaf"
        case .needle: return "Needle"
        case .flame: return "Flame"
        case .clip: return "Clip point"
        case .tanto: return "Tanto"
        case .curved: return "Curved"
        case .hook: return "Hook"
        case .cleaver: return "Cleaver"
        }
    }
}

public enum EdgeStyle: String, Codable, CaseIterable {
    case plain, serrated
}

public struct BladeSpec: Codable, Equatable {
    public var build: BladeBuild
    public var tip: TipStyle
    public var edge: EdgeStyle
    /// Shoulder → tip.
    public var length: Float
    /// Full width at the shoulder.
    public var width: Float
    /// Laminate only: 0 = straight, 1 = strongly curved.
    public var curve: Float
    public var tangLength: Float
    /// Decorative groove down the blade (carved in the sharpen step).
    public var fuller: Bool

    public init(build: BladeBuild, tip: TipStyle, edge: EdgeStyle = .plain, length: Float, width: Float,
                curve: Float = 0, tangLength: Float = 3.3, fuller: Bool = false) {
        self.build = build
        self.tip = tip
        self.edge = edge
        self.length = length
        self.width = width
        self.curve = curve
        self.tangLength = tangLength
        self.fuller = fuller
    }
}

/// Shapes of the clip wings — the part you see from above.
public enum WingStyle: String, Codable, CaseIterable {
    // Guards (front clip).
    case bar, flared, spiked, disc
    // Pommels (end clip).
    case diamond, knob, spike
    // Axe heads (end clip).
    case bit, doubleBit, bearded

    public var isGuard: Bool { [.bar, .flared, .spiked, .disc].contains(self) }
    public var isPommel: Bool { [.diamond, .knob, .spike].contains(self) }
    public var isAxeHead: Bool { [.bit, .doubleBit, .bearded].contains(self) }

    public var title: String {
        switch self {
        case .bar: return "Bar"
        case .flared: return "Flared"
        case .spiked: return "Spiked"
        case .disc: return "Disc"
        case .diamond: return "Diamond"
        case .knob: return "Knob"
        case .spike: return "Spike"
        case .bit: return "Single bit"
        case .doubleBit: return "Double bit"
        case .bearded: return "Bearded"
        }
    }
}

/// A U-shaped clip that slides over an end of the handle: a bridge across the end
/// (with a slot for the tang on guards) and two wings glued to the top and bottom.
public struct ClipSpec: Codable, Equatable {
    public var style: WingStyle
    /// Sideways reach from the handle centre.
    public var span: Float
    /// Length along the handle.
    public var depth: Float

    public init(_ style: WingStyle, span: Float, depth: Float) {
        self.style = style
        self.span = span
        self.depth = depth
    }
}

/// One stage of a weapon build.
public enum WeaponStage: String, CaseIterable {
    case cut, handle, blade, fittings, assemble, sharpen
}

public enum WeaponKind: String, Codable, CaseIterable {
    case knife, dagger, sword, axe

    public var title: String {
        switch self {
        case .knife: return "Knife"
        case .dagger: return "Dagger"
        case .sword: return "Sword"
        case .axe: return "Axe"
        }
    }
}

public struct WeaponDesign: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: WeaponKind
    /// nil for axes.
    public var blade: BladeSpec?
    /// Handle box, inner dimensions.
    public var handleLength: Float
    public var handleWidth: Float
    public var handleHeight: Float
    public var lanyardHole: Bool
    /// Crossguard sliding onto the front of the handle.
    public var guardClip: ClipSpec?
    /// Pommel or axe head on the far end of the handle.
    public var endClip: ClipSpec?
    /// Grip / guard bands, as distances from the front of the handle.
    public var wraps: [Float]

    public init(id: String, name: String, kind: WeaponKind, blade: BladeSpec?, handleLength: Float,
                handleWidth: Float = 1.3, handleHeight: Float = 1.0, lanyardHole: Bool = false,
                guardClip: ClipSpec? = nil, endClip: ClipSpec? = nil, wraps: [Float] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.blade = blade
        self.handleLength = handleLength
        self.handleWidth = handleWidth
        self.handleHeight = handleHeight
        self.lanyardHole = lanyardHole
        self.guardClip = guardClip
        self.endClip = endClip
        self.wraps = wraps
    }

    /// Build stages for this design (the HUD's STEP n / N).
    public var stages: [WeaponStage] {
        var s: [WeaponStage] = [.cut, .handle]
        if blade != nil { s.append(.blade) }
        if guardClip != nil || endClip != nil { s.append(.fittings) }
        s.append(.assemble)
        if blade != nil || endClip?.style.isAxeHead == true { s.append(.sharpen) }
        return s
    }

    public var stepCount: Int { stages.count }

    /// Number of separate pieces on the sheet.
    public var pieceCount: Int {
        1 + (blade != nil ? 1 : 0) + (guardClip != nil ? 1 : 0) + (endClip != nil ? 1 : 0) + wraps.count
    }

    /// Keeps Free Craft parameters inside ranges the generator handles.
    public func sanitized() -> WeaponDesign {
        var d = self
        d.handleLength = clampf(d.handleLength, kind == .axe ? 6 : 3.4, kind == .axe ? 10.5 : 6.5)
        d.handleWidth = clampf(d.handleWidth, 0.9, 1.5)
        d.handleHeight = clampf(d.handleHeight, 0.8, 1.2)
        if var b = d.blade {
            if b.build == .ridge && !b.tip.forRidge { b.tip = .spear }
            if b.build == .laminate && b.tip.forRidge { b.tip = .curved }
            b.tangLength = clampf(min(b.tangLength, d.handleLength - 0.8), 2.2, 4.5)
            // A laminated blade is cut with its twin end to end, so it must fit the sheet twice.
            let maxLen: Float = b.build == .laminate ? min(9.5, 11.8 - b.tangLength) : 12
            b.length = clampf(b.length, 3.5, maxLen)
            b.width = clampf(b.width, max(1.2, d.handleWidth * 0.9), 3.2)
            b.curve = b.build == .laminate ? clampf(b.curve, 0, 1) : 0
            d.blade = b
        }
        if var g = d.guardClip {
            g.span = clampf(g.span, d.handleWidth * 0.5 + 0.35, 3.0)
            g.depth = clampf(g.depth, 0.35, 1.0)
            d.guardClip = g
        }
        if var e = d.endClip {
            let axe = e.style.isAxeHead
            e.span = clampf(e.span, d.handleWidth * 0.5 + 0.3, axe ? 4.2 : 1.6)
            e.depth = clampf(e.depth, 0.4, axe ? min(3.6, d.handleLength * 0.45) : 1.0)
            d.endClip = e
        }
        let front = (d.guardClip?.depth ?? 0) + 0.15
        let back = d.handleLength - (d.endClip?.depth ?? 0) - 0.95
        d.wraps = d.wraps.map { clampf($0, front, max(front, back)) }
        return d
    }
}

// MARK: - Campaign weapons

public extension WeaponDesign {
    static let knife = WeaponDesign(
        id: "knife", name: "Knife", kind: .knife,
        blade: BladeSpec(build: .ridge, tip: .drop, length: 6.4, width: 2.0, tangLength: 3.3),
        handleLength: 4.4, lanyardHole: true, wraps: [0.12])

    static let dagger = WeaponDesign(
        id: "dagger", name: "Dagger", kind: .dagger,
        blade: BladeSpec(build: .ridge, tip: .spear, length: 6.8, width: 1.8, tangLength: 3.3),
        handleLength: 4.2, guardClip: ClipSpec(.bar, span: 1.9, depth: 0.5), endClip: ClipSpec(.diamond, span: 1.1, depth: 0.7))

    static let kunai = WeaponDesign(
        id: "kunai", name: "Kunai", kind: .dagger,
        blade: BladeSpec(build: .ridge, tip: .leaf, length: 5.2, width: 2.2, tangLength: 3.0),
        handleLength: 4.6, handleWidth: 1.1, handleHeight: 0.9, lanyardHole: true, wraps: [0.4, 1.6, 2.8])

    static let bowie = WeaponDesign(
        id: "bowie", name: "Bowie Knife", kind: .knife,
        blade: BladeSpec(build: .laminate, tip: .clip, length: 7.0, width: 2.2, curve: 0.1, tangLength: 3.3),
        handleLength: 4.6, guardClip: ClipSpec(.bar, span: 1.5, depth: 0.45), endClip: ClipSpec(.knob, span: 0.95, depth: 0.6))

    static let shortSword = WeaponDesign(
        id: "shortSword", name: "Short Sword", kind: .sword,
        blade: BladeSpec(build: .ridge, tip: .leaf, length: 9.0, width: 2.3, tangLength: 3.6, fuller: true),
        handleLength: 4.8, guardClip: ClipSpec(.flared, span: 2.4, depth: 0.6), endClip: ClipSpec(.diamond, span: 1.2, depth: 0.75))

    static let handAxe = WeaponDesign(
        id: "handAxe", name: "Hand Axe", kind: .axe, blade: nil,
        handleLength: 8.0, handleWidth: 1.0, handleHeight: 0.9,
        endClip: ClipSpec(.bit, span: 3.0, depth: 2.6), wraps: [1.0])

    static let flameDagger = WeaponDesign(
        id: "flameDagger", name: "Flame Dagger", kind: .dagger,
        blade: BladeSpec(build: .ridge, tip: .flame, edge: .plain, length: 7.6, width: 2.1, tangLength: 3.3),
        handleLength: 4.4, guardClip: ClipSpec(.spiked, span: 2.2, depth: 0.55), endClip: ClipSpec(.spike, span: 1.0, depth: 0.8),
        wraps: [1.6])

    static let scimitar = WeaponDesign(
        id: "scimitar", name: "Scimitar", kind: .sword,
        blade: BladeSpec(build: .laminate, tip: .curved, length: 9.0, width: 2.4, curve: 0.7, tangLength: 3.4),
        handleLength: 4.8, guardClip: ClipSpec(.flared, span: 1.9, depth: 0.5), endClip: ClipSpec(.knob, span: 1.0, depth: 0.6))

    static let longsword = WeaponDesign(
        id: "longsword", name: "Longsword", kind: .sword,
        blade: BladeSpec(build: .ridge, tip: .spear, edge: .plain, length: 11.5, width: 2.2, tangLength: 4.0, fuller: true),
        handleLength: 6.0, guardClip: ClipSpec(.bar, span: 3.0, depth: 0.6), endClip: ClipSpec(.diamond, span: 1.3, depth: 0.8),
        wraps: [1.6, 3.2])

    static let katana = WeaponDesign(
        id: "katana", name: "Katana", kind: .sword,
        blade: BladeSpec(build: .laminate, tip: .tanto, length: 8.6, width: 1.9, curve: 0.35, tangLength: 3.8),
        handleLength: 6.2, handleWidth: 1.2, handleHeight: 1.0,
        guardClip: ClipSpec(.disc, span: 1.5, depth: 0.6), wraps: [1.4, 2.6, 3.8, 5.0])

    static let battleAxe = WeaponDesign(
        id: "battleAxe", name: "Battle Axe", kind: .axe, blade: nil,
        handleLength: 10.0, handleWidth: 1.0, handleHeight: 0.95,
        endClip: ClipSpec(.doubleBit, span: 3.6, depth: 3.2), wraps: [0.8, 2.2])

    static let karambit = WeaponDesign(
        id: "karambit", name: "Karambit", kind: .knife,
        blade: BladeSpec(build: .laminate, tip: .hook, edge: .serrated, length: 5.4, width: 2.0, curve: 1.0, tangLength: 3.0),
        handleLength: 4.2, lanyardHole: true, endClip: ClipSpec(.knob, span: 0.9, depth: 0.55), wraps: [0.3])

    // MARK: More blades (levels 15+)

    static let huntingKnife = WeaponDesign(
        id: "huntingKnife", name: "Hunting Knife", kind: .knife,
        blade: BladeSpec(build: .laminate, tip: .clip, length: 6.2, width: 2.1, curve: 0.2, tangLength: 3.2),
        handleLength: 4.6, guardClip: ClipSpec(.bar, span: 1.3, depth: 0.4), wraps: [1.2, 2.6])

    static let stiletto = WeaponDesign(
        id: "stiletto", name: "Stiletto", kind: .dagger,
        blade: BladeSpec(build: .ridge, tip: .needle, length: 7.4, width: 1.3, tangLength: 3.2),
        handleLength: 4.4, handleWidth: 1.05, handleHeight: 0.9,
        guardClip: ClipSpec(.bar, span: 1.7, depth: 0.4), endClip: ClipSpec(.knob, span: 0.85, depth: 0.55))

    static let gladius = WeaponDesign(
        id: "gladius", name: "Gladius", kind: .sword,
        blade: BladeSpec(build: .ridge, tip: .leaf, length: 8.2, width: 2.6, tangLength: 3.6),
        handleLength: 4.6, guardClip: ClipSpec(.disc, span: 1.6, depth: 0.7), endClip: ClipSpec(.knob, span: 1.25, depth: 0.85),
        wraps: [1.4, 2.4])

    static let tomahawk = WeaponDesign(
        id: "tomahawk", name: "Tomahawk", kind: .axe, blade: nil,
        handleLength: 8.6, handleWidth: 0.95, handleHeight: 0.85,
        endClip: ClipSpec(.bit, span: 2.5, depth: 2.0), wraps: [0.6, 1.6, 2.6])

    static let tantoKnife = WeaponDesign(
        id: "tantoKnife", name: "Tanto", kind: .knife,
        blade: BladeSpec(build: .laminate, tip: .tanto, length: 6.4, width: 1.9, tangLength: 3.2),
        handleLength: 4.8, handleWidth: 1.15, guardClip: ClipSpec(.disc, span: 1.15, depth: 0.45), wraps: [1.0, 2.0, 3.0])

    static let dirk = WeaponDesign(
        id: "dirk", name: "Dirk", kind: .dagger,
        blade: BladeSpec(build: .ridge, tip: .drop, length: 8.4, width: 1.8, tangLength: 3.4, fuller: true),
        handleLength: 4.8, guardClip: ClipSpec(.flared, span: 1.6, depth: 0.45), endClip: ClipSpec(.diamond, span: 1.1, depth: 0.7),
        wraps: [1.5, 2.5])

    static let cutlass = WeaponDesign(
        id: "cutlass", name: "Cutlass", kind: .sword,
        blade: BladeSpec(build: .laminate, tip: .curved, length: 8.2, width: 2.4, curve: 0.45, tangLength: 3.4),
        handleLength: 4.6, guardClip: ClipSpec(.disc, span: 1.8, depth: 0.8), endClip: ClipSpec(.knob, span: 0.95, depth: 0.55))

    static let machete = WeaponDesign(
        id: "machete", name: "Machete", kind: .knife,
        blade: BladeSpec(build: .laminate, tip: .curved, length: 8.4, width: 2.6, curve: 0.15, tangLength: 3.4),
        handleLength: 5.0, lanyardHole: true, endClip: ClipSpec(.knob, span: 0.9, depth: 0.5), wraps: [0.4, 1.4, 2.4])

    static let mainGauche = WeaponDesign(
        id: "mainGauche", name: "Main Gauche", kind: .dagger,
        blade: BladeSpec(build: .ridge, tip: .spear, length: 7.4, width: 1.7, tangLength: 3.3),
        handleLength: 4.4, guardClip: ClipSpec(.spiked, span: 2.8, depth: 0.5), endClip: ClipSpec(.knob, span: 1.0, depth: 0.6))

    static let rapier = WeaponDesign(
        id: "rapier", name: "Rapier", kind: .sword,
        blade: BladeSpec(build: .ridge, tip: .needle, length: 12.0, width: 1.4, tangLength: 3.8),
        handleLength: 5.0, handleWidth: 1.1, handleHeight: 0.9,
        guardClip: ClipSpec(.disc, span: 1.9, depth: 0.8), endClip: ClipSpec(.knob, span: 1.1, depth: 0.7), wraps: [1.6, 2.6])

    static let hatchet = WeaponDesign(
        id: "hatchet", name: "Hatchet", kind: .axe, blade: nil,
        handleLength: 6.6, handleWidth: 1.0, handleHeight: 0.9,
        endClip: ClipSpec(.bit, span: 2.4, depth: 2.4), wraps: [0.5])

    static let cleaver = WeaponDesign(
        id: "cleaver", name: "Cleaver", kind: .knife,
        blade: BladeSpec(build: .laminate, tip: .cleaver, length: 6.4, width: 3.1, tangLength: 3.2),
        handleLength: 4.6, lanyardHole: true, wraps: [0.3, 1.5])

    static let broadsword = WeaponDesign(
        id: "broadsword", name: "Broadsword", kind: .sword,
        blade: BladeSpec(build: .ridge, tip: .spear, length: 10.6, width: 2.9, tangLength: 3.8, fuller: true),
        handleLength: 5.4, guardClip: ClipSpec(.flared, span: 2.9, depth: 0.6), endClip: ClipSpec(.diamond, span: 1.3, depth: 0.8),
        wraps: [1.6, 2.8])

    static let kukri = WeaponDesign(
        id: "kukri", name: "Kukri", kind: .knife,
        blade: BladeSpec(build: .laminate, tip: .curved, length: 7.2, width: 2.8, curve: 1.0, tangLength: 3.2),
        handleLength: 4.8, guardClip: ClipSpec(.bar, span: 1.2, depth: 0.35), endClip: ClipSpec(.knob, span: 1.0, depth: 0.6),
        wraps: [1.3, 2.3])

    static let wakizashi = WeaponDesign(
        id: "wakizashi", name: "Wakizashi", kind: .sword,
        blade: BladeSpec(build: .laminate, tip: .tanto, length: 7.4, width: 1.8, curve: 0.3, tangLength: 3.4),
        handleLength: 5.0, handleWidth: 1.15, guardClip: ClipSpec(.disc, span: 1.4, depth: 0.55), wraps: [1.3, 2.3, 3.3])

    static let falchion = WeaponDesign(
        id: "falchion", name: "Falchion", kind: .sword,
        blade: BladeSpec(build: .laminate, tip: .cleaver, length: 8.4, width: 2.7, curve: 0.25, tangLength: 3.4),
        handleLength: 4.8, guardClip: ClipSpec(.bar, span: 2.2, depth: 0.5), endClip: ClipSpec(.diamond, span: 1.1, depth: 0.7))

    static let survivalKnife = WeaponDesign(
        id: "survivalKnife", name: "Survival Knife", kind: .knife,
        blade: BladeSpec(build: .laminate, tip: .clip, edge: .serrated, length: 6.8, width: 2.2, curve: 0.1, tangLength: 3.3),
        handleLength: 4.8, guardClip: ClipSpec(.spiked, span: 1.7, depth: 0.45), endClip: ClipSpec(.spike, span: 0.9, depth: 0.7),
        wraps: [1.2, 2.2])

    static let claymore = WeaponDesign(
        id: "claymore", name: "Claymore", kind: .sword,
        blade: BladeSpec(build: .ridge, tip: .spear, length: 12.0, width: 2.5, tangLength: 4.2, fuller: true),
        handleLength: 6.5, guardClip: ClipSpec(.spiked, span: 3.0, depth: 0.7), endClip: ClipSpec(.diamond, span: 1.4, depth: 0.9),
        wraps: [1.6, 2.8, 4.0])

    static let beardedAxe = WeaponDesign(
        id: "beardedAxe", name: "Bearded Axe", kind: .axe, blade: nil,
        handleLength: 9.6, handleWidth: 1.0, handleHeight: 0.95,
        endClip: ClipSpec(.bearded, span: 3.6, depth: 3.2), wraps: [0.8, 2.0, 3.2])

    static let flamberge = WeaponDesign(
        id: "flamberge", name: "Flamberge", kind: .sword,
        blade: BladeSpec(build: .ridge, tip: .flame, length: 11.6, width: 2.4, tangLength: 4.0),
        handleLength: 6.2, guardClip: ClipSpec(.spiked, span: 3.0, depth: 0.6), endClip: ClipSpec(.spike, span: 1.2, depth: 0.85),
        wraps: [1.6, 2.8, 4.0])

    /// Campaign order of the blades and axes (guns sit in between, see `Campaign.order`).
    static let campaign: [WeaponDesign] = [
        .knife, .dagger, .kunai, .bowie, .shortSword, .handAxe, .flameDagger, .karambit, .scimitar, .longsword, .katana, .battleAxe,
        .huntingKnife, .stiletto, .gladius, .tomahawk, .tantoKnife, .dirk, .cutlass, .machete, .mainGauche, .rapier, .hatchet,
        .cleaver, .broadsword, .kukri, .wakizashi, .falchion, .survivalKnife, .claymore, .beardedAxe, .flamberge,
    ]

    static func byID(_ id: String) -> WeaponDesign? { campaign.first { $0.id == id } }
}
