import Foundation

// Checks for the pistol and rifle blueprints on both board thicknesses.

func runGunTests(outDir: String) {
    for kind in GunKind.allCases {
        for t: Float in [0.14, 0.2] {
            let bp = GunBlueprint(kind: kind, thickness: t)
            let tag = "\(kind.rawValue)@\(t)"
            // Pieces: clean outlines, holes inside their panels.
            for piece in bp.template.pieces {
                for p in piece.panels {
                    check(Poly.isSimple(p.outline), "\(tag) \(piece.id).\(p.id) panel self-intersects")
                    for hole in p.holes {
                        check(Poly.isSimple(hole), "\(tag) \(piece.id).\(p.id) hole self-intersects")
                        check(hole.allSatisfy { Poly.contains(p.outline, $0) && minEdgeDist(p.outline, $0) > 0.05 },
                              "\(tag) \(piece.id).\(p.id) hole too close to the edge")
                    }
                    check(Earcut.triangulate(outer: p.outline, holes: p.holes).count > 0, "\(tag) \(piece.id).\(p.id) triangulates")
                }
                let panelArea = piece.panels.reduce(Float(0)) { $0 + abs(Poly.signedArea($1.outline)) }
                check(abs(panelArea - abs(Poly.signedArea(piece.outline))) < 0.02 * max(1, panelArea), "\(tag) \(piece.id) outline area")
                check(Poly.isSimple(piece.outline), "\(tag) \(piece.id) outline self-intersects")
            }
            // Sheet fits the mat, pieces don't overlap.
            let half = bp.template.sheetSize / 2
            check(bp.template.sheetSize.x <= 27.5 && bp.template.sheetSize.y <= 20.5, "\(tag) sheet too big \(bp.template.sheetSize)")
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
            // Boxes close; fins stand on their tabs against the right surface.
            func folded(_ id: String) -> FoldRig {
                var rig = FoldRig(piece: bp.piece(id)!, thickness: t)
                rig.angles = bp.finishedAngles(id)
                return rig
            }
            let body = bp.body
            guard let (bW, bH, bL, _) = body.boxSize else { check(false, "\(tag) body is a box"); continue }
            let bodyTop = bH + 2 * t
            for part in bp.parts {
                let rig = folded(part.id)
                if let (W, H, L, front) = part.boxSize {
                    let b = rig.foldedBounds()
                    check(abs(b.max.y - (H + 2 * t)) < 1e-3 && abs(b.max.z - (W / 2 + t)) < 1e-3 && abs(b.max.x - (L + t)) < 1e-3,
                          "\(tag) \(part.id) box closes \(b)")
                    check(abs(b.min.x - (front ? -t : 0)) < 1e-3, "\(tag) \(part.id) front cap \(b.min.x)")
                } else if let (u0, u1) = part.tabSpan {
                    // The tab's printed face is the glued face; it must touch the target surface.
                    let tab = bp.piece(part.id)!.panel("FT")!.outline
                    let face = tab.map { (part.mount * rig.pose(of: "FT")).apply($0.onMat(t)) }
                    let ys = face.map { $0.y }
                    let target: Float
                    if part.id == "guard" { target = 0 }
                    else if kind == .rifle && part.id == "frontSight" { target = bp.part("barrel")!.mount.pos.y + 0.62 + 2 * t }
                    else { target = bodyTop }
                    check(ys.allSatisfy { abs($0 - target) < 1e-3 }, "\(tag) \(part.id) tab on its surface \(ys) vs \(target)")
                    check(u1 > u0 + 0.3, "\(tag) \(part.id) tab span")
                    // Fin body is vertical in the z = 0 plane.
                    let fin = bp.piece(part.id)!.panel("F0")!.outline.flatMap { q in [Float(0), t].map { (part.mount * rig.pose(of: "F0")).apply(q.onMat($0)) } }
                    check(fin.allSatisfy { abs($0.z) <= t / 2 + 1e-3 }, "\(tag) \(part.id) fin centred")
                    if part.id == "guard" {
                        check(fin.allSatisfy { $0.y <= 1e-3 }, "\(tag) guard hangs below")
                    } else {
                        check(fin.allSatisfy { $0.y >= target - 1e-3 }, "\(tag) \(part.id) stands up")
                    }
                }
            }
            // Hanging boxes (grip, magazine) meet the body bottom: open-end corners at
            // y >= 0 (tucked into the body), the rest below it, all under the body.
            for id in ["grip", "magazine"] {
                guard let part = bp.part(id), let (W, H, _, _) = part.boxSize else { continue }
                let top = [V3(0, 0, 0), V3(0, H + 2 * t, 0)].map { part.mount.apply($0) }
                check(abs(min(top[0].y, top[1].y)) < 1e-3 && max(top[0].y, top[1].y) < bH * 0.4, "\(tag) \(id) top meets the body \(top)")
                check(top.allSatisfy { $0.x > 0 && $0.x < bL }, "\(tag) \(id) under the body \(top)")
                check(W + 2 * t <= bW + 2 * t + 1e-3, "\(tag) \(id) no wider than the body")
            }
            // Rifle: barrel through the slot, inside the receiver; stock against its back.
            if kind == .rifle, let barrel = bp.part("barrel"), let (W, H, L, _) = barrel.boxSize {
                let insideEnd = barrel.mount.apply(V3(L + t, 0, 0)).x
                check(insideEnd > 1 && insideEnd < bL, "\(tag) barrel goes in \(insideEnd)")
                let lo = barrel.mount.apply(V3(0, 0, -W / 2 - t)), hi = barrel.mount.apply(V3(0, H + 2 * t, W / 2 + t))
                check(lo.y > t && hi.y < bH + t, "\(tag) barrel inside the receiver \(lo.y)..\(hi.y)")
                let slot = bp.piece("receiver")!.panel("FC")!.holes[0]
                var rr = FoldRig(piece: bp.piece("receiver")!, thickness: t)
                rr.angles = bp.finishedAngles("receiver")
                let s = slot.map { rr.pose(of: "FC").apply($0.onMat(0)) }
                check(s.map { $0.y }.min()! < lo.y && s.map { $0.y }.max()! > hi.y && s.map { $0.z }.min()! < lo.z && s.map { $0.z }.max()! > hi.z,
                      "\(tag) barrel fits the slot")
                let stock = bp.part("stock")!
                let front = stock.mount.apply(V3(-t, stock.boxSize!.H + 2 * t, 0))
                check(abs(front.x - (bL + t)) < 1e-3 && abs(front.y - bodyTop) < 1e-3, "\(tag) stock meets the receiver \(front)")
            }
            // Glue and details stay on their panels.
            let paths = bp.details.map { $0.path } + bp.parts.compactMap { bp.glue($0.id) }
            for path in paths {
                guard let panel = bp.piece(path.piece)?.panel(path.panel) else { check(false, "\(tag) missing \(path.piece).\(path.panel)"); continue }
                check(path.points.allSatisfy { Poly.contains(panel.outline, $0.xz) }, "\(tag) path off \(path.piece).\(path.panel)")
            }
            check(bp.parts.allSatisfy { $0.id == bp.body.id || $0.approach.len > 0.5 }, "\(tag) every part has an approach")
            if t == 0.14 { exportGun(bp, outDir: outDir) }
            print("\(tag): \(bp.parts.count) parts, sheet \(bp.template.sheetSize)")
        }
    }
    // Campaign: weapons keep their order, guns sit in between.
    let weaponOrder = Campaign.order.filter { id in WeaponDesign.campaign.contains { $0.id == id } }
    check(weaponOrder == WeaponDesign.campaign.map { $0.id }, "campaign keeps the weapon order")
    check(Campaign.level(of: "pistol") == 2 && Campaign.level(of: "rifle") == 5, "gun levels")
}

