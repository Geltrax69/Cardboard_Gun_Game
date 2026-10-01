import Foundation

/// Player levels. Crafting a campaign weapon for the first time earns exactly enough XP
/// to reach the next level, which unlocks the next weapon (campaign weapon `i` unlocks
/// at level `i + 1`). Repeats and Free Craft builds earn smaller amounts.
public enum Progression {
    /// Total XP needed to reach `level` (level 1 needs 0). Steps grow by 50 per level:
    /// 100, 150, 200, …
    public static func xpNeeded(forLevel level: Int) -> Int {
        let n = max(0, level - 1)
        return 50 * n + 25 * n * (n + 1)
    }

    public static func level(forXP xp: Int) -> Int {
        var level = 1
        while xpNeeded(forLevel: level + 1) <= xp { level += 1 }
        return level
    }

    /// Progress through the current level, 0…1.
    public static func levelProgress(xp: Int) -> Float {
        let l = level(forXP: xp)
        let lo = xpNeeded(forLevel: l), hi = xpNeeded(forLevel: l + 1)
        return Float(xp - lo) / Float(max(1, hi - lo))
    }

    /// XP for crafting campaign weapon `index` (0-based).
    public static func weaponXP(index: Int, firstTime: Bool) -> Int {
        let base = 100 + 50 * index
        return firstTime ? base : base * 2 / 5
    }

    /// XP for a Free Craft build.
    public static let freeCraftXP = 60

    /// Level at which campaign weapon `index` unlocks.
    public static func unlockLevel(index: Int) -> Int { index + 1 }
}

public extension WeaponDesign {
    /// Short description for menu cards, e.g. "Drop point · ridge blade".
    var summary: String {
        if let b = blade {
            var parts = [b.tip.title, b.build == .ridge ? "ridge blade" : "laminated blade"]
            if b.edge == .serrated { parts.append("serrated") }
            if b.fuller { parts.append("fuller") }
            return parts.joined(separator: " · ")
        }
        if let e = endClip, e.style.isAxeHead { return "\(e.style.title) axe head" }
        return kind.title
    }

    /// Level that unlocks this campaign weapon (1 for anything else).
    var unlockLevel: Int {
        WeaponDesign.campaign.firstIndex { $0.id == id }.map { Progression.unlockLevel(index: $0) } ?? 1
    }
}
