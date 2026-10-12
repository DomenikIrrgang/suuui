-- tools/presets/MAGE.lua
-- The Mage presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-12): Arcane
-- Blast (Arcane) and Ice Lance (Frost) are new talents, also trained; Ice
-- Block is a Frost talent; Frostfire Bolt is trained; new proc talents
-- Missile Barrage, Heating Up (Hot Streak its instant Pyroblast), Fingers
-- of Frost (their aura IDs in tools/data/found.tsv). No Arcane Brilliance,
-- no Molten Armor, and Polymorph is the only Polymorph a Forever mage learns
-- (no Pig/Turtle), so it needs no group.
--
-- How they're laid out:
--   * cooldowns whose buff or debuff only matters while it runs carry it as
--     their effect (Arcane Power, Presence of Mind, Combustion, Ice Block,
--     Ice Barrier, Evocation, the wards, Mana Shield on you; Frost Nova and
--     Cone of Cold on the target), so those auras have no entry of their own
--   * Frost Nova's cell is gone while a boss is targeted (bosses don't root)
--   * Fire Ward and Frost Ward stay two cells: the class data carries no
--     cooldowns for trainer spells, so a shared cooldown isn't confirmed
--     (and one cell would show only the last ward learned, Frost Ward)
--   * buffs you keep up (armor, Arcane Intellect, from anyone; 30 min and
--     more) remind while missing, out of combat
--   * debuffs: Polymorph, Fireball's, Pyroblast's and Frostfire Bolt's DoTs
--     show only while up (no grey slot on every hostile target); Frostbolt's
--     slow stays grey with a hostile target (kiting). Talent auras (Fire
--     Vulnerability, Ignite, Winter's Chill, Frostbite, Chilled) are spells
--     you know no rank of, so they show only while up anyway. Fire
--     Vulnerability, Ignite and Winter's Chill are one debuff per target
--     that every mage feeds: from anyone.
--   * Stuns (Impact only, a proc) show only while one is up

local S = dofile("tools/presets/shared.lua")
local armors = S.armors

-- one armor at a time; remind while none is up
local function armor(icon)
    local g = armors(icon)
    g.missing = "remind"
    return g
end
local INTELLECT = { "Arcane Intellect", missing = "remind" }
local POLYMORPH = { "Polymorph", missing = "hide" }
local function notBoss() return { conditions = { { type = "target", kinds = { "boss" }, ["not"] = true } } } end
local FROST_NOVA = { "Frost Nova", effect = "target", when = notBoss() }
local STUNS = S.with(S.STUNS, { missing = "hide" })

-- Fire's debuffs on the target, side by side: Scorch's stacks (amber in
-- time to refresh them), Ignite, Pyroblast's and Frostfire Bolt's DoTs.
local FIRE_DEBUFFS = { collection = "Fire Debuffs", entries = {
    { "Fire Vulnerability", source = "any", missing = "hide", expiring = 5 },
    { "Ignite", source = "any", missing = "hide" },
    { "Pyroblast", missing = "hide" },
    { "Frostfire Bolt", missing = "hide" } } }

return {
    -- No talents: Clearcasting needs Arcane Concentration, so it only shows
    -- once a point goes there (harmless till then).
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Fire Blast", FROST_NOVA, { "Cone of Cold", effect = "target" }, "Counterspell" },
      utility = { "Blink", { "Evocation", effect = "you" }, { "Mana Shield", effect = "you" },
                  { "Fire Ward", effect = "you" }, { "Frost Ward", effect = "you" } },
      buffs = { armor("Frost Armor"), INTELLECT },
      debuffs = { "Frostbolt", { "Fireball", missing = "hide" }, POLYMORPH },
      procs = { "Clearcasting" } },

    -- Arcane Blast stacks into Arcane Missiles (Missile Barrage) under
    -- Clearcasting; Arcane Power and Presence of Mind are the spec's buttons.
    { id = "arcane", name = "Arcane", tree = 1,
      essential = { { "Arcane Power", effect = "you" }, { "Presence of Mind", effect = "you" },
                    "Fire Blast", FROST_NOVA,
                    -- Improved Counterspell's silence covers the icon
                    { "Counterspell", effect = "target", effectName = "Counterspell - Silenced" } },
      utility = { "Blink", { "Evocation", effect = "you" }, { "Mana Shield", effect = "you" },
                  { "Ice Block", effect = "you" }, "Cone of Cold",
                  { "Fire Ward", effect = "you" }, { "Frost Ward", effect = "you" } },
      buffs = { armor("Mage Armor"), INTELLECT },
      debuffs = { POLYMORPH },
      -- Arcane Blast: the stacking buff on you (up to 4, 8 sec)
      procs = { "Clearcasting", "Missile Barrage", "Arcane Blast" } },

    -- Scorch keeps Fire Vulnerability stacked; crits build Heating Up, then
    -- Hot Streak's instant Pyroblast; Fireball/Frostfire Bolt filler, Fire
    -- Blast and Blast Wave.
    { id = "fire", name = "Fire", tree = 2,
      essential = { "Fire Blast", "Blast Wave", FROST_NOVA,
                    { "Cone of Cold", effect = "target" }, "Counterspell" },
      utility = { { "Combustion", effect = "you" }, "Blink", { "Evocation", effect = "you" },
                  { "Ice Block", effect = "you" }, { "Mana Shield", effect = "you" },
                  { "Fire Ward", effect = "you" }, { "Frost Ward", effect = "you" } },
      buffs = { armor("Mage Armor"), INTELLECT },
      debuffs = { FIRE_DEBUFFS, POLYMORPH, STUNS },
      -- Hot Streak: the cue to press Pyroblast
      procs = { { "Hot Streak", glow = true, soundAppear = "proc" }, "Heating Up", "Clearcasting" } },

    -- Frostbolt and Ice Lance on frozen targets (Frost Nova, Frostbite,
    -- Fingers of Frost); Ice Barrier on cooldown.
    { id = "frost", name = "Frost", tree = 3,
      essential = { FROST_NOVA, { "Cone of Cold", effect = "target" },
                    { "Ice Barrier", effect = "you" }, "Fire Blast", "Counterspell" },
      utility = { "Blink", { "Ice Block", effect = "you" }, "Cold Snap", { "Evocation", effect = "you" },
                  { "Frost Ward", effect = "you" }, { "Fire Ward", effect = "you" } },
      buffs = { armor("Ice Armor"), INTELLECT },
      -- Frostbite: the freeze (Ice Lance's window); Chilled: Improved
      -- Blizzard's and Frost/Ice Armor's slow
      debuffs = { { "Winter's Chill", source = "any" }, "Frostbite", "Frostbolt", "Chilled",
                  { "Frostfire Bolt", missing = "hide" }, POLYMORPH },
      procs = { "Fingers of Frost", "Clearcasting" } },
}
