-- Facts about the game, not choices about the look.
--
-- A class colour, a reaction colour, a power type's colour and a spell school's colour are
-- not design language: they are what the client says those things ARE. "Frost is cyan",
-- "mages are light blue" and "a mob that wants you dead is red" are as fixed as each
-- other, so the theme has nothing to offer here and the theme editor would only present
-- controls that are wrong to touch. They live in Core
-- rather than in whichever plugin paints them first, because a resource bar, a cast bar, a
-- nameplate and a debuff border all describe the same facts — and two copies of a fact
-- drift.
--
-- Note the split this draws with the theme: whether a health bar is class-coloured at all
-- is a look decision and lives in the theme as colorUseClassColors; WHICH colour a mage
-- gets, and what colour a unit with no class falls back to, are facts and live here.
-- Theme:GetUnitColor is the one place the two meet.
--
-- The spell-school cache lives here for the same reason, and exists at all because this
-- client has no API mapping a spell to its school: neither GetSpellInfo nor UnitCastingInfo
-- reports one, so the combat log is the only source. Whoever is already reading the log
-- calls LearnFromCombatLog; everything else reads back out of SchoolOf.
local type, ipairs = type, ipairs
local floor = math.floor
local format = string.format

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

--- The colour for a unit's class, or nil when the unit has no class to be coloured by.
--
-- Only a PLAYER has one, and asking UnitClass is not how you find that out. A creature
-- carries a class field of its own and the client answers UnitClass for it — almost always
-- "WARRIOR", since that is what the overwhelming majority of creatures are internally — so
-- trusting UnitClass alone paints every mob, critter and quest giver in warrior tan and
-- never reaches the reaction fallback that exists for exactly those units. That shipped: a
-- neutral Vale Moth rendered brown instead of yellow.
--
-- UnitIsPlayer is the question that actually separates a mage from a moth, which is why nil
-- is a real answer here rather than a failure.
--
-- UnitClass returns the localised name first and the class file second; only the second
-- is a stable key, so the first is deliberately discarded.
-- @param unit string  Unit id, e.g. "player"
-- @return table|nil  {r,g,b,a}
function M:UnitClassColor(unit)
    if type(unit) ~= "string" or type(UnitClass) ~= "function" then return nil end
    -- Guarded rather than assumed: a client with no UnitIsPlayer cannot answer the
    -- question, and losing class colouring for every player is worse than the tan mob.
    if type(UnitIsPlayer) == "function" and not UnitIsPlayer(unit) then return nil end
    local _, classFile = UnitClass(unit)
    return self:ClassColor(classFile)
end

---------------------------------------------------------------------------
-- Reactions
---------------------------------------------------------------------------

-- What a unit is TO YOU, for the units that have no class to be coloured by: a mob, a
-- critter, a quest giver, a totem. The client already answers this question everywhere
-- else in its UI — a nameplate, a tooltip's name, the default target frame — so these are
-- its values rather than chosen ones, for the same reason the class and school colours
-- above are.
--
-- Three bands, not eight. UnitReaction reports a full reputation standing (1 hated to 8
-- exalted), but a health bar is answering "can this thing hurt me" and the client's own
-- colour table collapses the standings into exactly these three answers. Keeping eight
-- would give the player five shades that all mean "friendly".
--
-- The rows are the FACTION_BAR_COLORS indices that carry each band, which is what makes
-- the live global below a drop-in source rather than a coincidence.
M.REACTION = {
    HOSTILE  = 2,
    NEUTRAL  = 4,
    FRIENDLY = 5,
}

-- The fallback copy, for the login moment before FACTION_BAR_COLORS exists. Same role as
-- the CLASS table above: the client's global is preferred whenever it is there, so SuuUI
-- agrees with the rest of the player's UI including anything that retints it.
local REACTION_COLORS = {
    [1] = {0.80, 0.30, 0.22, 1},  -- Hated
    [2] = {0.80, 0.30, 0.22, 1},  -- Hostile
    [3] = {0.75, 0.27, 0.00, 1},  -- Unfriendly
    [4] = {0.90, 0.70, 0.00, 1},  -- Neutral
    [5] = {0.00, 0.60, 0.10, 1},  -- Friendly
    [6] = {0.00, 0.60, 0.10, 1},  -- Honored
    [7] = {0.00, 0.60, 0.10, 1},  -- Revered
    [8] = {0.00, 0.60, 0.10, 1},  -- Exalted
}

