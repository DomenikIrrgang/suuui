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
-- Buffs lasting longer (Fortitude, Divine Spirit, Shadow Protection) are
-- reminders: grey while missing, out of combat. Inner Fire's charges run out
-- in a fight: a fixed slot (charges and time) that warns while missing.
-- Shadowform is a warning instead (an ember slot, in combat too) while
-- you're out of the form, and gone while in it (live stance condition):
-- healing out of form is when you forget it. Renew on you is a heal you
-- cast when hurt, not a buff you keep up: shown while up, no grey slot.
-- Only in a group (static, rebuilt on roster changes out of combat): Divine
-- Grace (can't be cast on yourself), Fear Ward (for the tank; a battleground
-- or arena is a group too) and the Shadow Protection reminder (a group buff).
-- Debuffs: Shadow Word: Pain grey with a hostile target (default); Shadow's
-- warns only in combat with a target (a warn slot shows without one).
-- Mind Flay (a channel) and Blackout's stuns show only while on the target.
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
-- used up by its charges: a fixed slot (its charges and time while up),
-- warning while missing
local INNER_FIRE = { "Inner Fire", missing = "warn" }
local function onYou(name) return { name, effect = "you" } end
local function onTarget(name) return { name, effect = "target" } end
-- only while you're in a group (a party, raid, battleground or arena)
local function inGroup(entry)
    if type(entry) == "string" then entry = { entry } end
    entry.when = { conditions = { { type = "group", value = "solo", ["not"] = true } } }
    return entry
end
local RENEW = { "Renew", missing = "hide" }
-- out of Shadowform: an ember slot, in combat too; in the form, gone
local SHADOWFORM = { "Shadowform", missing = "warn",
    when = { conditions = { { type = "stance", stances = { "shadowform" }, ["not"] = true } } } }

return {
    -- no talent points yet (below level 10): the level-30 buffs (Divine
    -- Spirit, Shadow Protection) would only remind of spells not yet known
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Mind Blast", onTarget("Holy Fire"), onTarget("Devouring Plague"), onYou("Power Word: Shield") },
      utility = { "Psychic Scream", onYou("Fade"), inGroup(onYou("Fear Ward")), inGroup("Divine Grace") },
      buffs = { remind("Power Word: Fortitude"), INNER_FIRE, RENEW },
      debuffs = { "Shadow Word: Pain" },
      procs = {} },
    { id = "discipline", name = "Discipline", tree = 1,
      essential = { "Penance", onYou("Power Word: Shield"), onTarget("Holy Fire"), "Mind Blast" },
      utility = { onYou("Power Infusion"), onYou("Inner Focus"), inGroup("Divine Grace"), inGroup(onYou("Fear Ward")),
                  "Psychic Scream", onYou("Fade"), onTarget("Devouring Plague") },
      buffs = { remind("Power Word: Fortitude"), INNER_FIRE, SPIRITS, inGroup(remind("Shadow Protection")), RENEW },
      -- Weakened Soul on the friend you target: Renewed Hope's crit window,
      -- what Divine Grace clears; packed, so no grey slot on enemies
      debuffs = { "Shadow Word: Pain", { "Weakened Soul", missing = "hide" } },
      procs = { "Focused Casting" } },
    { id = "holy", name = "Holy", tree = 2,
      -- Prayer of Mending on you shows on its icon; Holy Fire's dots feed
      -- Searing Light
      essential = { onYou("Prayer of Mending"), onYou("Power Word: Shield"), onTarget("Holy Fire"), "Mind Blast" },
      utility = { onYou("Inner Focus"), inGroup("Divine Grace"), inGroup(onYou("Fear Ward")), "Psychic Scream", onYou("Fade"),
                  onTarget("Devouring Plague") },
      buffs = { remind("Power Word: Fortitude"), INNER_FIRE, SPIRITS, inGroup(remind("Shadow Protection")), RENEW },
      debuffs = { "Shadow Word: Pain", { "Weakened Soul", missing = "hide" } },
      -- Inspiration and Blessed Recovery when they land on you
      procs = { "Inspiration", "Blessed Recovery" } },
    { id = "shadow", name = "Shadow", tree = 3,
      essential = { "Mind Blast", "Shadow Word: Death", onTarget("Devouring Plague"), onTarget("Vampiric Embrace") },
      utility = { onTarget("Silence"), onYou("Inner Focus"), "Psychic Scream", onYou("Fade"),
                  onYou("Power Word: Shield"), inGroup(onYou("Fear Ward")) },
      buffs = { SHADOWFORM, INNER_FIRE, remind("Power Word: Fortitude"), inGroup(remind("Shadow Protection")), SPIRITS },
      -- the dot you keep up warns while it's off the target, in combat with a
      -- target (without one a warn slot would pulse at nothing); Mind Flay
      -- and Blackout (a 10% proc) only while they're on it
      debuffs = { { "Shadow Word: Pain", missing = "warn",
                    when = { conditions = { { type = "combat" },
                        { type = "target", kinds = { "boss", "elite", "normal", "player" } } } } },
                  { "Mind Flay", missing = "hide" }, S.with(S.STUNS, { missing = "hide" }) },
      procs = { "Shadow Weaving", "Spirit Tap" } },
}
