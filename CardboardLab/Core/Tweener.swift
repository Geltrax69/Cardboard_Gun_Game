import Foundation

public enum Ease {
    case linear, inQuad, outQuad, inOutQuad, inCubic, outCubic, inOutCubic, outBack, outElastic, inOutSine

    public func callAsFunction(_ t: Float) -> Float {
        let x = saturate(t)
        switch self {
        case .linear: return x
        case .inQuad: return x * x
        case .outQuad: return 1 - (1 - x) * (1 - x)
        case .inOutQuad: return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
        case .inCubic: return x * x * x
        case .outCubic: return 1 - pow(1 - x, 3)
        case .inOutCubic: return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        case .outBack:
            let c1: Float = 1.70158, c3 = c1 + 1
            return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
        case .outElastic:
            if x == 0 || x == 1 { return x }
            return pow(2, -10 * x) * sin((x * 10 - 0.75) * (2 * .pi / 3)) + 1
        case .inOutSine: return -(cos(.pi * x) - 1) / 2
        }
    }
}

/// Promise-style tweening driven by the game loop. Crafting scripts are written as
/// straight-line async code (`try await tweener.tween(0.4) { … }`), and leaving a
/// session calls `cancelAll()`, which throws `Tweener.Cancelled` out of every pending
/// await so the script unwinds cleanly.
@MainActor
public final class Tweener {
    public struct Cancelled: Error {}

    private final class Item {
        let duration: Double
        var delay: Double
        var elapsed: Double = 0
        let ease: Ease
        let update: ((Float) -> Void)?
        let predicate: (() -> Bool)?
        let continuation: CheckedContinuation<Void, Error>?
        let tag: String?

        init(duration: Double, delay: Double, ease: Ease, update: ((Float) -> Void)?,
             predicate: (() -> Bool)?, continuation: CheckedContinuation<Void, Error>?, tag: String? = nil) {
            self.duration = max(duration, 1e-4)
            self.delay = delay
            self.ease = ease
            self.update = update
            self.predicate = predicate
            self.continuation = continuation
            self.tag = tag
        }
    }

    private var items: [Item] = []
    public private(set) var time: Double = 0
    public var isIdle: Bool { items.isEmpty }

    public init() {}

    /// Animates k from 0 → 1 (eased) over `duration` seconds.
    public func tween(_ duration: Double, ease: Ease = .inOutCubic, delay: Double = 0,
                      _ update: ((Float) -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            items.append(Item(duration: duration, delay: delay, ease: ease, update: update, predicate: nil, continuation: c))
        }
    }

    /// Fire-and-forget tween (runs alongside awaited ones). Starting a tween with the
    /// same `tag` replaces the previous one.
    public func start(_ duration: Double, ease: Ease = .inOutCubic, delay: Double = 0, tag: String? = nil,
                      _ update: @escaping (Float) -> Void) {
        if let tag { items.removeAll { $0.tag == tag && $0.continuation == nil } }
        items.append(Item(duration: duration, delay: delay, ease: ease, update: update, predicate: nil, continuation: nil, tag: tag))
    }

    public func wait(_ seconds: Double) async throws {
        try await tween(seconds, ease: .linear)
    }

    /// Resumes on the first frame where `predicate` returns true.
    public func until(_ predicate: @escaping () -> Bool) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            items.append(Item(duration: 0, delay: 0, ease: .linear, update: nil, predicate: predicate, continuation: c))
        }
    }

    public func update(_ dt: Double) {
        time += dt
        var finished: [Item] = []
        for item in items {
            if let p = item.predicate {
                if p() { finished.append(item) }
                continue
            }
            if item.delay > 0 {
                item.delay -= dt
                continue
            }
            item.elapsed += dt
            let k = Float(min(1, item.elapsed / item.duration))
            item.update?(item.ease(k))
            if k >= 1 { finished.append(item) }
        }
        guard !finished.isEmpty else { return }
        items.removeAll { i in finished.contains { $0 === i } }
        for item in finished { item.continuation?.resume() }
    }

    public func cancelAll() {
        let all = items
        items.removeAll()
        for item in all { item.continuation?.resume(throwing: Cancelled()) }
    }
}
