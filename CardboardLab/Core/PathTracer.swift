import Foundation

/// Follows a finger along a 3D path in screen space. Used for cutting (red lines),
/// scoring (blue lines) and gluing (cyan guides). The tool only moves forward, only
/// as far as `lookahead` per touch sample, and only while the finger stays within
/// `tolerance` points of the path — forgiving but never auto-completing.
public struct PathTracer {
    public let path: Polyline
    public private(set) var progress: Float = 0
    public var lookahead: Float = 2.2
    public var sampleStep: Float = 0.035
    /// Remaining length that is auto-completed so players never chase the last pixel.
    public var finishSlack: Float = 0.12

    public init(path: Polyline, lookahead: Float = 2.2) {
        self.path = path
        self.lookahead = lookahead
    }

    public enum Feed: Equatable {
        case advanced(Float)
        case holding
        case offPath(Float)
    }

    public var fraction: Float { path.length > 0 ? progress / path.length : 1 }
    public var isDone: Bool { progress >= path.length - 1e-4 }
    public var head: V3 { path.point(at: progress) }
    public var tangent: V3 { path.tangent(at: min(progress + 0.01, path.length)) }
    public var segmentIndex: Int { path.segment(at: min(progress + 1e-3, path.length)) }

    /// Closest screen distance from `finger` to the path ahead of the tool.
    public func nearestAhead(finger: V2, project: (V3) -> V2) -> (distance: Float, arc: Float) {
        let start = progress
        let end = min(path.length, progress + lookahead)
        var best = start
        var bestDist = Float.greatestFiniteMagnitude
        var d = start
        while true {
            let s = project(path.point(at: d))
            let dist = s.dist(finger)
            if dist < bestDist {
                bestDist = dist
                best = d
            }
            if d >= end { break }
            d = min(end, d + sampleStep)
        }
        return (bestDist, best)
    }

    @discardableResult
    public mutating func feed(finger: V2, tolerance: Float, project: (V3) -> V2) -> Feed {
        guard !isDone else { return .holding }
        let (dist, arc) = nearestAhead(finger: finger, project: project)
        guard dist <= tolerance else { return .offPath(dist) }
        if arc > progress + 1e-5 {
            let before = progress
            progress = arc
            if path.length - progress < finishSlack { progress = path.length }
            return .advanced(progress - before)
        }
        return .holding
    }

    public mutating func complete() { progress = path.length }
    public mutating func reset() { progress = 0 }
}
