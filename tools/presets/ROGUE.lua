-- tools/presets/ROGUE.lua
-- The Rogue presets (format: tools/presets_source.lua).
--
-- Forever's trees (tools/data/class_rogue.tsv): Assassination has Venom (a
-- finisher buff for your poisons), Mutilate, Cold Blood, Improved Kidney Shot
-- (stunned targets take 10% more) and Improved Gouge; Combat has Adrenaline
-- Rush, Blade Flurry and Riposte; Subtlety has Hemorrhage (15 sec debuff: more
-- Rupture damage), Thousand Cuts (Rupture ticks stack a cheaper Hemorrhage or
-- Backstab), Cutthroat (Ambush without Stealth), Ghostly Strike,
-- Premeditation and Preparation (so Preparation is Subtlety's only).
--
-- Cooldowns whose aura matters only while it runs show it on their icon
-- (effect): Evasion, Sprint, Vanish, Cold Blood, Adrenaline Rush, Blade
-- Flurry, Ghostly Strike, Premeditation on you; Kidney Shot, Gouge, Blind,
-- Riposte's disarm on the target. Kick's silence (Improved Kick) is named
-- "Silenced" like other classes', so it isn't tied to Kick.
-- Slice and Dice and Venom are finishers without a cooldown: buffs that warn
-- while missing. A rogue has no buff of a minute or longer to remind of:
-- poisons are weapon enchants, not auras, and Stealth is a state (left out).
-- Kick and Feint (10 sec) and Kidney Shot are pressed every fight, so they're
-- essential; Gouge too where Improved Gouge is (Assassination) or nothing
-- else is (Unspecced), utility elsewhere.

-- Your poisons on the target, one slot: main and off hand can carry two.
-- The debuffs keep their rank's name (Deadly Poison II...) except Wound and
-- Crippling Poison's; Instant Poison leaves no debuff.
local POISON_DEBUFFS = { "Deadly Poison", "Deadly Poison II", "Deadly Poison III", "Deadly Poison IV", "Deadly Poison V",
    "Wound Poison", "Crippling Poison", "Mind-numbing Poison", "Mind-numbing Poison II", "Mind-numbing Poison III" }
local function poisons(missing)
    return { group = "Poisons", source = "mine", max = 2, icon = "Deadly Poison", members = POISON_DEBUFFS, missing = missing }
end

local you = function(name) return { name, effect = "you" } end
local target = function(name) return { name, effect = "target" } end

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Kick", target("Gouge"), target("Kidney Shot"), "Feint" },
      utility = { you("Evasion"), you("Sprint"), you("Vanish"), target("Blind"), "Distract" },
      buffs = { { "Slice and Dice", missing = "grey" } },
      debuffs = { "Rupture", "Garrote", "Expose Armor", poisons(), "Cheap Shot" },
      procs = {} },
    { id = "assassination", name = "Assassination", tree = 1,
      -- Improved Kidney Shot: the stun is a damage window, so it leads
      essential = { you("Cold Blood"), target("Kidney Shot"), "Kick", target("Gouge"), "Feint" },
      utility = { you("Evasion"), you("Sprint"), you("Vanish"), target("Blind"), "Distract" },
      buffs = { { "Slice and Dice", missing = "warn" }, { "Venom", missing = "warn" } },
      -- Mutilate and Venom want a poison up: grey while none is
      debuffs = { "Rupture", poisons("grey"), "Garrote", "Expose Armor", "Cheap Shot" },
      procs = { "Remorseless" } },
    { id = "combat", name = "Combat", tree = 2,
      -- Riposte lights up after a parry by itself; its disarm shows on it
      essential = { you("Adrenaline Rush"), you("Blade Flurry"), target("Riposte"), "Kick", target("Kidney Shot"), "Feint" },
      utility = { you("Evasion"), you("Sprint"), you("Vanish"), target("Gouge"), target("Blind"), "Distract" },
      buffs = { { "Slice and Dice", missing = "warn" } },
      debuffs = { "Rupture", "Expose Armor", poisons(), "Cheap Shot" },
      procs = {} },
    { id = "subtlety", name = "Subtlety", tree = 3,
      -- Premeditation's 20 sec to spend its combo points
      essential = { you("Ghostly Strike"), you("Premeditation"), "Kick", target("Kidney Shot"), "Feint" },
      -- Elusiveness shortens Vanish and Blind
      utility = { "Preparation", you("Vanish"), target("Blind"), target("Gouge"), you("Evasion"), you("Sprint"), "Distract" },
      buffs = { { "Slice and Dice", missing = "warn" } },
      -- Hemorrhage feeds Rupture: grey while it's off
      debuffs = { { "Hemorrhage", missing = "grey" }, "Rupture", "Garrote", "Expose Armor", poisons(), "Cheap Shot", "Sap" },
      procs = { "Thousand Cuts", "Cutthroat" } },
}
