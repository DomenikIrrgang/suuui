#!/bin/sh
# tools/update_recipe_sources.sh
# Refreshes src/Data/RecipeSources.wowlua: merges the profession trainers SuuUI
# recorded in game into tools/data/trainer_records.tsv, fetches the build's
# ItemSparse (the skill each recipe item needs; 70338's for the recipe items
# later builds no longer ship) from wago.tools into a cache outside the
# repo, and regenerates the data file.
#   sh tools/update_recipe_sources.sh [<SuuUI.lua SavedVariables> ...]
#   (default: the SavedVariables of every WoW Forever account)
set -e
cd "$(dirname "$0")/.."
BUILD=1.60.1.70862
OLD=1.60.1.70338
CACHE=${TMPDIR:-/tmp}/suuui-wago-$BUILD
OLDCACHE=${TMPDIR:-/tmp}/suuui-wago-$OLD
mkdir -p "$CACHE" "$OLDCACHE"
[ -s "$CACHE/ItemSparse.csv" ] || curl -sfL -o "$CACHE/ItemSparse.csv" "https://wago.tools/db2/ItemSparse/csv?build=$BUILD"
[ -s "$OLDCACHE/ItemSparse.csv" ] || curl -sfL -o "$OLDCACHE/ItemSparse.csv" "https://wago.tools/db2/ItemSparse/csv?build=$OLD"
if [ $# -eq 0 ]; then
    set -- "/Applications/World of Warcraft/_forever_/WTF/Account/"*/SavedVariables/SuuUI.lua
fi
lua tools/merge_trainer_records.lua tools/data/trainer_records.tsv "$@"
python3 -I tools/gen_recipe_sources.py tools/data/forever_recipes.json src/Data/RecipeSources.wowlua \
    --itemsparse "$CACHE/ItemSparse.csv" --itemsparse-old "$OLDCACHE/ItemSparse.csv" --trainers tools/data/trainer_records.tsv \
    --cmangos tools/data/cmangos_trainers.tsv
