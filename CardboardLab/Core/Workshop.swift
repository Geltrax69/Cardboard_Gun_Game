import Foundation

// MARK: - Free mode workshop
//
// An open workbench with unlimited cardboard: draw any shape on a sheet and cut it out,
// draw crease lines across pieces and fold them to any angle, paint faces any colour,
// and move, turn, stack and glue pieces into 3D builds. Everything here is plain data
// plus the geometry that edits it, so it can be saved, undone and tested.

/// An RGB colour (0…1) painted on a face.
public struct PaintColor: Codable, Equatable, Hashable {
    public var r: Float
    public var g: Float
    public var b: Float

    public init(r: Float, g: Float, b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// From hue (0…1, wrapping), saturation and brightness (0…1).
    public init(hue: Float, saturation s: Float, brightness v: Float) {
        let h = (hue - floor(hue)) * 6
        let i = Int(h) % 6
        let f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: self.init(r: v, g: t, b: p)
        case 1: self.init(r: q, g: v, b: p)
        case 2: self.init(r: p, g: v, b: t)
        case 3: self.init(r: p, g: q, b: v)
        case 4: self.init(r: t, g: p, b: v)
        default: self.init(r: v, g: p, b: q)
        }
    }

    public init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(s, radix: 16) ?? 0
        self.init(r: Float((v >> 16) & 0xFF) / 255, g: Float((v >> 8) & 0xFF) / 255, b: Float(v & 0xFF) / 255)
    }

    /// Hue, saturation, brightness (0…1).
    public var hsb: (h: Float, s: Float, b: Float) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h: Float = 0
        if d > 1e-6 {
            if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
        }
        return (h, mx > 0 ? d / mx : 0, mx)
    }
}

/// A rigid transform that can be saved.
public struct StoredPose: Codable, Equatable {
    public var p: [Float]
    public var q: [Float]

    public init(_ pose: Pose) {
        p = [pose.pos.x, pose.pos.y, pose.pos.z]
        q = [pose.rot.x, pose.rot.y, pose.rot.z, pose.rot.w]
    }

    public var pose: Pose {
        guard p.count == 3, q.count == 4 else { return .identity }
        return Pose(rot: Quat(x: q[0], y: q[1], z: q[2], w: q[3]).normalized, pos: V3(p[0], p[1], p[2]))
    }
}

/// One flat panel of a free piece. Panels are joined by creases into a tree.
public struct FreePanel: Codable, Equatable {
    public var id: String
    /// Outline in the piece's flat frame (counter-clockwise).
    public var outline: [V2]
    public var parent: String?
    /// Crease to the parent panel.
    public var hingeA: V2?
    public var hingeB: V2?
    /// Fold angle relative to the parent (radians, + folds toward the top face).
    public var angle: Float = 0
    public var top: PaintColor?
    public var under: PaintColor?

    public init(id: String, outline: [V2], parent: String? = nil, hingeA: V2? = nil, hingeB: V2? = nil,
                angle: Float = 0, top: PaintColor? = nil, under: PaintColor? = nil) {
        self.id = id
        self.outline = Poly.signedArea(outline) < 0 ? outline.reversed() : outline
        self.parent = parent
        self.hingeA = hingeA
        self.hingeB = hingeB
        self.angle = angle
        self.top = top
        self.under = under
    }
}

/// A piece cut out in the workshop.
public struct FreePiece: Codable, Equatable {
    public var id: String
    public var panels: [FreePanel]
    /// World pose of the flat frame, or relative to `gluedTo`'s frame when glued.
    public var pose: StoredPose
    public var gluedTo: String?
    public var nextPanel = 1

    public init(id: String, panels: [FreePanel], pose: Pose, gluedTo: String? = nil) {
        self.id = id
        self.panels = panels
        self.pose = StoredPose(pose)
        self.gluedTo = gluedTo
    }

    public func panel(_ id: String) -> FreePanel? { panels.first { $0.id == id } }
    public func panelIndex(_ id: String) -> Int? { panels.firstIndex { $0.id == id } }

