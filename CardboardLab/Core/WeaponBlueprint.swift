import Foundation

/// A path on one face of a panel (glue beads, sharpened bevels, fullers), in the flat
/// frame of its piece.
public struct SurfacePath {
    public var piece: String
    public var panel: String
    public var points: [V3]
    /// Outward normal of the face the path lies on (flat frame).
    public var normal: V3

    /// Each point moved up to `width` into the panel on the same face: the inner border
    /// of a sanded bevel. The offset shrinks where the panel narrows (toward a tip).
    public func inset(into panel: PanelDef, width: Float) -> [V3] {
        let n = points.count
        guard n > 1 else { return points }
        func inside(_ q: V3) -> Bool { Poly.contains(outer: panel.outline, holes: panel.holes, q.xz) }
        // One side for the whole path, chosen by majority so a stray tooth can't flip it.
        var votes = 0
        for i in 0..<n {
            let side = normal.crossp(tangent(i)).unit
            votes += inside(points[i] + side * 0.1) ? 1 : (inside(points[i] - side * 0.1) ? -1 : 0)
        }
        let sign: Float = votes >= 0 ? 1 : -1
        return (0..<n).map { i in
            let side = normal.crossp(tangent(i)).unit * sign
            var w = width
            while w > 0.015 && !inside(points[i] + side * w) { w *= 0.7 }
            return points[i] + side * (w > 0.015 ? w : 0)
        }
    }

    func tangent(_ i: Int) -> V3 {
        let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
        return (b - a).unit
    }
}

/// Turns a `WeaponDesign` into everything the crafting session needs: the cut-out
/// pieces on a sheet, fold targets, assembly poses (all in the handle's frame), glue
/// and sharpening paths. Sizes derive from the board thickness so parts meet flush.
///
/// Piece ids: "blade", "handle", "guard" (front clip), "end" (pommel / axe head),
/// "wrap0", "wrap1", …
public struct WeaponBlueprint {
    public let design: WeaponDesign
    public let t: Float
    public let template: CraftTemplate

    // Handle box (inner dimensions).
    public let W: Float
    public let H: Float
    public let L: Float
    public let tab: Float = 0.45
    // Blade.
    public let ridgeAngle: Float = radians(20)
    public let tangHalf: Float
    public let bandWidth: Float = 0.8
    /// Clip bridge clearance around the handle.
    let clearance: Float = 0.02

    public var outerWidth: Float { W + 2 * t }
    public var outerHeight: Float { H + 2 * t }
    public var blade: BladeSpec? { design.blade }
    public var hasBlade: Bool { design.blade != nil }
    public var isRidge: Bool { design.blade?.build == .ridge }
    public var bladeFoldPanel: String { isRidge ? "BL" : "LB" }
    public var bladeRootPanel: String { isRidge ? "BU" : "LA" }

