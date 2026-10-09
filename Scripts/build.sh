#!/bin/zsh
# Builds Maple for the iPhone simulator.
# Build output goes to ~/Library/Developer/Xcode/DerivedData/Maple because this repo lives in an
# iCloud-synced folder, and iCloud's file attributes make codesign fail on build products.
set -euo pipefail
cd "${0:A:h}/.."
SIMULATOR="${SIMULATOR:-iPhone 17}"
xcodebuild build \
  -project Maple.xcodeproj -scheme Maple -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Maple" \
  "$@"
echo "App: $HOME/Library/Developer/Xcode/DerivedData/Maple/Build/Products/Debug-iphonesimulator/Maple.app"
