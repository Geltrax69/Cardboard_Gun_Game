import SceneKit
import UIKit

/// Converts the platform-free core types into SceneKit objects.
enum SceneBridge {
    static func geometry(_ m: MeshData, materials: [SCNMaterial]) -> SCNGeometry {
        let verts = m.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let norms = m.normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let uvs = m.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        var elements: [SCNGeometryElement] = []
        var mats: [SCNMaterial] = []
        for (i, idx) in m.parts.enumerated() where !idx.isEmpty {
            elements.append(SCNGeometryElement(indices: idx, primitiveType: .triangles))
            mats.append(materials[min(i, materials.count - 1)])
        }
        let g = SCNGeometry(sources: [
            SCNGeometrySource(vertices: verts),
            SCNGeometrySource(normals: norms),
            SCNGeometrySource(textureCoordinates: uvs),
        ], elements: elements)
        g.materials = mats
        return g
    }

    static func node(_ m: MeshData, _ materials: [SCNMaterial], name: String? = nil) -> SCNNode {
        let n = SCNNode(geometry: geometry(m, materials: materials))
        n.name = name
        return n
    }
}

extension SCNNode {
    /// Places the node with a rigid transform from the core.
    func setPose(_ pose: Pose) {
        position = SCNVector3(pose.pos.x, pose.pos.y, pose.pos.z)
        orientation = SCNVector4(pose.rot.x, pose.rot.y, pose.rot.z, pose.rot.w)
    }

    var pose: Pose {
        let p = position, q = orientation
        return Pose(rot: Quat(x: q.x, y: q.y, z: q.z, w: q.w), pos: V3(p.x, p.y, p.z))
    }

    func setPosition(_ v: V3) {
        position = SCNVector3(v.x, v.y, v.z)
    }

    var pos3: V3 {
        let p = position
        return V3(p.x, p.y, p.z)
    }

    func setUniformScale(_ s: Float) {
        scale = SCNVector3(s, s, s)
    }
}
