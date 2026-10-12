-- tools/presets/WARRIOR.lua
-- The Warrior presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-11): new
-- talent Spearing Strike (Arms); Victory Rush is trained (its IDs came from
-- /suu probe spells find, tools/data/found.tsv); possible procs
-- from new passives (Bloodthrill, Raging Blows, Bastion) are tracked as
-- procs, which show only while up. Taunt isn't on the trainer list (known
-- already at level 10).

local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing, armors = S.mine, S.seal, S.blessing, S.armors
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Bloodrage", "Overpower", "Execute", "Victory Rush", "Thunder Clap" },
      utility = { "Charge", "Intercept", "Berserker Rage", "Pummel", "Shield Bash", "Disarm" },
      buffs = { "Battle Shout", "Bloodrage" },
      debuffs = { "Rend", "Thunder Clap", "Demoralizing Shout", "Hamstring", "Sunder Armor" },
      procs = { "Enrage" } },
    { id = "arms", name = "Arms", tree = 1,
      essential = { "Mortal Strike", "Overpower", "Spearing Strike", "Sweeping Strikes", "Whirlwind", "Victory Rush", "Bloodrage" },
      utility = { "Charge", "Intercept", "Pummel", "Berserker Rage", "Intimidating Shout", "Recklessness", "Retaliation", "Thunder Clap" },
      buffs = { "Battle Shout", "Sweeping Strikes", "Recklessness", "Retaliation", "Berserker Rage", "Bloodrage" },
      debuffs = { "Rend", "Mortal Strike", "Sunder Armor", "Hamstring", "Thunder Clap", "Demoralizing Shout", "Deep Wounds" },
      procs = { "Bloodthrill" } },
    { id = "fury", name = "Fury", tree = 2,
      essential = { "Bloodthirst", "Whirlwind", "Death Wish", "Victory Rush", "Bloodrage" },
      utility = { "Pummel", "Intercept", "Berserker Rage", "Recklessness", "Intimidating Shout", "Piercing Howl", "Charge" },
      buffs = { "Battle Shout", "Death Wish", "Recklessness", "Berserker Rage", "Bloodrage" },
      debuffs = { "Sunder Armor", "Rend", "Demoralizing Shout", "Hamstring", "Piercing Howl", "Deep Wounds" },
      procs = { "Flurry", "Enrage", "Raging Blows" } },
    { id = "protection", name = "Protection", tree = 3,
      essential = { "Shield Slam", "Revenge", "Shield Block", "Taunt", "Concussion Blow", "Bloodrage" },
      utility = { "Charge", "Shield Wall", "Last Stand", "Challenging Shout", "Shield Bash", "Mocking Blow", "Disarm", "Berserker Rage", "Intercept", "Victory Rush" },
      buffs = { "Battle Shout", "Shield Block", "Last Stand", "Shield Wall", "Bloodrage" },
      debuffs = { TAUNTS, "Sunder Armor", "Rend", "Thunder Clap", "Demoralizing Shout", "Concussion Blow", "Disarm" },
      procs = { "Bastion", "Enrage" } },
}
