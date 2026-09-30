import SceneKit
import UIKit

/// Tiny pooled particle system: cardboard fibres while cutting, glue droplets and the
/// completion confetti. Particles are plain low-poly nodes updated by the game loop.
@MainActor
final class Particles {
    enum Kind: CaseIterable {
        case flake, confetti, droplet, spark
    }

    private struct Particle {
        let node: SCNNode
        let kind: Kind
        var vel: V3
        var spinAxis: V3
        var spinSpeed: Float
        var age: Float = 0
        var life: Float
        var size: Float
        var drag: Float
        var gravity: Float
        var floorY: Float?
    }

    let root = SCNNode()
    private var live: [Particle] = []
    private var pool: [Kind: [SCNNode]] = [:]
    private var geometries: [Kind: [SCNGeometry]] = [:]

    init() {
        root.name = "particles"
        var flake = MeshData(parts: 1)
        flake.triangle(0, V3(-0.09, 0, -0.06), V3(0.1, 0, -0.03), V3(-0.01, 0, 0.1), facing: V3(0, 1, 0))
        let flakeGeoms = [Palette.cardboard, Palette.cardboardLight, Palette.cardboardDark].map {
            SceneBridge.geometry(flake, materials: [Mat.lambert($0, doubleSided: true)])
        }
        geometries[.flake] = flakeGeoms

        let confettiColors = [Palette.mint, Palette.red, Palette.blue, Palette.yellow, Palette.paper]
        let rect = MeshBuilder.box(V3(0.34, 0.02, 0.18))
        geometries[.confetti] = confettiColors.map { SceneBridge.geometry(rect, materials: [Mat.lambert($0, doubleSided: true)]) }

        let drop = MeshBuilder.lathe([V2(0, 0), V2(0.07, 0.04), V2(0.05, 0.1), V2(0, 0.14)], sides: 6)
        geometries[.droplet] = [SceneBridge.geometry(drop, materials: [Mat.glossy(Palette.glue)])]

        let spark = MeshBuilder.box(V3(0.12, 0.12, 0.12))
        geometries[.spark] = [Palette.mint, Palette.yellow].map { SceneBridge.geometry(spark, materials: [Mat.unlit($0)]) }
    }

    private func take(_ kind: Kind) -> SCNNode {
        if var list = pool[kind], let n = list.popLast() {
            pool[kind] = list
            n.isHidden = false
            n.opacity = 1
            return n
        }
        let options = geometries[kind] ?? []
        let n = SCNNode(geometry: options.randomElement())
        n.castsShadow = kind == .confetti
        root.addChildNode(n)
        return n
    }

    private func recycle(_ p: Particle) {
        p.node.isHidden = true
        if let options = geometries[p.kind], let g = options.randomElement() { p.node.geometry = g }
        pool[p.kind, default: []].append(p.node)
    }

    private func spawn(_ kind: Kind, at pos: V3, vel: V3, life: Float, size: Float,
                       drag: Float = 1.5, gravity: Float = 9, floorY: Float? = 0.02) {
        let n = take(kind)
        n.setPosition(pos)
        n.setUniformScale(size)
        let axis = V3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)).unit
        live.append(Particle(node: n, kind: kind, vel: vel, spinAxis: axis.len > 0 ? axis : V3(0, 1, 0),
                             spinSpeed: Float.random(in: 4...12), life: life, size: size, drag: drag,
                             gravity: gravity, floorY: floorY))
    }

    /// Cardboard fibres flicking off the knife.
    func flakes(at p: V3, count: Int, direction: V3 = V3(0, 0, 0)) {
        for _ in 0..<count {
            let side = V3(Float.random(in: -1...1), 0, Float.random(in: -1...1)).unit
            let v = side * Float.random(in: 0.6...1.8) + V3(0, Float.random(in: 1.8...3.4), 0) - direction * 0.6
            spawn(.flake, at: p + V3(0, 0.05, 0), vel: v, life: Float.random(in: 0.8...1.3), size: Float.random(in: 0.5...1.1))
        }
    }

    /// Mint / coral / blue celebration burst.
    func confetti(at p: V3, count: Int = 70, power: Float = 7) {
        for _ in 0..<count {
            let dir = V3(Float.random(in: -1...1), Float.random(in: 0.9...1.9), Float.random(in: -1...1)).unit
            spawn(.confetti, at: p, vel: dir * Float.random(in: power * 0.55...power), life: Float.random(in: 1.6...2.6),
                  size: Float.random(in: 0.8...1.3), drag: 1.2, gravity: 7)
        }
    }

    /// Little mint sparks when pieces lock together.
    func sparks(at p: V3, count: Int = 14) {
        for _ in 0..<count {
            let dir = V3(Float.random(in: -1...1), Float.random(in: 0.3...1.2), Float.random(in: -1...1)).unit
            spawn(.spark, at: p, vel: dir * Float.random(in: 2...4), life: Float.random(in: 0.35...0.6),
                  size: Float.random(in: 0.6...1.0), drag: 3, gravity: 2, floorY: nil)
        }
    }

    func droplet(at p: V3) {
        spawn(.droplet, at: p, vel: V3(Float.random(in: -0.2...0.2), 0.6, Float.random(in: -0.2...0.2)),
              life: 0.45, size: Float.random(in: 0.7...1.0), drag: 2, gravity: 6)
    }

    func update(_ dt: Float) {
        guard !live.isEmpty else { return }
        var keep: [Particle] = []
        keep.reserveCapacity(live.count)
        for var p in live {
            p.age += dt
            if p.age >= p.life {
                recycle(p)
                continue
            }
            p.vel.y -= p.gravity * dt
            p.vel = p.vel * max(0, 1 - p.drag * dt)
            var pos = p.node.pos3 + p.vel * dt
            if let floor = p.floorY, pos.y < floor {
                pos.y = floor
                p.vel = V3(p.vel.x * 0.4, 0, p.vel.z * 0.4)
                p.spinSpeed *= 0.5
            }
            p.node.setPosition(pos)
            let q = p.node.pose.rot * Quat(axis: p.spinAxis, angle: p.spinSpeed * dt)
            p.node.orientation = SCNVector4(q.x, q.y, q.z, q.w)
            let remain = p.life - p.age
            if remain < 0.3 { p.node.setUniformScale(p.size * max(0.01, remain / 0.3)) }
            keep.append(p)
        }
        live = keep
    }

    func clear() {
        for p in live { recycle(p) }
        live.removeAll()
    }
}
