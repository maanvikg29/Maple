#!/bin/zsh
# Screenshots one DEBUG launch of Maple in the simulator, to check a screen against the spec.
#
#   Scripts/shoot.sh <name> <out-dir> [--no-build] [--wait <seconds>] [-- <launch arguments…>]
#
# 1. Builds the Debug app with Scripts/build.sh, unless --no-build is given (then the last build is used).
# 2. Boots the "$SIMULATOR" simulator (default "iPhone 17") if it isn't running.
# 3. Installs the app on it, and stops any copy that is running.
# 4. Launches com.maanvikgupta.maple with the launch arguments (docs/debug-launch-arguments.md).
# 5. Waits 4 seconds (or --wait), and saves <out-dir>/<name>.png.
#
# Example (build once, then shoot without building):
#   SIMULATOR="iPhone 17" Scripts/build.sh > "$WS/build.log" 2>&1
#   Scripts/shoot.sh focus-idle "$WS/shots/task-9" --no-build -- -MapleDemoShip f1 -MapleDemoTab focus -MapleDemoFocus idle
#
# Exit 0: the screenshot was saved (its path is printed). Exit 1: the build failed (its log is
# <out-dir>/<name>.build.log). Exit 2: a simulator step failed (no such simulator, boot, install, launch or
# screenshot), or there is no app to install. Exit 64: wrong usage.
set -euo pipefail
cd "${0:A:h}/.."

usage() {
  print -u2 "Usage: Scripts/shoot.sh <name> <out-dir> [--no-build] [--wait <seconds>] [-- <launch arguments…>]"
  print -u2 "Saves <out-dir>/<name>.png from the \"${SIMULATOR:-iPhone 17}\" simulator. Launch arguments go after --."
}

fail() {
  print -u2 "shoot.sh: $2"
  exit $1
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  usage
  exit 0
fi
(( $# >= 2 )) || { usage; exit 64; }
NAME=$1
OUT=$2
shift 2
[[ -n $NAME && $NAME != */* && $NAME != -* ]] || { print -u2 "shoot.sh: the name must be a plain file name, not '$NAME'"; usage; exit 64; }
[[ -n $OUT && $OUT != -* ]] || { print -u2 "shoot.sh: the output folder must come second"; usage; exit 64; }

BUILD=1
WAIT=4
while (( $# > 0 )); do
  case $1 in
    --no-build)
      BUILD=0
      shift ;;
    --wait)
      [[ $# -ge 2 && $2 =~ '^[0-9]+([.][0-9]+)?$' ]] || { print -u2 "shoot.sh: --wait needs a number of seconds"; usage; exit 64; }
      WAIT=$2
      shift 2 ;;
    --)
      shift
      break ;;
    *)
      print -u2 "shoot.sh: unknown option '$1' (launch arguments go after --)"
      usage
      exit 64 ;;
  esac
done
LAUNCH_ARGS=("$@")

SIMULATOR="${SIMULATOR:-iPhone 17}"
# The folder Scripts/build.sh builds into: one DerivedData folder per checkout, outside the repo.
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Maple-$(pwd -P | shasum | cut -c1-8)}"
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Maple.app"
mkdir -p "$OUT" || fail 2 "can't create $OUT"

if (( BUILD )); then
  LOG="$OUT/$NAME.build.log"
  SIMULATOR="$SIMULATOR" DERIVED_DATA="$DERIVED_DATA" Scripts/build.sh > "$LOG" 2>&1 || fail 1 "the build failed; see $LOG"
fi
[[ -d $APP ]] || fail 2 "no app at $APP: run Scripts/build.sh first, or leave out --no-build"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist") || fail 2 "can't read the bundle id from $APP"

# The simulator with exactly this name ("iPhone 17", never "iPhone 17 Pro"), by UDID: another worktree may have a
# second simulator booted, so "booted" could mean either.
UDID=$(xcrun simctl list devices available \
  | sed -nE 's/^[[:space:]]+'"$SIMULATOR"' \(([0-9A-F-]{36})\) \(.*\)[[:space:]]*$/\1/p' | head -1)
[[ -n $UDID ]] || fail 2 "no available simulator named \"$SIMULATOR\" (see xcrun simctl list devices available)"
xcrun simctl bootstatus "$UDID" -b > /dev/null || fail 2 "\"$SIMULATOR\" didn't boot"
xcrun simctl install "$UDID" "$APP" || fail 2 "couldn't install $APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" "${LAUNCH_ARGS[@]}" > /dev/null || fail 2 "couldn't launch $BUNDLE_ID"
sleep "$WAIT"
xcrun simctl io "$UDID" screenshot "$OUT/$NAME.png" > /dev/null 2>&1 || fail 2 "couldn't save $OUT/$NAME.png"
print -r -- "$OUT/$NAME.png"
