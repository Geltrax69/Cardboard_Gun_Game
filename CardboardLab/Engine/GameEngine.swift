import Combine
import QuartzCore
import SceneKit
import SwiftUI
import UIKit

enum AppScreen: Equatable {
    case menu
    case crafting
}

/// Floating feedback text ("+100 CRAFT", "Perfect fold", …).
struct Toast: Identifiable, Equatable {
    enum Style: Equatable { case reward, success, hint, info }
    let id = UUID()
    var text: String
    var style: Style
    /// Screen position; nil = centred under the instruction.
    var position: CGPoint?
    var born: Double
    var life: Double
}

/// Owns the SceneKit world, the game loop and input routing. Crafting sessions and the
/// menu drive it; SwiftUI observes it.
@MainActor
final class GameEngine: NSObject, ObservableObject, PointerSink {
    // MARK: Scene
    let scene = SCNScene()
    let scnView = GameSCNView(frame: .zero)
    let overlay = GuideOverlayView(frame: .zero)
    private(set) lazy var container: GameContainerView = {
        let c = GameContainerView(scnView: scnView, overlay: overlay)
        c.onLayout = { [weak self] size in self?.viewportChanged(size) }
        return c
    }()
    let rig = CameraRig()
    let workspace = Workspace()
    let menu = MenuScene()
    let particles = Particles()
    let tweener = Tweener()
    /// Everything that belongs to the current craft (sheet, pieces, guides).
    let craftRoot = SCNNode()

    // MARK: Game state
    let profile = PlayerProfile()
    let icons = IconFactory()
    let hud = HUDModel()
    private(set) var session: CraftSession?
    @Published private(set) var screen: AppScreen = .menu
    @Published private(set) var menuAnchors: [String: MenuAnchor] = [:]
    @Published private(set) var toasts: [Toast] = []
    @Published var selectedTool: String = "knife"
    @Published private(set) var transitioning = false
    private var sessionTask: Task<Void, Never>?

    // MARK: Loop
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameHandlers: [Int: (Double) -> Void] = [:]
    private var nextHandlerID = 0
    private(set) var time: Double = 0

    // MARK: Input
    /// The active interaction receives pointer events in view coordinates.
    var pointerHandler: ((PointerPhase, V2) -> Void)?
    private(set) var viewportSize = CGSize(width: 1180, height: 820)

    /// Screen fractions the menu UI covers (title/top, tools/bottom, projects/right).
    let menuInsets = CameraRig.Insets(top: 0.3, bottom: 0.3, left: 0.03, right: 0.3)

    override init() {
        super.init()
        scene.background.contents = Palette.table
        scene.rootNode.addChildNode(rig.node)
        scene.rootNode.addChildNode(workspace.root)
        scene.rootNode.addChildNode(menu.root)
        craftRoot.name = "craft"
        scene.rootNode.addChildNode(craftRoot)
        scene.rootNode.addChildNode(particles.root)
        Workspace.installLights(in: scene)

        scnView.scene = scene
        scnView.pointOfView = rig.node
        scnView.backgroundColor = Palette.table
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.isPlaying = true
        scnView.allowsCameraControl = false
        scnView.isMultipleTouchEnabled = false
        scnView.sink = self

        menu.select(profile.stock.id)
        rig.set(menuShot())
    }