-- Collapses a standing onto one of the three bands. Hostile takes everything at or below
-- unfriendly because that is the set that will fight you; friendly takes everything from
-- friendly up, since the reputation tiers above it change nothing about what the unit is.
local function reactionRow(reaction)
    if reaction <= 3 then return M.REACTION.HOSTILE end
    if reaction == 4 then return M.REACTION.NEUTRAL end
    return M.REACTION.FRIENDLY
end

-- Converted client colours, keyed by band row. Cached and validated against the source for
-- the same reason the class cache is: this is read on every health repaint, and a table
-- allocated per repaint for a value that never moves is waste.
local reactionCache = {}

--- The colour for a reaction standing, or nil when the standing is not one.
--
-- nil is a real answer, exactly as with ClassColor and SchoolColor: a unit that does not
-- exist has no reaction, and the caller's own fallback is the right response.
-- @param reaction number  UnitReaction's 1..8 standing, or a M.REACTION row
-- @return table|nil  {r,g,b,a}
function M:ReactionColor(reaction)
    if type(reaction) ~= "number" or reaction < 1 or reaction > 8 then return nil end
    local row = reactionRow(reaction)
    local src = type(FACTION_BAR_COLORS) == "table" and FACTION_BAR_COLORS[row] or nil
    if type(src) == "table" and type(src.r) == "number" then
        local hit = reactionCache[row]
        if hit and hit[1] == src.r and hit[2] == src.g and hit[3] == src.b then return hit end
        hit = { src.r, src.g, src.b, 1 }
        reactionCache[row] = hit
        return hit
    end
    return REACTION_COLORS[row]
end

--- The colour for how a unit stands towards the player, or nil when that is unknown.
--
-- The unit is the FIRST argument deliberately: UnitReaction reports the first unit's
-- reaction towards the second, and it is not symmetric in the general case. The question a
-- unit frame paints is "what is this thing to me", so the unit asks and the player is asked
-- about — the other way round reads the player's own standing and is nil for every unit.
-- @param unit string  Unit id, e.g. "target"
-- @return table|nil  {r,g,b,a}
function M:UnitReactionColor(unit)
    if type(unit) ~= "string" or type(UnitReaction) ~= "function" then return nil end
    return self:ReactionColor(UnitReaction(unit, "player"))
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

---------------------------------------------------------------------------
-- Debuff types (dispel categories)
---------------------------------------------------------------------------

-- What kind of debuff this is — Magic, Curse, Disease, Poison — for the coloured border on
-- an aura icon that tells the player whether they can dispel it. These are the client's own
-- values for the same reason the school and class colours above are: a player reading a
-- debuff border expects the same colour they see on their default raid frames and on every
-- other addon that shows debuffs.
--
-- This is a game fact, not a theme token: changing these would lie about what a debuff IS,
-- which is the same reason class and school colours are here rather than in Theme. A theme
-- cannot decide that "Curse" is blue.
--
-- Preference order matches ClassColor / ReactionColor:
--   1. DebuffTypeColor global (the client ships it; an addon may retint it)
--   2. The internal copy below, for the login moment before the global exists

local DEBUFF_TYPES = {
    Magic   = {0.20, 0.60, 1.00, 1},
    Curse   = {0.60, 0.00, 1.00, 1},
    Disease = {0.60, 0.40, 0.00, 1},
    Poison  = {0.00, 0.60, 0.00, 1},
}

