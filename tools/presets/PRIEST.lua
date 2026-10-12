-- tools/presets/PRIEST.lua
-- The Priest presets (format: tools/presets_source.lua).


local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing, armors = S.mine, S.seal, S.blessing, S.armors
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Power Word: Shield", "Mind Blast", "Psychic Scream", "Fade" },
      utility = { "Fear Ward" },
      buffs = { "Power Word: Fortitude", "Inner Fire", "Power Word: Shield", "Renew", "Fade" },
      debuffs = { "Shadow Word: Pain", "Mind Flay" },
      procs = {} },
    { id = "discipline", name = "Discipline", tree = 1,
      essential = { "Penance", "Power Infusion", "Inner Focus", "Power Word: Shield" },
      utility = { "Psychic Scream", "Fade", "Fear Ward" },
      buffs = { "Power Word: Fortitude", "Divine Spirit", "Inner Fire", "Power Word: Shield", "Power Infusion", "Inner Focus", "Fear Ward", "Shadow Protection", "Fade" },
      debuffs = { "Shadow Word: Pain" },
      procs = { "Focused Casting" } },
    { id = "holy", name = "Holy", tree = 2,
      essential = { "Prayer of Mending", "Power Word: Shield", "Fear Ward" },
      utility = { "Psychic Scream", "Fade" },
      buffs = { "Inner Fire", "Power Word: Fortitude", "Divine Spirit", "Fear Ward", "Renew", "Prayer of Mending", "Fade" },
      debuffs = { "Shadow Word: Pain" },
      procs = {} },
    { id = "shadow", name = "Shadow", tree = 3,
      essential = { "Mind Blast", "Silence", "Psychic Scream", "Fade" },
      utility = { "Inner Focus", "Power Word: Shield", "Devouring Plague", "Fear Ward" },
      buffs = { "Shadowform", "Inner Fire", "Power Word: Fortitude", "Shadow Protection", "Power Word: Shield", "Fade" },
      debuffs = { "Shadow Word: Pain", "Vampiric Embrace", "Mind Flay", "Devouring Plague", "Shadow Vulnerability", "Silence", "Psychic Scream", "Blackout" },
      procs = { "Shadow Weaving", "Spirit Tap" } },
}
