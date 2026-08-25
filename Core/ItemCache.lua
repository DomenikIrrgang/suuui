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
    for _, bag in ipairs(ids) do
        local n = numSlots(bag) or 0
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

    local key   = self:CurrentKey()
    local chars = store().chars
    local rec   = chars[key]
    if not rec then rec = {} chars[key] = rec end
    rec.class = rec.class or (UnitClass and select(2, UnitClass("player"))) or nil
    if GetMoney then rec.money = GetMoney() end
    -- `seen` is per character AND per container, not one stamp per character. Bags refresh every
    -- time that character plays; the bank only when they visit one, so hour-old bags beside
    -- three-week-old bank data is the normal case and a single stamp would be a lie.
    rec[which] = { seen = time(), slots = slots }
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
local elapsed = 0

local function onUpdate(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < DEBOUNCE then return end
    frame:SetScript("OnUpdate", nil)
    M:Capture("bags")
end

local function markDirty()
    elapsed = 0
    frame:SetScript("OnUpdate", onUpdate)
end

function M:_watch()
    if frame then return end
    frame = CreateFrame("Frame")
    frame:RegisterEvent("BAG_UPDATE")
    frame:RegisterEvent("BANKFRAME_OPENED")
    frame:RegisterEvent("BANKFRAME_CLOSED")
    frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    frame:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function(_, event)
        if event == "BAG_UPDATE" then
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
            -- The final sweep, so an alt is current as of its last play session. Bags only:
            -- the bank is not readable here.
            frame:SetScript("OnUpdate", nil)
            M:Capture("bags")
        end
    end)
end

SuuUI.ItemCache = M
