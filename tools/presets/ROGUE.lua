-- tools/presets/ROGUE.lua
-- The Rogue presets (format: tools/presets_source.lua).


local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing, armors = S.mine, S.seal, S.blessing, S.armors
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Kick", "Gouge", "Kidney Shot", "Riposte" },
      utility = { "Sprint", "Evasion", "Vanish", "Blind", "Feint" },
      buffs = { "Slice and Dice", "Sprint", "Evasion", "Stealth" },
      debuffs = { "Rupture", "Garrote", "Expose Armor", "Gouge", "Kidney Shot", "Cheap Shot" },
      procs = {} },
    { id = "assassination", name = "Assassination", tree = 1,
      essential = { "Cold Blood", "Kidney Shot", "Kick", "Gouge", "Vanish" },
      utility = { "Sprint", "Evasion", "Blind", "Feint", "Distract", "Preparation" },
      buffs = { "Slice and Dice", "Venom", "Cold Blood", "Sprint", "Evasion", "Stealth" },
      debuffs = { "Rupture", "Garrote", "Deadly Poison", "Wound Poison", "Crippling Poison", "Mind-numbing Poison", "Expose Armor", "Kidney Shot", "Cheap Shot", "Gouge" },
      procs = { "Remorseless" } },
    { id = "combat", name = "Combat", tree = 2,
      essential = { "Blade Flurry", "Adrenaline Rush", "Riposte", "Kick", "Gouge" },
      utility = { "Sprint", "Evasion", "Vanish", "Blind", "Kidney Shot", "Feint" },
      buffs = { "Slice and Dice", "Blade Flurry", "Adrenaline Rush", "Evasion", "Sprint" },
      debuffs = { "Rupture", "Expose Armor", "Crippling Poison", "Wound Poison", "Deadly Poison", "Kidney Shot", "Gouge", "Riposte" },
      procs = {} },
    { id = "subtlety", name = "Subtlety", tree = 3,
      essential = { "Preparation", "Premeditation", "Ghostly Strike", "Kick", "Vanish" },
      utility = { "Sprint", "Evasion", "Blind", "Gouge", "Kidney Shot", "Distract" },
      buffs = { "Slice and Dice", "Ghostly Strike", "Stealth", "Evasion", "Sprint" },
      debuffs = { "Hemorrhage", "Rupture", "Garrote", "Expose Armor", "Sap", "Cheap Shot", "Kidney Shot", "Blind" },
      procs = { "Thousand Cuts", "Cutthroat" } },
}
