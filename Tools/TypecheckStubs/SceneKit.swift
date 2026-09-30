@_exported import UIKit
import Metal

public struct SCNVector3 {
    public var x: Float, y: Float, z: Float
    public init() { x = 0; y = 0; z = 0 }
    public init(_ x: Float, _ y: Float, _ z: Float) { self.x = x; self.y = y; self.z = z }
    public init(x: Float, y: Float, z: Float) { self.x = x; self.y = y; self.z = z }
    public init(_ v: SIMD3<Float>) { x = v.x; y = v.y; z = v.z }
}
public struct SCNVector4 {
    public var x: Float, y: Float, z: Float, w: Float
    public init() { x = 0; y = 0; z = 0; w = 0 }
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) { self.x = x; self.y = y; self.z = z; self.w = w }
    public init(x: Float, y: Float, z: Float, w: Float) { self.x = x; self.y = y; self.z = z; self.w = w }
}
public typealias SCNQuaternion = SCNVector4
public let SCNVector3Zero = SCNVector3()
public struct SCNMatrix4 { public init() {} }
public let SCNMatrix4Identity = SCNMatrix4()
public func SCNMatrix4MakeScale(_ x: Float, _ y: Float, _ z: Float) -> SCNMatrix4 { SCNMatrix4() }

public enum SCNGeometryPrimitiveType { case triangles, triangleStrip, line, point, polygon }
public enum SCNWrapMode { case clamp, `repeat`, clampToBorder, mirror }
public enum SCNFilterMode { case none, nearest, linear }
public enum SCNCullMode { case back, front }
public enum SCNBlendMode { case alpha, add, subtract, multiply, screen, replace, max }
public enum SCNTransparencyMode { case aOne, rgbZero, singleLayer, dualLayer, `default` }
public enum SCNShadowMode { case forward, deferred, modulated }
public enum SCNAntialiasingMode { case none, multisampling2X, multisampling4X }
public enum SCNCameraProjectionDirection { case vertical, horizontal }

open class SCNMaterialProperty: NSObject {
    open var contents: Any?
    open var intensity: CGFloat = 1
    open var wrapS: SCNWrapMode = .clamp
    open var wrapT: SCNWrapMode = .clamp
    open var minificationFilter: SCNFilterMode = .linear
    open var magnificationFilter: SCNFilterMode = .linear
    open var mipFilter: SCNFilterMode = .none
    open var maxAnisotropy: CGFloat = 1
    open var contentsTransform = SCNMatrix4()
}

open class SCNMaterial: NSObject {
    public struct LightingModel: Equatable {
        public static let phong = LightingModel(), blinn = LightingModel(), lambert = LightingModel(), constant = LightingModel(), physicallyBased = LightingModel()
    }
    public override init() {}
    open var name: String?
    open var lightingModel: LightingModel = .blinn
    public let diffuse = SCNMaterialProperty()
    public let specular = SCNMaterialProperty()
    public let emission = SCNMaterialProperty()
    public let ambient = SCNMaterialProperty()
    public let transparent = SCNMaterialProperty()
    open var transparency: CGFloat = 1
    open var transparencyMode: SCNTransparencyMode = .default
    open var shininess: CGFloat = 1
    open var isDoubleSided = false
    open var cullMode: SCNCullMode = .back
    open var writesToDepthBuffer = true
    open var readsFromDepthBuffer = true
    open var blendMode: SCNBlendMode = .alpha
    open var locksAmbientWithDiffuse = true
}

open class SCNGeometrySource: NSObject {
    public init(vertices: [SCNVector3]) {}
    public init(normals: [SCNVector3]) {}
    public init(textureCoordinates: [CGPoint]) {}
}
open class SCNGeometryElement: NSObject {
    public init<IndexType: FixedWidthInteger>(indices: [IndexType], primitiveType: SCNGeometryPrimitiveType) {}
}
open class SCNGeometry: NSObject {
    public override init() {}
    public init(sources: [SCNGeometrySource], elements: [SCNGeometryElement]?) {}
    open var materials: [SCNMaterial] = []
    open var firstMaterial: SCNMaterial?
    open var name: String?
}
open class SCNPlane: SCNGeometry {
    public init(width: CGFloat, height: CGFloat) { super.init() }
    open var width: CGFloat = 1
    open var height: CGFloat = 1
}

open class SCNLight: NSObject {
    public struct LightType: Equatable {
        public static let ambient = LightType(), directional = LightType(), omni = LightType(), spot = LightType()
    }
    public override init() {}
    open var type: LightType = .omni
    open var color: Any = UIColor.white
    open var intensity: CGFloat = 1000
    open var castsShadow = false
    open var shadowMode: SCNShadowMode = .forward
    open var shadowColor: Any = UIColor.black
    open var shadowRadius: CGFloat = 3
    open var shadowSampleCount: Int = 0
    open var shadowMapSize: CGSize = .zero
    open var shadowBias: CGFloat = 1
    open var automaticallyAdjustsShadowProjection = true
    open var maximumShadowDistance: CGFloat = 100
    open var orthographicScale: Double = 1
    open var zNear: Double = 1
    open var zFar: Double = 100
    open var categoryBitMask: Int = -1
}

open class SCNCamera: NSObject {
    public override init() {}
    open var fieldOfView: CGFloat = 60
    open var projectionDirection: SCNCameraProjectionDirection = .vertical
    open var zNear: Double = 1
    open var zFar: Double = 100
    open var usesOrthographicProjection = false
    open var orthographicScale: Double = 1
}

open class SCNNode: NSObject {
    public override init() {}
    public init(geometry: SCNGeometry?) {}
    open var name: String?
    open var geometry: SCNGeometry?
    open var position = SCNVector3()
    open var orientation = SCNVector4(0, 0, 0, 1)
    open var eulerAngles = SCNVector3()
    open var scale = SCNVector3(1, 1, 1)
    open var simdPosition = SIMD3<Float>()
    open var opacity: CGFloat = 1
    open var isHidden = false
    open var castsShadow = true
    open var renderingOrder: Int = 0
    open var categoryBitMask: Int = 1
    open var light: SCNLight?
    open var camera: SCNCamera?
    open var childNodes: [SCNNode] { [] }
    open var parent: SCNNode? { nil }
    open func addChildNode(_ child: SCNNode) {}
    open func removeFromParentNode() {}
    open func look(at worldTarget: SCNVector3) {}
    open func childNode(withName name: String, recursively: Bool) -> SCNNode? { nil }
    open func clone() -> Self { self }
    open func flattenedClone() -> Self { self }
}

open class SCNScene: NSObject {
    public override init() {}
    open var rootNode: SCNNode { SCNNode() }
    public let background = SCNMaterialProperty()
    public let lightingEnvironment = SCNMaterialProperty()
}

open class SCNView: UIView {
    public override init(frame: CGRect) { super.init(frame: frame) }
    public init(frame: CGRect, options: [String: Any]?) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open var scene: SCNScene?
    open var pointOfView: SCNNode?
    open var antialiasingMode: SCNAntialiasingMode = .none
    open var preferredFramesPerSecond: Int = 60
    open var rendersContinuously = false
    open var isPlaying = false
    open var allowsCameraControl = false
    open var isJitteringEnabled = false
    open func snapshot() -> UIImage { UIImage() }
}

open class SCNRenderer: NSObject {
    public init(device: MTLDevice?, options: [AnyHashable: Any]? = nil) {}
    open var scene: SCNScene?
    open var pointOfView: SCNNode?
    open func snapshot(atTime time: CFTimeInterval, with size: CGSize, antialiasingMode: SCNAntialiasingMode) -> UIImage { UIImage() }
}
