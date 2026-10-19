-- tools/presets/SHAMAN.lua
-- The Shaman presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-12): Lava Burst
-- (Elemental), Rage of the Farseer and Maelstrom Weapon (Enhancement),
-- Riptide and Water Shield (Restoration) are talents; Fire Nova is a spell
-- with a cooldown (needs a fire totem down), not a totem.
--   Shocks share one cooldown, so they are one cell (Shocks: Earth Shock's
--   icon, the interrupt). Flame Shock's DoT and Frost Shock's slow are
--   debuff entries, not effects: an effect would hide the shared cooldown
--   for the DoT's 12 sec.
--   Short effects ride on their cooldown icon (effect): Stormstrike's debuff
--   (your next nature spell on the target), Rage of the Farseer (25 sec),
--   Nature's Swiftness (until the next Nature spell).
--   Situational debuffs (Frost Shock, Earthbind) show only while up.
--   Earthbind is the totem's, from any shaman (a totem's aura may not count
--   as yours).
--   Not tracked: Purge, Tremor Totem, Totemic Recall, Totemic Projection
--   (no cooldown to show), Astral Recall (a hearthstone), Mana Tide's aura
--   (none on you in classic; its cooldown has no condition: solo it
--   restores your own mana).
--   Weapon imbues: the main hand's enchant entry (Rockbiter from level 1),
--   Enhancement's off hand too (shown only with a weapon there); they warn
--   out of combat while the weapon has none.
--   Maelstrom Weapon's aura IDs come from tools/data/found.tsv (/suu probe
--   spells find), the passive talent's ID left out.
--   Lightning Shield / Water Shield (10 min) reminds while missing, out of
--   combat. Totems: one Totems collection, a slot per element from any
--   shaman, shown only while up (totems go down at the pull: a reminder out
--   of combat would always show; most totem buffs aren't spells you know
--   anyway). No Fire slot: Searing and Magma put no aura on you, and
--   Windfury Weapon voids Flametongue Totem's.

-- one elemental shield at a time (Water Shield is a Restoration talent)
local S = dofile("tools/presets/shared.lua")
local function shields(icon) return { group = "Shields", source = "mine", max = 1, icon = icon, missing = "remind",
    members = { "Lightning Shield", "Water Shield" } } end
-- the buffs totems put on you, per element (any shaman's totem counts)
local function element(group, icon, members) return { group = group, source = "any", max = 1, icon = icon,
    missing = "hide", members = members } end
local EARTH = element("Earth Totems", "Strength of Earth", { "Strength of Earth", "Stoneskin" })
local WATER = element("Water Totems", "Mana Spring", { "Mana Spring", "Healing Stream", "Fire Resistance" })
local function air(icon) return element("Air Totems", icon, { "Windfury Totem", "Grace of Air", "Windwall", "Nature Resistance" }) end
local function totems(...) return { collection = "Totems", entries = { ... } } end

-- the shared shock cooldown: the last one you know (Earth Shock from level 4)
local SHOCKS = { group = "Shocks", icon = "Earth Shock", members = { "Frost Shock", "Flame Shock", "Earth Shock" } }
local FROST_SHOCK = { "Frost Shock", missing = "hide" }
-- the imbue on each weapon (whichever: Rockbiter, Flametongue, Windfury...)
local MAIN_HAND, OFF_HAND = { enchant = "main" }, { enchant = "off" }
local EARTHBIND = { "Earthbind", source = "any", missing = "hide" }

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { SHOCKS, "Chain Lightning", "Fire Nova" },
      utility = { "Grounding Totem", "Stoneclaw Totem", "Earthbind Totem", "Reincarnation" },
      buffs = { shields("Lightning Shield"), MAIN_HAND, totems(EARTH, WATER, air("Grace of Air")) },
      debuffs = { "Flame Shock", FROST_SHOCK, EARTHBIND },
      procs = {} },
    { id = "elemental", name = "Elemental", tree = 1,
      essential = { "Lava Burst", SHOCKS, "Chain Lightning", "Fire Nova" },
      utility = { "Grounding Totem", "Earthbind Totem", "Stoneclaw Totem", "Reincarnation" },
      buffs = { shields("Lightning Shield"), MAIN_HAND, totems(WATER, EARTH, air("Nature Resistance")) },
      -- Flame Shock kept up (Lava Burst crits on it)
      debuffs = { "Flame Shock", FROST_SHOCK, EARTHBIND },
      -- Elemental Focus
      procs = { "Clearcasting" } },
    { id = "enhancement", name = "Enhancement", tree = 2,
      -- Stormstrike's debuff (your next Lightning Bolt, Chain Lightning or
      -- Earth Shock on the target hits 20% harder) on its icon; Rage of the
      -- Farseer is Enhancement's burst, used on cooldown
      essential = { { "Stormstrike", effect = "target" }, SHOCKS, { "Rage of the Farseer", effect = "you" } },
      utility = { "Fire Nova", "Grounding Totem", "Earthbind Totem", "Stoneclaw Totem", "Reincarnation" },
      buffs = { shields("Lightning Shield"), MAIN_HAND, OFF_HAND, totems(air("Windfury Totem"), EARTH, WATER) },
      debuffs = { "Flame Shock", FROST_SHOCK, EARTHBIND, S.physical() },
      procs = { "Maelstrom Weapon", "Flurry", "Elemental Devastation" } },
    { id = "restoration", name = "Restoration", tree = 3,
      -- a healer's rotation has only Riptide, so the healing cooldowns sit
      -- in the big row; the shock is the interrupt
      essential = { "Riptide", { "Nature's Swiftness", effect = "you" }, "Mana Tide Totem", SHOCKS },
      utility = { "Grounding Totem", "Earthbind Totem", "Stoneclaw Totem", "Reincarnation" },
      buffs = { shields("Water Shield"), MAIN_HAND, totems(WATER, EARTH, air("Windwall")) },
      debuffs = { FROST_SHOCK },
      procs = {} },
}
