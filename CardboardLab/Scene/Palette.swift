import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(s, radix: 16) ?? 0
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Cardboard Lab color system. Every color in the game comes from here.
enum Palette {
    static let table = UIColor(hex: "#083739")
    static let mat = UIColor(hex: "#0E6762")
    static let cardboard = UIColor(hex: "#E2A652")
    static let cardboardLight = UIColor(hex: "#F3C274")
    static let cardboardDark = UIColor(hex: "#B17330")
    static let ink = UIColor(hex: "#0D2730")
    static let red = UIColor(hex: "#F46359")
    static let blue = UIColor(hex: "#67C2E2")
    static let mint = UIColor(hex: "#97E1BE")
    static let yellow = UIColor(hex: "#FADC70")
    static let paper = UIColor(hex: "#F8F7EF")

    // Derived tones (mixes of the palette, used sparingly).
    static let matLine = UIColor(hex: "#2E8A80")
    static let matSide = UIColor(hex: "#0A4E4B")
    static let steel = UIColor(hex: "#D5DFE2")
    static let steelDark = UIColor(hex: "#8FA3AB")
    static let redMuted = UIColor(hex: "#C98A73")
    static let glue = UIColor(hex: "#FDFDF8")
}

extension Color {
    init(hex: String, alpha: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: CGFloat(alpha)))
    }

    static let labTable = Color(uiColor: Palette.table)
    static let labMat = Color(uiColor: Palette.mat)
    static let labCardboard = Color(uiColor: Palette.cardboard)
    static let labCardboardLight = Color(uiColor: Palette.cardboardLight)
    static let labCardboardDark = Color(uiColor: Palette.cardboardDark)
    static let labInk = Color(uiColor: Palette.ink)
    static let labRed = Color(uiColor: Palette.red)
    static let labBlue = Color(uiColor: Palette.blue)
    static let labMint = Color(uiColor: Palette.mint)
    static let labYellow = Color(uiColor: Palette.yellow)
    static let labPaper = Color(uiColor: Palette.paper)
}
