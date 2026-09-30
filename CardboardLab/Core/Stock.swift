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

    public static let plain = CardboardStock(
        id: "plain", name: "Plain Cardboard", blurb: "Start with a simple sheet",
        top: "#E2A652", under: "#E9B25F", side: "#B17330", flute: "#8A5521", thickness: 0.14, price: 0)

    public static let corrugated = CardboardStock(
        id: "corrugated", name: "Corrugated Cardboard", blurb: "Stronger and detailed",
        top: "#DC9D4A", under: "#E6AC5C", side: "#A96B2B", flute: "#77481B", thickness: 0.2, price: 150)

    public static let colored = CardboardStock(
        id: "colored", name: "Colored Cardboard", blurb: "Unlock new designs",
        top: "#C8674A", under: "#D27A5C", side: "#8E4630", flute: "#6C3222", thickness: 0.14, price: 300)

    public static let all: [CardboardStock] = [.plain, .corrugated, .colored]

    public static func byID(_ id: String) -> CardboardStock { all.first { $0.id == id } ?? .plain }
}
