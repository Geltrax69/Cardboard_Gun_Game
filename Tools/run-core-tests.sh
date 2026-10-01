#!/usr/bin/env bash
# Compiles the platform-free game core together with the test harness and runs it.
# Works on macOS (Xcode toolchain) and Linux (swift.org toolchain).
#   Tools/run-core-tests.sh [output-dir-for-preview-json]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.build/core-tests}"
mkdir -p "$OUT"
swiftc -O -o "$OUT/core-tests" "$ROOT"/CardboardLab/Core/*.swift "$ROOT"/Tools/CoreTests/*.swift
"$OUT/core-tests" "$OUT"
