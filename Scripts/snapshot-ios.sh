#!/bin/zsh
# Renders snapshot scenes inside the iOS simulator, so text styles have their iPhone sizes and
# `.environment(\.dynamicTypeSize, …)` takes effect (Scripts/snapshot.sh renders on macOS, which maps text
# styles to Mac sizes and has no Dynamic Type).
#
#   SIMULATOR="iPhone 17" Scripts/snapshot-ios.sh <scenes.swift> [output-dir] [name-filter]
#
# Same scenes file contract as snapshot.sh: it defines `@MainActor func snapshotScenes() -> [SnapshotScene]`.
# Known limits of ImageRenderer here: Liquid Glass renders empty (draw it solid), and SF Rounded falls back to
# SF Pro.
set -euo pipefail
ROOT="${0:A:h}/.."
SCENES="${1:?usage: snapshot-ios.sh <scenes.swift> [output-dir] [name-filter]}"
OUT="${2:-${TMPDIR:-/tmp}/maple-snapshots-ios}"
FILTER="${3:-}"
SIMULATOR="${SIMULATOR:-iPhone 17}"
OUT="${OUT:A}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/maple-snapshot-ios.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/core" "$WORK/src" "$OUT"

UDID="$(xcrun simctl list devices available | grep -F "    $SIMULATOR (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[[ -n "$UDID" ]] || { echo "No available simulator named '$SIMULATOR'" >&2; exit 1; }
xcrun simctl bootstatus "$UDID" -b >/dev/null

for f in "$ROOT"/MapleKit/Sources/MapleCore/**/*.swift; do
  cp "$f" "$WORK/core/$(basename "$f" .swift)-$RANDOM.swift"
done
cat > "$WORK/core/BundleModuleShim.swift" <<SHIM
import Foundation
extension Foundation.Bundle {
    static let module = Bundle(path: "${ROOT:A}/MapleKit/Sources/MapleCore/Resources")!
}
SHIM

cat > "$WORK/Harness.swift" <<'HARNESS'
import SwiftUI
import UIKit

struct SnapshotScene {
    let name: String
    let size: CGSize
    let view: AnyView

    init<V: View>(_ name: String, size: CGSize = CGSize(width: 402, height: 874), @ViewBuilder _ view: () -> V) {
        self.name = name
        self.size = size
        self.view = AnyView(view())
    }
}

@main
struct SnapshotMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let directory = URL(fileURLWithPath: arguments.first ?? "snapshots")
        let filter = arguments.count > 1 ? arguments[1] : ""
        MainActor.assumeIsolated {
            for scene in snapshotScenes() where filter.isEmpty || scene.name.contains(filter) {
                let renderer = ImageRenderer(content: scene.view
                    .frame(width: scene.size.width, height: scene.size.height)
                    .environment(\.colorScheme, .dark))
                renderer.scale = 2
                guard let png = renderer.uiImage?.pngData() else {
                    print("FAILED \(scene.name)")
                    continue
                }
                let url = directory.appendingPathComponent("\(scene.name).png")
                try? png.write(to: url)
                print("wrote \(url.path)")
            }
        }
    }
}
HARNESS

TARGET=arm64-apple-ios27.0-simulator
xcrun --sdk iphonesimulator swiftc -parse-as-library -Onone -swift-version 6 \
  -target $TARGET -module-name MapleCore \
  -emit-library -static -emit-module -emit-module-path "$WORK/MapleCore.swiftmodule" \
  -o "$WORK/libMapleCore.a" "$WORK"/core/*.swift
for f in "$ROOT"/MapleKit/Sources/MapleDesign/**/*.swift "${SCENES:A}" "$WORK/Harness.swift"; do
  { echo "import MapleCore"; sed -E '/^import MapleDesign$/d' "$f"; } > "$WORK/src/$(basename "$f" .swift)-$RANDOM.swift"
done
xcrun --sdk iphonesimulator swiftc -parse-as-library -Onone -swift-version 6 \
  -default-isolation MainActor \
  -target $TARGET -module-name MapleSnapshot \
  -I "$WORK" -L "$WORK" -lMapleCore \
  -o "$WORK/snapshot" "$WORK"/src/*.swift
xcrun simctl spawn "$UDID" "$WORK/snapshot" "$OUT" "$FILTER"
