import SwiftUI

/// "How to build the Knife": eight illustrated steps rendered from the real 3D pieces,
/// plus the line and fold legend. Shown before the first knife, from the menu, the
/// crafting HUD (?) and Settings.
struct GuideView: View {
    @EnvironmentObject var engine: GameEngine
    @EnvironmentObject var icons: IconFactory
    let scale: CGFloat

    struct Step: Identifiable {
        let id: Int
        let title: String
        let text: String
    }

    static let knifeSteps: [Step] = [
        Step(id: 1, title: "Cut the shape", text: "Cut along the solid red lines. Punch out the two small holes."),
        Step(id: 2, title: "Score the creases", text: "Run the bone folder along every blue dashed line."),
        Step(id: 3, title: "Fold the walls", text: "Fold the walls and end cap up, then tuck the glue tab in."),
        Step(id: 4, title: "Add glue", text: "Lay a bead of glue along the tucked-in tab."),
        Step(id: 5, title: "Close the top", text: "Fold the lid onto the glued tab until it snaps."),
        Step(id: 6, title: "Fold the blade", text: "Pinch a ridge along the spine, then glue the tang."),
        Step(id: 7, title: "Connect the pieces", text: "Slide the blade into the handle and wrap the guard band."),
        Step(id: 8, title: "Sharpen & shape", text: "Sand both edges into a bevel and shape the tip. Done!"),
    ]

    var body: some View {
        let s = scale
        ZStack {
            Color.labTable.opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture { engine.closeGuide(start: false) }

            VStack(alignment: .leading, spacing: 14 * s) {
                HStack(alignment: .center) {
                    OutlinedText(text: "How to build the Knife", font: LabFont.black(34 * s), fill: .labCardboardLight,
                                 width: 2.5 * s, depth: 4 * s)
                    Spacer()
                    Button { engine.closeGuide(start: false) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20 * s, weight: .black))
                            .foregroundStyle(Color.labPaper)
                            .frame(width: 46 * s, height: 46 * s)
                            .background(Circle().fill(Color.labMat))
                    }
                    .buttonStyle(PressableStyle())
                }

                VStack(spacing: 12 * s) {
                    HStack(spacing: 12 * s) {
                        ForEach(GuideView.knifeSteps.prefix(4)) { step in card(step, s) }
                    }
                    HStack(spacing: 12 * s) {
                        ForEach(GuideView.knifeSteps.suffix(4)) { step in card(step, s) }
                    }
                }

                HStack(alignment: .center, spacing: 16 * s) {
                    LegendNote(scale: s, compact: true)
                    foldLegend(s)
                    Spacer()
                    Button {
                        engine.closeGuide(start: true)
                    } label: {
                        HStack(spacing: 10 * s) {
                            Text(engine.guideStartsCraft ? "Start crafting" : "Got it")
                                .font(LabFont.black(24 * s))
                            Image(systemName: "arrow.right").font(.system(size: 22 * s, weight: .black))
                        }
                        .foregroundStyle(Color.labPaper)
                        .padding(.horizontal, 28 * s)
                        .frame(height: 60 * s)
                        .background(Capsule().fill(Color.labRed))
                        .overlay(Capsule().stroke(Color.labInk, lineWidth: 3))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(24 * s)
            .frame(maxWidth: 1130 * s)
            .background(RoundedRectangle(cornerRadius: 30 * s, style: .continuous).fill(Color.labInk))
            .overlay(RoundedRectangle(cornerRadius: 30 * s, style: .continuous).stroke(Color.labMat, lineWidth: 3))
            .padding(20 * s)
        }
    }

    private func card(_ step: Step, _ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let img = icons.image("guide.\(step.id)") {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 14 * s).fill(Color.labMat.opacity(0.5))
                            .aspectRatio(1.5, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
                Text("\(step.id)")
                    .font(LabFont.black(20 * s))
                    .foregroundStyle(Color.labPaper)
                    .frame(width: 38 * s, height: 38 * s)
                    .background(Circle().fill(step.id == 8 ? Color.labMint : Color.labRed))
                    .overlay(Circle().stroke(Color.labInk, lineWidth: 2.5))
                    .padding(6 * s)
            }
            Text(step.title)
                .font(LabFont.heavy(18 * s))
                .foregroundStyle(Color.labPaper)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(step.text)
                .font(LabFont.semibold(13 * s))
                .foregroundStyle(Color.labPaper.opacity(0.75))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10 * s)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20 * s, style: .continuous).fill(Color.labTable))
        .overlay(RoundedRectangle(cornerRadius: 20 * s, style: .continuous).stroke(Color.labMat, lineWidth: 2))
    }

    private func foldLegend(_ s: CGFloat) -> some View {
        HStack(spacing: 14 * s) {
            foldChip(icon: "arrow.uturn.up", title: "Valley fold", detail: "flap folds up toward you", s)
            foldChip(icon: "arrow.uturn.down", title: "Mountain fold", detail: "crease rises, sides go down", s)
        }
    }

    private func foldChip(icon: String, title: String, detail: String, _ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Image(systemName: icon)
                .font(.system(size: 18 * s, weight: .bold))
                .foregroundStyle(Color.labBlue)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(LabFont.heavy(14 * s)).foregroundStyle(Color.labPaper)
                Text(detail).font(LabFont.semibold(12 * s)).foregroundStyle(Color.labPaper.opacity(0.7))
            }
        }
        .padding(.horizontal, 12 * s).padding(.vertical, 8 * s)
        .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(Color.labTable))
        .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).stroke(Color.labBlue.opacity(0.6), lineWidth: 1.5))
    }
}