    public init(design raw: WeaponDesign, thickness: Float) {
        let design = raw.sanitized()
        self.design = design
        let t = thickness
        self.t = t
        W = design.handleWidth
        H = design.handleHeight
        L = design.handleLength
        if let b = design.blade {
            if b.build == .ridge {
                tangHalf = min(0.5, design.handleWidth / 2 - 0.15, b.width / 2 - 0.22)
            } else {
                tangHalf = min(0.5, design.handleWidth / 2 - 0.15, b.width * 0.4 - 0.14)
            }
        } else {
            tangHalf = 0.4
        }

        var pieces: [PieceDef] = []
        pieces.append(PieceDef(id: "handle", name: design.kind == .axe ? "Shaft" : "Handle", placement: V2(0, 0),
                               panels: WeaponBlueprint.handlePanels(W: W, H: H, L: L, t: t, lanyard: design.lanyardHole && design.endClip == nil)))
        if let b = design.blade {
            let panels = b.build == .ridge
                ? WeaponBlueprint.ridgePanels(b, tangHalf: tangHalf, angle: ridgeAngle)
                : WeaponBlueprint.laminatePanels(b, tangHalf: tangHalf)
            pieces.append(PieceDef(id: "blade", name: "Blade", placement: V2(0, 0), panels: panels))
        }
        let hb = H + 2 * t + 2 * clearance
        let bw = W + 2 * t
        var slot: (centre: V2, size: V2)? = nil
        if WeaponBlueprint.hasBladeStatic(design) {
            let s = WeaponBlueprint.tangSection(design: design, W: W, H: H, t: t, tangHalf: tangHalf, angle: ridgeAngle)
            // Bridge flat u ↔ handle y (offset by the clearance), flat v ↔ −handle z.
            slot = (V2(s.yMid + clearance, 0), V2(s.height + 0.12, s.width + 0.12))
        }
        if let g = design.guardClip {
            pieces.append(PieceDef(id: "guard", name: "Guard", placement: V2(0, 0),
                                   panels: WeaponBlueprint.clipPanels(g, bridgeHeight: hb, bridgeWidth: bw, slot: slot)))
        }
        if let e = design.endClip {
            pieces.append(PieceDef(id: "end", name: e.style.isAxeHead ? "Axe head" : "Pommel", placement: V2(0, 0),
                                   panels: WeaponBlueprint.clipPanels(e, bridgeHeight: hb, bridgeWidth: bw, slot: nil)))
        }
        for (i, _) in design.wraps.enumerated() {
            pieces.append(PieceDef(id: "wrap\(i)", name: i == 0 && design.kind == .knife ? "Guard band" : "Grip band", placement: V2(0, 0),
                                   panels: WeaponBlueprint.bandPanels(W: W, H: H, t: t, width: bandWidth)))
        }
        let (packed, sheet) = WeaponBlueprint.pack(pieces)
        template = CraftTemplate(sheetSize: sheet, thickness: t, pieces: packed)
    }

    public func piece(_ id: String) -> PieceDef? { template.piece(id) }

    public static func sheetPose(_ piece: PieceDef) -> Pose {
        .translation(piece.placement.onMat(0))
    }

    // MARK: Handle

    static func handlePanels(W: Float, H: Float, L: Float, t: Float, lanyard: Bool) -> [PanelDef] {
        let g: Float = 0.45
        let H2 = H - t
        let lanyardU = L - 0.62
        let hbHoles = lanyard ? [Poly.circle(center: V2(lanyardU, 0), radius: 0.2, sides: 8, phase: .pi / 8)] : []
        let htHoles = lanyard ? [Poly.circle(center: V2(lanyardU, -W - H), radius: 0.2, sides: 8, phase: .pi / 8)] : []
        return [
            PanelDef("HB", Poly.rect(0, -W / 2, L, W / 2), holes: hbHoles),
            PanelDef("HS1", Poly.rect(0, -W / 2 - H, L, -W / 2), parent: "HB", hinge: HingeDef(V2(0, -W / 2), V2(L, -W / 2))),
            PanelDef("HT", Poly.rect(0, -W / 2 - H - (W + t), L + t, -W / 2 - H), holes: htHoles,
                     parent: "HS1", hinge: HingeDef(V2(0, -W / 2 - H), V2(L, -W / 2 - H))),
            PanelDef("HS2", Poly.rect(0, W / 2, L, W / 2 + H2), parent: "HB", hinge: HingeDef(V2(0, W / 2), V2(L, W / 2))),
            PanelDef("GT", [V2(0.12, W / 2 + H2), V2(L - 0.12, W / 2 + H2), V2(L - 0.42, W / 2 + H2 + g), V2(0.42, W / 2 + H2 + g)],
                     parent: "HS2", hinge: HingeDef(V2(0.12, W / 2 + H2), V2(L - 0.12, W / 2 + H2)), role: .glueTab),
            PanelDef("EC", [V2(L, -W / 2), V2(L + H, -W / 2 + 0.1), V2(L + H, W / 2 - 0.1), V2(L, W / 2)],
                     parent: "HB", hinge: HingeDef(V2(L, -W / 2), V2(L, W / 2))),
        ]
    }

    // MARK: Blades

