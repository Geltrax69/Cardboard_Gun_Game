import UIKit

/// Procedural textures, drawn once at launch. Flat colors only — no gradients.
enum Textures {
    private static func render(_ size: CGSize, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in draw(ctx.cgContext) }
    }

    /// Cutting mat: flat teal with a subtle 1-unit grid, 5-unit major lines and ruler
    /// numbers along the bottom and left margins. `size` is in world units.
    static func cuttingMat(size: CGSize, pixelsPerUnit ppu: CGFloat = 64, margin: CGFloat = 1.3) -> UIImage {
        let px = CGSize(width: size.width * ppu, height: size.height * ppu)
        return render(px) { g in
            g.setFillColor(Palette.mat.cgColor)
            g.fill(CGRect(origin: .zero, size: px))
            let inner = CGRect(x: margin * ppu, y: margin * 0.7 * ppu,
                               width: (size.width - margin * 1.7) * ppu, height: (size.height - margin * 1.7) * ppu)
            let cols = Int((inner.width / ppu).rounded(.down))
            let rows = Int((inner.height / ppu).rounded(.down))
            let grid = CGRect(x: inner.minX, y: inner.minY, width: CGFloat(cols) * ppu, height: CGFloat(rows) * ppu)
            g.setStrokeColor(Palette.matLine.withAlphaComponent(0.55).cgColor)
            g.setLineWidth(2)
            for c in 0...cols {
                let x = grid.minX + CGFloat(c) * ppu
                g.move(to: CGPoint(x: x, y: grid.minY)); g.addLine(to: CGPoint(x: x, y: grid.maxY))
            }
            for r in 0...rows {
                let y = grid.minY + CGFloat(r) * ppu
                g.move(to: CGPoint(x: grid.minX, y: y)); g.addLine(to: CGPoint(x: grid.maxX, y: y))
            }
            g.strokePath()
            g.setStrokeColor(Palette.matLine.cgColor)
            g.setLineWidth(3.5)
            for c in stride(from: 0, through: cols, by: 5) {
                let x = grid.minX + CGFloat(c) * ppu
                g.move(to: CGPoint(x: x, y: grid.minY)); g.addLine(to: CGPoint(x: x, y: grid.maxY))
            }
            for r in stride(from: 0, through: rows, by: 5) {
                let y = grid.maxY - CGFloat(r) * ppu
                g.move(to: CGPoint(x: grid.minX, y: y)); g.addLine(to: CGPoint(x: grid.maxX, y: y))
            }
            g.strokePath()
            // Ruler ticks + numbers.
            let font = UIFont.systemFont(ofSize: ppu * 0.42, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.matLine]
            g.setStrokeColor(Palette.matLine.cgColor)
            g.setLineWidth(2)
            for c in 0...(cols * 2) {
                let x = grid.minX + CGFloat(c) * ppu / 2
                let len: CGFloat = c % 10 == 0 ? 0.42 : (c % 2 == 0 ? 0.26 : 0.14)
                g.move(to: CGPoint(x: x, y: grid.maxY)); g.addLine(to: CGPoint(x: x, y: grid.maxY + len * ppu))
            }
            for r in 0...(rows * 2) {
                let y = grid.maxY - CGFloat(r) * ppu / 2
                let len: CGFloat = r % 10 == 0 ? 0.42 : (r % 2 == 0 ? 0.26 : 0.14)
                g.move(to: CGPoint(x: grid.minX, y: y)); g.addLine(to: CGPoint(x: grid.minX - len * ppu, y: y))
            }
            g.strokePath()
            UIGraphicsPushContext(g)
            for c in stride(from: 0, through: cols, by: 5) {
                let s = NSAttributedString(string: "\(c)", attributes: attrs)
                let w = s.size()
                s.draw(at: CGPoint(x: grid.minX + CGFloat(c) * ppu - w.width / 2, y: grid.maxY + 0.5 * ppu))
            }
            for r in stride(from: 5, through: rows, by: 5) {
                let s = NSAttributedString(string: "\(r)", attributes: attrs)
                let w = s.size()
                s.draw(at: CGPoint(x: grid.minX - 0.55 * ppu - w.width, y: grid.maxY - CGFloat(r) * ppu - w.height / 2))
            }
            UIGraphicsPopContext()
        }
    }

    private static var corrugationCache: [String: UIImage] = [:]

    /// Cardboard edge: dark board with a zig-zag flute and ink liners top and bottom.
    /// Repeats horizontally once per flute period; symmetric vertically.
    static func corrugation(_ stock: CardboardStock) -> UIImage {
        if let img = corrugationCache[stock.id] { return img }
        let size = CGSize(width: 64, height: 32)
        let img = render(size) { g in
            g.setFillColor(UIColor(hex: stock.side).cgColor)
            g.fill(CGRect(origin: .zero, size: size))
            g.setStrokeColor(UIColor(hex: stock.flute).cgColor)
            g.setLineWidth(4)
            g.setLineJoin(.miter)
            g.move(to: CGPoint(x: 0, y: 26))
            g.addLine(to: CGPoint(x: 16, y: 6))
            g.addLine(to: CGPoint(x: 32, y: 26))
            g.addLine(to: CGPoint(x: 48, y: 6))
            g.addLine(to: CGPoint(x: 64, y: 26))
            g.strokePath()
            g.setFillColor(Palette.ink.cgColor)
            g.fill(CGRect(x: 0, y: 0, width: 64, height: 3))
            g.fill(CGRect(x: 0, y: 29, width: 64, height: 3))
        }
        corrugationCache[stock.id] = img
        return img
    }

    /// Yellow ruler face with tick marks and numbers (image top = far edge).
    static func ruler(lengthUnits: CGFloat, widthUnits: CGFloat, ppu: CGFloat = 60) -> UIImage {
        let size = CGSize(width: widthUnits * ppu, height: lengthUnits * ppu)
        return render(size) { g in
            g.setFillColor(Palette.yellow.cgColor)
            g.fill(CGRect(origin: .zero, size: size))
            g.setStrokeColor(Palette.ink.withAlphaComponent(0.8).cgColor)
            g.setLineWidth(2)
            let count = Int(lengthUnits * 4)
            for i in 1..<count {
                let y = CGFloat(i) * ppu / 4
                let len: CGFloat = i % 4 == 0 ? 0.42 : (i % 2 == 0 ? 0.28 : 0.16)
                g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: len * ppu, y: y))
            }
            g.strokePath()
            let font = UIFont.systemFont(ofSize: ppu * 0.3, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.ink]
            UIGraphicsPushContext(g)
            for i in stride(from: 1, to: Int(lengthUnits), by: 1) {
                let s = NSAttributedString(string: "\(i)", attributes: attrs)
                let w = s.size()
                s.draw(at: CGPoint(x: 0.5 * ppu, y: CGFloat(i) * ppu - w.height / 2))
            }
            UIGraphicsPopContext()
        }
    }
}
