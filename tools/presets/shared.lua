-- tools/presets/shared.lua
-- Groups and helpers several classes' presets use (see tools/presets_source.lua
-- for the format). Each class file: local S = dofile("tools/presets/shared.lua").

local unpack = table.unpack or unpack

local function mine(name) return { name, mine = true } end

-- "while one of these classes is in your group (you included)"
local function withClass(...)
    return { conditions = { { type = "classes", classes = { ... } } } }
end

-- Members of a class's own spells: they count only while someone of that
-- class is around (you, or someone in your group). by("WARRIOR", "Sunder
-- Armor") or by({ "DRUID", "HUNTER" }, "Growl") (a hunter's pet growls).
local function by(classes, ...)
    if type(classes) == "string" then classes = { classes } end
    local out = {}
    for _, name in ipairs({ ... }) do
        out[#out + 1] = { name, when = withClass(unpack(classes)) }
    end
    return out
end

-- A list of members from several lists (by() results and plain names).
local function members(...)
    local out = {}
    for _, part in ipairs({ ... }) do
        if type(part) == "table" and part[1] == nil then part = {} end
        if type(part) == "string" then out[#out + 1] = part
        elseif type(part) == "table" and type(part[1]) == "table" then
            for _, m in ipairs(part) do out[#out + 1] = m end
        else
            out[#out + 1] = part
        end
    end
    return out
end

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
    members = members(by("WARRIOR", "Taunt", "Mocking Blow", "Challenging Shout"),
        by({ "DRUID", "HUNTER" }, "Growl"), by("DRUID", "Challenging Roar"), by("PALADIN", "Judgement of Fury")) }
-- Mages: one armor at a time, so one slot (Molten Armor isn't in Forever).
local function armors(icon) return { group = "Armors", source = "mine", max = 1, icon = icon,
    members = { "Frost Armor", "Ice Armor", "Mage Armor" } } end
local OTHERS_JUDGEMENTS = { group = "Others' Judgements", source = "others", max = 3, icon = "Judgement of Wisdom", members = JUDGEMENTS }

-- Debuffs that don't stack across classes, from anyone (whoever put it up,
-- you needn't): armor and attack power reduction, the attack-speed slow
-- tanks want on their target, and healing reduction (PvP; hidden until shown).
-- Each member counts only while its class is around (you or your group); with
-- none of them around, the slot is gone.
local ARMOR_REDUCTION = { group = "Armor Reduction", source = "any", max = 1, icon = "Sunder Armor",
    members = members(by("WARRIOR", "Sunder Armor"), by("ROGUE", "Expose Armor")) }
local AP_REDUCTION = { group = "Attack Power Reduction", source = "any", max = 1, icon = "Demoralizing Shout",
    members = members(by("WARRIOR", "Demoralizing Shout"), by("DRUID", "Demoralizing Roar"), by("PALADIN", "Vindication")) }
local ATTACK_SLOWS = { group = "Attack Speed Slows", source = "any", max = 1, icon = "Thunder Clap",
    members = members(by("WARRIOR", "Thunder Clap"), by("DRUID", "Hurricane")) }
local HEALING_REDUCTION = { group = "Healing Reduction", source = "any", max = 1, icon = "Mortal Strike", hidden = true,
    members = members(by("WARRIOR", "Mortal Strike"),
        by("ROGUE", "Wound Poison", "Wound Poison II", "Wound Poison III", "Wound Poison IV")) }

-- Every stun on the target, from anyone: whoever stuns sees what's already
-- on it, so stuns don't overlap (proc stuns included; Seal of Justice's is
-- named "Stun").
-- Every preset of a class or spec that can stun has it: all paladins,
-- warriors, rogues, druids (Bash) and hunters; Fire mages (Impact),
-- Destruction warlocks (Pyroclasm), Shadow priests (Blackout).
-- (War Stomp is a Tauren's, any class: no condition)
local STUNS = { group = "Stuns", source = "any", max = 2, icon = "Hammer of Justice",
    members = members(by("PALADIN", "Hammer of Justice", "Holy Wrath", "Stun"), by("ROGUE", "Cheap Shot", "Kidney Shot"),
        by("DRUID", "Bash", "Pounce", "Starfire Stun"), by("WARRIOR", "Concussion Blow", "Charge Stun", "Intercept Stun"),
        by("HUNTER", "Intimidation", "Improved Concussive Shot"), by("MAGE", "Impact"), by("WARLOCK", "Pyroclasm"),
        by("PRIEST", "Blackout"), "War Stomp") }

-- The Physical Debuffs collection: armor reduction from anyone, Faerie Fire
-- while a druid is in the group (any druid keeps it up: grey while missing),
-- Curse of Recklessness while a warlock is (often another curse: hidden while
-- missing); tanks add attack power reduction and the attack-speed slow.
-- opts: tank = true; druid = true (druids track their own Faerie Fire).
local function physical(opts)
    opts = opts or {}
    local entries = { ARMOR_REDUCTION }
    if not opts.druid then
        entries[#entries + 1] = { "Faerie Fire", source = "any", missing = "grey", when = withClass("DRUID") }
    end
    entries[#entries + 1] = { "Curse of Recklessness", source = "any", missing = "hide", when = withClass("WARLOCK") }
    if opts.tank then
        entries[#entries + 1] = AP_REDUCTION
        entries[#entries + 1] = ATTACK_SLOWS
    end
    return { collection = "Physical Debuffs", entries = entries }
end

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
    withClass = withClass, physical = physical, by = by, members = members,
}
