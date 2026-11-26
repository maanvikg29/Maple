#!/bin/sh
# Fails when the image sets in the catalog differ from what the generator draws.
set -e
cd "$(dirname "$0")/../.."
python3 -I Scripts/art/build_van_art.py >/dev/null
if ! git diff --quiet -- App/Resources/Assets.xcassets/Van; then
    echo "The van's image sets are out of date: run python3 -I Scripts/art/build_van_art.py and commit." >&2
    git diff --stat -- App/Resources/Assets.xcassets/Van >&2
    exit 1
fi
echo "The van's image sets match the generator."