    // MARK: Loop

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
        icons.renderAll(stock: profile.stock)
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(max(now - lastTimestamp, 0), 1.0 / 20)
        lastTimestamp = now
        time += dt
        tweener.update(dt)
        for handler in Array(frameHandlers.values) { handler(dt) }
        particles.update(Float(dt))
        rig.update(dt)
        if screen == .menu {
            menu.update(time: time)
            refreshMenuAnchors()
        }
        if toasts.contains(where: { time - $0.born > $0.life }) {
            toasts.removeAll { time - $0.born > $0.life }
        }
    }

    /// Registers a per-frame callback; returns a token for `removeFrameHandler`.
    @discardableResult
    func onFrame(_ handler: @escaping (Double) -> Void) -> Int {
        nextHandlerID += 1
        frameHandlers[nextHandlerID] = handler
        return nextHandlerID
    }

    func removeFrameHandler(_ id: Int?) {
        guard let id else { return }
        frameHandlers.removeValue(forKey: id)
    }

    private func viewportChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let first = viewportSize != size
        viewportSize = size
        rig.setViewport(size)
        if first && screen == .menu && !transitioning { rig.set(menuShot()) }
    }

    // MARK: Input

    func pointer(_ phase: PointerPhase, at point: CGPoint) {
        pointerHandler?(phase, V2(Float(point.x), Float(point.y)))
    }

    // MARK: Projection helpers (view coordinates, points)

    func toScreen(_ p: V3) -> CGPoint {
        let s = rig.orbit.screen(p)
        return CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
    }

    func toScreenV(_ p: V3) -> V2 { rig.orbit.screen(p) }

    func hit(_ p: V2, planeY y: Float) -> V3? { rig.orbit.hit(p, planeY: y) }

    /// Screen-space length of one world unit near `p` (for tolerance scaling).
    func pointsPerUnit(near p: V3) -> Float {
        let a = rig.orbit.screen(p), b = rig.orbit.screen(p + rig.orbit.right)
        return max(1, a.dist(b))
    }

    // MARK: Toasts

    func toast(_ text: String, _ style: Toast.Style = .info, at world: V3? = nil, life: Double = 1.6) {
        let pos = world.map { toScreen($0) }
        toasts.append(Toast(text: text, style: style, position: pos, born: time, life: life))
        if toasts.count > 4 { toasts.removeFirst(toasts.count - 4) }
    }

    // MARK: Menu

    func menuShot() -> OrbitCamera {
        rig.framing(center: V3(0, 0.4, -0.6), size: V2(21, 6.5), view: .menu, insets: menuInsets)
    }

    private func refreshMenuAnchors() {
        let a = menu.anchors(camera: rig.orbit)
        let changed = a.contains { key, value in
            guard let old = menuAnchors[key] else { return true }
            return abs(old.label.x - value.label.x) > 0.5 || abs(old.label.y - value.label.y) > 0.5
                || abs(old.rect.width - value.rect.width) > 0.5
        }
        if changed || a.count != menuAnchors.count { menuAnchors = a }
    }

    enum StockChoice { case selected, bought, tooExpensive }

    @discardableResult
    func chooseStock(_ stock: CardboardStock) -> StockChoice {
        let wasUnlocked = profile.isUnlocked(stock)
        guard profile.selectStock(stock) else {
            toast("Need \(stock.price) CRAFT — finish projects to earn more", .hint, life: 2.2)
            return .tooExpensive
        }
        menu.select(stock.id)
        icons.renderAll(stock: stock)
        if !wasUnlocked {
            toast("\(stock.name) unlocked!", .success)
            return .bought
        }
        return .selected
    }

    /// Returns to the menu from anywhere, cancelling the running craft.
    func goToMenu() {
        sessionTask?.cancel()
        sessionTask = nil
        tweener.cancelAll()
        session?.cleanup()
        session = nil
        hud.nextVisible = false
        particles.clear()
        pointerHandler = nil
        overlay.clearAll()
        transitioning = true
        screen = .menu
        Task { @MainActor in
            defer { transitioning = false }
            let fadeOut = craftRoot.childNodes
            menu.root.isHidden = false
            for id in menu.stacks.keys { menu.hideTopSheet(id, false) }
            rig.glide(to: menuShot(), duration: 1.0, tweener: tweener)
            try? await tweener.tween(0.45) { [weak self] k in
                for n in fadeOut { n.opacity = CGFloat(1 - k) }
                self?.menu.root.opacity = CGFloat(k)
            }
            for n in fadeOut { n.removeFromParentNode() }
        }
    }

    /// Starts a craft project: the top sheet of the chosen stack slides to the middle of
    /// the mat and grows into a full sheet, then the session script takes over.
    func startProject(_ project: ProjectInfo) {
        guard case .playable = project.kind, !transitioning else { return }
        transitioning = true
        screen = .crafting
        let stock = profile.stock
        sessionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.introSheet(stock: stock)
                self.transitioning = false
                try await self.runSession(project: project, stock: stock)
            } catch {
                self.transitioning = false
            }
        }
    }

    private func introSheet(stock: CardboardStock) async throws {
        clearCraft()
        let size = KnifeBlueprint(thickness: stock.thickness).template.sheetSize
        let from = menu.topSheetWorldPose(stock.id)
        menu.hideTopSheet(stock.id, true)
        let sheet = makeBlankSheet(stock: stock, size: size)
        craftRoot.addChildNode(sheet)
        let startScale = V3(menu.stackSize.x / size.x, 1, menu.stackSize.y / size.y)
        sheet.setPose(from)
        sheet.scale = SCNVector3(startScale.x, 1, startScale.z)
        rig.glide(to: rig.framing(center: V3(0, 0, 0), size: size + V2(3.2, 2.6), view: .topDown), duration: 1.4, tweener: tweener)
        let mid = Pose(rot: from.rot, pos: V3(from.pos.x * 0.4, 3.2, from.pos.z * 0.4))
        try await tweener.tween(0.55, ease: .outCubic) { [weak self] k in
            sheet.setPose(from.lerp(mid, k))
            self?.menu.root.opacity = CGFloat(1 - k)
        }
        menu.root.isHidden = true
        try await tweener.tween(0.6, ease: .inOutCubic) { k in
            sheet.setPose(mid.lerp(.identity, k))
            let s = mix3(startScale, V3(1, 1, 1), k)
            sheet.scale = SCNVector3(s.x, 1, s.z)
        }
        rig.addShake(0.12)
        try await tweener.wait(0.35)
    }

    /// Runs the project's crafting script, then returns to the menu.
    private func runSession(project: ProjectInfo, stock: CardboardStock) async throws {
        let s: CraftSession
        switch project.id {
        case ProjectInfo.knife.id: s = KnifeSession(engine: self, stock: stock)
        default: return
        }
        session = s
        try await s.run()
        s.cleanup()
        session = nil
        goToMenu()
    }

    // MARK: Craft scene helpers

    func clearCraft() {
        craftRoot.childNodes.forEach { $0.removeFromParentNode() }
        overlay.clearAll()
        pointerHandler = nil
    }

    /// Plain sheet on the mat (the empty workbench before a template is placed).
    func makeBlankSheet(stock: CardboardStock, size: V2) -> SCNNode {
        let outline = Poly.rect(-size.x / 2, -size.y / 2, size.x / 2, size.y / 2)
        let edges = (0..<4).map { (outline[$0], outline[($0 + 1) % 4]) }
        let mesh = MeshBuilder.cardboard(outline: outline, thickness: stock.thickness, inkEdges: edges, inkWidth: 0.05)
        let node = SceneBridge.node(mesh, CardboardMaterials(stock: stock).array, name: "blankSheet")
        node.castsShadow = true
        return node
    }
}