    /// Template form, for folding and meshing with the same code as the campaign.
    public var pieceDef: PieceDef {
        let defs = panels.map { p -> PanelDef in
            var hinge: HingeDef? = nil
            if let a = p.hingeA, let b = p.hingeB { hinge = HingeDef(a, b, .valley, degrees: 90) }
            return PanelDef(p.id, p.outline, parent: p.parent, hinge: hinge)
        }
        return PieceDef(id: id, name: "Piece", placement: V2(0, 0), panels: defs)
    }

    public var angles: [String: Float] {
        var a: [String: Float] = [:]
        for p in panels where p.parent != nil { a[p.id] = p.angle }
        return a
    }
}

/// A sheet of cardboard on the table. Cut shapes leave holes in it.
public struct FreeSheet: Codable, Equatable {
    public var id: String
    public var size: V2
    /// Centre of the sheet on the table.
    public var center: V3
    /// Holes left by cut pieces, in sheet coordinates (centred on the sheet).
    public var holes: [[V2]] = []
    public var top: PaintColor?
    public var under: PaintColor?

    public init(id: String, size: V2, center: V3) {
        self.id = id
        self.size = size
        self.center = center
    }

    public var outline: [V2] {
        let h = size / 2
        return Poly.rect(-h.x, -h.y, h.x, h.y)
    }
}

public struct WorkshopState: Codable, Equatable {
    public var sheets: [FreeSheet] = []
    public var pieces: [FreePiece] = []
    public var activeSheet: String?
    public var counter = 0

    public init() {}

    public mutating func makeID(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)\(counter)"
    }

    public func sheet(_ id: String) -> FreeSheet? { sheets.first { $0.id == id } }
    public func piece(_ id: String) -> FreePiece? { pieces.first { $0.id == id } }
    public func pieceIndex(_ id: String) -> Int? { pieces.firstIndex { $0.id == id } }
    public func sheetIndex(_ id: String) -> Int? { sheets.firstIndex { $0.id == id } }

    /// World pose of a piece's flat frame (following glue links).
    public func worldPose(_ id: String) -> Pose {
        var pose = Pose.identity
        var current: String? = id
        var guardCount = 0
        while let cid = current, let p = piece(cid), guardCount < 64 {
            pose = p.pose.pose * pose
            current = p.gluedTo
            guardCount += 1
        }
        return pose
    }

    /// The piece at the top of a glue chain (moving it moves the whole group).
    public func groupRoot(_ id: String) -> String {
        var current = id
        var guardCount = 0
        while let p = piece(current), let up = p.gluedTo, guardCount < 64 {
            current = up
            guardCount += 1
        }
        return current
    }
}

// MARK: - Editing

public enum Workshop {
    public static let sheetSize = V2(14, 10)
    /// Free space kept between holes and around the sheet edge.
    public static let margin: Float = 0.15
    public static let minArea: Float = 0.35

    public enum CutProblem: Equatable {
        case tooSmall, crossesItself, offSheet, overlapsHole
    }

    /// Turns a hand-drawn loop into a clean low-poly shape (closed, counter-clockwise).
    public static func cleanStroke(_ raw: [V2], tolerance: Float = 0.12) -> [V2] {
        var pts: [V2] = []
        for p in raw where pts.last.map({ $0.dist(p) > 0.04 }) ?? true { pts.append(p) }
        guard pts.count >= 3 else { return pts }
        var simple = Poly.simplifyClosed(pts, tolerance: tolerance)
        if simple.count >= 3, let f = simple.first, let l = simple.last, f.dist(l) < 0.05 { simple.removeLast() }
        return Poly.signedArea(simple) < 0 ? simple.reversed() : simple
    }

    /// Checks a shape (sheet coordinates) can be cut from the sheet.
    public static func checkCut(_ shape: [V2], in sheet: FreeSheet) -> CutProblem? {
        guard shape.count >= 3, abs(Poly.signedArea(shape)) >= minArea else { return .tooSmall }
        guard Poly.isSimple(shape) else { return .crossesItself }
        let h = sheet.size / 2 - V2(margin, margin)
        guard shape.allSatisfy({ abs($0.x) <= h.x && abs($0.y) <= h.y }) else { return .offSheet }
        for hole in sheet.holes where Poly.overlaps(shape, hole, gap: margin) { return .overlapsHole }
        return nil
    }

