-- tools/presets/WARLOCK.lua
-- The Warlock presets (format: tools/presets_source.lua).
--
-- Forever's warlock (tools/data/class_warlock.tsv): Curse of Agony/Doom are
-- "Bane of Agony"/"Bane of Doom", plus Bane of Havoc (Destruction); one Bane
-- and one Curse per warlock per target, so each is one slot. Affliction:
-- Wrack (a 6 sec channelled DoT that raises your other Shadow DoTs' damage),
-- Siphon Life, Amplify Curse, Nightfall's Shadow Trance, Soul Harvest.
-- Demonology: Soul Link, Demonic Sacrifice (2 hours; Demonic Pact keeps it
-- with another demon out), Decimation (Soul Fire's cooldown -90%, so Soul
-- Fire is a rotation spell there; its 10 sec buff makes Soul Fire fast and
-- free), Demonic Brand. Destruction: Conflagrate, Shadowburn, Incinerate,
-- Shadow and Flame (20 sec buffs after Conflagrate / Shadowburn), Bane of
-- Havoc.
-- The warlock kit has few cooldowns, so the essential rows are short.
-- Cooldowns whose aura only matters while it runs (Shadow Ward, Amplify
-- Curse, Death Coil's horror, Fel Domination) show it on their icon
-- (effect) instead of a buff/debuff entry of their own.
-- Buffs of a minute or longer (armors, Soul Link, the sacrifice) are
-- reminders: grey only while missing, out of combat.
-- Debuffs: your DoTs are one collection (DoTs) and grey only with a hostile
-- target (the debuff default). The spec's core DoT (Corruption, Immolate)
-- warns instead, in combat only: a warn slot doesn't wait for a target, so
-- out of combat it would pulse on an empty row. In a group, other
-- warlocks' curses on your target show (Others' Curses, hidden while none
-- is up), so you pick a curse nobody has put up.
-- Fear and Banish show only while up (no combat condition: a Banish before
-- the pull keeps its timer).
-- Not tracked: Master Demonologist (automatic while a demon is out), pet
-- abilities (Spell Lock, Seduction: the pet's, not yours), Haunt (no
-- Forever warlock learns it), Bane of Doom as a cooldown (its cooldown runs
-- with its debuff, which is in the Banes slot: a cell for bosses only would
-- show the same minute twice).

local S = dofile("tools/presets/shared.lua")

-- Only one Bane per warlock on a target (Havoc is also limited to 1 target).
local function banes(icon) return { group = "Banes", source = "mine", max = 1, icon = icon,
    members = { "Bane of Agony", "Bane of Doom", "Bane of Havoc" } } end
-- Only one Curse per warlock on a target (Curse of Shadow isn't in Forever).
local function curses(icon) return { group = "Curses", source = "mine", max = 1, icon = icon,
    members = { "Curse of Weakness", "Curse of Recklessness", "Curse of the Elements", "Curse of Tongues", "Curse of Exhaustion" } } end
-- Other warlocks' curses on your target, in a group: a curse of the same
-- kind doesn't stack across warlocks, so cast another one.
local OTHERS_CURSES = { group = "Others' Curses", source = "others", max = 2, icon = "Curse of the Elements", missing = "hide",
    when = { conditions = { { type = "group", value = "solo", ["not"] = true } } },
    members = { "Curse of the Elements", "Curse of Recklessness", "Curse of Weakness", "Curse of Tongues" } }
-- One armor at a time; 30 min, kept up.
local function armors(icon) return { group = "Armors", source = "mine", max = 1, icon = icon, missing = "remind",
    members = { "Demon Skin", "Demon Armor" } } end
-- Demonic Sacrifice: one effect at a time (2 hours), named per demon.
local SACRIFICES = { group = "Sacrifices", source = "mine", max = 1, icon = "Burning Shadow", missing = "remind",
    members = { "Burning Shadow", "Touch of Fire", "Fel Stamina", "Fel Energy" } }

-- Your DoTs side by side.
local function dots(...) return { collection = "DoTs", entries = { ... } } end
-- The spec's core DoT: warns while missing, in combat.
local function core(name) return { name, missing = "warn", when = { conditions = { { type = "combat" } } } } end

-- cooldowns shared by every spec
local DEATH_COIL = { "Death Coil", effect = "target" }   -- the 3 sec horror
local SHADOW_WARD = { "Shadow Ward", effect = "you" }    -- 30 sec absorb
local CC = { { "Fear", missing = "hide" }, { "Banish", missing = "hide" } }

local function with(list, extra)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e end
    for _, e in ipairs(extra) do out[#out + 1] = e end
    return out
end

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { DEATH_COIL },
      utility = { SHADOW_WARD, "Howl of Terror", "Soul Fire" },
      buffs = { armors("Demon Skin") },
      debuffs = { dots("Corruption", banes("Bane of Agony"), "Immolate"), curses("Curse of Weakness"), OTHERS_CURSES,
          { "Fear", missing = "hide" } },
      procs = {} },
    { id = "affliction", name = "Affliction", tree = 1,
      essential = { { "Amplify Curse", effect = "you" }, DEATH_COIL },
      utility = { SHADOW_WARD, "Howl of Terror", "Soul Fire" },
      buffs = { armors("Demon Armor") },
      -- Corruption and the Bane carry the spec (Soul Siphon counts them)
      debuffs = with({ dots(core("Corruption"), banes("Bane of Agony"), "Siphon Life", "Immolate", { "Wrack", missing = "hide" }),
          curses("Curse of Weakness"), OTHERS_CURSES }, CC),
      -- Soul Harvest: 10 sec of mana regeneration after a Drain Soul kill
      procs = { "Shadow Trance", "Soul Harvest" } },
    { id = "demonology", name = "Demonology", tree = 2,
      -- Soul Fire: Decimation cuts its cooldown by 90%
      essential = { "Soul Fire", DEATH_COIL },
      utility = { { "Fel Domination", effect = "you" }, SHADOW_WARD, "Howl of Terror" },
      -- Soul Link lasts as long as the demon, so its reminder doubles as
      -- "your demon is out"
      buffs = { armors("Demon Armor"), { "Soul Link", missing = "remind" }, SACRIFICES },
      debuffs = with({ dots("Corruption", banes("Bane of Agony"), "Immolate"), curses("Curse of the Elements"), OTHERS_CURSES,
          { "Demonic Brand", missing = "hide" } }, CC),
      -- Decimation: Soul Fire fast and free for 10 sec (target below 35%)
      procs = { "Decimation" } },
    { id = "destruction", name = "Destruction", tree = 3,
      essential = { "Conflagrate", "Shadowburn", DEATH_COIL },
      utility = { SHADOW_WARD, "Howl of Terror", "Soul Fire" },
      buffs = { armors("Demon Armor") },
      -- Immolate feeds Conflagrate and Incinerate's bonus
      debuffs = with({ dots(core("Immolate"), banes("Bane of Agony"), "Corruption"), curses("Curse of the Elements"), OTHERS_CURSES,
          { "Shadow Vulnerability", missing = "hide" }, S.STUNS }, CC),
      -- Shadow and Flame: +10% Shadow (after Conflagrate) or Fire (after
      -- Shadowburn) damage for 20 sec
      procs = { "Shadow and Flame" } },
}