-- What an UNTYPED debuff is worth showing as. The client ships this in the same table as
-- the four dispel types, under "none", and its own debuff displays use it -- so red for
-- "nothing removes this" is a convention the player already reads, not a colour we chose.
--
-- It is a separate accessor rather than a fifth row in DebuffTypeColor because the two
-- questions are different: "what dispel type is this" must answer nil for an aura that has
-- none, so a caller can fall back to whatever its own surface calls for. Only a debuff
-- display wants red; a buff with no type must not go red, and neither must a cast bar.
---------------------------------------------------------------------------
-- Item quality
---------------------------------------------------------------------------

-- What an item's quality is worth showing as. A fact about the client, not a design
-- choice: "epics are purple" is as fixed as "frost is cyan", and a theme that could
-- retint it would make a quality border lie about the game.
--
-- Preference order matches ClassColor / ReactionColor / DebuffTypeColor:
--   1. ITEM_QUALITY_COLORS global (the client ships it; an addon may retint it)
--   2. The internal copy below, for the login moment before the global exists
--
-- NOTE the client's rows also carry a `.hex` field, which is a |cff… COLOUR ESCAPE and
-- not a colour. Reading it by mistake yields a string that silently swallows the rest of
-- whatever it is concatenated into -- which is exactly what happened to the Phase 0 probe
-- that tried to print one. Only r/g/b are read here.
local ITEM_QUALITY = {
    [0] = {0.62, 0.62, 0.62, 1},   -- Poor
    [1] = {1.00, 1.00, 1.00, 1},   -- Common
    [2] = {0.12, 1.00, 0.00, 1},   -- Uncommon
    [3] = {0.00, 0.44, 0.87, 1},   -- Rare
    [4] = {0.64, 0.21, 0.93, 1},   -- Epic
    [5] = {1.00, 0.50, 0.00, 1},   -- Legendary
    [6] = {0.90, 0.80, 0.50, 1},   -- Artifact
    [7] = {0.00, 0.80, 1.00, 1},   -- Heirloom
}

local qualityCache = {}

--- The colour for an item quality, or nil for a quality this client does not name.
--
-- Answers for EVERY known quality including Poor and Common. It deliberately does NOT
-- fold in "only colour uncommon and above" -- that rule belongs to whichever surface is
-- drawing, because it is a look decision rather than a fact. A tooltip border wants it
-- (a white 1px edge reads as a selected state, and it would fire on the majority of
-- tooltips a player sees); an item NAME in a bag grid does not, since white is exactly
-- what a common item's name should be. Putting the threshold here would deny the second
-- caller a colour that genuinely exists.
--
-- nil is a real answer, as with SchoolColor and ClassColor: an unknown quality has no
-- identity to paint and the caller's own default is the right response.
-- @param quality number  The client's quality index, 0..7
-- @return table|nil  {r,g,b,a}
function M:ItemQualityColor(quality)
    if type(quality) ~= "number" or quality ~= quality then return nil end
    local src = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[quality] or nil
    if type(src) == "table" and type(src.r) == "number" then
        local hit = qualityCache[quality]
        if hit and hit[1] == src.r and hit[2] == src.g and hit[3] == src.b then return hit end
        hit = { src.r, src.g, src.b, 1 }
        qualityCache[quality] = hit
        return hit
    end
    return ITEM_QUALITY[quality]
end

---------------------------------------------------------------------------
-- Creature difficulty
---------------------------------------------------------------------------

