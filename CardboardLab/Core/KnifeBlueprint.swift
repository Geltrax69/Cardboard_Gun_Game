import Foundation

/// The cardboard knife: three pieces cut from one sheet.
///
///  • Blade  — a dagger outline with a centre crease. A shallow mountain fold turns it
///             into a ridged blade; its narrow tang slides into the handle.
///  • Handle — a box net: bottom, two walls, a lid, an end cap and a glue tab.
///  • Guard  — a strip that wraps around the front of the handle and glues onto itself.
///
/// All sizes derive from the cardboard thickness so folded panels meet flush.
public struct KnifeBlueprint {
    public let t: Float

    // Handle (inner dimensions).
    public let W: Float = 1.3
    public let H: Float = 1.0
    public let L: Float = 4.4
    public let tab: Float = 0.45
    // Blade.
    public let halfWidth: Float = 1.0
    public let tipX: Float = -6.4
    public let shoulderX: Float = -4.2
    public let tangHalf: Float = 0.5
    public let tangLength: Float = 3.3
    public let ridgeAngle: Float = radians(20)
    // Guard band.
    public let bandWidth: Float = 0.8
    public let bandInset: Float = 0.12

    public let template: CraftTemplate

    public var outerWidth: Float { W + 2 * t }
    public var outerHeight: Float { H + 2 * t }

    public init(thickness: Float) {
        let t = thickness
        self.t = t
        let W: Float = 1.3, H: Float = 1.0, L: Float = 4.4, g: Float = 0.45
        let H2 = H - t

        // --- Handle -----------------------------------------------------------
        let lanyardU = L - 0.62
        let hb = PanelDef("HB", Poly.rect(0, -W / 2, L, W / 2),
                          holes: [Poly.circle(center: V2(lanyardU, 0), radius: 0.2, sides: 8, phase: .pi / 8)])
        let hs1 = PanelDef("HS1", Poly.rect(0, -W / 2 - H, L, -W / 2), parent: "HB",
                           hinge: HingeDef(V2(0, -W / 2), V2(L, -W / 2)))
        let ht = PanelDef("HT", Poly.rect(0, -W / 2 - H - (W + t), L + t, -W / 2 - H),
                          holes: [Poly.circle(center: V2(lanyardU, -W - H), radius: 0.2, sides: 8, phase: .pi / 8)],
                          parent: "HS1", hinge: HingeDef(V2(0, -W / 2 - H), V2(L, -W / 2 - H)))
        let hs2 = PanelDef("HS2", Poly.rect(0, W / 2, L, W / 2 + H2), parent: "HB",
                           hinge: HingeDef(V2(0, W / 2), V2(L, W / 2)))
        let gt = PanelDef("GT", [V2(0.12, W / 2 + H2), V2(L - 0.12, W / 2 + H2), V2(L - 0.42, W / 2 + H2 + g), V2(0.42, W / 2 + H2 + g)],
                          parent: "HS2", hinge: HingeDef(V2(0.12, W / 2 + H2), V2(L - 0.12, W / 2 + H2)), role: .glueTab)
        let ec = PanelDef("EC", [V2(L, -W / 2), V2(L + H, -W / 2 + 0.1), V2(L + H, W / 2 - 0.1), V2(L, W / 2)],
                          parent: "HB", hinge: HingeDef(V2(L, -W / 2), V2(L, W / 2)))

        // --- Blade --------------------------------------------------------------
        let tip = V2(-6.4, 0), sh: Float = -4.2, hw: Float = 1.0, th: Float = 0.5, tl: Float = 3.3
        let upper = PanelDef("BU", [tip, V2(sh, -hw), V2(0, -hw), V2(0, -th), V2(tl, -th), V2(tl, 0)])
        let lower = PanelDef("BL", [tip, V2(tl, 0), V2(tl, th), V2(0, th), V2(0, hw), V2(sh, hw)],
                             parent: "BU", hinge: HingeDef(tip, V2(tl, 0), .mountain, degrees: 40))

        // --- Guard band ------------------------------------------------------------
        let wo = W + 2 * t, ho = H + 2 * t, bw: Float = 0.8
        let c1 = wo, c2 = wo + ho, c3 = 2 * wo + ho, c4 = 2 * wo + 2 * ho + t
        let band = [
            PanelDef("C0", Poly.rect(0, 0, c1, bw)),
            PanelDef("C1", Poly.rect(c1, 0, c2, bw), parent: "C0", hinge: HingeDef(V2(c1, 0), V2(c1, bw), .mountain)),
            PanelDef("C2", Poly.rect(c2, 0, c3, bw), parent: "C1", hinge: HingeDef(V2(c2, 0), V2(c2, bw), .mountain)),
            PanelDef("C3", Poly.rect(c3, 0, c4, bw), parent: "C2", hinge: HingeDef(V2(c3, 0), V2(c3, bw), .mountain)),
            PanelDef("C4", [V2(c4, 0), V2(c4 + 0.45, 0.12), V2(c4 + 0.45, bw - 0.12), V2(c4, bw)],
                     parent: "C3", hinge: HingeDef(V2(c4, 0), V2(c4, bw), .mountain), role: .glueTab),
        ]

        template = CraftTemplate(
            sheetSize: V2(15.2, 10),
            thickness: t,
            pieces: [
                PieceDef(id: "blade", name: "Blade", placement: V2(1.45, -3.1), panels: [upper, lower]),
                PieceDef(id: "handle", name: "Handle", placement: V2(-6.6, 1.75), panels: [hb, hs1, ht, hs2, gt, ec]),
                PieceDef(id: "guard", name: "Guard band", placement: V2(0.3, 1.9), panels: band),
            ]
        )
    }