    static func ridgePanels(_ b: BladeSpec, tangHalf: Float, angle: Float) -> [PanelDef] {
        var upper = BladeShapes.ridgeUpper(b, tangHalf: tangHalf)
        if !Poly.isSimple(upper) {
            var plain = b
            plain.tip = .spear
            plain.edge = .plain
            upper = BladeShapes.ridgeUpper(plain, tangHalf: tangHalf)
        }
        let lower = upper.map { V2($0.x, -$0.y) }
        return [
            PanelDef("BU", upper),
            PanelDef("BL", lower, parent: "BU",
                     hinge: HingeDef(V2(-b.length, 0), V2(b.tangLength, 0), .mountain, degrees: angle * 2 * 180 / .pi)),
        ]
    }

    static func laminatePanels(_ b: BladeSpec, tangHalf: Float) -> [PanelDef] {
        var shape = BladeShapes.laminate(b, tangHalf: tangHalf).outline
        if !Poly.isSimple(shape) {
            var calm = b
            calm.curve = 0
            calm.edge = .plain
            shape = BladeShapes.laminate(calm, tangHalf: tangHalf).outline
        }
        let twin = shape.map { V2(2 * b.tangLength - $0.x, $0.y) }
        return [
            PanelDef("LA", shape),
            PanelDef("LB", twin, parent: "LA",
                     hinge: HingeDef(V2(b.tangLength, -tangHalf), V2(b.tangLength, tangHalf), .valley, degrees: 180)),
        ]
    }

    static func hasBladeStatic(_ d: WeaponDesign) -> Bool { d.blade != nil && d.guardClip != nil }

    /// Blade lift for the ridge fold: the root half tilts about the crease and lifts so
    /// both outer edges stay on the mat.
    public func bladeRootPose(_ p: Float) -> Pose {
        guard isRidge, let b = blade else { return .identity }
        let a = ridgeAngle * p
        return Pose.translation(V3(0, b.width / 2 * sin(a), 0)) * Pose(rot: Quat(axis: V3(1, 0, 0), angle: -a))
    }

    public func bladeAngles(_ p: Float) -> [String: Float] {
        isRidge ? ["BL": -2 * ridgeAngle * p] : ["LB": .pi * p]
    }

    /// Cross-section of the seated tang in handle space (for the guard slot).
    static func tangSection(design: WeaponDesign, W: Float, H: Float, t: Float, tangHalf: Float, angle: Float)
        -> (yMid: Float, height: Float, width: Float) {
        guard let b = design.blade else { return (H / 2 + t, 0.4, 0.8) }
        if b.build == .ridge {
            let lift = b.width / 2 * sin(angle)
            let low = (b.width / 2 - tangHalf) * sin(angle)
            let high = lift + t * cos(angle)
            let dy = (t + H / 2) - (low + high) / 2
            return (dy + (low + high) / 2, high - low, 2 * tangHalf * cos(angle) + 0.04)
        } else {
            return (t + H / 2, 2 * t, 2 * tangHalf)
        }
    }

    // MARK: Assembly (handle frame)

    /// Blade seated in the handle: shoulders against the guard (if any), tang centred.
    public var bladeSeated: Pose {
        guard let b = blade else { return .identity }
        let front: Float = design.guardClip != nil ? -t : 0
        if b.build == .ridge {
            let lift = b.width / 2 * sin(ridgeAngle)
            let low = (b.width / 2 - tangHalf) * sin(ridgeAngle)
            let high = lift + t * cos(ridgeAngle)
            let dy = (t + H / 2) - (low + high) / 2
            return Pose.translation(V3(front, dy, 0)) * bladeRootPose(1)
        }
        return Pose.translation(V3(front, H / 2, 0))
    }

    /// Blade lined up in front of the handle, ready to slide in.
    public var bladeReady: Pose {
        Pose.translation(V3(-((blade?.tangLength ?? 3) + 0.7), 0, 0)) * bladeSeated
    }

    /// Guard clip over the front of the handle: bridge across the mouth (tang slot),
    /// wings on the top and bottom faces.
    public var guardMount: Pose {
        let rot = Quat.fromBasis(x: V3(0, 1, 0), y: V3(1, 0, 0), z: V3(0, 0, -1))
        return Pose.translation(V3(-t, -clearance, 0)) * Pose(rot: rot)
    }

