import Combine
import Foundation

/// The weapon being designed in Free Craft. Every edit goes through `update`, which
/// keeps the design buildable with the parts unlocked at the player's level, renames it
/// after its parts and tells the engine to refresh the 3D preview.
@MainActor
final class FreeCraftModel: ObservableObject {
    struct Stats: Equatable {
        var pieces = 0
        var steps = 0
        var sheet = V2(0, 0)
    }

    @Published private(set) var design: WeaponDesign
    @Published private(set) var stats = Stats()
    private(set) var level = 1
    /// Called after every change (the engine rebuilds the preview).
    var onChange: ((WeaponDesign) -> Void)?

    init(saved: WeaponDesign?) {
        design = saved ?? FreeCraftParts.starter(.knife)
        refreshStats()
    }

    /// Restores the last saved design.
    func load(_ saved: WeaponDesign?) {
        guard let saved else { return }
        design = saved
        refreshStats()
    }

    /// Opens the designer for a player at `level`.
    func begin(level: Int) {
        self.level = level
        update { _ in }
    }

    func update(_ change: (inout WeaponDesign) -> Void) {
        var d = design
        change(&d)
        d.wraps = FreeCraftParts.wraps(count: min(d.wraps.count, FreeCraftParts.maxWraps), for: d.sanitized())
        d = FreeCraftParts.clamp(d, level: level)
        d.name = FreeCraftParts.autoName(d)
        design = d
        refreshStats()
        onChange?(d)
    }

    private func refreshStats() {
        let bp = WeaponBlueprint(design: design, thickness: CardboardStock.plain.thickness)
        stats = Stats(pieces: design.pieceCount, steps: design.stepCount, sheet: bp.template.sheetSize)
    }

    // MARK: Edits

    func setKind(_ kind: WeaponKind) {
        guard kind != design.kind else { return }
        update { d in
            let wasAxe = d.kind == .axe
            d.kind = kind
            if kind == .axe {
                d = FreeCraftParts.starter(.axe)
            } else if wasAxe || d.blade == nil {
                let starter = FreeCraftParts.starter(kind)
                d.blade = starter.blade
                d.handleLength = starter.handleLength
                d.guardClip = starter.guardClip
                d.endClip = starter.endClip
            } else if var b = d.blade {
                // Keep the shape, adopt the kind's typical size.
                b.length = FreeCraftParts.defaultBlade(for: kind, build: b.build).length
                b.tangLength = FreeCraftParts.defaultBlade(for: kind, build: b.build).tangLength
                d.blade = b
                d.handleLength = FreeCraftParts.starter(kind).handleLength
            }
        }
    }

    func setBuild(_ build: BladeBuild) {
        update { d in
            guard var b = d.blade, b.build != build else { return }
            let fresh = FreeCraftParts.defaultBlade(for: d.kind, build: build)
            b.build = build
            b.tip = fresh.tip
            b.curve = fresh.curve
            b.fuller = false
            d.blade = b
        }
    }

    func setTip(_ tip: TipStyle) { update { $0.blade?.tip = tip } }
    func setEdge(_ edge: EdgeStyle) { update { $0.blade?.edge = edge } }
    func toggleFuller() { update { d in d.blade?.fuller.toggle() } }
    func setLength(_ v: Float) { update { $0.blade?.length = v } }
    func setWidth(_ v: Float) { update { $0.blade?.width = v } }
    func setCurve(_ v: Float) { update { $0.blade?.curve = v } }

    func setGuard(_ style: WingStyle?) {
        update { d in
            guard let style else { d.guardClip = nil; return }
            d.guardClip = ClipSpec(style, span: d.guardClip?.span ?? 2.0, depth: style == .disc ? 0.6 : 0.55)
        }
    }

    func setGuardSpan(_ v: Float) { update { $0.guardClip?.span = v } }

    /// Pommel (bladed weapons) or axe head.
    func setEnd(_ style: WingStyle?) {
        update { d in
            guard let style else { d.endClip = nil; return }
            if style.isAxeHead {
                let size = d.endClip.map { $0.depth / 3.6 } ?? 0.75
                d.endClip = ClipSpec(style, span: 4.2 * size, depth: 3.6 * size)
            } else {
                d.endClip = ClipSpec(style, span: d.endClip?.span ?? 1.1, depth: 0.7)
                d.lanyardHole = false
            }
        }
    }

    /// Pommel span, or axe head scale (0.5…1).
    var endSize: Float {
        guard let e = design.endClip else { return 1 }
        return e.style.isAxeHead ? e.depth / 3.6 : e.span
    }

    func setEndSize(_ v: Float) {
        update { d in
            guard var e = d.endClip else { return }
            if e.style.isAxeHead {
                e.span = 4.2 * v
                e.depth = 3.6 * v
            } else {
                e.span = v
            }
            d.endClip = e
        }
    }

    func setHandleLength(_ v: Float) { update { $0.handleLength = v } }
    func setWraps(_ n: Int) { update { $0.wraps = Array(repeating: 0, count: n) } }
    func toggleLanyard() { update { d in d.lanyardHole.toggle() } }

    func randomize() {
        var rng = SystemRandomNumberGenerator()
        let fresh = FreeCraftParts.random(level: level, using: &rng)
        update { $0 = fresh }
    }
}
