#!/bin/sh
# tools/fetch_quest_starts.sh
# Downloads what tools/gen_quest_starts.lua reads, into a folder outside the
# repo: QuestieDB's Forever quests, NPCs, objects and items with their corrections,
# the enums the corrections use, Forever's area-to-map table and dungeon
# entrances (github.com/Questie/QuestieDB, no license stated), the Questie
# addon's quest tag corrections (github.com/Questie/Questie, no license stated: where
# the game's elite, dungeon or raid tag is wrong), and SOURCES (the
# commits) for the data file's header. Pull requests named
# after the folder (not merged yet) go on top as their diffs, only to the
# files fetched here (tools/apply_questiedb_pull.py); SOURCES records each
# one's head commit.
#   sh tools/fetch_quest_starts.sh <dir> [<pull request> ...]
# Then: lua tools/gen_quest_starts.lua <dir> src/Data/QuestStarts.lua src/Data/MapPlaces.lua
# Or both at once: sh tools/update_quest_starts.sh
set -e
DIR=${1:?usage: fetch_quest_starts.sh <dir> [<pull request> ...]}
shift
mkdir -p "$DIR"
SHA=$(curl -sfL https://api.github.com/repos/Questie/QuestieDB/commits/HEAD | sed -n 's/^  "sha": "\([0-9a-f]*\)".*/\1/p' | head -1)
[ -n "$SHA" ] || { echo "fetch_quest_starts: no QuestieDB commit (GitHub API)" >&2; exit 1; }
FILES="
    data/Forever/foreverQuestDB.lua data/Forever/foreverNpcDB.lua data/Forever/foreverObjectDB.lua \
    data/Forever/foreverItemDB.lua \
    src/corrections/enum/constants.lua src/corrections/enum/expansions.lua src/corrections/enum/zones.lua \
    src/corrections/enum/factions.lua src/corrections/enum/professions.lua src/corrections/enum/quests.lua \
    src/corrections/enum/items.lua \
    src/corrections/Forever/legacy/classicQuestFixes.lua src/corrections/Forever/legacy/classicNPCFixes.lua \
    src/corrections/Forever/legacy/classicObjectFixes.lua src/corrections/Forever/legacy/classicItemFixes.lua \
    src/corrections/Forever/generated/foreverBaseQuest.lua src/corrections/Forever/generated/foreverBaseNpc.lua \
    src/corrections/Forever/generated/foreverBaseObject.lua src/corrections/Forever/generated/foreverBaseItem.lua \
    src/corrections/Forever/foreverQuestFixes.lua src/corrections/Forever/foreverNPCFixes.lua \
    src/corrections/Forever/foreverObjectFixes.lua src/corrections/Forever/foreverItemFixes.lua \
    support/Forever/Zones/areaIdToUiMapId.lua support/Forever/Zones/dungeons.lua"
for p in $FILES; do
    mkdir -p "$DIR/$(dirname "$p")"
    curl -sfL -o "$DIR/$p" "https://raw.githubusercontent.com/Questie/QuestieDB/$SHA/$p"
done
QUESTIE=$(curl -sfL https://api.github.com/repos/Questie/Questie/commits/HEAD | sed -n 's/^  "sha": "\([0-9a-f]*\)".*/\1/p' | head -1)
[ -n "$QUESTIE" ] || { echo "fetch_quest_starts: no Questie commit (GitHub API)" >&2; exit 1; }
mkdir -p "$DIR/questie"
curl -sfL -o "$DIR/questie/questTagInfoCorrections.lua" \
    "https://raw.githubusercontent.com/Questie/Questie/$QUESTIE/Database/Corrections/questTagInfoCorrections.lua"
PRS=""
for pr in "$@"; do
    HEAD=$(curl -sfL "https://api.github.com/repos/Questie/QuestieDB/pulls/$pr" | sed -n 's/^    "sha": "\([0-9a-f]*\)".*/\1/p' | head -1)
    [ -n "$HEAD" ] || { echo "fetch_quest_starts: no pull request $pr (GitHub API)" >&2; exit 1; }
    curl -sfL -o "$DIR/pr$pr.diff" "https://github.com/Questie/QuestieDB/compare/$SHA...$HEAD.diff"
    python3 -I "$(dirname "$0")/apply_questiedb_pull.py" "$DIR" "$DIR/pr$pr.diff" $FILES
    PRS="$PRS #$pr@$(echo "$HEAD" | cut -c1-7)"
done
printf 'questiedb\t%s\nquestie\t%s\nfetched\t%s\n' "$SHA" "$QUESTIE" "$(date +%Y-%m-%d)" > "$DIR/SOURCES"
[ -z "$PRS" ] || printf 'pulls\t%s\n' "${PRS# }" >> "$DIR/SOURCES"
cat "$DIR/SOURCES"
