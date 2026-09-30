import SceneKit
import UIKit

/// The crafting table: dark teal table, cutting mat with grid, lights and the tools
/// resting around the mat (they peek in from the screen edges like a real desk).
final class Workspace {
    let root = SCNNode()
    let matSize = V2(30, 21)
    let matThickness: Float = 0.3

    let knife = Props.craftKnife()
    let glue = Props.glueBottle()
    let tape = Props.tapeRoll()
    let ruler = Props.ruler()
    let pencil = Props.pencil()
    let boneFolder = Props.boneFolder()
    private(set) var scraps: [SCNNode] = []

    /// Resting transforms of the tools that get picked up during crafting.
    let knifeRest = Pose(rot: Quat.euler(yaw: -0.95, pitch: 0, roll: 0.12), pos: V3(11.6, 0.32, 6.3))
    let folderRest = Pose(rot: Quat(axis: V3(0, 1, 0), angle: -0.35), pos: V3(-12.4, 0.02, 5.6))
    let glueRest = Pose(rot: Quat(axis: V3(1, 0, 0), angle: .pi / 2), pos: V3(11.5, 0.65, 0.4))

    init() {
        root.name = "workspace"
        buildTableAndMat()
        placeProps()
    }

    static func installLights(in scene: SCNScene) {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 640
        ambient.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 480
        sun.color = UIColor.white
        sun.castsShadow = true
        sun.shadowMode = .forward
        sun.shadowColor = UIColor(white: 0, alpha: 0.32)
        sun.shadowRadius = 1.2
        sun.shadowSampleCount = 4
        sun.shadowMapSize = CGSize(width: 4096, height: 4096)
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 90
        sun.shadowBias = 1.5
        let sunNode = SCNNode()
        sunNode.name = "sun"
        sunNode.light = sun
        sunNode.position = SCNVector3(-9, 24, -7)
        sunNode.look(at: SCNVector3(2, 0, 3))
        scene.rootNode.addChildNode(sunNode)
    }

    private func buildTableAndMat() {
        let table = SceneBridge.node(MeshBuilder.box(V3(220, 2, 220), center: V3(0, -matThickness - 1, 0)), [Mat.lambert(Palette.table)])
        table.name = "table"
        root.addChildNode(table)

        let body = Props.part(MeshBuilder.box(V3(matSize.x, matThickness, matSize.y), center: V3(0, -matThickness / 2 - 0.002, 0)),
                              Palette.matSide, outline: 0.05, castsShadow: false)
        root.addChildNode(body)
        let top = SCNPlane(width: CGFloat(matSize.x), height: CGFloat(matSize.y))
        top.materials = [Mat.textured(Textures.cuttingMat(size: CGSize(width: CGFloat(matSize.x), height: CGFloat(matSize.y))))]
        let topNode = SCNNode(geometry: top)
        topNode.name = "matTop"
        topNode.eulerAngles.x = -.pi / 2
        topNode.position = SCNVector3(0, 0, 0)
        root.addChildNode(topNode)
    }

    private func placeProps() {
        ruler.setPose(Pose(rot: Quat(axis: V3(0, 1, 0), angle: 0.95), pos: V3(-12.2, 0, -7.4)))
        root.addChildNode(ruler)

        pencil.setPose(Pose(rot: Quat(axis: V3(0, 1, 0), angle: 0.62), pos: V3(-11.9, 0.2, 1.4)))
        root.addChildNode(pencil)

        tape.setPose(Pose(pos: V3(12.4, 0, -6.8)))
        root.addChildNode(tape)

        glue.setPose(glueRest)
        root.addChildNode(glue)

        knife.setPose(knifeRest)
        root.addChildNode(knife)

        boneFolder.setPose(folderRest)
        root.addChildNode(boneFolder)

        let stackA = Props.cardboardStack(width: 7, depth: 5.5, sheets: 3, stock: .plain, seed: 1)
        stackA.setPose(Pose(rot: Quat(axis: V3(0, 1, 0), angle: 0.25), pos: V3(-16.5, -matThickness, 8.8)))
        root.addChildNode(stackA)
        let stackB = Props.cardboardStack(width: 6, depth: 4.5, sheets: 2, stock: .plain, seed: 2)
        stackB.setPose(Pose(rot: Quat(axis: V3(0, 1, 0), angle: -0.4), pos: V3(-15.5, -matThickness, -10.8)))
        root.addChildNode(stackB)
        let stackC = Props.cardboardStack(width: 5, depth: 4, sheets: 2, stock: .plain, seed: 3)
        stackC.setPose(Pose(rot: Quat(axis: V3(0, 1, 0), angle: 0.5), pos: V3(16.8, -matThickness, -11.5)))
        root.addChildNode(stackC)

        let spots: [(Float, Float, Float)] = [(-9.8, -8.6, 0.8), (-7.6, -9.3, 0.55), (-10.6, -3.4, 0.7), (-11.1, 5.2, 0.85),
                                              (10.3, 3.4, 0.6), (9.6, 8.6, 0.75), (8.2, -9.1, 0.5), (11.2, -2.6, 0.55),
                                              (-8.9, 9.1, 0.6), (6.2, 9.4, 0.45)]
        for (i, s) in spots.enumerated() {
            let scrap = Props.scrap(size: s.2, seed: i + 3)
            scrap.position = SCNVector3(s.0, 0.001, s.1)
            scrap.eulerAngles.y = Float(i) * 1.7
            root.addChildNode(scrap)
            scraps.append(scrap)
        }
    }
}
