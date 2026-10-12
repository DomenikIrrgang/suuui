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
--   forms (live conditions, in combat too): bear abilities and auras show in
--   bear form, cat ones in cat form (Primal Bite is bear only, confirmed in
--   game), Berserk in either (it requires one), Barkskin in every form
--   (confirmed in game), heals
--   (Tranquility, Swiftmend, Wild Growth, Nature's Swiftness) in caster form
--   only (Moonkin Form blocks healing), the other spells (Innervate, Rebirth, Hurricane, the DoTs) in caster or moonkin form.
--   Nature's Grasp (castable while shapeshifted), Faerie Fire (one name for
--   the caster and the feral spell), the reminders and the shared groups
--   show in every form. So each preset is right whatever you shift into: the
--   cat preset shows Bash and Feral Charge in bear form, the bear preset
--   Dash in cat form, both their caster cooldowns in caster form.
--   cooldowns whose buff or debuff only matters while it runs (Barkskin,
--   Dash, Innervate, Berserk, Enrage, Frenzied Regeneration, Nature's
--   Swiftness, Nature's Grasp, Prowl; Feral Charge on the target) show it on
--   their own icon (effect) instead of a buff entry; Bash and Pounce are in
--   the shared Stuns
--   buffs that last a minute or longer (Mark of the Wild, Thorns) are
--   reminders; Moonkin Form's reminds in caster form only (not while you
--   travel or tank); your HoTs on yourself (Restoration) show while up
--   debuffs a spec keeps up (Faerie Fire, the DoTs, the cat's Bleeds,
--   Lacerate) grey with a hostile target (the default); crowd control, and
--   Restoration's occasional Moonfire and Faerie Fire, only while up
--   Shifting Power is an energy cooldown: cat form only

local S = dofile("tools/presets/shared.lua")
local TAUNTS = S.TAUNTS

local function remind(name) return { name, missing = "remind" } end
local function hide(name) return { name, missing = "hide" } end
local function onYou(name) return { name, effect = "you" } end

-- An entry (a name or a table) shown only in these forms.
local function forms(entry, ...)
    if type(entry) == "string" then entry = { entry } end
    entry.when = { conditions = { { type = "stance", stances = { ... } } } }
    return entry
end
local function bear(entry) return forms(entry, "bear") end
local function cat(entry) return forms(entry, "cat") end
local function feral(entry) return forms(entry, "bear", "cat") end
-- heals: Moonkin Form blocks them
local function healing(entry) return forms(entry, "caster") end
-- other spells: caster or Moonkin Form
local function casting(entry) return forms(entry, "caster", "moonkin") end

-- One rooted or sleeping target at a time (Nature's Grasp's roots are
-- Entangling Roots too, in any form); Overgrowth allows more roots, but one
-- shows here. Shown only while up.
local HOLDS = { group = "Crowd Controls", source = "mine", max = 1, icon = "Entangling Roots", missing = "hide",
    members = { "Entangling Roots", "Hibernate" } }

local function feralCharge()
    return bear({ group = "Feral Charge", members = { "Feral Charge", "Feral Charge (Bear)" }, effect = "target" })
end

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { bear("Bash"), bear("Growl"), bear(onYou("Enrage")), onYou("Nature's Grasp") },
      utility = { onYou("Barkskin"), casting(onYou("Innervate")), cat(onYou("Dash")), casting("Rebirth"), healing("Tranquility") },
      buffs = { remind("Mark of the Wild"), remind("Thorns") },
      debuffs = { casting("Moonfire"), "Faerie Fire", bear("Demoralizing Roar"), HOLDS, S.STUNS },
      procs = { "Clearcasting" } },
    -- Balance has no short cooldowns: its essentials are the minute-long ones.
    { id = "balance", name = "Balance", tree = 1,
      essential = { casting("Hurricane"), casting(onYou("Innervate")), onYou("Barkskin"), onYou("Nature's Grasp") },
      -- Nature's Swiftness for hybrids that reach it in Restoration
      utility = { casting("Rebirth"), healing("Tranquility"), cat(onYou("Dash")), casting(onYou("Nature's Swiftness")) },
      buffs = { remind("Mark of the Wild"), remind("Thorns"), forms({ "Moonkin Form", mine = true, missing = "remind" }, "caster") },
      debuffs = { casting("Moonfire"), casting("Insect Swarm"), "Faerie Fire", HOLDS, S.STUNS },
      procs = { "Clearcasting", "Nature's Grace", "Eclipse" } },
    { id = "feralcat", name = "Feral (cat)", tree = 2,
      -- Bash and Feral Charge for the times you shift to bear
      essential = { cat("Shifting Power"), bear("Primal Bite"), feral(onYou("Berserk")), cat("Cower"), bear("Bash"), feralCharge() },
      -- Prowl's cooldown restarts when stealth breaks; its icon shows while you prowl
      utility = { cat(onYou("Prowl")), cat(onYou("Dash")), onYou("Barkskin"), casting(onYou("Innervate")), casting("Rebirth") },
      buffs = { remind("Mark of the Wild"), remind("Thorns") },
      -- Pounce Bleed only after an opener
      debuffs = { cat({ collection = "Bleeds", entries = { "Rip", "Rake", hide("Pounce Bleed") } }),
          "Faerie Fire", S.physical({ druid = true }), S.STUNS },
      procs = { "Clearcasting" } },
    { id = "feralbear", name = "Feral (bear)", tree = 2,
      essential = { bear("Primal Bite"), bear("Growl"), feralCharge(), bear("Bash"), bear(onYou("Enrage")), feral(onYou("Berserk")) },
      -- Dash for the times you shift to cat
      utility = { bear(onYou("Frenzied Regeneration")), bear("Challenging Roar"), onYou("Barkskin"), casting(onYou("Innervate")),
          casting("Rebirth"), cat(onYou("Dash")) },
      buffs = { remind("Mark of the Wild"), remind("Thorns") },
      -- Lacerate stacks to 5 and is kept up, like Faerie Fire and the roar
      debuffs = { bear("Lacerate"), "Faerie Fire", S.physical({ tank = true, druid = true }), S.STUNS, TAUNTS },
      procs = { "Clearcasting" } },
    { id = "restoration", name = "Restoration", tree = 3,
      essential = { healing("Swiftmend"), healing("Wild Growth"), healing(onYou("Nature's Swiftness")), casting(onYou("Innervate")) },
      utility = { healing("Tranquility"), casting("Rebirth"), onYou("Barkskin"), onYou("Nature's Grasp") },
      -- your own HoTs on yourself, for self-healing, while up
      buffs = { remind("Mark of the Wild"), remind("Thorns"), { "Rejuvenation", mine = true, missing = "hide" },
          { "Regrowth", mine = true, missing = "hide" } },
      debuffs = { casting(hide("Moonfire")), hide("Faerie Fire"), HOLDS, S.STUNS },
      procs = { "Clearcasting" } },
}
