import Foundation

/// Every gun in the game. Each is a `GunSpec` — sizes of the boxes and which parts it
/// has — built by the same generator.
public enum GunKind: String, Codable, CaseIterable {
    // Pistols: a slide box with a raked grip.
    case pistol, compact, targetPistol, machinePistol
    // Revolver: a frame box with the barrel pushed through it.
    case revolver
    // Long guns: a receiver box with a barrel through its front, stock and grip.
    case rifle, carbine, smg, shotgun, sniper

    public var title: String {
        switch self {
        case .pistol: return "Pistol"
        case .compact: return "Compact Pistol"
        case .targetPistol: return "Target Pistol"
        case .machinePistol: return "Machine Pistol"
        case .revolver: return "Revolver"
        case .rifle: return "Rifle"
        case .carbine: return "Carbine"
        case .smg: return "SMG"
        case .shotgun: return "Shotgun"
        case .sniper: return "Sniper Rifle"
        }
    }

    /// One line for the menu card.
    public var blurb: String {
        switch self {
        case .pistol: return "Slide · raked grip · trigger guard · sights"
        case .compact: return "Short slide · stubby grip · sights"
        case .targetPistol: return "Long slim slide · sights"
        case .machinePistol: return "Magazine in front of the trigger"
        case .revolver: return "Frame · barrel through it · hammer"
        case .rifle: return "Barrel · scope · stock · magazine"
        case .carbine: return "Short barrel · iron sights · curved mag"
        case .smg: return "Stubby stock · long magazine"
        case .shotgun: return "Wide barrel · pump grooves · stock"
        case .sniper: return "Long barrel · big scope · long stock"
        }
    }

    public var spec: GunSpec { GunSpec.of(self) }
}

/// Sizes and parts of one gun. Boxes are inner sizes (W across, H up, L along the gun).
public struct GunSpec {
    public struct Box {
        public var W: Float, H: Float, L: Float
        public init(_ W: Float, _ H: Float, _ L: Float) { self.W = W; self.H = H; self.L = L }
    }

    /// A box hanging under the body (grip, magazine): `x` is where its top meets the
    /// body, `rake` tips it back (negative forward).
    public struct Hang {
        public var box: Box
        public var x: Float
        public var rake: Float
        public init(_ box: Box, x: Float, rake: Float) { self.box = box; self.x = x; self.rake = rake }
    }

    public enum Rear { case none, sight, hammer }

    public var bodyID: String
    public var bodyName: String
    public var body: Box
    /// Square barrel pushed through the body's front cap: width, length, length inside.
    public var barrel: (W: Float, L: Float, insert: Float)?
    /// Stock behind the body, drooping by `droop` radians.
    public var stock: (box: Box, droop: Float)?
    public var grip: Hang
    public var magazine: Hang?
    /// Scope on top: width (square), length, front at `x`.
    public var scope: (W: Float, L: Float, x: Float)?
    public var rear: Rear
    /// Slide serrations (pistols), cylinder flutes (revolver) or pump grooves (shotgun).
    public var bodyGrooves: String?
    public var barrelGrooves: Bool

