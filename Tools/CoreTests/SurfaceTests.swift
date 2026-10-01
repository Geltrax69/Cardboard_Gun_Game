import Foundation

// Procedural cardboard surfaces: right size, repeatable, seamless, and every stock
// points at one.
func runSurfaceTests() {
    let n = SurfaceTexture.size
    for surface in CardboardSurface.allCases {
        let m = SurfaceTexture.maps(surface)
        check(m.detail.count == n * n * 4 && m.normal.count == n * n * 4, "\(surface): map size")
        check(SurfaceTexture.maps(surface).detail == m.detail, "\(surface): same texture every launch")
        // Mostly clean board: the average detail stays bright so stock colours read true.
        var sum = 0.0
        for i in stride(from: 0, to: m.detail.count, by: 4) { sum += Double(m.detail[i]) }
        let mean = sum / Double(n * n) / 255
        check(mean > 0.78 && mean <= 1, "\(surface): detail too dark (\(mean))")
        // Normals face out of the board.
        var minZ = 255
        for i in stride(from: 2, to: m.normal.count, by: 4) { minZ = min(minZ, Int(m.normal[i])) }
        check(minZ > 160, "\(surface): normals tilt too far (\(minZ))")
        // Seamless: the jump across the wrap is no bigger than between ordinary neighbours.
        func px(_ x: Int, _ y: Int) -> Int { Int(m.detail[(y * n + x) * 4]) }
        var inner = 0, seam = 0
        for y in 0..<n {
            seam += abs(px(n - 1, y) - px(0, y))
            inner += abs(px(n / 2 - 1, y) - px(n / 2, y))
        }
        for x in 0..<n {
            seam += abs(px(x, n - 1) - px(x, 0))
            inner += abs(px(x, n / 2 - 1) - px(x, n / 2))
        }
        check(Double(seam) < Double(inner) * 2 + Double(2 * n), "\(surface): visible seam (\(seam) vs \(inner))")
    }
    var ids = Set<String>()
    for stock in CardboardStock.all {
        check(ids.insert(stock.id).inserted, "duplicate stock id \(stock.id)")
        check(CardboardStock.byID(stock.id) == stock, "\(stock.id): lookup")
        check(stock.thickness >= 0.12 && stock.thickness <= 0.3, "\(stock.id): thickness")
    }
    check(CardboardStock.all.first?.price == 0, "the first board is free")
    check(zip(CardboardStock.all, CardboardStock.all.dropFirst()).allSatisfy { $0.price < $1.price }, "boards get pricier")
    print("surfaces: ok (\(CardboardSurface.allCases.count) surfaces, \(CardboardStock.all.count) boards)")
}
