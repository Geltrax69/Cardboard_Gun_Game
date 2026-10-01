import Foundation

/// Craft projects shown on the menu: Free Craft and the campaign (blades and guns in
/// `Campaign.order`, unlocked by player level). A new knife, dagger, sword or axe only
/// needs a `WeaponDesign` in `WeaponDesign.campaign` and its id in `Campaign.order`.
struct ProjectInfo: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A weapon built by `WeaponSession` from `design`.
        case weapon
        /// The pistol or rifle, built by `GunSession`.
        case gun
        /// Opens the free mode workbench.
        case freeCraft
        case comingSoon
    }

    let id: String
    let name: String
    let kind: Kind
    var design: WeaponDesign? = nil
    var gun: GunKind? = nil
    /// Player level that unlocks it.
    var level: Int = 1
    /// CRAFT coins on completion.
    var reward: Int = 0
    /// One-line description for the card.
    var blurb: String = ""
    /// Position in the campaign (drives XP); nil for Free Craft builds.
    var campaignIndex: Int? = nil

    var steps: Int { design?.stepCount ?? (gun != nil ? 5 : 0) }

    /// Icon key in `IconFactory`.
    var iconKey: String {
        switch kind {
        case .weapon: return campaignIndex != nil ? "weapon.\(id)" : "weapon.custom"
        case .gun: return "gun.\(id)"
        case .freeCraft: return "project.free"
        case .comingSoon: return "project.\(id)"
        }
    }

    /// XP earned for finishing it.
    func xp(firstTime: Bool) -> Int {
        guard let i = campaignIndex else { return Progression.freeCraftXP }
        return Progression.weaponXP(index: i, firstTime: firstTime)
    }

    static func weapon(_ d: WeaponDesign, index: Int) -> ProjectInfo {
        ProjectInfo(id: d.id, name: d.name, kind: .weapon, design: d, level: Progression.unlockLevel(index: index),
                    reward: 250 + 40 * index, blurb: d.summary, campaignIndex: index)
    }

    static func gunProject(_ kind: GunKind, index: Int) -> ProjectInfo {
        ProjectInfo(id: kind.rawValue, name: kind.title, kind: .gun, gun: kind, level: Progression.unlockLevel(index: index),
                    reward: 300 + 40 * index,
                    blurb: kind.blurb,
                    campaignIndex: index)
    }

    /// Every campaign project in unlock order.
    static let campaign: [ProjectInfo] = Campaign.order.enumerated().compactMap { i, id in
        if let d = WeaponDesign.byID(id) { return weapon(d, index: i) }
        if let g = GunKind(rawValue: id) { return gunProject(g, index: i) }
        return nil
    }
    static let knife = campaign[0]
    static let freeCraft = ProjectInfo(id: "freeCraft", name: "Free Mode", kind: .freeCraft,
                                       blurb: "Unlimited cardboard: draw, cut, fold, paint")

    static func byID(_ id: String) -> ProjectInfo? { campaign.first { $0.id == id } }
}

/// Filters for the menu's project list.
enum ProjectCategory: String, CaseIterable {
    case all, knives, daggers, swords, axes, guns

    var title: String {
        switch self {
        case .all: return "All"
        case .knives: return "Knives"
        case .daggers: return "Daggers"
        case .swords: return "Swords"
        case .axes: return "Axes"
        case .guns: return "Guns"
        }
    }

    func includes(_ p: ProjectInfo) -> Bool {
        switch self {
        case .all: return true
        case .guns: return p.kind == .gun
        case .knives: return p.design?.kind == .knife
        case .daggers: return p.design?.kind == .dagger
        case .swords: return p.design?.kind == .sword
        case .axes: return p.design?.kind == .axe
        }
    }
}

/// Tools on the menu shelf.
struct ToolInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let tip: String

    static let all: [ToolInfo] = [
        ToolInfo(id: "knife", name: "Craft Knife", tip: "Cuts cleanly along the solid red lines."),
        ToolInfo(id: "folder", name: "Bone Folder", tip: "Scores crisp creases on the blue dashed lines."),
        ToolInfo(id: "glue", name: "Glue", tip: "Sticks tabs onto their matching surface."),
        ToolInfo(id: "sander", name: "Sanding Block", tip: "Sands edges into a sharp bevel and shapes the tip."),
        ToolInfo(id: "pencil", name: "Pencil", tip: "Traces templates onto a fresh sheet."),
        ToolInfo(id: "marker", name: "Marker", tip: "Draws ejection ports, serrations and grip texture."),
    ]
}
