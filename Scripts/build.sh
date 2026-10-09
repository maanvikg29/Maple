#!/bin/zsh
# Builds Maple for the iPhone simulator.
# Build output goes to ~/Library/Developer/Xcode/DerivedData/Maple because this repo lives in an
# iCloud-synced folder, and iCloud's file attributes make codesign fail on build products.
set -euo pipefail
cd "${0:A:h}/.."
SIMULATOR="${SIMULATOR:-iPhone 17}"
# One DerivedData folder per checkout, so parallel worktrees never share build state.
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Maple-$(pwd -P | shasum | cut -c1-8)}"
xcodebuild build \
  -project Maple.xcodeproj -scheme Maple -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -derivedDataPath "$DERIVED_DATA" \
  "$@"
echo "App: $DERIVED_DATA/Build/Products/Debug-iphonesimulator/Maple.app"
