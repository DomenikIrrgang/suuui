-- tools/presets/MAGE.lua
-- The Mage presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-11): Arcane
-- Blast (Arcane) and Ice Lance (Frost) are new talents, also trained; Ice
-- Block is a Frost talent; Frostfire Bolt is trained; new proc talents
-- Missile Barrage, Heating Up, Fingers of Frost.

local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing, armors = S.mine, S.seal, S.blessing, S.armors
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
   
      essential = { "Fire Blast", "Frost Nova", "Cone of Cold", "Counterspell" },
      utility = { "Blink", "Evocation", "Fire Ward", "Frost Ward" },
      buffs = { armors("Frost Armor"), "Arcane Intellect", "Mana Shield" },
      debuffs = { "Polymorph", "Frost Nova", "Frostbolt", "Fireball" },
      { "Clearcasting" } },
    { id = "arcane", name = "Arcane", tree = 1,
   
      essential = { "Arcane Power", "Presence of Mind", "Evocation", "Counterspell" },
      utility = { "Blink", "Frost Nova", "Cone of Cold", "Fire Blast", "Fire Ward", "Frost Ward" },
      buffs = { armors("Mage Armor"), "Arcane Intellect", "Arcane Power", "Presence of Mind", "Mana Shield", "Evocation" },
      debuffs = { "Polymorph", "Counterspell - Silenced", "Frost Nova" },
      { "Clearcasting", "Missile Barrage", "Arcane Blast" } },
    { id = "fire", name = "Fire", tree = 2,
   
      essential = { "Fire Blast", "Combustion", "Blast Wave", "Counterspell" },
      utility = { "Blink", "Frost Nova", "Cone of Cold", "Evocation", "Fire Ward" },
      buffs = { armors("Mage Armor"), "Combustion", "Arcane Intellect", "Fire Ward" },
      debuffs = { "Ignite", "Fire Vulnerability", "Pyroblast", "Fireball", "Blast Wave", "Frostfire Bolt", "Polymorph" },
      { "Clearcasting", "Heating Up" } },
    { id = "frost", name = "Frost", tree = 3,
   
      essential = { "Frost Nova", "Cone of Cold", "Ice Barrier", "Cold Snap", "Ice Block", "Counterspell" },
      utility = { "Blink", "Evocation", "Fire Blast", "Frost Ward", "Fire Ward" },
      buffs = { armors("Ice Armor"), "Ice Barrier", "Arcane Intellect", "Frost Ward", "Ice Block" },
      debuffs = { "Frostbolt", "Frost Nova", "Cone of Cold", "Winter's Chill", "Frostbite", "Chilled", "Frostfire Bolt", "Polymorph" },
      { "Clearcasting", "Fingers of Frost" } },
}
