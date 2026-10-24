#!/bin/zsh
# Builds Maple in Release for the iPhone simulator and fails if any DEBUG-only demo or preview type made it into the
# binary (F1 design §8.4). Run from anywhere: Scripts/check-release.sh
set -euo pipefail
cd "${0:A:h}/.."
SIMULATOR="${SIMULATOR:-iPhone 17}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Maple-release-$(pwd -P | shasum | cut -c1-8)}"
xcodebuild build \
  -project Maple.xcodeproj -scheme Maple -configuration Release \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO -quiet
BINARY="$DERIVED_DATA/Build/Products/Release-iphonesimulator/Maple.app/Maple"
FORBIDDEN='PreviewBlockingService|RecordingLiveActivityController|DemoLaunchOptions|DemoData|PreviewLeafShareProvider|HealthSleepSeeder|FocusDemo'
FOUND=$( { nm "$BINARY" | xcrun swift-demangle; strings - "$BINARY"; } | grep -Eo "$FORBIDDEN" | sort -u || true)
if [[ -n "$FOUND" ]]; then
  echo "Release build contains DEBUG-only code:"
  echo "$FOUND"
  exit 1
fi
echo "Release build has no demo or preview code."
