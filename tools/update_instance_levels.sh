#!/bin/sh
# tools/update_instance_levels.sh
# Refreshes src/Data/InstanceLevels.lua (the recommended levels of dungeons,
# raids and battlegrounds, for the world map's entrances): fetches the
# build's GroupFinderActivity from wago.tools into a cache outside the repo,
# then regenerates the data file.
#   sh tools/update_instance_levels.sh [<build>]
set -e
cd "$(dirname "$0")/.."
BUILD=${1:-1.60.1.70338}
CACHE=${TMPDIR:-/tmp}/suuui-wago-$BUILD
mkdir -p "$CACHE"
for t in GroupFinderActivity; do
    [ -s "$CACHE/$t.csv" ] || curl -sfL -o "$CACHE/$t.csv" "https://wago.tools/db2/$t/csv?build=$BUILD"
done
python3 -I tools/gen_instance_levels.py "$CACHE" "$BUILD" src/Data/InstanceLevels.lua