    public var blade: PieceDef { template.piece("blade")! }
    public var handle: PieceDef { template.piece("handle")! }
    public var guardBand: PieceDef { template.piece("guard")! }

    public static func sheetPose(_ piece: PieceDef) -> Pose {
        .translation(piece.placement.onMat(0))
    }

    // MARK: Blade ridge

    /// Extra transform of the blade's root half while the ridge is folded by `p` ∈ [0, 1]:
    /// the root tilts about the crease and lifts so both outer edges stay on the mat.
    public func bladeRootPose(_ p: Float) -> Pose {
        let a = ridgeAngle * p
        return Pose.translation(V3(0, halfWidth * sin(a), 0)) * Pose(rot: Quat(axis: V3(1, 0, 0), angle: -a))
    }

    public func bladeAngles(_ p: Float) -> [String: Float] { ["BL": -2 * ridgeAngle * p] }

    // MARK: Assembly frames (relative to the handle piece frame)

    /// Blade seated in the handle: tang centred in the cavity.
    public var bladeSeated: Pose {
        let lift = halfWidth * sin(ridgeAngle)
        let tangLow = (halfWidth - tangHalf) * sin(ridgeAngle)
        let tangHigh = lift + t * cos(ridgeAngle)
        let dy = (t + H / 2) - (tangLow + tangHigh) / 2
        return Pose.translation(V3(0, dy, 0)) * bladeRootPose(1)
    }

    /// Blade lined up in front of the handle, ready to slide in.
    public var bladeReady: Pose {
        Pose.translation(V3(-(tangLength + 0.6), 0, 0)) * bladeSeated
    }

    /// Guard band root panel lying across the top of the handle's front end.
    public var guardOnHandle: Pose {
        let origin = V3(bandInset + bandWidth, H + 2 * t, -W / 2 - t)
        return Pose.translation(origin) * Pose(rot: Quat(axis: V3(0, 1, 0), angle: -.pi / 2))
    }

    // MARK: Glue paths (piece space, on the surface that faces up when glued)

    /// Along the handle's glue tab, on its underside (which faces up once tucked in).
    public var handleGluePath: [V3] {
        let v = W / 2 + (H - t) + tab * 0.45
        return [V3(0.55, -0.012, v), V3(L - 0.55, -0.012, v)]
    }

    /// Along the tang, on the printed face of the blade.
    public var tangGluePath: [V3] {
        [V3(0.35, t + 0.012, -tangHalf * 0.5), V3(tangLength - 0.35, t + 0.012, -tangHalf * 0.5)]
    }

    /// Across the end of the guard band where its tab lands.
    public var guardGluePath: [V3] {
        [V3(0.22, t + 0.012, 0.16), V3(0.22, t + 0.012, bandWidth - 0.16)]
    }
}
