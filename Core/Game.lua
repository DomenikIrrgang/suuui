-- Facts about the game, not choices about the look.
--
-- A class colour, a power type's colour and a spell school's colour are not design
-- language: they are what the client says those things ARE. "Frost is cyan" and "mages are
-- light blue" are as fixed as each other, so the theme has nothing to offer here and the
-- theme editor would only present controls that are wrong to touch. They live in Core
-- rather than in whichever plugin paints them first, because a resource bar, a cast bar, a
-- nameplate and a debuff border all describe the same facts — and two copies of a fact
-- drift.
--
-- Note the split this draws with the theme: whether a health bar is class-coloured at all
-- is a look decision and lives in the theme as colorUseClassColors; WHICH colour a mage
-- gets is a fact and lives here. Theme:GetUnitColor is the one place the two meet.
--
-- The spell-school cache lives here for the same reason, and exists at all because this
-- client has no API mapping a spell to its school: neither GetSpellInfo nor UnitCastingInfo
-- reports one, so the combat log is the only source. Whoever is already reading the log
-- calls LearnFromCombatLog; everything else reads back out of SchoolOf.
local type, ipairs = type, ipairs
local floor = math.floor

local M = {}

---------------------------------------------------------------------------
-- Power
---------------------------------------------------------------------------

-- Keyed by the powerType UnitPowerType reports.
local POWER = {
    [0] = {0.00, 0.44, 0.87, 1},  -- Mana
    [1] = {0.77, 0.12, 0.23, 1},  -- Rage
    [2] = {1.00, 0.50, 0.25, 1},  -- Focus
    [3] = {1.00, 0.96, 0.41, 1},  -- Energy
    [4] = {0.00, 0.44, 0.87, 1},  -- Combo points
    [5] = {0.50, 0.50, 0.50, 1},  -- Runes
    [6] = {0.00, 0.82, 1.00, 1},  -- Runic power
}

--- The colour for a power type, falling back to mana for one this client does not name.
-- @param powerType number
-- @return table  {r,g,b,a}
function M:PowerColor(powerType)
    return POWER[powerType] or POWER[0]
end

---------------------------------------------------------------------------
-- Classes
---------------------------------------------------------------------------

-- Blizzard's own class colours, copied for the same reason the school colours below are:
-- the point of class colouring is that it matches what the player already reads on every
-- nameplate, raid frame and chat line, so these are the client's values rather than chosen
-- ones.
--
-- This table is the fallback, not the first source. The client ships the same values in
-- RAID_CLASS_COLORS, and a player may run an addon that retints them UI-wide through
-- CUSTOM_CLASS_COLORS; both are preferred when present so SuuUI agrees with the rest of
-- their UI instead of being the one frame that disagrees. The copy exists for the login
-- moment before either global has appeared.
--
-- The four classes this expansion does not have are here anyway: a class colour is a fact
-- whether or not TBC ships the class, and POWER above already names runes for the same
-- reason.
local CLASS = {
    WARRIOR     = {0.78, 0.61, 0.43, 1},
    PALADIN     = {0.96, 0.55, 0.73, 1},
    HUNTER      = {0.67, 0.83, 0.45, 1},
    ROGUE       = {1.00, 0.96, 0.41, 1},
    PRIEST      = {1.00, 1.00, 1.00, 1},
    SHAMAN      = {0.00, 0.44, 0.87, 1},
    MAGE        = {0.41, 0.80, 0.94, 1},
    WARLOCK     = {0.58, 0.51, 0.79, 1},
    DRUID       = {1.00, 0.49, 0.04, 1},
    DEATHKNIGHT = {0.77, 0.12, 0.23, 1},
    MONK        = {0.00, 1.00, 0.60, 1},
    DEMONHUNTER = {0.64, 0.19, 0.79, 1},
    EVOKER      = {0.20, 0.58, 0.50, 1},
}

-- Converted client colours, keyed by class file. The client hands out {r=,g=,b=} objects
-- and callers here want a {r,g,b,a} array, so the conversion is cached: a class colour is
-- read whenever a bar repaints, and allocating a table per repaint for a value that never
-- changes is waste. The cache is validated against the source rather than trusted, so an
-- addon swapping CUSTOM_CLASS_COLORS at runtime is still picked up — that costs three
-- number compares and no allocation on the hit path.
local classCache = {}

local function classSource()
    if type(CUSTOM_CLASS_COLORS) == "table" then return CUSTOM_CLASS_COLORS end
    if type(RAID_CLASS_COLORS) == "table" then return RAID_CLASS_COLORS end
    return nil
end

--- The colour for a class, or nil when the class is not one this knows.
--
-- nil is a real answer, as with SchoolColor: "no class" is what an NPC, a totem or a
-- pet reports, and the caller's own fallback is the right response rather than a
-- stand-in colour invented here.
-- @param classFile string  The non-localised class token, e.g. "WARRIOR"
-- @return table|nil  {r,g,b,a}
function M:ClassColor(classFile)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    local src = classSource()
    local c = src and src[classFile]
    if type(c) == "table" and type(c.r) == "number" then
        local hit = classCache[classFile]
        if hit and hit[1] == c.r and hit[2] == c.g and hit[3] == c.b then return hit end
        hit = { c.r, c.g, c.b, 1 }
        classCache[classFile] = hit
        return hit
    end
    return CLASS[classFile]
end

--- The colour for a unit's class, or nil when the unit or its class is unknown.
--
-- UnitClass returns the localised name first and the class file second; only the second
-- is a stable key, so the first is deliberately discarded.
-- @param unit string  Unit id, e.g. "player"
-- @return table|nil  {r,g,b,a}
function M:UnitClassColor(unit)
    if type(unit) ~= "string" or type(UnitClass) ~= "function" then return nil end
    local _, classFile = UnitClass(unit)
    return self:ClassColor(classFile)
