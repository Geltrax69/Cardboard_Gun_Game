import SwiftUI

/// Rounded, chunky type used everywhere.
enum LabFont {
    static func heavy(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func bold(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func semibold(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func black(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
}

/// Buttons shrink a little while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Dark panel used for menu shelves.
struct LabPanel<Content: View>: View {
    var scale: CGFloat = 1
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16 * scale)
            .background(RoundedRectangle(cornerRadius: 24 * scale, style: .continuous).fill(Color.labInk.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 24 * scale, style: .continuous).stroke(Color.labMat, lineWidth: 2))
    }
}

/// Square icon button (home, settings).
struct RoundIconButton: View {
    let systemName: String
    var size: CGFloat = 60
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundStyle(Color.labPaper)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Color.labInk))
                .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).stroke(Color.labMat, lineWidth: 3))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Round home button with a mint ring (top-left of the crafting HUD).
struct HomeButton: View {
    var size: CGFloat = 64
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "house.fill")
                .font(.system(size: size * 0.4, weight: .heavy))
                .foregroundStyle(Color.labPaper)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.labMat))
                .overlay(Circle().stroke(Color.labMint, lineWidth: 4))
                .overlay(Circle().stroke(Color.labInk, lineWidth: 1.5).padding(-2))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Home")
    }
}

struct CoinIcon: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(Color.labYellow)
            Circle().stroke(Color.labInk, lineWidth: max(2, size * 0.09))
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.5, weight: .black))
                .foregroundStyle(Color.labCardboardDark)
        }
        .frame(width: size, height: size)
    }
}

/// "★ 120 [+]" balance chip.
struct CoinBadge: View {
    let coins: Int
    var scale: CGFloat = 1
    var showPlus = true
    var onPlus: () -> Void = {}

    var body: some View {
        HStack(spacing: 10 * scale) {
            CoinIcon(size: 36 * scale)
            Text("\(coins)")
                .font(LabFont.heavy(28 * scale))
                .monospacedDigit()
                .foregroundStyle(Color.labPaper)
                .contentTransition(.numericText())
                .frame(minWidth: 56 * scale)
            if showPlus {
                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .font(.system(size: 20 * scale, weight: .black))
                        .foregroundStyle(Color.labPaper)
                        .frame(width: 40 * scale, height: 40 * scale)
                        .background(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous).fill(Color.labRed))
                        .overlay(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous).stroke(Color.labInk, lineWidth: 2))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.leading, 10 * scale)
        .padding(.trailing, showPlus ? 8 * scale : 18 * scale)
        .padding(.vertical, 8 * scale)
        .background(Capsule().fill(Color.labInk.opacity(0.9)))
        .overlay(Capsule().stroke(Color.labMat, lineWidth: 2))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: coins)
    }
}

/// Text with a chunky ink outline and a dropped "extrusion", like cut cardboard letters.
struct OutlinedText: View {
    let text: String
    let font: Font
    var fill: Color = .labCardboardLight
    var outline: Color = .labInk
    var width: CGFloat = 3
    var depth: CGFloat = 5

    var body: some View {
        ZStack {
            ForEach(0..<8) { i in
                let a = Double(i) / 8 * 2 * Double.pi
                Text(text).font(font).foregroundStyle(outline)
                    .offset(x: CGFloat(cos(a)) * width, y: CGFloat(sin(a)) * width + depth)
            }
            ForEach(0..<8) { i in
                let a = Double(i) / 8 * 2 * Double.pi
                Text(text).font(font).foregroundStyle(outline)
                    .offset(x: CGFloat(cos(a)) * width, y: CGFloat(sin(a)) * width)
            }
            Text(text).font(font).foregroundStyle(fill)
        }
    }
}

/// CARDBOARD LAB logo: individually tilted cardboard letters.
struct CardboardTitle: View {
    var scale: CGFloat = 1
    private let tilts: [Double] = [-4, 3, -2, 4, -3, 2, -4, 3, -2]

    var body: some View {
        VStack(alignment: .leading, spacing: -6 * scale) {
            HStack(spacing: -1 * scale) {
                ForEach(Array("CARDBOARD".enumerated()), id: \.offset) { item in
                    OutlinedText(text: String(item.element), font: LabFont.black(58 * scale),
                                 fill: item.offset % 2 == 0 ? .labCardboardLight : .labCardboard,
                                 width: 3 * scale, depth: 6 * scale)
                        .rotationEffect(.degrees(tilts[item.offset % tilts.count]))
                }
            }
            HStack(alignment: .center, spacing: 14 * scale) {
                OutlinedText(text: "LAB", font: LabFont.black(62 * scale), fill: .labPaper, width: 3 * scale, depth: 6 * scale)
                    .rotationEffect(.degrees(-2))
                Text("CUT · FOLD · GLUE · CREATE")
                    .font(LabFont.heavy(15 * scale))
                    .tracking(3 * scale)
                    .foregroundStyle(Color.labPaper)
                    .padding(.top, 10 * scale)
            }
            .padding(.leading, 40 * scale)
        }
    }
}

/// Little dashed blue sample line.
struct DashedLine: View {
    var color: Color = .labBlue
    var dash: CGFloat = 12
    var gap: CGFloat = 7
    var count: Int = 4
    var thickness: CGFloat = 5

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { _ in
                Capsule().fill(color).frame(width: dash, height: thickness)
            }
        }
    }
}

