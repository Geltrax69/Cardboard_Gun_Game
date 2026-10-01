// Minimal CoreGraphics surface for Linux type-checking (CGFloat/CGPoint/CGSize/CGRect
// come from Foundation on Linux).
@_exported import Foundation

open class CGColor { public init() {} }
open class CGPath { public init() {} }
open class CGMutablePath: CGPath { public override init() { super.init() } }
public enum CGLineJoin { case miter, round, bevel }
public enum CGLineCap { case butt, round, square }
public enum CGBlendMode { case normal, multiply }

open class CGImage { public init() {} }
open class CGColorSpace { public init() {} }
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace() }
public enum CGImageAlphaInfo: UInt32 { case none = 0, premultipliedLast, premultipliedFirst, last, first, noneSkipLast, noneSkipFirst, alphaOnly }

open class CGContext {
    public init() {}
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int,
                 space: CGColorSpace, bitmapInfo: UInt32) {}
    public func makeImage() -> CGImage? { nil }
    public func setFillColor(_ c: CGColor) {}
    public func setStrokeColor(_ c: CGColor) {}
    public func setLineWidth(_ w: CGFloat) {}
    public func setLineJoin(_ j: CGLineJoin) {}
    public func setLineCap(_ c: CGLineCap) {}
    public func setLineDash(phase: CGFloat, lengths: [CGFloat]) {}
    public func fill(_ r: CGRect) {}
    public func fillEllipse(in r: CGRect) {}
    public func strokeEllipse(in r: CGRect) {}
    public func stroke(_ r: CGRect) {}
    public func move(to p: CGPoint) {}
    public func addLine(to p: CGPoint) {}
    public func addLines(between: [CGPoint]) {}
    public func addRect(_ r: CGRect) {}
    public func addEllipse(in r: CGRect) {}
    public func closePath() {}
    public func strokePath() {}
    public func fillPath() {}
    public func saveGState() {}
    public func restoreGState() {}
    public func translateBy(x: CGFloat, y: CGFloat) {}
    public func rotate(by: CGFloat) {}
    public func scaleBy(x: CGFloat, y: CGFloat) {}
    public func addPath(_ p: CGPath) {}
}
public typealias CFTimeInterval = Double
