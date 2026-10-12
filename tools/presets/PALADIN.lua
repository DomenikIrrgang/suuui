-- tools/presets/PALADIN.lua
-- The Paladin presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-12):
--   Holy: Light's Vigil (on the target 30 sec, frees the next Holy Shock),
--     Voice of Truth (6 sec silence/interrupt immunity), Infusion of Light
--     (proc: faster Holy Light).
--   Protection: Seal of Fury (its judgement, Judgement of Fury, is the
--     taunt: in the Taunts group), Templar's Bulwark (8 sec absorb, shares
--     Forbearance), Swift Judgement (resets Judgement), Iron Creed (Holy
--     Strike's 6 sec damage reduction under Righteous Fury).
--   Retribution: Twist of Light (swapping seals leaves an "Echo of <seal>"
--     for the next swing), Sacred Arbiter (Holy Strike refreshes every
--     judgement on the target, so others' judgements are worth seeing).
-- Short self-buffs that come from a cooldown (shields, Divine Favor, Voice
-- of Truth, the hand-style blessings) show on their cooldown icon (effect)
-- instead of as a buff; CC on the target likewise. Seals last 30 sec and
-- matter in combat, so a missing seal warns (not for Holy, who heals without
-- one); blessings (1 hour), auras and Righteous Fury (30 min) remind.
-- Hammer of the Righteous isn't on Forever's trainer or talents (yet).

local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing = S.mine, S.seal, S.blessing
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

-- a shared group with behaviour added (the helpers build a fresh table)
local function with(g, fields) for k, v in pairs(fields) do g[k] = v end return g end

-- one aura per paladin: your own, one slot (Sanctity Aura isn't a Forever
-- talent)
local function auras(icon) return { group = "Auras", source = "mine", max = 1, icon = icon, missing = "remind",
    members = { "Devotion Aura", "Retribution Aura", "Concentration Aura",
        "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" } } end
local function seals(icon, missing) return with(seal(icon), { missing = missing }) end
local function blessings(icon) return with(blessing(icon), { missing = "remind" }) end
-- Twist of Light's echoes: up until the next swing
local ECHOES = { group = "Echoes", source = "mine", max = 1, icon = "Echo of Command",
    members = { "Echo of Command", "Echo of Righteousness", "Echo of Justice", "Echo of Fury" } }

-- cooldowns whose effect shows on the icon while it runs
local function onYou(name) return { name, effect = "you" } end
local function onTarget(name) return { name, effect = "target" } end

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Judgement", "Holy Strike", "Consecration", "Hammer of Wrath" },
      utility = { onTarget("Hammer of Justice"), onYou("Divine Protection"), onYou("Divine Shield"), "Lay on Hands",
          onYou("Blessing of Protection"), onYou("Blessing of Freedom"), "Exorcism" },
      buffs = { seals("Seal of Righteousness", "warn"), blessings("Blessing of Might"), auras("Devotion Aura") },
      debuffs = { MY_JUDGEMENT },
      procs = {} },
    { id = "holy", name = "Holy", tree = 1,
      -- Light's Vigil on an enemy shows on its icon; on an ally (a buff on
      -- another unit) the tracker can't show it
      essential = { "Holy Shock", onTarget("Light's Vigil"), onYou("Divine Favor"), "Judgement" },
      utility = { onYou("Voice of Truth"), onYou("Divine Shield"), onYou("Divine Protection"), "Lay on Hands",
          onYou("Blessing of Protection"), onYou("Blessing of Freedom"), onTarget("Hammer of Justice"), "Exorcism" },
      buffs = { seal("Seal of Wisdom"), blessings("Blessing of Wisdom"), auras("Concentration Aura") },
      debuffs = { MY_JUDGEMENT },
      procs = { "Infusion of Light" } },
    { id = "protection", name = "Protection", tree = 2,
      essential = { onYou("Holy Shield"), "Holy Strike", "Judgement", "Consecration", onYou("Swift Judgement"), "Hammer of Wrath" },
      utility = { onYou("Templar's Bulwark"), onYou("Divine Protection"), onYou("Divine Shield"), "Lay on Hands",
          onYou("Blessing of Protection"), onYou("Blessing of Freedom"), onTarget("Hammer of Justice"), "Holy Wrath" },
      -- Seal of Fury is the taunt and the shield: never without it
      buffs = { seals("Seal of Fury", "warn"), { "Righteous Fury", mine = true, missing = "remind" },
          blessings("Blessing of Kings"), auras("Devotion Aura"), mine("Iron Creed") },
      debuffs = { MY_JUDGEMENT, S.AP_REDUCTION, S.ATTACK_SLOWS, TAUNTS },
      procs = { "Redoubt", "Reckoning" } },
    { id = "retribution", name = "Retribution", tree = 3,
      essential = { "Judgement", "Holy Strike", "Consecration", "Exorcism", "Hammer of Wrath" },
      utility = { onTarget("Repentance"), onTarget("Hammer of Justice"), onYou("Divine Shield"), onYou("Divine Protection"),
          "Lay on Hands", onYou("Blessing of Freedom"), onYou("Blessing of Protection"), "Holy Wrath" },
      buffs = { seals("Seal of Command", "warn"), blessings("Blessing of Might"), auras("Retribution Aura") },
      -- Sacred Arbiter keeps every paladin's judgement up: others' count too
      debuffs = { MY_JUDGEMENT, OTHERS_JUDGEMENTS },
      procs = { "Vengeance", "Vindication", ECHOES } },
}
