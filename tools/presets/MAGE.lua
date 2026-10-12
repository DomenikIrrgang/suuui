-- tools/presets/MAGE.lua
-- The Mage presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-12): Arcane
-- Blast (Arcane) and Ice Lance (Frost) are new talents, also trained; Ice
-- Block is a Frost talent; Frostfire Bolt is trained; new proc talents
-- Missile Barrage, Heating Up, Fingers of Frost. No Arcane Brilliance, no
-- Molten Armor, and Polymorph is the only Polymorph a Forever mage learns (no
-- Pig/Turtle), so it needs no group.
--
-- How they're laid out:
--   * cooldowns whose buff or debuff only matters while it runs carry it as
--     their effect (Arcane Power, Presence of Mind, Combustion, Ice Block,
--     Ice Barrier, Evocation, the wards, Mana Shield on you; Frost Nova and
--     Cone of Cold on the target), so those auras have no entry of their own
--   * buffs you keep up (armor, Arcane Intellect; 30 min and more) remind
--     while missing, out of combat
--   * Missile Barrage, Heating Up and Fingers of Frost resolve to their
--     talents' IDs only so far (the scan lacks their proc auras' IDs); the
--     aura IDs belong in tools/data/found.tsv once /suu probe finds them

local S = dofile("tools/presets/shared.lua")
local armors = S.armors

-- one armor at a time; remind while none is up
local function armor(icon)
    local g = armors(icon)
    g.missing = "remind"
    return g
end
local INTELLECT = { "Arcane Intellect", missing = "remind" }

return {
    -- No talents: Clearcasting needs Arcane Concentration, so it only shows
    -- once a point goes there (harmless till then).
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Fire Blast", { "Frost Nova", effect = "target" }, { "Cone of Cold", effect = "target" }, "Counterspell" },
      utility = { "Blink", { "Evocation", effect = "you" }, { "Mana Shield", effect = "you" },
                  { "Fire Ward", effect = "you" }, { "Frost Ward", effect = "you" } },
      buffs = { armor("Frost Armor"), INTELLECT },
      debuffs = { "Polymorph", "Frostbolt", "Fireball" },
      procs = { "Clearcasting" } },

    -- Arcane Blast stacks into Arcane Missiles (Missile Barrage) under
    -- Clearcasting; Arcane Power and Presence of Mind are the spec's buttons.
    { id = "arcane", name = "Arcane", tree = 1,
      essential = { { "Arcane Power", effect = "you" }, { "Presence of Mind", effect = "you" },
                    "Fire Blast", { "Frost Nova", effect = "target" },
                    -- Improved Counterspell's silence covers the icon
                    { "Counterspell", effect = "target", effectName = "Counterspell - Silenced" } },
      utility = { "Blink", { "Evocation", effect = "you" }, { "Mana Shield", effect = "you" },
                  { "Ice Block", effect = "you" }, "Cone of Cold",
                  { "Fire Ward", effect = "you" }, { "Frost Ward", effect = "you" } },
      buffs = { armor("Mage Armor"), INTELLECT },
      debuffs = { "Polymorph" },
      -- Arcane Blast: the stacking buff on you (up to 4, 8 sec)
      procs = { "Clearcasting", "Missile Barrage", "Arcane Blast" } },

    -- Scorch keeps Fire Vulnerability stacked; crits build Heating Up for
    -- Pyroblast; Fireball/Frostfire Bolt filler, Fire Blast and Blast Wave.
    { id = "fire", name = "Fire", tree = 2,
      essential = { "Fire Blast", "Blast Wave", { "Frost Nova", effect = "target" },
                    { "Cone of Cold", effect = "target" }, "Counterspell" },
      utility = { { "Combustion", effect = "you" }, "Blink", { "Evocation", effect = "you" },
                  { "Ice Block", effect = "you" }, { "Mana Shield", effect = "you" },
                  { "Fire Ward", effect = "you" }, { "Frost Ward", effect = "you" } },
      buffs = { armor("Mage Armor"), INTELLECT },
      -- amber in time to refresh the stacks with Scorch
      debuffs = { { "Fire Vulnerability", expiring = 5 }, "Ignite", "Pyroblast", "Frostfire Bolt", "Polymorph" },
      procs = { "Heating Up", "Clearcasting" } },

    -- Frostbolt and Ice Lance on frozen targets (Frost Nova, Frostbite,
    -- Fingers of Frost); Ice Barrier on cooldown.
    { id = "frost", name = "Frost", tree = 3,
      essential = { { "Frost Nova", effect = "target" }, { "Cone of Cold", effect = "target" },
                    { "Ice Barrier", effect = "you" }, "Fire Blast", "Counterspell" },
      utility = { "Blink", { "Ice Block", effect = "you" }, "Cold Snap", { "Evocation", effect = "you" },
                  { "Frost Ward", effect = "you" }, { "Fire Ward", effect = "you" } },
      buffs = { armor("Ice Armor"), INTELLECT },
      -- Frostbite: the freeze (Ice Lance's window); Chilled: Improved Blizzard
      debuffs = { "Winter's Chill", "Frostbite", "Frostbolt", "Chilled", "Frostfire Bolt", "Polymorph" },
      procs = { "Fingers of Frost", "Clearcasting" } },
}
