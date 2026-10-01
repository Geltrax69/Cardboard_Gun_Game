import Foundation

// Checks for the parametric weapon generator across every campaign design and a batch
// of random Free Craft designs, on both board thicknesses.

func runWeaponTests(outDir: String) {
    var designs = WeaponDesign.campaign
    // Random Free Craft designs.
    var rng = SystemRandomNumberGenerator()
    for i in 0..<300 {
        let kind = WeaponKind.allCases[i % 4]
        var d = WeaponDesign(id: "free\(i)", name: "Free \(i)", kind: kind, blade: nil, handleLength: Float.random(in: 3...11, using: &rng))
        if kind != .axe {
            let build: BladeBuild = Bool.random(using: &rng) ? .ridge : .laminate
            let tips = TipStyle.allCases.filter { build == .ridge ? $0.forRidge : !$0.forRidge }
            d.blade = BladeSpec(build: build, tip: tips.randomElement(using: &rng)!, edge: Bool.random(using: &rng) ? .serrated : .plain,
                                length: Float.random(in: 3...13, using: &rng), width: Float.random(in: 1...3.5, using: &rng),
                                curve: Float.random(in: 0...1, using: &rng), tangLength: Float.random(in: 2...5, using: &rng),
                                fuller: Bool.random(using: &rng))
            if Bool.random(using: &rng) {
                d.guardClip = ClipSpec([.bar, .flared, .spiked, .disc].randomElement(using: &rng)!,
                                       span: Float.random(in: 0.5...3.5, using: &rng), depth: Float.random(in: 0.2...1.2, using: &rng))
            }
            if Bool.random(using: &rng) {
                d.endClip = ClipSpec([.diamond, .knob, .spike].randomElement(using: &rng)!,
                                     span: Float.random(in: 0.5...2, using: &rng), depth: Float.random(in: 0.3...1.2, using: &rng))
            }
        } else {
            d.endClip = ClipSpec([.bit, .doubleBit, .bearded].randomElement(using: &rng)!,
                                 span: Float.random(in: 1...5, using: &rng), depth: Float.random(in: 1...4, using: &rng))
        }
        d.handleWidth = Float.random(in: 0.8...1.6, using: &rng)
        d.handleHeight = Float.random(in: 0.7...1.3, using: &rng)
        d.lanyardHole = Bool.random(using: &rng)
        d.wraps = (0..<Int.random(in: 0...3, using: &rng)).map { _ in Float.random(in: 0...6, using: &rng) }
        designs.append(d)
    }

    var worstSheet = V2(0, 0)
    for (index, design) in designs.enumerated() {
        for t: Float in [0.14, 0.2] {
            let bp = WeaponBlueprint(design: design, thickness: t)
            let tag = "\(design.id)@\(t)"
            // Pieces: clean outlines that match their panels.
            for piece in bp.template.pieces {
                for p in piece.panels {
                    check(Poly.isSimple(p.outline), "\(tag) \(piece.id).\(p.id) panel self-intersects")
                }
                let panelArea = piece.panels.reduce(Float(0)) { $0 + abs(Poly.signedArea($1.outline)) }
                let outlineArea = abs(Poly.signedArea(piece.outline))
                check(abs(panelArea - outlineArea) < 0.02 * max(1, panelArea), "\(tag) \(piece.id): outline \(outlineArea) vs panels \(panelArea)")
                check(Poly.isSimple(piece.outline), "\(tag) \(piece.id): outline self-intersects")
                let tris = piece.panels.reduce(0) { $0 + Earcut.triangulate(outer: $1.outline, holes: $1.holes).count }
                check(tris > 0, "\(tag) \(piece.id): triangulation failed")
            }
            // Sheet: everything on it, nothing overlapping, fits the mat.
            let half = bp.template.sheetSize / 2
            worstSheet = V2(max(worstSheet.x, bp.template.sheetSize.x), max(worstSheet.y, bp.template.sheetSize.y))
            check(bp.template.sheetSize.x <= 27.5 && bp.template.sheetSize.y <= 20.5,
                  "\(tag): sheet too big \(bp.template.sheetSize) \(bp.template.pieces.map { "\($0.id) \(Poly.bounds($0.outline))" })")
            var boxes: [(V2, V2)] = []
            for piece in bp.template.pieces {
                let b = piece.sheetBounds
                check(b.min.x > -half.x + 0.3 && b.max.x < half.x - 0.3 && b.min.y > -half.y + 0.3 && b.max.y < half.y - 0.3,
                      "\(tag) \(piece.id) off the sheet")
                for o in boxes {
                    check(!(b.min.x < o.1.x && b.max.x > o.0.x && b.min.y < o.1.y && b.max.y > o.0.y), "\(tag) \(piece.id) overlaps")
                }
                boxes.append((b.min, b.max))
            }
            // Handle closes into a box.
            var hr = FoldRig(piece: bp.piece("handle")!, thickness: t)
            hr.foldAll()
            let hb = hr.foldedBounds()
            check(abs(hb.max.y - (bp.H + 2 * t)) < 1e-3 && abs(hb.max.z - (bp.W / 2 + t)) < 1e-3, "\(tag): handle box")
            // Blade: tang inside the cavity, through the guard slot.
            if bp.hasBlade {
                var br = FoldRig(piece: bp.piece("blade")!, thickness: t)
                br.angles = bp.bladeAngles(1)
                var lo = V3(repeating: 99), hi = V3(repeating: -99)
                for p in bp.piece("blade")!.panels {
                    let pose = bp.bladeSeated * br.pose(of: p.id)
                    for q in p.outline where q.x > 0.05 && q.x < (design.blade?.tangLength ?? 0) + 0.01 {
                        for y in [Float(0), t] {
                            let w = pose.apply(q.onMat(y))
                            lo = V3(min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z))
                            hi = V3(max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z))
                        }
                    }
                }
                check(lo.y > t - 1e-3 && hi.y < bp.H + t + 1e-3, "\(tag): tang height \(lo.y)..\(hi.y)")
                check(lo.z > -bp.W / 2 - 1e-3 && hi.z < bp.W / 2 + 1e-3, "\(tag): tang width \(lo.z)..\(hi.z)")
                check(hi.x < bp.L + 1e-3, "\(tag): tang too long \(hi.x) vs \(bp.L)")
                if design.blade?.build == .laminate {
                    // Twin lands exactly on the first layer.
                    let la = br.pose(of: "LA"), lb = br.pose(of: "LB")
                    let a = bp.piece("blade")!.panel("LA")!.outline
                    let b = bp.piece("blade")!.panel("LB")!.outline
                    let aTop = a.map { la.apply($0.onMat(t)) }
                    // A 180° valley fold turns the twin's printed face down onto the first layer.
                    let bBottom = b.map { lb.apply($0.onMat(t)) }
                    check(bBottom.allSatisfy { abs($0.y - t) < 1e-3 }, "\(tag): twin rests on the first layer")
                    check(bBottom.allSatisfy { q in aTop.contains { $0.dist(q) < 2e-3 } }, "\(tag): twin aligned")
                }
                if let guardDef = bp.piece("guard"), let slot = guardDef.panel("B0")?.holes.first {
                    // Slot (bridge flat coords) must contain the tang cross-section.
                    var gr = FoldRig(piece: guardDef, thickness: t)
                    gr.foldAll()
                    let toHandle = bp.guardMount * gr.pose(of: "B0")
                    let pts = slot.map { toHandle.apply($0.onMat(0)) }
                    let sy = pts.map { $0.y }, sz = pts.map { $0.z }
                    check(sy.min()! <= lo.y + 1e-3 && sy.max()! >= hi.y - 1e-3 && sz.min()! <= lo.z + 1e-3 && sz.max()! >= hi.z - 1e-3,
                          "\(tag): tang fits guard slot")
                }
            }
            // Clips hug the handle: top wing on top, bottom wing below, bridge at the end.
            for (id, mount) in [("guard", bp.guardMount), ("end", bp.endMount)] {
                guard let clip = bp.piece(id) else { continue }
                var cr = FoldRig(piece: clip, thickness: t)
                cr.foldAll()
                let top = clip.panel("WB")!.outline.map { (mount * cr.pose(of: "WB")).apply($0.onMat(t)) }
                let under = clip.panel("WA")!.outline.map { (mount * cr.pose(of: "WA")).apply($0.onMat(t)) }
                check(top.allSatisfy { abs($0.y - (bp.H + 2 * t + 0.01)) < 0.02 }, "\(tag) \(id): top wing on the handle \(top.map { $0.y }.min()!)")
                check(under.allSatisfy { abs($0.y + 0.01) < 0.02 }, "\(tag) \(id): bottom wing under the handle")
                let us = top.map { $0.x }
                if id == "guard" {
                    check(us.min()! > -1e-3 && us.max()! < bp.L, "\(tag) guard wings along the handle front \(us.min()!)..\(us.max()!)")
                } else {
                    check(us.max()! < bp.L + t + 1e-3 && us.min()! > 0, "\(tag) end wings along the handle end \(us.min()!)..\(us.max()!)")
                }
            }
            // Bands keep clear of the clips.
            for (i, inset) in bp.design.wraps.enumerated() {
                let front = bp.design.guardClip?.depth ?? 0
                let back = bp.L - (bp.design.endClip?.depth ?? 0)
                check(inset >= front - 1e-3 && inset + bp.bandWidth <= back + t + 0.2, "\(tag) wrap\(i) collides with a clip")
            }
            // Paths stay on their panels.
            for path in bp.sharpenPaths + bp.fullerPaths + [bp.handleGlue] + (bp.bladeGlue.map { [$0] } ?? []) {
                guard let panel = bp.piece(path.piece)?.panel(path.panel) else { check(false, "\(tag) missing panel \(path.panel)"); continue }
                let inside = path.points.filter { Poly.contains(outer: panel.outline, holes: panel.holes, $0.xz) || minEdgeDist(panel.outline, $0.xz) < 0.05 }
                check(inside.count >= path.points.count - 1, "\(tag) path off panel \(path.piece).\(path.panel): \(inside.count)/\(path.points.count)")
            }
            if index < WeaponDesign.campaign.count && t == 0.14 {
                exportWeapon(bp, outDir: outDir)
            }
        }
    }
    print("weapons: \(designs.count) designs checked, largest sheet \(worstSheet)")
}

