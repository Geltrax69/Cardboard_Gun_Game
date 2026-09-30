import Combine
import QuartzCore
import SceneKit
import SwiftUI
import UIKit

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
    let tweener = Tweener()
    /// Everything that belongs to the current craft (sheet, pieces, guides).
    let craftRoot = SCNNode()

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

    override init() {
        super.init()
        scene.background.contents = Palette.table
        scene.rootNode.addChildNode(rig.node)
        scene.rootNode.addChildNode(workspace.root)
        craftRoot.name = "craft"
        scene.rootNode.addChildNode(craftRoot)
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

        rig.set(rig.framing(center: V3(0, 0, 0), size: V2(26, 18), view: .menu))
    }

    // MARK: Loop

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(max(now - lastTimestamp, 0), 1.0 / 20)
        lastTimestamp = now
        time += dt
        tweener.update(dt)
        for handler in Array(frameHandlers.values) { handler(dt) }
        rig.update(dt)
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
        viewportSize = size
        rig.setViewport(size)
    }

    // MARK: Input

    func pointer(_ phase: PointerPhase, at point: CGPoint) {
        pointerHandler?(phase, V2(Float(point.x), Float(point.y)))
    }

    // MARK: Projection helpers (view coordinates, points)

    func screen(_ p: V3) -> CGPoint {
        let s = rig.orbit.screen(p)
        return CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
    }

    func screenV(_ p: V3) -> V2 { rig.orbit.screen(p) }

    func hit(_ p: V2, planeY y: Float) -> V3? { rig.orbit.hit(p, planeY: y) }

    /// Screen-space length of one world unit near `p` (for tolerance scaling).
    func pointsPerUnit(near p: V3) -> Float {
        let a = rig.orbit.screen(p), b = rig.orbit.screen(p + rig.orbit.right)
        return max(1, a.dist(b))
    }

    // MARK: Craft scene helpers

    func clearCraft() {
        craftRoot.childNodes.forEach { $0.removeFromParentNode() }
        overlay.clearAll()
        pointerHandler = nil
    }

    /// Slides a fresh sheet onto the mat and settles into the top-down planning view.
    func showWorkbench(stock: CardboardStock) async throws {
        clearCraft()
        let size = V2(15.2, 10)
        let sheet = makeBlankSheet(stock: stock, size: size)
        craftRoot.addChildNode(sheet)
        let start = Pose(rot: Quat(axis: V3(0, 1, 0), angle: -0.25), pos: V3(-22, 1.5, 6))
        sheet.setPose(start)
        rig.glide(to: rig.framing(center: V3(0, 0, 0), size: size + V2(3.2, 2.4), view: .topDown), duration: 1.3, tweener: tweener)
        try await tweener.tween(0.9, ease: .outCubic) { k in
            sheet.setPose(start.lerp(.identity, k))
        }
        try await tweener.wait(0.4)
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
