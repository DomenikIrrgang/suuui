#!/bin/sh
# tools/fetch_quest_starts.sh
# Downloads what tools/gen_quest_starts.lua reads, into a folder outside the
# repo: QuestieDB's Forever quests, NPCs and objects with their corrections,
# the enums the corrections use, Forever's area-to-map table and dungeon
# entrances (github.com/Questie/QuestieDB, no license stated), and SOURCES
# (the QuestieDB commit) for the data file's header.
#   sh tools/fetch_quest_starts.sh <dir>
# Then: lua tools/gen_quest_starts.lua <dir> src/Data/QuestStarts.lua
# Or both at once: sh tools/update_quest_starts.sh
set -e
DIR=${1:?usage: fetch_quest_starts.sh <dir>}
mkdir -p "$DIR"
SHA=$(curl -sfL https://api.github.com/repos/Questie/QuestieDB/commits/HEAD | sed -n 's/^  "sha": "\([0-9a-f]*\)".*/\1/p' | head -1)
[ -n "$SHA" ] || { echo "fetch_quest_starts: no QuestieDB commit (GitHub API)" >&2; exit 1; }
for p in \
    data/Forever/foreverQuestDB.lua data/Forever/foreverNpcDB.lua data/Forever/foreverObjectDB.lua \
    src/corrections/enum/constants.lua src/corrections/enum/expansions.lua src/corrections/enum/zones.lua \
    src/corrections/enum/factions.lua src/corrections/enum/professions.lua src/corrections/enum/quests.lua \
    src/corrections/Forever/legacy/classicQuestFixes.lua src/corrections/Forever/legacy/classicNPCFixes.lua \
    src/corrections/Forever/legacy/classicObjectFixes.lua \
    src/corrections/Forever/generated/foreverBaseQuest.lua src/corrections/Forever/generated/foreverBaseNpc.lua \
    src/corrections/Forever/generated/foreverBaseObject.lua \
    src/corrections/Forever/foreverQuestFixes.lua src/corrections/Forever/foreverNPCFixes.lua \
    src/corrections/Forever/foreverObjectFixes.lua \
    support/Forever/Zones/areaIdToUiMapId.lua support/Forever/Zones/dungeons.lua; do
    mkdir -p "$DIR/$(dirname "$p")"
    curl -sfL -o "$DIR/$p" "https://raw.githubusercontent.com/Questie/QuestieDB/$SHA/$p"
done
printf 'questiedb\t%s\nfetched\t%s\n' "$SHA" "$(date +%Y-%m-%d)" > "$DIR/SOURCES"
cat "$DIR/SOURCES"
