import Foundation

// Linux/macOS test harness for the platform-free core (CardboardLab/Core).
// Run: Tools/run-core-tests.sh

var failures = 0
func check(_ cond: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if !cond {
        failures += 1
        print("FAIL [\(line)]: \(msg)")
    }
}
func near(_ a: Float, _ b: Float, _ eps: Float = 1e-3) -> Bool { abs(a - b) <= eps }

// MARK: Earcut
do {
    let outer = Poly.rect(0, 0, 4, 4)
    let hole = Poly.rect(1, 1, 2, 2)
    let tris = Earcut.triangulate(outer: outer, holes: [hole])
    let pts = outer + hole
    var area: Float = 0
    var i = 0
    while i < tris.count {
        let a = pts[tris[i]], b = pts[tris[i + 1]], c = pts[tris[i + 2]]
        area += abs((b - a).crossp(c - a)) / 2
        i += 3
    }
    check(tris.count / 3 == 8, "square with hole should give 8 triangles, got \(tris.count / 3)")
    check(near(area, 15), "area with hole should be 15, got \(area)")

    let concave: [V2] = [V2(0, 0), V2(4, 0), V2(4, 4), V2(2, 2), V2(0, 4)]
    let t2 = Earcut.triangulate(outer: concave)
    check(t2.count == 9, "concave pentagon should give 3 triangles")
}

// MARK: Knife template (the first campaign weapon)
extension WeaponBlueprint {
    var handle: PieceDef { piece("handle")! }
    var bladePiece: PieceDef { piece("blade")! }
    var guardBand: PieceDef { piece("wrap0")! }
    var guardOnHandle: Pose { wrapMount(0) }
    var halfWidth: Float { design.blade!.width / 2 }
    var handleGluePath: [V3] { handleGlue.points }
}
let bp = WeaponBlueprint(design: .knife, thickness: 0.14)
let t = bp.t
do {
    for piece in bp.template.pieces {
        let panelArea = piece.panels.reduce(Float(0)) { $0 + abs(Poly.signedArea($1.outline)) }
        let outlineArea = abs(Poly.signedArea(piece.outline))
        check(near(panelArea, outlineArea, 1e-2), "\(piece.id): outline area \(outlineArea) != panels \(panelArea)")
        check(Poly.signedArea(piece.outline) > 0, "\(piece.id): outline winding")
        print("\(piece.id): outline \(piece.outline.count) pts, perimeter \(Polyline((piece.outline + [piece.outline[0]]).map { $0.onMat() }).length)")
    }
    // Pieces must lie inside the sheet and not overlap each other.
    let half = bp.template.sheetSize / 2
    var boxes: [(V2, V2)] = []
    for piece in bp.template.pieces {
        let b = piece.sheetBounds
        check(b.min.x > -half.x + 0.3 && b.max.x < half.x - 0.3 && b.min.y > -half.y + 0.3 && b.max.y < half.y - 0.3,
              "\(piece.id) must sit inside the sheet: \(b)")
        for o in boxes {
            let overlap = b.min.x < o.1.x && b.max.x > o.0.x && b.min.y < o.1.y && b.max.y > o.0.y
            check(!overlap, "\(piece.id) overlaps another piece")
        }
        boxes.append((b.min, b.max))
    }
    let freeHB = bp.handle.freeEdges(of: "HB")
    // HB: 4 edges, 3 hinged (HS1, HS2, EC) + 8 hole edges -> 1 + 8 free
    check(freeHB.count == 9, "HB free edges expected 9, got \(freeHB.count)")
}

// MARK: Handle folds into a closed box
do {
    var rig = FoldRig(piece: bp.handle, thickness: t)
    rig.foldAll()
    let ps = rig.poses()
    let b = rig.foldedBounds()
    print("handle folded bounds", b)
    check(near(b.min.y, 0) && near(b.max.y, bp.H + 2 * t), "handle height")
    check(near(b.min.z, -bp.W / 2 - t) && near(b.max.z, bp.W / 2 + t), "handle width \(b.min.z) \(b.max.z)")
    check(near(b.min.x, 0) && near(b.max.x, bp.L + t), "handle length \(b.min.x) \(b.max.x)")
    // Lid underside rests on the glue tab's upper face.
    let ht = ps["HT"]!, gt = ps["GT"]!
    let lidUnder = ht.apply(V3(2, 0, -bp.W / 2 - bp.H - 0.5)).y
    let lidTop = ht.apply(V3(2, t, -bp.W / 2 - bp.H - 0.5)).y
    let tabUpper = gt.apply(V3(2, 0, bp.W / 2 + (bp.H - t) + 0.2)).y
    check(near(min(lidUnder, lidTop), bp.H + t), "lid underside at H+t, got \(min(lidUnder, lidTop))")
    check(near(tabUpper, bp.H + t), "tab upper face at H+t, got \(tabUpper)")
    // Lanyard holes line up.
    let holeTop = ht.apply(V3(bp.L - 0.62, 0, -bp.W - bp.H))
    check(near(holeTop.z, 0, 0.01) && near(holeTop.x, bp.L - 0.62), "lid hole aligns with base hole: \(holeTop)")
    // Glue path ends up facing up on top of the tab.
    let gp = bp.handleGluePath.map { gt.apply($0) }
    check(gp.allSatisfy { $0.y > bp.H + t - 0.02 && $0.y < bp.H + t + 0.05 }, "glue path on tab: \(gp)")
}

