import Foundation

/// Polygon triangulation with holes — a Swift port of mapbox/earcut (ISC license)
/// without the z-order hashing (our polygons are small). Nodes live in an array and
/// link by index, so there are no reference cycles.
public enum Earcut {
    /// - Parameters:
    ///   - outer: outer ring (any winding, not closed)
    ///   - holes: hole rings (any winding, not closed)
    /// - Returns: triangle vertex indices into `outer + holes.flatMap { $0 }`.
    public static func triangulate(outer: [V2], holes: [[V2]] = []) -> [Int] {
        var coords: [Double] = []
        var holeStarts: [Int] = []
        for p in outer { coords.append(Double(p.x)); coords.append(Double(p.y)) }
        var count = outer.count
        for h in holes {
            holeStarts.append(count)
            for p in h { coords.append(Double(p.x)); coords.append(Double(p.y)) }
            count += h.count
        }
        var e = Solver(coords: coords)
        return e.run(holeStarts: holeStarts)
    }

    private struct Node {
        var i: Int
        var x: Double
        var y: Double
        var prev: Int = -1
        var next: Int = -1
        var steiner = false
    }

    private struct Solver {
        let coords: [Double]
        var n: [Node] = []
        var triangles: [Int] = []

        init(coords: [Double]) { self.coords = coords }

        mutating func run(holeStarts: [Int]) -> [Int] {
            let vertexCount = coords.count / 2
            let outerEnd = holeStarts.first ?? vertexCount
            guard var outer = linkedList(start: 0, end: outerEnd, clockwise: true) else { return [] }
            if n[outer].next == n[outer].prev { return [] }
            if !holeStarts.isEmpty {
                outer = eliminateHoles(holeStarts: holeStarts, outer: outer, vertexCount: vertexCount)
            }
            earcutLinked(outer, pass: 0)
            return triangles
        }

        // MARK: Linked list

        mutating func insertNode(_ i: Int, _ last: Int?) -> Int {
            let idx = n.count
            n.append(Node(i: i, x: coords[i * 2], y: coords[i * 2 + 1]))
            if let last {
                let lastNext = n[last].next
                n[idx].next = lastNext
                n[idx].prev = last
                n[lastNext].prev = idx
                n[last].next = idx
            } else {
                n[idx].prev = idx
                n[idx].next = idx
            }
            return idx
        }

        mutating func removeNode(_ p: Int) {
            let pn = n[p].next, pp = n[p].prev
            n[pn].prev = pp
            n[pp].next = pn
        }

        func signedArea(start: Int, end: Int) -> Double {
            var sum = 0.0
            var j = end - 1
            for i in start..<end {
                sum += (coords[j * 2] - coords[i * 2]) * (coords[i * 2 + 1] + coords[j * 2 + 1])
                j = i
            }
            return sum
        }

        mutating func linkedList(start: Int, end: Int, clockwise: Bool) -> Int? {
            guard end > start else { return nil }
            var last: Int? = nil
            if clockwise == (signedArea(start: start, end: end) > 0) {
                for i in start..<end { last = insertNode(i, last) }
            } else {
                for i in stride(from: end - 1, through: start, by: -1) { last = insertNode(i, last) }
            }
            if let l = last, equals(l, n[l].next) {
                removeNode(l)
                last = n[l].next
            }
            return last
        }

        // MARK: Geometry predicates

        func area(_ p: Int, _ q: Int, _ r: Int) -> Double {
            (n[q].y - n[p].y) * (n[r].x - n[q].x) - (n[q].x - n[p].x) * (n[r].y - n[q].y)
        }

        func equals(_ a: Int, _ b: Int) -> Bool { n[a].x == n[b].x && n[a].y == n[b].y }

        func pointInTriangle(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                             _ cx: Double, _ cy: Double, _ px: Double, _ py: Double) -> Bool {
            (cx - px) * (ay - py) >= (ax - px) * (cy - py) &&
                (ax - px) * (by - py) >= (bx - px) * (ay - py) &&
                (bx - px) * (cy - py) >= (cx - px) * (by - py)
        }

        func sign(_ v: Double) -> Int { v > 0 ? 1 : (v < 0 ? -1 : 0) }

        func onSegment(_ p: Int, _ q: Int, _ r: Int) -> Bool {
            n[q].x <= max(n[p].x, n[r].x) && n[q].x >= min(n[p].x, n[r].x) &&
                n[q].y <= max(n[p].y, n[r].y) && n[q].y >= min(n[p].y, n[r].y)
        }

