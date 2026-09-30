#!/usr/bin/env bash
# Type-checks the whole app on Linux against stub SceneKit/UIKit/SwiftUI modules
# (Tools/TypecheckStubs). Stubs mirror only the API subset the game uses; Xcode
# remains the source of truth. ObjC-only syntax is neutralised in a temp copy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/cardboardlab-typecheck"
rm -rf "$WORK"; mkdir -p "$WORK/mods" "$WORK/src"
STUBS="$ROOT/Tools/TypecheckStubs"
build() { swiftc -parse-as-library -emit-module -module-name "$1" -I "$WORK/mods" -o "$WORK/mods/$1.swiftmodule" "$STUBS/$1.swift" 2>&1; }
for m in CoreGraphics QuartzCore UIKit Combine SceneKit SwiftUI; do build $m; done
[ -f "$STUBS/AVFoundation.swift" ] && build AVFoundation
[ -f "$STUBS/Metal.swift" ] && build Metal
find "$ROOT/CardboardLab" -name '*.swift' | while read -r f; do
  out="$WORK/src/$(echo "${f#$ROOT/}" | tr '/' '_')"
  sed -e 's/@objc //g' -e 's/#selector(\([^)]*)\))/Selector("\1")/g' -e 's/#selector(\([^)]*\))/Selector("\1")/g' "$f" > "$out"
done
swiftc -typecheck -parse-as-library -swift-version 5 -I "$WORK/mods" "$WORK"/src/*.swift
echo "Type check passed."
