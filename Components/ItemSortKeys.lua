-- The CATEGORY ordering rule: quality, then what kind of thing an item is, then how good it is.
--
-- `Components/ItemGrid.lua` ships three orderings whose whole key chain fits on one line each
-- (quality-then-name, name, container-then-slot). This is the fourth and it does not: it is seven
-- keys deep, needs five fields the container API does not report, and carries two data tables. So it
-- lives here and the grid registers it, rather than growing a 120-line comparator inside a file
-- already at the size guideline.
--
-- WHY THE NAME IS NOT THE ADDON IT CAME FROM. The rule is modelled on ElvUI's bag sorter -- branch
-- for branch, including two decisions below that look like bugs until you know they are deliberate --
-- but naming it after the addon would tell a future reader nothing about what it produces and would
-- go stale the moment either side changed. `quality_type` says what it orders by. The provenance is a
-- comment, which is where provenance belongs.
--
-- WHAT IT PRODUCES, in order. First difference found wins:
--
--   1. same item id      -> smaller stack first (see STACK ORDER below)
--   2. quality           -> DESCENDING; conjured items demoted below poor (see CONJURED below)
--   3. item class        -> ascending, the client's own numeric class id
--   4. equip slot        -> ascending, gear only, paper-doll order (head before feet)
--   5. item subclass     -> ascending, everything that is not gear
--   6. item level        -> DESCENDING
--   7. sell price        -> DESCENDING
--   8. name              -> ascending
--   9. container + slot  -> the total-order backstop
--
-- QUALITY IS THE PRIMARY KEY, not the category. That is the counter-intuitive half and it is worth
-- stating plainly: a rare trade good sorts above an uncommon weapon. Category only groups WITHIN a
-- quality band. A player who wants all weapons together regardless of quality wants a different mode,
-- which is why the label says "Quality + Type" rather than "Type".
local ipairs, pairs, pcall, type = ipairs, pairs, pcall, type

local M = {}

-- The paper-doll order, so gear inside one quality band reads head-to-toe rather than alphabetically.
-- An INVTYPE this table does not name resolves to -1 and therefore leads its class, which is the
-- right answer for the odd ones (a bag is class Container and never reaches here at all).
M.EQUIP_ORDER = {
    INVTYPE_AMMO = 0, INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
    INVTYPE_BODY = 4, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10,
    INVTYPE_FINGER = 11, INVTYPE_TRINKET = 12, INVTYPE_CLOAK = 13, INVTYPE_WEAPON = 14,
    INVTYPE_SHIELD = 15, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 18,
    INVTYPE_WEAPONOFFHAND = 19, INVTYPE_HOLDABLE = 20, INVTYPE_RANGED = 21,
    INVTYPE_THROWN = 22, INVTYPE_RANGEDRIGHT = 23, INVTYPE_RELIC = 24, INVTYPE_TABARD = 25,
}

-- Read from the client rather than hardcoded, for the reason every other enum in this addon is: a
-- backport that renumbered one would silently reorder the whole grid. The literals are the fallback
-- for a client generation with no `Enum.ItemClass`, and they are the values measured on this one.
local function classId(name, fallback)
    local E = Enum
    local v = E and E.ItemClass and E.ItemClass[name]
    if type(v) == "number" then return v end
    return fallback
end

M.CLASS_ARMOR  = classId("Armor", 4)
M.CLASS_WEAPON = classId("Weapon", 2)

-- An item whose class we cannot learn yet. High rather than low so it lands at the END of its quality
-- band, which is the SHORTEST possible jump when the client finally answers -- the item is already
-- beside the others of its quality, so resolving moves it a few cells rather than across the grid.
M.CLASS_UNKNOWN = 99