// MARK: Guard band wraps the handle
do {
    var rig = FoldRig(piece: bp.guardBand, thickness: t)
    rig.foldAll()
    let b = rig.foldedBounds()
    print("guard folded bounds", b)
    check(near(b.min.x, -t) && near(b.max.x, bp.outerWidth + t), "band width around handle \(b.min.x)..\(b.max.x)")
    check(near(b.min.y, -bp.outerHeight - t) && near(b.max.y, 2 * t), "band height \(b.min.y)..\(b.max.y)")
    // In handle space the band hugs the outside of the box.
    var hr = FoldRig(piece: bp.handle, thickness: t)
    hr.foldAll()
    let hb = hr.foldedBounds()
    let corners = rig.foldedCorners().map { bp.guardOnHandle.apply($0) }
    let lo = corners.reduce(V3(repeating: 99)) { V3(min($0.x, $1.x), min($0.y, $1.y), min($0.z, $1.z)) }
    let hi = corners.reduce(V3(repeating: -99)) { V3(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z)) }
    print("guard on handle", lo, hi)
    check(near(lo.y, hb.min.y - t) && near(hi.y, hb.max.y + 2 * t), "band wraps top and bottom")
    check(near(lo.z, hb.min.z - t) && near(hi.z, hb.max.z + t), "band wraps sides")
    check(lo.x > 0.05 && hi.x < 1.2, "band near the front of the handle \(lo.x)..\(hi.x)")
}

// MARK: Blade ridge
do {
    var rig = FoldRig(piece: bp.bladePiece, thickness: t)
    rig.angles = bp.bladeAngles(1)
    let root = bp.bladeRootPose(1)
    let ps = rig.poses()
    let farUpper = (root * ps["BU"]!).apply(V3(-2, 0, -bp.halfWidth))
    let farLower = (root * ps["BL"]!).apply(V3(-2, 0, bp.halfWidth))
    let ridge = (root * ps["BU"]!).apply(V3(-2, 0, 0))
    check(near(farUpper.y, 0) && near(farLower.y, 0), "blade edges rest on the mat \(farUpper.y) \(farLower.y)")
    check(near(farUpper.z, -farLower.z), "blade symmetric")
    check(ridge.y > 0.3, "ridge lifted \(ridge.y)")
    // Seated tang stays inside the handle cavity.
    let seat = bp.bladeSeated
    var pts: [V3] = []
    for p in bp.bladePiece.panels {
        let pose = seat * rig.pose(of: p.id)
        for q in p.outline where q.x > 0.01 {
            pts.append(pose.apply(q.onMat(0)))
            pts.append(pose.apply(q.onMat(t)))
        }
    }
    let ys = pts.map { $0.y }, zs = pts.map { $0.z }
    print("tang y", ys.min()!, ys.max()!, "z", zs.min()!, zs.max()!)
    check(ys.min()! > t + 0.02 && ys.max()! < bp.H - 0.02, "tang clears floor and glue tab")
    check(zs.min()! > -bp.W / 2 && zs.max()! < bp.W / 2, "tang fits between walls")
}

// MARK: Tracer
do {
    let path = Polyline([V3(0, 0, 0), V3(4, 0, 0), V3(4, 0, 3)])
    var tr = PathTracer(path: path, lookahead: 1.5)
    let project: (V3) -> V2 = { V2($0.x * 50, $0.z * 50) }
    // Jumping far ahead does nothing.
    let r0 = tr.feed(finger: V2(200, 150), tolerance: 30, project: project)
    check(tr.progress == 0, "no skipping ahead: \(r0)")
    // Sweep along.
    var x: Float = 0
    while x <= 200 { tr.feed(finger: V2(x, 3), tolerance: 30, project: project); x += 10 }
    check(tr.progress > 3.9 && tr.progress < 4.2, "followed first edge to the corner: \(tr.progress)")
    var z: Float = 0
    while z <= 150 { tr.feed(finger: V2(203, z), tolerance: 30, project: project); z += 10 }
    check(tr.isDone, "finished the path: \(tr.progress)/\(path.length)")
}