    /// Pommel / axe head clip over the far end of the handle.
    public var endMount: Pose {
        let rot = Quat.fromBasis(x: V3(0, 1, 0), y: V3(-1, 0, 0), z: V3(0, 0, 1))
        return Pose.translation(V3(L + 2 * t, -clearance, 0)) * Pose(rot: rot)
    }

    /// Clip lined up just off its end of the handle, ready to slide on.
    public func clipReady(_ pieceID: String) -> Pose {
        let isGuard = pieceID == "guard"
        let gap = ((isGuard ? design.guardClip : design.endClip)?.depth ?? 0.6) + 0.7
        return isGuard ? Pose.translation(V3(-gap, 0, 0)) * guardMount : Pose.translation(V3(gap, 0, 0)) * endMount
    }

    /// Band wrapped around the handle `inset` from its front.
    public func wrapMount(_ i: Int) -> Pose {
        let inset = i < design.wraps.count ? design.wraps[i] : 0.12
        let origin = V3(inset + bandWidth, H + 2 * t, -W / 2 - t)
        return Pose.translation(origin) * Pose(rot: Quat(axis: V3(0, 1, 0), angle: -.pi / 2))
    }

    /// Fold state of a fully assembled piece.
    public func finishedAngles(_ pieceID: String) -> [String: Float] {
        guard let p = piece(pieceID) else { return [:] }
        if pieceID == "blade" { return bladeAngles(1) }
        var a: [String: Float] = [:]
        for panel in p.panels { if let h = panel.hinge { a[panel.id] = h.signedTarget } }
        return a
    }

    /// Handle-frame pose of each assembled piece.
    public func assembledPose(_ pieceID: String) -> Pose {
        switch pieceID {
        case "handle": return .identity
        case "blade": return bladeSeated
        case "guard": return guardMount
        case "end": return endMount
        default:
            if pieceID.hasPrefix("wrap"), let i = Int(pieceID.dropFirst(4)) { return wrapMount(i) }
            return .identity
        }
    }

    /// Bounds of the finished weapon in handle space.
    public func assembledBounds() -> (min: V3, max: V3) {
        var lo = V3(repeating: .greatestFiniteMagnitude), hi = V3(repeating: -.greatestFiniteMagnitude)
        for p in template.pieces {
            var rig = FoldRig(piece: p, thickness: t)
            rig.angles = finishedAngles(p.id)
            let pose = assembledPose(p.id)
            for c in rig.foldedCorners() {
                let q = pose.apply(c)
                lo = V3(min(lo.x, q.x), min(lo.y, q.y), min(lo.z, q.z))
                hi = V3(max(hi.x, q.x), max(hi.y, q.y), max(hi.z, q.z))
            }
        }
        return (lo, hi)
    }

    public var assembledCentre: V3 {
        let b = assembledBounds()
        return (b.min + b.max) / 2
    }

    // MARK: Clips (guards, pommels, axe heads)

    /// Wing outline in wing space: d ≥ 0 runs along the handle away from the bridge,
    /// s is sideways. The hinge to the bridge is the segment |s| ≤ hw at d = 0.
    public static func wingOutline(_ c: ClipSpec, hw: Float) -> [V2] {
        let shape = rawWing(c, hw: hw)
        if Poly.isSimple(shape) && abs(Poly.signedArea(shape)) > 0.05 { return shape }
        // Fallback for extreme Free Craft settings: a plain bar.
        let S = max(c.span, hw + 0.3), D = max(c.depth, 0.3)
        return [V2(-S, 0), V2(S, 0), V2(S, D), V2(-S, D)]
    }

