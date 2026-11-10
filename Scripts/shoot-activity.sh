#!/bin/zsh
# Screenshots Maple's Live Activity outside the app (F1 design §5.11): on the Lock Screen and in the Dynamic Island.
#
#   Scripts/shoot-activity.sh <name> <out-dir> lock|island|expanded [--no-build] [--after <seconds>] [-- <launch arguments…>]
#
# 1. Launches Maple with the launch arguments through Scripts/shoot.sh (building first, unless --no-build). That also
#    saves <out-dir>/<name>-app.png: the app as it starts the activity.
# 2. Then, on the same "$SIMULATOR" simulator (default "iPhone 17"):
#    lock      locks it (Simulator › Device › Lock, ⌘L), waits --after seconds (default 2), saves <out-dir>/<name>.png,
#              and unlocks it again (Device › Home, ⇧⌘H);
#    island    brings Settings forward, so Maple's activity moves into the Dynamic Island, waits --after seconds
#              (default 2) and saves <out-dir>/<name>.png: the compact presentation;
#    expanded  brings Settings forward and, from --after seconds (default 2.4), saves <name>-1.png, -2.png and
#              -3.png, 0.6 s apart. Launch with -MapleDemoLiveActivityExpand 2: the activity alerts 2 s after Maple
#              leaves the screen, and the island shows its expanded presentation for a few seconds.
# In the simulator, the `ended` activity (an 8 s stale date) was seen going stale about 2 minutes after the request,
# when the system's own timer marked it: shoot -MapleDemoLiveActivity ended with --after 130 to see "Session complete".
#
# Locking and unlocking press keys in the Simulator app, which needs that app to be installed (Xcode's Simulator.app;
# a headless simulator has none) and this terminal to be allowed to control the computer (System Settings › Privacy &
# Security › Accessibility). The script never asks for that permission. Without either, the lock step stops with
# exit 3: lock the simulator by hand (⌘L in Simulator, or a simulator tool's lock button), save the screen with
# `xcrun simctl io <udid> screenshot --mask=black <file>`, and unlock it (⇧⌘H).
#
# Exit 0: saved (each path is printed). 1: the build failed. 2: a simulator step failed. 3: the simulator couldn't be
# locked or unlocked. 64: wrong usage.
set -euo pipefail
cd "${0:A:h}/.."

usage() {
  print -u2 "Usage: Scripts/shoot-activity.sh <name> <out-dir> lock|island|expanded [--no-build] [--after <seconds>] [-- <launch arguments…>]"
}

fail() {
  print -u2 "shoot-activity.sh: $2"
  exit $1
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  usage
  exit 0
fi
(( $# >= 3 )) || { usage; exit 64; }
NAME=$1
OUT=$2
MODE=$3
shift 3
if [[ $MODE != lock && $MODE != island && $MODE != expanded ]]; then
  print -u2 "shoot-activity.sh: the mode must be lock, island or expanded, not '$MODE'"
  usage
  exit 64
fi

SHOOT_OPTIONS=()
AFTER=""
while (( $# > 0 )); do
  case $1 in
    --no-build)
      SHOOT_OPTIONS+=(--no-build)
      shift ;;
    --after)
      [[ $# -ge 2 && $2 =~ '^[0-9]+([.][0-9]+)?$' ]] || { print -u2 "shoot-activity.sh: --after needs a number of seconds"; usage; exit 64; }
      AFTER=$2
      shift 2 ;;
    --)
      shift
      break ;;
    *)
      print -u2 "shoot-activity.sh: unknown option '$1' (launch arguments go after --)"
      usage
      exit 64 ;;
  esac
done
if [[ -z $AFTER ]]; then
  if [[ $MODE == expanded ]]; then AFTER=2.4; else AFTER=2; fi
fi

# 1. The launch, and the app's own frame. shoot.sh's exit codes (1 build, 2 simulator, 64 usage) pass through.
Scripts/shoot.sh "$NAME-app" "$OUT" "${SHOOT_OPTIONS[@]}" --wait 4 -- "$@" || exit $?

SIMULATOR="${SIMULATOR:-iPhone 17}"
UDID=$(xcrun simctl list devices available \
  | sed -nE 's/^[[:space:]]+'"$SIMULATOR"' \(([0-9A-F-]{36})\) \(.*\)[[:space:]]*$/\1/p' | head -1)
[[ -n $UDID ]] || fail 2 "no available simulator named \"$SIMULATOR\""

# Presses a key in the Simulator window that shows this device: simulator_key <key> <modifiers>.
simulator_key() {
  open -a Simulator --args -CurrentDeviceUDID "$UDID" || return 1
  sleep 1
  osascript -e 'tell application "Simulator" to activate' \
    -e "tell application \"System Events\" to keystroke \"$1\" using {$2}" > /dev/null 2>&1
}

# --mask=black: without a device mask, simctl leaves the Dynamic Island's layer out of the image (the island and its
# activity are missing), so the screen's corners and cutout are masked black and the island is drawn in.
save() {
  xcrun simctl io "$UDID" screenshot --mask=black "$OUT/$1.png" > /dev/null 2>&1 || fail 2 "couldn't save $OUT/$1.png"
  print -r -- "$OUT/$1.png"
}

case $MODE in
  lock)
    simulator_key l "command down" \
      || fail 3 "couldn't lock the simulator: there is no Simulator app to press ⌘L in, or this terminal isn't allowed under System Settings › Privacy & Security › Accessibility; lock it by hand (⌘L)"
    sleep "$AFTER"
    save "$NAME"
    simulator_key h "command down, shift down" \
      || fail 3 "couldn't unlock the simulator: there is no Simulator app to press ⇧⌘H in, or this terminal isn't allowed under Accessibility; unlock it by hand (⇧⌘H)"
    ;;
  island)
    xcrun simctl launch "$UDID" com.apple.Preferences > /dev/null || fail 2 "couldn't open Settings"
    sleep "$AFTER"
    save "$NAME"
    ;;
  expanded)
    xcrun simctl launch "$UDID" com.apple.Preferences > /dev/null || fail 2 "couldn't open Settings"
    sleep "$AFTER"
    for frame in 1 2 3; do
      save "$NAME-$frame"
      sleep 0.6
    done
    ;;
esac
