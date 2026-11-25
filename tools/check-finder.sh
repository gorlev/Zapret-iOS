#!/bin/sh
# Checks Find a Strategy's pure logic (scan plan, block diagnosis, trial rules)
# on the Mac, without the simulator.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swiftc -swift-version 6 -o "$OUT/finder-checks" \
    "$ROOT/App/Finder/Trial.swift" \
    "$ROOT/App/Finder/ScanPlan.swift" \
    "$ROOT/App/Finder/BlockDiagnosis.swift" \
    "$ROOT/tools/finder-checks/main.swift"
"$OUT/finder-checks"
