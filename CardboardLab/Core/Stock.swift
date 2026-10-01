import Foundation

/// Cardboard the player crafts with. Colors are hex strings so this stays platform-free.
public struct CardboardStock: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let blurb: String
    public let top: String
    public let under: String
    public let side: String
    public let flute: String
    public let thickness: Float
    public let price: Int
    /// The texture pressed into the printed face.
    public let surface: CardboardSurface
    /// The inside face (coated boards are plain brown inside, old boxes just scuffed).
    public let underSurface: CardboardSurface
    /// Two layers of flutes on the cut edge.
    public var doubleWall: Bool { thickness > 0.21 }

    public static let plain = CardboardStock(
        id: "plain", name: "Plain Cardboard", blurb: "Start with a simple sheet",
        top: "#E2A652", under: "#E9B25F", side: "#B17330", flute: "#8A5521", thickness: 0.14, price: 0,
        surface: .smooth, underSurface: .smooth)

    public static let corrugated = CardboardStock(
        id: "corrugated", name: "Corrugated Cardboard", blurb: "Stronger and detailed",
        top: "#DC9D4A", under: "#E6AC5C", side: "#A96B2B", flute: "#77481B", thickness: 0.2, price: 150,
        surface: .ribbed, underSurface: .ribbed)

    public static let colored = CardboardStock(
        id: "colored", name: "Colored Cardboard", blurb: "Unlock new designs",
        top: "#C8674A", under: "#D27A5C", side: "#8E4630", flute: "#6C3222", thickness: 0.14, price: 300,
        surface: .smooth, underSurface: .smooth)

    public static let kraft = CardboardStock(
        id: "kraft", name: "Kraft Board", blurb: "Long brown fibres",
        top: "#B98049", under: "#C48D55", side: "#8C5A2C", flute: "#5E3A1A", thickness: 0.17, price: 450,
        surface: .kraft, underSurface: .kraft)

    public static let recycled = CardboardStock(
        id: "recycled", name: "Recycled Board", blurb: "Grey and flecked",
        top: "#A79F92", under: "#B4AC9F", side: "#7D766B", flute: "#59534A", thickness: 0.14, price: 600,
        surface: .speckled, underSurface: .speckled)

    public static let white = CardboardStock(
        id: "white", name: "White Coated", blurb: "Crisp, bright and smooth",
        top: "#EFEBE1", under: "#D9B985", side: "#B58A55", flute: "#8A6436", thickness: 0.14, price: 750,
        surface: .coated, underSurface: .kraft)

    public static let black = CardboardStock(
        id: "black", name: "Black Board", blurb: "Stealthy and sleek",
        top: "#3E3936", under: "#4B4542", side: "#2C2725", flute: "#191513", thickness: 0.14, price: 900,
        surface: .coated, underSurface: .smooth)

    public static let rough = CardboardStock(
        id: "rough", name: "Rough Board", blurb: "Scuffed, dented and tough",
        top: "#C78D4F", under: "#CF9A5E", side: "#94602F", flute: "#66401C", thickness: 0.2, price: 1100,
        surface: .rough, underSurface: .rough)

    public static let oldBox = CardboardStock(
        id: "oldBox", name: "Old Shipping Box", blurb: "Tape, stains and stamps",
        top: "#BE915C", under: "#CDA16B", side: "#8E663A", flute: "#634422", thickness: 0.2, price: 1300,
        surface: .worn, underSurface: .rough)

    public static let doubleWallBoard = CardboardStock(
        id: "doubleWall", name: "Double Wall", blurb: "Extra thick and sturdy",
        top: "#D69C4F", under: "#DDA75E", side: "#A56A2C", flute: "#74461A", thickness: 0.22, price: 1600,
        surface: .ribbed, underSurface: .ribbed)

    public static let all: [CardboardStock] = [
        .plain, .corrugated, .colored, .kraft, .recycled, .white, .black, .rough, .oldBox, .doubleWallBoard,
    ]

    public static func byID(_ id: String) -> CardboardStock { all.first { $0.id == id } ?? .plain }

    /// Every board thickness in the game (blueprints are validated against each).
    public static var thicknesses: [Float] { Array(Set(all.map(\.thickness))).sorted() }
}