-- How dangerous a level is RELATIVE TO THE PLAYER: grey, green, yellow, orange, red. A fact
-- about the client for the same reason class and school colours are -- the player already reads
-- these five in their quest log and on every mob they hover, so they are copied rather than
-- chosen. A theme that could retint "red" would make the tooltip lie about the danger.
--
-- Unlike the other tables here this one is a FUNCTION of two levels, not a lookup, so the
-- client's own GetCreatureDifficultyColor is preferred and the formula below is the fallback.
-- COIN COLOURS. Facts for the same reason quality colours are: gold is yellow, silver is grey and
-- copper is bronze in every gold addon, auction house and vendor frame the player has ever used, so
-- a theme that could decide copper is blue would make the UI lie about the game. That is why these
-- are here rather than as tokens -- the argument is identical to ItemQualityColor's.
--
-- The client exposes no coin COLOUR global (only GetCoinTextureString, which returns embedded coin
-- ICONS rather than coloured text), so unlike RAID_CLASS_COLORS there is nothing live to prefer.
-- The values are ElvUI's, read off this install rather than recalled: Game/Shared/General/Math.lua
-- carries `'|cffeda55f', '|cffc7c7cf', '|cffffd700'` for copper/silver/gold, and Gargul
-- independently agrees on FFD700 for gold. Same method as the stance and pet return orders.
-- Stated to four decimals rather than two, and that is not fussiness: at two decimals 0.84 * 255 is
-- 214.2, which rounds to d6 and prints ffd600 -- a value ElvUI never had. Copying a source hex and
-- then quietly emitting a different one discards the only reason to copy it, so each channel is the
-- exact eighth-bit fraction and the escape round-trips to the value in the comment.
local COIN = {
    GOLD   = {1.0000, 0.8431, 0.0000, 1},   -- ffd700
    SILVER = {0.7804, 0.7804, 0.8118, 1},   -- c7c7cf
    COPPER = {0.9294, 0.6471, 0.3725, 1},   -- eda55f
}
M.COIN = COIN

local coinCodeCache = {}

--- The colour for a coin denomination.
-- @param kind string  "GOLD" | "SILVER" | "COPPER" (case-insensitive)
-- @return table|nil  {r,g,b,a}; nil for anything that is not a denomination
function M:CoinColor(kind)
    if type(kind) ~= "string" then return nil end
    return COIN[kind:upper()]
end

