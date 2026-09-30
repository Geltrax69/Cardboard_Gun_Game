import SceneKit
import UIKit

/// Material factory. Solid objects use Lambert shading on flat-normal geometry, which
/// gives the faceted low-poly look; lights are tuned so an upward face shows its exact
/// palette color. Guides and ink use unlit (constant) materials.
enum Mat {
    static func lambert(_ color: UIColor, doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        m.isDoubleSided = doubleSided
        m.locksAmbientWithDiffuse = true
        return m
    }

    static func textured(_ image: UIImage, repeatS: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        m.diffuse.minificationFilter = .linear
        m.diffuse.magnificationFilter = .linear
        m.diffuse.maxAnisotropy = 8
        m.diffuse.wrapS = repeatS ? .repeat : .clamp
        m.diffuse.wrapT = .clamp
        m.locksAmbientWithDiffuse = true
        return m
    }

    static func unlit(_ color: UIColor, opacity: CGFloat = 1, depthWrite: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.transparency = opacity
        m.writesToDepthBuffer = depthWrite
        if opacity < 1 { m.blendMode = .alpha }
        return m
    }

    static func glossy(_ color: UIColor, shininess: CGFloat = 0.75) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = color
        m.specular.contents = UIColor.white
        m.shininess = shininess
        m.locksAmbientWithDiffuse = true
        return m
    }

    /// Back-face shell rendered in ink for outlines.
    static let hull: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Palette.ink
        m.cullMode = .front
        return m
    }()

    static let ink: SCNMaterial = unlit(Palette.ink)
}

/// Cardboard materials for one stock: [top, underside, sides, ink].
struct CardboardMaterials {
    let top: SCNMaterial
    let under: SCNMaterial
    let side: SCNMaterial
    let ink: SCNMaterial

    var array: [SCNMaterial] { [top, under, side, ink] }

    init(stock: CardboardStock) {
        top = Mat.lambert(UIColor(hex: stock.top))
        under = Mat.lambert(UIColor(hex: stock.under))
        side = Mat.textured(Textures.corrugation(stock), repeatS: true)
        ink = Mat.ink
    }

    /// Same cardboard with a tint (used to highlight a panel).
    func tinted(_ color: UIColor) -> [SCNMaterial] {
        [Mat.lambert(color), Mat.lambert(color), side, ink]
    }
}
