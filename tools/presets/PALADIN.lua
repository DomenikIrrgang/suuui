-- tools/presets/PALADIN.lua
-- The Paladin presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-11): new
-- talents Light's Vigil and Voice of Truth (Holy), Swift Judgement and
-- Templar's Bulwark (Protection); Holy Strike is trained. Their buffs are
-- tracked as procs (shown only while up) until their aura names are seen.

local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing, armors = S.mine, S.seal, S.blessing, S.armors
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Judgement", "Hammer of Justice", "Consecration", "Holy Strike" },
      utility = { "Divine Shield", "Divine Protection", "Lay on Hands", "Blessing of Protection", "Blessing of Freedom", "Exorcism" },
      buffs = { seal("Seal of Righteousness"), blessing("Blessing of Might"), "Devotion Aura", "Divine Protection", "Divine Shield", "Blessing of Freedom", "Blessing of Protection" },
      debuffs = { MY_JUDGEMENT, "Hammer of Justice" },
      procs = {} },
    { id = "holy", name = "Holy", tree = 1,
      essential = { "Holy Shock", "Divine Favor", "Light's Vigil", "Lay on Hands", "Divine Shield" },
      utility = { "Voice of Truth", "Hammer of Justice", "Blessing of Protection", "Blessing of Freedom", "Divine Intervention", "Consecration", "Hammer of Wrath", "Exorcism", "Holy Wrath", "Turn Undead" },
      buffs = { seal("Seal of Wisdom"), blessing("Blessing of Wisdom"), "Divine Favor", "Divine Shield", "Divine Protection", "Blessing of Freedom", "Blessing of Protection", "Blessing of Sacrifice", "Concentration Aura", "Devotion Aura" },
      debuffs = { MY_JUDGEMENT, OTHERS_JUDGEMENTS, "Hammer of Justice" },
      procs = { "Light's Vigil", "Voice of Truth" } },
    { id = "protection", name = "Protection", tree = 2,
      essential = { "Holy Shield", "Holy Strike", "Consecration", "Judgement", "Swift Judgement", "Templar's Bulwark", "Hammer of Justice" },
      utility = { "Divine Shield", "Divine Protection", "Lay on Hands", "Blessing of Protection", "Blessing of Freedom", "Hammer of Wrath", "Holy Wrath", "Exorcism" },
      buffs = { seal("Seal of Fury"), blessing("Blessing of Kings"), "Holy Shield", "Righteous Fury", "Devotion Aura", "Divine Protection", "Divine Shield", "Blessing of Freedom", "Blessing of Protection", "Blessing of Sacrifice" },
      debuffs = { TAUNTS, MY_JUDGEMENT, OTHERS_JUDGEMENTS, "Hammer of Justice" },
      procs = { "Redoubt", "Templar's Bulwark", "Swift Judgement" } },
    { id = "retribution", name = "Retribution", tree = 3,
      essential = { "Judgement", "Holy Strike", "Consecration", "Exorcism", "Hammer of Wrath", "Repentance" },
      utility = { "Hammer of Justice", "Divine Shield", "Divine Protection", "Lay on Hands", "Blessing of Freedom", "Blessing of Protection", "Holy Wrath" },
      buffs = { seal("Seal of Command"), blessing("Blessing of Might"), "Retribution Aura", "Divine Shield", "Divine Protection", "Blessing of Freedom", "Blessing of Protection", "Blessing of Sacrifice" },
      debuffs = { MY_JUDGEMENT, OTHERS_JUDGEMENTS, "Repentance", "Hammer of Justice" },
      procs = { "Vengeance", "Vindication" } },
}