--- A coin denomination as a |cffRRGGBB escape, for composing into a money string.
--
-- The escape rather than the table is what a caller actually needs here, because money is spelled as
-- ONE font string -- three denominations cannot be three separately-coloured Text handles without
-- putting three baselines on one line, which is the mistake DataField documents at length. Cached
-- per denomination because this is called from a footer refresh.
-- @param kind string  "GOLD" | "SILVER" | "COPPER"
-- @return string|nil
function M:CoinColorCode(kind)
    if type(kind) ~= "string" then return nil end
    local key = kind:upper()
    local cached = coinCodeCache[key]
    if cached then return cached end
    local c = COIN[key]
    if not c then return nil end
    -- Rounded to integers explicitly. "%02x" on 214.2 raises "number has no integer representation"
    -- under the test runner's Lua 5.3 while the client's 5.1 would truncate silently -- the same
    -- version split this file already handles by doing its bit tests arithmetically. Rounding rather
    -- than truncating, so 0.84 lands on d7 as the source hex intends rather than d6.
    local code = format("|cff%02x%02x%02x",
        floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
    coinCodeCache[key] = code
    return code
end

local DIFFICULTY = {    trivial = {0.50, 0.50, 0.50, 1},   -- grey:   no experience left in it
    easy    = {0.25, 0.75, 0.25, 1},   -- green
    fair    = {1.00, 1.00, 0.00, 1},   -- yellow: within two levels either way
    hard    = {1.00, 0.50, 0.25, 1},   -- orange
    deadly  = {1.00, 0.10, 0.10, 1},   -- red
}

M.DIFFICULTY = DIFFICULTY

--- The colour for a creature's level, from the player's point of view.
--
-- Prefers the client's own GetCreatureDifficultyColor so SuuUI agrees with the rest of the UI,
-- including the quest log. The fallback reproduces the classic bands: red more than 4 above,
-- orange more than 2 above, yellow within 2, then green down to the grey threshold.
--
-- The GREY threshold is not a fixed offset -- it widens as the player levels, which is what
-- GetQuestGreenRange reports. Hardcoding a single number makes low-level mobs read as green for
-- a level 70 player long after they have stopped giving experience.
--
-- A level of -1 or 0 is the client's "cannot tell" (a boss, or a unit too far above you). It
-- takes `deadly` rather than nil, because "unknown" here genuinely means "dangerous" -- which is
-- also what the client's own ?? does.
-- @param level number  The creature's level
-- @param playerLevel number|nil  Defaults to the player's own
-- @return table  {r,g,b,a}; never nil
function M:DifficultyColor(level, playerLevel)
    if type(level) ~= "number" then return DIFFICULTY.fair end
    if level <= 0 then return DIFFICULTY.deadly end

    -- The client's own answer, but ONLY when no explicit player level was asked about: its
    -- function can only ever answer about the ACTUAL player, so consulting it for a hypothetical
    -- would ignore the argument and return the wrong band. A spec caught exactly that -- the
    -- parameter was silently dead in game, where the client function always exists.
    if playerLevel == nil and type(GetCreatureDifficultyColor) == "function" then
        local ok, c = pcall(GetCreatureDifficultyColor, level)
        if ok and type(c) == "table" and type(c.r) == "number" then
            return { c.r, c.g, c.b, 1 }
        end
    end

    local mine = playerLevel
    if type(mine) ~= "number" and type(UnitLevel) == "function" then
        mine = UnitLevel("player")
    end
    if type(mine) ~= "number" or mine <= 0 then return DIFFICULTY.fair end

    local diff = level - mine
    if diff > 4 then return DIFFICULTY.deadly end
    if diff > 2 then return DIFFICULTY.hard end
    if diff >= -2 then return DIFFICULTY.fair end

    local green = 5
    if type(GetQuestGreenRange) == "function" then
        local ok, g = pcall(GetQuestGreenRange)
        if ok and type(g) == "number" then green = g end
    end
    if level > mine - green then return DIFFICULTY.easy end
    return DIFFICULTY.trivial
end

local DEBUFF_NONE = {0.80, 0.00, 0.00, 1}
local noneCache

-- Cached converted arrays, validated against the live source on each read.
local debuffTypeCache = {}

--- The border colour for a debuff's dispel type, or nil when the type is nil, "none" or
--- anything this client does not name.
--
-- nil is a real answer, exactly as with SchoolColor and ClassColor: a debuff with no type
-- or with type "none" has no dispel identity and the caller falls back to its own default
-- border — inventing a colour for "unknown" would give the player a cue that means nothing.
-- @param dispelType string|nil  e.g. "Magic", "Curse", "Disease", "Poison"
-- @return table|nil  {r,g,b,a}
function M:DebuffTypeColor(dispelType)
    if type(dispelType) ~= "string" or dispelType == "" or dispelType == "none" then
        return nil
    end
    -- Prefer the client's live global so SuuUI agrees with the rest of the player's UI
    -- including an addon that retints debuff borders. Same pattern as ClassColor and
    -- ReactionColor.
    local src = type(DebuffTypeColor) == "table" and DebuffTypeColor[dispelType] or nil
    if type(src) == "table" and type(src.r) == "number" then
        local hit = debuffTypeCache[dispelType]
        if hit and hit[1] == src.r and hit[2] == src.g and hit[3] == src.b then return hit end
        hit = { src.r, src.g, src.b, 1 }
        debuffTypeCache[dispelType] = hit
        return hit
    end
    return DEBUFF_TYPES[dispelType]
end

--- The border colour for a debuff the client reports no dispel type for.
--
-- Prefers the live global's "none" row for the same reason every other fact here does: an
-- addon that retints debuff borders should retint ours too. Unlike DebuffTypeColor this
-- never returns nil -- a debuff display always has something to paint, and "no type" is a
-- real answer worth showing rather than an absence to fall back from.
-- @return table  {r,g,b,a}
function M:UntypedDebuffColor()
    local src = type(DebuffTypeColor) == "table" and DebuffTypeColor["none"] or nil
    if type(src) == "table" and type(src.r) == "number" then
        if noneCache and noneCache[1] == src.r and noneCache[2] == src.g
           and noneCache[3] == src.b then
            return noneCache
        end
        noneCache = { src.r, src.g, src.b, 1 }
        return noneCache
    end
    return DEBUFF_NONE
end

SuuUI.Game = M
