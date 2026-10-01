import Foundation

/// The two folding shapes most builds are made of.
///
/// **Box**: a closed rectangular tube, inner size W × H × L, lying along +x in its piece
/// frame: floor HB (y = 0…t), walls HS1 (−z) and HS2 (+z), lid HT, glue tab GT tucked
/// under the lid, end cap EC at x = L…L+t and an optional front cap FC at x = −t…0. The
/// printed face ends up inside, so the outside of a wall is its underside.
///
/// **Fin**: a flat shape (panel F0, v ≤ 0) standing on a glue tab (panel FT, v ≥ 0) that
/// folds 90° so its printed face lies flat against whatever the fin is glued to.
public enum BoxNet {
    public struct Caps {
        public var front = false
        /// Round hole in the front cap (muzzle, scope lens).
        public var frontHole: Float? = nil
        /// Square hole in the front cap (half size) for a part to slide through.
        public var frontSlot: Float? = nil
        public var lanyard = false

        public init(front: Bool = false, frontHole: Float? = nil, frontSlot: Float? = nil, lanyard: Bool = false) {
            self.front = front
            self.frontHole = frontHole
            self.frontSlot = frontSlot
            self.lanyard = lanyard
        }
    }

    public static let tabDepth: Float = 0.45

    public static func box(W: Float, H: Float, L: Float, t: Float, caps: Caps = Caps()) -> [PanelDef] {
        let g = tabDepth
        let H2 = H - t
        let lanyardU = L - 0.62
        let hbHoles = caps.lanyard ? [Poly.circle(center: V2(lanyardU, 0), radius: 0.2, sides: 8, phase: .pi / 8)] : []
        let htHoles = caps.lanyard ? [Poly.circle(center: V2(lanyardU, -W - H), radius: 0.2, sides: 8, phase: .pi / 8)] : []
        // The lid also covers the thickness of the caps.
        let lidStart: Float = caps.front ? -t : 0
        var panels = [
            PanelDef("HB", Poly.rect(0, -W / 2, L, W / 2), holes: hbHoles),
            PanelDef("HS1", Poly.rect(0, -W / 2 - H, L, -W / 2), parent: "HB", hinge: HingeDef(V2(0, -W / 2), V2(L, -W / 2))),
            PanelDef("HT", Poly.rect(lidStart, -W / 2 - H - (W + t), L + t, -W / 2 - H), holes: htHoles,
                     parent: "HS1", hinge: HingeDef(V2(0, -W / 2 - H), V2(L, -W / 2 - H))),
            PanelDef("HS2", Poly.rect(0, W / 2, L, W / 2 + H2), parent: "HB", hinge: HingeDef(V2(0, W / 2), V2(L, W / 2))),
            PanelDef("GT", [V2(0.12, W / 2 + H2), V2(L - 0.12, W / 2 + H2), V2(L - 0.42, W / 2 + H2 + g), V2(0.42, W / 2 + H2 + g)],
                     parent: "HS2", hinge: HingeDef(V2(0.12, W / 2 + H2), V2(L - 0.12, W / 2 + H2)), role: .glueTab),
            PanelDef("EC", [V2(L, -W / 2), V2(L + H, -W / 2 + 0.1), V2(L + H, W / 2 - 0.1), V2(L, W / 2)],
                     parent: "HB", hinge: HingeDef(V2(L, -W / 2), V2(L, W / 2))),
        ]
        if caps.front {
            var holes: [[V2]] = []
            if let r = caps.frontHole {
                holes.append(Poly.circle(center: V2(-H / 2, 0), radius: r, sides: 10, phase: .pi / 10))
            }
            if let h = caps.frontSlot {
                holes.append(Poly.rect(-H / 2 - h, -h, -H / 2 + h, h))
            }
            panels.append(PanelDef("FC", [V2(0, -W / 2), V2(0, W / 2), V2(-H, W / 2 - 0.1), V2(-H, -W / 2 + 0.1)], holes: holes,
                                   parent: "HB", hinge: HingeDef(V2(0, -W / 2), V2(0, W / 2))))
        }
        return panels
    }

    /// Hinged panels of a box, in the order they are scored.
    public static func creases(front: Bool) -> [String] {
        ["HS1", "HS2", "HT", "GT", "EC"] + (front ? ["FC"] : [])
    }

    /// Walls folded up before the lid closes (the tab GT goes last).
    public static func walls(front: Bool) -> [String] {
        ["HS1", "HS2", "EC"] + (front ? ["FC"] : [])
    }

    /// Glue along the tucked-in tab, on its underside (which faces up once tucked).
    public static func tabGlue(piece: String, W: Float, H: Float, L: Float, t: Float) -> SurfacePath {
        let v = W / 2 + (H - t) + tabDepth * 0.45
        return SurfacePath(piece: piece, panel: "GT", points: [V3(0.55, -0.012, v), V3(L - 0.55, -0.012, v)], normal: V3(0, -1, 0))
    }

    /// Converts a point on the outside of wall HS2 — `u` along the box, `h` up from the
    /// floor — to its flat panel position on the underside.
    public static func onSideWall(u: Float, h: Float, W: Float, lift: Float = 0.006) -> V3 {
        V3(u, -lift, W / 2 + h)
    }

    // MARK: Fins

    /// Fin body `outline` (v ≤ 0, top edge along v = 0) with a glue tab hinged on
    /// u0…u1 of that edge. The tab folds down (mountain) so its printed face is the one
    /// that gets glued.
    public static func fin(outline: [V2], holes: [[V2]] = [], tab u0: Float, _ u1: Float) -> [PanelDef] {
        let d = tabDepth
        let inset = min(0.12, (u1 - u0) * 0.2)
        return [
            PanelDef("F0", outline, holes: holes),
            PanelDef("FT", [V2(u0, 0), V2(u1, 0), V2(u1 - inset, d), V2(u0 + inset, d)],
                     parent: "F0", hinge: HingeDef(V2(u0, 0), V2(u1, 0), .mountain), role: .glueTab),
        ]
    }

    /// Glue across the fin's tab (printed face, applied while flat).
    public static func finGlue(piece: String, u0: Float, u1: Float, t: Float) -> SurfacePath {
        let v = tabDepth * 0.5
        return SurfacePath(piece: piece, panel: "FT", points: [V3(u0 + 0.2, t + 0.012, v), V3(u1 - 0.2, t + 0.012, v)], normal: V3(0, 1, 0))
    }

    /// Fin hanging below a surface at height `y` (its tab glued to the underside), in the
    /// plane z = 0. Fin u runs along +x.
    public static func finBelow(surfaceY y: Float, t: Float) -> Pose {
        Pose(rot: Quat.fromBasis(x: V3(1, 0, 0), y: V3(0, 0, -1), z: V3(0, 1, 0)), pos: V3(0, y - t, t / 2))
    }

    /// Fin standing on a surface at height `y` (its tab glued to the top), in the plane
    /// z = 0. Fin u runs along +x; the fin's v ≤ 0 side points up.
    public static func finAbove(surfaceY y: Float, t: Float) -> Pose {
        Pose(rot: Quat.fromBasis(x: V3(1, 0, 0), y: V3(0, 0, 1), z: V3(0, -1, 0)), pos: V3(0, y + t, -t / 2))
    }
}
