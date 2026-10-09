#!/bin/zsh
# Renders design components to PNG for fast visual review, without building the app.
#
#   Scripts/snapshot.sh <scenes.swift> [output-dir]
#
# <scenes.swift> must define `@MainActor func snapshotScenes() -> [SnapshotScene]`.
# MapleCore is built as its own nonisolated module; MapleDesign + the scenes compile on top of it (main actor by default).
set -euo pipefail
ROOT="${0:A:h}/.."
SCENES="${1:?usage: snapshot.sh <scenes.swift> [output-dir]}"
OUT="${2:-${TMPDIR:-/tmp}/maple-snapshots}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/maple-snapshot.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/core" "$WORK/src"
# Build MapleCore as its own nonisolated module, exactly as the package does.
for f in "$ROOT"/MapleKit/Sources/MapleCore/**/*.swift; do
  cp "$f" "$WORK/core/$(basename "$f" .swift)-$RANDOM.swift"
done
# SwiftPM normally generates `Bundle.module`; point it at MapleCore's resources folder instead.
cat > "$WORK/core/BundleModuleShim.swift" <<SHIM
import Foundation
extension Foundation.Bundle {
    static let module = Bundle(path: "$ROOT/MapleKit/Sources/MapleCore/Resources")!
}
SHIM
xcrun --sdk macosx swiftc -parse-as-library -O -swift-version 6 \
  -target arm64-apple-macos27.0 -module-name MapleCore \
  -emit-library -static -emit-module -emit-module-path "$WORK/MapleCore.swiftmodule" \
  -o "$WORK/libMapleCore.a" "$WORK"/core/*.swift
# MapleDesign + scenes + harness compile together with main-actor default isolation, like MapleDesign.
for f in "$ROOT"/MapleKit/Sources/MapleDesign/**/*.swift "${SCENES:A}" "$ROOT/Scripts/snapshot/Harness.swift"; do
  { echo "import MapleCore"; sed -E '/^import MapleDesign$/d' "$f"; } > "$WORK/src/$(basename "$f" .swift)-$RANDOM.swift"
done
xcrun --sdk macosx swiftc -parse-as-library -O -swift-version 6 \
  -default-isolation MainActor \
  -target arm64-apple-macos27.0 -module-name MapleSnapshot \
  -I "$WORK" -L "$WORK" -lMapleCore \
  -o "$WORK/snapshot" "$WORK"/src/*.swift
"$WORK/snapshot" "$OUT"
