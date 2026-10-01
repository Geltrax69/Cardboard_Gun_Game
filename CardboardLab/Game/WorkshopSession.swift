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

/// Free mode: an open workbench with unlimited cardboard. Everything on the table is a
/// piece (fresh sheets included): draw on any of them to punch shapes out or slice them
/// apart, draw valley or mountain fold lines and fold them, paint any face, and slide,
/// lift, turn, stack and glue pieces into 3D builds.
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
        case cut(Target, loop: [V2]?, slice: [V2]?)
        case score(piece: String, panel: String)
    }

    /// The panel face a stroke is drawn on.
    private struct Target: Equatable {
        var piece: String
        var panel: String
        var faceY: Float
    }

    private enum Drag {
        /// Drawing a cut or fold line: screen points so far.
        case stroke
        case fold(piece: String, panel: String, grab: V3, angle: Float, kind: FoldKind)
        case move(root: String, start: Pose, current: Pose, planeY: Float, from: V3, last: V2, centre: V3, moved: Bool)
        case paint
        case pan(last: V2)
        case tap(at: V2)
    }
    private var drag: Drag?
    private var target: Target?
    private var strokeScreen: [V2] = []
    /// Straight-lines mode: corners on the target panel (flat frame).
    private var linePoints: [V2] = []
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

    // MARK: Run loop

    override func run() async throws {
        hud.reset(steps: 1)
        preview.name = "workshopPreview"
        engine.craftRoot.addChildNode(scene.root)
        engine.craftRoot.addChildNode(preview)
        if var saved = WorkshopStore.load(), !saved.sheets.isEmpty || !saved.pieces.isEmpty {
            saved.migrate(defaultStock: stock.id)
            state = saved
        } else {
            state = freshBench()
            model.showHelp = true
        }
        if model.sheetStock.isEmpty { model.sheetStock = stock.id }
        scene.apply(state)
        model.canUndo = false
        model.busy = false
        model.cutting = false
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
            case let .cut(target, loop, slice): try await performCut(target, loop: loop, slice: slice)
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
        model.cutting = false
        engine.pointerHandler = nil
    }

    private func freshBench() -> WorkshopState {
        var s = WorkshopState()
        Workshop.addSheet(size: Workshop.sheetSizes[0].size, stock: stock.id, at: V3(0, 0, 0), in: &s)
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
        if undoStack.count > 50 { undoStack.removeFirst() }
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
        engine.toast(text, .hint, life: 2.0)
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
        target = nil
        strokeScreen = []
        linePoints = []
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
        case .cut: model.shape == .lines ? linesPointer(phase, p, ray) : strokePointer(phase, p, ray, crease: false)
        case .crease: strokePointer(phase, p, ray, crease: true)
        case .fold: foldPointer(phase, p, ray)
        case .paint: paintPointer(phase, ray)
        case .move: movePointer(phase, p, ray)
        case .glue: gluePointer(phase, p, ray)
        case .view: panPointer(phase, p)
        }
    }

    private func isTap(_ start: V2, _ end: V2) -> Bool { start.dist(end) < 14 }

    private func hitTarget(_ ray: (origin: V3, dir: V3)) -> Target? {
        scene.hitPanel(origin: ray.origin, dir: ray.dir).map { Target(piece: $0.piece, panel: $0.panel, faceY: $0.faceY) }
    }

    /// A screen point on the target panel's plane (flat frame).
    private func project(_ p: V2, onto t: Target) -> V2? {
        let r = rig.orbit.ray(p)
        return scene.panelPlanePoint(t.piece, t.panel, faceY: t.faceY, origin: r.origin, dir: r.dir)
    }

    // MARK: Cut and fold-line strokes

    /// Cut strokes (freehand, straight, rectangle, circle) and fold lines. A stroke may
    /// start off a piece: the first piece it passes over becomes its target, and every
    /// point is projected onto that piece's face.
    private func strokePointer(_ phase: PointerPhase, _ p: V2, _ ray: (origin: V3, dir: V3), crease: Bool) {
        switch phase {
        case .began:
            drag = .stroke
            strokeScreen = [p]
            target = hitTarget(ray)
        case .moved:
            guard case .stroke? = drag else { return }
            if let last = strokeScreen.last, last.dist(p) < 3 { return }
            strokeScreen.append(p)
            if target == nil { target = hitTarget(ray) }
            updateStrokePreview(crease: crease)
        case .ended:
            guard case .stroke? = drag else { return }
            drag = nil
            if strokeScreen.last.map({ $0.dist(p) > 1 }) ?? true { strokeScreen.append(p) }
            defer { strokeScreen = []; target = nil }
            guard let t = target else {
                clearPreview()
                nudge(crease ? "Draw the fold line across a piece" : "Draw over a piece or a sheet")
                return
            }
            let flat = strokeScreen.compactMap { project($0, onto: t) }
            guard flat.count >= 2 else { clearPreview(); return }
            crease ? finishCrease(flat, on: t) : finishCut(flat, on: t)
        case .cancelled:
            drag = nil
            strokeScreen = []
            target = nil
            clearPreview()
        }
    }

    private func updateStrokePreview(crease: Bool) {
        guard let t = target else { return }
        let flat = strokeScreen.compactMap { project($0, onto: t) }
        guard flat.count >= 2 else { return }
        if crease {
            showCreasePreview(t, flat.first!, flat.last!)
            return
        }
        switch model.shape {
        case .freehand: showPreview(flat, on: t, closed: false)
        case .straight: showPreview([flat.first!, flat.last!], on: t, closed: false)
        case .rectangle, .circle: showPreview(shapeLoop(flat.first!, flat.last!), on: t, closed: true)
        case .lines: break
        }
    }

    private func shapeLoop(_ a: V2, _ b: V2) -> [V2] {
        if model.shape == .circle {
            let r = a.dist(b)
            return Poly.circle(center: a, radius: r, sides: Int(clampf(r * 6, 10, 24)), phase: 0)
        }
        return Poly.rect(min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y))
    }

    private func finishCut(_ flat: [V2], on t: Target) {
        switch model.shape {
        case .freehand:
            let length = zip(flat, flat.dropFirst()).reduce(Float(0)) { $0 + $1.0.dist($1.1) }
            let closed = length > 1.5 && flat.first!.dist(flat.last!) < max(0.6, length * 0.12)
            if closed {
                submitCut(t, loop: Workshop.cleanStroke(flat), slice: nil)
            } else {
                submitCut(t, loop: nil, slice: Workshop.cleanPath(flat))
            }
        case .straight:
            submitCut(t, loop: nil, slice: [flat.first!, flat.last!])
        case .rectangle, .circle:
            submitCut(t, loop: shapeLoop(flat.first!, flat.last!), slice: nil)
        case .lines:
            break
        }
    }

    // MARK: Cut: straight lines

    private func linesPointer(_ phase: PointerPhase, _ p: V2, _ ray: (origin: V3, dir: V3)) {
        switch phase {
        case .began:
            if target == nil {
                guard let t = hitTarget(ray) else {
                    nudge("Tap on a piece or sheet to place the first corner")
                    return
                }
                target = t
            }
            drag = .tap(at: p)
            updateLinesPreview(p)
        case .moved:
            updateLinesPreview(p)
        case .ended:
            guard let t = target, let q = project(p, onto: t) else { return }
            drag = nil
            // Tapping the first corner again closes the shape.
            if linePoints.count >= 3, q.dist(linePoints[0]) < max(0.35, rig.orbit.distance * 0.012) {
                closeLines()
                return
            }
            if let last = linePoints.last, q.dist(last) < 0.15 { return }
            linePoints.append(q)
            model.linePoints = linePoints.count
            status(linePoints.count < 2 ? "Tap the next corner" : "Tap the first corner to close the shape, or Cut along the line")
            updateLinesPreview(nil)
        case .cancelled:
            drag = nil
            updateLinesPreview(nil)
        }
    }

    private func updateLinesPreview(_ finger: V2?) {
        guard let t = target else { clearPreview(); return }
        var pts = linePoints
        if let finger, let q = project(finger, onto: t) { pts.append(q) }
        showPreview(pts, on: t, closed: false, startMarker: linePoints.first)
    }

    private func closeLines() {
        guard let t = target, linePoints.count >= 3 else {
            nudge("Place at least three corners first")
            return
        }
        let loop = linePoints
        clearDrawing()
        submitCut(t, loop: loop, slice: nil)
    }

    private func cutAlongLines() {
        guard let t = target, linePoints.count >= 2 else {
            nudge("Place at least two points first")
            return
        }
        let path = linePoints
        clearDrawing()
        submitCut(t, loop: nil, slice: path)
    }

    private func clearDrawing() {
        linePoints = []
        target = nil
        model.linePoints = 0
    }

    // MARK: Cutting

    private func problemText(_ p: Workshop.CutProblem) -> String {
        switch p {
        case .tooSmall: return "Too small to cut — draw a bigger shape"
        case .crossesItself: return "The line crosses itself — try a simpler stroke"
        case .missesPiece: return "Draw the cut over a piece or sheet"
        case .crossesHole: return "That runs into a hole you already cut"
        case .crossesFold: return "A cut can't run through a fold line — cut beside it"
        case .needsEdge: return "Run the cut from edge to edge, or draw a closed shape"
        case .tooManyCrossings: return "That crosses the edge too many times — keep it simpler"
        }
    }

    /// Checks a cut on a copy of the bench first, so nobody traces a cut that can't happen.
    private func submitCut(_ t: Target, loop: [V2]?, slice: [V2]?) {
        var trial = state
        let result = loop != nil ? Workshop.cutLoop(loop!, piece: t.piece, panel: t.panel, in: &trial)
            : Workshop.slice(slice ?? [], piece: t.piece, panel: t.panel, in: &trial)
        if case let .failure(problem) = result {
            clearPreview()
            nudge(problemText(problem))
            return
        }
        jobs.append(.cut(t, loop: loop, slice: slice))
    }

    private func performCut(_ t: Target, loop: [V2]?, slice: [V2]?) async throws {
        clearPreview()
        var next = state
        let result = loop != nil ? Workshop.cutLoop(loop!, piece: t.piece, panel: t.panel, in: &next)
            : Workshop.slice(slice ?? [], piece: t.piece, panel: t.panel, in: &next)
        guard case let .success(newID) = result,
              let outline = state.piece(t.piece)?.panel(t.panel)?.outline,
              let knifeLine = Workshop.knifePath(loop: loop, slice: slice, outline: outline) else { return }
        // The red line, on the face it was drawn on.
        let pose = scene.panelWorld(t.piece, t.panel)
        let lift: Float = t.faceY > 0 ? t.faceY + 0.008 : -0.008
        var pts = knifeLine.points.map { pose.apply($0.onMat(lift)) }
        if knifeLine.closed, let f = pts.first { pts.append(f) }
        let normal = pose.applyVector(V3(0, t.faceY > 0 ? 1 : -1, 0))
        let line = CutLineNode(points: pts, name: "free", normal: normal)
        engine.craftRoot.addChildNode(line.root)
        defer { line.root.removeFromParentNode() }
        let knife = engine.workspace.knife
        model.cancelRequested = false
        model.cutting = true
        defer { model.cutting = false }
        do {
            if model.quickCut {
                status("Cutting…")
                try await autoCut(line, knife: knife)
            } else {
                status("Cut along the red line with the craft knife — or tap Cancel")
                let trace = TraceInteraction.cut(session: self, line: line, knife: knife, showHint: hintsOn && firstCut)
                let model = self.model
                trace.isCancelled = { model.cancelRequested }
                try await trace.run()
                firstCut = false
            }
        } catch is TraceInteraction.Cancelled {
            let from = knife.pose, rest = engine.workspace.knifeRest
            tw.start(0.6, ease: .inOutCubic) { k in knife.setPose(from.lerp(rest, k)) }
            status("Cut cancelled")
            return
        }
        let from = knife.pose, rest = engine.workspace.knifeRest
        tw.start(0.6, ease: .inOutCubic) { k in knife.setPose(from.lerp(rest, k)) }
        commit { $0 = next }
        guard let node = scene.pieceNodes[newID] else { return }
        // The cut-off piece pops out of the board and settles back.
        let base = node.pose
        let up = normal
        engine.particles.flakes(at: pose.apply(V3(0, 0.3, 0)), count: 10)
        engine.sound.play(.snap, volume: 0.7)
        try await tw.tween(0.45, ease: .linear) { k in
            node.pose = Pose(rot: base.rot, pos: base.pos + up * (0.45 * sin(k * .pi)))
        }
        node.pose = base
        success("Cut!", at: base.pos + V3(0, 0.8, 0))
        status("Cut! Move it with Move, crease it with Fold line, or keep cutting.")
    }

    // MARK: Fold lines

    private func finishCrease(_ flat: [V2], on t: Target) {
        clearPreview()
        guard var piece = state.piece(t.piece), let panel = piece.panel(t.panel) else { return }
        let a = flat.first!, b = flat.last!
        guard a.dist(b) > 0.3 else {
            nudge("Drag a line right across the piece")
            return
        }
        let (sa, sb) = Workshop.snapCrease(a, b, outline: panel.outline)
        switch Workshop.addCrease(&piece, panel: t.panel, sa, sb, kind: model.creaseKind) {
        case .success(let flap):
            commit { s in
                if let i = s.pieceIndex(t.piece) { s.pieces[i] = piece }
            }
            jobs.append(.score(piece: t.piece, panel: flap))
        case .failure(let problem):
            switch problem {
            case .missesPanel: nudge("Draw the fold line all the way across one panel")
            case .crossesCrease: nudge("Fold lines can't cross each other")
            case .tooThin: nudge("Too close to the edge — move the line inward")
            case .crossesHole: nudge("A fold line can't run through a hole")
            }
        }
    }

    /// The bone folder runs along a new crease.
    private func performScore(_ pieceID: String, _ panelID: String) async throws {
        guard let piece = state.piece(pieceID), let panel = piece.panel(panelID), let a = panel.hingeA, let b = panel.hingeB,
              let parent = panel.parent else { return }
        let folder = engine.workspace.boneFolder
        let pose = scene.panelWorld(pieceID, parent)
        let t = scene.thickness(pieceID)
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
        let kind = panel.foldKind == .valley ? "Valley" : "Mountain"
        success("\(kind) fold line", at: mix3(wa, wb, 0.5) + V3(0, 0.8, 0))
        status("Switch to Fold and drag the flap \(panel.foldKind == .valley ? "up" : "down"), or add more fold lines.")
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
            drag = .fold(piece: hit.piece, panel: hit.panel, grab: hit.local, angle: panel.angle, kind: panel.foldKind)
        case .moved:
            guard case let .fold(pieceID, panelID, grab, angle, kind)? = drag, let node = scene.pieceNodes[pieceID] else { return }
            let base = state.worldPose(pieceID)
            let orbit = rig.orbit
            var rigCopy = node.rig
            func screenPos(_ a: Float) -> V2 {
                rigCopy.angles[panelID] = a
                return orbit.screen((base * rigCopy.pose(of: panelID)).apply(grab))
            }
            // Valley folds go up, mountain folds go down; search near the current angle
            // so the flap never jumps through the board.
            let lo: Float = kind == .valley ? 0 : -.pi, hi: Float = kind == .valley ? .pi : 0
            var best = angle, bestD = screenPos(angle).dist(p)
            var a = max(lo, angle - radians(60))
            while a <= min(hi, angle + radians(60)) {
                let d = screenPos(a).dist(p)
                if d < bestD { bestD = d; best = a }
                a += radians(1.5)
            }
            node.setAngle(panelID, best)
            drag = .fold(piece: pieceID, panel: panelID, grab: grab, angle: best, kind: kind)
            status("\(kind == .valley ? "Valley" : "Mountain") fold: \(Int((abs(best) * 180 / .pi).rounded()))°")
        case .ended:
            guard case let .fold(pieceID, panelID, _, angle, kind)? = drag, let node = scene.pieceNodes[pieceID] else { return }
            drag = nil
            let snapped = Workshop.snapAngle(angle, kind: kind)
            node.setAngle(panelID, snapped)
            node.setCrease(panelID, 1)
            engine.sound.play(.fold, volume: 0.8)
            commit { s in
                if let i = s.pieceIndex(pieceID), let j = s.pieces[i].panelIndex(panelID) { s.pieces[i].panels[j].angle = snapped }
            }
            // Folding down would poke through the table: the piece rests on its flap.
            keepAboveTable(state.groupRoot(pieceID))
            let deg = Int((abs(snapped) * 180 / .pi).rounded())
            if deg == 90 || deg == 180 { success("Perfect fold") }
            status("\(kind == .valley ? "Valley" : "Mountain") fold: \(deg)°")
        case .cancelled:
            if case let .fold(pieceID, _, _, _, _)? = drag, let piece = state.piece(pieceID) {
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
        guard var pending = pendingPaint, let h = scene.hitPanel(origin: ray.origin, dir: ray.dir),
              let i = pending.pieceIndex(h.piece) else { return }
        let c = model.color
        var changed = false
        for j in pending.pieces[i].panels.indices where model.paintWhole || pending.pieces[i].panels[j].id == h.panel {
            if h.top {
                if pending.pieces[i].panels[j].top != c { pending.pieces[i].panels[j].top = c; changed = true }
            } else if pending.pieces[i].panels[j].under != c {
                pending.pieces[i].panels[j].under = c
                changed = true
            }
        }
        guard changed else { return }
        pendingPaint = pending
        scene.apply(pending)
        engine.sound.play(.glue, volume: 0.5, minInterval: 0.08)
        engine.particles.sparks(at: h.world, count: 4)
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
            let start = state.piece(root)?.pose.pose ?? .identity
            let b = scene.groupBounds(root)
            drag = .move(root: root, start: start, current: start, planeY: hit.world.y, from: hit.world, last: p,
                         centre: (b.min + b.max) / 2, moved: false)
        case .moved:
            guard case let .move(root, start, current, planeY, from, last, centre, _)? = drag,
                  let node = scene.pieceNodes[root] else { return }
            let orbit = rig.orbit
            var pose = current
            var c = centre
            switch model.moveMode {
            case .slide:
                guard let w = orbit.hit(p, planeY: planeY) else { return }
                pose = Pose(rot: start.rot, pos: start.pos + V3(w.x - from.x, 0, w.z - from.z))
            case .lift:
                let depth = (centre - orbit.eye).dotp(orbit.forward)
                let dy = -(p.y - last.y) * orbit.unitsPerPoint(atDepth: max(depth, 1))
                pose.pos.y += dy
                c.y += dy
            case .turn:
                let axis = orbit.up * (p.x - last.x) + orbit.right * (p.y - last.y)
                let len = axis.len
                if len > 1e-4 {
                    let r = Pose(rot: Quat(axis: axis / len, angle: len * 0.011))
                    pose = Pose.translation(centre) * r * Pose.translation(centre * -1) * current
                }
            }
            node.pose = pose
            let moved = pose.pos.dist(start.pos) > 0.03 || abs(pose.rot.w - start.rot.w) > 1e-3 ||
                abs(pose.rot.x - start.rot.x) > 1e-3 || abs(pose.rot.y - start.rot.y) > 1e-3
            drag = .move(root: root, start: start, current: pose, planeY: planeY, from: from, last: p, centre: c, moved: moved)
        case .ended:
            if case .tap? = drag {
                drag = nil
                select(nil)
                return
            }
            guard case let .move(root, _, current, _, _, _, _, moved)? = drag else { drag = nil; return }
            drag = nil
            guard moved else {
                status("Selected — drag to \(model.moveMode.title.lowercased()) it, or use the buttons below")
                return
            }
            engine.sound.play(.snap, volume: 0.5)
            commit { s in
                if let i = s.pieceIndex(root) { s.pieces[i].pose = StoredPose(current) }
            }
            keepAboveTable(root)
        case .cancelled:
            if case let .move(root, start, _, _, _, _, _, _)? = drag { scene.pieceNodes[root]?.pose = start }
            drag = nil
        }
    }

    private func select(_ id: String?) {
        selected = id
        model.hasSelection = id != nil
        refreshSelection()
    }

    private func refreshSelection() {
        if let s = selected, state.piece(s) == nil {
            selected = nil
            model.hasSelection = false
        }
        if let g = glueSource {
            scene.setSelected(g, color: PaintColor.glueTint)
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
        switch action {
        case .turn: try await rotateGroup(root, axis: up3, angle: -.pi / 4)
        case .stand: try await rotateGroup(root, axis: right, angle: -.pi / 2)
        case .flip: try await rotateGroup(root, axis: right, angle: .pi)
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
        keepAboveTable(root)
    }

    private func shiftGroup(_ root: String, by d: V3) async throws {
        guard let node = scene.pieceNodes[root], let start = state.piece(root)?.pose.pose else { return }
        let end = Pose(rot: start.rot, pos: start.pos + d)
        try await tw.tween(0.2, ease: .outCubic) { k in node.pose = start.lerp(end, k) }
        commit { s in
            if let i = s.pieceIndex(root) { s.pieces[i].pose = StoredPose(end) }
        }
        keepAboveTable(root)
    }

    /// Nothing sinks into the table.
    private func keepAboveTable(_ root: String) {
        let low = scene.groupBounds(root).min.y
        guard low < -1e-3, state.piece(root)?.gluedTo == nil else { return }
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
        case .moved:
            break
        case .cancelled:
            drag = nil
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
            let fresh = freshBench()
            commit { $0 = fresh }
            frameBench(duration: 0.9)
            status("Fresh workbench — Undo brings everything back")
        case .resetView:
            frameBench(duration: 0.8)
        case .toggleView:
            model.topView.toggle()
            frameBench(duration: 0.8)
        case .closeShape:
            closeLines()
        case .cutAlong:
            cutAlongLines()
        case .undoPoint:
            if !linePoints.isEmpty { linePoints.removeLast() }
            model.linePoints = linePoints.count
            if linePoints.isEmpty { target = nil }
            updateLinesPreview(nil)
        case .cancelDrawing:
            clearGesture()
            status(model.tool.help)
        case .move(let action):
            try await performMove(action)
        }
    }

    private func newSheet() async throws {
        clearGesture()
        model.showSheetPicker = false
        let size = Workshop.sheetSizes[min(max(model.sheetSize, 0), Workshop.sheetSizes.count - 1)].size
        let spot = Workshop.freeSpot(size: size, occupied: scene.pieceFootprints())
        var id = ""
        let stockID = model.sheetStock.isEmpty ? stock.id : model.sheetStock
        commit { s in id = Workshop.addSheet(size: size, stock: stockID, at: spot, in: &s) }
        frameBench(duration: 0.9)
        guard let node = scene.pieceNodes[id] else { return }
        engine.sound.play(.whoosh)
        let end = node.pose
        try await tw.tween(0.55, ease: .outBack) { k in
            node.pose = Pose(rot: end.rot, pos: end.pos + V3(0, 3 * (1 - k), 0))
        }
        node.pose = end
        rig.addShake(0.1)
        status("Fresh sheet — draw your next shape")
    }

    /// Frames the newest sheet (or everything) in the workshop view.
    private func frameBench(duration: Double) {
        let focus = state.activeSheet.flatMap { state.piece($0) != nil ? $0 : nil } ?? state.pieces.last?.id
        var center = V3(0, 0, 0)
        var size = Workshop.sheetSize + V2(5, 4)
        if let focus {
            let b = scene.groupBounds(state.groupRoot(focus))
            if b.min.x < b.max.x {
                center = (b.min + b.max) / 2
                size = V2(b.max.x - b.min.x, b.max.z - b.min.z) + V2(5, 4)
            }
        }
        let insets = CameraRig.Insets(top: 0.16, bottom: 0.17, left: 0.12, right: model.tool == .paint ? 0.3 : 0.04)
        rig.glide(to: rig.framing(center: center, size: size, view: model.topView ? .topDown : .workshop, insets: insets),
                  duration: duration, tweener: tw)
    }

    // MARK: Previews

    private func clearPreview() {
        preview.childNodes.forEach { $0.removeFromParentNode() }
    }

    /// Red line showing a cut being drawn on a panel face.
    private func showPreview(_ flat: [V2], on t: Target, closed: Bool, startMarker: V2? = nil) {
        clearPreview()
        guard flat.count >= 2 else { return }
        let pose = scene.panelWorld(t.piece, t.panel)
        let lift: Float = t.faceY > 0 ? t.faceY + 0.012 : -0.012
        let normal = pose.applyVector(V3(0, t.faceY > 0 ? 1 : -1, 0))
        var pts = flat.map { pose.apply($0.onMat(lift)) }
        if closed, let f = pts.first { pts.append(f) }
        var m = MeshData()
        MeshBuilder.ribbon(pts, width: 0.09, normal: normal, into: &m)
        if let a = startMarker {
            let ring = Poly.circle(center: a, radius: 0.28, sides: 12).map { pose.apply($0.onMat(lift)) }
            MeshBuilder.ribbon(ring + [ring[0]], width: 0.06, normal: normal, into: &m)
        }
        let node = SceneBridge.node(m, [Mat.unlit(Palette.red)], name: "shapePreview")
        node.castsShadow = false
        node.renderingOrder = 12
        preview.addChildNode(node)
    }

    /// Where the crease will go (snapped, across the whole panel): blue dashes for a
    /// valley, dash-dot for a mountain, red if it can't split the panel.
    private func showCreasePreview(_ t: Target, _ a: V2, _ b: V2) {
        clearPreview()
        guard let panel = state.piece(t.piece)?.panel(t.panel) else { return }
        let pose = scene.panelWorld(t.piece, t.panel)
        let lift: Float = t.faceY > 0 ? t.faceY + 0.015 : -0.015
        let normal = pose.applyVector(V3(0, t.faceY > 0 ? 1 : -1, 0))
        let (sa, sb) = a.dist(b) > 0.3 ? Workshop.snapCrease(a, b, outline: panel.outline) : (a, b)
        var m = MeshData()
        let ok: Bool
        if let split = Poly.splitByLine(panel.outline, sa, sb) {
            let p = pose.apply(split.p.onMat(lift)), q = pose.apply(split.q.onMat(lift))
            if model.creaseKind == .mountain {
                MeshBuilder.dashDot(p, q, width: 0.08, normal: normal, into: &m)
            } else {
                MeshBuilder.dashes(p, q, width: 0.08, normal: normal, into: &m)
            }
            ok = true
        } else {
            MeshBuilder.ribbon([pose.apply(sa.onMat(lift)), pose.apply(sb.onMat(lift))], width: 0.06, normal: normal, into: &m)
            ok = false
        }
        let node = SceneBridge.node(m, [Mat.unlit(ok ? Palette.blue : Palette.red)], name: "creasePreview")
        node.castsShadow = false
        node.renderingOrder = 12
        preview.addChildNode(node)
    }
}
