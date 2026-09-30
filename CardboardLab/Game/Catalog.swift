import Foundation

/// Craft projects shown on the menu. Add a new weapon/object here and give it a
/// blueprint + session script (see KnifeSession) to make it playable.
struct ProjectInfo: Identifiable, Equatable {
    enum Kind: Equatable {
        case playable
        case locked(requirement: String)
        case comingSoon
    }

    let id: String
    let name: String
    let steps: Int
    let kind: Kind
    let reward: Int

    static let knife = ProjectInfo(id: "knife", name: "Knife", steps: 6, kind: .playable, reward: 250)
    static let pistol = ProjectInfo(id: "pistol", name: "Pistol", steps: 8, kind: .locked(requirement: "Craft the knife to unlock"), reward: 400)
    static let rifle = ProjectInfo(id: "rifle", name: "Rifle", steps: 10, kind: .locked(requirement: "Craft the pistol to unlock"), reward: 600)
    static let more = ProjectInfo(id: "more", name: "More Crafts", steps: 0, kind: .comingSoon, reward: 0)

    static let all: [ProjectInfo] = [.knife, .pistol, .rifle, .more]
}

/// Tools on the menu shelf.
struct ToolInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let tip: String

    static let all: [ToolInfo] = [
        ToolInfo(id: "knife", name: "Craft Knife", tip: "Cuts cleanly along the solid red lines."),
        ToolInfo(id: "scissors", name: "Scissors", tip: "Trims scraps and rough edges."),
        ToolInfo(id: "glue", name: "Glue", tip: "Sticks tabs onto their matching surface."),
        ToolInfo(id: "ruler", name: "Ruler", tip: "Scores straight creases on the blue dashed lines."),
        ToolInfo(id: "pencil", name: "Pencil", tip: "Traces templates onto a fresh sheet."),
        ToolInfo(id: "tape", name: "Tape", tip: "Wraps and reinforces handles."),
    ]
}
