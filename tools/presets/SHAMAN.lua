-- tools/presets/SHAMAN.lua
-- The Shaman presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-12): Lava Burst
-- (Elemental), Rage of the Farseer and Maelstrom Weapon (Enhancement),
-- Riptide and Water Shield (Restoration) are talents; Fire Nova is a spell
-- with a cooldown (needs a fire totem down), not a totem.
--   Shocks share one cooldown: Earth Shock's icon carries it; Flame Shock's
--   icon shows its DoT on the target while it runs (effect), then the shared
--   cooldown again. Frost Shock (the slow) is a debuff entry.
--   Short effects ride on their cooldown icon (effect): Rage of the Farseer
--   (25 sec), Nature's Swiftness (until the next Nature spell).
--   Not tracked: Purge, Tremor Totem, Totemic Recall, Totemic Projection
--   (no cooldown to show), Astral Recall (a hearthstone), weapon imbues
--   (enchants, not auras), Mana Tide (no aura on you in classic).
--   Long buffs (10 min shields, 5 min totems) remind while missing, out of
--   combat. Totem buffs pulse on you while you're in range, one totem per
--   element, so one slot per element from any shaman. No Fire slot: Searing
--   and Magma put no aura on you, and Windfury Weapon voids Flametongue
--   Totem's.

-- one elemental shield at a time (Water Shield is a Restoration talent)
local function shields(icon) return { group = "Shields", source = "mine", max = 1, icon = icon, missing = "remind",
    members = { "Lightning Shield", "Water Shield" } } end
-- the buffs totems put on you, per element (any shaman's totem counts)
local function totems(group, icon, members) return { group = group, source = "any", max = 1, icon = icon,
    missing = "remind", members = members } end
local EARTH = totems("Earth Totems", "Strength of Earth", { "Strength of Earth", "Stoneskin" })
local WATER = totems("Water Totems", "Mana Spring", { "Mana Spring", "Healing Stream", "Fire Resistance" })
local function air(icon) return totems("Air Totems", icon, { "Windfury Totem", "Grace of Air", "Windwall", "Nature Resistance" }) end

-- Flame Shock: the shared shock cooldown, its DoT on the icon while it runs
local FLAME_SHOCK = { "Flame Shock", effect = "target" }

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Earth Shock", FLAME_SHOCK, "Chain Lightning", "Fire Nova" },
      utility = { "Grounding Totem", "Stoneclaw Totem", "Earthbind Totem", "Reincarnation" },
      buffs = { shields("Lightning Shield"), EARTH, WATER, air("Grace of Air") },
      debuffs = { "Frost Shock", "Earthbind" },
      procs = {} },
    { id = "elemental", name = "Elemental", tree = 1,
      essential = { "Lava Burst", FLAME_SHOCK, "Earth Shock", "Chain Lightning", "Fire Nova" },
      utility = { "Grounding Totem", "Earthbind Totem", "Stoneclaw Totem", "Reincarnation" },
      buffs = { shields("Lightning Shield"), WATER, EARTH, air("Nature Resistance") },
      debuffs = { "Frost Shock", "Earthbind" },
      -- Elemental Focus
      procs = { "Clearcasting" } },
    { id = "enhancement", name = "Enhancement", tree = 2,
      -- Rage of the Farseer is Enhancement's burst, used on cooldown
      essential = { "Stormstrike", "Earth Shock", FLAME_SHOCK, { "Rage of the Farseer", effect = "you" } },
      utility = { "Fire Nova", "Grounding Totem", "Earthbind Totem", "Stoneclaw Totem", "Reincarnation" },
      buffs = { shields("Lightning Shield"), air("Windfury Totem"), EARTH, WATER },
      -- Stormstrike's debuff: your next Lightning Bolt, Chain Lightning or
      -- Earth Shock on the target hits 20% harder
      debuffs = { "Stormstrike", "Frost Shock", "Earthbind" },
      procs = { "Maelstrom Weapon", "Flurry", "Elemental Devastation" } },
    { id = "restoration", name = "Restoration", tree = 3,
      -- a healer's rotation has only Riptide, so the healing cooldowns sit
      -- in the big row; Earth Shock is the interrupt
      essential = { "Riptide", { "Nature's Swiftness", effect = "you" }, "Mana Tide Totem", "Earth Shock" },
      utility = { "Grounding Totem", "Earthbind Totem", "Stoneclaw Totem", "Reincarnation" },
      buffs = { shields("Water Shield"), WATER, EARTH, air("Windwall") },
      debuffs = { "Frost Shock" },
      procs = {} },
}
