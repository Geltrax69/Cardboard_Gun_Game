import Foundation

/// Craft projects shown on the menu: the campaign weapons (unlocked by player level),
/// Free Craft, and the guns that are still on the drawing board. A new knife, dagger,
/// sword or axe only needs a `WeaponDesign` in `WeaponDesign.campaign`.
struct ProjectInfo: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A weapon built by `WeaponSession` from `design`.
        case weapon
        /// Opens the Free Craft designer.
        case freeCraft
        case comingSoon
    }

    let id: String
    let name: String
    let kind: Kind
    var design: WeaponDesign? = nil
    /// Player level that unlocks it.
    var level: Int = 1
    /// CRAFT coins on completion.
    var reward: Int = 0
    /// One-line description for the card.
    var blurb: String = ""
    /// Position in the campaign (drives XP); nil for Free Craft builds.
    var campaignIndex: Int? = nil

    var steps: Int { design?.stepCount ?? 0 }

    /// Icon key in `IconFactory`.
    var iconKey: String {
        switch kind {
        case .weapon: return campaignIndex != nil ? "weapon.\(id)" : "weapon.custom"
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

    /// A Free Craft creation, ready to build.
    static func freeBuild(_ d: WeaponDesign) -> ProjectInfo {
        var design = d
        design.id = "free"
        return ProjectInfo(id: "free", name: design.name, kind: .weapon, design: design, reward: 120, blurb: design.summary)
    }

    static let weapons: [ProjectInfo] = WeaponDesign.campaign.enumerated().map { weapon($1, index: $0) }
    static let knife = weapons[0]
    static let freeCraft = ProjectInfo(id: "freeCraft", name: "Free Craft", kind: .freeCraft,
                                       blurb: "Design your own blade, guard and grip")
    static let pistol = ProjectInfo(id: "pistol", name: "Pistol", kind: .comingSoon, level: WeaponDesign.campaign.count + 1,
                                    blurb: "Blueprint on the drawing board")
    static let rifle = ProjectInfo(id: "rifle", name: "Rifle", kind: .comingSoon, level: WeaponDesign.campaign.count + 2,
                                   blurb: "Blueprint on the drawing board")

    static func byID(_ id: String) -> ProjectInfo? { weapons.first { $0.id == id } }
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
        ToolInfo(id: "tape", name: "Tape", tip: "Wraps and reinforces handles."),
    ]
}
