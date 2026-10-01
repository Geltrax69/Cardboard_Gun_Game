import Foundation

public enum GunKind: String, Codable, CaseIterable {
    case pistol, rifle

    public var title: String { self == .pistol ? "Pistol" : "Rifle" }
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

/// Pistol and rifle: boxes and fins cut from one sheet. The first part is the body
/// (slide / receiver) that everything else is glued to. All sizes derive from the board
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
        let (parts, details) = kind == .pistol ? GunBlueprint.pistol(t) : GunBlueprint.rifle(t)
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

    // MARK: Pistol

    static func pistol(_ t: Float) -> ([GunPart], [GunDetail]) {
        let sW: Float = 1.3, sH: Float = 1.35, sL: Float = 7.6
        let gW: Float = 1.25, gH: Float = 1.55, gL: Float = 4.4
        let a = radians(15)
        let gx = sL - 2.05
        let top = sH + 2 * t
        let parts = [
            GunPart(id: "slide", name: "Slide", shape: .box(W: sW, H: sH, L: sL, caps: BoxNet.Caps(front: true, frontHole: 0.3)),
                    mount: .identity, approach: V3(0, 0, 0)),
            GunPart(id: "grip", name: "Grip", shape: .box(W: gW, H: gH, L: gL, caps: BoxNet.Caps()),
                    mount: hangingBox(x: gx, angle: a, H: gH, t: t), approach: V3(0.4, -1.4, 0)),
            GunPart(id: "guard", name: "Trigger guard", shape: guardFin(gripX: gx, angle: a),
                    mount: BoxNet.finBelow(surfaceY: 0, t: t), approach: V3(0, -1.2, 0)),
            GunPart(id: "rearSight", name: "Rear sight",
                    shape: .fin(outline: [V2(sL - 1.1, 0), V2(sL - 0.2, 0), V2(sL - 0.2, -0.45), V2(sL - 0.5, -0.45), V2(sL - 0.58, -0.24),
                                          V2(sL - 0.72, -0.24), V2(sL - 0.8, -0.45), V2(sL - 1.1, -0.45)],
                                holes: [], tab: (sL - 1.0, sL - 0.3)),
                    mount: BoxNet.finAbove(surfaceY: top, t: t), approach: V3(0, 1.1, 0)),
            GunPart(id: "frontSight", name: "Front sight",
                    shape: .fin(outline: [V2(0.25, 0), V2(1.0, 0), V2(0.8, -0.38), V2(0.45, -0.38)], holes: [], tab: (0.32, 0.93)),
                    mount: BoxNet.finAbove(surfaceY: top, t: t), approach: V3(0, 1.1, 0)),
        ]
        let details = [
            GunDetail(name: "Draw the ejection port", path: port("slide", u0: sL * 0.3, u1: sL * 0.55, h0: (sH - t) * 0.42, h1: (sH - t) * 0.86, W: sW)),
            GunDetail(name: "Add the slide serrations", path: zigzag("slide", u0: sL - 1.9, u1: sL - 0.4, h0: 0.18, h1: sH - t - 0.18, step: 0.25, W: sW)),
            GunDetail(name: "Texture the grip", path: zigzag("grip", u0: 0.9, u1: gL - 0.5, h0: 0.25, h1: gH - t - 0.25, step: 0.45, W: gW)),
        ]
        return (parts, details)
    }

    // MARK: Rifle

    static func rifle(_ t: Float) -> ([GunPart], [GunDetail]) {
        let rW: Float = 1.5, rH: Float = 1.7, rL: Float = 7.2
        let bW: Float = 0.62, bL: Float = 9.0
        let insert: Float = 2.4
        let sW: Float = 1.35, sH: Float = 2.3, sL: Float = 5.2
        let gW: Float = 1.15, gH: Float = 1.45, gL: Float = 3.6
        let mW: Float = 1.0, mH: Float = 1.35, mL: Float = 3.1
        let cW: Float = 0.75, cL: Float = 4.4
        let ga = radians(16), ma = radians(-10)
        let gx = rL - 2.5
        let top = rH + 2 * t

        // Barrel: centred in the receiver's front slot, its back end `insert` inside.
        let barrelY = (rH - bW) / 2
        let barrel = Pose.translation(V3(insert - (bL + t), barrelY, 0))
        let barrelFront = insert - bL - 2 * t
        // Stock: its front cap against the receiver's end cap, drooping a little.
        let pivotLocal = V3(-t, sH + 2 * t, 0)
        let pivotBody = V3(rL + t, top, 0)
        let stock = Pose.translation(pivotBody) * Pose(rot: Quat(axis: V3(0, 0, 1), angle: -radians(6))) * Pose.translation(pivotLocal * -1)

        let parts = [
            GunPart(id: "receiver", name: "Receiver",
                    shape: .box(W: rW, H: rH, L: rL, caps: BoxNet.Caps(front: true, frontSlot: 0.56)),
                    mount: .identity, approach: V3(0, 0, 0)),
            GunPart(id: "barrel", name: "Barrel", shape: .box(W: bW, H: bW, L: bL, caps: BoxNet.Caps(front: true, frontHole: 0.18)),
                    mount: barrel, approach: V3(-2.6, 0, 0)),
            GunPart(id: "stock", name: "Stock", shape: .box(W: sW, H: sH, L: sL, caps: BoxNet.Caps(front: true)),
                    mount: stock, approach: V3(1.8, 0, 0)),
            GunPart(id: "grip", name: "Grip", shape: .box(W: gW, H: gH, L: gL, caps: BoxNet.Caps()),
                    mount: hangingBox(x: gx, angle: ga, H: gH, t: t), approach: V3(0.4, -1.4, 0)),
            GunPart(id: "magazine", name: "Magazine", shape: .box(W: mW, H: mH, L: mL, caps: BoxNet.Caps()),
                    mount: hangingBox(x: 0.9, angle: ma, H: mH, t: t), approach: V3(-0.3, -1.4, 0)),
            GunPart(id: "guard", name: "Trigger guard", shape: guardFin(gripX: gx, angle: ga),
                    mount: BoxNet.finBelow(surfaceY: 0, t: t), approach: V3(0, -1.2, 0)),
            GunPart(id: "scope", name: "Scope", shape: .box(W: cW, H: cW, L: cL, caps: BoxNet.Caps(front: true, frontHole: 0.22)),
                    mount: Pose.translation(V3(1.6, top, 0)), approach: V3(0, 1.2, 0)),
            GunPart(id: "frontSight", name: "Front sight",
                    shape: .fin(outline: [V2(barrelFront + 0.4, 0), V2(barrelFront + 1.1, 0), V2(barrelFront + 0.9, -0.42),
                                          V2(barrelFront + 0.6, -0.42)], holes: [], tab: (barrelFront + 0.47, barrelFront + 1.03)),
                    mount: BoxNet.finAbove(surfaceY: barrelY + bW + 2 * t, t: t), approach: V3(0, 1.1, 0)),
        ]
        let details = [
            GunDetail(name: "Draw the ejection port", path: port("receiver", u0: rL * 0.42, u1: rL * 0.68, h0: (rH - t) * 0.45, h1: (rH - t) * 0.85, W: rW)),
            GunDetail(name: "Ridge the magazine", path: zigzag("magazine", u0: 0.7, u1: mL - 0.4, h0: 0.2, h1: mH - t - 0.2, step: 0.4, W: mW)),
            GunDetail(name: "Texture the grip", path: zigzag("grip", u0: 0.8, u1: gL - 0.5, h0: 0.22, h1: gH - t - 0.22, step: 0.45, W: gW)),
        ]
        return (parts, details)
    }
}
