import Foundation

/// The campaign: every project in unlock order. Project `i` unlocks at level `i + 1`,
/// so the pistol arrives right after the first knife.
public enum Campaign {
    public static let order: [String] = [
        "knife", "pistol", "dagger", "kunai", "rifle", "bowie", "shortSword", "handAxe",
        "flameDagger", "karambit", "scimitar", "longsword", "katana", "battleAxe",
        // Added later, after everything above so nobody loses an unlock.
        "compact", "huntingKnife", "stiletto", "gladius", "revolver", "tomahawk", "tantoKnife", "dirk",
        "smg", "cutlass", "machete", "mainGauche", "carbine", "rapier", "hatchet", "cleaver",
        "machinePistol", "broadsword", "kukri", "wakizashi", "shotgun", "falchion", "survivalKnife", "targetPistol",
        "claymore", "beardedAxe", "flamberge", "sniper",
    ]

    public static func index(of id: String) -> Int? { order.firstIndex(of: id) }

    public static func level(of id: String) -> Int? { index(of: id).map { Progression.unlockLevel(index: $0) } }

    /// Enough XP to unlock everything.
    public static var allUnlockedXP: Int { Progression.xpNeeded(forLevel: order.count) }
}

/// Player levels. Crafting a campaign project for the first time earns exactly enough
/// XP to reach the next level, which unlocks the next project. Repeats and Free Craft
/// builds earn smaller amounts.
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

    /// XP for crafting campaign project `index` (0-based).
    public static func weaponXP(index: Int, firstTime: Bool) -> Int {
        let base = 100 + 50 * index
        return firstTime ? base : base * 2 / 5
    }

    /// XP for a Free Craft build.
    public static let freeCraftXP = 60

    /// Level at which campaign project `index` unlocks.
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
    var unlockLevel: Int { Campaign.level(of: id) ?? 1 }
}
