# Cardboard Lab

A tactile, low-poly 3D **iPad** crafting game written in **Swift** (SwiftUI + SceneKit).
Cut cardboard along red lines, score and fold along blue dashed lines, glue tabs and
assemble real 3D cardboard objects, starting with a **cardboard knife**.

> CUT → SCORE/FOLD → GLUE → ALIGN → FOLD → ASSEMBLE → FINISHED

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

## Project layout

```
CardboardLab/
  App/        App entry point
  Core/       Platform-free game logic (math, triangulation, fold kinematics,
              templates, cut tracing, tweening). Unit tested on any OS.
  Scene/      SceneKit building blocks: palette, materials, textures, low-poly props,
              the workspace (table, cutting mat, lights)
  Engine/     Game loop, camera rig, touch input, guide overlay
  UI/         SwiftUI screens and HUD
Tools/        Test harness, preview renderer, type-check stubs, icon generator
```

## Style

Low-poly, flat-shaded geometry with chunky ink outlines and hard-edged shadows. All
colors come from `Scene/Palette.swift`:

| Token | Hex | Use |
|---|---|---|
| table | `#083739` | table / background |
| mat | `#0E6762` | cutting mat |
| cardboard | `#E2A652` | cardboard |
| cardboardLight | `#F3C274` | highlights |
| cardboardDark | `#B17330` | cardboard edges |
| ink | `#0D2730` | outlines, text |
| red | `#F46359` | **cut** lines, primary actions |
| blue | `#67C2E2` | **fold** lines, fold arrows |
| mint | `#97E1BE` | success / completed |
| yellow | `#FADC70` | tools |
| paper | `#F8F7EF` | UI surfaces |

**RED SOLID = CUT. BLUE DASHED = FOLD.** These two line types never share a style.

## Developing without a Mac

The `Core/` folder has no Apple-framework dependencies:

```bash
Tools/run-core-tests.sh            # compile + run the core test-suite (swiftc)
Tools/check-syntax.sh              # parse every Swift file
Tools/typecheck.sh                 # type-check the whole app against API stubs
python3 Tools/render_preview.py .build/core-tests/knife.json knife.png --pitch 40 --yaw 35
```

`Tools/typecheck.sh` uses small stand-ins for SceneKit/UIKit/SwiftUI
(`Tools/TypecheckStubs`) to catch type and actor-isolation errors on Linux. Xcode is
still the source of truth.
