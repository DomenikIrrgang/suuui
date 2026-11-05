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
# #135 An Enticing Offer's objectives; #136 Desperate Prayer dwarves only;
# #137 Divine Grace and Confounding Flash variants exclusive (asked
# 2026-11-05; #72's NPC titles, services and item sources are in main already)
PULLS="135 136 137"
CACHE=${TMPDIR:-/tmp}/suuui-questiedb-$(date +%Y%m%d%H%M%S)
sh tools/fetch_quest_starts.sh "$CACHE" $PULLS
lua tools/gen_quest_starts.lua "$CACHE" src/Data/QuestStarts.wowlua src/Data/MapPlaces.wowlua
