import Foundation

// Free mode workshop: cutting shapes out of sheets, creasing and folding pieces, colours.

func runWorkshopTests() {
    var state = WorkshopState()
    let sheetID = state.makeID("sheet")
    state.sheets.append(FreeSheet(id: sheetID, size: Workshop.sheetSize, center: V3(0, 0, 0)))

    // Hand-drawn wobbly circle → clean low-poly loop.
    let wobbly = (0..<120).map { i -> V2 in
        let a = Float(i) / 120 * 2 * .pi
        return V2(cos(a), sin(a)) * (2 + 0.03 * sin(a * 17))
    }
    let clean = Workshop.cleanStroke(wobbly)
    check(clean.count >= 6 && clean.count <= 40, "stroke simplified to \(clean.count) points")
    check(Poly.signedArea(clean) > 0 && Poly.isSimple(clean), "clean stroke is a CCW simple loop")
    check(abs(abs(Poly.signedArea(clean)) - .pi * 4) < 1.2, "clean stroke keeps its area \(Poly.signedArea(clean))")

    // Cut problems.
    check(Workshop.checkCut([V2(0, 0), V2(0.2, 0), V2(0, 0.2)], in: state.sheets[0]) == .tooSmall, "too small")
    check(Workshop.checkCut([V2(0, 0), V2(4, 4), V2(4, 0), V2(0, 1)], in: state.sheets[0]) == .crossesItself, "bow tie")
    check(Workshop.checkCut(Poly.rect(5, 2, 8, 4), in: state.sheets[0]) == .offSheet, "off sheet")

    // Cut a rectangle: hole in the sheet, piece where it was.
    let rect = Poly.rect(-5, -3, 1, 1)
    guard let pid = Workshop.cut(rect, from: sheetID, in: &state) else { check(false, "cut failed"); return }
    check(state.sheets[0].holes.count == 1 && state.pieces.count == 1, "cut adds hole + piece")
    check(Workshop.checkCut(Poly.rect(0, 0, 3, 3), in: state.sheets[0]) == .overlapsHole, "overlapping hole")
    check(Workshop.checkCut(Poly.rect(2, -3, 5, 1), in: state.sheets[0]) == nil, "beside the hole is fine")
    let piece0 = state.piece(pid)!
    let world = piece0.panels[0].outline.map { state.worldPose(pid).apply($0.onMat(0)).xz }
    check(world.allSatisfy { p in rect.contains { $0.dist(p) < 1e-3 } }, "piece sits in its hole")

    // Crease across the piece (local x −3…3): two panels sharing the crease; the
    // bigger side (x > −1) stays put, the flap is x < −1.
    var piece = piece0
    let r1 = Workshop.addCrease(&piece, panel: "P0", V2(-1, -5), V2(-1, 5))
    guard case let .success(flap) = r1 else { check(false, "crease failed \(r1)"); return }
    check(piece.panels.count == 2, "two panels")
    let base = piece.panel("P0")!, f = piece.panel(flap)!
    check(abs(Poly.signedArea(base.outline)) >= abs(Poly.signedArea(f.outline)), "bigger side is the base")
    check(abs(abs(Poly.signedArea(base.outline)) + abs(Poly.signedArea(f.outline)) - 24) < 1e-3, "area kept")
    let def = piece.pieceDef
    check(abs(abs(Poly.signedArea(def.outline)) - 24) < 1e-2, "union outline intact")
    // Second crease on the flap, parallel: nests under the flap.
    var nested = piece
    let r2 = Workshop.addCrease(&nested, panel: flap, V2(-2, -5), V2(-2, 5))
    if case let .success(f2) = r2 {
        check(nested.panel(f2)!.parent == flap, "nested flap")
    } else { check(false, "second crease failed \(r2)") }
    // A crease on the base that would cut through the first crease is refused.
    let bad = Workshop.addCrease(&piece, panel: "P0", V2(-3, -2.5), V2(1, 2))
    check(bad == .failure(.crossesCrease) || bad == .failure(.missesPanel), "crease through a crease refused \(bad)")
    // A crease on the base parallel to the first one moves nothing it shouldn't.
    var p3 = piece
    if case let .success(f3) = Workshop.addCrease(&p3, panel: "P0", V2(1.5, -5), V2(1.5, 5)) {
        let base3 = p3.panel("P0")!
        // The existing flap stays attached to whichever side holds its crease.
        let parentOfFlap = p3.panel(flap)!.parent!
        let holder = p3.panel(parentOfFlap)!
        check(Poly.onBoundary(holder.outline, p3.panel(flap)!.hingeA!), "flap re-parented to the side holding its crease")
        check(base3.id == "P0" && p3.panel(f3) != nil, "base keeps its id")
    } else { check(false, "parallel base crease failed") }

    // Folding both ways keeps the flap attached along the crease, top face or underside.
    for angle: Float in [radians(90), radians(-90), radians(180), radians(-135)] {
        var fp = piece
        fp.panels[fp.panelIndex(flap)!].angle = angle
        var rig = FoldRig(piece: fp.pieceDef, thickness: 0.14)
        rig.angles = fp.angles
        let h = fp.panel(flap)!
        let pivotY: Float = angle > 0 ? 0.14 : 0
        for e in [h.hingeA!, h.hingeB!] {
            let q = rig.pose(of: flap).apply(e.onMat(pivotY))
            check(q.dist(e.onMat(pivotY)) < 1e-3, "crease stays put at \(angle)")
        }
        let c = rig.pose(of: flap).apply(Poly.centroid(h.outline).onMat(0.07))
        // At ±180° the flap lies flat on (or under) the base.
        let lift: Float = abs(angle) > radians(170) ? 0.1 : 0.5
        check(angle > 0 ? c.y > lift : c.y < -lift, "flap goes \(angle > 0 ? "up" : "down") (\(c.y))")
    }
    check(abs(Workshop.snapAngle(radians(87)) - radians(90)) < 1e-4 && abs(Workshop.snapAngle(radians(82)) - radians(82)) < 1e-4,
          "angle snapping")

    // Splitting concave shapes: an L split across both arms is refused (3 pieces).
    let L: [V2] = [V2(0, 0), V2(4, 0), V2(4, 1), V2(1, 1), V2(1, 4), V2(0, 4)]
    check(Poly.splitByLine(L, V2(-1, 0.5), V2(5, 0.5)) != nil, "L split along one arm")
    check(Poly.splitByLine(L, V2(-1, -1), V2(5, 5)) != nil, "L split diagonally into two")
    check(Poly.splitByLine(L, V2(0.5, -1), V2(0.5, 5)) != nil, "L split along the other arm")
    check(Poly.splitByLine(Poly.rect(0, 0, 1, 1), V2(5, 0), V2(5, 1)) == nil, "line missing the shape")

    // Ray hits on a slab.
    let sq = Poly.rect(-1, -1, 1, 1)
    let down = Poly.raySlab(origin: V3(0.2, 5, 0.3), dir: V3(0, -1, 0), outline: sq, thickness: 0.14)
    check(down != nil && down!.top && abs(down!.distance - (5 - 0.14)) < 1e-4, "ray hits the top face")
    let up = Poly.raySlab(origin: V3(0.2, -5, 0.3), dir: V3(0, 1, 0), outline: sq, thickness: 0.14)
    check(up != nil && !up!.top, "ray from below hits the underside")
    check(Poly.raySlab(origin: V3(3, 5, 0), dir: V3(0, -1, 0), outline: sq, thickness: 0.14) == nil, "ray misses")

    // Colours.
    let red = PaintColor(hue: 0, saturation: 1, brightness: 1)
    check(red == PaintColor(r: 1, g: 0, b: 0), "hsb red")
    let teal = PaintColor(hex: "#0E6762")
    let hsb = teal.hsb
    let back = PaintColor(hue: hsb.h, saturation: hsb.s, brightness: hsb.b)
    check(abs(back.r - teal.r) < 1e-3 && abs(back.g - teal.g) < 1e-3 && abs(back.b - teal.b) < 1e-3, "hsb round trip")

    // Glue chains and saving.
    var s2 = state
    s2.pieces[0] = piece
    let other = s2.makeID("piece")
    s2.pieces.append(FreePiece(id: other, panels: [FreePanel(id: "P0", outline: Poly.rect(-1, -1, 1, 1))],
                               pose: Pose.translation(V3(1, 0.5, 0)), gluedTo: pid))
    check(s2.groupRoot(other) == pid, "glue root")
    check(s2.worldPose(other).pos.dist(state.worldPose(pid).apply(V3(1, 0.5, 0))) < 1e-4, "glued world pose")
    let data = try! JSONEncoder().encode(s2)
    let loaded = try! JSONDecoder().decode(WorkshopState.self, from: data)
    check(loaded == s2, "workshop state round-trips through JSON")

    // New sheets go to free spots.
    let spot = Workshop.freeSheetSpot(state, pieceBounds: [])
    check(spot.xz.len > 5, "second sheet goes beside the first \(spot)")
    // A cross-shaped net creased four times folds into an open box.
    var bench = WorkshopState()
    let sid = bench.makeID("sheet")
    bench.sheets.append(FreeSheet(id: sid, size: Workshop.sheetSize, center: V3(0, 0, 0)))
    let plus: [V2] = [V2(-1, -3), V2(1, -3), V2(1, -1), V2(3, -1), V2(3, 1), V2(1, 1), V2(1, 3), V2(-1, 3),
                      V2(-1, 1), V2(-3, 1), V2(-3, -1), V2(-1, -1)]
    guard let boxID = Workshop.cut(plus, from: sid, in: &bench), var box = bench.piece(boxID) else { check(false, "cut the net"); return }
    var flaps: [String] = []
    for (a, b) in [(V2(1, -5), V2(1, 5)), (V2(-1, -5), V2(-1, 5)), (V2(-5, 1), V2(5, 1)), (V2(-5, -1), V2(5, -1))] {
        // Each crease goes across whichever panel it splits (always the base here).
        if case let .success(f) = Workshop.addCrease(&box, panel: "P0", a, b) { flaps.append(f) } else { check(false, "box crease \(a)") }
    }
    check(flaps.count == 4 && box.panels.count == 5, "four flaps around a base")
    check(abs(abs(Poly.signedArea(box.panel("P0")!.outline)) - 4) < 0.01, "base is the centre square")
    let paints = ["#F46359", "#FADC70", "#97E1BE", "#67C2E2"].map { PaintColor(hex: $0) }
    for (i, f) in flaps.enumerated() {
        let j = box.panelIndex(f)!
        box.panels[j].angle = .pi / 2
        box.panels[j].under = paints[i]
    }
    var boxRig = FoldRig(piece: box.pieceDef, thickness: 0.14)
    boxRig.angles = box.angles
    let bb = boxRig.foldedBounds()
    check(abs(bb.max.y - (2 + 0.14)) < 0.05 && bb.max.x < 1.2 && bb.min.x > -1.2, "flaps stand up into an open box \(bb)")
    bench.pieces[bench.pieceIndex(boxID)!] = box
    exportWorkshop(bench, name: "workshop_box")
    print("workshop: ok")
}

func exportWorkshop(_ s: WorkshopState, name: String) {
    let t: Float = 0.14
    var items: [(MeshData, Pose, [String])] = []
    func hex(_ c: PaintColor?, _ fallback: String) -> String {
        guard let c else { return fallback }
        return String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255))
    }
    for sheet in s.sheets {
        let m = MeshBuilder.cardboard(outline: sheet.outline, holes: sheet.holes, thickness: t)
        items.append((m, Pose.translation(sheet.center + V3(-9, 0, 0)), ["#D69A48", "#E8B062", "#B17330", "#0D2730"]))
    }
    for p in s.pieces {
        let def = p.pieceDef
        var rig = FoldRig(piece: def, thickness: t)
        rig.angles = p.angles
        for panel in p.panels {
            let m = MeshBuilder.cardboard(outline: panel.outline, thickness: t, inkEdges: def.freeEdges(of: panel.id))
            items.append((m, s.worldPose(p.id) * rig.pose(of: panel.id),
                          [hex(panel.top, "#E2A652"), hex(panel.under, "#E8B062"), "#B17330", "#0D2730"]))
        }
    }
    exportScene(name, items)
}
