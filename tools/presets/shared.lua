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

-- A member that comes from a talent: it counts while another player of its
-- class is in your group (they may have it), or you have the talent yourself.
-- Shared groups serve every class, so the talent goes by its spell ID.
local function talented(class, talentID, name)
    return { { name, when = { match = "any", conditions = {
        { type = "classes", classes = { class }, others = true },
        { type = "talent", talents = { talentID } } } } } }
end

-- Members you count only once you've learned them: while another player of
-- the class is in your group (they may have it), or you know the spell
-- yourself (a level 11 warrior has no Demoralizing Shout yet). For auras
-- named like the spell that puts them up; by() for the rest (Charge Stun,
-- Wound Poison, a pet's Growl).
local function learned(classes, ...)
    if type(classes) == "string" then classes = { classes } end
    local out = {}
    for _, name in ipairs({ ... }) do
        out[#out + 1] = { name, when = { match = "any", conditions = {
            { type = "classes", classes = classes, others = true },
            { type = "talent", talents = { name } } } } }
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
-- (anywhere: in the open world you taunt mobs off players outside your
-- group too; only while one is up, nothing to grey while none is)
local TAUNTS = { group = "Taunts", source = "any", max = 2, missing = "hide",
    members = members(learned("WARRIOR", "Taunt", "Mocking Blow", "Challenging Shout"),
        by({ "DRUID", "HUNTER" }, "Growl"), learned("DRUID", "Challenging Roar"), by("PALADIN", "Judgement of Fury")) }
-- Mages: one armor at a time, so one slot (Molten Armor isn't in Forever).
local function armors(icon) return { group = "Armors", source = "mine", max = 1, icon = icon,
    members = { "Frost Armor", "Ice Armor", "Mage Armor" } } end
-- (in a group only, and only while one is up)
local OTHERS_JUDGEMENTS = { group = "Others' Judgements", source = "others", max = 3, icon = "Judgement of Wisdom",
    missing = "hide", when = { conditions = { { type = "group", value = "solo", ["not"] = true } } }, members = JUDGEMENTS }

-- Debuffs that don't stack across classes, from anyone (whoever put it up,
-- you needn't): armor and attack power reduction, the attack-speed slow
-- tanks want on their target, and healing reduction (against players only).
-- Each member counts only while another player of its class is in your
-- group or you know it yourself; with none of them, the slot is gone. Their icon is automatic: the first
-- member you know, else the first that can show.
local ARMOR_REDUCTION = { group = "Armor Reduction", source = "any", max = 1,
    members = members(learned("WARRIOR", "Sunder Armor"), learned("ROGUE", "Expose Armor")) }
local AP_REDUCTION = { group = "Attack Power Reduction", source = "any", max = 1,
    members = members(learned("WARRIOR", "Demoralizing Shout"), learned("DRUID", "Demoralizing Roar"), talented("PALADIN", 9452, "Vindication")) }
local ATTACK_SLOWS = { group = "Attack Speed Slows", source = "any", max = 1,
    members = members(learned("WARRIOR", "Thunder Clap"), learned("DRUID", "Hurricane")) }
local HEALING_REDUCTION = { group = "Healing Reduction", source = "any", max = 1,
    when = { conditions = { { type = "target", kinds = { "player" } } } },
    members = members(talented("WARRIOR", 12294, "Mortal Strike"),
        by("ROGUE", "Wound Poison", "Wound Poison II", "Wound Poison III", "Wound Poison IV")) }

-- Every stun on the target, from anyone: whoever stuns sees what's already
-- on it, so stuns don't overlap (proc stuns included; Seal of Justice's is
-- named "Stun").
-- Every preset of a class or spec that can stun has it: all paladins,
-- warriors, rogues, druids (Bash) and hunters; Fire mages (Impact),
-- Destruction warlocks (Pyroclasm), Shadow priests (Blackout).
-- (War Stomp is a Tauren's, any class: no condition)
-- (only while one is up: a stun isn't something you keep up)
local STUNS = { group = "Stuns", source = "any", max = 2, missing = "hide",
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
    withClass = withClass, physical = physical, by = by, learned = learned, members = members,
}
