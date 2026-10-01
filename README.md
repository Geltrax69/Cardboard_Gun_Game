# Cardboard Lab

A tactile, low-poly 3D **iPad** crafting game written in **Swift** (SwiftUI + SceneKit).
Cut cardboard along red lines, score and fold along blue dashed lines, glue tabs,
assemble and sharpen real 3D cardboard weapons. Twelve knives, daggers, swords and
axes unlock as you level up; the pistol and rifle are on the menu as upcoming blueprints.

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
| **Rotate the view** | Two-finger drag orbits around the build (or one finger when no tool is active, e.g. while *Next* is showing). |
| **Zoom** | Pinch. The ↶ button next to Home returns to the step's own framing. |

There are no timers, lives or score loss. Straying off a line only shows *Try following
the highlighted line*. A ghost finger demonstrates each gesture the first time and
again if you pause. You can turn hints off in Settings.

### Weapons and levels

| Level | Weapon | Build |
|---|---|---|
| 1 | Knife | Drop-point ridge blade, lanyard hole, guard band |
| 2 | Dagger | Spear-point ridge blade, bar guard, diamond pommel |
| 3 | Kunai | Leaf blade, slim handle, three grip bands |
| 4 | Bowie Knife | Laminated clip-point blade, guard, knob pommel |
| 5 | Short Sword | Leaf blade with a fuller, flared guard |
| 6 | Hand Axe | Long shaft, single-bit axe head |
| 7 | Flame Dagger | Wavy flame blade, spiked guard, spike pommel |
| 8 | Karambit | Hooked laminated blade with a saw back |
| 9 | Scimitar | Strongly curved laminated blade |
| 10 | Longsword | 11.5-unit ridge blade, fuller, long grip |
| 11 | Katana | Curved tanto-tip blade, disc guard, four wraps |
| 12 | Battle Axe | Double-bit head on a long shaft |

Crafting a weapon for the first time earns exactly the XP needed for the next level
(`Core/Progression.swift`), which unlocks the next weapon. Crafting again earns 40% XP.
The finish card shows **LEVEL UP!** and what it unlocked; new weapons wear a **NEW**
badge on the menu.

### Free Craft

**Free Craft** (top of the Weapons list) is a designer for your own weapons. The weapon
spins on a turntable above the mat (drag to spin it, pinch to zoom) and updates live as
you pick parts:

- **Type**: knife, dagger, sword or axe
- **Blade**: double edge (ridge) or single edge (laminated), tip shape, plain or
  serrated edge, length, width, curve, fuller groove
- **Guard** and **pommel**, or an **axe head**, with sizes
- **Handle / shaft** length, grip bands, lanyard hole

Every part unlocks at the level of the first campaign weapon that uses it (flame tips at
level 7 with the Flame Dagger, axes at level 6, …; `Core/FreeCraft.swift`), so the
designer grows as you level up. **Surprise me** rolls a random design from your unlocked
parts. **Craft it!** builds it with the normal six-stage session for 60 XP, and the last
design is remembered.

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
                WeaponBlueprint (design → pieces, folds, assembly, glue & bevels) · Stock
  Scene/      SceneKit building blocks: palette, materials, procedural textures,
              low-poly props, workspace, menu stacks, PieceNode, TemplateSheet,
              cut/score/glue visuals, particles, icon & guide renderer
  Engine/     GameEngine (loop, input, screens), CameraRig, HUD model, SoundBoard,
              guide overlay (arrows, dotted guides, ghost finger)
  Game/       Crafting sessions and interactions: CraftSession, WeaponSession,
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

Something completely different (for example the pistol) gets its own blueprint in
`Core/` and its own `CraftSession` subclass in `Game/`, built from the ready-made
interactions: `TraceInteraction.cut/score/glue/sand/carve`, `FoldInteraction`,
`PlaceInteraction`.

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
