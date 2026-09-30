#!/usr/bin/env bash
# Parse-only check of every Swift file (catches syntax errors on machines without the
# iOS SDK, e.g. Linux CI). Full type checking needs Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
status=0
while IFS= read -r -d '' f; do
  if ! swiftc -parse "$f" 2>/tmp/cl-parse.log; then
    echo "✗ $f"; cat /tmp/cl-parse.log; status=1
  fi
done < <(find "$ROOT/CardboardLab" -name '*.swift' -print0)
[ $status -eq 0 ] && echo "All Swift files parse cleanly."
exit $status