        func intersects(_ p1: Int, _ q1: Int, _ p2: Int, _ q2: Int) -> Bool {
            let o1 = sign(area(p1, q1, p2))
            let o2 = sign(area(p1, q1, q2))
            let o3 = sign(area(p2, q2, p1))
            let o4 = sign(area(p2, q2, q1))
            if o1 != o2 && o3 != o4 { return true }
            if o1 == 0 && onSegment(p1, p2, q1) { return true }
            if o2 == 0 && onSegment(p1, q2, q1) { return true }
            if o3 == 0 && onSegment(p2, p1, q2) { return true }
            if o4 == 0 && onSegment(p2, q1, q2) { return true }
            return false
        }

        func intersectsPolygon(_ a: Int, _ b: Int) -> Bool {
            var p = a
            repeat {
                let pn = n[p].next
                if n[p].i != n[a].i && n[pn].i != n[a].i && n[p].i != n[b].i && n[pn].i != n[b].i &&
                    intersects(p, pn, a, b) { return true }
                p = pn
            } while p != a
            return false
        }

        func locallyInside(_ a: Int, _ b: Int) -> Bool {
            let ap = n[a].prev, an = n[a].next
            return area(ap, a, an) < 0
                ? area(a, b, an) >= 0 && area(a, ap, b) >= 0
                : area(a, b, ap) < 0 || area(a, an, b) < 0
        }

        func middleInside(_ a: Int, _ b: Int) -> Bool {
            var p = a
            var inside = false
            let px = (n[a].x + n[b].x) / 2, py = (n[a].y + n[b].y) / 2
            repeat {
                let pn = n[p].next
                if (n[p].y > py) != (n[pn].y > py) && n[pn].y != n[p].y &&
                    px < (n[pn].x - n[p].x) * (py - n[p].y) / (n[pn].y - n[p].y) + n[p].x {
                    inside.toggle()
                }
                p = pn
            } while p != a
            return inside
        }

        func isValidDiagonal(_ a: Int, _ b: Int) -> Bool {
            let an = n[a].next, ap = n[a].prev, bn = n[b].next, bp = n[b].prev
            if n[an].i == n[b].i || n[ap].i == n[b].i || intersectsPolygon(a, b) { return false }
            let visible = locallyInside(a, b) && locallyInside(b, a) && middleInside(a, b) &&
                (area(ap, a, bp) != 0 || area(a, bp, b) != 0)
            let zeroLength = equals(a, b) && area(ap, a, an) > 0 && area(bp, b, bn) > 0
            return visible || zeroLength
        }

        func sectorContainsSector(_ m: Int, _ p: Int) -> Bool {
            area(n[m].prev, m, n[p].prev) < 0 && area(n[p].next, m, n[m].next) < 0
        }

        // MARK: Ear slicing

        mutating func filterPoints(_ start: Int, _ endIn: Int? = nil) -> Int {
            var end = endIn ?? start
            var p = start
            var again: Bool
            repeat {
                again = false
                let pn = n[p].next, pp = n[p].prev
                if !n[p].steiner && (equals(p, pn) || area(pp, p, pn) == 0) {
                    removeNode(p)
                    p = pp
                    end = pp
                    if p == n[p].next { break }
                    again = true
                } else {
                    p = pn
                }
            } while again || p != end
            return end
        }

        func isEar(_ ear: Int) -> Bool {
            let a = n[ear].prev, b = ear, c = n[ear].next
            if area(a, b, c) >= 0 { return false }
            var p = n[c].next
            while p != a {
                if pointInTriangle(n[a].x, n[a].y, n[b].x, n[b].y, n[c].x, n[c].y, n[p].x, n[p].y) &&
                    area(n[p].prev, p, n[p].next) >= 0 { return false }
                p = n[p].next
            }
            return true
        }

        mutating func earcutLinked(_ start: Int, pass: Int) {
            var ear = start
            var stop = ear
            var guardCount = 0
            while n[ear].prev != n[ear].next {
                guardCount += 1
                if guardCount > 200_000 { return }
                let prev = n[ear].prev, next = n[ear].next
                if isEar(ear) {
                    triangles.append(n[prev].i)
                    triangles.append(n[ear].i)
                    triangles.append(n[next].i)
                    removeNode(ear)
                    ear = n[next].next
                    stop = n[next].next
                    continue
                }
                ear = next
                if ear == stop {
                    if pass == 0 {
                        earcutLinked(filterPoints(ear), pass: 1)
                    } else if pass == 1 {
                        let cured = cureLocalIntersections(filterPoints(ear))
                        earcutLinked(cured, pass: 2)
                    } else if pass == 2 {
                        splitEarcut(ear)
                    }
                    break
                }
            }
        }