    static func rawWing(_ c: ClipSpec, hw: Float) -> [V2] {
        let S = max(c.span, c.style.isGuard ? 2 * hw + 0.2 : hw + 0.3), D = c.depth
        func sym(_ right: [V2]) -> [V2] {
            // `right` runs from the hinge outward and back along +s; mirror for −s.
            right + right.reversed().map { V2(-$0.x, $0.y) }
        }
        switch c.style {
        case .bar:
            return sym([V2(S, 0), V2(S, D * 0.7), V2(S - 0.2, D)])
        case .flared:
            return sym([V2(S * 0.75, 0), V2(S, D), V2(S * 0.7, D * 0.75), V2(hw, D * 0.6)])
        case .spiked:
            return sym([V2(S * 0.6, 0), V2(S, D * 0.25), V2(S * 0.7, D * 0.6), V2(S * 0.9, D * 1.3), V2(S * 0.5, D * 0.8), V2(hw, D * 0.8)])
        case .disc:
            return sym([V2(S, 0), V2(S, D * 0.6), V2(S * 0.7, D)])
        case .diamond:
            return sym([V2(hw, 0), V2(S, D * 0.5), V2(hw * 0.6, D)])
        case .knob:
            return sym([V2(hw * 1.05, 0), V2(S, D * 0.35), V2(S, D * 0.75), V2(S * 0.6, D)])
        case .spike:
            return sym([V2(hw, 0), V2(S, D * 0.3), V2(hw * 0.5, D)])
        case .bit:
            let eye = D * 0.45
            return [V2(-hw, 0), V2(S * 0.9, 0), V2(S, D * 0.25), V2(S * 1.02, D * 0.6), V2(S * 0.85, D),
                    V2(S * 0.55, D * 0.72), V2(S * 0.3, D * 0.55), V2(hw, eye), V2(-hw, eye)]
        case .doubleBit:
            let eye = D * 0.45
            let right = [V2(S * 0.9, 0), V2(S, D * 0.25), V2(S * 1.02, D * 0.6), V2(S * 0.85, D),
                         V2(S * 0.55, D * 0.72), V2(S * 0.3, D * 0.55), V2(hw, eye)]
            return right + right.reversed().map { V2(-$0.x, $0.y) }
        case .bearded:
            let eye = D * 0.5
            return [V2(-hw, 0), V2(S * 0.85, 0), V2(S, D * 0.2), V2(S * 1.04, D * 0.62), V2(S * 0.78, D),
                    V2(S * 0.5, D * 0.86), V2(hw + 0.25, D * 0.62), V2(hw, eye), V2(-hw, eye)]
        }
    }

    /// Cutting edge(s) of an axe head wing, in wing space.
    public static func wingEdges(_ c: ClipSpec, hw: Float) -> [[V2]] {
        let S = max(c.span, hw + 0.3), D = c.depth
        switch c.style {
        case .bit: return [[V2(S * 0.9, 0.02), V2(S, D * 0.25), V2(S * 1.02, D * 0.6), V2(S * 0.85, D)]]
        case .bearded: return [[V2(S * 0.85, 0.02), V2(S, D * 0.2), V2(S * 1.04, D * 0.62), V2(S * 0.78, D)]]
        case .doubleBit:
            let r = [V2(S * 0.9, 0.02), V2(S, D * 0.25), V2(S * 1.02, D * 0.6), V2(S * 0.85, D)]
            return [r, r.map { V2(-$0.x, $0.y) }]
        default: return []
        }
    }

    /// Clip net: bridge (rect, optional slot) with a wing hinged on each long edge.
    /// Net coordinates: u across the bridge (handle height), v sideways.
    static func clipPanels(_ c: ClipSpec, bridgeHeight hb: Float, bridgeWidth bw: Float, slot: (centre: V2, size: V2)?) -> [PanelDef] {
        let hw = bw / 2
        let wing = wingOutline(c, hw: hw)
        let wingA = wing.map { V2(-$0.y, $0.x) }
        let wingB = wing.map { V2(hb + $0.y, $0.x) }
        var holes: [[V2]] = []
        if let s = slot {
            let h = s.size / 2
            holes = [Poly.rect(s.centre.x - h.x, s.centre.y - h.y, s.centre.x + h.x, s.centre.y + h.y)]
        }
        return [
            PanelDef("B0", Poly.rect(0, -hw, hb, hw), holes: holes),
            PanelDef("WA", wingA, parent: "B0", hinge: HingeDef(V2(0, -hw), V2(0, hw))),
            PanelDef("WB", wingB, parent: "B0", hinge: HingeDef(V2(hb, -hw), V2(hb, hw))),
        ]
    }

    /// Wing-space point → clip net coordinates on the top wing (WB).
    public func wingToNet(_ p: V2) -> V2 {
        V2(H + 2 * t + 2 * clearance + p.y, p.x)
    }