    /// Cuts `shape` (sheet coordinates) out of a sheet: the sheet gets a hole and a new
    /// piece lies exactly where it was cut, coloured like the sheet.
    public static func cut(_ shape: [V2], from sheetID: String, in state: inout WorkshopState) -> String? {
        guard let si = state.sheetIndex(sheetID), checkCut(shape, in: state.sheets[si]) == nil else { return nil }
        let sheet = state.sheets[si]
        let ccw = Poly.signedArea(shape) < 0 ? shape.reversed() : shape
        let c = Poly.centroid(ccw)
        let id = state.makeID("piece")
        let panel = FreePanel(id: "P0", outline: ccw.map { $0 - c }, top: sheet.top, under: sheet.under)
        let pose = Pose.translation(sheet.center + c.onMat(0))
        state.pieces.append(FreePiece(id: id, panels: [panel], pose: pose))
        state.sheets[si].holes.append(ccw)
        return id
    }

    public enum CreaseProblem: Error, Equatable {
        case missesPanel, crossesCrease, tooThin
    }

    /// Adds a crease along the line through `a` and `b` (flat piece frame) across one
    /// panel. The side holding the panel's own crease stays; for the base panel the side
    /// holding more folds (or else the bigger side) stays. Returns the new flap's id.
    public static func addCrease(_ piece: inout FreePiece, panel panelID: String, _ a: V2, _ b: V2) -> Result<String, CreaseProblem> {
        guard let pi = piece.panelIndex(panelID) else { return .failure(.missesPanel) }
        let panel = piece.panels[pi]
        guard let split = Poly.splitByLine(panel.outline, a, b) else { return .failure(.missesPanel) }
        let (left, right, p, q) = split
        guard abs(Poly.signedArea(left)) > 0.08, abs(Poly.signedArea(right)) > 0.08, p.dist(q) > 0.2 else {
            return .failure(.tooThin)
        }
        func holds(_ poly: [V2], _ ha: V2, _ hb: V2) -> Bool {
            Poly.onBoundary(poly, ha) && Poly.onBoundary(poly, hb) && Poly.onBoundary(poly, (ha + hb) / 2)
        }
        // Which side keeps the panel's identity.
        var keepLeft: Bool
        if let ha = panel.hingeA, let hb = panel.hingeB {
            let l = holds(left, ha, hb), r = holds(right, ha, hb)
            guard l != r else { return .failure(.crossesCrease) }
            keepLeft = l
        } else {
            // The base keeps the side holding more folds (the hub), then the bigger side.
            let kids = piece.panels.filter { $0.parent == panelID }.compactMap { c -> (V2, V2)? in
                guard let ha = c.hingeA, let hb = c.hingeB else { return nil }
                return (ha, hb)
            }
            let l = kids.filter { holds(left, $0.0, $0.1) }.count, r = kids.filter { holds(right, $0.0, $0.1) }.count
            keepLeft = l != r ? l > r : abs(Poly.signedArea(left)) >= abs(Poly.signedArea(right))
        }
        let kept = keepLeft ? left : right, flap = keepLeft ? right : left
        // Child creases must land wholly on one side.
        var moves: [(Int, Bool)] = []
        for (ci, child) in piece.panels.enumerated() where child.parent == panelID {
            guard let ha = child.hingeA, let hb = child.hingeB else { continue }
            let inKept = holds(kept, ha, hb), inFlap = holds(flap, ha, hb)
            guard inKept != inFlap else { return .failure(.crossesCrease) }
            moves.append((ci, inFlap))
        }
        let newID = "P\(piece.nextPanel)"
        piece.nextPanel += 1
        piece.panels[pi].outline = kept
        for (ci, toFlap) in moves where toFlap { piece.panels[ci].parent = newID }
        piece.panels.append(FreePanel(id: newID, outline: flap, parent: panelID, hingeA: p, hingeB: q,
                                      top: panel.top, under: panel.under))
        return .success(newID)
    }

    /// Snaps a fold angle to the nearest 15° when close (within 5°), and keeps it in ±180°.
    public static func snapAngle(_ a: Float) -> Float {
        let c = clampf(a, -.pi, .pi)
        let step = radians(15)
        let s = (c / step).rounded() * step
        return abs(s - c) < radians(5) ? s : c
    }

