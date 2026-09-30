import Combine
import Foundation

/// Tool shown in the bottom-left chip during crafting.
enum HUDTool: String {
    case knife, scorer, hand, glue, none

    var title: String {
        switch self {
        case .knife: return "Craft Knife"
        case .scorer: return "Bone Folder"
        case .hand: return "Hands"
        case .glue: return "Glue"
        case .none: return ""
        }
    }

    var iconKey: String? {
        switch self {
        case .knife: return "tool.knife"
        case .glue: return "tool.glue"
        case .scorer: return "tool.ruler"
        case .hand, .none: return nil
        }
    }

    var symbol: String {
        switch self {
        case .hand: return "hand.draw.fill"
        case .scorer: return "ruler.fill"
        case .glue: return "drop.fill"
        default: return "scissors"
        }
    }
}

/// State of the crafting HUD. Sessions write it; SwiftUI renders it.
@MainActor
final class HUDModel: ObservableObject {
    @Published var stepIndex = 1
    @Published var stepCount = 6
    @Published var title = ""
    @Published var instruction = ""
    @Published var tool: HUDTool = .knife
    @Published var showLegend = true
    @Published var nextVisible = false
    @Published var nextTitle = "Next"
    /// e.g. "Blade · 1 of 3".
    @Published var detail: String?
    /// Bumps whenever the title changes so SwiftUI can animate it.
    @Published private(set) var titleID = 0

    private(set) var nextTapped = false

    func set(step: Int? = nil, title: String, instruction: String, tool: HUDTool? = nil, detail: String? = nil) {
        if let step { stepIndex = step }
        self.title = title
        self.instruction = instruction
        if let tool { self.tool = tool }
        self.detail = detail
        titleID += 1
    }

    func armNext(_ title: String = "Next") {
        nextTapped = false
        nextTitle = title
        nextVisible = true
    }

    func tapNext() {
        guard nextVisible else { return }
        nextVisible = false
        nextTapped = true
    }

    func reset(steps: Int) {
        stepIndex = 1
        stepCount = steps
        title = ""
        instruction = ""
        detail = nil
        nextVisible = false
        nextTapped = false
    }
}
