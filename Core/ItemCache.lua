-- Account-wide item cache: which character holds what, how many, and whether it is in bags
-- or in the bank.
--
-- WHY THIS IS IN CORE rather than in the inventory plugin. Two plugins consume it -- the
-- inventory window and the tooltip's "across your account" section -- and a plugin may never
-- call into another plugin. It is the same argument that put DataBar and Dock here: the answer
-- has to exist whether or not the window that writes it is loaded, enabled, or came up first.
-- Disabling the inventory plugin must not silently stop the tooltip lines updating.
--
-- TWO TABLES, not one. Roughly 250 slots per character across bags, bank and bank bags, and a
-- 60-byte link per slot per character is ~25 KB each before you count alts. So the shared
-- `items` table carries everything about an ITEM keyed by id, and a character's slots are just
-- {itemID, count} pairs. Ten alts land in tens of KB, and the item table is shared by the
-- tooltip, the search index and the ledger for free.
local ipairs, pairs, type, time = ipairs, pairs, type, time
local tsort, tinsert = table.sort, table.insert

local M = {}

-- Bumped when the stored shape changes, so a renamed key from an older save can be migrated on
-- read rather than silently misread. Same reasoning as Theme's _tokenVersion.
local VERSION = 1

-- How long to coalesce a burst of BAG_UPDATE into one capture. Looting a stack fires several in
-- a few frames, and each one would otherwise walk every slot the character owns.
local DEBOUNCE = 0.35

local frame
local bankOpen = false
-- Memoised Find results, keyed by item id. Cleared whenever HOLDINGS change -- a capture or a
-- Forget -- and never persisted: it is derived from the store, so rebuilding it costs one walk.
local findMemo = {}

--------------------------------------------------------------------------------
-- The client's container API
--------------------------------------------------------------------------------

-- MEASURED on this client 2026-08-24: `C_Container` is a table and every bare container global
-- is nil, so the namespaced form is the real path here. The bare form is still resolved because
-- a client generation carrying only that shape is a real possibility and the cost is a branch --
-- but an ABSENT api is a visible Fault rather than a silently empty cache, because "the API is
-- gone" and "this character owns nothing" render identically and only one of them is normal.
--
-- Globals are read BARE, never through _G: a chunk resolves bare names through its own
-- environment, which is the table the test harness controls.
local function numSlots(bag)
    local C = C_Container
    if C and type(C.GetContainerNumSlots) == "function" then return C.GetContainerNumSlots(bag) end
    if type(GetContainerNumSlots) == "function" then return GetContainerNumSlots(bag) end
    return nil
end

--- Reads one container slot, normalised to the modern TABLE shape whichever API answers.
--
-- The legacy positional order is taken from the shims three installed addons ship on this
-- client (RXPGuides, Gargul, Questie), not from memory.
-- @return table|nil  nil for an empty slot, which is a real answer
local function readSlot(bag, slot)
    local C = C_Container
    if C and type(C.GetContainerItemInfo) == "function" then
        return C.GetContainerItemInfo(bag, slot)
    end
    local get = GetContainerItemInfo
    if type(get) ~= "function" then return nil end
    local icon, count, locked, quality, readable, lootable, link, filtered, noValue, id, bound =
        get(bag, slot)
    if not id and not link then return nil end
    return {
        iconFileID = icon, stackCount = count, isLocked = locked, quality = quality,
        isReadable = readable, hasLoot = lootable, hyperlink = link, isFiltered = filtered,
        hasNoValue = noValue, itemID = id, isBound = bound,
    }
end

local function haveApi()
    local C = C_Container
    if C and type(C.GetContainerItemInfo) == "function" then return true end
    return type(GetContainerItemInfo) == "function"
end

--------------------------------------------------------------------------------
-- Container lists
--------------------------------------------------------------------------------

