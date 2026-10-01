import SceneKit
import UIKit

/// Saves the free mode workbench between visits.
enum WorkshopStore {
    static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CardboardLab", isDirectory: true).appendingPathComponent("workshop.json")
    }

    static func load() -> WorkshopState? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkshopState.self, from: data)
    }

    static func save(_ state: WorkshopState) {
        guard let url, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// Free mode: an open workbench with unlimited cardboard. The player draws shapes on a
/// sheet and cuts them out, draws fold lines across pieces and folds them to any angle,
/// paints any face any colour, and moves, turns, stacks and glues pieces into 3D builds.
///
/// Every change is a commit to `WorkshopState` (undoable, saved to disk); the scene
/// follows the state. Gestures go to the active tool; buttons arrive as commands.
@MainActor
final class WorkshopSession: BuildSession {
    let model: WorkshopModel
    private let scene: WorkshopScene
    private var state = WorkshopState()
    private var undoStack: [WorkshopState] = []
    private var jobs: [Job] = []

    private enum Job {
        case command(WorkshopCommand)
        case cut([V2], sheet: String)
        case score(piece: String, panel: String)
    }

    // Gesture state.
    private enum Drag {
        case draw(sheet: String, start: V2)
        case crease(piece: String, panel: String, a: V2, b: V2, faceY: Float)
        case fold(piece: String, panel: String, grab: V3, angle: Float)
        case move(root: String, start: Pose, planeY: Float, from: V3, picked: String, moved: Bool)
        case paint
        case pan(last: V2)
        case tap(at: V2)
    }
    private var drag: Drag?
    private var stroke: [V2] = []
    private var linePoints: [V2] = []
    private var lineSheet: String?
    private var pendingPaint: WorkshopState?
    private var selected: String?
    private var glueSource: String?
    private let preview = SCNNode()
    private var firstCut = true

    init(engine: GameEngine, model: WorkshopModel, stock: CardboardStock) {
        self.model = model
        scene = WorkshopScene(stock: stock)
        super.init(engine: engine, project: .freeCraft, stock: stock)
    }

    private var t: Float { stock.thickness }

    // MARK: Run loop

    override func run() async throws {
        hud.reset(steps: 1)
        preview.name = "workshopPreview"
        engine.craftRoot.addChildNode(scene.root)
        engine.craftRoot.addChildNode(preview)
        if let saved = WorkshopStore.load(), !saved.sheets.isEmpty || !saved.pieces.isEmpty {
            state = saved
        } else {
            state = WorkshopSession.freshBench()
            model.showHelp = true
        }
        scene.apply(state)
        model.canUndo = false
        model.busy = false
        model.send = { [weak self] c in self?.jobs.append(.command(c)) }
        model.onToolChange = { [weak self] _ in self?.toolChanged() }
        toolChanged()
        frameBench(duration: 1.2)
        installPointer()

        while true {
            try await tw.until { [weak self] in !(self?.jobs.isEmpty ?? true) }
            let job = jobs.removeFirst()
            model.busy = true
            defer { model.busy = false }
            switch job {
            case .command(let c): try await perform(c)
            case let .cut(shape, sheet): try await performCut(shape, sheetID: sheet)
            case let .score(piece, panel): try await performScore(piece, panel)
            }
            model.busy = false
            installPointer()
        }
    }

    override func cleanup() {
        super.cleanup()
        WorkshopStore.save(state)
        model.send = nil
        model.onToolChange = nil
        model.busy = false
        engine.pointerHandler = nil
    }

    static func freshBench() -> WorkshopState {
        var s = WorkshopState()
        let id = s.makeID("sheet")
        s.sheets.append(FreeSheet(id: id, size: Workshop.sheetSize, center: V3(0, 0, 0)))
        s.activeSheet = id
        return s
    }

    private func installPointer() {
        engine.pointerHandler = { [weak self] phase, p in self?.pointer(phase, p) }
    }

    // MARK: State

    /// Applies a change as one undo step, updates the scene and saves.
    private func commit(_ change: (inout WorkshopState) -> Void) {
        let before = state
        change(&state)
        guard state != before else { return }
        undoStack.append(before)
        if undoStack.count > 40 { undoStack.removeFirst() }
        scene.apply(state)
        model.canUndo = true
        refreshSelection()
        WorkshopStore.save(state)
    }

    /// Adjusts the last commit without a new undo step.
    private func amend(_ change: (inout WorkshopState) -> Void) {
        change(&state)
        scene.apply(state)
        refreshSelection()
        WorkshopStore.save(state)
    }

    private func status(_ text: String) { model.status = text }

    private func nudge(_ text: String) {
        status(text)
        engine.toast(text, .hint, life: 1.8)
    }

    // MARK: Tools

    private func toolChanged() {
        clearGesture()
        glueSource = nil
        if model.tool != .move { select(nil) }
        status(model.tool.help)
    }

    private func clearGesture() {
        drag = nil
        stroke = []
        linePoints = []
        lineSheet = nil
        model.linePoints = 0
        if let pending = pendingPaint, pending != state { scene.apply(state) }
        pendingPaint = nil
        clearPreview()
        refreshSelection()
    }

    private func pointer(_ phase: PointerPhase, _ p: V2) {
        guard !model.busy else { return }
        let ray = rig.orbit.ray(p)
        switch model.tool {
        case .cut: model.shape == .lines ? linesPointer(phase, p, ray) : cutPointer(phase, ray)
        case .crease: creasePointer(phase, p, ray)
        case .fold: foldPointer(phase, p, ray)
        case .paint: paintPointer(phase, ray)
        case .move: movePointer(phase, p, ray)
        case .glue: gluePointer(phase, p, ray)
        case .view: panPointer(phase, p)
        }
    }

    /// A touch that barely moved counts as a tap.
    private func isTap(_ start: V2, _ end: V2) -> Bool { start.dist(end) < 14 }

    // MARK: Cut: freehand, rectangle, circle

    private func cutPointer(_ phase: PointerPhase, _ ray: (origin: V3, dir: V3)) {
        switch phase {
        case .began:
            guard let hit = scene.hitSheet(origin: ray.origin, dir: ray.dir), hit.top else {
                nudge("Start drawing on a cardboard sheet — tap New sheet for more")
                return
            }
            drag = .draw(sheet: hit.sheet, start: hit.local)
            stroke = [hit.local]
        case .moved:
            guard case let .draw(sheet, start)? = drag, let q = scene.sheetPlanePoint(sheet, origin: ray.origin, dir: ray.dir) else { return }
            if model.shape == .freehand {
                if let last = stroke.last, q.dist(last) > 0.05 { stroke.append(q) }
            } else {
                stroke = [start, q]
            }
            // Freehand shows the raw stroke under the finger; shapes show their outline.
            showShapePreview(model.shape == .freehand ? stroke : currentShape(), sheet: sheet, closed: model.shape != .freehand)
        case .ended:
            guard case let .draw(sheet, _)? = drag else { return }
            let shape = currentShape()
            drag = nil
            stroke = []
            submit(shape, sheet: sheet)
        case .cancelled:
            drag = nil
            stroke = []
            clearPreview()
        }
    }

    private func currentShape() -> [V2] {
        switch model.shape {
        case .freehand:
            return Workshop.cleanStroke(stroke)
        case .rectangle:
            guard stroke.count == 2 else { return [] }
            let a = stroke[0], b = stroke[1]
            return Poly.rect(min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y))
        case .circle:
            guard stroke.count == 2 else { return [] }
            let r = stroke[0].dist(stroke[1])
            return Poly.circle(center: stroke[0], radius: r, sides: Int(clampf(r * 6, 10, 24)), phase: 0)
        case .lines:
            return linePoints
        }
    }

    // MARK: Cut: straight lines

    private func linesPointer(_ phase: PointerPhase, _ p: V2, _ ray: (origin: V3, dir: V3)) {
        switch phase {
        case .began:
            if lineSheet == nil {
                guard let hit = scene.hitSheet(origin: ray.origin, dir: ray.dir), hit.top else {
                    nudge("Tap on a cardboard sheet to place the first corner")
                    return
                }
                lineSheet = hit.sheet
            }
            drag = .tap(at: p)
            updateLinesPreview(ray)
        case .moved:
            updateLinesPreview(ray)
        case .ended:
            guard let sheet = lineSheet, let q = scene.sheetPlanePoint(sheet, origin: ray.origin, dir: ray.dir) else { return }
            drag = nil
            // Tapping the first corner again closes the shape.
            if linePoints.count >= 3, q.dist(linePoints[0]) < max(0.35, rig.orbit.distance * 0.012) {
                closeLines()
                return
            }
            if let last = linePoints.last, q.dist(last) < 0.15 { return }
            linePoints.append(q)
            model.linePoints = linePoints.count
            status(linePoints.count < 3 ? "Tap the next corner" : "Tap the first corner (or Close shape) to finish")
            updateLinesPreview(nil)
        case .cancelled:
            drag = nil
            updateLinesPreview(nil)
        }
    }

    private func updateLinesPreview(_ ray: (origin: V3, dir: V3)?) {
        guard let sheet = lineSheet else { clearPreview(); return }
        var pts = linePoints
        if let ray, let q = scene.sheetPlanePoint(sheet, origin: ray.origin, dir: ray.dir) { pts.append(q) }
        showShapePreview(pts, sheet: sheet, closed: false, startMarker: linePoints.first)
    }

    private func closeLines() {
        guard let sheet = lineSheet, linePoints.count >= 3 else {
            nudge("Place at least three corners first")
            return
        }
        let shape = Poly.signedArea(linePoints) < 0 ? Array(linePoints.reversed()) : linePoints
        linePoints = []
        lineSheet = nil
        model.linePoints = 0
        submit(shape, sheet: sheet)
    }

    /// Checks a drawn shape and queues the cut, or explains what's wrong.
    private func submit(_ shape: [V2], sheet: String) {
        guard let s = state.sheet(sheet) else { clearPreview(); return }
        if let problem = Workshop.checkCut(shape, in: s) {
            clearPreview()
            switch problem {
            case .tooSmall: nudge("Too small to cut — draw a bigger shape")
            case .crossesItself: nudge("The line crosses itself — try a simpler loop")
            case .offSheet: nudge("Keep the shape inside the sheet")
            case .overlapsHole: nudge("That overlaps a piece you already cut")
            }
            return
        }
        showShapePreview(shape, sheet: sheet, closed: true)
        jobs.append(.cut(shape, sheet: sheet))
    }

    private func performCut(_ shape: [V2], sheetID: String) async throws {
        guard let sheet = state.sheet(sheetID) else { return }
        clearPreview()
        let y = sheet.center.y + t + 0.008
        let loop = (shape + [shape[0]]).map { (sheet.center.xz + $0).onMat(y) }
        let line = CutLineNode(points: loop, name: "free")
        engine.craftRoot.addChildNode(line.root)
        defer { line.root.removeFromParentNode() }
        let knife = engine.workspace.knife
        if model.quickCut {
            status("Cutting…")
            try await autoCut(line, knife: knife)
        } else {
            status("Cut along the red line with the craft knife")
            try await TraceInteraction.cut(session: self, line: line, knife: knife, showHint: hintsOn && firstCut).run()
            firstCut = false
        }
        let from = knife.pose, rest = engine.workspace.knifeRest
        tw.start(0.6, ease: .inOutCubic) { k in knife.setPose(from.lerp(rest, k)) }
        var newID: String?
        commit { newID = Workshop.cut(shape, from: sheetID, in: &$0) }
        guard let id = newID, let node = scene.pieceNodes[id] else { return }
        // The piece pops up out of the board and settles back into place.
        let base = node.pose
        engine.particles.flakes(at: base.pos + V3(0, 0.3, 0), count: 10)
        engine.sound.play(.snap, volume: 0.7)
        try await tw.tween(0.45, ease: .linear) { k in
            node.pose = Pose(rot: base.rot, pos: base.pos + V3(0, 0.45 * sin(k * .pi), 0))
        }
        node.pose = base
        success("Cut out!", at: base.pos + V3(0, 0.8, 0))
        status("Cut out! Draw another shape, or switch to Fold line to crease it.")
    }

    // MARK: Fold lines

    private func creasePointer(_ phase: PointerPhase, _ p: V2, _ ray: (origin: V3, dir: V3)) {
        switch phase {
        case .began:
            guard let hit = scene.hitPanel(origin: ray.origin, dir: ray.dir) else {
                nudge("Start the fold line on a cut-out piece")
                return
            }
            let faceY: Float = hit.top ? t : 0
            drag = .crease(piece: hit.piece, panel: hit.panel, a: hit.local.xz, b: hit.local.xz, faceY: faceY)
        case .moved:
            guard case let .crease(piece, panel, a, _, faceY)? = drag else { return }
            let pose = scene.panelWorld(piece, panel)
            guard let w = rig.orbit.hit(p, planePoint: pose.apply(V3(0, faceY, 0)), normal: pose.applyVector(V3(0, 1, 0))) else { return }
            let b = pose.inverse.apply(w).xz
            drag = .crease(piece: piece, panel: panel, a: a, b: b, faceY: faceY)
            showCreasePreview(piece, panel, a, b, faceY: faceY)
        case .ended:
            clearPreview()
            guard case let .crease(pieceID, panel, a, b, _)? = drag else { return }
            drag = nil
            guard a.dist(b) > 0.3, var piece = state.piece(pieceID) else {
                nudge("Drag a line right across the piece")
                return
            }
            switch Workshop.addCrease(&piece, panel: panel, a, b) {
            case .success(let flap):
                commit { s in
                    if let i = s.pieceIndex(pieceID) { s.pieces[i] = piece }
                }
                jobs.append(.score(piece: pieceID, panel: flap))
            case .failure(let problem):
                switch problem {
                case .missesPanel: nudge("Draw the fold line all the way across one panel")
                case .crossesCrease: nudge("Fold lines can't cross each other")
                case .tooThin: nudge("Too close to the edge — move the line inward")
                }
            }
        case .cancelled:
            drag = nil
            clearPreview()
        }
    }

    /// The bone folder runs along a new crease.
    private func performScore(_ pieceID: String, _ panelID: String) async throws {
        guard let piece = state.piece(pieceID), let panel = piece.panel(panelID), let a = panel.hingeA, let b = panel.hingeB,
              let parent = panel.parent else { return }
        let folder = engine.workspace.boneFolder
        let pose = scene.panelWorld(pieceID, parent)
        let wa = pose.apply(a.onMat(t + 0.012)), wb = pose.apply(b.onMat(t + 0.012))
        let tangent = (wb - wa).unit
        let raise = radians(30)
        let from = folder.pose
        let start = TraceInteraction.penPose(tip: wa, tangent: tangent, raise: raise)
        try await tw.tween(0.25, ease: .inOutCubic) { k in folder.setPose(from.lerp(start, k)) }
        engine.sound.play(.score, volume: 0.6)
        try await tw.tween(0.35, ease: .inOutSine) { k in
            folder.setPose(TraceInteraction.penPose(tip: mix3(wa, wb, k), tangent: tangent, raise: raise))
        }
        let fp = folder.pose, rest = engine.workspace.folderRest
        tw.start(0.6) { k in folder.setPose(fp.lerp(rest, k)) }
        success("Fold line scored", at: mix3(wa, wb, 0.5) + V3(0, 0.8, 0))
        status("Switch to Fold and drag the flap to bend it, or add more fold lines.")
    }

    // MARK: Fold

    private func foldPointer(_ phase: PointerPhase, _ p: V2, _ ray: (origin: V3, dir: V3)) {
        switch phase {
        case .began:
            guard let hit = scene.hitPanel(origin: ray.origin, dir: ray.dir), let piece = state.piece(hit.piece),
                  let panel = piece.panel(hit.panel) else {
                nudge("Grab a piece's flap to fold it")
                return
            }
            guard panel.parent != nil else {
                nudge(piece.panels.count > 1 ? "That's the base — grab the flap on the other side of a fold line"
                                              : "Add a fold line first (Fold line tool)")
                return
            }
            drag = .fold(piece: hit.piece, panel: hit.panel, grab: hit.local, angle: panel.angle)
        case .moved:
            guard case let .fold(pieceID, panelID, grab, angle)? = drag, let node = scene.pieceNodes[pieceID] else { return }
            let base = state.worldPose(pieceID)
            let orbit = rig.orbit
            var rigCopy = node.rig
            func screenPos(_ a: Float) -> V2 {
                rigCopy.angles[panelID] = a
                return orbit.screen((base * rigCopy.pose(of: panelID)).apply(grab))
            }
            // Search near the current angle so the flap never jumps through the board.
            var best = angle, bestD = screenPos(angle).dist(p)
            var a = max(-Float.pi, angle - radians(60))
            while a <= min(Float.pi, angle + radians(60)) {
                let d = screenPos(a).dist(p)
                if d < bestD { bestD = d; best = a }
                a += radians(1.5)
            }
            node.setAngle(panelID, best)
            drag = .fold(piece: pieceID, panel: panelID, grab: grab, angle: best)
            status("Fold: \(Int((best * 180 / .pi).rounded()))°")
        case .ended:
            guard case let .fold(pieceID, panelID, _, angle)? = drag, let node = scene.pieceNodes[pieceID] else { return }
            drag = nil
            let snapped = Workshop.snapAngle(angle)
            node.setAngle(panelID, snapped)
            node.setCrease(panelID, 1)
            engine.sound.play(.fold, volume: 0.8)
            commit { s in
                if let i = s.pieceIndex(pieceID), let j = s.pieces[i].panelIndex(panelID) { s.pieces[i].panels[j].angle = snapped }
            }
            let deg = Int((snapped * 180 / .pi).rounded())
            if [90, -90, 180, -180].contains(deg) { success("Perfect fold") }
            status("Fold: \(deg)°")
        case .cancelled:
            if case let .fold(pieceID, _, _, _)? = drag, let piece = state.piece(pieceID) {
                scene.pieceNodes[pieceID]?.setAngles(piece.angles)
            }
            drag = nil
        }
    }

    // MARK: Paint

    private func paintPointer(_ phase: PointerPhase, _ ray: (origin: V3, dir: V3)) {
        switch phase {
        case .began:
            pendingPaint = state
            drag = .paint
            paintAt(ray)
        case .moved:
            guard case .paint? = drag else { return }
            paintAt(ray)
        case .ended:
            guard case .paint? = drag, let pending = pendingPaint else { return }
            drag = nil
            pendingPaint = nil
            if pending != state {
                model.used(model.color)
                commit { $0 = pending }
            }
        case .cancelled:
            drag = nil
            pendingPaint = nil
            scene.apply(state)
        }
    }

    private func paintAt(_ ray: (origin: V3, dir: V3)) {
        guard var pending = pendingPaint else { return }
        let c = model.color
        let panelHit = scene.hitPanel(origin: ray.origin, dir: ray.dir)
        let sheetHit = scene.hitSheet(origin: ray.origin, dir: ray.dir)
        var changed = false
        var at: V3?
        if let h = panelHit, sheetHit.map({ h.distance <= $0.distance }) ?? true {
            if let i = pending.pieceIndex(h.piece) {
                for j in pending.pieces[i].panels.indices where model.paintWhole || pending.pieces[i].panels[j].id == h.panel {
                    if h.top {
                        if pending.pieces[i].panels[j].top != c { pending.pieces[i].panels[j].top = c; changed = true }
                    } else if pending.pieces[i].panels[j].under != c {
                        pending.pieces[i].panels[j].under = c
                        changed = true
                    }
                }
                at = h.world
            }
        } else if let h = sheetHit, let i = pending.sheetIndex(h.sheet) {
            if h.top {
                if pending.sheets[i].top != c { pending.sheets[i].top = c; changed = true }
            } else if pending.sheets[i].under != c {
                pending.sheets[i].under = c
                changed = true
            }
            at = ray.origin + ray.dir * h.distance
        }
        guard changed else { return }
        pendingPaint = pending
        scene.apply(pending)
        engine.sound.play(.glue, volume: 0.5, minInterval: 0.08)
        if let at { engine.particles.sparks(at: at, count: 4) }
    }

    // MARK: Move

    private func movePointer(_ phase: PointerPhase, _ p: V2, _ ray: (origin: V3, dir: V3)) {
        switch phase {
        case .began:
            guard let hit = scene.hitPanel(origin: ray.origin, dir: ray.dir) else {
                drag = .tap(at: p)
                return
            }
            let root = state.groupRoot(hit.piece)
            select(hit.piece)
            drag = .move(root: root, start: state.piece(root)?.pose.pose ?? .identity, planeY: hit.world.y, from: hit.world,
                         picked: hit.piece, moved: false)
        case .moved:
            guard case let .move(root, start, planeY, from, picked, _)? = drag,
                  let w = rig.orbit.hit(p, planeY: planeY), let node = scene.pieceNodes[root] else { return }
            let delta = V3(w.x - from.x, 0, w.z - from.z)
            node.pose = Pose(rot: start.rot, pos: start.pos + delta)
            drag = .move(root: root, start: start, planeY: planeY, from: from, picked: picked, moved: delta.len > 0.05)
        case .ended:
            if case .tap? = drag {
                drag = nil
                select(nil)
                return
            }
            guard case let .move(root, _, _, _, _, moved)? = drag, let node = scene.pieceNodes[root] else { drag = nil; return }
            drag = nil
            guard moved else {
                status("Selected — turn, tilt, raise, copy or delete it with the buttons below")
                return
            }
            let pose = node.pose
            engine.sound.play(.snap, volume: 0.5)
            commit { s in
                if let i = s.pieceIndex(root) { s.pieces[i].pose = StoredPose(pose) }
            }
        case .cancelled:
            if case let .move(root, start, _, _, _, _)? = drag { scene.pieceNodes[root]?.pose = start }
            drag = nil
        }
    }

    private func select(_ id: String?) {
        selected = id
        model.hasSelection = id != nil
        model.selectionGlued = id.flatMap { state.piece($0)?.gluedTo } != nil
        refreshSelection()
    }

    private func refreshSelection() {
        if let s = selected, state.piece(s) == nil {
            selected = nil
            model.hasSelection = false
        }
        if let g = glueSource {
            scene.setSelected(g, color: Palette.yellow)
        } else {
            scene.setSelected(model.tool == .move ? selected : nil)
        }
        model.selectionGlued = selected.flatMap { state.piece($0)?.gluedTo } != nil
    }

    private func performMove(_ action: WorkshopModel.MoveAction) async throws {
        guard let sel = selected, let piece = state.piece(sel) else {
            nudge("Tap a piece first")
            return
        }
        let root = state.groupRoot(sel)
        let right = rig.orbit.right
        let forward = up3.crossp(right).unit
        switch action {
        case .turn: try await rotateGroup(root, axis: up3, angle: -.pi / 4)
        case .tilt: try await rotateGroup(root, axis: right, angle: .pi / 4)
        case .roll: try await rotateGroup(root, axis: forward, angle: .pi / 4)
        case .flip: try await rotateGroup(root, axis: right, angle: .pi)
        case .raise: try await shiftGroup(root, by: V3(0, 0.5, 0))
        case .lower: try await shiftGroup(root, by: V3(0, -0.5, 0))
        case .drop:
            let b = scene.groupBounds(root)
            try await shiftGroup(root, by: V3(0, -b.min.y, 0))
        case .copy:
            var copy = piece
            let world = state.worldPose(sel)
            commit { s in
                copy.id = s.makeID("piece")
                copy.gluedTo = nil
                copy.pose = StoredPose(Pose(rot: world.rot, pos: world.pos + V3(1.2, 0.3, 1.2)))
                s.pieces.append(copy)
            }
            select(copy.id)
            success("Copied")
        case .unglue:
            guard piece.gluedTo != nil else { return }
            let world = state.worldPose(sel)
            commit { s in
                if let i = s.pieceIndex(sel) {
                    s.pieces[i].gluedTo = nil
                    s.pieces[i].pose = StoredPose(world)
                }
            }
            success("Unglued")
        case .delete:
            commit { s in
                // Pieces glued to it stay where they are.
                for i in s.pieces.indices where s.pieces[i].gluedTo == sel {
                    let w = s.worldPose(s.pieces[i].id)
                    s.pieces[i].gluedTo = nil
                    s.pieces[i].pose = StoredPose(w)
                }
                s.pieces.removeAll { $0.id == sel }
            }
            select(nil)
            engine.sound.play(.whoosh, volume: 0.6)
        }
    }

    private func rotateGroup(_ root: String, axis: V3, angle: Float) async throws {
        guard let node = scene.pieceNodes[root], let start = state.piece(root)?.pose.pose else { return }
        let b = scene.groupBounds(root)
        let c = (b.min + b.max) / 2
        let end = Pose.translation(c) * Pose(rot: Quat(axis: axis, angle: angle)) * Pose.translation(c * -1) * start
        engine.sound.play(.fold, volume: 0.6)
        try await tw.tween(0.25, ease: .inOutCubic) { k in node.pose = start.lerp(end, k) }
        commit { s in
            if let i = s.pieceIndex(root) { s.pieces[i].pose = StoredPose(end) }
        }
        keepAboveMat(root)
    }

    private func shiftGroup(_ root: String, by d: V3) async throws {
        guard let node = scene.pieceNodes[root], let start = state.piece(root)?.pose.pose else { return }
        let end = Pose(rot: start.rot, pos: start.pos + d)
        try await tw.tween(0.2, ease: .outCubic) { k in node.pose = start.lerp(end, k) }
        commit { s in
            if let i = s.pieceIndex(root) { s.pieces[i].pose = StoredPose(end) }
        }
        keepAboveMat(root)
    }

    /// Nothing sinks into the table.
    private func keepAboveMat(_ root: String) {
        let low = scene.groupBounds(root).min.y
        guard low < -1e-3 else { return }
        amend { s in
            if let i = s.pieceIndex(root) {
                var p = s.pieces[i].pose.pose
                p.pos.y -= low
                s.pieces[i].pose = StoredPose(p)
            }
        }
    }

    // MARK: Glue

    private func gluePointer(_ phase: PointerPhase, _ p: V2, _ ray: (origin: V3, dir: V3)) {
        switch phase {
        case .began:
            drag = .tap(at: p)
        case .moved, .cancelled:
            if phase == .cancelled { drag = nil }
        case .ended:
            guard case let .tap(at)? = drag, isTap(at, p) else { drag = nil; return }
            drag = nil
            guard let hit = scene.hitPanel(origin: ray.origin, dir: ray.dir) else {
                glueSource = nil
                refreshSelection()
                status(model.tool.help)
                return
            }
            guard let source = glueSource else {
                glueSource = hit.piece
                refreshSelection()
                status("Now tap the piece to glue it onto")
                engine.sound.play(.tap)
                return
            }
            if hit.piece == source {
                glueSource = nil
                refreshSelection()
                status(model.tool.help)
                return
            }
            // No loops: the target can't already hang off the source.
            var up: String? = hit.piece
            var hops = 0
            while let u = up, hops < 64 {
                if u == source {
                    nudge("Those are already stuck together")
                    glueSource = nil
                    refreshSelection()
                    return
                }
                up = state.piece(u)?.gluedTo
                hops += 1
            }
            let target = hit.piece
            let rel = state.worldPose(target).inverse * state.worldPose(source)
            glueSource = nil
            commit { s in
                if let i = s.pieceIndex(source) {
                    s.pieces[i].gluedTo = target
                    s.pieces[i].pose = StoredPose(rel)
                }
            }
            engine.sound.play(.snap)
            engine.particles.sparks(at: hit.world, count: 10)
            success("Glued!", at: hit.world + V3(0, 0.8, 0))
            status("Glued — they move together now. Tap another piece to glue more.")
        }
    }

    // MARK: Look

    private func panPointer(_ phase: PointerPhase, _ p: V2) {
        switch phase {
        case .began:
            drag = .pan(last: p)
        case .moved:
            guard case let .pan(last)? = drag else { return }
            rig.userPan(dx: p.x - last.x, dy: p.y - last.y)
            drag = .pan(last: p)
        case .ended, .cancelled:
            drag = nil
        }
    }

    // MARK: Commands

    private func perform(_ c: WorkshopCommand) async throws {
        switch c {
        case .newSheet:
            try await newSheet()
        case .undo:
            clearGesture()
            guard let previous = undoStack.popLast() else { return }
            state = previous
            scene.apply(state)
            model.canUndo = !undoStack.isEmpty
            refreshSelection()
            WorkshopStore.save(state)
            engine.sound.play(.tap)
            status("Undone")
        case .clearAll:
            clearGesture()
            select(nil)
            commit { $0 = WorkshopSession.freshBench() }
            frameBench(duration: 0.9)
            status("Fresh workbench — Undo brings everything back")
        case .resetView:
            frameBench(duration: 0.8)
        case .toggleView:
            model.topView.toggle()
            frameBench(duration: 0.8)
        case .closeShape:
            closeLines()
        case .undoPoint:
            if !linePoints.isEmpty { linePoints.removeLast() }
            model.linePoints = linePoints.count
            if linePoints.isEmpty { lineSheet = nil }
            updateLinesPreview(nil)
        case .move(let action):
            try await performMove(action)
        }
    }

    private func newSheet() async throws {
        clearGesture()
        let spot = Workshop.freeSheetSpot(state, pieceBounds: scene.pieceFootprints())
        var id = ""
        commit { s in
            id = s.makeID("sheet")
            s.sheets.append(FreeSheet(id: id, size: Workshop.sheetSize, center: spot))
            s.activeSheet = id
        }
        frameBench(duration: 0.9)
        guard let node = scene.sheetNodes[id] else { return }
        engine.sound.play(.whoosh)
        try await tw.tween(0.55, ease: .outBack) { k in
            node.setPosition(spot + V3(0, 3 * (1 - k), 0))
            node.opacity = CGFloat(min(1, k * 2))
        }
        node.setPosition(spot)
        node.opacity = 1
        rig.addShake(0.1)
        status("Fresh sheet — draw your next shape")
    }

    /// Frames the active sheet (or the last one) in the workshop view.
    private func frameBench(duration: Double) {
        let sheet = state.activeSheet.flatMap { state.sheet($0) } ?? state.sheets.last
        let center = sheet?.center ?? V3(0, 0, 0)
        let size = (sheet?.size ?? Workshop.sheetSize) + V2(5, 4)
        let insets = CameraRig.Insets(top: 0.16, bottom: 0.17, left: 0.12, right: model.tool == .paint ? 0.3 : 0.04)
        rig.glide(to: rig.framing(center: center, size: size, view: model.topView ? .topDown : .workshop, insets: insets),
                  duration: duration, tweener: tw)
    }

    // MARK: Previews

    private func clearPreview() {
        preview.childNodes.forEach { $0.removeFromParentNode() }
    }

    /// Red line showing the shape being drawn on a sheet.
    private func showShapePreview(_ shape: [V2], sheet: String, closed: Bool, startMarker: V2? = nil) {
        clearPreview()
        guard let s = state.sheet(sheet), shape.count >= 2 else { return }
        let y = s.center.y + t + 0.012
        var pts = shape.map { (s.center.xz + $0).onMat(y) }
        if closed, let f = pts.first { pts.append(f) }
        var m = MeshData()
        MeshBuilder.ribbon(pts, width: 0.09, into: &m)
        if let a = startMarker {
            let ring = Poly.circle(center: a, radius: 0.28, sides: 12).map { (s.center.xz + $0).onMat(y) }
            MeshBuilder.ribbon(ring + [ring[0]], width: 0.06, into: &m)
        }
        let node = SceneBridge.node(m, [Mat.unlit(Palette.red)], name: "shapePreview")
        node.castsShadow = false
        node.renderingOrder = 12
        preview.addChildNode(node)
    }

    /// Blue dashed line where the crease will go (red if it can't split the panel).
    private func showCreasePreview(_ piece: String, _ panel: String, _ a: V2, _ b: V2, faceY: Float) {
        clearPreview()
        guard let p = state.piece(piece)?.panel(panel) else { return }
        let pose = scene.panelWorld(piece, panel)
        let lift: Float = faceY > 0 ? faceY + 0.015 : -0.015
        var m = MeshData()
        let ok: Bool
        if let split = Poly.splitByLine(p.outline, a, b) {
            MeshBuilder.dashes(pose.apply(split.p.onMat(lift)), pose.apply(split.q.onMat(lift)), width: 0.08,
                               normal: pose.applyVector(V3(0, faceY > 0 ? 1 : -1, 0)), into: &m)
            ok = true
        } else {
            MeshBuilder.ribbon([pose.apply(a.onMat(lift)), pose.apply(b.onMat(lift))], width: 0.06,
                               normal: pose.applyVector(V3(0, faceY > 0 ? 1 : -1, 0)), into: &m)
            ok = false
        }
        let node = SceneBridge.node(m, [Mat.unlit(ok ? Palette.blue : Palette.red)], name: "creasePreview")
        node.castsShadow = false
        node.renderingOrder = 12
        preview.addChildNode(node)
    }
}
