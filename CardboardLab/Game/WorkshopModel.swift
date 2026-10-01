import Combine
import Foundation

/// Things the workshop UI asks the session to do.
enum WorkshopCommand: Equatable {
    case newSheet
    case undo
    case clearAll
    case resetView
    case toggleView
    /// Lines mode: close the shape drawn so far / remove the last point.
    case closeShape
    case undoPoint
    case move(WorkshopModel.MoveAction)
}

/// UI state of free mode: the active tool and its options, the paint colour, the
/// selection and a status line. The session owns the actual work.
@MainActor
final class WorkshopModel: ObservableObject {
    enum Tool: String, CaseIterable {
        case cut, crease, fold, paint, move, glue, view

        var title: String {
            switch self {
            case .cut: return "Cut"
            case .crease: return "Fold line"
            case .fold: return "Fold"
            case .paint: return "Paint"
            case .move: return "Move"
            case .glue: return "Glue"
            case .view: return "Look"
            }
        }

        var symbol: String {
            switch self {
            case .cut: return "scissors"
            case .crease: return "line.diagonal"
            case .fold: return "arrow.uturn.up"
            case .paint: return "paintbrush.fill"
            case .move: return "hand.draw.fill"
            case .glue: return "drop.fill"
            case .view: return "eye.fill"
            }
        }

        /// What to do with this tool, shown under the title.
        var help: String {
            switch self {
            case .cut: return "Draw a closed shape on a sheet, then cut along the red line."
            case .crease: return "Drag a line across a piece to add a blue fold line."
            case .fold: return "Grab a flap next to a fold line and drag it up or down."
            case .paint: return "Pick a colour, then tap or brush over faces and sheets."
            case .move: return "Drag a piece to move it. Tap one to turn, tilt, copy or delete it."
            case .glue: return "Tap a piece, then tap the piece to stick it onto."
            case .view: return "Drag to slide around the table · two fingers to turn · pinch to zoom."
            }
        }
    }

    enum Shape: String, CaseIterable {
        case freehand, lines, rectangle, circle

        var title: String {
            switch self {
            case .freehand: return "Freehand"
            case .lines: return "Straight lines"
            case .rectangle: return "Rectangle"
            case .circle: return "Circle"
            }
        }

        var symbol: String {
            switch self {
            case .freehand: return "scribble"
            case .lines: return "triangle"
            case .rectangle: return "rectangle"
            case .circle: return "circle"
            }
        }
    }

    enum MoveAction: String, CaseIterable {
        case turn, tilt, roll, raise, lower, flip, drop, copy, unglue, delete

        var title: String {
            switch self {
            case .turn: return "Turn"
            case .tilt: return "Tilt"
            case .roll: return "Roll"
            case .raise: return "Up"
            case .lower: return "Down"
            case .flip: return "Flip"
            case .drop: return "To mat"
            case .copy: return "Copy"
            case .unglue: return "Unglue"
            case .delete: return "Delete"
            }
        }

        var symbol: String {
            switch self {
            case .turn: return "arrow.clockwise"
            case .tilt: return "rotate.3d"
            case .roll: return "arrow.triangle.2.circlepath"
            case .raise: return "arrow.up"
            case .lower: return "arrow.down"
            case .flip: return "arrow.up.arrow.down"
            case .drop: return "arrow.down.to.line"
            case .copy: return "plus.square.on.square"
            case .unglue: return "scissors"
            case .delete: return "trash.fill"
            }
        }
    }

    @Published var tool: Tool = .cut {
        didSet { if tool != oldValue { onToolChange?(tool) } }
    }
    @Published var shape: Shape = .freehand {
        didSet { if shape != oldValue { onToolChange?(tool) } }
    }
    /// The knife cuts the shape by itself instead of the player tracing it.
    @Published var quickCut = false
    /// Paint every panel of a piece at once.
    @Published var paintWhole = false

    // Colour (HSB, 0…1).
    @Published var hue: Float = 0.02
    @Published var saturation: Float = 0.72
    @Published var brightness: Float = 0.96
    @Published private(set) var recent: [PaintColor] = []

    @Published var status = ""
    @Published var busy = false
    @Published var hasSelection = false
    @Published var selectionGlued = false
    @Published var canUndo = false
    /// Straight-lines mode: points placed so far.
    @Published var linePoints = 0
    @Published var topView = false
    @Published var showHelp = false

    /// Set by the session.
    var send: ((WorkshopCommand) -> Void)?
    var onToolChange: ((Tool) -> Void)?

    var color: PaintColor { PaintColor(hue: hue, saturation: saturation, brightness: brightness) }

    func pick(_ c: PaintColor) {
        let hsb = c.hsb
        hue = hsb.h
        saturation = hsb.s
        brightness = hsb.b
    }

    /// Remembers a colour once it's been used.
    func used(_ c: PaintColor) {
        recent.removeAll { $0 == c }
        recent.insert(c, at: 0)
        if recent.count > 8 { recent.removeLast(recent.count - 8) }
    }

    /// Ready-made shades: the game palette, cardboard tones, greys.
    static let swatches: [PaintColor] = [
        "#F46359", "#FADC70", "#97E1BE", "#67C2E2", "#0E6762", "#083739",
        "#E2A652", "#F3C274", "#B17330", "#F8F7EF", "#9AA5A8", "#0D2730",
    ].map { PaintColor(hex: $0) }
}
