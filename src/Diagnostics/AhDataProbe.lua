-- Diagnostics/AhDataProbe.lua
-- "/suu probe ahdata [search]" (at the auction house): what the auction
-- house's own data looks like, for SuuUI's own window (plan 3.6). It only
-- searches and reads; nothing is bought. In order, each step waiting for the
-- game's answer (or three seconds):
--   browse      a search (default "linen"): each result's item, lowest price,
--               quantity, whether it's a commodity
--   item        the first non-commodity result's auctions: sellers, time
--               left, bid and buyout per auction
--   commodity   the first commodity result's offers: price per unit,
--               quantity, sellers
--   categories  the game's category tree (AuctionCategories) and its filters
--   bids        your bids
-- Printed and saved in SuuUIProbe.ahData on /reload.

local _, ns = ...

local AP = {}
ns.AhDataProbe = AP

local isSecret = issecretvalue or function() return false end
local function show(v, depth)
    depth = depth or 0
    if isSecret(v) then return "secret" end
    if type(v) == "table" then
        if depth > 1 then return "{…}" end
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. show(x, depth + 1) end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

local out
local function line(section, text)
    out[section] = out[section] or {}
    table.insert(out[section], text)
end

-- Runs fn when `event` comes (once), or after three seconds.
local function after(event, fn)
    local done = false
    local f = CreateFrame("Frame")
    local function go(why)
        if done then return end
        done = true
        f:UnregisterAllEvents()
        fn(why)
    end
    pcall(f.RegisterEvent, f, event)
    f:SetScript("OnEvent", function() C_Timer.After(0.3, function() go("event") end) end)
    C_Timer.After(3, function() go("timeout") end)
end

local function keyInfo(key)
    local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, key)
    return ok and info or nil
end

local function stepBids()
    pcall(C_AuctionHouse.QueryBids, {}, {})
    after("BIDS_UPDATED", function(why)
        local ok, bids = pcall(C_AuctionHouse.GetBids)
        line("bids", ("(%s) %s bids"):format(why, ok and type(bids) == "table" and #bids or ("error " .. tostring(bids))))
        if ok and type(bids) == "table" then
            for i = 1, math.min(2, #bids) do line("bids", show(bids[i])) end
        end
        SuuUIProbe = SuuUIProbe or {}
        SuuUIProbe.ahData = out
        ns.Print("AH data probe: done. /reload to save.")
    end)
end

local function stepCategories()
    local cats = rawget(_G, "AuctionCategories")
    if type(cats) ~= "table" then
        line("categories", "AuctionCategories: " .. type(cats))
    else
        line("categories", #cats .. " top categories")
        for i, c in ipairs(cats) do
            local subs = c.subCategories and #c.subCategories or 0
            local filters = {}
            for _, f in ipairs(c.filters or {}) do filters[#filters + 1] = show(f) end
            line("categories", ("%d %s: %d sub, flags %s, filters %s"):format(i, tostring(c.name), subs, show(c.flags),
                table.concat(filters, "; "):sub(1, 200)))
            if i == 1 and c.subCategories then
                for k = 1, math.min(3, subs) do
                    local s = c.subCategories[k]
                    line("categories", ("  %s: %d sub, filters %d"):format(tostring(s.name), s.subCategories and #s.subCategories or 0, s.filters and #s.filters or 0))
                end
            end
        end
    end
    stepBids()
end

local function stepCommodity(key)
    if not key then line("commodity", "no commodity among the results") stepCategories() return end
    pcall(C_AuctionHouse.SendSearchQuery, key, {}, true)
    after("COMMODITY_SEARCH_RESULTS_UPDATED", function(why)
        local n = C_AuctionHouse.GetNumCommoditySearchResults(key.itemID)
        line("commodity", ("(%s) %s: %s offers"):format(why, show((keyInfo(key) or {}).itemName), show(n)))
        for i = 1, math.min(4, n or 0) do
            local ok, r = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, key.itemID, i)
            line("commodity", ok and show(r) or ("error " .. tostring(r)))
        end
        stepCategories()
    end)
end

local function stepItem(key, commodityKey)
    if not key then line("item", "no non-commodity among the results") stepCommodity(commodityKey) return end
    pcall(C_AuctionHouse.SendSearchQuery, key, {}, true)
    after("ITEM_SEARCH_RESULTS_UPDATED", function(why)
        local n = C_AuctionHouse.GetNumItemSearchResults(key)
        line("item", ("(%s) %s: %s auctions"):format(why, show((keyInfo(key) or {}).itemName), show(n)))
        for i = 1, math.min(4, n or 0) do
            local ok, r = pcall(C_AuctionHouse.GetItemSearchResultInfo, key, i)
            line("item", ok and show(r) or ("error " .. tostring(r)))
        end
        stepCommodity(commodityKey)
    end)
end

function AP.Command(rest)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        ns.Print("AH data probe: open the auction house first.")
        return
    end
    local text = (rest and rest ~= "") and rest or "linen"
    out = { at = date("%Y-%m-%d %H:%M:%S"), search = text }
    ns.Print(("AH data probe: searching %q, then reading; about 15 seconds."):format(text))
    local query = { searchString = text, sorts = {}, filters = {}, itemClassFilters = {} }
    local ok, err = pcall(C_AuctionHouse.SendBrowseQuery, query)
    if not ok then line("browse", "SendBrowseQuery error " .. tostring(err)) end
    after("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function(why)
        local okR, results = pcall(C_AuctionHouse.GetBrowseResults)
        results = okR and results or {}
        line("browse", ("(%s) %d results"):format(why, #results))
        local itemKey, commodityKey
        for i, r in ipairs(results) do
            local info = keyInfo(r.itemKey) or {}
            if i <= 6 then
                line("browse", ("%s | key %s | min %s | qty %s | commodity %s | equipment %s | yours %s"):format(
                    show(info.itemName), show(r.itemKey), show(r.minPrice), show(r.totalQuantity), show(info.isCommodity),
                    show(info.isEquipment), show(r.containsOwnerItem)))
            end
            if info.isCommodity and not commodityKey then commodityKey = r.itemKey end
            if info.isCommodity == false and not itemKey then itemKey = r.itemKey end
        end
        stepItem(itemKey, commodityKey)
    end)
end
