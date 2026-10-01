import SceneKit
import UIKit

/// Screen-space placement of a menu object, published to SwiftUI for labels and taps.
struct MenuAnchor: Equatable {
    var rect: CGRect
    var label: CGPoint
    var badge: CGPoint
}

/// The cardboard stacks on the mat that the player picks from on the menu, three to a
/// page; the shelf slides sideways between pages.
@MainActor
final class MenuScene {
    let root = SCNNode()
    let stackSize = V2(5.4, 5.4)
    let sheetsPerStack = 4
    private(set) var stacks: [String: SCNNode] = [:]
    private(set) var topSheets: [String: SCNNode] = [:]
    private let frame: SCNNode
    private(set) var selected: String = CardboardStock.plain.id
    private var lift: [String: Float] = [:]
    /// Shelf page shown (three stacks each) and how far the shelf has slid toward it.
    private(set) var page = 0
    private var scroll: Float = 0

    static let perPage = 3
    static let pagerKey = "pager"
    static let spacing: Float = 7
    /// Pages sit this far apart, so the neighbours are well off screen.
    static let pageWidth: Float = 24
    static var pageCount: Int { (CardboardStock.all.count + perPage - 1) / perPage }

    static func page(of id: String) -> Int {
        (CardboardStock.all.firstIndex { $0.id == id } ?? 0) / perPage
    }

    /// Where a stack rests with the shelf scrolled to `scroll` pages.
    private static func position(_ id: String, scroll: Float) -> V3 {
        let i = CardboardStock.all.firstIndex { $0.id == id } ?? 0
        let page = i / perPage, slot = i % perPage
        let x = Float(page) * pageWidth + Float(slot - 1) * spacing - scroll * pageWidth
        return V3(x, 0, -0.6)
    }

    private func position(_ id: String) -> V3 { MenuScene.position(id, scroll: scroll) }

    init() {
        root.name = "menu"
        let s = stackSize
        let rectOutline = Poly.rect(-s.x / 2, -s.y / 2, s.x / 2, s.y / 2)
        let edges = (0..<4).map { (rectOutline[$0], rectOutline[($0 + 1) % 4]) }
        for stock in CardboardStock.all {
            let stack = SCNNode()
            stack.name = "stack-\(stock.id)"
            let mats = CardboardMaterials(stock: stock)
            let t = stock.thickness * 1.5
            for i in 0..<sheetsPerStack {
                let jitter = Float((i * 5 + stock.id.count) % 5 - 2) * 0.05
                let m = MeshBuilder.cardboard(outline: rectOutline, thickness: t, inkEdges: edges, inkWidth: 0.06)
                let sheet = SceneBridge.node(m, mats.array, name: "sheet")
                sheet.castsShadow = true
                sheet.setPose(Pose(rot: Quat(axis: V3(0, 1, 0), angle: jitter), pos: V3(jitter * 1.5, Float(i) * t, jitter)))
                stack.addChildNode(sheet)
                if i == sheetsPerStack - 1 { topSheets[stock.id] = sheet }
            }
            stack.setPosition(MenuScene.position(stock.id, scroll: 0))
            root.addChildNode(stack)
            stacks[stock.id] = stack
            lift[stock.id] = 0
        }

        // Glowing selection frame (a flat yellow ring around the chosen stack).
        var ring = MeshData()
        let m: Float = 0.45
        let r = Poly.rect(-s.x / 2 - m, -s.y / 2 - m, s.x / 2 + m, s.y / 2 + m)
        MeshBuilder.ribbon((r + [r[0]]).map { $0.onMat(0.02) }, width: 0.3, into: &ring)
        frame = SceneBridge.node(ring, [Mat.unlit(Palette.yellow)], name: "selection")
        frame.castsShadow = false
        root.addChildNode(frame)
        page = MenuScene.page(of: selected)
        scroll = Float(page)
        place(frame: selected)
    }

    private func place(frame id: String) {
        frame.setPosition(position(id))
    }

    /// Selects a stack (and turns the shelf to its page).
    func select(_ id: String) {
        selected = id
        show(page: MenuScene.page(of: id))
        place(frame: id)
    }

    func show(page p: Int) {
        page = max(0, min(MenuScene.pageCount - 1, p))
    }

    /// The shelf slides toward its page; the selected stack bobs gently; the frame pulses.
    func update(time: Double) {
        scroll += (Float(page) - scroll) * 0.16
        if abs(Float(page) - scroll) < 1e-3 { scroll = Float(page) }
        for (id, stack) in stacks {
            let target: Float = id == selected ? 0.35 + 0.08 * Float(sin(time * 2.4)) : 0
            let cur = lift[id] ?? 0
            let next = cur + (target - cur) * 0.18
            lift[id] = next
            var p = position(id)
            p.y = next
            stack.setPosition(p)
            stack.isHidden = abs(p.x) > MenuScene.pageWidth * 0.9
        }
        place(frame: selected)
        frame.isHidden = MenuScene.page(of: selected) != page && abs(position(selected).x) > MenuScene.pageWidth * 0.9
        frame.opacity = CGFloat(0.75 + 0.25 * sin(time * 3.2))
    }

    func topSheetWorldPose(_ id: String) -> Pose {
        guard let stack = stacks[id], let sheet = topSheets[id] else { return .identity }
        return stack.pose * sheet.pose
    }

    func hideTopSheet(_ id: String, _ hidden: Bool) {
        topSheets[id]?.isHidden = hidden
    }

    func anchors(camera: OrbitCamera) -> [String: MenuAnchor] {
        var out: [String: MenuAnchor] = [:]
        let s = stackSize
        // The page switcher sits just behind the middle stack.
        let pager = camera.screen(V3(0, 0, -0.6 - s.y / 2 - 1.1))
        out[MenuScene.pagerKey] = MenuAnchor(rect: .zero, label: CGPoint(x: CGFloat(pager.x), y: CGFloat(pager.y)), badge: .zero)
        // Only the stacks on the page being shown (once the shelf has settled).
        guard abs(Float(page) - scroll) < 0.05 else { return out }
        for (i, stock) in CardboardStock.all.enumerated() where i / MenuScene.perPage == page {
            let id = stock.id
            let base = position(id)
            let h: Float = 0.9
            var pts: [V2] = []
            for dx in [-s.x / 2, s.x / 2] {
                for dz in [-s.y / 2, s.y / 2] {
                    for dy in [Float(0), h] { pts.append(camera.screen(base + V3(dx, dy, dz))) }
                }
            }
            let xs = pts.map { CGFloat($0.x) }, ys = pts.map { CGFloat($0.y) }
            let rect = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                              width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
            let front = camera.screen(base + V3(0, 0, s.y / 2 + 0.6))
            let corner = camera.screen(base + V3(s.x / 2 - 0.5, h, s.y / 2 - 0.5))
            out[id] = MenuAnchor(rect: rect,
                                 label: CGPoint(x: CGFloat(front.x), y: CGFloat(front.y)),
                                 badge: CGPoint(x: CGFloat(corner.x), y: CGFloat(corner.y)))
        }
        return out
    }
}
