import Combine
import Foundation

/// Everything the player owns, saved to UserDefaults as JSON.
final class PlayerProfile: ObservableObject {
    struct SaveData: Codable {
        var coins = 120
        var stockID = CardboardStock.plain.id
        var unlockedStocks: [String] = [CardboardStock.plain.id]
        var progress: [String: Int] = [:]
        var completed: [String: Int] = [:]
        var soundOn = true
        var hintsOn = true
        var seenGuide = false
        // Optional so saves from earlier versions still decode.
        var seenRotateTip: Bool?
        var xp: Int?
        /// Last Free Craft design.
        var freeDesign: WeaponDesign?
    }

    /// What finishing a craft earned.
    struct CompletionResult: Equatable {
        var xp: Int
        var levelBefore: Int
        var levelAfter: Int
        var firstTime: Bool
        var leveledUp: Bool { levelAfter > levelBefore }
    }

    private static let key = "cardboardlab.save.v1"

    @Published private(set) var data: SaveData

    init() {
        if let raw = UserDefaults.standard.data(forKey: PlayerProfile.key),
           let decoded = try? JSONDecoder().decode(SaveData.self, from: raw) {
            data = decoded
        } else {
            data = SaveData()
        }
    }

    private func mutate(_ change: (inout SaveData) -> Void) {
        var d = data
        change(&d)
        data = d
        if let raw = try? JSONEncoder().encode(d) {
            UserDefaults.standard.set(raw, forKey: PlayerProfile.key)
        }
    }

    // MARK: Accessors

    var coins: Int { data.coins }
    var stock: CardboardStock { CardboardStock.byID(data.stockID) }
    var soundOn: Bool { data.soundOn }
    var hintsOn: Bool { data.hintsOn }
    var seenGuide: Bool { data.seenGuide }
    var seenRotateTip: Bool { data.seenRotateTip ?? false }
    var xp: Int { data.xp ?? PlayerProfile.legacyXP(data) }
    var freeDesign: WeaponDesign? { data.freeDesign }
    var level: Int { Progression.level(forXP: xp) }
    var levelProgress: Float { Progression.levelProgress(xp: xp) }
    var xpToNextLevel: Int { Progression.xpNeeded(forLevel: level + 1) - xp }

    func isUnlocked(_ project: ProjectInfo) -> Bool { level >= project.level }

    /// Saves from before levels existed: credit the weapons already crafted.
    private static func legacyXP(_ d: SaveData) -> Int {
        ProjectInfo.campaign.reduce(0) { sum, p in
            let n = d.completed[p.id] ?? 0
            guard n > 0 else { return sum }
            return sum + p.xp(firstTime: true) + (n - 1) * p.xp(firstTime: false)
        }
    }

    func isUnlocked(_ stock: CardboardStock) -> Bool { data.unlockedStocks.contains(stock.id) }
    func progress(of project: String) -> Int { data.progress[project] ?? 0 }
    func timesCompleted(_ project: String) -> Int { data.completed[project] ?? 0 }

    // MARK: Mutations

    func addCoins(_ amount: Int) { mutate { $0.coins = max(0, $0.coins + amount) } }

    /// Selects a stock, buying it first if needed. Returns false if it can't be afforded.
    @discardableResult
    func selectStock(_ stock: CardboardStock) -> Bool {
        if !isUnlocked(stock) {
            guard data.coins >= stock.price else { return false }
            mutate {
                $0.coins -= stock.price
                $0.unlockedStocks.append(stock.id)
            }
        }
        mutate { $0.stockID = stock.id }
        return true
    }

    func recordStep(_ project: String, step: Int) {
        mutate { $0.progress[project] = max($0.progress[project] ?? 0, step) }
    }

    @discardableResult
    func recordCompletion(_ project: ProjectInfo) -> CompletionResult {
        let first = timesCompleted(project.id) == 0
        let gained = project.xp(firstTime: first)
        let before = level
        let total = xp + gained
        mutate {
            $0.completed[project.id, default: 0] += 1
            $0.progress[project.id] = 0
            $0.xp = total
        }
        return CompletionResult(xp: gained, levelBefore: before, levelAfter: level, firstTime: first)
    }

    func setSound(_ on: Bool) { mutate { $0.soundOn = on } }
    func setHints(_ on: Bool) { mutate { $0.hintsOn = on } }
    func markGuideSeen() { mutate { $0.seenGuide = true } }
    func markRotateTipSeen() { mutate { $0.seenRotateTip = true } }
    func saveFreeDesign(_ d: WeaponDesign) { mutate { $0.freeDesign = d } }

    /// Testing aid: enough XP to unlock every project and Free Craft part.
    func unlockAll() {
        let target = Campaign.allUnlockedXP
        mutate { $0.xp = max($0.xp ?? 0, target) }
    }

    func reset() {
        mutate { $0 = SaveData() }
    }
}
