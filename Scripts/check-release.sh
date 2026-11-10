#!/bin/zsh
# Builds Maple in Release for the iPhone simulator and fails if any DEBUG-only demo or preview type made it into the
# app or into the extension it embeds (F1 design §8.4). Run from anywhere: Scripts/check-release.sh
# Exit 0: clean. Exit 1: DEBUG-only code found. Exit 2: the check could not run (no binary, a tool failed), which never
# counts as a pass.
set -euo pipefail
cd "${0:A:h}/.."
SIMULATOR="${SIMULATOR:-iPhone 17}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Maple-release-$(pwd -P | shasum | cut -c1-8)}"
xcodebuild build \
  -project Maple.xcodeproj -scheme Maple -configuration Release \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO -quiet
APP="$DERIVED_DATA/Build/Products/Release-iphonesimulator/Maple.app"
# The app and the Live Activity extension: each is its own binary, with its own copy of the package code it links.
BINARIES=("$APP/Maple" "$APP/PlugIns/MapleWidgets.appex/MapleWidgets")
# Bare `Demo` covers DemoLaunchOptions, DemoData, DemoPresenter, RevealDemoOptions, HealthDemoSeeding, HerbariumDemo,
# ReminderDemo, SleepDemo, FocusDemo, FocusDemoPresenter and LiveActivityDemo. A bare `Preview` would also hit
# SharePreview and similar real names, so the preview types are named. `LedgerInspect` covers LedgerInspection and
# LedgerInspector; FakeAppPicker and PickerChoice are the DEBUG fake app picker's.
FORBIDDEN='PreviewBlockingService|PreviewLeafShareProvider|RecordingLiveActivityController|HealthSleepSeeder|Demo|DesignSystemView|LedgerInspect|FakeAppPicker|PickerChoice'
FOUND=""
for BINARY in "${BINARIES[@]}"; do
  [[ -f "$BINARY" ]] || { echo "No binary at $BINARY" >&2; exit 2; }
  SYMS=$(nm "$BINARY" | xcrun swift-demangle) || { echo "Could not read symbols from $BINARY" >&2; exit 2; }
  STR=$(strings - "$BINARY") || { echo "Could not read strings from $BINARY" >&2; exit 2; }
  [[ -n "$SYMS" && -n "$STR" ]] || { echo "Read no symbols or strings from $BINARY" >&2; exit 2; }
  # grep exits 1 when nothing matches (the pass); any other failure, such as a broken pattern, is an error.
  STATUS=0
  HITS=$(print -r -- "$SYMS"$'\n'"$STR" | grep -Eo "$FORBIDDEN" | sort -u) || STATUS=$?
  (( STATUS <= 1 )) || { echo "Searching $BINARY failed (exit $STATUS)" >&2; exit 2; }
  [[ -z "$HITS" ]] || FOUND+="${BINARY:t}:"$'\n'"$HITS"$'\n'
done
if [[ -n "$FOUND" ]]; then
  echo "Release build contains DEBUG-only code:"
  print -rn -- "$FOUND"
  exit 1
fi
echo "Release build has no demo or preview code (Maple and MapleWidgets)."
