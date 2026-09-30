@_exported import Foundation
@_exported import CoreGraphics
@_exported import QuartzCore

open class UIColor: NSObject, @unchecked Sendable {
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public init(white: CGFloat, alpha: CGFloat) {}
    open var cgColor: CGColor { CGColor() }
    open func withAlphaComponent(_ alpha: CGFloat) -> UIColor { self }
    open class var white: UIColor { UIColor(white: 1, alpha: 1) }
    open class var black: UIColor { UIColor(white: 0, alpha: 1) }
    open class var clear: UIColor { UIColor(white: 0, alpha: 0) }
}

open class UIImage: NSObject, @unchecked Sendable {
    public override init() {}
    open var size: CGSize { .zero }
    open var cgImage: AnyObject? { nil }
}

open class UIFont: NSObject, @unchecked Sendable {
    public struct Weight: Hashable { public init(_ v: CGFloat) {}
        public static let regular = Weight(0), medium = Weight(0.2), semibold = Weight(0.3), bold = Weight(0.4), heavy = Weight(0.56), black = Weight(0.62) }
    open class func systemFont(ofSize: CGFloat, weight: Weight) -> UIFont { UIFont() }
    open class func systemFont(ofSize: CGFloat) -> UIFont { UIFont() }
}

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
    public static let foregroundColor = NSAttributedString.Key("NSColor")
}
extension NSAttributedString {
    public func size() -> CGSize { .zero }
    public func draw(at point: CGPoint) {}
    public func draw(in rect: CGRect) {}
}

public func UIGraphicsPushContext(_ c: CGContext) {}
public func UIGraphicsPopContext() {}

open class UIGraphicsImageRendererFormat: NSObject {
    public override init() {}
    open var scale: CGFloat = 1
    open var opaque = false
    open class func `default`() -> UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
}
open class UIGraphicsImageRendererContext: NSObject {
    open var cgContext: CGContext { CGContext() }
}
open class UIGraphicsImageRenderer: NSObject {
    public init(size: CGSize, format: UIGraphicsImageRendererFormat) {}
    public init(size: CGSize) {}
    open func image(actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage { UIImage() }
}

open class UIBezierPath: NSObject {
    public override init() {}
    public init(arcCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {}
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) {}
    public init(ovalIn rect: CGRect) {}
    public init(rect: CGRect) {}
    open func move(to point: CGPoint) {}
    open func addLine(to point: CGPoint) {}
    open func addQuadCurve(to point: CGPoint, controlPoint: CGPoint) {}
    open func addCurve(to point: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {}
    open func close() {}
    open var cgPath: CGPath { CGPath() }
    open var lineWidth: CGFloat = 1
    open func stroke() {}
    open func fill() {}
}

@MainActor open class UIResponder: NSObject {
    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
}

@MainActor open class UITouch: NSObject {
    open func location(in view: UIView?) -> CGPoint { .zero }
    open var force: CGFloat { 0 }
}

@MainActor open class UIEvent: NSObject {
    open func coalescedTouches(for touch: UITouch) -> [UITouch]? { nil }
}

@MainActor open class UIView: UIResponder {
    public init(frame: CGRect) {}
    public required init?(coder: NSCoder) {}
    open var frame: CGRect = .zero
    open var bounds: CGRect = .zero
    open var center: CGPoint = .zero
    open var backgroundColor: UIColor?
    open var isUserInteractionEnabled = true
    open var isMultipleTouchEnabled = false
    open var isHidden = false
    open var alpha: CGFloat = 1
    open var layer: CALayer { CALayer() }
    open var subviews: [UIView] { [] }
    open func addSubview(_ view: UIView) {}
    open func removeFromSuperview() {}
    open func layoutSubviews() {}
    open func setNeedsLayout() {}
    open func convert(_ point: CGPoint, to view: UIView?) -> CGPoint { point }
}

public enum UIUserInterfaceIdiom { case phone, pad, mac }
@MainActor open class UIDevice: NSObject {
    open class var current: UIDevice { UIDevice() }
    open var userInterfaceIdiom: UIUserInterfaceIdiom { .pad }
}

@MainActor open class UIImpactFeedbackGenerator: NSObject {
    public enum FeedbackStyle { case light, medium, heavy, soft, rigid }
    public init(style: FeedbackStyle) {}
    open func impactOccurred() {}
    open func prepare() {}
}
