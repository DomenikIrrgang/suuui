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
-- one: grey); blessings (1 hour), auras and Righteous Fury (30 min) remind.
-- The blessing reminder counts anyone's blessing (in a raid another
-- paladin's Greater Blessing replaces yours: no false reminder).
-- Stuns are short and nothing to keep up: shown while on the target only.
-- Others' Judgements (Ret) only in a group, and only while up.
-- Divine Protection, Divine Shield, Templar's Bulwark and Blessing of
-- Protection all apply Forbearance but keep cooldowns of their own (the
-- tracker can't show Forbearance on you), so only Divine Protection ->
-- Divine Shield shares an icon.
-- Hammer of the Righteous isn't on Forever's trainer or talents (yet); Exorcism
-- and Holy Wrath (undead and demons) can't be conditioned on the target's
-- creature type (target kinds are boss/elite/player/normal).

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
local function blessings(icon) return with(blessing(icon), { missing = "remind", source = "any" }) end
-- every stun, shown only while one is on the target
local STUNS = S.with(S.STUNS, { missing = "hide" })
-- Sacred Arbiter refreshes them, so Ret sees them: only in a group (solo
-- there are none), only while up (a group without another paladin has none)
local OTHERS = S.with(OTHERS_JUDGEMENTS, { missing = "hide",
    when = { conditions = { { type = "group", value = "group" } } } })
-- Twist of Light's echoes: up until the next swing
local ECHOES = { group = "Echoes", source = "mine", max = 1, icon = "Echo of Command",
    members = { "Echo of Command", "Echo of Righteousness", "Echo of Justice", "Echo of Fury" } }

-- cooldowns whose effect shows on the icon while it runs
local function onYou(name) return { name, effect = "you" } end
local function onTarget(name) return { name, effect = "target" } end

-- Divine Protection until Divine Shield is learned, then Divine Shield (both
-- apply Forbearance): one cooldown icon, its bubble shown on it
local SHIELDS = { group = "Divine Shield", members = { "Divine Protection", "Divine Shield" }, effect = "you" }
-- a tank can't attack under Divine Protection (threat lost): in a group,
-- Protection's icon waits for Divine Shield
local TANK_SHIELDS = { group = "Divine Shield", effect = "you", members = {
    { "Divine Protection", when = { conditions = { { type = "group", value = "solo" } } } }, "Divine Shield" } }

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Judgement", "Holy Strike", "Consecration", "Hammer of Wrath" },
      utility = { "Hammer of Justice", SHIELDS, "Lay on Hands",
          onYou("Blessing of Protection"), onYou("Blessing of Freedom"), "Exorcism" },
      buffs = { seals("Seal of Righteousness", "warn"), blessings("Blessing of Might"), auras("Devotion Aura") },
      debuffs = { MY_JUDGEMENT, STUNS },
      procs = {} },
    { id = "holy", name = "Holy", tree = 1,
      -- Light's Vigil on an enemy shows on its icon; on an ally (a buff on
      -- another unit) the tracker can't show it
      essential = { "Holy Shock", onTarget("Light's Vigil"), onYou("Divine Favor"), "Judgement" },
      utility = { onYou("Voice of Truth"), SHIELDS, "Lay on Hands",
          onYou("Blessing of Protection"), onYou("Blessing of Freedom"), "Hammer of Justice", "Exorcism" },
      buffs = { seal("Seal of Wisdom"), blessings("Blessing of Wisdom"), auras("Concentration Aura") },
      debuffs = { MY_JUDGEMENT, STUNS },
      procs = { "Infusion of Light" } },
    { id = "protection", name = "Protection", tree = 2,
      -- Holy Shield's block charges show with the procs, its icon is the cooldown;
      -- Exorcism is for undead and demons (dimmed on anything else)
      essential = { "Holy Shield", "Holy Strike", "Judgement", "Consecration", "Exorcism", "Hammer of Wrath", onYou("Swift Judgement") },
      utility = { onYou("Templar's Bulwark"), TANK_SHIELDS, "Lay on Hands",
          onYou("Blessing of Protection"), onYou("Blessing of Freedom"), "Hammer of Justice", "Holy Wrath" },
      -- Seal of Fury is the taunt and the shield: never without it
      buffs = { seals("Seal of Fury", "warn"), { "Righteous Fury", mine = true, missing = "remind" },
          blessings("Blessing of Kings"), auras("Devotion Aura"),
          -- Holy Strike's damage reduction: a grey slot to keep up, in combat
          { "Iron Creed", mine = true, when = { conditions = { { type = "combat" } } } } },
      debuffs = { MY_JUDGEMENT, S.physical({ tank = true }), STUNS, TAUNTS },
      procs = { "Holy Shield", "Redoubt", "Reckoning" } },
    { id = "retribution", name = "Retribution", tree = 3,
      essential = { "Judgement", "Holy Strike", "Consecration", "Exorcism", "Hammer of Wrath" },
      utility = { onTarget("Repentance"), "Hammer of Justice", SHIELDS,
          "Lay on Hands", onYou("Blessing of Freedom"), onYou("Blessing of Protection"), "Holy Wrath" },
      buffs = { seals("Seal of Command", "warn"), blessings("Blessing of Might"), auras("Retribution Aura") },
      -- Sacred Arbiter keeps every paladin's judgement up: others' count too
      -- (in a group)
      debuffs = { MY_JUDGEMENT, OTHERS, S.physical(), STUNS },
      procs = { "Vengeance", "Vindication", ECHOES } },
}