// MARK: Tracer on a tiny closed loop (lanyard hole)
do {
    let ring = Poly.circle(center: V2(0, 0), radius: 0.2, sides: 8)
    let loop = Polyline((ring + [ring[0]]).map { $0.onMat() })
    var tr = PathTracer(path: loop, lookahead: min(2.0, loop.length * 0.4))
    let project: (V3) -> V2 = { V2($0.x * 70, $0.z * 70) }
    // Wiggling around the start (which is also the end) must not finish the loop.
    for a in stride(from: Float(-0.6), through: 0.1, by: 0.05) {
        tr.feed(finger: V2(cos(a), sin(a)) * 14, tolerance: 48, project: project)
    }
    check(!tr.isDone && tr.progress < loop.length * 0.5, "tiny loop not completed by wiggling at the start: \(tr.progress)")
    // Going round does finish it.
    for a in stride(from: Float(0), through: 2 * .pi + 0.2, by: 0.1) {
        tr.feed(finger: V2(cos(a), sin(a)) * 14, tolerance: 48, project: project)
    }
    check(tr.isDone, "tiny loop completed by circling: \(tr.progress)/\(loop.length)")
}

// MARK: Mesh
do {
    let piece = bp.handle
    let p = piece.panel("HB")!
    let m = MeshBuilder.cardboard(outline: p.outline, holes: p.holes, thickness: t, inkEdges: piece.freeEdges(of: "HB"))
    check(!m.parts[0].isEmpty && !m.parts[1].isEmpty && !m.parts[2].isEmpty && !m.parts[3].isEmpty, "all cardboard parts built")
    // Winding matches the stored normal for every triangle.
    var bad = 0
    for part in m.parts {
        var i = 0
        while i < part.count {
            let a = m.positions[Int(part[i])], b = m.positions[Int(part[i + 1])], c = m.positions[Int(part[i + 2])]
            let n = (b - a).crossp(c - a).unit
            if n.dotp(m.normals[Int(part[i])]) < 0.99 { bad += 1 }
            i += 3
        }
    }
    check(bad == 0, "\(bad) triangles with inconsistent winding")
    var bead = MeshData()
    MeshBuilder.sweep([V3(0, 0.05, 0), V3(1, 0.05, 0.1), V3(2, 0.05, 0)], radius: 0.07, sides: 6, flatten: 0.6, into: &bead)
    var badBead = 0
    var bi = 0
    while bi < bead.parts[0].count {
        let a = bead.positions[Int(bead.parts[0][bi])], b = bead.positions[Int(bead.parts[0][bi + 1])], c = bead.positions[Int(bead.parts[0][bi + 2])]
        if (b - a).crossp(c - a).unit.dotp(bead.normals[Int(bead.parts[0][bi])]) < 0.99 { badBead += 1 }
        bi += 3
    }
    check(bead.triangleCount == 2 * 6 * 2 + 12 && badBead == 0, "glue bead sweep: \(bead.triangleCount) tris, \(badBead) bad")
    let lathe = MeshBuilder.lathe([V2(0.5, 0), V2(0.5, 1), V2(0.2, 1.4), V2(0, 1.6)], sides: 8)
    check(lathe.triangleCount > 30, "lathe built")
    let hull = lathe.inflated(by: 0.05)
    check(hull.bounds.max.y > 1.6, "hull inflated")
}

// MARK: Camera
do {
    var cam = OrbitCamera(target: V3(1, 0, -2), distance: 30, polar: 0.6, azimuth: 0.4, fovY: radians(30), viewSize: V2(1180, 820))
    let p = V3(3, 0.5, 1)
    let s = cam.screen(p)
    let hitP = cam.hit(s, planeY: 0.5)!
    check(hitP.dist(p) < 1e-3, "ray/projection round trip \(hitP) vs \(p)")
    check(cam.screen(cam.target).dist(cam.viewSize / 2) < 1e-2, "target projects to centre")
    let q = cam.orientation
    check(q.rotate(V3(0, 0, -1)).dist(cam.forward) < 1e-4, "camera looks down -z")
    check(q.rotate(V3(0, 1, 0)).dist(cam.up) < 1e-4, "camera up")
    cam.polar = 0.001
    check(cam.screen(V3(1, 0, -5)).y < cam.screen(V3(1, 0, 2)).y, "top-down: far side of mat is up on screen")
}

