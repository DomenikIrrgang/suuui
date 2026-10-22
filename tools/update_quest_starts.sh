#!/bin/sh
# tools/update_quest_starts.sh
# Refreshes src/Data/QuestStarts.wowlua (where quests are picked up, and the
# dungeon entrances, for the world map) and src/Data/MapPlaces.wowlua (town
# services, mailboxes, rares, treasure chests) from QuestieDB's latest Forever data:
# fetches it into a cache outside the repo, then regenerates the data file.
#   sh tools/update_quest_starts.sh
# Check the summary line (quests, pins, maps, entrances) and the diff before
# committing; a new QuestieDB layout shows as errors from the generator.
set -e
cd "$(dirname "$0")/.."
# QuestieDB pull requests taken before they're merged (drop each once it is):
# #103 the vendor flag on vendors that lost it
PULLS="103"
CACHE=${TMPDIR:-/tmp}/suuui-questiedb-$(date +%Y%m%d%H%M%S)
sh tools/fetch_quest_starts.sh "$CACHE" $PULLS
lua tools/gen_quest_starts.lua "$CACHE" src/Data/QuestStarts.wowlua src/Data/MapPlaces.wowlua
