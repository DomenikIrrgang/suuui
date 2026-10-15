#!/bin/sh
# tools/update_map_overlays.sh
# Refreshes src/Data/MapOverlays.lua (every area overlay of Forever's maps,
# for the world map's unexplored areas): fetches the build's
# WorldMapOverlay and WorldMapOverlayTile from wago.tools into a cache
# outside the repo, then regenerates the data file.
#   sh tools/update_map_overlays.sh [<build>]
set -e
cd "$(dirname "$0")/.."
BUILD=${1:-1.60.1.70338}
CACHE=${TMPDIR:-/tmp}/suuui-wago-$BUILD
mkdir -p "$CACHE"
for t in WorldMapOverlay WorldMapOverlayTile; do
    [ -s "$CACHE/$t.csv" ] || curl -sfL -o "$CACHE/$t.csv" "https://wago.tools/db2/$t/csv?build=$BUILD"
done
python3 -I tools/gen_map_overlays.py "$CACHE" "$BUILD" src/Data/MapOverlays.lua