// MARK: Tweener
let tw = Tweener()
var log: [String] = []
let task = Task { @MainActor in
    do {
        try await tw.tween(0.5) { k in log.append(String(format: "%.2f", k)) }
        log.append("done")
        try await tw.wait(10)
        log.append("never")
    } catch is Tweener.Cancelled {
        log.append("cancelled")
    } catch {}
}
for _ in 0..<5 { await Task.yield() }
for _ in 0..<8 { tw.update(0.1); await Task.yield(); await Task.yield() }
tw.cancelAll()
_ = await task.value
check(log.contains("done") && log.last == "cancelled" && !log.contains("never"), "tweener sequencing: \(log)")

// MARK: Export previews for Tools/render_preview.py
func exportScene(_ name: String, _ items: [(MeshData, Pose, [String])]) {
    var tris: [[Any]] = []
    for (mesh, pose, colors) in items {
        for (pi, part) in mesh.parts.enumerated() {
            let color = colors[min(pi, colors.count - 1)]
            if color == "-" { continue }
            var i = 0
            while i < part.count {
                let pts = (0..<3).map { pose.apply(mesh.positions[Int(part[i + $0])]) }
                tris.append([pts.map { [$0.x, $0.y, $0.z] }, color])
                i += 3
            }
        }
    }
    let data = try! JSONSerialization.data(withJSONObject: tris)
    let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
    try! data.write(to: URL(fileURLWithPath: dir + "/" + name + ".json"))
}

func pieceMeshes(_ piece: PieceDef, rig: FoldRig, pose: Pose) -> [(MeshData, Pose, [String])] {
    let ps = rig.poses()
    return piece.panels.map { p in
        let m = MeshBuilder.cardboard(outline: p.outline, holes: p.holes, thickness: t, inkEdges: piece.freeEdges(of: p.id))
        return (m, pose * ps[p.id]!, ["#E2A652", "#E8B062", "#B17330", "#0D2730"])
    }
}

do {
    // Flat sheet layout with cut outlines.
    var items: [(MeshData, Pose, [String])] = []
    var sheet = MeshData()
    let holes = bp.template.pieces.map { Poly.translate($0.outline, $0.placement) }
    let sm = MeshBuilder.cardboard(outline: bp.template.sheetOutline, holes: holes, thickness: t)
    sheet.append(sm)
    items.append((sheet, .identity, ["#D69A48", "#E8B062", "#B17330", "#0D2730"]))
    for piece in bp.template.pieces {
        items += pieceMeshes(piece, rig: FoldRig(piece: piece, thickness: t), pose: WeaponBlueprint.sheetPose(piece))
        var lines = MeshData()
        MeshBuilder.ribbon((piece.outline + [piece.outline[0]]).map { ($0 + piece.placement).onMat(t + 0.01) }, width: 0.08, into: &lines)
        for p in piece.panels {
            if let h = p.hinge {
                MeshBuilder.dashes((h.a + piece.placement).onMat(t + 0.01), (h.b + piece.placement).onMat(t + 0.01), into: &lines)
            }
        }
        items.append((lines, .identity, [piece.id == "blade" ? "#F46359" : "#F46359"]))
        var dash = MeshData()
        for p in piece.panels {
            if let h = p.hinge {
                MeshBuilder.dashes((h.a + piece.placement).onMat(t + 0.02), (h.b + piece.placement).onMat(t + 0.02), into: &dash)
            }
        }
        items.append((dash, .identity, ["#67C2E2"]))
    }
    exportScene("flat", items)

    // Assembled knife.
    var hr = FoldRig(piece: bp.handle, thickness: t)
    hr.foldAll()
    var br = FoldRig(piece: bp.bladePiece, thickness: t)
    br.angles = bp.bladeAngles(1)
    var gr = FoldRig(piece: bp.guardBand, thickness: t)
    gr.foldAll()
    let handlePose = Pose.translation(V3(0, 1.5, 0))
    var knife = pieceMeshes(bp.handle, rig: hr, pose: handlePose)
    knife += pieceMeshes(bp.bladePiece, rig: br, pose: handlePose * bp.bladeSeated)
    knife += pieceMeshes(bp.guardBand, rig: gr, pose: handlePose * bp.guardOnHandle)
    exportScene("knife", knife)

    // Half-folded handle.
    var half = FoldRig(piece: bp.handle, thickness: t)
    half.setFolded(["HS1", "HS2", "EC"], progress: 1)
    half.setFolded(["GT"], progress: 1)
    half.setFolded(["HT"], progress: 0.45)
    exportScene("handle_half", pieceMeshes(bp.handle, rig: half, pose: .identity))

    var gHalf = FoldRig(piece: bp.guardBand, thickness: t)
    gHalf.foldAll(progress: 0.6)
    exportScene("guard_half", pieceMeshes(bp.guardBand, rig: gHalf, pose: .identity))
}

runWeaponTests(outDir: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

if failures == 0 {
    print("All core tests passed")
} else {
    print("\(failures) failure(s)")
    exit(1)
}
