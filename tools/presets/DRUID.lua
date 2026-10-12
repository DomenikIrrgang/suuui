-- tools/presets/DRUID.lua
-- The Druid presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-11): new
-- talents Berserk, Primal Bite, Shifting Power (Feral) and Wild Growth
-- (Restoration); Lacerate is trained; Tiger's Fury doesn't exist.

local S = dofile("tools/presets/shared.lua")
local mine, seal, blessing, armors = S.mine, S.seal, S.blessing, S.armors
local MY_JUDGEMENT, OTHERS_JUDGEMENTS, TAUNTS = S.MY_JUDGEMENT, S.OTHERS_JUDGEMENTS, S.TAUNTS

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Barkskin", "Innervate", "Nature's Grasp", "Bash" },
      utility = { "Rebirth", "Tranquility", "Dash", "Faerie Fire" },
      buffs = { "Mark of the Wild", "Thorns", "Barkskin", "Innervate", "Omen of Clarity" },
      debuffs = { "Moonfire", "Faerie Fire", "Entangling Roots", "Demoralizing Roar" },
      procs = { "Clearcasting" } },
    { id = "balance", name = "Balance", tree = 1,
      essential = { "Hurricane", "Innervate", "Barkskin", "Nature's Grasp" },
      utility = { "Rebirth", "Tranquility", "Dash", "Faerie Fire" },
      buffs = { "Mark of the Wild", "Thorns", "Omen of Clarity", "Moonkin Form", "Barkskin", "Nature's Grasp", "Innervate" },
      debuffs = { "Moonfire", "Insect Swarm", "Faerie Fire", "Entangling Roots", "Hibernate" },
      procs = { "Clearcasting" } },
    { id = "feralcat", name = "Feral (cat)", tree = 2,
      essential = { "Berserk", "Primal Bite", "Faerie Fire", "Cower", "Dash" },
      utility = { "Shifting Power", "Barkskin", "Innervate", "Rebirth", "Prowl" },
      buffs = { "Berserk", "Dash", "Prowl", "Mark of the Wild", "Thorns", "Omen of Clarity" },
      debuffs = { "Rake", "Rip", "Faerie Fire", "Pounce Bleed", "Pounce" },
      procs = { "Clearcasting", "Shifting Power" } },
    { id = "feralbear", name = "Feral (bear)", tree = 2,
      essential = { "Growl", "Feral Charge", "Bash", "Enrage", "Berserk" },
      utility = { "Challenging Roar", "Frenzied Regeneration", "Shifting Power", "Barkskin", "Innervate", "Rebirth", "Faerie Fire" },
      buffs = { "Frenzied Regeneration", "Enrage", "Berserk", "Barkskin", "Mark of the Wild", "Thorns", "Omen of Clarity" },
      debuffs = { TAUNTS, "Demoralizing Roar", "Faerie Fire", "Lacerate", "Bash" },
      procs = { "Clearcasting", "Shifting Power" } },
    { id = "restoration", name = "Restoration", tree = 3,
      essential = { "Swiftmend", "Wild Growth", "Nature's Swiftness", "Innervate", "Tranquility" },
      utility = { "Rebirth", "Barkskin", "Nature's Grasp" },
      buffs = { "Mark of the Wild", "Thorns", "Innervate", "Nature's Swiftness", "Barkskin", "Rejuvenation", "Regrowth", "Wild Growth", "Omen of Clarity" },
      debuffs = { "Entangling Roots", "Faerie Fire" },
      procs = { "Clearcasting" } },
}