    static func of(_ kind: GunKind) -> GunSpec {
        let slide = ("slide", "Slide"), receiver = ("receiver", "Receiver")
        switch kind {
        case .pistol:
            return GunSpec(slide, Box(1.3, 1.35, 7.6), grip: Hang(Box(1.25, 1.55, 4.4), x: 7.6 - 2.05, rake: radians(15)),
                           rear: .sight, bodyGrooves: "Add the slide serrations")
        case .compact:
            return GunSpec(slide, Box(1.25, 1.25, 6.0), grip: Hang(Box(1.2, 1.45, 3.4), x: 6.0 - 2.0, rake: radians(12)),
                           rear: .sight, bodyGrooves: "Add the slide serrations")
        case .targetPistol:
            return GunSpec(slide, Box(1.1, 1.25, 9.6), grip: Hang(Box(1.1, 1.35, 4.6), x: 9.6 - 2.1, rake: radians(15)),
                           rear: .sight, bodyGrooves: "Add the slide serrations")
        case .machinePistol:
            return GunSpec(slide, Box(1.3, 1.4, 8.2), grip: Hang(Box(1.2, 1.5, 4.0), x: 8.2 - 2.0, rake: radians(16)),
                           magazine: Hang(Box(1.0, 1.2, 3.6), x: 0.8, rake: radians(-4)),
                           rear: .sight, bodyGrooves: "Add the slide serrations")
        case .revolver:
            return GunSpec(("frame", "Frame"), Box(1.7, 1.6, 4.4), barrel: (0.62, 6.0, 1.7),
                           grip: Hang(Box(1.2, 1.25, 3.8), x: 2.5, rake: radians(20)),
                           rear: .hammer, bodyGrooves: "Flute the cylinder")
        case .rifle:
            return GunSpec(receiver, Box(1.5, 1.7, 7.2), barrel: (0.62, 9.0, 2.4), stock: (Box(1.35, 2.3, 5.2), radians(6)),
                           grip: Hang(Box(1.15, 1.45, 3.6), x: 7.2 - 2.5, rake: radians(16)),
                           magazine: Hang(Box(1.0, 1.35, 3.1), x: 0.9, rake: radians(-10)), scope: (0.75, 4.4, 1.6), rear: .none)
        case .carbine:
            return GunSpec(receiver, Box(1.4, 1.6, 6.6), barrel: (0.58, 6.6, 2.2), stock: (Box(1.3, 2.0, 4.4), radians(5)),
                           grip: Hang(Box(1.1, 1.4, 3.4), x: 6.6 - 2.2, rake: radians(18)),
                           magazine: Hang(Box(0.95, 1.3, 3.4), x: 0.5, rake: radians(-20)), rear: .sight)
        case .smg:
            return GunSpec(receiver, Box(1.4, 1.6, 6.0), barrel: (0.55, 4.6, 2.0), stock: (Box(1.1, 1.5, 3.0), radians(3)),
                           grip: Hang(Box(1.1, 1.4, 3.3), x: 6.0 - 2.0, rake: radians(14)),
                           magazine: Hang(Box(0.9, 1.1, 4.6), x: 0.4, rake: radians(-3)), rear: .sight)
        case .shotgun:
            return GunSpec(receiver, Box(1.7, 1.6, 6.4), barrel: (0.82, 10.0, 2.2), stock: (Box(1.35, 2.4, 5.6), radians(7)),
                           grip: Hang(Box(1.15, 1.45, 3.4), x: 6.4 - 2.2, rake: radians(18)), rear: .none, barrelGrooves: true)
        case .sniper:
            return GunSpec(receiver, Box(1.4, 1.6, 7.8), barrel: (0.58, 11.0, 2.6), stock: (Box(1.3, 2.4, 6.4), radians(5)),
                           grip: Hang(Box(1.1, 1.45, 3.5), x: 7.8 - 2.3, rake: radians(18)),
                           magazine: Hang(Box(0.95, 1.1, 2.2), x: 1.4, rake: 0), scope: (0.95, 6.2, 1.0), rear: .none)
        }
    }

    init(_ body: (String, String), _ box: Box, barrel: (W: Float, L: Float, insert: Float)? = nil,
         stock: (box: Box, droop: Float)? = nil, grip: Hang, magazine: Hang? = nil, scope: (W: Float, L: Float, x: Float)? = nil,
         rear: Rear, bodyGrooves: String? = nil, barrelGrooves: Bool = false) {
        bodyID = body.0
        bodyName = body.1
        self.body = box
        self.barrel = barrel
        self.stock = stock
        self.grip = grip
        self.magazine = magazine
        self.scope = scope
        self.rear = rear
        self.bodyGrooves = bodyGrooves
        self.barrelGrooves = barrelGrooves
    }
}

/// One part of a cardboard gun: a folded box or a fin on a glue tab, and where it sits
/// on the finished gun (in the body box's frame).
public struct GunPart {
    public enum Shape {
        case box(W: Float, H: Float, L: Float, caps: BoxNet.Caps)
        /// Fin outline in body-x / fin-v coordinates, finger holes, tab span along u.
        case fin(outline: [V2], holes: [[V2]], tab: (Float, Float))
    }

    public var id: String
    public var name: String
    public var shape: Shape
    /// Assembled pose of the piece frame in the body frame.
    public var mount: Pose
    /// Body-frame offset the part waits at before it slides home.
    public var approach: V3

    public var isBox: Bool { if case .box = shape { return true } else { return false } }

    public var boxSize: (W: Float, H: Float, L: Float, front: Bool)? {
        if case let .box(W, H, L, caps) = shape { return (W, H, L, caps.front) }
        return nil
    }

