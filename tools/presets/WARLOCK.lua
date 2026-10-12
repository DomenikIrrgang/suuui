-- tools/presets/WARLOCK.lua
-- The Warlock presets (format: tools/presets_source.lua).


local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing, armors = S.mine, S.seal, S.blessing, S.armors
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Death Coil", "Shadow Ward", "Howl of Terror" },
      utility = {},
      buffs = { "Demon Skin", "Demon Armor", "Shadow Ward" },
      debuffs = { "Corruption", "Bane of Agony", "Immolate", "Fear", "Curse of Weakness" },
      procs = { "Shadow Trance" } },
    { id = "affliction", name = "Affliction", tree = 1,
      essential = { "Amplify Curse", "Death Coil", "Howl of Terror", "Shadow Ward" },
      utility = { "Fel Domination", "Bane of Doom" },
      buffs = { "Demon Armor", "Demon Skin", "Shadow Ward", "Amplify Curse" },
      debuffs = { "Corruption", "Bane of Agony", "Wrack", "Siphon Life", "Curse of Exhaustion", "Curse of Weakness", "Curse of Tongues", "Curse of the Elements", "Curse of Recklessness", "Bane of Doom", "Drain Life", "Drain Soul", "Fear", "Death Coil", "Immolate" },
      procs = { "Shadow Trance" } },
    { id = "demonology", name = "Demonology", tree = 2,
      essential = { "Fel Domination", "Death Coil", "Shadow Ward" },
      utility = { "Howl of Terror", "Bane of Doom" },
      buffs = { "Demon Armor", "Soul Link", "Shadow Ward", "Touch of Fire", "Burning Shadow", "Fel Stamina", "Fel Energy" },
      debuffs = { "Corruption", "Bane of Agony", "Immolate", "Fear", "Death Coil", "Banish" },
      procs = { "Shadow Trance" } },
    { id = "destruction", name = "Destruction", tree = 3,
      essential = { "Conflagrate", "Shadowburn", "Death Coil", "Shadow Ward" },
      utility = { "Howl of Terror", "Bane of Havoc", "Fel Domination" },
      buffs = { "Demon Armor", "Shadow Ward" },
      debuffs = { "Immolate", "Bane of Havoc", "Corruption", "Curse of the Elements", "Shadow Vulnerability", "Shadowburn" },
      procs = { "Shadow Trance" } },
}
