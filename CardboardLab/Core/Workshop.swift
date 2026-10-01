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

extension FoldKind: Codable {}

/// One flat panel of a free piece. Panels are joined by creases into a tree.
public struct FreePanel: Codable, Equatable {
    public var id: String
    /// Outline in the piece's flat frame (counter-clockwise).
    public var outline: [V2]
    /// Holes cut out of the panel (optional on disk so older saves still load).
    public var cutouts: [[V2]]?
    public var parent: String?
    /// Crease to the parent panel.
    public var hingeA: V2?
    public var hingeB: V2?
    /// Valley creases fold toward the top face, mountain creases away from it.
    public var fold: FoldKind?
    /// Fold angle relative to the parent (radians, + folds toward the top face).
    public var angle: Float = 0
    public var top: PaintColor?
    public var under: PaintColor?

    public init(id: String, outline: [V2], holes: [[V2]] = [], parent: String? = nil, hingeA: V2? = nil, hingeB: V2? = nil,
                fold: FoldKind? = nil, angle: Float = 0, top: PaintColor? = nil, under: PaintColor? = nil) {
        self.id = id
        self.outline = Poly.signedArea(outline) < 0 ? outline.reversed() : outline
        self.cutouts = holes.isEmpty ? nil : holes
        self.parent = parent
        self.hingeA = hingeA
        self.hingeB = hingeB
        self.fold = fold
        self.angle = angle
        self.top = top
        self.under = under
    }

    public var holes: [[V2]] {
        get { cutouts ?? [] }
        set { cutouts = newValue.isEmpty ? nil : newValue }
    }

    public var foldKind: FoldKind { fold ?? .valley }
}

/// A piece of cardboard on the table: a fresh sheet or anything cut from one.
public struct FreePiece: Codable, Equatable {
    public var id: String
    public var panels: [FreePanel]
    /// World pose of the flat frame, or relative to `gluedTo`'s frame when glued.
    public var pose: StoredPose
    public var gluedTo: String?
    public var nextPanel = 1
    /// Cardboard stock id (texture, colours, thickness).
    public var stock: String?
    /// True for sheets taken from the pile (they're just big pieces).
    public var sheet: Bool?

    public init(id: String, panels: [FreePanel], pose: Pose, gluedTo: String? = nil, stock: String? = nil, sheet: Bool = false) {
        self.id = id
        self.panels = panels
        self.pose = StoredPose(pose)
        self.gluedTo = gluedTo
        self.stock = stock
        self.sheet = sheet ? true : nil
    }

    public func panel(_ id: String) -> FreePanel? { panels.first { $0.id == id } }
    public func panelIndex(_ id: String) -> Int? { panels.firstIndex { $0.id == id } }

    public var thickness: Float { CardboardStock.byID(stock ?? CardboardStock.plain.id).thickness }
    public var isSheet: Bool { sheet ?? false }

    /// Template form, for folding and meshing with the same code as the campaign.
    public var pieceDef: PieceDef {
        let defs = panels.map { p -> PanelDef in
            var hinge: HingeDef? = nil
            if let a = p.hingeA, let b = p.hingeB { hinge = HingeDef(a, b, p.foldKind, degrees: 90) }
            return PanelDef(p.id, p.outline, holes: p.holes, parent: p.parent, hinge: hinge)
        }
        return PieceDef(id: id, name: isSheet ? "Sheet" : "Piece", placement: V2(0, 0), panels: defs)
    }

    public var angles: [String: Float] {
        var a: [String: Float] = [:]
        for p in panels where p.parent != nil { a[p.id] = p.angle }
        return a
    }

    /// Folded pose of each panel in the piece frame.
    public func rig() -> FoldRig {
        var r = FoldRig(piece: pieceDef, thickness: thickness)
        r.angles = angles
        return r
    }

    /// The panel and every panel hanging off it.
    public func subtree(_ id: String) -> Set<String> {
        var out: Set<String> = [id]
        var grew = true
        while grew {
            grew = false
            for p in panels where !out.contains(p.id) {
                if let parent = p.parent, out.contains(parent) {
                    out.insert(p.id)
                    grew = true
                }
            }
        }
        return out
    }
}

/// A sheet from an older save (sheets are pieces now).
public struct FreeSheet: Codable, Equatable {
    public var id: String
    public var size: V2
    public var center: V3
    public var holes: [[V2]] = []
    public var top: PaintColor?
    public var under: PaintColor?
}

