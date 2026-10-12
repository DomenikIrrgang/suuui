-- tools/presets/WARRIOR.lua
-- The Warrior presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-12):
--   * Forever's trees: Arms has Spearing Strike (20 s, situational: giants,
--     dragonkin, mounts), Bloodthrill (Rend lets Overpower through for 6 s),
--     Improved Slam and Deep Wounds; Fury has Enrage, Flurry, Bloodthirst,
--     Death Wish, Piercing Howl; Protection has Shield Slam, Concussion Blow,
--     Last Stand. Bastion, Raging Blows, Master of Defense and Shield
--     Specialization are passives with no aura, so they aren't procs.
--   * Slam has a cooldown on Forever (18 s; Improved Slam takes 3 off), so
--     it's an Arms rotation cooldown.
--   * Victory Rush is trained (its IDs come from tools/data/found.tsv);
--     Taunt and Defensive Stance are known before the trainer lists start.
--   * Cooldowns whose buff/debuff only matters while it runs carry it as
--     effect (Bloodrage, Recklessness, Shield Wall, Disarm ...) instead of
--     a separate aura entry. Battle Shout (3 min) is a reminder.
--   * Sunder Armor/Expose Armor and Demoralizing Shout/Roar don't stack, so
--     each pair is one slot from anyone.

local S = dofile("tools/presets/shared.lua")
local TAUNTS = S.TAUNTS

local function you(name, extra)
    local e = { name, effect = "you" }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end
local function onTarget(name) return { name, effect = "target" } end

local BATTLE_SHOUT = { "Battle Shout", missing = "remind" }
local ARMOR = { group = "Armor Debuffs", source = "any", max = 1, icon = "Sunder Armor",
    members = { "Sunder Armor", "Expose Armor" } }
local DEMORALIZING = { group = "Demoralizing Effects", source = "any", max = 1, icon = "Demoralizing Shout",
    members = { "Demoralizing Shout", "Demoralizing Roar" } }

return {
    -- levels 1-10 (and anyone without points): leveling with what's trained
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Overpower", "Thunder Clap", "Victory Rush", "Execute", you("Bloodrage") },
      utility = { "Charge", "Intercept", "Pummel", "Shield Bash", onTarget("Disarm"), you("Berserker Rage"), you("Retaliation") },
      buffs = { BATTLE_SHOUT },
      debuffs = { "Rend", "Hamstring", ARMOR, "Demoralizing Shout" },
      procs = {} },
    { id = "arms", name = "Arms", tree = 1,
      -- Bloodthrill's window shows on Overpower (aura name differs)
      essential = { "Mortal Strike", you("Overpower", { effectName = "Bloodthrill" }), "Slam", "Whirlwind", "Execute",
          you("Sweeping Strikes"), you("Bloodrage") },
      utility = { "Charge", "Intercept", "Pummel", you("Berserker Rage"), you("Recklessness", { sound = "chime" }),
          onTarget("Intimidating Shout"), "Spearing Strike", "Victory Rush", you("Retaliation", { hidden = true }) },
      buffs = { BATTLE_SHOUT },
      -- Rend feeds Bloodthrill; Mortal Strike's healing cut is for PvP
      debuffs = { "Rend", "Deep Wounds", ARMOR, "Hamstring", { "Mortal Strike", hidden = true } },
      procs = {} },
    { id = "fury", name = "Fury", tree = 2,
      essential = { "Bloodthirst", "Whirlwind", "Execute", you("Death Wish"), you("Bloodrage") },
      utility = { "Pummel", "Intercept", "Charge", you("Berserker Rage"), you("Recklessness", { sound = "chime" }),
          onTarget("Intimidating Shout"), "Victory Rush" },
      buffs = { BATTLE_SHOUT },
      -- Deep Wounds is an Arms talent most Fury builds still reach
      debuffs = { ARMOR, "Deep Wounds", { "Hamstring", hidden = true }, { "Piercing Howl", hidden = true } },
      procs = { "Flurry", "Enrage" } },
    { id = "protection", name = "Protection", tree = 3,
      essential = { "Shield Slam", "Revenge", you("Shield Block"), onTarget("Thunder Clap"), you("Bloodrage") },
      utility = { "Taunt", "Mocking Blow", "Challenging Shout", you("Shield Wall", { sound = "chime" }), you("Last Stand"),
          "Shield Bash", onTarget("Concussion Blow"), onTarget("Disarm"), "Charge",
          { "Intercept", hidden = true }, you("Berserker Rage", { hidden = true }) },
      buffs = { BATTLE_SHOUT },
      debuffs = { TAUNTS, ARMOR, DEMORALIZING },
      procs = {} },
}