        mutating func cureLocalIntersections(_ startIn: Int) -> Int {
            var start = startIn
            var p = start
            repeat {
                let a = n[p].prev, b = n[n[p].next].next
                if !equals(a, b) && intersects(a, p, n[p].next, b) && locallyInside(a, b) && locallyInside(b, a) {
                    triangles.append(n[a].i)
                    triangles.append(n[p].i)
                    triangles.append(n[b].i)
                    let pn = n[p].next
                    removeNode(p)
                    removeNode(pn)
                    p = b
                    start = b
                }
                p = n[p].next
            } while p != start
            return filterPoints(p)
        }

        mutating func splitEarcut(_ start: Int) {
            var a = start
            repeat {
                var b = n[n[a].next].next
                while b != n[a].prev {
                    if n[a].i != n[b].i && isValidDiagonal(a, b) {
                        var c = splitPolygon(a, b)
                        let a2 = filterPoints(a, n[a].next)
                        c = filterPoints(c, n[c].next)
                        earcutLinked(a2, pass: 0)
                        earcutLinked(c, pass: 0)
                        return
                    }
                    b = n[b].next
                }
                a = n[a].next
            } while a != start
        }

        // MARK: Holes

        mutating func eliminateHoles(holeStarts: [Int], outer: Int, vertexCount: Int) -> Int {
            var queue: [Int] = []
            for (k, s) in holeStarts.enumerated() {
                let e = k < holeStarts.count - 1 ? holeStarts[k + 1] : vertexCount
                guard let list = linkedList(start: s, end: e, clockwise: false) else { continue }
                if list == n[list].next { n[list].steiner = true }
                queue.append(getLeftmost(list))
            }
            queue.sort { n[$0].x < n[$1].x }
            var outerNode = outer
            for h in queue { outerNode = eliminateHole(h, outerNode) }
            return outerNode
        }

        mutating func eliminateHole(_ hole: Int, _ outer: Int) -> Int {
            guard let bridge = findHoleBridge(hole, outer) else { return outer }
            let bridgeReverse = splitPolygon(bridge, hole)
            _ = filterPoints(bridgeReverse, n[bridgeReverse].next)
            return filterPoints(bridge, n[bridge].next)
        }

        func findHoleBridge(_ hole: Int, _ outer: Int) -> Int? {
            var p = outer
            let hx = n[hole].x, hy = n[hole].y
            var qx = -Double.infinity
            var m: Int? = nil
            repeat {
                let pn = n[p].next
                if hy <= n[p].y && hy >= n[pn].y && n[pn].y != n[p].y {
                    let x = n[p].x + (hy - n[p].y) * (n[pn].x - n[p].x) / (n[pn].y - n[p].y)
                    if x <= hx && x > qx {
                        qx = x
                        m = n[p].x < n[pn].x ? p : pn
                        if x == hx { return m }
                    }
                }
                p = pn
            } while p != outer
            guard var best = m else { return nil }
            let stop = best
            let mx = n[best].x, my = n[best].y
            var tanMin = Double.infinity
            p = best
            repeat {
                if hx >= n[p].x && n[p].x >= mx && hx != n[p].x &&
                    pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, n[p].x, n[p].y) {
                    let tanV = abs(hy - n[p].y) / (hx - n[p].x)
                    if locallyInside(p, hole) &&
                        (tanV < tanMin || (tanV == tanMin && (n[p].x > n[best].x || (n[p].x == n[best].x && sectorContainsSector(best, p))))) {
                        best = p
                        tanMin = tanV
                    }
                }
                p = n[p].next
            } while p != stop
            return best
        }

        func getLeftmost(_ start: Int) -> Int {
            var p = start, leftmost = start
            repeat {
                if n[p].x < n[leftmost].x || (n[p].x == n[leftmost].x && n[p].y < n[leftmost].y) { leftmost = p }
                p = n[p].next
            } while p != start
            return leftmost
        }

        mutating func splitPolygon(_ a: Int, _ b: Int) -> Int {
            let a2 = n.count
            n.append(Node(i: n[a].i, x: n[a].x, y: n[a].y))
            let b2 = n.count
            n.append(Node(i: n[b].i, x: n[b].x, y: n[b].y))
            let an = n[a].next, bp = n[b].prev
            n[a].next = b
            n[b].prev = a
            n[a2].next = an
            n[an].prev = a2
            n[b2].next = a2
            n[a2].prev = b2
            n[bp].next = b2
            n[b2].prev = bp
            return b2
        }
    }
}
