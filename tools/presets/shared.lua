-- tools/presets/shared.lua
-- Groups and helpers several classes' presets use (see tools/presets_source.lua
-- for the format). Each class file: local S = dofile("tools/presets/shared.lua").

local function mine(name) return { name, mine = true } end

-- Paladin groups: one slot for your seal, your blessing on yourself, your
-- judgement, and other paladins' judgements.
local SEALS = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Wisdom", "Seal of Light", "Seal of Justice", "Seal of Command", "Seal of Fury" }
local BLESSINGS = { "Blessing of Might", "Greater Blessing of Might", "Blessing of Wisdom", "Greater Blessing of Wisdom",
    "Blessing of Kings", "Greater Blessing of Kings", "Blessing of Salvation", "Greater Blessing of Salvation",
    "Blessing of Light", "Greater Blessing of Light" }
-- the judgements that stay on the target (Righteousness and Command only
-- deal damage). Judgement of Fury, Forever's taunt from Seal of Fury, is in
-- the Taunts group instead.
local JUDGEMENTS = { "Judgement of the Crusader", "Judgement of Wisdom", "Judgement of Light", "Judgement of Justice" }
local function seal(icon) return { group = "Seals", source = "mine", max = 1, icon = icon, members = SEALS } end
local function blessing(icon) return { group = "Blessings", source = "mine", max = 1, icon = icon, members = BLESSINGS } end
local MY_JUDGEMENT = { group = "My Judgements", source = "mine", max = 1, icon = "Judgement of the Crusader", members = JUDGEMENTS }
-- Tanks: the taunt on your target, whoever cast it (another tank's too; a
-- hunter pet's Growl counts as well). A Forever paladin taunts with
-- Judgement of Fury (Seal of Fury's judgement); Hand of Reckoning exists in
-- the client but no Forever paladin learns it.
local TAUNTS = { group = "Taunts", source = "any", max = 2, icon = "Taunt",
    members = { "Taunt", "Growl", "Mocking Blow", "Challenging Shout", "Challenging Roar", "Judgement of Fury" } }
-- Mages: one armor at a time, so one slot (Molten Armor isn't in Forever).
local function armors(icon) return { group = "Armors", source = "mine", max = 1, icon = icon,
    members = { "Frost Armor", "Ice Armor", "Mage Armor" } } end
local OTHERS_JUDGEMENTS = { group = "Others' Judgements", source = "others", max = 3, icon = "Judgement of Wisdom", members = JUDGEMENTS }

return {
    mine = mine, seal = seal, blessing = blessing, armors = armors,
    SEALS = SEALS, BLESSINGS = BLESSINGS, JUDGEMENTS = JUDGEMENTS,
    MY_JUDGEMENT = MY_JUDGEMENT, OTHERS_JUDGEMENTS = OTHERS_JUDGEMENTS, TAUNTS = TAUNTS,
}