    // MARK: Bands

    static func bandPanels(W: Float, H: Float, t: Float, width bw: Float) -> [PanelDef] {
        let wo = W + 2 * t, ho = H + 2 * t
        let c1 = wo, c2 = wo + ho, c3 = 2 * wo + ho, c4 = 2 * wo + 2 * ho + t
        return [
            PanelDef("C0", Poly.rect(0, 0, c1, bw)),
            PanelDef("C1", Poly.rect(c1, 0, c2, bw), parent: "C0", hinge: HingeDef(V2(c1, 0), V2(c1, bw), .mountain)),
            PanelDef("C2", Poly.rect(c2, 0, c3, bw), parent: "C1", hinge: HingeDef(V2(c2, 0), V2(c2, bw), .mountain)),
            PanelDef("C3", Poly.rect(c3, 0, c4, bw), parent: "C2", hinge: HingeDef(V2(c3, 0), V2(c3, bw), .mountain)),
            PanelDef("C4", [V2(c4, 0), V2(c4 + 0.45, 0.12), V2(c4 + 0.45, bw - 0.12), V2(c4, bw)],
                     parent: "C3", hinge: HingeDef(V2(c4, 0), V2(c4, bw), .mountain), role: .glueTab),
        ]
    }

    // MARK: Glue

    public var handleGlue: SurfacePath {
        let v = W / 2 + (H - t) + tab * 0.45
        return SurfacePath(piece: "handle", panel: "GT", points: [V3(0.55, -0.012, v), V3(L - 0.55, -0.012, v)], normal: V3(0, -1, 0))
    }

    /// Ridge blades: glue on the tang before it slides into the handle.
    /// Laminated blades: glue down the middle of the first layer before folding the twin over.
    public var bladeGlue: SurfacePath? {
        guard let b = blade else { return nil }
        if b.build == .ridge {
            return SurfacePath(piece: "blade", panel: "BU",
                               points: [V3(0.35, t + 0.012, -tangHalf * 0.5), V3(b.tangLength - 0.35, t + 0.012, -tangHalf * 0.5)],
                               normal: V3(0, 1, 0))
        }
        let shape = BladeShapes.laminate(b, tangHalf: tangHalf)
        // Follow the blade's centre line from the tang into the blade.
        var pts: [V3] = [V3(b.tangLength - 0.35, t + 0.012, 0), V3(0, t + 0.012, 0)]
        let n = shape.centre.count
        for i in stride(from: 3, to: Int(Float(n) * 0.72), by: 3) {
            pts.append(shape.centre[i].onMat(t + 0.012))
        }
        return SurfacePath(piece: "blade", panel: "LA", points: pts, normal: V3(0, 1, 0))
    }

    /// Glue across the top wing of a clip (inside face, applied while flat).
    public func clipGlue(_ pieceID: String) -> SurfacePath? {
        guard let c = pieceID == "guard" ? design.guardClip : design.endClip else { return nil }
        let hw = (W + 2 * t) / 2
        let d = c.depth * 0.4
        let reach = min(max(c.span, hw + 0.2) * 0.75, hw + 1.6)
        let a = wingToNet(V2(-reach, d)), b = wingToNet(V2(reach, d))
        return SurfacePath(piece: pieceID, panel: "WB", points: [a.onMat(t + 0.012), b.onMat(t + 0.012)], normal: V3(0, 1, 0))
    }

    public func wrapGlue(_ pieceID: String) -> SurfacePath {
        SurfacePath(piece: pieceID, panel: "C0", points: [V3(0.22, t + 0.012, 0.16), V3(0.22, t + 0.012, bandWidth - 0.16)],
                    normal: V3(0, 1, 0))
    }

    // MARK: Sharpening (molding the edge and tip)

