import Foundation

/// Kinematics of a folding piece. Every panel is a rigid slab of cardboard from y = 0
/// (underside) to y = thickness (printed face). A valley fold hinges about the top
/// surface, a mountain fold about the underside — exactly like a real sheet, so the
/// folded panels meet flush instead of intersecting.
public struct FoldRig {
    public let piece: PieceDef
    public let thickness: Float
    /// Signed fold angle per panel id, relative to its parent (radians, + = valley).
    public var angles: [String: Float] = [:]
    private let order: [Int]

    public init(piece: PieceDef, thickness: Float) {
        self.piece = piece
        self.thickness = thickness
        self.order = piece.topologicalOrder
    }

    public static func hingePose(_ h: HingeDef, childCentroid: V2, angle: Float, thickness: Float) -> Pose {
        // Folding up hinges about the top face, folding down about the underside (the
        // hinge kind only matters at angle 0, where there is no rotation anyway).
        let y: Float = angle > 0 ? thickness : (angle < 0 ? 0 : (h.kind == .valley ? thickness : 0))
        let d = (h.b - h.a).unit
        var n = d.perp
        if (childCentroid - h.a).dotp(n) < 0 { n = n * -1 }
        let axis = V3(n.x, 0, n.y).crossp(up3)
        return Pose.rotation(about: h.a.onMat(y), axis: axis, angle: angle)
    }

    /// Transform of each panel from flat piece space into folded piece space.
    public func poses() -> [String: Pose] {
        var out: [String: Pose] = [:]
        for i in order {
            let p = piece.panels[i]
            guard let parent = p.parent, let h = p.hinge else {
                out[p.id] = .identity
                continue
            }
            let parentPose = out[parent] ?? .identity
            let a = angles[p.id] ?? 0
            out[p.id] = parentPose * FoldRig.hingePose(h, childCentroid: p.centroid, angle: a, thickness: thickness)
        }
        return out
    }

    public func pose(of id: String) -> Pose { poses()[id] ?? .identity }

    public mutating func setFolded(_ ids: [String], progress: Float = 1) {
        for id in ids {
            guard let h = piece.panel(id)?.hinge else { continue }
            angles[id] = h.signedTarget * progress
        }
    }

    public mutating func foldAll(progress: Float = 1) {
        setFolded(piece.panels.map { $0.id }, progress: progress)
    }

    public func progress(of id: String) -> Float {
        guard let h = piece.panel(id)?.hinge, h.target > 0 else { return 0 }
        return (angles[id] ?? 0) / h.signedTarget
    }

    /// Every vertex of the folded piece (top and bottom of each panel) in piece space.
    public func foldedCorners() -> [V3] {
        let ps = poses()
        var pts: [V3] = []
        for p in piece.panels {
            let pose = ps[p.id] ?? .identity
            for q in p.outline {
                pts.append(pose.apply(q.onMat(0)))
                pts.append(pose.apply(q.onMat(thickness)))
            }
        }
        return pts
    }

    /// Axis-aligned bounds of the folded piece in piece space.
    public func foldedBounds() -> (min: V3, max: V3) {
        var lo = V3(repeating: .greatestFiniteMagnitude), hi = V3(repeating: -.greatestFiniteMagnitude)
        for p in foldedCorners() {
            lo = V3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = V3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        return (lo, hi)
    }
}
