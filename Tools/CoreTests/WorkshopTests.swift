import Foundation

// Free mode workshop: cutting shapes and slices out of any piece, creasing and folding,
// colours, glue, saving.

func runWorkshopTests() {
    let t: Float = 0.14
    func area(_ p: FreePiece) -> Float {
        p.panels.reduce(0) { sum, panel in
            sum + abs(Poly.signedArea(panel.outline)) - panel.holes.reduce(0) { $0 + abs(Poly.signedArea($1)) }
        }
    }
    func worldPoints(_ s: WorkshopState, _ id: String) -> [V3] {
        guard let p = s.piece(id) else { return [] }
        return p.panels.flatMap { panel in panel.outline.map { s.panelWorld(id, panel.id).apply($0.onMat(0)) } }
    }

    var state = WorkshopState()
    let sheet = Workshop.addSheet(size: V2(14, 10), stock: "plain", at: V3(0, 0, 0), in: &state)
    check(state.piece(sheet)?.isSheet == true && state.activeSheet == sheet, "sheet is a piece")

    // Hand-drawn wobbly circle → clean low-poly loop.
    let wobbly = (0..<120).map { i -> V2 in
        let a = Float(i) / 120 * 2 * .pi
        return V2(cos(a), sin(a)) * (2 + 0.03 * sin(a * 17))
    }
    let clean = Workshop.cleanStroke(wobbly)
    check(clean.count >= 6 && clean.count <= 40 && Poly.signedArea(clean) > 0 && Poly.isSimple(clean), "stroke simplified")

    // Punch a rectangle out of the sheet: hole + piece lying exactly in it.
    var s1 = state
    let rect = Poly.rect(-5, -3, 1, 1)
    guard case let .success(cut) = Workshop.cutLoop(rect, piece: sheet, panel: "P0", in: &s1) else { check(false, "punch"); return }
    check(s1.piece(sheet)!.panels[0].holes.count == 1, "sheet has the hole")
    check(worldPoints(s1, cut).allSatisfy { w in rect.contains { $0.dist(w.xz) < 1e-3 } }, "piece sits in its hole")
    check(abs(area(s1.piece(sheet)!) + area(s1.piece(cut)!) - 140) < 1e-2, "area kept")
    var s1b = s1
    check(Workshop.cutLoop(Poly.rect(0, 0, 3, 3), piece: sheet, panel: "P0", in: &s1b) == .failure(.crossesHole), "overlapping hole")
    check(Workshop.cutLoop([V2(0, 0), V2(0.2, 0), V2(0, 0.2)], piece: sheet, panel: "P0", in: &s1b) == .failure(.tooSmall), "too small")
    check(Workshop.cutLoop([V2(2, 0), V2(6, 4), V2(6, 0), V2(2, 1)], piece: sheet, panel: "P0", in: &s1b) == .failure(.crossesItself), "bow tie")

    // A shape over the edge bites that corner off.
    var s2 = state
    let bite = Poly.rect(5, 3, 9, 7)
    guard case let .success(corner) = Workshop.cutLoop(bite, piece: sheet, panel: "P0", in: &s2) else { check(false, "edge bite"); return }
    check(abs(area(s2.piece(corner)!) - 4) < 1e-2 && abs(area(s2.piece(sheet)!) - 136) < 1e-2, "bite takes the 2×2 corner")

    // Slice the sheet in two with a straight line (ends stretched to the edges).
    var s3 = state
    guard case let .success(half) = Workshop.slice([V2(-2, -4.7), V2(-2, 4.7)], piece: sheet, panel: "P0", in: &s3) else {
        check(false, "slice")
        return
    }
    check(abs(area(s3.piece(half)!) + area(s3.piece(sheet)!) - 140) < 1e-2, "slice keeps the area")
    check(abs(area(s3.piece(sheet)!) - 90) < 1e-2, "bigger side stays")
    check(Poly.isSimple(s3.piece(half)!.panels[0].outline), "slice half is clean")
    // A wiggly freehand slice also works.
    var s3b = state
    let wiggle = stride(from: Float(-7.5), through: 7.5, by: 0.5).map { V2($0, 0.6 * sin($0)) }
    if case .success = Workshop.slice(wiggle, piece: sheet, panel: "P0", in: &s3b) {} else { check(false, "wiggly slice") }
    var s3c = state
    check(Workshop.slice([V2(-1, 0), V2(1, 0)], piece: sheet, panel: "P0", in: &s3c) == .failure(.needsEdge), "slice must reach the edges")
    var s3d = s1
    check(Workshop.slice([V2(-3, -6), V2(-3, 6)], piece: sheet, panel: "P0", in: &s3d) == .failure(.crossesHole), "slice through hole refused")

    // Crease the punched piece (local x −3…3) and fold the flap; slicing the flap keeps
    // the cut-off part where it was in 3D.
    var piece = s1.piece(cut)!
    guard case let .success(flap) = Workshop.addCrease(&piece, panel: "P0", V2(-1, -5), V2(-1, 5)) else { check(false, "crease"); return }
    check(piece.panels.count == 2 && abs(Poly.signedArea(piece.panel("P0")!.outline)) > abs(Poly.signedArea(piece.panel(flap)!.outline)),
          "bigger side is the base")
    var s4 = s1
    s4.pieces[s4.pieceIndex(cut)!] = piece
    s4.pieces[s4.pieceIndex(cut)!].panels[1].angle = .pi / 2
    let before = worldPoints(s4, cut)
    guard case let .success(tip) = Workshop.slice([V2(-2, -3), V2(-2, 3)], piece: cut, panel: flap, in: &s4) else {
        check(false, "slice the folded flap")
        return
    }
    let after = worldPoints(s4, cut) + worldPoints(s4, tip)
    check(after.allSatisfy { a in before.contains { $0.dist(a) < 1e-3 } || abs(a.y) > 0.5 }, "sliced flap stays in place")
    check(s4.piece(tip)!.panels.allSatisfy { p in p.outline.allSatisfy { s4.panelWorld(tip, p.id).apply($0.onMat(0)).y > -1e-3 } },
          "cut-off flap part still stands up")
    // Slicing the base across the crease is refused.
    var s5 = s1
    s5.pieces[s5.pieceIndex(cut)!] = piece
    check(Workshop.slice([V2(-4, 0.3), V2(4, 0.3)], piece: cut, panel: "P0", in: &s5) == .failure(.crossesFold),
          "cut through a crease refused")
    // Slicing the base beside the crease takes the flap along with the cut-off part.
    var s6 = s1
    s6.pieces[s6.pieceIndex(cut)!] = piece
    if case let .success(part) = Workshop.slice([V2(0.5, -4), V2(0.5, 4)], piece: cut, panel: "P0", in: &s6) {
        let withFlap = s6.piece(part)!.panels.count == 2 || s6.piece(cut)!.panels.count == 2
        check(withFlap, "flap travels with the side holding its crease")
    } else { check(false, "slice beside the crease") }

    // Creases: holes refuse crossing, snapping straightens and finds corners.
    var holed = s1.piece(sheet)!
    check(Workshop.addCrease(&holed, panel: "P0", V2(-3, -6), V2(-3, 6)) == .failure(.crossesHole), "crease through a hole refused")
    var holed2 = s1.piece(sheet)!
    if case .success = Workshop.addCrease(&holed2, panel: "P0", V2(3, -6), V2(3, 6)) {
        check(holed2.panels.map { $0.holes.count }.reduce(0, +) == 1, "hole goes with its side")
    } else { check(false, "crease beside the hole") }
    let square = Poly.rect(-2, -2, 2, 2)
    let (sa, sb) = Workshop.snapCrease(V2(-3, 0.1), V2(3, -0.25), outline: square)
    check(abs(sa.y - sb.y) < 1e-4, "nearly level crease snaps level")
    let (ca, cb) = Workshop.snapCrease(V2(-1.8, -3), V2(-1.85, 3), outline: square)
    check(abs(ca.x + 2) < 1e-3 && abs(cb.x + 2) < 1e-3, "crease near a corner snaps through it")

    // Valley folds go up, mountain folds down; both stay attached along the crease.
    check(Workshop.snapAngle(radians(-30), kind: .valley) == 0 && Workshop.snapAngle(radians(30), kind: .mountain) == 0, "fold sides")
    check(abs(Workshop.snapAngle(radians(87)) - radians(90)) < 1e-4 && abs(Workshop.snapAngle(radians(82)) - radians(82)) < 1e-4,
          "angle snapping")
    for (kind, angle) in [(FoldKind.valley, radians(90)), (.mountain, radians(-90)), (.valley, radians(180)), (.mountain, radians(-135))] {
        var fp = piece
        let j = fp.panelIndex(flap)!
        fp.panels[j].fold = kind
        fp.panels[j].angle = angle
        let rig = fp.rig()
        let h = fp.panel(flap)!
        let pivotY: Float = angle > 0 ? t : 0
        for e in [h.hingeA!, h.hingeB!] {
            check(rig.pose(of: flap).apply(e.onMat(pivotY)).dist(e.onMat(pivotY)) < 1e-3, "crease stays put at \(angle)")
        }
        check(fp.pieceDef.panel(flap)!.hinge!.kind == kind, "crease kind \(kind)")
    }

    // Ray hits, through holes.
    let sq = Poly.rect(-1, -1, 1, 1)
    check(Poly.raySlab(origin: V3(0.2, 5, 0.3), dir: V3(0, -1, 0), outline: sq, thickness: t)?.top == true, "ray hits the top")
    check(Poly.raySlab(origin: V3(0, 5, 0), dir: V3(0, -1, 0), outline: sq, holes: [Poly.rect(-0.5, -0.5, 0.5, 0.5)], thickness: t) == nil,
          "ray passes through a hole")

    // Colours.
    check(PaintColor(hue: 0, saturation: 1, brightness: 1) == PaintColor(r: 1, g: 0, b: 0), "hsb red")
    let teal = PaintColor(hex: "#0E6762"), back = PaintColor(hue: teal.hsb.h, saturation: teal.hsb.s, brightness: teal.hsb.b)
    check(abs(back.r - teal.r) < 1e-3 && abs(back.g - teal.g) < 1e-3 && abs(back.b - teal.b) < 1e-3, "hsb round trip")

    // Glue chains and saving.
    var s7 = s1
    let other = s7.makeID("piece")
    s7.pieces.append(FreePiece(id: other, panels: [FreePanel(id: "P0", outline: sq)], pose: .translation(V3(1, 0.5, 0)), gluedTo: cut))
    check(s7.groupRoot(other) == cut && s7.worldPose(other).pos.dist(s1.worldPose(cut).apply(V3(1, 0.5, 0))) < 1e-4, "glue")
    let loaded = try! JSONDecoder().decode(WorkshopState.self, from: try! JSONEncoder().encode(s7))
    check(loaded == s7, "workshop state round-trips through JSON")

    // Saves from before sheets were pieces still load.
    let oldJSON = """
    {"sheets":[{"id":"sheet1","size":[14,10],"center":[0,0,0],"holes":[[[-1,-1],[1,-1],[1,1],[-1,1]]]}],
     "pieces":[{"id":"piece2","panels":[{"id":"P0","outline":[[-1,-1],[1,-1],[1,1],[-1,1]],"angle":0}],
                "pose":{"p":[0,0,0],"q":[0,0,0,1]},"nextPanel":1}],
     "activeSheet":"sheet1","counter":2}
    """
    if var old = try? JSONDecoder().decode(WorkshopState.self, from: Data(oldJSON.utf8)) {
        old.migrate(defaultStock: "plain")
        check(old.sheets.isEmpty && old.pieces.count == 2 && old.piece("sheet1")?.panels[0].holes.count == 1, "old sheets migrate")
        check(old.pieces.allSatisfy { $0.stock == "plain" }, "old pieces get a stock")
    } else { check(false, "old save decodes") }

    // A cross-shaped net creased four times folds into an open box.
    var bench = WorkshopState()
    let sid = Workshop.addSheet(size: V2(14, 10), stock: "plain", at: V3(0, 0, 0), in: &bench)
    let plus: [V2] = [V2(-1, -3), V2(1, -3), V2(1, -1), V2(3, -1), V2(3, 1), V2(1, 1), V2(1, 3), V2(-1, 3),
                      V2(-1, 1), V2(-3, 1), V2(-3, -1), V2(-1, -1)]
    guard case let .success(boxID) = Workshop.cutLoop(plus, piece: sid, panel: "P0", in: &bench), var box = bench.piece(boxID) else {
        check(false, "cut the net")
        return
    }
    var flaps: [String] = []
    for (a, b) in [(V2(1, -5), V2(1, 5)), (V2(-1, -5), V2(-1, 5)), (V2(-5, 1), V2(5, 1)), (V2(-5, -1), V2(5, -1))] {
        if case let .success(f) = Workshop.addCrease(&box, panel: "P0", a, b) { flaps.append(f) } else { check(false, "box crease \(a)") }
    }
    check(flaps.count == 4 && abs(abs(Poly.signedArea(box.panel("P0")!.outline)) - 4) < 0.01, "four flaps around the centre")
    let paints = ["#F46359", "#FADC70", "#97E1BE", "#67C2E2"].map { PaintColor(hex: $0) }
    for (i, f) in flaps.enumerated() {
        let j = box.panelIndex(f)!
        box.panels[j].angle = .pi / 2
        box.panels[j].under = paints[i]
    }
    let bb = box.rig().foldedBounds()
    check(abs(bb.max.y - (2 + t)) < 0.05 && bb.max.x < 1.2 && bb.min.x > -1.2, "flaps stand up into an open box \(bb)")
    bench.pieces[bench.pieceIndex(boxID)!] = box
    // Slice what's left of the sheet so the export shows a sliced sheet too.
    _ = Workshop.slice([V2(4, -6), V2(4.5, 6)], piece: sid, panel: "P0", in: &bench)
    exportWorkshop(bench, name: "workshop_box")

    let spot = Workshop.freeSpot(size: V2(14, 10), occupied: [(V2(-7, -5), V2(7, 5))])
    check(spot.xz.len > 5, "new sheets go beside the first \(spot)")
    print("workshop: ok")
}

func exportWorkshop(_ s: WorkshopState, name: String) {
    var items: [(MeshData, Pose, [String])] = []
    func hex(_ c: PaintColor?, _ fallback: String) -> String {
        guard let c else { return fallback }
        return String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255))
    }
    for (k, p) in s.pieces.enumerated() {
        let def = p.pieceDef
        let rig = p.rig()
        // Spread the pieces a little so they read apart in the preview.
        let spread = Pose.translation(V3(Float(k) * 1.2, 0, 0))
        for panel in p.panels {
            let m = MeshBuilder.cardboard(outline: panel.outline, holes: panel.holes, thickness: p.thickness, inkEdges: def.freeEdges(of: panel.id))
            items.append((m, spread * s.worldPose(p.id) * rig.pose(of: panel.id),
                          [hex(panel.top, p.isSheet ? "#D69A48" : "#E2A652"), hex(panel.under, "#E8B062"), "#B17330", "#0D2730"]))
        }
    }
    exportScene(name, items)
}