    /// Edges sanded into bevels, on the faces that end up on top.
    public var sharpenPaths: [SurfacePath] {
        var out: [SurfacePath] = []
        if let b = blade {
            if b.build == .ridge {
                let edge = BladeShapes.ridgeEdgePath(b)
                out.append(SurfacePath(piece: "blade", panel: "BU", points: edge.map { $0.onMat(t + 0.006) }, normal: V3(0, 1, 0)))
                out.append(SurfacePath(piece: "blade", panel: "BL", points: edge.map { V2($0.x, -$0.y).onMat(t + 0.006) }, normal: V3(0, 1, 0)))
            } else {
                let edge = BladeShapes.laminate(b, tangHalf: tangHalf).edge
                // The twin's underside faces up once folded over.
                let twin = edge.map { V2(2 * b.tangLength - $0.x, $0.y) }
                out.append(SurfacePath(piece: "blade", panel: "LB", points: twin.map { $0.onMat(-0.006) }, normal: V3(0, -1, 0)))
            }
        }
        if let e = design.endClip, e.style.isAxeHead {
            let hw = (W + 2 * t) / 2
            for edge in WeaponBlueprint.wingEdges(e, hw: hw) {
                out.append(SurfacePath(piece: "end", panel: "WB", points: edge.map { wingToNet($0).onMat(-0.006) }, normal: V3(0, -1, 0)))
            }
        }
        return out
    }

    /// Fuller grooves carved down a ridge blade.
    public var fullerPaths: [SurfacePath] {
        guard let b = blade, b.build == .ridge, b.fuller else { return [] }
        let h0 = b.width / 2
        let pts = stride(from: Float(0.06), through: 0.62, by: 0.08).map { s -> V2 in
            V2(-b.length * s, -h0 * BladeShapes.ridgeFraction(b.tip, s) * 0.42)
        }
        return [
            SurfacePath(piece: "blade", panel: "BU", points: pts.map { $0.onMat(t + 0.007) }, normal: V3(0, 1, 0)),
            SurfacePath(piece: "blade", panel: "BL", points: pts.map { V2($0.x, -$0.y).onMat(t + 0.007) }, normal: V3(0, 1, 0)),
        ]
    }

    // MARK: Sheet layout

    /// Shelf-packs the pieces onto a sheet centred on the origin, trying several row
    /// widths and keeping the layout that best fits the cutting mat.
    static func pack(_ pieces: [PieceDef]) -> ([PieceDef], V2) {
        let gap: Float = 0.7, border: Float = 0.9
        let bounds = pieces.map { Poly.bounds($0.outline) }
        let widths = bounds.map { $0.max.x - $0.min.x }
        let heights = bounds.map { $0.max.y - $0.min.y }
        let order = pieces.indices.sorted { heights[$0] * 100 + widths[$0] > heights[$1] * 100 + widths[$1] }
        let widest = widths.max() ?? 10

        func layout(rowLimit: Float) -> ([V2], V2) {
            var placements = [V2](repeating: V2(0, 0), count: pieces.count)
            var x: Float = 0, y: Float = 0, rowH: Float = 0, maxX: Float = 0
            for i in order {
                let w = widths[i], h = heights[i]
                if x > 0 && x + w > rowLimit + 0.01 {
                    x = 0
                    y += rowH + gap
                    rowH = 0
                }
                placements[i] = V2(x - bounds[i].min.x, y - bounds[i].min.y)
                x += w + gap
                rowH = max(rowH, h)
                maxX = max(maxX, x - gap)
            }
            return (placements, V2(maxX, y + rowH))
        }

        var best: ([V2], V2)? = nil
        var bestScore = Float.greatestFiniteMagnitude
        var limit = max(widest, 10)
        while limit <= 26.01 {
            let candidate = layout(rowLimit: limit)
            let sheet = candidate.1 + V2(2 * border, 2 * border)
            // Fit the 27.5 × 19 usable mat area; prefer compact, landscape sheets.
            let score = max(sheet.x / 27.5, sheet.y / 19) + 0.002 * sheet.x * sheet.y / 100
            if score < bestScore {
                bestScore = score
                best = candidate
            }
            limit += 1
        }
        let (placements, total) = best ?? layout(rowLimit: max(widest, 13))
        let sheet = total + V2(2 * border, 2 * border)
        let origin = V2(-total.x / 2, -total.y / 2)
        let out = pieces.indices.map { i -> PieceDef in
            var p = pieces[i]
            p.placement = placements[i] + origin
            return p
        }
        return (out, sheet)
    }
}