-- CONJURED items rank BELOW poor, so a mage's water and a warlock's stones fall past the greys
-- instead of sitting in the middle of the bag at common quality. There is no API for this -- the
-- client exposes no "is conjured" flag and the tooltip line is not readable as data -- so the ids are
-- enumerated, which makes this the one table here that is opinion rather than a client fact, and the
-- one that needs a line adding when a new conjured item appears.
--
-- -99 rather than -1 so it also sits below an item whose quality is not known yet (which reads -1),
-- because "this is deliberately demoted" and "we have not learned this yet" must not collide.
M.CONJURED_RANK = -99

M.CONJURED = {}
for _, id in ipairs({
    -- Mage water
    5350, 2288, 2136, 3772, 8077, 8078, 8079, 30703, 22018,
    -- Mage food
    5349, 1113, 1114, 1487, 8075, 8076, 22895, 22019,
    -- Mage mana gems
    5514, 5513, 8007, 8008, 22044,
    -- Warlock soulstones
    5232, 16892, 16893, 16895, 16896, 22116,
    -- Warlock firestones
    1254, 13699, 13700, 13701, 22128,
    -- Warlock spellstones
    5522, 13602, 13603, 22646,
    -- Warlock healthstones, including both Improved Healthstone ranks of each
    5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009,
    5510, 19010, 19011, 9421, 19012, 19013, 22103, 22104, 22105,
}) do M.CONJURED[id] = true end

--- Whether an item is demoted below poor quality.
-- @param id number|nil
-- @return bool
function M.IsConjured(id)
    return id ~= nil and M.CONJURED[id] == true
end

-- MEMOISED, and that is not a micro-optimisation. `table.sort` calls a comparator O(n log n) times,
-- so an 80-slot grid is roughly 500 comparisons and 1000 metadata reads for one sort -- and the grid
-- sorts on every window open and again on every batch of resolved items. ElvUI calls GetItemInfo
-- straight from its comparator and pays that; a table lookup costs nothing and the answer cannot go
-- stale, since an item's class, slot, level and price are fixed properties of the item id.
--
-- ONLY SUCCESSES ARE MEMOISED. Caching a miss would pin an item at CLASS_UNKNOWN for the rest of the
-- session, so the one thing this table must never do is remember that we once did not know.
local memo = {}

--- The five ordering fields for an item id.
--
-- Live client first, then the account cache. The cache matters for a SNAPSHOT of another character:
-- the client has no reason to have cached an item only an alt owns, so without it every item in an
-- alt's bags would order at CLASS_UNKNOWN. The live read is still tried first because it is the
-- fresher of the two and needs no capture to have happened.
-- @param id number|nil
-- @return number|nil classId, number|nil subclassId, string|nil equipLoc, number|nil itemLevel, number|nil sellPrice
function M.Meta(id)
    if id == nil then return nil end
    local hit = memo[id]
    if hit then return hit[1], hit[2], hit[3], hit[4], hit[5] end

    if type(GetItemInfo) == "function" then
        -- pcall'd because this can run from a ticker and from an event handler, and an id the client
        -- dislikes must not unwind into a sort that is halfway through reordering the grid.
        local ok, _, _, _, ilvl, _, _, _, _, equip, _, price, cls, sub = pcall(GetItemInfo, id)
        if ok and type(cls) == "number" then
            memo[id] = { cls, sub, equip, ilvl, price }
            return cls, sub, equip, ilvl, price
        end
    end

    local IC = SuuUI.ItemCache
    local e = IC and type(IC.ItemInfo) == "function" and IC:ItemInfo(id) or nil
    if e and type(e.cls) == "number" then
        memo[id] = { e.cls, e.sub, e.eq, e.ilvl, e.price }
        return e.cls, e.sub, e.eq, e.ilvl, e.price
    end

    return nil
end

--- Drops the metadata memo. For the suite, which rebuilds the client between tests.
function M.ResetMemo()
    for k in pairs(memo) do memo[k] = nil end
end

local function byPosition(a, b)
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