    /// First free spot for a new sheet, spiralling out from the mat's centre so earlier
    /// sheets and pieces stay where they are.
    public static func freeSheetSpot(_ state: WorkshopState, size: V2 = sheetSize, pieceBounds: [(V2, V2)]) -> V3 {
        var boxes: [(V2, V2)] = pieceBounds
        for s in state.sheets {
            let h = s.size / 2
            boxes.append((s.center.xz - h, s.center.xz + h))
        }
        let step = size + V2(1.5, 1.5)
        var candidates: [V2] = [V2(0, 0)]
        for ring in 1...6 {
            for i in -ring...ring {
                for j in -ring...ring where max(abs(i), abs(j)) == ring {
                    candidates.append(V2(Float(i) * step.x, Float(j) * step.y))
                }
            }
        }
        candidates.sort { $0.len < $1.len }
        let h = size / 2 + V2(0.4, 0.4)
        for c in candidates {
            let lo = c - h, hi = c + h
            if !boxes.contains(where: { lo.x < $0.1.x && hi.x > $0.0.x && lo.y < $0.1.y && hi.y > $0.0.y }) {
                return c.onMat(0)
            }
        }
        return V3(Float(state.sheets.count) * step.x, 0, 0)
    }
}

// MARK: - Polygon helpers used by the workshop

public extension Poly {
    /// Douglas–Peucker simplification of a closed loop.
    static func simplifyClosed(_ pts: [V2], tolerance: Float) -> [V2] {
        guard pts.count > 3 else { return pts }
        // Split the loop at the point farthest from the start and simplify both halves.
        let far = pts.indices.max { pts[$0].dist(pts[0]) < pts[$1].dist(pts[0]) } ?? pts.count / 2
        let a = simplifyOpen(Array(pts[0...far]), tolerance)
        let b = simplifyOpen(Array(pts[far...]) + [pts[0]], tolerance)
        return Array(a.dropLast()) + Array(b.dropLast())
    }

    static func simplifyOpen(_ pts: [V2], _ tol: Float) -> [V2] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        var stack = [(0, pts.count - 1)]
        while let (i, j) = stack.popLast() {
            guard j > i + 1 else { continue }
            var best = -1
            var bestD: Float = 0
            for k in (i + 1)..<j {
                let d = closestOnSegment(pts[k], pts[i], pts[j]).dist
                if d > bestD { bestD = d; best = k }
            }
            if bestD > tol, best >= 0 {
                keep[best] = true
                stack.append((i, best))
                stack.append((best, j))
            }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }

    static func onBoundary(_ poly: [V2], _ p: V2, eps: Float = 1e-3) -> Bool {
        for i in 0..<poly.count where closestOnSegment(p, poly[i], poly[(i + 1) % poly.count]).dist < eps { return true }
        return false
    }

    /// True if two polygons touch, overlap or come within `gap` of each other.
    static func overlaps(_ a: [V2], _ b: [V2], gap: Float = 0) -> Bool {
        func segDist(_ p1: V2, _ p2: V2, _ q1: V2, _ q2: V2) -> Float {
            if segmentsCross(p1, p2, q1, q2) { return 0 }
            return min(closestOnSegment(p1, q1, q2).dist, closestOnSegment(p2, q1, q2).dist,
                       closestOnSegment(q1, p1, p2).dist, closestOnSegment(q2, p1, p2).dist)
        }
        for i in 0..<a.count {
            for j in 0..<b.count where segDist(a[i], a[(i + 1) % a.count], b[j], b[(j + 1) % b.count]) <= gap {
                return true
            }
        }
        return contains(a, b[0]) || contains(b, a[0])
    }