func minEdgeDist(_ poly: [V2], _ p: V2) -> Float {
    var best = Float.greatestFiniteMagnitude
    for i in 0..<poly.count {
        best = min(best, Poly.closestOnSegment(p, poly[i], poly[(i + 1) % poly.count]).dist)
    }
    return best
}

/// Assembled weapon + flat sheet previews for Tools/render_preview.py.
func exportWeapon(_ bp: WeaponBlueprint, outDir: String) {
    let t = bp.t
    var items: [(MeshData, Pose, [String])] = []
    for p in bp.template.pieces {
        var rig = FoldRig(piece: p, thickness: t)
        rig.angles = bp.finishedAngles(p.id)
        let ps = rig.poses()
        for panel in p.panels {
            let m = MeshBuilder.cardboard(outline: panel.outline, holes: panel.holes, thickness: t, inkEdges: p.freeEdges(of: panel.id))
            items.append((m, bp.assembledPose(p.id) * ps[panel.id]!, ["#E2A652", "#E8B062", "#B17330", "#0D2730"]))
        }
    }
    for path in bp.sharpenPaths {
        guard let p = bp.piece(path.piece) else { continue }
        var rig = FoldRig(piece: p, thickness: t)
        rig.angles = bp.finishedAngles(p.id)
        var m = MeshData()
        MeshBuilder.ribbon(path.points, width: 0.2, normal: path.normal, into: &m)
        items.append((m, bp.assembledPose(p.id) * rig.pose(of: path.panel), ["#F3C274"]))
    }
    exportScene("weapon_\(bp.design.id)", items)

    var flat: [(MeshData, Pose, [String])] = []
    let holes = bp.template.pieces.map { Poly.translate($0.outline, $0.placement) }
    flat.append((MeshBuilder.cardboard(outline: bp.template.sheetOutline, holes: holes, thickness: t), .identity, ["#D69A48", "#E8B062", "#B17330", "#0D2730"]))
    for p in bp.template.pieces {
        for panel in p.panels {
            let m = MeshBuilder.cardboard(outline: panel.outline, holes: panel.holes, thickness: t)
            flat.append((m, WeaponBlueprint.sheetPose(p), ["#E2A652", "#E8B062", "#B17330", "#0D2730"]))
        }
        var lines = MeshData()
        MeshBuilder.ribbon((p.outline + [p.outline[0]]).map { ($0 + p.placement).onMat(t + 0.01) }, width: 0.09, into: &lines)
        flat.append((lines, .identity, ["#F46359"]))
        var dash = MeshData()
        for panel in p.panels {
            if let h = panel.hinge { MeshBuilder.dashes((h.a + p.placement).onMat(t + 0.02), (h.b + p.placement).onMat(t + 0.02), into: &dash) }
        }
        flat.append((dash, .identity, ["#67C2E2"]))
    }
    exportScene("sheet_\(bp.design.id)", flat)
}
