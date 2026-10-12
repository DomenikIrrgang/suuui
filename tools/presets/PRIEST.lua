-- tools/presets/PRIEST.lua
-- The Priest presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-12): Penance,
-- Power Infusion and Inner Focus are Discipline talents (Soul Warding takes
-- Power Word: Shield's cooldown off, Martyrdom gives Focused Casting);
-- Prayer of Mending, Binding Heal and Holy Nova are Holy talents (Searing
-- Light: Holy Fire's dots make Holy Nova free; Inspiration, Blessed
-- Recovery); Shadowform, Silence, Vampiric Embrace (a 1-min cooldown here,
-- 30 sec on the target) and Mind Flay are Shadow talents, and Shadow Weaving
-- is a stacking buff on you (vanilla's Shadow Vulnerability is the warlock's
-- debuff, so it's not here). Every priest trains Fear Ward and Devouring
-- Plague (once racials; 3-min and 1-min cooldowns), Holy Fire, Shadow Word:
-- Death and Divine Spirit/Prayer of Spirit. No Lightwell, Desperate Prayer
-- or Prayer of Fortitude. Discipline's Power in Light makes Smite and Penance
-- hit harder on your Holy Fire, so Holy Fire is on its cooldown icon there.
--
-- Cooldowns whose aura matters only while it runs (Power Word: Shield, Fade,
-- Fear Ward, Power Infusion and Inner Focus on you; Holy Fire, Devouring
-- Plague, Vampiric Embrace and Silence on the target) show it on the icon
-- (effect) instead of a buff or debuff entry of their own.
-- Buffs lasting a minute or more (Fortitude, Inner Fire, Divine Spirit,
-- Shadow Protection, Shadowform) are reminders: grey while missing, out of
-- combat.
-- Racials: only the Human's Divine Grace (5 min) is in; it isn't drawn for
-- other races. The other races' (Elune's Grace, Chastise, Shadowguard...)
-- aren't on the Human trainer the class data comes from, so the generator
-- would flag them.

local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing, armors = S.mine, S.seal, S.blessing, S.armors
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

-- Divine Spirit or its party version, from you or another priest: one slot.
local SPIRITS = { group = "Spirits", source = "any", max = 1, icon = "Divine Spirit", missing = "remind",
    members = { "Divine Spirit", "Prayer of Spirit" } }

local function remind(name) return { name, missing = "remind" } end
local function onYou(name) return { name, effect = "you" } end
local function onTarget(name) return { name, effect = "target" } end

return {
    -- no talent points yet (below level 10): the level-30 buffs (Divine
    -- Spirit, Shadow Protection) would only remind of spells not yet known
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { onYou("Power Word: Shield"), "Mind Blast", onTarget("Holy Fire"), onTarget("Devouring Plague") },
      utility = { "Psychic Scream", onYou("Fade"), onYou("Fear Ward"), "Divine Grace" },
      buffs = { remind("Power Word: Fortitude"), remind("Inner Fire"), "Renew" },
      debuffs = { "Shadow Word: Pain" },
      procs = {} },
    { id = "discipline", name = "Discipline", tree = 1,
      essential = { "Penance", onYou("Power Word: Shield"), onTarget("Holy Fire"), "Mind Blast" },
      utility = { onYou("Power Infusion"), onYou("Inner Focus"), "Divine Grace", onYou("Fear Ward"),
                  "Psychic Scream", onYou("Fade"), onTarget("Devouring Plague") },
      buffs = { remind("Power Word: Fortitude"), remind("Inner Fire"), SPIRITS, remind("Shadow Protection"), "Renew" },
      -- Weakened Soul on the friend you target: Renewed Hope's crit window,
      -- what Divine Grace clears; packed, so no grey slot on enemies
      debuffs = { "Shadow Word: Pain", { "Weakened Soul", missing = "hide" } },
      procs = { "Focused Casting" } },
    { id = "holy", name = "Holy", tree = 2,
      -- Prayer of Mending on you shows on its icon; Holy Fire's dots feed
      -- Searing Light
      essential = { onYou("Prayer of Mending"), onYou("Power Word: Shield"), onTarget("Holy Fire"), "Mind Blast" },
      utility = { onYou("Inner Focus"), "Divine Grace", onYou("Fear Ward"), "Psychic Scream", onYou("Fade"),
                  onTarget("Devouring Plague") },
      buffs = { remind("Power Word: Fortitude"), remind("Inner Fire"), SPIRITS, remind("Shadow Protection"), "Renew" },
      debuffs = { "Shadow Word: Pain", { "Weakened Soul", missing = "hide" } },
      -- Inspiration and Blessed Recovery when they land on you
      procs = { "Inspiration", "Blessed Recovery" } },
    { id = "shadow", name = "Shadow", tree = 3,
      essential = { "Mind Blast", "Shadow Word: Death", onTarget("Devouring Plague"), onTarget("Vampiric Embrace") },
      utility = { onTarget("Silence"), onYou("Inner Focus"), "Psychic Scream", onYou("Fade"),
                  onYou("Power Word: Shield"), onYou("Fear Ward") },
      buffs = { remind("Shadowform"), remind("Inner Fire"), remind("Power Word: Fortitude"), remind("Shadow Protection"), SPIRITS },
      -- the dot you keep up warns while it's off the target
      debuffs = { { "Shadow Word: Pain", missing = "warn" }, "Mind Flay", "Blackout" },
      procs = { "Shadow Weaving", "Spirit Tap" } },
}
