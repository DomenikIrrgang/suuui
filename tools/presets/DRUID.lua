-- tools/presets/DRUID.lua
-- The Druid presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-12): new
-- talents Berserk, Primal Bite, Shifting Power (Feral, instead of Tiger's
-- Fury, which no trainer teaches) and Wild Growth (Restoration); Eclipse is
-- a Balance talent (a stacking Starfire buff); Lacerate is trained; Feral
-- Charge is a Feral talent (the spell named "Feral Charge", bear only).
-- Omen of Clarity is trained and, going by its tooltip (no duration), a
-- passive, so only its Clearcasting is tracked.
--
-- Choices:
--   cooldowns whose buff or debuff only matters while it runs (Barkskin,
--   Dash, Innervate, Berserk, Enrage, Frenzied Regeneration, Nature's
--   Swiftness, Nature's Grasp, Prowl; Bash and Feral Charge on the target)
--   show it on their own icon (effect) instead of a buff entry
--   buffs that last a minute or longer (Mark of the Wild, Thorns, Moonkin
--   Form) are reminders; Faerie Fire and the DoTs a spec keeps up grey while
--   missing
--   Shifting Power is an energy cooldown, so bears don't track it

local S = dofile("tools/presets/shared.lua")
local mine, TAUNTS = S.mine, S.TAUNTS

local function remind(name) return { name, missing = "remind" } end
local function grey(name) return { name, missing = "grey" } end
local function onYou(name) return { name, effect = "you" } end
local function onTarget(name) return { name, effect = "target" } end

-- One rooted or sleeping target at a time (Nature's Grasp's roots are
-- Entangling Roots too); Overgrowth allows more roots, but one shows here.
local HOLDS = { group = "Crowd Controls", source = "mine", max = 1, icon = "Entangling Roots",
    members = { "Entangling Roots", "Hibernate" } }

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { onTarget("Bash"), "Growl", onYou("Enrage"), onYou("Nature's Grasp") },
      utility = { onYou("Barkskin"), onYou("Innervate"), onYou("Dash"), "Rebirth", "Tranquility" },
      buffs = { remind("Mark of the Wild"), remind("Thorns") },
      debuffs = { "Moonfire", "Faerie Fire", "Demoralizing Roar", HOLDS },
      procs = { "Clearcasting" } },
    -- Balance has no short cooldowns: its essentials are the minute-long ones.
    { id = "balance", name = "Balance", tree = 1,
      essential = { "Hurricane", onYou("Innervate"), onYou("Barkskin"), onYou("Nature's Grasp") },
      -- Nature's Swiftness for hybrids that reach it in Restoration
      utility = { "Rebirth", "Tranquility", onYou("Dash"), onYou("Nature's Swiftness") },
      buffs = { remind("Mark of the Wild"), remind("Thorns"), { "Moonkin Form", mine = true, missing = "remind" } },
      debuffs = { grey("Moonfire"), grey("Insect Swarm"), "Faerie Fire", HOLDS },
      procs = { "Clearcasting", "Nature's Grace", "Eclipse" } },
    { id = "feralcat", name = "Feral (cat)", tree = 2,
      essential = { "Shifting Power", "Primal Bite", onYou("Berserk"), "Cower" },
      -- Prowl's cooldown restarts when stealth breaks; its icon shows while you prowl
      utility = { onYou("Prowl"), onYou("Dash"), onYou("Barkskin"), onYou("Innervate"), "Rebirth" },
      buffs = { remind("Mark of the Wild"), remind("Thorns") },
      debuffs = { grey("Rip"), grey("Rake"), grey("Faerie Fire"), "Pounce Bleed" },
      procs = { "Clearcasting" } },
    { id = "feralbear", name = "Feral (bear)", tree = 2,
      essential = { "Primal Bite", "Growl", onTarget("Feral Charge"), onTarget("Bash"), onYou("Enrage"), onYou("Berserk") },
      utility = { onYou("Frenzied Regeneration"), "Challenging Roar", onYou("Barkskin"), onYou("Innervate"), "Rebirth" },
      buffs = { remind("Mark of the Wild"), remind("Thorns") },
      -- Lacerate stacks to 5 and is kept up, like Faerie Fire and the roar
      debuffs = { grey("Lacerate"), grey("Faerie Fire"), grey("Demoralizing Roar"), TAUNTS },
      procs = { "Clearcasting" } },
    { id = "restoration", name = "Restoration", tree = 3,
      essential = { "Swiftmend", "Wild Growth", onYou("Nature's Swiftness"), onYou("Innervate") },
      utility = { "Tranquility", "Rebirth", onYou("Barkskin"), onYou("Nature's Grasp") },
      -- your own HoTs on yourself, for self-healing
      buffs = { remind("Mark of the Wild"), remind("Thorns"), mine("Rejuvenation"), mine("Regrowth") },
      debuffs = { "Moonfire", "Faerie Fire", HOLDS },
      procs = { "Clearcasting" } },
}