-- Read from the client rather than hardcoded: measured 4 / 7 on this build, but a backport that
-- adds a bag slot would silently drop a whole container from every capture.
local function bagIds()
    local n = NUM_BAG_SLOTS or 4
    local out = {}
    for i = 0, n do out[#out + 1] = i end
    return out
end

local function bankIds()
    local first = (NUM_BAG_SLOTS or 4) + 1
    local n = NUM_BANKBAGSLOTS or 7
    local out = { -1 }
    for i = first, first + n - 1 do out[#out + 1] = i end
    return out
end

--------------------------------------------------------------------------------
-- Store
--------------------------------------------------------------------------------

local function store()
    return SuuUIItemCache
end

--- Records everything known about one ITEM, keyed by id.
--
-- ONLY EVER FILLS IN, never erases. A live read can be thin -- GetContainerItemInfo answers
-- before the client has resolved a name it has never seen -- and overwriting a richer entry
-- captured earlier would blank a name that was already working.
--- The display name carried inside an item link, or nil.
--
-- THE CONTAINER API DOES NOT RETURN A NAME. GetContainerItemInfo answers icon, count, quality, link
-- and id -- and no name at all -- so a capture had nothing to store, and a cached character could not
-- be SEARCHED: the filter matched zero items whatever you typed, while your own live bags searched
-- fine because a live cell reads the client. Measured with a real capture: icon, quality and link all
-- present, `name` nil, `CountMatches()` 0.
--
-- The name is in the link, between the brackets, so it needs no GetItemInfo call and no event -- which
-- also means it is available for an item the client has never cached, exactly the case that would
-- otherwise have to wait for GET_ITEM_INFO_RECEIVED.
--
-- Matched non-greedily on the bracketed span rather than parsed as a whole link, because the link is
-- wrapped in a colour escape (`|cffffffff…|r`) whose contents are not ours to depend on.
-- @param link string|nil
-- @return string|nil
function M.NameFromLink(link)
    if type(link) ~= "string" then return nil end
    local name = link:match("%[(.-)%]")
    if name == nil or name == "" then return nil end
    return name
end

-- THE FIVE ORDERING FIELDS, on their own top-up path rather than inside the record upsert below.
--
-- The container API reports none of them -- it gives icon, count, quality, link and id and stops --
-- so they are fetched here. They are what the `quality_type` ordering compares, and storing them is
-- what lets a SNAPSHOT of another character order the same way: the client has no reason to have
-- cached an item only an alt owns.
--
-- SEPARATE from `upsertItem` because they arrived later than the rest of the record, so an entry
-- written by an earlier version is complete by every other measure. Widening `Resolve`'s completeness
-- test to include them was tried and it broke the rule this file exists to keep -- it sent otherwise
-- complete entries back through the full upsert, where a thin resolve overwrote a good icon with
-- whatever that call happened to report. `59_itemcache_spec`'s "never blanks a field it already had"
-- is the assertion that caught it.
--
-- Guarded on `e.cls == nil` rather than on falsiness, because a class id of 0 (Consumable) and a sell
-- price of 0 (a quest item) are both real answers. So this runs ONCE PER ITEM ID EVER: a capture
-- reads ~250 slots, and a per-slot lookup would be 250 calls where this is one per new item.
-- @return bool  whether anything was learned
local function fillOrderKeys(e, id)
    if e.cls ~= nil or type(GetItemInfo) ~= "function" then return false end
    local ok, _, _, _, ilvl, _, _, _, _, equip, _, price, cls, sub = pcall(GetItemInfo, id)
    if not ok or type(cls) ~= "number" then return false end
    e.cls, e.sub, e.eq, e.ilvl, e.price = cls, sub, equip, ilvl, price
    return true
end

local function upsertItem(info)
    local id = info and info.itemID
    if not id then return end
    local items = store().items
    local e = items[id]
    if not e then e = {} items[id] = e end
    if info.hyperlink  then e.link = info.hyperlink end
    if info.iconFileID then e.icon = info.iconFileID end
    if info.quality    then e.q    = info.quality end
    if info.itemName   then e.name = info.itemName end
    fillOrderKeys(e, id)
    -- Derived from the link when nothing supplied one, which for a container read is ALWAYS --
    -- see NameFromLink. Filling in here rather than at the call site means every writer gets it,
    -- including the resolve path and any future one.
    if not e.name then e.name = M.NameFromLink(e.link or info.hyperlink) end
end

--- The key a character is stored under: "Name-Realm".
-- @return string
function M:CurrentKey()
    local name  = (UnitName and UnitName("player")) or "?"
    local realm = (GetRealmName and GetRealmName()) or "?"
    return name .. "-" .. realm
end

--- Initialises the store from SavedVariables and starts watching. Called by core on
--- ADDON_LOADED, because SavedVariables do not exist before then.
function M:Init()
    if type(SuuUIItemCache) ~= "table" then
        SuuUIItemCache = { _version = VERSION, items = {}, chars = {} }
    end
    local s = SuuUIItemCache
    s.items = type(s.items) == "table" and s.items or {}
    s.chars = type(s.chars) == "table" and s.chars or {}
    if s._version ~= VERSION then
        -- Nothing to migrate at v1. The branch exists so the next shape change has a home
        -- rather than being bolted on under pressure.
        s._version = VERSION
    end
    self:_watch()
end

--------------------------------------------------------------------------------
-- Capture
--------------------------------------------------------------------------------

--- Captures the current character's containers into the cache.
--
-- @param which string  "bags" | "bank"
-- @return boolean  whether anything was written
function M:Capture(which)
    if which ~= "bags" and which ~= "bank" then return false end
    if not store() then return false end
    if not haveApi() then
        SuuUI.Fault("ItemCache: no container API — neither C_Container.GetContainerItemInfo " ..
                    "nor GetContainerItemInfo exists, so no inventory can be recorded")
        return false
    end
    -- The bank is only READABLE while its frame is open: measured 2026-08-24, where a shut bank
    -- answers 28 slots with every slot nil and zero free. Capturing anyway would overwrite a
    -- good snapshot with an empty one, which is worse than not capturing at all.
    if which == "bank" and not bankOpen then return false end

    local ids   = (which == "bank") and bankIds() or bagIds()
    local slots = {}
    -- THE CAPACITY, PER BAG, and it has to be recorded because it cannot be recovered later. The slot
    -- table is sparse -- only occupied slots are stored -- so "how big is this container" is
    -- unanswerable from it: a bank holding three items in its first three slots is indistinguishable
    -- from a three-slot bank. Asking the client is worse than useless, since GetContainerNumSlots
    -- answers for whoever is logged in.
    --
    -- Without it a cached container could only ever show its USED slots, so an alt's bank rendered as a
    -- tight block of items with no free space visible and no honest total to report in the footer.
    local sizes = {}
    local totalSlots = 0
    for _, bag in ipairs(ids) do
        local n = numSlots(bag) or 0
        totalSlots = totalSlots + n
        if n > 0 then sizes[bag] = n end
        local perBag
        for slot = 1, n do
            local info = readSlot(bag, slot)
            if info and info.itemID then
                perBag = perBag or {}
                perBag[slot] = { info.itemID, info.stackCount or 1 }
                upsertItem(info)
            end
        end
        if perBag then slots[bag] = perBag end
    end

    -- AN UNREADABLE READ MUST NOT OVERWRITE A GOOD SNAPSHOT. This is the same rule the bank already
    -- had ("capturing anyway would overwrite a good snapshot with an empty one, which is worse than
    -- not capturing at all") -- it just was not applied to bags, and that cost real data: measured in
    -- game as a cached alt holding `money = 0` and ZERO slots, with the record present so the character
    -- still appeared in the dropdown. The window then correctly rendered nothing, because there was
    -- nothing there.
    --
    -- THE DISCRIMINATOR IS THE SLOT COUNT, NOT THE ITEM COUNT. A character can genuinely have empty
    -- bags, and refusing to record that would leave a stale snapshot forever. But every character has
    -- a backpack, so a TOTAL of zero slots across every container can only mean the container API is
    -- not answering yet -- which is the state at PLAYER_LOGOUT, and early in a login before the client
    -- has populated anything.
    if totalSlots == 0 then
        SuuUI.Debug("ItemCache: refusing to capture " .. which ..
                    " -- the containers report no slots at all, so the API is not readable yet")
        return false
    end

    local key   = self:CurrentKey()
    local chars = store().chars
    local rec   = chars[key]
    if not rec then rec = {} chars[key] = rec end
    rec.class = rec.class or (UnitClass and select(2, UnitClass("player"))) or nil
    if GetMoney then rec.money = GetMoney() end
    -- `seen` is per character AND per container, not one stamp per character. Bags refresh every
    -- time that character plays; the bank only when they visit one, so hour-old bags beside
    -- three-week-old bank data is the normal case and a single stamp would be a lie.
    rec[which] = { seen = time(), slots = slots, sizes = sizes }
    -- Holdings moved, so every memoised answer about who holds what is now suspect.
    findMemo = {}
    return true
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

--- One character's stored container record.
-- @return table|nil  { seen = number, slots = { [bag] = { [slot] = {itemID, count} } } }
function M:Get(key, which)
    local s = store()
    local rec = s and s.chars[key]
    return rec and rec[which] or nil
end

--- When that container was last read, as a unix time, or nil if never.
-- @return number|nil
function M:SeenAt(key, which)
    local rec = self:Get(key, which)
    return rec and rec.seen or nil
end

--- The money that character had when it was last captured, in copper, or nil.
--
-- Nil rather than 0 for a character captured before money was stored, because "no figure" and "no
-- gold" are different statements and a footer printing 0g under an alt's name states the second.
-- @param key string|nil
-- @return number|nil
function M:MoneyOf(key)
    local s = store()
    local rec = s and key and s.chars[key]
    return rec and rec.money or nil
end

--- Everything known about one item id, or nil.
-- @return table|nil  { link, icon, q, name }
--- Fills in an item's details once the client has finally resolved them.
--
-- GetItemInfo answers NIL for an item this client has never seen, and fires GET_ITEM_INFO_RECEIVED
-- later -- so a character captured on a fresh login stores ids and counts with no name, icon or
-- quality behind them, and a grid built from that cache renders unresolved cells. This is the other
-- half of that: the client tells us, we write it into the shared item table, and every view reading
-- the cache is correct from then on without recapturing anything.
--
-- ONLY FOR AN ID WE ALREADY HOLD. The event fires for every item the client resolves for any reason
-- -- a tooltip, a chat link, an auction search, someone else's inspect -- so acting on all of them
-- would grow the account-wide item table without bound and store thousands of items no character
-- owns. The `items[id]` check is what keeps this a fill-in rather than a harvester.
-- @param id number
-- @return bool  whether anything was learned
function M:Resolve(id)
    if type(id) ~= "number" then return false end
    local s = store()
    local e = s and s.items and s.items[id]
    if not e then return false end
    -- The ordering fields top up FIRST and on their own path, so an entry that is complete by every
    -- other measure still gains them -- while a complete entry still returns before the record upsert
    -- below, which is what stops a thin resolve overwriting a good icon.
    local learned = fillOrderKeys(e, id)
    if e.name and e.icon and e.q then return learned end
    if type(GetItemInfo) ~= "function" then return false end
    -- Positional, and only the four fields a cell paints from. A pcall because this runs from an
    -- event handler and an unresolvable id must not unwind into the client's dispatch.
    local ok, name, link, quality, _, _, _, _, _, _, texture = pcall(GetItemInfo, id)
    if not ok or not name then return false end
    upsertItem({ itemID = id, itemName = name, hyperlink = link,
                 quality = quality, iconFileID = texture })
    return true
end

--- The item table's entry for an id, or nil.
-- @param id number
-- @return table|nil
function M:ItemInfo(id)
    local s = store()
    return s and s.items[id] or nil
end

--- Every character in the cache, current character first, then the current realm, then others.
--
-- Ordered rather than a bare map because it drives a dropdown: "do I have this on my other
-- realm" is worth answering, but the character you are playing is the one you look for first.
-- @return table  { { key, name, realm, class, isCurrent } }
function M:Characters()
    local s = store()
    if not s then return {} end
    local cur      = self:CurrentKey()
    local curRealm = (GetRealmName and GetRealmName()) or "?"
    local out = {}
    for key, rec in pairs(s.chars) do
        local name, realm = key:match("^(.-)%-(.*)$")
        tinsert(out, {
            key = key, name = name or key, realm = realm or "?",
            class = rec.class, isCurrent = (key == cur),
        })
    end
    tsort(out, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        local aHere, bHere = (a.realm == curRealm), (b.realm == curRealm)
        if aHere ~= bHere then return aHere end
        if a.realm ~= b.realm then return a.realm < b.realm end
        return a.name < b.name
    end)
    return out
end

--- Where an item is held across the whole account.
--
-- @param id number  item id
-- @return table  { { key, container, count } }, ordered as Characters() is
function M:Find(id)
    local out = {}
    if not id then return out end
    -- MEMOISED, because this is now on a HOVER path rather than only a window path. Every walk is
    -- characters x containers x bags x slots -- around 2,500 iterations for ten alts -- and moving the
    -- cursor across an 80-cell grid fires 80 item tooltips, one per cell. The answer only changes when
    -- holdings change, so the memo is cleared by Capture and Forget and by nothing else; resolving an
    -- item's NAME cannot move it between characters.
    if findMemo[id] then
        local hit = findMemo[id]
        -- A COPY, for the reason Container:GetPadding returns one: the memo is what the next caller
        -- reads, so handing out the internal table lets one consumer's edit become another's answer.
        for i = 1, #hit do out[i] = hit[i] end
        return out
    end
    for _, c in ipairs(self:Characters()) do
        for _, which in ipairs({ "bags", "bank" }) do
            local rec = self:Get(c.key, which)
            local total = 0
            if rec and rec.slots then
                for _, perBag in pairs(rec.slots) do
                    for _, entry in pairs(perBag) do
                        if entry[1] == id then total = total + (entry[2] or 1) end
                    end
                end
            end
            if total > 0 then
                out[#out + 1] = { key = c.key, container = which, count = total }
            end
        end
    end
    local keep = {}
    for i = 1, #out do keep[i] = out[i] end
    findMemo[id] = keep
    return out
end

--- How many of an item the whole account holds.
-- @return number
function M:Total(id)
    local n = 0
    for _, hit in ipairs(self:Find(id)) do n = n + hit.count end
    return n
end

--- Drops a character from the cache, for a deleted or renamed alt.
-- @return boolean  whether anything was removed
function M:Forget(key)
    local s = store()
    if not (s and s.chars[key]) then return false end
    s.chars[key] = nil
    findMemo = {}
    return true
end

--- Whether the bank frame is currently open, i.e. whether the bank is readable at all.
-- @return boolean
function M:IsBankOpen() return bankOpen end

--------------------------------------------------------------------------------
-- Watching
--------------------------------------------------------------------------------

-- Debounced bags capture. The OnUpdate is registered only while a capture is pending and
-- unregistered the moment it fires, per the addon's "no idle OnUpdate" rule.
-- Debounced bags capture, and a debounced "items resolved" announcement sharing the same timer.
-- The OnUpdate is registered only while something is pending and unregistered the moment it fires,
-- per the addon's "no idle OnUpdate" rule.
--
-- THE ANNOUNCEMENT IS COALESCED FOR A REAL REASON: GET_ITEM_INFO_RECEIVED fires once PER ITEM, so a
-- fresh login browsing an alt with 58 unresolved stacks fires 58 times in a few frames. Emitting per
-- event would make every listening grid re-sort and re-place 80 cells 58 times. One announcement
-- after the burst settles is indistinguishable to the player and is a single pass.
local elapsed = 0
local wantCapture, wantResolve = false, false

local function onUpdate(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < DEBOUNCE then return end
    frame:SetScript("OnUpdate", nil)
    local capture, resolve = wantCapture, wantResolve
    wantCapture, wantResolve = false, false
    if capture then M:Capture("bags") end
    -- Emitted AFTER the capture, so a listener that reads the cache sees both effects at once.
    if resolve then SuuUI.Events:Emit("SUUUI_ITEMS_RESOLVED") end
end

local function arm()
    elapsed = 0
    frame:SetScript("OnUpdate", onUpdate)
end

local function markDirty()
    wantCapture = true
    arm()
end

local function markResolved()
    wantResolve = true
    arm()
end

function M:_watch()
    if frame then return end
    frame = CreateFrame("Frame")
    frame:RegisterEvent("BAG_UPDATE")
    -- ENTERING THE WORLD is the first moment the containers are readable, and without it a character
    -- who logs in and straight back out again records nothing: BAG_UPDATE may fire before the client
    -- has populated anything, and the logout sweep reads a torn-down API. Debounced like BAG_UPDATE
    -- rather than immediate, because the event fires before the bags have settled.
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("BANKFRAME_OPENED")
    frame:RegisterEvent("BANKFRAME_CLOSED")
    frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    frame:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
    frame:RegisterEvent("PLAYER_LOGOUT")
    -- The client answering a question we asked earlier: an item nothing had seen when it was
    -- captured. Registered unconditionally rather than only while a window is open, because the
    -- answers arrive during login and the point is that the cache is already correct by the time
    -- anyone looks at it.
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(_, event, arg1)
        if event == "GET_ITEM_INFO_RECEIVED" then
            -- Announce only when something was actually learned, so the burst of events for items no
            -- character holds costs one table lookup each and wakes no view at all.
            if M:Resolve(arg1) then markResolved() end
        elseif event == "BAG_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            markDirty()
        elseif event == "BANKFRAME_OPENED" then
            bankOpen = true
            -- The bank session IS the capture window, so read it the moment it opens rather
            -- than waiting for a change that may never come.
            M:Capture("bank")
        elseif event == "BANKFRAME_CLOSED" then
            bankOpen = false
        elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
            M:Capture("bank")
        elseif event == "PLAYER_LOGOUT" then
            -- The final sweep, so an alt is current as of its last play session. Bags only: the bank
            -- is not readable here.
            --
            -- AND OFTEN THE BAGS ARE NOT EITHER. Measured in game: this sweep wrote `money = 0` and an
            -- empty slot table over a perfectly good snapshot, which is why a cached alt rendered as an
            -- empty grid with no gold. Capture now refuses a read that reports no slots at all, so this
            -- is safe to keep -- and it is worth keeping, because when the API IS still answering it is
            -- the most current reading that character will ever have.
            frame:SetScript("OnUpdate", nil)
            M:Capture("bags")
        end
    end)
end

SuuUI.ItemCache = M
