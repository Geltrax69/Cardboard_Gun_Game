@_exported import Foundation

public typealias AVAudioFrameCount = UInt32

open class AVAudioNode: NSObject {}
open class AVAudioMixerNode: AVAudioNode {}

open class AVAudioFormat: NSObject {
    public init?(standardFormatWithSampleRate: Double, channels: UInt32) {}
}

open class AVAudioPCMBuffer: NSObject {
    public init?(pcmFormat: AVAudioFormat, frameCapacity: AVAudioFrameCount) {}
    open var frameLength: AVAudioFrameCount = 0
    open var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? { nil }
}

public struct AVAudioPlayerNodeBufferOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let loops = AVAudioPlayerNodeBufferOptions(rawValue: 1)
}

public struct AVAudioTime {}

open class AVAudioPlayerNode: AVAudioNode {
    public override init() {}
    open var volume: Float = 1
    open var isPlaying: Bool { false }
    open func scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?, options: AVAudioPlayerNodeBufferOptions = [],
                             completionHandler: (() -> Void)? = nil) {}
    open func play() {}
    open func stop() {}
}

open class AVAudioEngine: NSObject {
    public override init() {}
    open var mainMixerNode: AVAudioMixerNode { AVAudioMixerNode() }
    open func attach(_ node: AVAudioNode) {}
    open func connect(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) {}
    open func start() throws {}
    open func stop() {}
}

open class AVAudioSession: NSObject {
    public struct Category: Equatable { public static let ambient = Category(), playback = Category(), soloAmbient = Category() }
    public struct Mode: Equatable { public static let `default` = Mode() }
    public struct CategoryOptions: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mixWithOthers = CategoryOptions(rawValue: 1)
    }
    open class func sharedInstance() -> AVAudioSession { AVAudioSession() }
    open func setCategory(_ category: Category, mode: Mode, options: CategoryOptions = []) throws {}
    open func setActive(_ active: Bool) throws {}
}
