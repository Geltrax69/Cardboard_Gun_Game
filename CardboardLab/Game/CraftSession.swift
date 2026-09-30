import SceneKit
import UIKit

/// Base class for a crafting script. Subclasses write the build as straight-line async
/// code; every await goes through the engine's Tweener, so leaving the session throws
/// `Tweener.Cancelled` and unwinds it.
@MainActor
class CraftSession {
    unowned let engine: GameEngine
    let project: ProjectInfo
    let stock: CardboardStock
    private var lastHintTime: Double = -10

    var hud: HUDModel { engine.hud }
    var tw: Tweener { engine.tweener }
    var rig: CameraRig { engine.rig }
    var overlay: GuideOverlayView { engine.overlay }
    var hintsOn: Bool { engine.profile.hintsOn }

    init(engine: GameEngine, project: ProjectInfo, stock: CardboardStock) {
        self.engine = engine
        self.project = project
        self.stock = stock
    }

    func run() async throws {}

    /// Called once the session is torn down (normal finish or Home).
    func cleanup() {}

    // MARK: HUD

    func step(_ n: Int, _ title: String, _ instruction: String, tool: HUDTool, detail: String? = nil) {
        hud.set(step: n, title: title, instruction: instruction, tool: tool, detail: detail)
        engine.profile.recordStep(project.id, step: n)
    }

    func say(_ title: String, _ instruction: String, tool: HUDTool? = nil, detail: String? = nil) {
        hud.set(title: title, instruction: instruction, tool: tool, detail: detail)
    }

    func waitForNext(_ label: String = "Next") async throws {
        hud.armNext(label)
        let model = hud
        try await tw.until { model.nextTapped }
    }

    // MARK: Feedback

    func reward(_ amount: Int, at world: V3? = nil) {
        engine.profile.addCoins(amount)
        engine.toast("+\(amount) CRAFT", .reward, at: world, life: 1.5)
    }

    func success(_ text: String, at world: V3? = nil) {
        engine.toast(text, .success, at: world, life: 1.4)
    }

    /// Gentle nudge, never more than once every few seconds.
    func hint(_ text: String = "Try following the highlighted line") {
        guard engine.time - lastHintTime > 3 else { return }
        lastHintTime = engine.time
        engine.toast(text, .hint, life: 2.0)
    }

    // MARK: Camera

    func look(at center: V3, size: V2, shot: CameraRig.Shot, duration: Double = 1.0, zoom: Float = 1) async throws {
        try await rig.move(to: rig.framing(center: center, size: size, view: shot, zoom: zoom), duration: duration, tweener: tw)
    }

    func glide(to center: V3, size: V2, shot: CameraRig.Shot, duration: Double = 1.0, zoom: Float = 1) {
        rig.glide(to: rig.framing(center: center, size: size, view: shot, zoom: zoom), duration: duration, tweener: tw)
    }
}
