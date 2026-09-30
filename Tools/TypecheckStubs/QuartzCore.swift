@_exported import CoreGraphics

open class CALayer {
    public init() {}
    open var opacity: Float = 1
    open var isHidden = false
    open var frame: CGRect = .zero
    open var bounds: CGRect = .zero
    open var position: CGPoint = .zero
    open var cornerRadius: CGFloat = 0
    open var backgroundColor: CGColor?
    open func addSublayer(_ l: CALayer) {}
    open func removeFromSuperlayer() {}
}

public struct CAShapeLayerLineCap: Equatable { public static let round = CAShapeLayerLineCap(); public static let butt = CAShapeLayerLineCap(); public static let square = CAShapeLayerLineCap() }
public struct CAShapeLayerLineJoin: Equatable { public static let round = CAShapeLayerLineJoin(); public static let miter = CAShapeLayerLineJoin(); public static let bevel = CAShapeLayerLineJoin() }

open class CAShapeLayer: CALayer {
    public override init() {}
    open var path: CGPath?
    open var fillColor: CGColor?
    open var strokeColor: CGColor?
    open var lineWidth: CGFloat = 1
    open var lineCap: CAShapeLayerLineCap = .butt
    open var lineJoin: CAShapeLayerLineJoin = .miter
    open var lineDashPattern: [NSNumber]?
    open var lineDashPhase: CGFloat = 0
    open var strokeEnd: CGFloat = 1
}

open class CATransaction {
    open class func begin() {}
    open class func commit() {}
    open class func setDisableActions(_ flag: Bool) {}
}

public struct CAFrameRateRange {
    public init(minimum: Float, maximum: Float, preferred: Float?) {}
    public static let `default` = CAFrameRateRange(minimum: 0, maximum: 0, preferred: nil)
}

public struct Selector { public init(_ s: String) {} }

open class CADisplayLink {
    public init(target: Any, selector sel: Selector) {}
    open var timestamp: CFTimeInterval = 0
    open var targetTimestamp: CFTimeInterval = 0
    open var duration: CFTimeInterval = 0
    open var isPaused = false
    open var preferredFrameRateRange: CAFrameRateRange = .default
    open func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {}
    open func invalidate() {}
}