public struct WorkshopState: Codable, Equatable {
    /// Only read from older saves; see `migrate`.
    public var sheets: [FreeSheet] = []
    public var pieces: [FreePiece] = []
    /// The piece the camera frames by default (usually the newest sheet).
    public var activeSheet: String?
    public var counter = 0

    public init() {}

    public mutating func makeID(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)\(counter)"
    }

    public func piece(_ id: String) -> FreePiece? { pieces.first { $0.id == id } }
    public func pieceIndex(_ id: String) -> Int? { pieces.firstIndex { $0.id == id } }

    /// Turns sheets from older saves into pieces, and gives pieces without a stock one.
    public mutating func migrate(defaultStock: String) {
        for s in sheets {
            let panel = FreePanel(id: "P0", outline: Poly.rect(-s.size.x / 2, -s.size.y / 2, s.size.x / 2, s.size.y / 2),
                                  holes: s.holes, top: s.top, under: s.under)
            pieces.insert(FreePiece(id: s.id, panels: [panel], pose: .translation(s.center), stock: defaultStock, sheet: true), at: 0)
        }
        sheets = []
        for i in pieces.indices where pieces[i].stock == nil { pieces[i].stock = defaultStock }
    }

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

    /// World pose of one panel as folded.
    public func panelWorld(_ pieceID: String, _ panelID: String) -> Pose {
        guard let p = piece(pieceID) else { return .identity }
        return worldPose(pieceID) * p.rig().pose(of: panelID)
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
    /// Sheet sizes on offer (long ones fit swords).
    public static let sheetSizes: [(name: String, size: V2)] = [
        ("Small", V2(14, 10)), ("Large", V2(20, 14)), ("Long", V2(28, 10)), ("Huge", V2(28, 20)),
    ]
    public static let sheetSize = V2(14, 10)
    public static let minArea: Float = 0.3

    public enum CutProblem: Error, Equatable {
        case tooSmall, crossesItself, missesPiece, crossesHole, crossesFold, needsEdge, tooManyCrossings
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

    /// Cleans an open stroke (a slicing cut).
    public static func cleanPath(_ raw: [V2], tolerance: Float = 0.1) -> [V2] {
        var pts: [V2] = []
        for p in raw where pts.last.map({ $0.dist(p) > 0.04 }) ?? true { pts.append(p) }
        return pts.count > 2 ? Poly.simplifyOpen(pts, tolerance) : pts
    }

    /// Adds a fresh sheet to the table.
    @discardableResult
    public static func addSheet(size: V2, stock: String, at center: V3, in state: inout WorkshopState) -> String {
        let id = state.makeID("sheet")
        let panel = FreePanel(id: "P0", outline: Poly.rect(-size.x / 2, -size.y / 2, size.x / 2, size.y / 2))
        state.pieces.append(FreePiece(id: id, panels: [panel], pose: .translation(center), stock: stock, sheet: true))
        state.activeSheet = id
        return id
    }

    // MARK: Cutting

    /// Cuts along a closed loop drawn on a panel (flat piece coordinates). Inside the
    /// panel it punches the shape out as a new piece; crossing the edge it bites that
    /// part off. Returns the new piece.
    public static func cutLoop(_ raw: [V2], piece pieceID: String, panel panelID: String,
                               in state: inout WorkshopState) -> Result<String, CutProblem> {
        let loop = Poly.signedArea(raw) < 0 ? Array(raw.reversed()) : raw
        guard loop.count >= 3, abs(Poly.signedArea(loop)) >= minArea else { return .failure(.tooSmall) }
        guard Poly.isSimple(loop) else { return .failure(.crossesItself) }
        guard let pi = state.pieceIndex(pieceID), let panel = state.pieces[pi].panel(panelID) else { return .failure(.missesPiece) }
        let crossings = Poly.pathCrossings(loop, closed: true, outline: panel.outline)
        if crossings.isEmpty {
            guard loop.allSatisfy({ Poly.contains(panel.outline, $0) }) else {
                return .failure(Poly.contains(loop, panel.outline[0]) ? .tooManyCrossings : .missesPiece)
            }
            guard loop.allSatisfy({ minDistance($0, panel.outline) > 0.06 }) else { return .failure(.needsEdge) }
            for hole in panel.holes where Poly.overlaps(loop, hole, gap: 0.06) { return .failure(.crossesHole) }
            // Punch out: a hole in the panel and a new piece lying exactly where it was.
            let piece = state.pieces[pi]
            let c = Poly.centroid(loop)
            let world = state.panelWorld(pieceID, panelID)
            let id = state.makeID("piece")
            let cut = FreePanel(id: "P0", outline: loop.map { $0 - c }, top: panel.top, under: panel.under)
            state.pieces.append(FreePiece(id: id, panels: [cut], pose: world * .translation(c.onMat(0)), stock: piece.stock))
            if let j = state.pieces[pi].panelIndex(panelID) { state.pieces[pi].panels[j].holes.append(loop) }
            return .success(id)
        }
        guard crossings.count == 2 else { return .failure(.tooManyCrossings) }
        // The arc of the loop inside the panel is the cut.
        let a = crossings[0], b = crossings[1]
        let inner = Poly.subPath(loop, closed: true, from: a, to: b)
        let other = Poly.subPath(loop, closed: true, from: b, to: a)
        let path = Poly.contains(panel.outline, Poly.pathMidpoint(inner)) ? inner : other
        let (from, to) = path == inner ? (a, b) : (b, a)
        return split(pieceID, panelID, along: path, entry: (from.edge, from.t), exit: (to.edge, to.t), in: &state)
    }

    /// Cuts along an open line drawn across a panel, splitting the piece in two. The
    /// line's ends are stretched a little so a stroke that stops just short of an edge
    /// still reaches it. Returns the new piece.
    public static func slice(_ raw: [V2], piece pieceID: String, panel panelID: String,
                             in state: inout WorkshopState) -> Result<String, CutProblem> {
        guard raw.count >= 2, let panel = state.piece(pieceID)?.panel(panelID) else { return .failure(.missesPiece) }
        var path = raw
        let n = path.count
        let d0 = (path[0] - path[1]).unit, d1 = (path[n - 1] - path[n - 2]).unit
        path[0] = path[0] + d0 * 0.6
        path[n - 1] = path[n - 1] + d1 * 0.6
        let crossings = Poly.pathCrossings(path, closed: false, outline: panel.outline)
        guard crossings.count >= 2 else {
            return .failure(path.allSatisfy { Poly.contains(panel.outline, $0) } ? .needsEdge : .missesPiece)
        }
        for k in 0..<(crossings.count - 1) {
            let a = crossings[k], b = crossings[k + 1]
            let inner = Poly.subPath(path, closed: false, from: a, to: b)
            if Poly.contains(panel.outline, Poly.pathMidpoint(inner)) {
                guard Poly.isSimpleOpen(inner) else { return .failure(.crossesItself) }
                return split(pieceID, panelID, along: inner, entry: (a.edge, a.t), exit: (b.edge, b.t), in: &state)
            }
        }
        return .failure(.missesPiece)
    }

    /// The exact line the knife will run along for a cut on a panel: the loop itself
    /// when it's inside, otherwise the part of the loop or slice inside the panel.
    public static func knifePath(loop: [V2]?, slice: [V2]?, outline: [V2]) -> (points: [V2], closed: Bool)? {
        if let raw = loop, raw.count >= 3 {
            let loop = Poly.signedArea(raw) < 0 ? Array(raw.reversed()) : raw
            let c = Poly.pathCrossings(loop, closed: true, outline: outline)
            if c.isEmpty { return (loop, true) }
            guard c.count == 2 else { return nil }
            let inner = Poly.subPath(loop, closed: true, from: c[0], to: c[1])
            return (Poly.contains(outline, Poly.pathMidpoint(inner)) ? inner : Poly.subPath(loop, closed: true, from: c[1], to: c[0]), false)
        }
        if let raw = slice, raw.count >= 2 {
            var path = raw
            let n = path.count
            path[0] = path[0] + (path[0] - path[1]).unit * 0.6
            path[n - 1] = path[n - 1] + (path[n - 1] - path[n - 2]).unit * 0.6
            let c = Poly.pathCrossings(path, closed: false, outline: outline)
            guard c.count >= 2 else { return nil }
            for k in 0..<(c.count - 1) {
                let inner = Poly.subPath(path, closed: false, from: c[k], to: c[k + 1])
                if Poly.contains(outline, Poly.pathMidpoint(inner)) { return (inner, false) }
            }
        }
        return nil
    }

    /// Splits one panel along a path running edge to edge. The side holding the panel's
    /// own crease (or, for the base, more creases, else more area) stays; the other side
    /// and everything folded off it becomes a new piece.
    static func split(_ pieceID: String, _ panelID: String, along path: [V2], entry: (Int, Float), exit: (Int, Float),
                      in state: inout WorkshopState) -> Result<String, CutProblem> {
        guard let pi = state.pieceIndex(pieceID), let panel = state.pieces[pi].panel(panelID) else { return .failure(.missesPiece) }
        let piece = state.pieces[pi]
        guard let (sideA, sideB) = Poly.splitByPath(panel.outline, path, entry: entry, exit: exit) else { return .failure(.crossesItself) }
        guard abs(Poly.signedArea(sideA)) > 0.05, abs(Poly.signedArea(sideB)) > 0.05 else { return .failure(.tooSmall) }
        guard Poly.isSimple(sideA), Poly.isSimple(sideB) else { return .failure(.crossesItself) }
        // Holes go with the side they're in; the cut can't run through one.
        var holesA: [[V2]] = [], holesB: [[V2]] = []
        for hole in panel.holes {
            for i in 0..<(path.count - 1) {
                for j in 0..<hole.count where Poly.segmentsCross(path[i], path[i + 1], hole[j], hole[(j + 1) % hole.count]) {
                    return .failure(.crossesHole)
                }
            }
            if Poly.contains(sideA, Poly.centroid(hole)) { holesA.append(hole) } else { holesB.append(hole) }
        }
        func holds(_ poly: [V2], _ ha: V2, _ hb: V2) -> Bool {
            Poly.onBoundary(poly, ha) && Poly.onBoundary(poly, hb) && Poly.onBoundary(poly, (ha + hb) / 2)
        }
        var keepA: Bool
        if let ha = panel.hingeA, let hb = panel.hingeB {
            let a = holds(sideA, ha, hb), b = holds(sideB, ha, hb)
            guard a != b else { return .failure(.crossesFold) }
            keepA = a
        } else {
            let kids = piece.panels.filter { $0.parent == panelID }.compactMap { k -> (V2, V2)? in
                guard let ha = k.hingeA, let hb = k.hingeB else { return nil }
                return (ha, hb)
            }
            let a = kids.filter { holds(sideA, $0.0, $0.1) }.count, b = kids.filter { holds(sideB, $0.0, $0.1) }.count
            keepA = a != b ? a > b : abs(Poly.signedArea(sideA)) >= abs(Poly.signedArea(sideB))
        }
        let kept = keepA ? sideA : sideB, gone = keepA ? sideB : sideA
        let keptHoles = keepA ? holesA : holesB, goneHoles = keepA ? holesB : holesA
        // Child creases must land wholly on one side; those on the cut-off side go with it.
        var moving: Set<String> = []
        for child in piece.panels where child.parent == panelID {
            guard let ha = child.hingeA, let hb = child.hingeB else { continue }
            let k = holds(kept, ha, hb), g = holds(gone, ha, hb)
            guard k != g else { return .failure(.crossesFold) }
            if g { moving.formUnion(piece.subtree(child.id)) }
        }
        // The cut-off part becomes a new piece in the same flat frame, posed where the
        // panel was folded to.
        let world = state.panelWorld(pieceID, panelID)
        let id = state.makeID("piece")
        var newPanels = [FreePanel(id: "P0", outline: gone, holes: goneHoles, top: panel.top, under: panel.under)]
        for p in piece.panels where moving.contains(p.id) {
            var q = p
            if q.parent == panelID { q.parent = "P0" }
            newPanels.append(q)
        }
        // Its root sits flat in its own frame, so the frame goes where the panel was.
        var fresh = FreePiece(id: id, panels: newPanels, pose: world, stock: piece.stock, sheet: piece.isSheet)
        fresh.nextPanel = piece.nextPanel
        state.pieces[pi].panels.removeAll { moving.contains($0.id) }
        if let j = state.pieces[pi].panelIndex(panelID) {
            state.pieces[pi].panels[j].outline = kept
            state.pieces[pi].panels[j].holes = keptHoles
        }
        state.pieces.append(fresh)
        return .success(id)
    }

    static func minDistance(_ p: V2, _ poly: [V2]) -> Float {
        var best = Float.greatestFiniteMagnitude
        for i in 0..<poly.count { best = min(best, Poly.closestOnSegment(p, poly[i], poly[(i + 1) % poly.count]).dist) }
        return best
    }

    // MARK: Creases

    public enum CreaseProblem: Error, Equatable {
        case missesPanel, crossesCrease, tooThin, crossesHole
    }

    /// Straightens a hand-drawn crease: nearly parallel or square to an edge snaps to
    /// it, and a line passing close to a corner snaps through the corner.
    public static func snapCrease(_ a: V2, _ b: V2, outline: [V2]) -> (V2, V2) {
        let len = a.dist(b)
        guard len > 1e-3 else { return (a, b) }
        var dir = (b - a) / len
        var mid = (a + b) / 2
        var best: Float = radians(6)
        for i in 0..<outline.count {
            let e = (outline[(i + 1) % outline.count] - outline[i]).unit
            for cand in [e, e.perp] {
                // Compare as lines (direction and its reverse are the same crease).
                let diff = acos(min(1, abs(dir.dotp(cand))))
                if diff < best {
                    best = diff
                    dir = dir.dotp(cand) >= 0 ? cand : cand * -1
                }
            }
        }
        var nearest: Float = 0.3
        var shift = V2(0, 0)
        for v in outline {
            let off = (v - mid).dotp(dir.perp)
            if abs(off) < nearest {
                nearest = abs(off)
                shift = dir.perp * off
            }
        }
        mid = mid + shift
        return (mid - dir * (len / 2), mid + dir * (len / 2))
    }

    /// Adds a crease along the line through `a` and `b` (flat piece frame) across one
    /// panel. The side holding the panel's own crease stays; for the base panel the side
    /// holding more folds (or else the bigger side) stays. Returns the new flap's id.
    public static func addCrease(_ piece: inout FreePiece, panel panelID: String, _ a: V2, _ b: V2,
                                 kind: FoldKind = .valley) -> Result<String, CreaseProblem> {
        guard let pi = piece.panelIndex(panelID) else { return .failure(.missesPanel) }
        let panel = piece.panels[pi]
        guard let split = Poly.splitByLine(panel.outline, a, b) else { return .failure(.missesPanel) }
        let (left, right, p, q) = split
        guard abs(Poly.signedArea(left)) > 0.08, abs(Poly.signedArea(right)) > 0.08, p.dist(q) > 0.2 else {
            return .failure(.tooThin)
        }
        for hole in panel.holes {
            for j in 0..<hole.count where Poly.segmentsCross(p, q, hole[j], hole[(j + 1) % hole.count]) {
                return .failure(.crossesHole)
            }
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
        piece.panels[pi].holes = panel.holes.filter { Poly.contains(kept, Poly.centroid($0)) }
        for (ci, toFlap) in moves where toFlap { piece.panels[ci].parent = newID }
        piece.panels.append(FreePanel(id: newID, outline: flap, holes: panel.holes.filter { Poly.contains(flap, Poly.centroid($0)) },
                                      parent: panelID, hingeA: p, hingeB: q, fold: kind, top: panel.top, under: panel.under))
        return .success(newID)
    }

    /// Keeps a fold angle on its crease's side (valley up, mountain down), within 180°,
    /// snapping to the nearest 15° when close (within 5°).
    public static func snapAngle(_ a: Float, kind: FoldKind = .valley) -> Float {
        let c = kind == .valley ? clampf(a, 0, .pi) : clampf(a, -.pi, 0)
        let step = radians(15)
        let s = (c / step).rounded() * step
        return abs(s - c) < radians(5) ? s : c
    }

    /// First free spot for a new sheet, spiralling out from the mat's centre so earlier
    /// sheets and pieces stay where they are.
    public static func freeSpot(size: V2, occupied boxes: [(V2, V2)]) -> V3 {
        let step = size + V2(1.5, 1.5)
        var candidates: [V2] = [V2(0, 0)]
        for ring in 1...8 {
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
        return V3(Float(boxes.count) * step.x, 0, 0)
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

    /// Where a path crosses a polygon's outline, in order along the path.
    struct PathCrossing {
        /// Segment index along the path plus the fraction along that segment.
        public var s: Float
        /// Outline edge and fraction along it.
        public var edge: Int
        public var t: Float
        public var point: V2
    }

    static func pathCrossings(_ path: [V2], closed: Bool, outline: [V2]) -> [PathCrossing] {
        var out: [PathCrossing] = []
        let segs = closed ? path.count : path.count - 1
        guard segs > 0 else { return [] }
        for i in 0..<segs {
            let p = path[i], r = path[(i + 1) % path.count] - p
            for e in 0..<outline.count {
                let q = outline[e], v = outline[(e + 1) % outline.count] - q
                let den = r.crossp(v)
                guard abs(den) > 1e-9 else { continue }
                let u = (q - p).crossp(v) / den
                let t = (q - p).crossp(r) / den
                if u >= 0 && u < 1 && t >= 0 && t < 1 {
                    out.append(PathCrossing(s: Float(i) + u, edge: e, t: t, point: p + r * u))
                }
            }
        }
        return out.sorted { $0.s < $1.s }
    }

    /// The part of a path between two crossings, starting and ending on them.
    static func subPath(_ path: [V2], closed: Bool, from a: PathCrossing, to b: PathCrossing) -> [V2] {
        var out = [a.point]
        let n = path.count
        var i = Int(a.s) + 1
        let end = Int(b.s)
        if closed && b.s < a.s {
            // Wrap around the loop.
            while i < n { out.append(path[i]); i += 1 }
            i = 0
        }
        while i <= end && i < n { out.append(path[i]); i += 1 }
        out.append(b.point)
        return out
    }

    static func pathMidpoint(_ path: [V2]) -> V2 {
        Polyline(path.map { $0.onMat() }).point(at: Polyline(path.map { $0.onMat() }).length / 2).xz
    }

    static func isSimpleOpen(_ p: [V2]) -> Bool {
        guard p.count > 3 else { return true }
        for i in 0..<(p.count - 1) {
            for j in stride(from: i + 2, to: p.count - 1, by: 1) where segmentsCross(p[i], p[i + 1], p[j], p[j + 1]) {
                return false
            }
        }
        return true
    }

    /// Splits a polygon (counter-clockwise) by a path that enters on edge `entry` and
    /// leaves on edge `exit`, running inside in between. Returns both sides, CCW.
    static func splitByPath(_ poly: [V2], _ path: [V2], entry: (Int, Float), exit: (Int, Float)) -> ([V2], [V2])? {
        let n = poly.count
        guard n >= 3, path.count >= 2 else { return nil }
        /// Outline vertices met walking forward from one boundary point to another.
        func walk(_ from: (Int, Float), _ to: (Int, Float)) -> [V2] {
            if from.0 == to.0 && to.1 >= from.1 { return [] }
            var out: [V2] = []
            var k = (from.0 + 1) % n
            var steps = 0
            while steps <= n {
                out.append(poly[k])
                if k == to.0 { break }
                k = (k + 1) % n
                steps += 1
            }
            return out
        }
        func clean(_ p: [V2]) -> [V2] {
            var out: [V2] = []
            for q in p where out.last.map({ $0.dist(q) > 1e-5 }) ?? true { out.append(q) }
            if let f = out.first, let l = out.last, out.count > 2, f.dist(l) < 1e-5 { out.removeLast() }
            return Poly.signedArea(out) < 0 ? out.reversed() : out
        }
        let a = clean(path + walk(exit, entry))
        let b = clean(path.reversed() + walk(entry, exit))
        guard a.count >= 3, b.count >= 3 else { return nil }
        return (a, b)
    }

    /// Ray against a flat slab (outline × [0, thickness]) in its own frame. Returns the
    /// distance along the ray and whether the top face (y = thickness) was hit.
    static func raySlab(origin o: V3, dir d: V3, outline: [V2], holes: [[V2]] = [], thickness t: Float) -> (distance: Float, top: Bool)? {
        guard abs(d.y) > 1e-6 else { return nil }
        let y: Float = d.y < 0 ? t : 0
        // Coming from above we meet the top face first; from below, the underside.
        guard (d.y < 0 && o.y > y) || (d.y > 0 && o.y < y) else { return nil }
        let k = (y - o.y) / d.y
        guard k > 0 else { return nil }
        let p = o + d * k
        return contains(outer: outline, holes: holes, p.xz) ? (k, d.y < 0) : nil
    }
}
