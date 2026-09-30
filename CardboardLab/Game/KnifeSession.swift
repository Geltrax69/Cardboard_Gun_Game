import SceneKit
import UIKit

/// The knife build, step by step:
///   1 CUT    — cut the blade, handle and guard band out of the sheet
///   2 FOLD   — score and fold the handle walls, end cap and glue tab
///   3 GLUE   — glue the handle's tab
///   4 ALIGN  — close the lid onto the glued tab
///   5 FOLD   — fold the blade's ridge and glue its tang
///   6 ASSEMBLE — slide the blade in, wrap the guard band, finished!
@MainActor
final class KnifeSession: CraftSession {
    let bp: KnifeBlueprint
    private(set) var sheet: TemplateSheet!

    init(engine: GameEngine, stock: CardboardStock) {
        bp = KnifeBlueprint(thickness: stock.thickness)
        super.init(engine: engine, project: .knife, stock: stock)
    }

    override func run() async throws {
        hud.reset(steps: project.steps)
        try await placeTemplate()
        try await stepCut()
        try await stepFoldHandle()
        try await stepGlueTab()
        try await stepCloseHandle()
        try await stepFoldBlade()
        try await stepAssemble()
    }

    // MARK: Template

    private func placeTemplate() async throws {
        say("Fresh sheet", "The template is traced onto the cardboard.", tool: .none)
        sheet = TemplateSheet(template: bp.template, stock: stock)
        engine.craftRoot.childNodes.forEach { $0.removeFromParentNode() }
        engine.craftRoot.addChildNode(sheet.root)
        try await sheet.printTemplate(pencil: engine.workspace.pencil, tweener: tw)
    }

    // MARK: Steps (interactions are filled in feature by feature)

    private func stepCut() async throws {
        step(1, "Cut the solid edge", "Follow the red line with the craft knife.", tool: .knife)
        try await waitForNext()
    }

    private func stepFoldHandle() async throws {
        step(2, "Score & fold the handle", "Drag each flap up along its blue dashed line.", tool: .hand)
        try await waitForNext()
    }

    private func stepGlueTab() async throws {
        step(3, "Glue the tab", "Run the glue along the highlighted tab.", tool: .glue)
        try await waitForNext()
    }

    private func stepCloseHandle() async throws {
        step(4, "Close the handle", "Fold the lid down onto the glued tab.", tool: .hand)
        try await waitForNext()
    }

    private func stepFoldBlade() async throws {
        step(5, "Fold the blade", "Crease the ridge and glue the tang.", tool: .hand)
        try await waitForNext()
    }

    private func stepAssemble() async throws {
        step(6, "Assemble the knife", "Slide the blade in and wrap the guard band.", tool: .hand)
        try await waitForNext("Finish")
    }
}