    static func segmentsCross(_ a: V2, _ b: V2, _ c: V2, _ d: V2) -> Bool {
        func cross(_ o: V2, _ p: V2, _ q: V2) -> Float { (p - o).crossp(q - o) }
        let d1 = cross(c, d, a), d2 = cross(c, d, b), d3 = cross(a, b, c), d4 = cross(a, b, d)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    /// Splits a simple polygon by the infinite line through `a` and `b`. Succeeds only
    /// when the line crosses the outline exactly twice (one cut, two pieces). Lines may
    /// pass exactly through corners or run along edges (box nets do this all the time).
    /// Returns both sides (counter-clockwise) and the crease end points.
    static func splitByLine(_ input: [V2], _ a: V2, _ b: V2) -> (left: [V2], right: [V2], p: V2, q: V2)? {
        let poly = signedArea(input) < 0 ? Array(input.reversed()) : input
        let n = poly.count
        let dir = b - a
        guard n >= 3, dir.len > 1e-4 else { return nil }
        let u = dir.unit
        let eps: Float = 1e-4
        // Which side of the line each vertex is on: +1, −1 or 0 (on the line).
        let side: [Int] = poly.map { p in
            let d = u.crossp(p - a)
            return abs(d) < eps ? 0 : (d > 0 ? 1 : -1)
        }
        guard side.contains(1), side.contains(-1) else { return nil }
        // Walk the outline as a ring with crossing points marked: strict sign changes
        // across an edge add an interpolated point; vertices (or runs of vertices) on
        // the line between opposite sides become crossings themselves.
        var ring: [(p: V2, cross: Bool)] = []
        var i = 0
        // Start just after a vertex that is off the line, so runs never wrap.
        let start = (side.firstIndex { $0 != 0 }! + 1) % n
        var lastSide = side[(start - 1 + n) % n]
        while i < n {
            let k = (start + i) % n
            if side[k] == 0 {
                // A run of on-line vertices.
                var run: [Int] = []
                while i < n && side[(start + i) % n] == 0 {
                    run.append((start + i) % n)
                    i += 1
                }
                let next = side[(start + i) % n]
                if next != lastSide {
                    // The polygon crosses the line along this run. The run's edges belong
                    // to the side the interior lies on (left of the CCW outline); the cut
                    // happens at the run end touching the other side.
                    var crossAt = run.count - 1
                    if run.count > 1 {
                        let d = poly[run[run.count - 1]] - poly[run[0]]
                        let interior = u.crossp(V2(-d.y, d.x)) > 0 ? 1 : -1
                        crossAt = interior == lastSide ? run.count - 1 : 0
                    }
                    for (r, idx) in run.enumerated() { ring.append((poly[idx], r == crossAt)) }
                } else {
                    for idx in run { ring.append((poly[idx], false)) }
                }
                continue
            }
            ring.append((poly[k], false))
            let j = (k + 1) % n
            if side[j] != 0 && side[j] != side[k] {
                let dk = u.crossp(poly[k] - a), dj = u.crossp(poly[j] - a)
                ring.append((poly[k] + (poly[j] - poly[k]) * (dk / (dk - dj)), true))
            }
            lastSide = side[k]
            i += 1
        }
        let crossings = ring.indices.filter { ring[$0].cross }
        guard crossings.count == 2 else { return nil }
        let c1 = crossings[0], c2 = crossings[1]
        let sideA = Array(ring[c1...c2]).map { $0.p }
        let sideB = (Array(ring[c2...]) + Array(ring[...c1])).map { $0.p }
        func clean(_ p: [V2]) -> [V2] {
            var out: [V2] = []
            for q in p where out.last.map({ $0.dist(q) > 1e-5 }) ?? true { out.append(q) }
            if let f = out.first, let l = out.last, out.count > 2, f.dist(l) < 1e-5 { out.removeLast() }
            return Poly.signedArea(out) < 0 ? out.reversed() : out
        }
        let A = clean(sideA), B = clean(sideB)
        guard A.count >= 3, B.count >= 3, abs(signedArea(A)) > 1e-4, abs(signedArea(B)) > 1e-4 else { return nil }
        return (A, B, ring[c1].p, ring[c2].p)
    }

    /// Ray against a flat slab (outline × [0, thickness]) in its own frame. Returns the
    /// distance along the ray and whether the top face (y = thickness) was hit.
    static func raySlab(origin o: V3, dir d: V3, outline: [V2], thickness t: Float) -> (distance: Float, top: Bool)? {
        guard abs(d.y) > 1e-6 else { return nil }
        let y: Float = d.y < 0 ? t : 0
        // Coming from above we meet the top face first; from below, the underside.
        guard (d.y < 0 && o.y > y) || (d.y > 0 && o.y < y) else { return nil }
        let k = (y - o.y) / d.y
        guard k > 0 else { return nil }
        let p = o + d * k
        return contains(outline, p.xz) ? (k, d.y < 0) : nil
    }
}