/// Paper sticky note: RED = CUT, BLUE = FOLD.
struct LegendNote: View {
    var scale: CGFloat = 1
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: (compact ? 6 : 10) * scale) {
            HStack(spacing: 12 * scale) {
                Capsule().fill(Color.labRed).frame(width: 58 * scale, height: 6 * scale)
                Text(compact ? "RED = CUT" : "Red = Cut").font(LabFont.heavy((compact ? 15 : 20) * scale)).foregroundStyle(Color.labInk)
            }
            HStack(spacing: 12 * scale) {
                DashedLine(dash: 11 * scale, gap: 5 * scale, count: 4, thickness: 5 * scale)
                    .frame(width: 58 * scale, alignment: .leading)
                Text(compact ? "BLUE = FOLD" : "Blue = Fold").font(LabFont.heavy((compact ? 15 : 20) * scale)).foregroundStyle(Color.labInk)
            }
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, (compact ? 10 : 16) * scale)
        .background(RoundedRectangle(cornerRadius: 6 * scale).fill(Color.labPaper))
        .overlay(RoundedRectangle(cornerRadius: 6 * scale).stroke(Color.labInk, lineWidth: 2))
        .overlay(alignment: .top) {
            if !compact {
                Rectangle().fill(Color.labYellow.opacity(0.85))
                    .frame(width: 60 * scale, height: 18 * scale)
                    .rotationEffect(.degrees(-6))
                    .offset(x: -40 * scale, y: -10 * scale)
            }
        }
        .rotationEffect(.degrees(compact ? 0 : -2.5))
    }
}

/// Floating feedback text.
struct ToastView: View {
    let toast: Toast
    var scale: CGFloat = 1

    var body: some View {
        switch toast.style {
        case .reward:
            OutlinedText(text: toast.text, font: LabFont.black(34 * scale), fill: .labYellow, width: 3 * scale, depth: 4 * scale)
        case .success:
            HStack(spacing: 8 * scale) {
                Image(systemName: "checkmark").font(.system(size: 18 * scale, weight: .black))
                Text(toast.text).font(LabFont.heavy(22 * scale))
            }
            .foregroundStyle(Color.labInk)
            .padding(.horizontal, 18 * scale).padding(.vertical, 10 * scale)
            .background(Capsule().fill(Color.labMint))
            .overlay(Capsule().stroke(Color.labInk, lineWidth: 2.5))
        case .hint:
            HStack(spacing: 8 * scale) {
                Image(systemName: "hand.point.up.left.fill").font(.system(size: 18 * scale, weight: .bold))
                Text(toast.text).font(LabFont.bold(19 * scale))
            }
            .foregroundStyle(Color.labInk)
            .padding(.horizontal, 18 * scale).padding(.vertical, 10 * scale)
            .background(Capsule().fill(Color.labPaper))
            .overlay(Capsule().stroke(Color.labInk, lineWidth: 2))
        case .info:
            Text(toast.text)
                .font(LabFont.bold(19 * scale))
                .foregroundStyle(Color.labPaper)
                .padding(.horizontal, 18 * scale).padding(.vertical, 10 * scale)
                .background(Capsule().fill(Color.labInk.opacity(0.92)))
                .overlay(Capsule().stroke(Color.labMat, lineWidth: 2))
        }
    }
}

/// Renders every live toast; positioned ones rise from their anchor.
struct ToastLayer: View {
    @EnvironmentObject var engine: GameEngine
    var scale: CGFloat = 1
    var defaultY: CGFloat

    var body: some View {
        GeometryReader { geo in
            if !engine.toasts.isEmpty {
                TimelineView(.animation) { _ in
                    ZStack {
                        ForEach(engine.toasts) { t in
                            let age = engine.time - t.born
                            let pop = min(1, age / 0.18)
                            let rise = CGFloat(min(age, 1.2) * 40)
                            let fade = age > t.life - 0.35 ? max(0, (t.life - age) / 0.35) : 1
                            ToastView(toast: t, scale: scale)
                                .scaleEffect(CGFloat(0.6 + 0.4 * pop))
                                .position(x: t.position?.x ?? geo.size.width / 2,
                                          y: (t.position?.y ?? defaultY) - rise)
                                .opacity(fade)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Chunky slider: label and value on top, a draggable track below.
struct LabSlider: View {
    let title: String
    let value: Float
    let range: ClosedRange<Float>
    let format: (Float) -> String
    let scale: CGFloat
    let onChange: (Float) -> Void

    var body: some View {
        let s = scale
        let span = max(range.upperBound - range.lowerBound, 1e-4)
        let k = CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack {
                Text(title).font(LabFont.heavy(14 * s)).foregroundStyle(Color.labPaper)
                Spacer()
                Text(format(value)).font(LabFont.heavy(14 * s)).monospacedDigit().foregroundStyle(Color.labYellow)
            }
            GeometryReader { g in
                let w = g.size.width
                let knob = 28 * s
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.labInk)
                        .frame(height: 12 * s)
                    Capsule().fill(Color.labBlue)
                        .frame(width: max(12 * s, (w - knob) * k + knob / 2), height: 12 * s)
                    Circle().fill(Color.labPaper)
                        .overlay(Circle().stroke(Color.labInk, lineWidth: 2.5))
                        .frame(width: knob, height: knob)
                        .offset(x: (w - knob) * k)
                }
                .frame(height: knob)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let f = Float(min(1, max(0, (v.location.x - knob / 2) / max(w - knob, 1))))
                    onChange(range.lowerBound + span * f)
                })
            }
            .frame(height: 28 * s)
        }
    }
}
