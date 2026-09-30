import Foundation

// MARK: - Template model
//
// A craft template is a flat cardboard sheet containing one or more pieces. Each piece
// is a tree of panels joined by hinges (blue dashed fold lines). The red cut line of a
// piece is computed automatically as the union outline of its panels, so authoring a
// new template only needs panel polygons + hinges. See README "Authoring templates".
//
// Coordinates: template space (u, v) = world (x, z) on the mat; +v points toward the
// player (down on screen). Units are roughly centimetres / 2.

public enum FoldKind: String {
    /// Flap rotates up, toward the printed (top) face.
    case valley
    /// Flap rotates down, away from the printed face.
    case mountain
}

public struct HingeDef {
    public var a: V2
    public var b: V2
    public var kind: FoldKind
    /// Magnitude of the finished fold, in radians.
    public var target: Float

    public init(_ a: V2, _ b: V2, _ kind: FoldKind = .valley, degrees: Float = 90) {
        self.a = a
        self.b = b
        self.kind = kind
        self.target = radians(degrees)
    }

    public var signedTarget: Float { kind == .valley ? target : -target }
    public var length: Float { a.dist(b) }
    public var midpoint: V2 { (a + b) / 2 }
}

public enum PanelRole: String {
    case body
    case glueTab
}

public struct PanelDef {
    public var id: String
    public var outline: [V2]
    public var holes: [[V2]]
    public var parent: String?
    public var hinge: HingeDef?
    public var role: PanelRole

    public init(_ id: String, _ outline: [V2], holes: [[V2]] = [], parent: String? = nil,
                hinge: HingeDef? = nil, role: PanelRole = .body) {
        self.id = id
        // Normalise winding: positive signed area.
        self.outline = Poly.signedArea(outline) < 0 ? outline.reversed() : outline
        self.holes = holes.map { Poly.signedArea($0) > 0 ? $0.reversed() : $0 }
        self.parent = parent
        self.hinge = hinge
        self.role = role
    }

    public var centroid: V2 { Poly.centroid(outline) }
}

public struct PieceDef {
    public var id: String
    public var name: String
    /// Sheet position of the piece's local origin.
    public var placement: V2
    public var panels: [PanelDef]
    /// Union outline in piece space; this is the red cut line.
    public private(set) var outline: [V2] = []
    /// Punched holes (inner cuts) in piece space.
    public private(set) var innerCuts: [[V2]] = []

    public init(id: String, name: String, placement: V2, panels: [PanelDef]) {
        self.id = id
        self.name = name
        self.placement = placement
        self.panels = panels
        self.outline = PieceDef.unionOutline(panels)
        self.innerCuts = panels.flatMap { $0.holes }
    }

    public func panelIndex(_ id: String) -> Int? { panels.firstIndex { $0.id == id } }
    public func panel(_ id: String) -> PanelDef? { panels.first { $0.id == id } }
    public var rootIndex: Int { panels.firstIndex { $0.parent == nil } ?? 0 }

    public func children(of id: String) -> [PanelDef] { panels.filter { $0.parent == id } }

    /// Parents before children.
    public var topologicalOrder: [Int] {
        var order: [Int] = []
        var visited = Set<String>()
        func visit(_ i: Int) {
            let p = panels[i]
            if visited.contains(p.id) { return }
            if let parent = p.parent, let pi = panelIndex(parent) { visit(pi) }
            visited.insert(p.id)
            order.append(i)
        }
        for i in panels.indices { visit(i) }
        return order
    }

    /// All hinges touching a panel (its own + its children's).
    public func hinges(touching id: String) -> [HingeDef] {
        var hs: [HingeDef] = []
        if let h = panel(id)?.hinge { hs.append(h) }
        for c in children(of: id) { if let h = c.hinge { hs.append(h) } }
        return hs
    }

    /// Edges of a panel's outer ring that are not hinges (these get ink outlines).
    public func freeEdges(of id: String) -> [(V2, V2)] {
        guard let p = panel(id) else { return [] }
        let hs = hinges(touching: id)
        var out: [(V2, V2)] = []
        let ring = p.outline
        for i in 0..<ring.count {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            let onHinge = hs.contains { h in
                Poly.pointLineDistance(a, h.a, h.b) < 1e-3 && Poly.pointLineDistance(b, h.a, h.b) < 1e-3 &&
                    overlapLength(a, b, h.a, h.b) > 0.5 * min(a.dist(b), h.length)
            }
            if !onHinge { out.append((a, b)) }
        }
        for hole in p.holes {
            for i in 0..<hole.count { out.append((hole[i], hole[(i + 1) % hole.count])) }
        }
        return out
    }

