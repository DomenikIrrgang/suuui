-- tools/presets/HUNTER.lua
-- The Hunter presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-11): Aimed
-- Shot is trained, not a talent; new: Sniper Shot (Marksmanship talent and
-- trained ranks), Summon Hawk (Beast Mastery), Strider Kick (Survival);
-- Wyvern Sting doesn't exist. Tranquilizing Shot comes from a book.

local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing, armors = S.mine, S.seal, S.blessing, S.armors
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Arcane Shot", "Multi-Shot", "Raptor Strike", "Mongoose Bite", "Aimed Shot" },
      utility = { "Concussive Shot", "Feign Death", "Freezing Trap", "Immolation Trap", "Disengage", "Rapid Fire" },
      buffs = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah" },
      debuffs = { "Hunter's Mark", "Serpent Sting", "Wing Clip", "Concussive Shot" },
      procs = {} },
    { id = "beastmastery", name = "Beast Mastery", tree = 1,
      essential = { "Bestial Wrath", "Intimidation", "Rapid Fire", "Aimed Shot", "Multi-Shot", "Arcane Shot" },
      utility = { "Summon Hawk", "Concussive Shot", "Feign Death", "Freezing Trap", "Frost Trap", "Immolation Trap", "Explosive Trap", "Scare Beast", "Disengage" },
      buffs = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Wild", "Aspect of the Beast", "Trueshot Aura", "Rapid Fire" },
      debuffs = { "Hunter's Mark", "Serpent Sting", "Scorpid Sting", "Viper Sting", "Concussive Shot", "Wing Clip", "Freezing Trap", "Intimidation" },
      procs = { "Quick Shots", "Focused Fire" } },
    { id = "marksmanship", name = "Marksmanship", tree = 2,
      essential = { "Aimed Shot", "Sniper Shot", "Multi-Shot", "Arcane Shot", "Rapid Fire" },
      utility = { "Scatter Shot", "Concussive Shot", "Feign Death", "Freezing Trap", "Distracting Shot", "Flare", "Disengage" },
      buffs = { "Trueshot Aura", "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Rapid Fire" },
      debuffs = { "Hunter's Mark", "Serpent Sting", "Scorpid Sting", "Viper Sting", "Scatter Shot", "Concussive Shot" },
      procs = { "Quick Shots", "Rapid Killing", "Careful Aim" } },
    { id = "survival", name = "Survival", tree = 3,
      essential = { "Mongoose Bite", "Raptor Strike", "Counterattack", "Strider Kick", "Multi-Shot", "Arcane Shot" },
      utility = { "Deterrence", "Disengage", "Feign Death", "Freezing Trap", "Immolation Trap", "Explosive Trap", "Frost Trap", "Rapid Fire" },
      buffs = { "Aspect of the Monkey", "Aspect of the Hawk", "Deterrence", "Rapid Fire" },
      debuffs = { "Wing Clip", "Serpent Sting", "Hunter's Mark", "Counterattack", "Immolation Trap", "Explosive Trap", "Expose Prey", "Lacerating Strikes" },
      procs = { "Predator's Edge" } },
}
