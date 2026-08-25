-- Selling grey items to a vendor, one item per tick.
--
-- WHY A LOOP AND NOT ONE CALL. `C_MerchantFrame.SellAllJunkItems` does not exist on this client --
-- measured in Phase 0 -- so the only route is UseContainerItem per slot. And that call MEANS THREE
-- DIFFERENT THINGS by location: at a merchant it SELLS (measured 2026-08-25, the item left the bag), at
-- an open bank it TRANSFERS, and anywhere else it USES the item, which is refused for tainted code. So
-- this module refuses to start away from a merchant -- not as caution but because the same call would
-- then try to USE eighty grey items in a row.
--
-- ONE TICK PER ITEM, at 0.2s, which is ElvUI's measured interval on this client. Selling is a server
-- round trip: firing eighty calls in one frame gets most of them dropped, and the bag does not clear
-- until the server confirms, so there is nothing to read back synchronously either.
--
-- IRREVERSIBLE ONCE BUYBACK OVERFLOWS. The vendor holds twelve buyback slots, so a sale of thirty
-- greys cannot be fully undone -- which is why the caller shows a confirmation naming the count and the
-- value, and why a grey with NO sell price is skipped rather than counted as a failure: it cannot be
-- sold at all, and reporting it as failed would make a clean run look broken.
local ipairs, type, select = ipairs, type, select

local M = {}

-- 0.2s, ElvUI's interval on this client. Its own constant rather than a theme token: this is a
-- SERVER pacing figure, not design language, and a theme has no business setting it.
--
-- It IS a plugin setting, though, which is a different thing: what paces safely depends on the
-- player's latency, and someone on 250ms wants a longer gap than someone on 20ms. TICK is the default
-- and the floor of what we recommend; SetInterval overrides it.
local TICK = 0.2
local interval = TICK

--- Overrides the seconds between sales. nil or a non-positive value returns to the default.
--
-- Clamped rather than trusted, because a hand-edited SavedVariable reaching 0 would turn the ticker
-- into a per-frame sell loop -- which is exactly the burst the interval exists to avoid.
-- @param seconds number|nil
function M.SetInterval(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then
        interval = TICK
        return interval
    end
    if seconds < 0.05 then seconds = 0.05 end
    if seconds > 5 then seconds = 5 end
    interval = seconds
    return interval
end

--- The interval currently in force.
-- @return number
function M.GetInterval() return interval end

local ticker
local queue = {}
local at = 0
local elapsed = 0
local onDone

--- Whether a merchant is open, which is the only place this may run.
-- @return bool
function M.AtMerchant()
    local f = MerchantFrame
    return (f and type(f.IsShown) == "function" and f:IsShown()) and true or false
end

--- The sell price of one item, or nil when the client has not cached it yet.
--
-- GetContainerItemInfo does NOT carry a price -- its measured field set has no such key -- so this is
-- the second call, and its answer may legitimately be missing for an item the client has not seen this
-- session. A missing price is reported as nil rather than 0 so the caller can say "at least" instead of
-- quietly under-reporting the total.
-- @param link string|nil
-- @return number|nil
function M.SellPrice(link)
    if not link or type(GetItemInfo) ~= "function" then return nil end
    local price = select(11, GetItemInfo(link))
    if type(price) ~= "number" or price <= 0 then return nil end
    return price
end

--- Every sellable grey across the given containers.
--
-- @param containers table  ordered bag ids
-- @return table  { { bag, slot, name, count, price } }, total copper, whether any price was unknown
function M.Scan(containers)
    local C = C_Container
    local found, total, unknown = {}, 0, false
    if not (C and type(C.GetContainerNumSlots) == "function"
            and type(C.GetContainerItemInfo) == "function") then
        return found, 0, false
    end

    for _, bag in ipairs(containers or {}) do
        local n = C.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C.GetContainerItemInfo(bag, slot)
            -- quality 0 is Poor. hasNoValue means the vendor will not take it, so it is not sellable
            -- and must never be queued -- a call on it would silently do nothing and the run would
            -- look stuck. isLocked means a move is already in flight for that slot.
            if info and info.quality == 0 and info.hasNoValue ~= true and info.isLocked ~= true then
                local count = info.stackCount or 1
                local price = M.SellPrice(info.hyperlink)
                if price then
                    total = total + price * count
                else
                    unknown = true
                end
                found[#found + 1] = {
                    bag = bag, slot = slot, name = info.itemName,
                    count = count, price = price,
                }
            end
        end
    end
    return found, total, unknown
end

--- Whether a sale is currently draining.
-- @return bool
function M.IsRunning()
    return ticker ~= nil and ticker:GetScript("OnUpdate") ~= nil
end

--- How many items are left to sell.
-- @return number
function M.Remaining()
    if not M.IsRunning() then return 0 end
    return #queue - at
end

local function stop()
    if ticker then ticker:SetScript("OnUpdate", nil) end
    queue, at, elapsed = {}, 0, 0
    local cb = onDone
    onDone = nil
    if cb then cb() end
end

--- Stops a sale in flight, leaving whatever has already sold sold.
function M.Stop()
    if M.IsRunning() then stop() end
end

local function tick(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < interval then return end
    elapsed = 0

    -- RE-CHECKED EVERY TICK, not once at the start. The player can walk away from the vendor or close
    -- the window mid-sale, and from that moment the same call would try to USE the items instead.
    if not M.AtMerchant() then
        stop()
        return
    end

    at = at + 1
    local entry = queue[at]
    if not entry then
        stop()
        return
    end

    local C = C_Container
    if C and type(C.UseContainerItem) == "function" then
        C.UseContainerItem(entry.bag, entry.slot)
    end
end

--- Starts selling a scanned list, one item per tick.
--
-- @param list table  as returned by Scan
-- @param done function|nil  called when the queue drains or the sale is stopped
-- @return bool  false when there is nothing to do or no merchant is open
function M.Start(list, done)
    if M.IsRunning() then return false end
    if not M.AtMerchant() then return false end
    if type(list) ~= "table" or #list == 0 then return false end

    queue, at, elapsed, onDone = list, 0, 0, done
    if not ticker then ticker = CreateFrame("Frame") end
    -- Registered only while a sale is in flight and dropped the moment it drains, per the addon's
    -- no-idle-OnUpdate rule.
    ticker:SetScript("OnUpdate", tick)
    return true
end

SuuUI._Inventory = SuuUI._Inventory or {}
SuuUI._Inventory.Sell = M
