#!/bin/zsh
# Proves the native leaf port (MapleDesign/Leaves) matches the catalogue exports (Catalog/svg/autumn).
#
#   Scripts/leaf-fidelity.sh [--no-controls] [output-dir]
#
# 1. Rasterises every autumn export with QuickLook (512 × 512), cached in <output-dir>/reference
#    (override with LEAF_FIDELITY_REFERENCE); only missing or out-of-date rasters are redrawn.
# 2. Renders every species with the Swift port in its autumn colour, framed by exactly its export's viewBox,
#    at 512 × 512 px on white (Scripts/snapshot/LeafFidelityScenes.swift via Scripts/snapshot.sh).
# 3. Compares each pair (Scripts/snapshot/LeafFidelityCompare.swift) on five gates:
#      silhouette IoU      outer shape: lobes, teeth, tilt, stalk         mean >= 0.995, every species >= 0.99
#      line IoU            where veins and outlines are, and how thick    mean >= 0.93,  every species >= 0.90
#      colour delta        fill / line colour over the whole leaf (/255)  mean <= 1.25,  every species <= 2.5
#      line colour delta   the same over vein and outline pixels only     mean <= 5,     every species <= 7
#      off-edge mismatches 3 × 3 blocks drawn by one side only            0 for every species
#    It prints a table worst first and writes <output-dir>/fidelity.tsv and <output-dir>/contact-sheet.png
#    (worst 12: reference | port | mask difference | colour difference). Override a gate with
#    LEAF_FIDELITY_GATES, e.g. LEAF_FIDELITY_GATES="line-min=0.85 colour-max=4".
# 4. Negative controls (skip with --no-controls): renders every species once per deliberately broken drawing
#    (no veins, thin or full-length veins, stronger veins, outline in the fill colour, fill 10/255 lighter,
#    1° more tilt, no teeth) plus an unchanged replica, and checks that the comparer fails every broken one
#    and passes the replica, so a gate that stops seeing a defect is caught. Adds about 5 seconds.
#
# Exits non-zero when a gate or a control check fails. Everything is written outside the repo
# (default ${TMPDIR}/maple-leaf-fidelity) because the repo is iCloud-synced.
set -euo pipefail
ROOT="${0:A:h:h}"
CONTROLS=1
if [[ "${1:-}" == "--no-controls" ]]; then
  CONTROLS=0
  shift
fi
OUT="${1:-${TMPDIR:-/tmp}/maple-leaf-fidelity}"
OUT="${OUT:A}"
case "$OUT/" in
  "$ROOT"/*) echo "Choose an output directory outside the repo (it is iCloud-synced)." >&2; exit 2 ;;
esac
REFERENCE="${LEAF_FIDELITY_REFERENCE:-$OUT/reference}"
SVG_DIR="$ROOT/Catalog/svg/autumn"
SPECIES_JSON="$ROOT/MapleKit/Sources/MapleCore/Resources/species.json"
GATES=(${=LEAF_FIDELITY_GATES:-})
mkdir -p "$OUT" "$REFERENCE" "$OUT/bin"

# 1. Reference rasters (cached).
stale=()
for svg in "$SVG_DIR"/acer-*.svg; do
  png="$REFERENCE/${svg:t}.png"
  [[ -s "$png" && "$png" -nt "$svg" ]] || stale+=("$svg")
done
if (( ${#stale} > 0 )); then
  echo "Rasterising ${#stale} export(s) with QuickLook..."
  qlmanage -t -s 512 -o "$REFERENCE" "${stale[@]}" >/dev/null 2>&1
fi

# 2. The port's renders (and the controls', in the same run).
echo "Rendering the Swift port..."
rm -rf "$OUT/port" "$OUT/controls"
LEAF_FIDELITY_CONTROLS=$CONTROLS MAPLE_CATALOG_SVG="$SVG_DIR" \
  "$ROOT/Scripts/snapshot.sh" "$ROOT/Scripts/snapshot/LeafFidelityScenes.swift" "$OUT/port" \
  | grep -v '^wrote ' || true
[[ -d "$OUT/port" ]] || { echo "The port's renders are missing; see the errors above." >&2; exit 1; }
if (( CONTROLS )); then
  for png in "$OUT"/port/*--acer-*.png(N); do
    name="${png:t}"
    control="${name%%--*}"
    mkdir -p "$OUT/controls/$control/port"
    mv "$png" "$OUT/controls/$control/port/${name#*--}"
  done
fi

# 3. Compare (the comparer is rebuilt only when its source changes).
COMPARE_SRC="$ROOT/Scripts/snapshot/LeafFidelityCompare.swift"
COMPARE_BIN="$OUT/bin/leaf-fidelity-compare"
if [[ ! -x "$COMPARE_BIN" || "$COMPARE_SRC" -nt "$COMPARE_BIN" ]]; then
  xcrun --sdk macosx swiftc -O -swift-version 6 -o "$COMPARE_BIN" "$COMPARE_SRC"
fi
failed=0
"$COMPARE_BIN" "$REFERENCE" "$OUT/port" "$OUT" "$SPECIES_JSON" "$SVG_DIR" "${GATES[@]}" || failed=1

# 4. Controls: the comparer must fail every broken drawing and pass the replica.
if (( CONTROLS )); then
  echo "\nNegative controls (full reports in $OUT/controls/<control>/report.txt):"
  controls=("$OUT"/controls/*(/N))
  if (( ${#controls} < 2 )); then
    echo "  WRONG: the controls were not rendered; see the errors above."
    failed=1
  fi
  for dir in "${controls[@]}"; do
    control="${dir:t}"
    if "$COMPARE_BIN" "$REFERENCE" "$dir/port" "$dir" "$SPECIES_JSON" "$SVG_DIR" "${GATES[@]}" > "$dir/report.txt"; then
      result=pass
    else
      result=fail
    fi
    failing="$(grep -E 'FAIL$' "$dir/report.txt" | sed -E 's/ +mean .*//' | paste -sd, - || true)"
    expected=fail
    [[ "$control" == replica ]] && expected=pass
    # A broken control only counts as caught when a gate fails, not when renders are missing.
    if [[ "$result" == "$expected" ]] && ! grep -q '^MISSING' "$dir/report.txt" \
       && [[ "$expected" == pass || -n "$failing" ]]; then
      verdict=ok
    else
      verdict=WRONG
      failed=1
    fi
    printf "  %-18s expected %-4s got %-4s %-5s %s\n" "$control" "$expected" "$result" "$verdict" "${failing:+failing: $failing}"
  done
fi
exit $failed