    public var tabSpan: (Float, Float)? {
        if case let .fin(_, _, tab) = shape { return tab }
        return nil
    }
}

/// A marker line drawn on the finished gun.
public struct GunDetail {
    public var name: String
    public var path: SurfacePath
}

/// A gun: boxes and fins cut from one sheet. The first part is the body (slide, frame
/// or receiver) that everything else is glued to. All sizes derive from the board
/// thickness so the parts meet flush.
public struct GunBlueprint {
    public let kind: GunKind
    public let t: Float
    public let parts: [GunPart]
    public let template: CraftTemplate
    /// Marker details drawn in the final stage (outside faces, flat frames).
    public let details: [GunDetail]

    public var name: String { kind.title }
    public var body: GunPart { parts[0] }

    public init(kind: GunKind, thickness t: Float) {
        self.kind = kind
        self.t = t
        let (parts, details) = GunBlueprint.build(kind.spec, t)
        self.parts = parts
        self.details = details
        let pieces = parts.map { part -> PieceDef in
            let panels: [PanelDef]
            switch part.shape {
            case let .box(W, H, L, caps): panels = BoxNet.box(W: W, H: H, L: L, t: t, caps: caps)
            case let .fin(outline, holes, tab): panels = BoxNet.fin(outline: outline, holes: holes, tab: tab.0, tab.1)
            }
            return PieceDef(id: part.id, name: part.name, placement: V2(0, 0), panels: panels)
        }
        let (packed, sheet) = WeaponBlueprint.pack(pieces)
        template = CraftTemplate(sheetSize: sheet, thickness: t, pieces: packed)
    }

    public func part(_ id: String) -> GunPart? { parts.first { $0.id == id } }
    public func piece(_ id: String) -> PieceDef? { template.piece(id) }

    /// Where a part waits, lined up next to its spot, before sliding home.
    public func ready(_ id: String) -> Pose {
        guard let p = part(id) else { return .identity }
        return Pose.translation(p.approach) * p.mount
    }

    /// Every hinge folded.
    public func finishedAngles(_ id: String) -> [String: Float] {
        guard let p = piece(id) else { return [:] }
        var a: [String: Float] = [:]
        for panel in p.panels { if let h = panel.hinge { a[panel.id] = h.signedTarget } }
        return a
    }

    public func assembledPose(_ id: String) -> Pose { part(id)?.mount ?? .identity }

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

    /// Glue for a part before assembly: the box's tucked tab, or the fin's tab.
    public func glue(_ id: String) -> SurfacePath? {
        guard let p = part(id) else { return nil }
        switch p.shape {
        case let .box(W, H, L, _): return BoxNet.tabGlue(piece: id, W: W, H: H, L: L, t: t)
        case let .fin(_, _, tab): return BoxNet.finGlue(piece: id, u0: tab.0, u1: tab.1, t: t)
        }
    }

    // MARK: Layout helpers

    /// A box hanging under the body at `x`, raked back by `angle` (negative rakes it
    /// forward). Its open end tucks up into the body; its end cap is the base.
    static func hangingBox(x: Float, angle a: Float, H: Float, t: Float) -> Pose {
        let rot = Quat(axis: V3(0, 0, 1), angle: a - .pi / 2)
        // Raise the front so the higher corner of the slanted top meets the body bottom.
        let lift = max(0, -(H + 2 * t) * sin(a))
        return Pose(rot: rot, pos: V3(x, lift, 0))
    }

    /// Ejection port: a rectangle on the outside of the box's +z wall.
    static func port(_ id: String, u0: Float, u1: Float, h0: Float, h1: Float, W: Float) -> SurfacePath {
        let pts = [(u0, h0), (u1, h0), (u1, h1), (u0, h1), (u0, h0)].map { BoxNet.onSideWall(u: $0.0, h: $0.1, W: W) }
        return SurfacePath(piece: id, panel: "HS2", points: pts, normal: V3(0, -1, 0))
    }

    /// Zigzag grip texture / serrations on the outside of the box's +z wall.
    static func zigzag(_ id: String, u0: Float, u1: Float, h0: Float, h1: Float, step: Float, W: Float) -> SurfacePath {
        var pts: [V3] = []
        var u = u0
        var low = true
        while u <= u1 + 1e-3 {
            pts.append(BoxNet.onSideWall(u: u, h: low ? h0 : h1, W: W))
            low.toggle()
            u += step
        }
        return SurfacePath(piece: id, panel: "HS2", points: pts, normal: V3(0, -1, 0))
    }