end

---------------------------------------------------------------------------
-- Spell schools
---------------------------------------------------------------------------

--- The combat log's school bits, named.
M.SCHOOL = {
    PHYSICAL = 0x01,
    HOLY     = 0x02,
    FIRE     = 0x04,
    NATURE   = 0x08,
    FROST    = 0x10,
    SHADOW   = 0x20,
    ARCANE   = 0x40,
}

-- The seven pure schools carry Blizzard's own values deliberately: the point of school
-- colouring is that it matches what the player already reads everywhere else in the game,
-- so these are copied rather than chosen.
--
-- The two mixed masks below are different. The client names them (everything magical, and
-- everything at once) but ships no colour for either, so these two ARE chosen — picked to
-- sit outside the pure set so a mixed school never reads as one of its parts.
local SCHOOL_COLORS = {
    [0x01] = {1.00, 1.00, 0.00, 1},  -- Physical
    [0x02] = {1.00, 0.90, 0.50, 1},  -- Holy
    [0x04] = {1.00, 0.50, 0.00, 1},  -- Fire
    [0x08] = {0.30, 1.00, 0.30, 1},  -- Nature
    [0x10] = {0.50, 1.00, 1.00, 1},  -- Frost
    [0x20] = {0.50, 0.50, 1.00, 1},  -- Shadow
    [0x40] = {1.00, 0.50, 1.00, 1},  -- Arcane
    [0x7E] = {0.40, 0.70, 1.00, 1},  -- Magic (every school but physical)
    [0x7F] = {1.00, 0.30, 0.30, 1},  -- Chaos (all schools)
}

local SCHOOL_BITS = { 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40 }

-- Averages the set bits of a mask the table above does not name outright.
--
-- A blend rather than "take the lowest bit", because a two-school spell genuinely is both
-- and picking one would paint a frost-fire spell as plain fire — hiding exactly the
-- distinction school colouring exists to show. Bit tests are arithmetic rather than
-- bit.band so this file behaves identically under the client's Lua and the test runner's.
--
-- Results are memoised: masks recur constantly, and SchoolColor is on a path that runs per
-- cast, which is no place to allocate a table per call.
local blended = {}

local function blend(mask)
    local hit = blended[mask]
    if hit then return hit end
    local r, g, b, n = 0, 0, 0, 0
    for _, value in ipairs(SCHOOL_BITS) do
        if floor(mask / value) % 2 == 1 then
            local c = SCHOOL_COLORS[value]
            r, g, b, n = r + c[1], g + c[2], b + c[3], n + 1
        end
    end
    if n == 0 then return nil end
    local out = { r / n, g / n, b / n, 1 }
    blended[mask] = out
    return out
end

--- The colour for a school mask, or nil when the mask says nothing.
--
-- nil is a real answer and every caller has to handle it: a mask of 0, or the absent mask
-- of a spell nothing has taught us yet, means "not known" — and the caller's own fallback
-- is the right response rather than some stand-in colour invented here.
-- @param mask number|nil
-- @return table|nil  {r,g,b,a}
function M:SchoolColor(mask)
    if type(mask) ~= "number" or mask <= 0 then return nil end
    return SCHOOL_COLORS[mask] or blend(mask)
end

---------------------------------------------------------------------------
-- Learned schools
---------------------------------------------------------------------------

local schools = {}  -- [spellId] = mask

--- The school recorded for a spell, or nil if nothing has reported one yet.
-- @param spellId number
-- @return number|nil
function M:SchoolOf(spellId)
    if type(spellId) ~= "number" then return nil end
    return schools[spellId]
end

--- Records a spell's school. Returns whether that changed what we knew.
-- @param spellId number
-- @param mask number
-- @return bool
function M:LearnSchool(spellId, mask)
    if type(spellId) ~= "number" then return false end
    if type(mask) ~= "number" or mask <= 0 then return false end
    local had = schools[spellId]
    schools[spellId] = mask
    return had ~= mask
end

-- SPELL_ABSORBED is the one spell-prefixed subevent that must be skipped: after a swing it
-- carries the absorbing caster's GUID where every other line carries a spell id, so reading
-- it positionally caches nonsense against a nonsense key.
local SKIP = { SPELL_ABSORBED = true }

--- Reads the school off the combat log line currently being dispatched, and records it.
--
-- Meant to be called from a handler that is already reading the log, where it costs one
-- more multiple-return unpack and no allocation.
--
-- It returns what the line said even when the cache already knew it. That matters with more
-- than one cast bar alive: both read the same line, and returning only on a fresh learn
-- would mean whichever handler ran second never heard about its own spell.
-- @return number|nil spellId, number|nil mask
function M:LearnFromCombatLog()
    if type(CombatLogGetCurrentEventInfo) ~= "function" then return nil end
    local _, subevent, _, _, _, _, _, _, _, _, _, spellId, _, mask =
        CombatLogGetCurrentEventInfo()
    if type(subevent) ~= "string" or SKIP[subevent] then return nil end
    -- Only the spell and ranged families name a spell at slots 12-14. A swing line has
    -- damage numbers there; an environmental one has a damage type.
    local prefix = subevent:sub(1, 6)
    if prefix ~= "SPELL_" and prefix ~= "RANGE_" then return nil end
    if type(spellId) ~= "number" then return nil end
    if type(mask) ~= "number" or mask <= 0 then return nil end
    schools[spellId] = mask
    return spellId, mask
end

SuuUI.Game = M
