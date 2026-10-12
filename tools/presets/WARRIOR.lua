-- tools/presets/WARRIOR.lua
-- The Warrior presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-12):
--   * Forever's trees: Arms has Spearing Strike (20 s, situational: giants,
--     dragonkin, mounts), Bloodthrill (Rend lets Overpower through for 6 s),
--     Improved Slam and Deep Wounds; Fury has Enrage, Flurry, Bloodthirst,
--     Death Wish, Piercing Howl; Protection has Shield Slam, Concussion Blow,
--     Last Stand, Vanguard (Charge in Defensive Stance too). Bastion, Raging
--     Blows, Master of Defense and Shield Specialization are passives with no
--     aura, so they aren't procs.
--   * Slam has a cooldown on Forever (18 s; Improved Slam takes 3 off), so
--     it's an Arms rotation cooldown.
--   * Victory Rush is trained (its IDs come from tools/data/found.tsv);
--     Taunt and Defensive Stance are known before the trainer lists start.
--   * Cooldowns whose buff/debuff only matters while it runs carry it as
--     effect (Bloodrage, Recklessness, Shield Wall, Disarm ...) instead of
--     a separate aura entry. Battle Shout (3 min) is a reminder.
--   * Sunder Armor/Expose Armor and Demoralizing Shout/Roar don't stack, so
--     each pair is one slot from anyone (shared groups).
-- Stances (live conditions; the tracker dims what the stance rules out):
--   * shown only in their stance, where seeing them elsewhere decides
--     nothing: Berserker Rage (Berserker), Revenge, Shield Block, Disarm
--     (Defensive), Overpower outside Arms (Battle), and Unspecced's
--     interrupts as a pair (Shield Bash in Battle/Defensive, Pummel in
--     Berserker: one interrupt, the one you can use).
--   * left in every stance, dimmed: the 30-min cooldowns (Retaliation,
--     Recklessness, Shield Wall), the gap closers (Charge ready or not
--     decides the dance to Intercept) and Arms' dance (Overpower's
--     Bloodthrill window, Whirlwind, Pummel cue the switch). Mocking Blow
--     and Taunt stay too: one is the other's backup. Thunder Clap and
--     Sweeping Strikes have no condition (Forever's stance rules for them
--     unverified).
--   * Charge "cannot be used in combat": out of combat only.
-- Taunts show anywhere: in the open world you taunt mobs off strangers too.
-- Debuffs you don't put up on purpose (Deep Wounds, Hamstring, Piercing
-- Howl, stuns) hide while missing instead of greying with a target.

local S = dofile("tools/presets/shared.lua")

local function you(name, extra)
    local e = { name, effect = "you" }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end
local function onTarget(name, extra)
    local e = { name, effect = "target" }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end
local function stance(...) return { type = "stance", stances = { ... } } end
local function inStance(...) return { conditions = { stance(...) } } end
local OUT_OF_COMBAT = { type = "combat", ["not"] = true }

local BATTLE_SHOUT = { "Battle Shout", missing = "remind" }
local CHARGE = { "Charge", when = { conditions = { OUT_OF_COMBAT } } }
local BERSERKER_RAGE = you("Berserker Rage", { when = inStance("berserker") })
local DISARM = onTarget("Disarm", { when = inStance("defensive") })
local DEMORALIZING = S.AP_REDUCTION
-- stuns aren't kept up: nothing to grey while none is on the target
local STUNS = S.with(S.STUNS, { missing = "hide" })
-- Mortal Strike's healing cut matters against players: shown on a player
-- target (grey there while it isn't up), not hidden
local HEALING = S.with(S.HEALING_REDUCTION, { when = { conditions = { { type = "target", kinds = { "player" } } } } })
HEALING.hidden = nil
-- Tanks: the last debuff entry
local TAUNTS = S.TAUNTS

return {
    -- levels 1-10 (and anyone without points): leveling with what's trained
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { { "Overpower", when = inStance("battle") }, "Thunder Clap", "Victory Rush", "Execute", you("Bloodrage") },
      utility = { CHARGE, "Intercept", { "Pummel", when = inStance("berserker") },
          { "Shield Bash", when = inStance("battle", "defensive") }, DISARM, BERSERKER_RAGE, you("Retaliation") },
      buffs = { BATTLE_SHOUT },
      debuffs = { "Rend", { "Hamstring", missing = "hide" }, S.physical(), DEMORALIZING, STUNS },
      procs = {} },
    { id = "arms", name = "Arms", tree = 1,
      -- Bloodthrill's window shows on Overpower (aura name differs)
      essential = { "Mortal Strike", you("Overpower", { effectName = "Bloodthrill" }), "Slam", "Whirlwind", "Execute",
          you("Sweeping Strikes"), you("Bloodrage") },
      utility = { CHARGE, "Intercept", "Pummel", BERSERKER_RAGE, you("Recklessness", { sound = "chime" }),
          onTarget("Intimidating Shout"), "Spearing Strike", "Victory Rush", you("Retaliation", { hidden = true }) },
      buffs = { BATTLE_SHOUT },
      -- Rend feeds Bloodthrill
      debuffs = { "Rend", { "Deep Wounds", missing = "hide" }, S.physical(), { "Hamstring", missing = "hide" }, STUNS, HEALING },
      procs = {} },
    { id = "fury", name = "Fury", tree = 2,
      essential = { "Bloodthirst", "Whirlwind", "Execute", you("Death Wish"), you("Bloodrage") },
      utility = { "Pummel", "Intercept", CHARGE, BERSERKER_RAGE, you("Recklessness", { sound = "chime" }),
          onTarget("Intimidating Shout"), "Victory Rush" },
      buffs = { BATTLE_SHOUT },
      -- Deep Wounds is an Arms talent most Fury builds still reach
      debuffs = { S.physical(), { "Deep Wounds", missing = "hide" }, { "Hamstring", hidden = true, missing = "hide" },
          { "Piercing Howl", hidden = true, missing = "hide" }, STUNS },
      procs = { "Flurry", "Enrage" } },
    { id = "protection", name = "Protection", tree = 3,
      essential = { "Shield Slam", { "Revenge", when = inStance("defensive") }, "Thunder Clap",
          you("Shield Block", { when = inStance("defensive") }), you("Bloodrage") },
      utility = { "Taunt", "Mocking Blow", "Challenging Shout",
          you("Shield Wall", { sound = "chime" }), you("Last Stand"), "Shield Bash", "Concussion Blow", DISARM,
          -- Vanguard: Defensive Stance charges too
          { "Charge", when = { conditions = { OUT_OF_COMBAT, stance("battle", "defensive") } } },
          { "Intercept", hidden = true }, you("Berserker Rage", { hidden = true, when = inStance("berserker") }) },
      buffs = { BATTLE_SHOUT },
      debuffs = { "Rend", S.physical({ tank = true }), STUNS, TAUNTS },
      procs = {} },
}
