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
-- Tanks (always the last debuff entry of a tank preset): the taunt on your target, whoever cast it (another tank's too; a
-- hunter pet's Growl counts as well). A Forever paladin taunts with
-- Judgement of Fury (Seal of Fury's judgement); Hand of Reckoning exists in
-- the client but no Forever paladin learns it.
local TAUNTS = { group = "Taunts", source = "any", max = 2, icon = "Taunt",
    members = { "Taunt", "Growl", "Mocking Blow", "Challenging Shout", "Challenging Roar", "Judgement of Fury" } }
-- Mages: one armor at a time, so one slot (Molten Armor isn't in Forever).
local function armors(icon) return { group = "Armors", source = "mine", max = 1, icon = icon,
    members = { "Frost Armor", "Ice Armor", "Mage Armor" } } end
local OTHERS_JUDGEMENTS = { group = "Others' Judgements", source = "others", max = 3, icon = "Judgement of Wisdom", members = JUDGEMENTS }

-- Debuffs that don't stack across classes, from anyone (whoever put it up,
-- you needn't): armor and attack power reduction, the attack-speed slow
-- tanks want on their target, and healing reduction (PvP; hidden until shown).
local ARMOR_REDUCTION = { group = "Armor Reduction", source = "any", max = 1, icon = "Sunder Armor",
    members = { "Sunder Armor", "Expose Armor" } }
local AP_REDUCTION = { group = "Attack Power Reduction", source = "any", max = 1, icon = "Demoralizing Shout",
    members = { "Demoralizing Shout", "Demoralizing Roar", "Vindication" } }
local ATTACK_SLOWS = { group = "Attack Speed Slows", source = "any", max = 1, icon = "Thunder Clap",
    members = { "Thunder Clap", "Hurricane" } }
local HEALING_REDUCTION = { group = "Healing Reduction", source = "any", max = 1, icon = "Mortal Strike", hidden = true,
    members = { "Mortal Strike", "Wound Poison", "Wound Poison II", "Wound Poison III", "Wound Poison IV" } }

-- Every stun on the target, from anyone: whoever stuns sees what's already
-- on it, so stuns don't overlap (proc stuns included; Seal of Justice's is
-- named "Stun").
local STUNS = { group = "Stuns", source = "any", max = 2, icon = "Hammer of Justice",
    members = { "Hammer of Justice", "Cheap Shot", "Kidney Shot", "Bash", "Pounce", "Concussion Blow",
        "Charge Stun", "Intercept Stun", "Intimidation", "War Stomp", "Holy Wrath", "Stun", "Impact",
        "Starfire Stun", "Improved Concussive Shot", "Pyroclasm", "Blackout" } }

-- A copy of a group (or entry) with other fields: with(AP_REDUCTION, { missing = "grey" }).
local function with(t, fields)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    for k, v in pairs(fields) do out[k] = v end
    return out
end

return {
    mine = mine, seal = seal, blessing = blessing, armors = armors,
    SEALS = SEALS, BLESSINGS = BLESSINGS, JUDGEMENTS = JUDGEMENTS,
    MY_JUDGEMENT = MY_JUDGEMENT, OTHERS_JUDGEMENTS = OTHERS_JUDGEMENTS, TAUNTS = TAUNTS,
    ARMOR_REDUCTION = ARMOR_REDUCTION, AP_REDUCTION = AP_REDUCTION, ATTACK_SLOWS = ATTACK_SLOWS,
    HEALING_REDUCTION = HEALING_REDUCTION, STUNS = STUNS, with = with,
}