    /// Bounding box of the flat piece on the sheet.
    public var sheetBounds: (min: V2, max: V2) {
        let b = Poly.bounds(outline)
        return (b.min + placement, b.max + placement)
    }

    // MARK: Union outline

    static func key(_ p: V2) -> String {
        String(format: "%.3f,%.3f", Double((p.x * 1000).rounded() / 1000), Double((p.y * 1000).rounded() / 1000))
    }

    static func unionOutline(_ panels: [PanelDef]) -> [V2] {
        // 1. Directed edges of every panel (all rings share the same winding).
        var edges: [(V2, V2)] = []
        var allPoints: [V2] = []
        for p in panels {
            let r = p.outline
            allPoints.append(contentsOf: r)
            for i in 0..<r.count { edges.append((r[i], r[(i + 1) % r.count])) }
        }
        // 2. Split edges at vertices lying on them (T-junctions between panels).
        var split: [(V2, V2)] = []
        for (a, b) in edges {
            let ab = b - a
            let l = ab.len
            guard l > 1e-6 else { continue }
            var ts: [Float] = []
            for q in allPoints {
                let t = (q - a).dotp(ab) / (l * l)
                if t > 1e-4, t < 1 - 1e-4, Poly.pointLineDistance(q, a, b) < 1e-4 { ts.append(t) }
            }
            ts.sort()
            var prev = a
            for t in ts {
                let m = a + ab * t
                if m.dist(prev) > 1e-5 { split.append((prev, m)) }
                prev = m
            }
            if b.dist(prev) > 1e-5 { split.append((prev, b)) }
        }
        // 3. Drop edges shared by two panels (they appear in opposite directions).
        var counts: [String: Int] = [:]
        for (a, b) in split { counts[key(a) + ">" + key(b), default: 0] += 1 }
        let boundary = split.filter { (a, b) in counts[key(b) + ">" + key(a)] == nil }
        // 4. Chain into loops.
        var next: [String: [(V2, V2)]] = [:]
        for e in boundary { next[key(e.0), default: []].append(e) }
        var used = Set<String>()
        var loops: [[V2]] = []
        for e in boundary {
            let ek = key(e.0) + ">" + key(e.1)
            if used.contains(ek) { continue }
            var loop: [V2] = []
            var cur = e
            var guardCount = 0
            while guardCount < 10_000 {
                guardCount += 1
                let ck = key(cur.0) + ">" + key(cur.1)
                if used.contains(ck) { break }
                used.insert(ck)
                loop.append(cur.0)
                guard let cands = next[key(cur.1)], let nxt = cands.first(where: { !used.contains(key($0.0) + ">" + key($0.1)) }) else { break }
                cur = nxt
            }
            if loop.count >= 3 { loops.append(loop) }
        }
        guard var outline = loops.max(by: { abs(Poly.signedArea($0)) < abs(Poly.signedArea($1)) }) else { return [] }
        // 5. Remove collinear points.
        var changed = true
        while changed && outline.count > 3 {
            changed = false
            for i in 0..<outline.count {
                let a = outline[(i - 1 + outline.count) % outline.count], b = outline[i], c = outline[(i + 1) % outline.count]
                if abs((b - a).unit.crossp((c - b).unit)) < 1e-4 && (b - a).dotp(c - b) > 0 {
                    outline.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        // Start at the top-left corner so the knife begins where players expect.
        if let start = outline.indices.min(by: { (outline[$0].y + outline[$0].x * 0.01) < (outline[$1].y + outline[$1].x * 0.01) }) {
            outline = Array(outline[start...] + outline[..<start])
        }
        return outline
    }
}

@inline(__always)
func overlapLength(_ a: V2, _ b: V2, _ c: V2, _ d: V2) -> Float {
    let dir = (b - a).unit
    let t0 = 0 as Float, t1 = (b - a).dotp(dir)
    let s0 = (c - a).dotp(dir), s1 = (d - a).dotp(dir)
    let lo = max(t0, min(s0, s1)), hi = min(t1, max(s0, s1))
    return max(0, hi - lo)
}

public struct CraftTemplate {
    public var sheetSize: V2
    public var thickness: Float
    public var pieces: [PieceDef]

    public init(sheetSize: V2, thickness: Float, pieces: [PieceDef]) {
        self.sheetSize = sheetSize
        self.thickness = thickness
        self.pieces = pieces
    }

    public func piece(_ id: String) -> PieceDef? { pieces.first { $0.id == id } }

    /// Sheet rectangle in template space, centred on the origin.
    public var sheetOutline: [V2] {
        let h = sheetSize / 2
        return Poly.rect(-h.x, -h.y, h.x, h.y)
    }
}
