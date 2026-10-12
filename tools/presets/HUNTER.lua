-- tools/presets/HUNTER.lua
-- The Hunter presets (format: tools/presets_source.lua).
-- From Forever's own class data (trainer + talents, 2026-10-12): Aimed
-- Shot is trained, not a talent, and shares its cooldown with Multi-Shot;
-- Summon Hawk (Beast Mastery) shares Arcane Shot's. New: Sniper Shot
-- (Marksmanship talent and trained ranks), Summon Hawk, Strider Kick,
-- Expose Prey and Lacerating Strikes (Survival). Wyvern Sting, Readiness and
-- Aspect of the Viper aren't trained or talents; Tranquilizing Shot comes
-- from a book. Survival is a melee spec here (Predator's Edge, Strider Kick).
-- Aspects (one at a time) and Trueshot Aura last until cancelled, so they
-- remind; stings (one per hunter on a target) are one slot.
-- Short effects of a cooldown sit on its icon (effect): Rapid Fire,
-- Deterrence, Concussive Shot, Scatter Shot, Counterattack's root. Bestial
-- Wrath and Intimidation are your pet's, which the tracker doesn't see, so
-- they're plain cooldowns. Mongoose Bite and Counterattack light up by
-- themselves (reactive). Passive talents (Careful Aim, Predator's Edge,
-- Focused Fire) aren't procs and aren't tracked; Rapid Killing's buff isn't
-- in the client scan (only the talent's ID), so it's left out for now.

local S = dofile("tools/presets/shared.lua")

local ASPECTS = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Beast",
    "Aspect of the Pack", "Aspect of the Wild" }
local function aspects(icon) return { group = "Aspects", source = "mine", max = 1, icon = icon, members = ASPECTS,
    missing = "remind" } end
local STINGS = { group = "Stings", source = "mine", max = 1, icon = "Serpent Sting",
    members = { "Serpent Sting", "Scorpid Sting", "Viper Sting" } }
-- Deadly Aspects (Beast Mastery): Quick Shots in Aspect of the Hawk, Quick
-- Strikes (IDs right after Forever's Aspect of the Beast) in Aspect of the
-- Beast; one aspect, so one of them.
local DEADLY_ASPECTS = { group = "Aspect Procs", source = "mine", max = 1, icon = "Quick Shots",
    members = { "Quick Shots", "Quick Strikes" } }
-- your fire trap's burn on the target (one fire trap at a time); Explosive
-- Trap's burn is named "Explosive Trap Effect" in the client
local FIRE_TRAPS = { group = "Fire Traps", source = "mine", max = 1, icon = "Immolation Trap",
    members = { "Immolation Trap", "Explosive Trap", "Explosive Trap Effect" } }

local RAPID_FIRE = { "Rapid Fire", effect = "you" }
local CONCUSSIVE = { "Concussive Shot", effect = "target" }
-- one Hunter's Mark per target: another hunter's counts too
local MARK = { "Hunter's Mark", source = "any", missing = "warn" }

return {
    { id = "unspecced", name = "Unspecced", tree = 0,
      essential = { "Arcane Shot", "Raptor Strike", "Mongoose Bite", "Aimed Shot", "Multi-Shot" },
      utility = { CONCUSSIVE, RAPID_FIRE, "Freezing Trap", "Immolation Trap", "Disengage", "Feign Death" },
      buffs = { aspects("Aspect of the Hawk") },
      debuffs = { { "Hunter's Mark", source = "any" }, STINGS, "Wing Clip", S.STUNS },
      procs = {} },
    -- ranged with pet and hawks; Summon Hawk and Arcane Shot share one
    -- cooldown, both kept so the icon is there before Summon Hawk is learnt
    { id = "beastmastery", name = "Beast Mastery", tree = 1,
      essential = { "Summon Hawk", "Arcane Shot", "Aimed Shot", "Multi-Shot", "Raptor Strike" },
      utility = { "Bestial Wrath", "Intimidation", RAPID_FIRE, CONCUSSIVE, "Freezing Trap", "Explosive Trap", "Feign Death" },
      buffs = { aspects("Aspect of the Hawk") },
      debuffs = { MARK, STINGS, "Wing Clip", S.STUNS },
      procs = { DEADLY_ASPECTS } },
    { id = "marksmanship", name = "Marksmanship", tree = 2,
      essential = { "Aimed Shot", "Multi-Shot", "Arcane Shot", "Sniper Shot" },
      utility = { RAPID_FIRE, { "Scatter Shot", effect = "target" }, CONCUSSIVE, "Freezing Trap", "Feign Death",
          "Disengage", { "Flare", hidden = true } },
      buffs = { { "Trueshot Aura", missing = "remind" }, aspects("Aspect of the Hawk") },
      debuffs = { MARK, STINGS, "Wing Clip", S.STUNS },
      procs = { "Quick Shots" } },
    -- melee: Expose Prey (on Hunter's Mark targets) and dodges open
    -- Mongoose Bite, parries Counterattack
    { id = "survival", name = "Survival", tree = 3,
      essential = { "Raptor Strike", "Mongoose Bite", { "Counterattack", effect = "target" }, "Strider Kick",
          "Arcane Shot", "Multi-Shot" },
      utility = { { "Deterrence", effect = "you" }, RAPID_FIRE, "Disengage", "Feign Death", "Freezing Trap",
          "Immolation Trap", "Explosive Trap" },
      buffs = { aspects("Aspect of the Monkey") },
      debuffs = { MARK, "Wing Clip", STINGS, "Lacerating Strikes", FIRE_TRAPS, S.STUNS },
      procs = { "Expose Prey" } },
}