func exportGun(_ bp: GunBlueprint, outDir: String) {
    let t = bp.t
    var items: [(MeshData, Pose, [String])] = []
    var flat: [(MeshData, Pose, [String])] = []
    for p in bp.template.pieces {
        var rig = FoldRig(piece: p, thickness: t)
        rig.angles = bp.finishedAngles(p.id)
        let ps = rig.poses()
        for panel in p.panels {
            let m = MeshBuilder.cardboard(outline: panel.outline, holes: panel.holes, thickness: t, inkEdges: p.freeEdges(of: panel.id))
            items.append((m, bp.assembledPose(p.id) * ps[panel.id]!, ["#E2A652", "#E8B062", "#B17330", "#0D2730"]))
            flat.append((MeshBuilder.cardboard(outline: panel.outline, holes: panel.holes, thickness: t), WeaponBlueprint.sheetPose(p),
                         ["#E2A652", "#E8B062", "#B17330", "#0D2730"]))
        }
        var lines = MeshData()
        MeshBuilder.ribbon((p.outline + [p.outline[0]]).map { ($0 + p.placement).onMat(t + 0.01) }, width: 0.09, into: &lines)
        for panel in p.panels {
            for h in panel.holes { MeshBuilder.ribbon((h + [h[0]]).map { ($0 + p.placement).onMat(t + 0.01) }, width: 0.07, into: &lines) }
        }
        flat.append((lines, .identity, ["#F46359"]))
        var dash = MeshData()
        for panel in p.panels {
            if let h = panel.hinge { MeshBuilder.dashes((h.a + p.placement).onMat(t + 0.02), (h.b + p.placement).onMat(t + 0.02), into: &dash) }
        }
        flat.append((dash, .identity, ["#67C2E2"]))
    }
    for path in bp.details.map({ $0.path }) {
        guard let p = bp.piece(path.piece) else { continue }
        var rig = FoldRig(piece: p, thickness: t)
        rig.angles = bp.finishedAngles(p.id)
        var m = MeshData()
        MeshBuilder.ribbon(path.points.map { $0 + path.normal * 0.004 }, width: 0.08, normal: path.normal, into: &m)
        items.append((m, bp.assembledPose(p.id) * rig.pose(of: path.panel), ["#0D2730"]))
    }
    exportScene("gun_\(bp.kind.rawValue)", items)
    let holes = bp.template.pieces.map { Poly.translate($0.outline, $0.placement) }
    flat.insert((MeshBuilder.cardboard(outline: bp.template.sheetOutline, holes: holes, thickness: t), .identity,
                 ["#D69A48", "#E8B062", "#B17330", "#0D2730"]), at: 0)
    exportScene("sheet_gun_\(bp.kind.rawValue)", flat)
}
