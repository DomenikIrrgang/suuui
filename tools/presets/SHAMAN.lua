-- tools/presets/SHAMAN.lua
-- The Shaman presets (format: tools/presets_source.lua).


local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing, armors = S.mine, S.seal, S.blessing, S.armors
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Earth Shock", "Flame Shock", "Frost Shock", "Chain Lightning", "Fire Nova" },
      utility = { "Grounding Totem", "Stoneclaw Totem", "Earthbind Totem", "Totemic Recall", "Reincarnation" },
      buffs = { "Lightning Shield" },
      debuffs = { "Flame Shock", "Frost Shock", "Earthbind" },
      procs = {} },
    { id = "elemental", name = "Elemental", tree = 1,
      essential = { "Lava Burst", "Earth Shock", "Flame Shock", "Frost Shock", "Chain Lightning", "Fire Nova" },
      utility = { "Grounding Totem", "Stoneclaw Totem", "Earthbind Totem", "Totemic Recall", "Reincarnation", "Astral Recall" },
      buffs = { "Lightning Shield" },
      debuffs = { "Flame Shock", "Frost Shock", "Earthbind" },
      procs = { "Clearcasting" } },
    { id = "enhancement", name = "Enhancement", tree = 2,
      essential = { "Stormstrike", "Rage of the Farseer", "Earth Shock", "Flame Shock", "Frost Shock" },
      utility = { "Grounding Totem", "Fire Nova", "Stoneclaw Totem", "Earthbind Totem", "Totemic Recall", "Reincarnation" },
      buffs = { "Lightning Shield", "Rage of the Farseer" },
      debuffs = { "Stormstrike", "Flame Shock", "Frost Shock", "Earthbind" },
      procs = { "Maelstrom Weapon", "Flurry", "Elemental Devastation" } },
    { id = "restoration", name = "Restoration", tree = 3,
      essential = { "Riptide", "Nature's Swiftness", "Mana Tide Totem", "Earth Shock" },
      utility = { "Grounding Totem", "Tremor Totem", "Earthbind Totem", "Reincarnation", "Purge" },
      buffs = { "Water Shield", "Lightning Shield", "Nature's Swiftness", "Mana Spring", "Mana Tide Totem" },
      debuffs = { "Flame Shock", "Frost Shock" },
      procs = { "Clearcasting" } },
}
