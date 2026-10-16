#!/bin/sh
# tools/fetch_recipe_sources.sh
# Downloads what tools/gen_recipes.py and tools/gen_collection_sources.py
# join, into a folder outside the repo:
#   <dir>/wago       client tables (DB2) of Forever's build from wago.tools
#   <dir>/questiedb  QuestieDB's Forever items, NPCs, objects and corrections
#                    (github.com/Questie/QuestieDB, no license stated)
#   <dir>/SOURCES    the build and the QuestieDB commit, for the data's header
#   sh tools/fetch_recipe_sources.sh <dir> [build]   (build: 1.60.1.70338)
set -e
DIR=${1:?usage: fetch_recipe_sources.sh <dir> [build]}
BUILD=${2:-1.60.1.70338}
mkdir -p "$DIR/wago" "$DIR/questiedb"
for t in SkillLine SkillLineAbility TradeSkillCategory SpellName SpellEffect SpellReagents \
         ItemEffect ItemXItemEffect ItemSparse AreaTable Mount Toy ItemModifiedAppearance; do
    curl -sfL -o "$DIR/wago/$t.csv" "https://wago.tools/db2/$t/csv?build=$BUILD"
done
SHA=$(curl -sfL https://api.github.com/repos/Questie/QuestieDB/commits/HEAD | sed -n 's/^  "sha": "\([0-9a-f]*\)".*/\1/p' | head -1)
for p in data/Forever/foreverItemDB.lua data/Forever/foreverNpcDB.lua data/Forever/foreverObjectDB.lua \
         src/corrections/Forever/generated/foreverBaseItem.lua src/corrections/Forever/foreverItemFixes.lua \
         src/corrections/Forever/traces/foreverItemTraces.lua src/corrections/Forever/generated/foreverBaseNpc.lua \
         src/corrections/Forever/foreverNPCFixes.lua; do
    mkdir -p "$DIR/questiedb/$(dirname "$p")"
    curl -sfL -o "$DIR/questiedb/$p" "https://raw.githubusercontent.com/Questie/QuestieDB/$SHA/$p"
done
printf 'build\t%s\nquestiedb\t%s\nfetched\t%s\n' "$BUILD" "$SHA" "$(date +%Y-%m-%d)" > "$DIR/SOURCES"
cat "$DIR/SOURCES"