    /// Trigger guard: a loop hanging below the body with the trigger inside, its back
    /// edge raked to meet a grip at `gripX` with rake `a`.
    static func guardFin(gripX gx: Float, angle a: Float) -> GunPart.Shape {
        let h: Float = 1.25
        let back = gx + 0.15
        let outline = [V2(gx - 2.0, 0), V2(back, 0), V2(back + h * tan(a), -h), V2(gx - 1.5, -h), V2(gx - 2.0, -0.8)]
        let x0 = gx - 1.72, x1 = gx - 0.12
        let hole = [V2(x0, -0.25), V2(gx - 1.05, -0.25), V2(gx - 1.0, -0.62), V2(gx - 0.84, -0.86), V2(gx - 0.68, -0.8),
                    V2(gx - 0.8, -0.6), V2(gx - 0.8, -0.25), V2(x1, -0.25), V2(x1, -0.98), V2(x0 + 0.3, -0.98), V2(x0, -0.72)]
        return .fin(outline: outline, holes: [hole], tab: (gx - 1.8, gx - 0.15))
    }

    // MARK: Build

    static func build(_ g: GunSpec, _ t: Float) -> ([GunPart], [GunDetail]) {
        let b = g.body
        let top = b.H + 2 * t
        let id = g.bodyID
        // The barrel needs a square slot; otherwise the body's front cap is the muzzle.
        let caps = g.barrel.map { BoxNet.Caps(front: true, frontSlot: $0.W / 2 + 0.25) } ?? BoxNet.Caps(front: true, frontHole: 0.3)
        var parts = [GunPart(id: id, name: g.bodyName, shape: .box(W: b.W, H: b.H, L: b.L, caps: caps), mount: .identity,
                             approach: V3(0, 0, 0))]
        var details: [GunDetail] = []
        var frontSightAt: (x: Float, y: Float) = (0, top)

        if let barrel = g.barrel {
            // Centred in the body's front slot, its back end `insert` inside.
            let y = (b.H - barrel.W) / 2
            let front = barrel.insert - barrel.L - 2 * t
            parts.append(GunPart(id: "barrel", name: "Barrel",
                                 shape: .box(W: barrel.W, H: barrel.W, L: barrel.L, caps: BoxNet.Caps(front: true, frontHole: barrel.W * 0.29)),
                                 mount: Pose.translation(V3(barrel.insert - (barrel.L + t), y, 0)), approach: V3(-2.6, 0, 0)))
            frontSightAt = (front, y + barrel.W + 2 * t)
            if g.barrelGrooves {
                let outside = barrel.L - barrel.insert
                details.append(GunDetail(name: "Groove the pump", path: zigzag("barrel", u0: outside - 4.2, u1: outside - 1.0, h0: 0.12,
                                                                               h1: barrel.W - t - 0.12, step: 0.3, W: barrel.W)))
            }
        }
        if let stock = g.stock {
            // Its front cap against the body's end cap, drooping a little.
            let s = stock.box
            let pivotLocal = V3(-t, s.H + 2 * t, 0)
            let pivotBody = V3(b.L + t, top, 0)
            let mount = Pose.translation(pivotBody) * Pose(rot: Quat(axis: V3(0, 0, 1), angle: -stock.droop)) * Pose.translation(pivotLocal * -1)
            parts.append(GunPart(id: "stock", name: "Stock", shape: .box(W: s.W, H: s.H, L: s.L, caps: BoxNet.Caps(front: true)),
                                 mount: mount, approach: V3(1.8, 0, 0)))
        }
        let grip = g.grip
        parts.append(GunPart(id: "grip", name: "Grip", shape: .box(W: grip.box.W, H: grip.box.H, L: grip.box.L, caps: BoxNet.Caps()),
                             mount: hangingBox(x: grip.x, angle: grip.rake, H: grip.box.H, t: t), approach: V3(0.4, -1.4, 0)))
        if let mag = g.magazine {
            parts.append(GunPart(id: "magazine", name: "Magazine", shape: .box(W: mag.box.W, H: mag.box.H, L: mag.box.L, caps: BoxNet.Caps()),
                                 mount: hangingBox(x: mag.x, angle: mag.rake, H: mag.box.H, t: t), approach: V3(-0.3, -1.4, 0)))
        }
        parts.append(GunPart(id: "guard", name: "Trigger guard", shape: guardFin(gripX: grip.x, angle: grip.rake),
                             mount: BoxNet.finBelow(surfaceY: 0, t: t), approach: V3(0, -1.2, 0)))
        if let scope = g.scope {
            parts.append(GunPart(id: "scope", name: "Scope", shape: .box(W: scope.W, H: scope.W, L: scope.L, caps: BoxNet.Caps(front: true, frontHole: scope.W * 0.3)),
                                 mount: Pose.translation(V3(scope.x, top, 0)), approach: V3(0, 1.2, 0)))
        }
        switch g.rear {
        case .none:
            break
        case .sight:
            // Notched blade near the back of a slide, near the front of a receiver.
            let x0 = g.barrel == nil ? b.L - 1.1 : 0.3, x1 = x0 + 0.9
            parts.append(GunPart(id: "rearSight", name: "Rear sight",
                                 shape: .fin(outline: [V2(x0, 0), V2(x1, 0), V2(x1, -0.45), V2(x1 - 0.3, -0.45), V2(x1 - 0.38, -0.24),
                                                       V2(x1 - 0.52, -0.24), V2(x1 - 0.6, -0.45), V2(x0, -0.45)],
                                             holes: [], tab: (x0 + 0.1, x1 - 0.1)),
                                 mount: BoxNet.finAbove(surfaceY: top, t: t), approach: V3(0, 1.1, 0)))
        case .hammer:
            // A spur curling up and back over the end of the frame.
            let e = b.L
            parts.append(GunPart(id: "hammer", name: "Hammer",
                                 shape: .fin(outline: [V2(e - 1.0, 0), V2(e - 0.1, 0), V2(e + 0.3, -0.5), V2(e + 0.45, -0.85), V2(e + 0.15, -0.95),
                                                       V2(e - 0.15, -0.6), V2(e - 0.6, -0.42), V2(e - 1.0, -0.3)],
                                             holes: [], tab: (e - 0.9, e - 0.2)),
                                 mount: BoxNet.finAbove(surfaceY: top, t: t), approach: V3(0, 1.1, 0)))
        }
        // Front sight: on the muzzle end of the barrel, or of the slide.
        let fx = g.barrel == nil ? Float(0) : frontSightAt.x
        parts.append(GunPart(id: "frontSight", name: "Front sight",
                             shape: .fin(outline: [V2(fx + 0.4, 0), V2(fx + 1.1, 0), V2(fx + 0.9, -0.4), V2(fx + 0.6, -0.4)],
                                         holes: [], tab: (fx + 0.47, fx + 1.03)),
                             mount: BoxNet.finAbove(surfaceY: frontSightAt.y, t: t), approach: V3(0, 1.1, 0)))

        // Marker details.
        let inner = b.H - t
        if g.rear != .hammer {
            let (u0, u1): (Float, Float) = g.barrel == nil ? (b.L * 0.3, b.L * 0.55) : (b.L * 0.42, b.L * 0.68)
            details.insert(GunDetail(name: "Draw the ejection port", path: port(id, u0: u0, u1: u1, h0: inner * 0.45, h1: inner * 0.85, W: b.W)), at: 0)
        }
        if let name = g.bodyGrooves {
            let (u0, u1, step): (Float, Float, Float) = g.rear == .hammer ? (0.4, b.L - 0.4, 0.4) : (b.L - 1.9, b.L - 0.4, 0.25)
            details.append(GunDetail(name: name, path: zigzag(id, u0: u0, u1: u1, h0: 0.18, h1: inner - 0.18, step: step, W: b.W)))
        }
        if let mag = g.magazine {
            details.append(GunDetail(name: "Ridge the magazine", path: zigzag("magazine", u0: 0.7, u1: mag.box.L - 0.4, h0: 0.2,
                                                                              h1: mag.box.H - t - 0.2, step: 0.4, W: mag.box.W)))
        }
        details.append(GunDetail(name: "Texture the grip", path: zigzag("grip", u0: 0.8, u1: grip.box.L - 0.5, h0: 0.22,
                                                                        h1: grip.box.H - t - 0.22, step: 0.45, W: grip.box.W)))
        return (parts, details)
    }
}
