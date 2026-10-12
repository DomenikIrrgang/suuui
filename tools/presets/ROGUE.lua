-- tools/presets/ROGUE.lua
-- The Rogue presets (format: tools/presets_source.lua).
--
-- Forever's trees (tools/data/class_rogue.tsv): Assassination has Venom (a
-- finisher buff for your poisons), Mutilate, Cold Blood, Improved Kidney Shot
-- (stunned targets take 10% more) and Improved Gouge; Combat has Adrenaline
-- Rush, Blade Flurry and Riposte; Subtlety has Hemorrhage (15 sec debuff: more
-- Rupture damage), Thousand Cuts (Rupture ticks stack a cheaper Hemorrhage or
-- Backstab), Cutthroat (Ambush without Stealth), Ghostly Strike,
-- Premeditation and Preparation (so Preparation is Subtlety's only), and
-- Initiative, Opportunity and Dirty Deeds for Ambush, Garrote and Cheap Shot.
--
-- Cooldowns whose aura matters only while it runs show it on their icon
-- (effect): Evasion, Sprint, Vanish, Cold Blood, Adrenaline Rush, Blade
-- Flurry, Ghostly Strike, Premeditation on you; Gouge, Blind, Riposte's
-- disarm on the target. Kidney Shot and Cheap Shot are in the Stuns slot
-- (anyone's stuns), so they carry no effect. Kick's silence (Improved Kick)
-- is named "Silenced" like other classes', so it isn't tied to Kick.
-- Slice and Dice and Venom are finishers without a cooldown: buffs that warn
-- while missing. A rogue has no buff of a minute or longer to remind of:
-- poisons are weapon enchants, not auras, and Stealth is a state (left out).
--
-- Conditions:
--   stealth   the openers (Cheap Shot, Garrote, Ambush) and Sap show only
--             while you're stealthed (Vanish puts you there too): out of
--             Stealth they can't be used. Cutthroat's Ambush without Stealth
--             is the Cutthroat proc's to show.
--   not boss  Kidney Shot, Gouge and Blind hide while a boss is targeted
--             (immune); with no target they show.
--   grouped   Feint (threat) only in a group: solo it does nothing.
-- Kick and Kidney Shot are pressed every fight, so they're essential, Feint
-- too in a group; Gouge where Improved Gouge is (Assassination) or nothing
-- else is (Unspecced, no talent points: below level 10), utility elsewhere.
--
-- Debuffs follow the default (grey while missing, with a hostile target)
-- except Garrote and Sap: only while up (Garrote can't be put back in combat,
-- Sap is a CC timer).
--
-- Your poisons on the target, one slot: main and off hand can carry two.
-- The debuffs keep their rank's name (Deadly Poison II...) except Wound and
-- Crippling Poison's; Instant Poison leaves no debuff.
-- Wound Poison is also in the shared Healing Reduction slot (anyone's): here
-- that slot is a copy whose Wound Poison is others' only, so your own Wound
-- Poison is the Poisons slot's and another rogue's still counts as healing
-- reduction (Mortal Strike stays anyone's).
local S = dofile("tools/presets/shared.lua")

local POISON_DEBUFFS = { "Deadly Poison", "Deadly Poison II", "Deadly Poison III", "Deadly Poison IV", "Deadly Poison V",
    "Wound Poison", "Crippling Poison", "Mind-numbing Poison", "Mind-numbing Poison II", "Mind-numbing Poison III" }
local POISONS = { group = "Poisons", source = "mine", max = 2, icon = "Deadly Poison", members = POISON_DEBUFFS }

local healingReductionMembers = {}
for i, m in ipairs(S.HEALING_REDUCTION.members) do
    local name = type(m) == "table" and m[1] or m
    if name:find("^Wound Poison") then m = S.with(type(m) == "table" and m or { m }, { source = "others" }) end
    healingReductionMembers[i] = m
end
local HEALING_REDUCTION = S.with(S.HEALING_REDUCTION, { members = healingReductionMembers })

local function stealthed() return { conditions = { { type = "stance", stances = { "stealth" } } } } end
local function notBoss() return { conditions = { { type = "target", kinds = { "boss" }, ["not"] = true } } } end
local function grouped() return { conditions = { { type = "group", value = "solo", ["not"] = true } } } end

local you = function(name) return { name, effect = "you" } end
local target = function(name) return { name, effect = "target", when = notBoss() } end
local opener = function(name) return { name, when = stealthed() } end
local kidney = { "Kidney Shot", when = notBoss() }
local feint = { "Feint", when = grouped() }
local garrote = { "Garrote", missing = "hide" }
local sap = { "Sap", missing = "hide" }

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Kick", target("Gouge"), kidney, feint },
      utility = { you("Evasion"), you("Sprint"), you("Vanish"), target("Blind"), "Distract", opener("Sap") },
      buffs = { { "Slice and Dice", missing = "grey" } },
      debuffs = { "Rupture", garrote, S.physical(), POISONS, S.STUNS, sap, HEALING_REDUCTION },
      procs = {} },
    { id = "assassination", name = "Assassination", tree = 1,
      -- Improved Kidney Shot: the stun is a damage window, so it leads
      essential = { you("Cold Blood"), kidney, "Kick", target("Gouge"), feint, opener("Garrote"), opener("Cheap Shot") },
      utility = { you("Evasion"), you("Sprint"), you("Vanish"), target("Blind"), "Distract", opener("Sap") },
      buffs = { { "Slice and Dice", missing = "warn" }, { "Venom", missing = "warn" } },
      -- Mutilate and Venom want a poison up: grey while none is (on a hostile target)
      debuffs = { "Rupture", POISONS, garrote, S.physical(), S.STUNS, sap, HEALING_REDUCTION },
      procs = { "Remorseless" } },
    { id = "combat", name = "Combat", tree = 2,
      -- Riposte lights up after a parry by itself; its disarm shows on it
      essential = { you("Adrenaline Rush"), you("Blade Flurry"), { "Riposte", effect = "target" }, "Kick", kidney, feint,
          opener("Cheap Shot") },
      utility = { you("Evasion"), you("Sprint"), you("Vanish"), target("Gouge"), target("Blind"), "Distract", opener("Sap") },
      buffs = { { "Slice and Dice", missing = "warn" } },
      debuffs = { "Rupture", S.physical(), POISONS, S.STUNS, sap, HEALING_REDUCTION },
      procs = {} },
    { id = "subtlety", name = "Subtlety", tree = 3,
      -- Premeditation's 20 sec to spend its combo points (shown out of
      -- Stealth too: its effect runs after the opener)
      essential = { you("Ghostly Strike"), you("Premeditation"), "Kick", kidney, feint,
          opener("Ambush"), opener("Cheap Shot"), opener("Garrote") },
      -- Elusiveness shortens Vanish and Blind
      utility = { "Preparation", you("Vanish"), target("Blind"), target("Gouge"), you("Evasion"), you("Sprint"), "Distract",
          opener("Sap") },
      buffs = { { "Slice and Dice", missing = "warn" } },
      -- Hemorrhage feeds Rupture: grey while it's off
      debuffs = { "Hemorrhage", "Rupture", garrote, S.physical(), POISONS, S.STUNS, sap, HEALING_REDUCTION },
      procs = { "Thousand Cuts", "Cutthroat" } },
}
