#!/bin/sh
# tools/update_quest_starts.sh
# Refreshes src/Data/QuestStarts.lua (where quests are picked up, and the
# dungeon entrances, for the world map) and src/Data/MapPlaces.lua (town
# services, mailboxes, rares, treasure chests) from QuestieDB's latest Forever data:
# fetches it into a cache outside the repo, then regenerates the data file.
#   sh tools/update_quest_starts.sh
# Check the summary line (quests, pins, maps, entrances) and the diff before
# committing; a new QuestieDB layout shows as errors from the generator.
set -e
cd "$(dirname "$0")/.."
CACHE=${TMPDIR:-/tmp}/suuui-questiedb-$(date +%Y%m%d%H%M%S)
sh tools/fetch_quest_starts.sh "$CACHE"
lua tools/gen_quest_starts.lua "$CACHE" src/Data/QuestStarts.lua src/Data/MapPlaces.lua
