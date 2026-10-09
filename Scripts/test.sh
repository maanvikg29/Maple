#!/bin/zsh
# Runs every MapleKit unit test through the Maple scheme on the iPhone simulator.
set -euo pipefail
cd "${0:A:h}/.."
SIMULATOR="${SIMULATOR:-iPhone 17}"
# One DerivedData folder per checkout, so parallel worktrees never share build state.
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Maple-$(pwd -P | shasum | cut -c1-8)}"
xcodebuild test \
  -project Maple.xcodeproj -scheme Maple \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -derivedDataPath "$DERIVED_DATA" \
  "$@"
