# Cardboard Lab

A tactile, low-poly 3D **iPad** crafting game written in **Swift** (SwiftUI + SceneKit).
Cut cardboard along red lines, score and fold along blue dashed lines, glue tabs,
assemble, sharpen and detail real 3D cardboard weapons. Twelve knives, daggers, swords
and axes plus a pistol and a rifle unlock as you level up, and Free Mode is an open
workbench with unlimited cardboard where you can make anything.

> CUT → HANDLE → BLADE → FITTINGS → ASSEMBLE → SHARPEN → FINISHED

## Requirements

- Xcode 16 or newer (the project uses Xcode's synchronized folders)
- iPadOS 17+ (landscape, iPad only)

## Run it

1. Open `CardboardLab.xcodeproj` in Xcode.
2. Select the **CardboardLab** scheme and an iPad simulator or a connected iPad.
3. For a device build, pick your team under *Signing & Capabilities*.
4. Press **Run** (⌘R).

Every Swift file under `CardboardLab/` is part of the app target automatically. New
files you add there are compiled with no project edits.

## How to play

| Action | Gesture |
|---|---|
| **Cut** (red solid line) | Swipe along the glowing red line; the craft knife follows your finger or Apple Pencil. Lift and continue any time. |
| **Score** (blue dashed line) | Swipe the bone folder along the dashed line (either direction). |
| **Fold** | Drag the highlighted flap along the curved blue arrow. Past ~70% it snaps: *Perfect fold*. |
| **Glue** | Drag the glue bottle along the dotted blue guide on the tab. |
| **Align / connect** | Drag the piece onto its glowing mint outline; it snaps into place: *Tab aligned*. |
| **Rotate the view** | Two-finger drag orbits around the build (or one finger when no tool is active, e.g. while *Next* is showing). A two-finger gesture either turns or zooms, so pinching never spins the view. |
| **Zoom** | Pinch: it zooms toward the spot between your fingers, from far out to right up close. The ↶ button next to Home returns to the step's own framing. |
| **Hand (explore)** | The ✋ button (next to Home, or *Hand* in Free Mode's tool column) hands every touch to the camera: drag to look around, two fingers to move, pinch to zoom in close (keep pinching to fly forward into the build), double-tap anything to fly to it, and walk with the joystick (hold *Up* / *Down* to float). Tap it again — or any Free Mode tool — to get back to work. |

There are no timers, lives or score loss. Straying off a line only shows *Try following
the highlighted line*. A ghost finger demonstrates each gesture the first time and
again if you pause. You can turn hints off in Settings.

### Weapons and levels

| Level | Project | Build |
|---|---|---|
| 1 | Knife | Drop-point ridge blade, lanyard hole, guard band |
| 2 | **Pistol** | Slide with muzzle, raked grip, trigger guard with trigger, front and rear sights |
| 3 | Dagger | Spear-point ridge blade, bar guard, diamond pommel |
| 4 | Kunai | Leaf blade, slim handle, three grip bands |
| 5 | **Rifle** | Receiver, barrel through a square slot, stock, grip, magazine, scope, sight |
| 6 | Bowie Knife | Laminated clip-point blade, guard, knob pommel |
| 7 | Short Sword | Leaf blade with a fuller, flared guard |
| 8 | Hand Axe | Long shaft, single-bit axe head |
| 9 | Flame Dagger | Wavy flame blade, spiked guard, spike pommel |
| 10 | Karambit | Hooked laminated blade with a saw back |
| 11 | Scimitar | Strongly curved laminated blade |
| 12 | Longsword | 11.5-unit ridge blade, fuller, long grip |
| 13 | Katana | Curved tanto-tip blade, disc guard, four wraps |
| 14 | Battle Axe | Double-bit head on a long shaft |

The order lives in `Campaign.order` (`Core/Progression.swift`). Crafting a project for
the first time earns exactly the XP needed for the next level, which unlocks the next
one. Crafting again earns 40% XP. **Settings → Unlock all projects** jumps straight to
the top level for testing.
The finish card shows **LEVEL UP!** and what it unlocked; new weapons wear a **NEW**
badge on the menu.

### Free Mode: make anything

**Free Mode** (top of the Weapons list) is an open workbench with unlimited cardboard.
There are no parts to pick: you draw, cut, fold, paint and build whatever you like.

| Tool | How it works |
|---|---|
| **Cut** | Draw anywhere on any piece or sheet — strokes may start and end off the edge. A closed shape (*Freehand*, *Lines*, *Rectangle*, *Circle*) punches a piece out, or bites a notch where it crosses the edge; an open line (*Freehand*, *Straight cut*, or *Lines* → *Cut along*) that runs edge to edge slices the piece in two. Every cut is checked first, so you only trace cuts that can happen. Trace the red line with the craft knife, switch on *Quick cut*, or tap **Cancel cut** to leave the board as it was. |
| **Fold line** | Pick **Valley** (blue dashes, the flap folds up) or **Mountain** (blue dash-dot, the flap folds down) and drag a line across a piece; it lands exactly where you drew it on that face and snaps straight. Lines may run through corners or along earlier creases (box nets work), but can't cross another fold or a hole. |
| **Fold** | Grab the flap beside a fold line and drag it to any angle: up for valley lines, down for mountain lines (it snaps to 15° steps near them; 90° and 180° are *Perfect folds*). A piece folded downward rests on its flaps instead of sinking into the table. |
| **Paint** | A full colour wheel (hue round the rim, saturation toward the centre), a brightness slider, ready-made shades and your recent colours. Tap or brush over faces — top or underside — or switch to *Whole piece*. |
| **Move** | Drag any piece or whole sheet. **Slide** moves it across the table, **Lift** raises and lowers it, **Turn** spins it freely in 3D. Tap one for Turn 45°, Stand up, Flip, To table, Copy, Unglue and Delete. |
| **Glue** | Tap a piece, then the piece to stick it onto: they move together from then on. |
| **Hand** | Explore the bench: drag to look, two fingers to move, pinch to zoom, double-tap to fly to a spot, joystick to walk. |

**New sheet** opens the sheet picker: *Small* 14×10, *Large* 20×14, *Long* 28×10 (room
for a long sword) or *Huge* 28×20, in any cardboard, dropped on the next free spot of the
table as often as you like. Sheets are ordinary pieces, so they can be moved, turned,
painted and glued too. **Undo** steps back through every change, **Top view / 3D view**
switches the camera, and the whole bench is saved automatically (`WorkshopStore`, older
saves are migrated) so you can keep adding detail next time. The model lives in
`Core/Workshop.swift` (cuts, slices, creases, colours, glue — all unit tested);
`Game/WorkshopSession.swift` runs the tools.

### A weapon, step by step

Every weapon goes through the same stages; ones a design doesn't need are skipped, so
the HUD shows 5 or 6 steps.

| Stage | What happens |
|---|---|
| Cut | The pencil traces the template. Cut out every piece and punch any lanyard holes. Each freed piece lifts out (+CRAFT); matching grip bands after the first are cut in one quick pass. The leftover board slides away. |
| Handle | Score the five handle creases, fold the walls, end cap and glue tab up in 3/4 view, glue the tab, then close the lid onto it (*Tab aligned*). |
| Blade | **Ridge** blades: score the spine and pinch a ridge, then glue the tang. **Laminated** (single-edged) blades: score the fold, glue the first layer, then fold the mirrored twin over on top. |
| Fittings | Guards, pommels and axe heads are U-shaped clips: score both creases, glue the top wing, fold the wings up. |
| Assemble | The handle lifts off the mat. Slide the guard on, push the blade through it into the handle, fit the pommel or axe head, and drop the grip bands on: they wrap themselves round. |
| Sharpen | Rub the **sanding block** along each edge: a sanded bevel appears behind it and the tip flashes when it's shaped. Swords with a fuller get it carved with the craft knife. The finished weapon pops up with confetti. |

The **How to build the Knife** guide (menu → *How to build*, the **?** button while
crafting, or Settings) shows all eight stages rendered from the real 3D pieces.

### The pistol and rifle, step by step

Guns are boxes and fins (`Core/GunBlueprint.swift`, built by `Game/GunSession.swift`):

| Stage | What happens |
|---|---|
| Cut | Cut every box net and fin out, punch the muzzle, the finger hole round the trigger and the rifle's barrel slot. |
| Body | Fold the slide / receiver box crease by crease, with a front cap holding the muzzle (pistol) or the barrel slot (rifle). Glue the tab, close the lid. |
| Parts | Every other box (grip, barrel, stock, magazine, scope) is scored for you and folds up with **one drag**; then glue and close. Fins (trigger guard, sights) get their tab scored and glued. |
| Assemble | The body lifts up. Push the barrel through the slot, fit the stock, hang the grip and magazine underneath, and drop on the trigger guard and sights: their glued tabs fold over and stick. |
| Details | Draw the ejection port, slide serrations, magazine ridges and grip texture with a **marker** along yellow dotted guides. |

## Project layout

```
CardboardLab/
  App/        App entry point
  Core/       Platform-free logic, unit tested on any OS:
                Vec (vectors, quaternions, poses) · Earcut (triangulation with holes)
                Polygon/Polyline · Template (pieces, panels, hinges, union outlines)
                FoldRig (fold kinematics) · MeshBuilder (flat-shaded meshes)
                PathTracer (finger → tool along a path) · CameraMath · Tweener
                WeaponDesign (parameters) · BladeShapes (blade outlines)
                WeaponBlueprint (design → pieces, folds, assembly, glue & bevels)
                BoxNet (box and fin nets) · GunBlueprint · Progression (campaign, XP)
                Workshop (free mode: cutting, creasing, colours, glue) · Stock
  Scene/      SceneKit building blocks: palette, materials, procedural textures,
              low-poly props, workspace, menu stacks, PieceNode, TemplateSheet,
              cut/score/glue visuals, particles, icon & guide renderer
  Engine/     GameEngine (loop, input, screens), CameraRig, HUD model, SoundBoard,
              guide overlay (arrows, dotted guides, ghost finger)
  Game/       Crafting sessions and interactions: CraftSession, BuildSession (shared
              moves), WeaponSession, GunSession, WorkshopSession, WorkshopModel,
              TraceInteraction (cut/score/glue), FoldInteraction, PlaceInteraction,
              GhostHint, PlayerProfile, Catalog
  UI/         SwiftUI: menu, crafting HUD, guide, components
Tools/        Core tests, preview renderer, API stubs for type-checking, icon generator
```

### How a craft runs

A project is a `CraftSession` subclass written as straight-line async code:

```swift
step(2, "Fold the walls up", "Drag each flap up along the blue arrow.", tool: .hand)
try await look(at: handleCenter(), size: V2(8, 6.5), shot: .threeQuarter)
try await foldPanel(handle, "HS1", grab: farEdge, first: true)
try await waitForNext()
```

Each `await` goes through the engine's `Tweener`, which the display link drives. Tapping
Home cancels every pending await, so the script unwinds cleanly.

## Adding your own cuts (templates)

A template is a sheet with one or more **pieces**. A piece is a tree of **panels**
joined by **hinges**. You describe panels and hinges; the red cut outline, ink edges,
blue fold lines, triangulation and folding are all derived automatically.

Coordinates are template space `(u, v)` = world `(x, z)` on the mat, with `+v` toward the
player (down on screen). A panel's printed face is up.

```swift
let t: Float = 0.14                          // board thickness (from the stock)
let base = PanelDef("BASE", Poly.rect(0, -1, 4, 1))            // root: no parent
let wall = PanelDef("WALL", Poly.rect(0, -2, 4, -1),
                    parent: "BASE",
                    hinge: HingeDef(V2(0, -1), V2(4, -1)))       // valley fold, 90°
let tab  = PanelDef("TAB", [V2(0.1, 1), V2(3.9, 1), V2(3.6, 1.4), V2(0.4, 1.4)],
                    parent: "BASE",
                    hinge: HingeDef(V2(0.1, 1), V2(3.9, 1), .mountain, degrees: 90),
                    role: .glueTab)
let piece = PieceDef(id: "box", name: "Box", placement: V2(-2, 0), panels: [base, wall, tab])
let template = CraftTemplate(sheetSize: V2(15.2, 10), thickness: t, pieces: [piece])
```

Rules of thumb:

- **Valley** folds hinge about the printed face (the flap rises toward you). **Mountain**
  folds hinge about the underside. Because the board has real thickness, size
  neighbouring panels with `t` in mind. `WeaponBlueprint.handlePanels` shows how a lid is `W + t` wide
  so it covers the wall, and how a tucked tab's wall is `H − t` tall so the lid sits flush.
- Holes go in `PanelDef(holes:)`. They are cut as small red circles and punch out.
- The piece outline is computed as the union of its panels. Panels must share edges
  exactly along hinges.
- Check a template before it ever reaches the iPad:
  `Tools/run-core-tests.sh`, then render a preview of any fold state with
  `python3 Tools/render_preview.py .build/core-tests/knife.json knife.png --pitch 40 --yaw 35`.

### Adding a new weapon

Knives, daggers, swords and axes need no new code: describe one with a `WeaponDesign`
(blade build, tip, edge, length, width, curve, guard, pommel or axe head, grip bands)
and give it a `ProjectInfo` in `Game/Catalog.swift`. `WeaponBlueprint` generates the
pieces and `WeaponSession` builds it. `Tools/run-core-tests.sh` checks every campaign
weapon plus hundreds of random designs and writes `weapon_<id>.json` / `sheet_<id>.json`
previews.

Something completely different gets its own blueprint in `Core/` (use `BoxNet` for
boxes and fins, like `GunBlueprint`) and its own `BuildSession` subclass in `Game/`,
built from the shared moves (`cutPieces`, `buildBox`, `liftBody`, `mount`,
`celebrate`) and the interactions `TraceInteraction.cut/score/glue/sand/carve/draw`,
`FoldInteraction` and `PlaceInteraction`.

## Style

Low-poly, flat-shaded geometry with chunky ink outlines and hard-edged shadows. The
camera is near top-down for cutting and planning and moves to 3/4 for folding. All
colors come from `Scene/Palette.swift`:

| Token | Hex | Use |
|---|---|---|
| table | `#083739` | table / background |
| mat | `#0E6762` | cutting mat |
| cardboard | `#E2A652` | cardboard |
| cardboardLight | `#F3C274` | highlights |
| cardboardDark | `#B17330` | cardboard edges, creases |
| ink | `#0D2730` | outlines, panels, text |
| red | `#F46359` | **cut** lines, primary actions |
| blue | `#67C2E2` | **fold** lines, fold arrows, guides |
| mint | `#97E1BE` | success, matching surfaces |
| yellow | `#FADC70` | tools, selection |
| paper | `#F8F7EF` | UI text and surfaces |

**RED SOLID = CUT. BLUE DASHED = FOLD.** The two line types never share a style.

Sound effects are synthesised at launch (`Engine/SoundBoard.swift`), so the game ships
with no audio assets.

## Developing without a Mac

The `Core/` folder has no Apple-framework dependencies:

```bash
Tools/run-core-tests.sh            # compile + run the core test-suite (swiftc)
Tools/check-syntax.sh              # parse every Swift file
Tools/typecheck.sh                 # type-check the whole app against API stubs
python3 Tools/render_preview.py .build/core-tests/knife.json knife.png --pitch 40 --yaw 35
python3 Tools/make_icon.py CardboardLab/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

`Tools/typecheck.sh` uses small stand-ins for SceneKit, UIKit, SwiftUI and AVFoundation
(`Tools/TypecheckStubs`) to catch type and actor-isolation errors on Linux. Xcode is
still the source of truth.
