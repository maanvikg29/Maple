#!/bin/zsh
# Runs every MapleKit unit test through the Maple scheme on the iPhone simulator.
set -euo pipefail
cd "${0:A:h}/.."
SIMULATOR="${SIMULATOR:-iPhone 17}"
xcodebuild test \
  -project Maple.xcodeproj -scheme Maple \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Maple" \
  "$@"