-- Keys 6 to 9. Item level and price DESCEND because both answer "which of these two is the better
-- one", and the better one leading is what makes a row of six similar items readable at a glance.
--
-- Read from the ITEM ID, not the link, which is a real limitation worth knowing: two random-suffix
-- items ("of the Bear", "of the Eagle") share an id and therefore report one item level, so they
-- fall through to price and then to name rather than ordering by their actual stats. Reading the link
-- would fix that and would also mean a per-instance lookup that cannot be memoised.
local function byGrade(a, b)
    local _, _, _, la, pa = M.Meta(a.info and a.info.itemID)
    local _, _, _, lb, pb = M.Meta(b.info and b.info.itemID)
    if la ~= lb and la and lb then return la > lb end
    if pa ~= pb and pa and pb then return pa > pb end
    local na = (a.info and a.info.itemName) or ""
    local nb = (b.info and b.info.itemName) or ""
    if na ~= nb then return na < nb end
    -- The BACKSTOP, and it is not decoration. Without it two items alike on every key above compare
    -- equal, and `table.sort` is not stable in Lua -- so the pair would swap places between logins
    -- for no reason the player could see. Every ordering in ItemGrid ends here for the same reason.
    return byPosition(a, b)
end

--- Orders two grid entries.
--
-- Takes ItemGrid's own entry shape (`{ bag, slot, info }`) rather than two item ids, because keys 1
-- and 9 need the stack count and the slot. Wrap it in the grid's `occupiedFirst` -- an empty slot has
-- no id and no quality, so it is not this function's business to decide where nothing goes.
-- @param a table
-- @param b table
-- @return bool  whether a orders before b
function M.Compare(a, b)
    local ia, ib = a.info, b.info
    local ida = ia and ia.itemID
    local idb = ib and ib.itemID

    -- STACK ORDER: the same item, so every key below would tie. The SMALLER stack leads, which is
    -- ElvUI's rule and looks like a bug until you notice why it almost never shows there: ElvUI
    -- merges partial stacks immediately before sorting, so at most one partial survives and it ends
    -- up adjacent to the full ones. SuuUI moves nothing, so this branch fires constantly instead --
    -- three piles of cloth at 7/12/20 render in that order rather than being consolidated. That is
    -- the one place where ordering without moving items visibly differs, and it is kept faithful on
    -- purpose so the two produce the same sequence from the same bag contents.
    if ida ~= nil and ida == idb then
        local ca = (ia.stackCount or 1)
        local cb = (ib.stackCount or 1)
        if ca ~= cb then return ca < cb end
        return byPosition(a, b)
    end

    local qa = M.IsConjured(ida) and M.CONJURED_RANK or (ia and ia.quality or -1)
    local qb = M.IsConjured(idb) and M.CONJURED_RANK or (ib and ib.quality or -1)
    if qa ~= qb then return qa > qb end

    local ca, sa, ea = M.Meta(ida)
    local cb, sb, eb = M.Meta(idb)
    ca = ca or M.CLASS_UNKNOWN
    cb = cb or M.CLASS_UNKNOWN
    if ca ~= cb then return ca < cb end

    -- GEAR SKIPS SUBCLASS ENTIRELY, which has a consequence worth knowing: a one-hand sword and a
    -- dagger are both INVTYPE_WEAPON, so they interleave and order by item level rather than
    -- clustering by weapon type. Where you WEAR a thing is the more useful grouping for gear -- all
    -- the helms together beats all the maces together -- and both classes are checked because armour
    -- carries shields, held-in-off-hands and relics.
    if ca == M.CLASS_ARMOR or ca == M.CLASS_WEAPON then
        local oa = M.EQUIP_ORDER[ea or ""] or -1
        local ob = M.EQUIP_ORDER[eb or ""] or -1
        if oa ~= ob then return oa < ob end
        return byGrade(a, b)
    end

    sa = sa or M.CLASS_UNKNOWN
    sb = sb or M.CLASS_UNKNOWN
    if sa ~= sb then return sa < sb end

    return byGrade(a, b)
end

SuuUI.ItemSortKeys = M
