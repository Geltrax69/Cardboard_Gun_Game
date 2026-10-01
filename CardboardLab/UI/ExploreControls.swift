import SwiftUI

/// Turns hand mode on and off: while it's on, touches move the camera instead of the
/// tool, so you can look at what you're making from anywhere.
struct HandButton: View {
    @EnvironmentObject var engine: GameEngine
    var size: CGFloat = 50

    var body: some View {
        let on = engine.handMode
        Button {
            engine.toggleHandMode()
        } label: {
            Image(systemName: on ? "hand.raised.fill" : "hand.raised")
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundStyle(on ? Color.labInk : Color.labPaper)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(on ? Color.labYellow : Color.labInk))
                .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).stroke(on ? Color.labInk : Color.labMat, lineWidth: 3))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(on ? "Stop exploring" : "Explore with the hand")
    }
}

/// Hand mode controls: a joystick that walks the camera across the table (push up to
/// go forward) and hold buttons that float it up and down.
struct ExplorePad: View {
    @EnvironmentObject var engine: GameEngine
    let scale: CGFloat
    @State private var knob = CGSize.zero
    @State private var stick = V2(0, 0)
    @State private var rise: Float = 0

    var body: some View {
        let s = scale
        let r = 62 * s
        let reach = r * 0.62
        HStack(alignment: .center, spacing: 12 * s) {
            ZStack {
                Circle().fill(Color.labInk.opacity(0.88))
                Circle().stroke(Color.labMat, lineWidth: 2.5)
                ForEach(0..<4, id: \.self) { i in
                    let a = Double(i) * .pi / 2
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14 * s, weight: .heavy))
                        .foregroundStyle(Color.labPaper.opacity(0.55))
                        .rotationEffect(.radians(a))
                        .offset(x: CGFloat(sin(a)) * r * 0.78, y: -CGFloat(cos(a)) * r * 0.78)
                }
                Circle()
                    .fill(Color.labYellow)
                    .frame(width: 50 * s, height: 50 * s)
                    .overlay(Circle().stroke(Color.labInk, lineWidth: 2.5))
                    .overlay(Image(systemName: "figure.walk")
                        .font(.system(size: 20 * s, weight: .heavy))
                        .foregroundStyle(Color.labInk))
                    .offset(knob)
            }
            .frame(width: 2 * r, height: 2 * r)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    var d = v.translation
                    let len = (d.width * d.width + d.height * d.height).squareRoot()
                    if len > reach {
                        d = CGSize(width: d.width / len * reach, height: d.height / len * reach)
                    }
                    knob = d
                    stick = V2(Float(d.width / reach), Float(-d.height / reach))
                    push()
                }
                .onEnded { _ in
                    knob = .zero
                    stick = V2(0, 0)
                    push()
                })
            VStack(spacing: 10 * s) {
                holdButton("arrow.up", "Up", 1, s)
                holdButton("arrow.down", "Down", -1, s)
            }
        }
        .onDisappear { engine.walkInput = V3(0, 0, 0) }
    }

    private func push() {
        engine.walkInput = V3(stick.x, rise, stick.y)
    }

    /// Floats the camera while held.
    private func holdButton(_ icon: String, _ title: String, _ value: Float, _ s: CGFloat) -> some View {
        let on = rise == value
        return VStack(spacing: 2 * s) {
            Image(systemName: icon).font(.system(size: 18 * s, weight: .heavy))
            Text(title).font(LabFont.heavy(11 * s))
        }
        .foregroundStyle(on ? Color.labInk : Color.labPaper)
        .frame(width: 56 * s, height: 54 * s)
        .background(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(on ? Color.labYellow : Color.labInk.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).stroke(on ? Color.labInk : Color.labMat, lineWidth: 2))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if rise != value {
                    rise = value
                    push()
                }
            }
            .onEnded { _ in
                rise = 0
                push()
            })
    }
}

/// The hint shown while exploring.
struct ExploreHint: View {
    let scale: CGFloat

    var body: some View {
        let s = scale
        HStack(spacing: 14 * s) {
            hint("hand.point.up.left.fill", "Drag to look", s)
            hint("hand.draw.fill", "Two fingers to move", s)
            hint("arrow.up.left.and.arrow.down.right", "Pinch to zoom", s)
            hint("hand.tap.fill", "Double-tap to fly there", s)
        }
        .padding(.horizontal, 16 * s)
        .padding(.vertical, 9 * s)
        .background(Capsule().fill(Color.labInk.opacity(0.88)))
        .overlay(Capsule().stroke(Color.labYellow, lineWidth: 2))
        .allowsHitTesting(false)
    }

    private func hint(_ icon: String, _ text: String, _ s: CGFloat) -> some View {
        HStack(spacing: 5 * s) {
            Image(systemName: icon).font(.system(size: 13 * s, weight: .bold)).foregroundStyle(Color.labYellow)
            Text(text).font(LabFont.heavy(13 * s)).foregroundStyle(Color.labPaper)
        }
    }
}
