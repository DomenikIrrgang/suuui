#!/bin/sh
# tools/update_flight_routes.sh
# Refreshes src/Data/FlightRoutes.lua (how far each flight master's route
# flies, for the flight times): fetches the build's TaxiPath, TaxiPathNode
# and TaxiNodes from wago.tools into a cache outside the repo, then
# regenerates the data file.
#   sh tools/update_flight_routes.sh [<build>]
set -e
cd "$(dirname "$0")/.."
BUILD=${1:-1.60.1.70338}
CACHE=${TMPDIR:-/tmp}/suuui-wago-$BUILD
mkdir -p "$CACHE"
for t in TaxiPath TaxiPathNode TaxiNodes; do
    [ -s "$CACHE/$t.csv" ] || curl -sfL -o "$CACHE/$t.csv" "https://wago.tools/db2/$t/csv?build=$BUILD"
done
python3 -I tools/gen_flight_routes.py "$CACHE" "$BUILD" src/Data/FlightRoutes.lua
