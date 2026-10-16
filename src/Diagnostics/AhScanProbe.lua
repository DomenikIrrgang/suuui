-- Diagnostics/AhScanProbe.lua
-- "/suu probe ahscan" (at the auction house): does the full scan work on
-- Forever? It asks the game for every auction once (ReplicateItems), waits
-- for REPLICATE_ITEM_LIST_UPDATE (a minute at most), and records how long it
-- took, how many auctions came back, how many had all their info, and five
-- of them. Saved in SuuUIProbe.ahScan on /reload. The game allows this only
-- now and then (on retail every 15 minutes), so run it once.

local _, ns = ...

local AP = {}
ns.AhScanProbe = AP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "secret" end
    return tostring(v)
end

local function store(out)
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.ahScan = out
end

-- What came back: the count, the share with all info, five samples.
local function collect(out)
    local ok, n = pcall(C_AuctionHouse.GetNumReplicateItems)
    out.count = ok and show(n) or ("error: " .. tostring(n))
    if not ok or type(n) ~= "number" then return end
    local full, samples = 0, {}
    for i = 0, n - 1 do
        local okInfo, name, _, count, quality, _, level, _, minBid, _, buyout, _, _, _, owner, _, _, itemID, hasAll =
            pcall(C_AuctionHouse.GetReplicateItemInfo, i)
        if okInfo then
            if hasAll then full = full + 1 end
            if #samples < 5 then
                samples[#samples + 1] = ("%s | item %s | x%s | q%s | lvl %s | bid %s | buyout %s | owner %s | all %s"):format(
                    show(name), show(itemID), show(count), show(quality), show(level), show(minBid), show(buyout), show(owner), show(hasAll))
            end
        elseif #samples < 5 then
            samples[#samples + 1] = "error at " .. i .. ": " .. tostring(name)
        end
    end
    out.withAllInfo = full
    out.samples = samples
end

function AP.Command()
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        ns.Print("Auction house scan probe: open the auction house first.")
        return
    end
    if AP.waiting then ns.Print("Auction house scan probe: already waiting for the scan.") return end
    local out = { at = date("%Y-%m-%d %H:%M:%S") }
    store(out)
    local okReady, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    out.throttleReady = okReady and show(ready) or ("error: " .. tostring(ready))
    local started = GetTime()
    local f = AP.frame or CreateFrame("Frame")
    AP.frame = f
    f:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    local function finish(why)
        if not AP.waiting then return end
        AP.waiting = nil
        f:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
        out.result = why
        out.seconds = ("%.1f"):format(GetTime() - started)
        collect(out)
        ns.Print(("Auction house scan probe: %s after %ss, %s auctions (%s with all info). /reload to save."):format(
            why, out.seconds, tostring(out.count), tostring(out.withAllInfo)))
    end
    f:SetScript("OnEvent", function() finish("list came back") end)
    AP.waiting = true
    local ok, err = pcall(C_AuctionHouse.ReplicateItems)
    out.call = ok and "ok" or ("error: " .. tostring(err))
    if not ok then
        finish("the call failed")
        return
    end
    ns.Print("Auction house scan probe: asked for every auction; waiting up to a minute.")
    C_Timer.After(60, function() finish("no answer in a minute") end)
end
