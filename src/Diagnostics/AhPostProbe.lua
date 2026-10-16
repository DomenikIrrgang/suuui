-- Diagnostics/AhPostProbe.lua
-- "/suu probe ahpost" (at the auction house): may SuuUI's own buttons post
-- and cancel an auction? Posting, bidding, buying and cancelling are
-- "restricted" in the API docs; this tries two of them from SuuUI's own
-- buttons before an own auction house window is built on them (plan 3.6,
-- asked 2026-10-16).
--   a slot: put a cheap item in (drag it there, or click the slot holding it)
--   Post test   posts it for 12 hours at 999g buyout (nobody buys that)
--   Cancel test cancels the newest of your auctions of that item
-- What the game answers (the call's result, its events, a blocked action) is
-- printed and saved in SuuUIProbe.ahPost on /reload. Costs the small deposit.

local _, ns = ...

local AP = {}
ns.AhPostProbe = AP

local UI = ns.UI
local isSecret = issecretvalue or function() return false end
local BUYOUT = 999 * 10000

local function out(text)
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.ahPost = SuuUIProbe.ahPost or { lines = {} }
    local lines = SuuUIProbe.ahPost.lines
    lines[#lines + 1] = date("%H:%M:%S") .. " " .. text
    ns.Print("AH post probe: " .. text)
end

local function show(v)
    if isSecret(v) then return "secret" end
    return tostring(v)
end

-- The item in the slot as the auction house takes it.
local function location()
    local loc = AP.loc
    if loc and loc.IsValid and loc:IsValid() then return loc end
end

local function build()
    local p = UI.Panel(UIParent, { title = "AH post probe", width = 300, height = 150, solid = true })
    p:SetFrameStrata("DIALOG")
    p:SetPoint("TOP", UIParent, "TOP", 0, -120)
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    local slot = UI.ItemSlot(p.body)
    slot:SetPoint("TOPLEFT")
    local name = UI.Text(p.body, "label", "ink")
    name:SetPoint("LEFT", slot, "RIGHT", 10, 0)
    name:SetValue("Drop a cheap item here")
    local function take()
        if not (C_Cursor and C_Cursor.GetCursorItem) then out("no C_Cursor.GetCursorItem") return end
        local loc = C_Cursor.GetCursorItem()
        if not loc then return end
        AP.loc = loc
        ClearCursor()
        local link = C_Item.GetItemLink(loc)
        local icon = C_Item.GetItemIcon(loc)
        slot.skin:SetItem({ icon = icon, quality = "common" })
        name:SetValue(link or "?")
        local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, loc)
        out(("item %s, commodity status %s"):format(tostring(link), ok and show(status) or ("error " .. tostring(status))))
    end
    slot:SetScript("OnReceiveDrag", take)
    slot:SetScript("OnClick", take)
    local post = UI.Button(p.body, { text = "Post test", width = 120, onClick = function() AP.Post() end })
    post:SetPoint("BOTTOMLEFT")
    local cancel = UI.Button(p.body, { text = "Cancel test", width = 120, onClick = function() AP.Cancel() end })
    cancel:SetPoint("BOTTOMRIGHT")
    p.closeButton = UI.CloseButton and UI.CloseButton(p, function() p:Hide() end)
    if p.closeButton then p.closeButton:SetPoint("TOPRIGHT", -8, -8) end
    return p
end

function AP.Post()
    local loc = location()
    if not loc then out("put an item in the slot first") return end
    local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, loc)
    local commodity = ok and Enum.ItemCommodityStatus and status == Enum.ItemCommodityStatus.Commodity
    if commodity then
        local okPost, res = pcall(C_AuctionHouse.PostCommodity, loc, 1, 1, BUYOUT)
        out(("PostCommodity(…, 12h, 1, 999g): %s %s"):format(okPost and "returned" or "error", show(res)))
    else
        local okPost, res = pcall(C_AuctionHouse.PostItem, loc, 1, 1, nil, BUYOUT)
        out(("PostItem(…, 12h, 1, no bid, 999g): %s %s"):format(okPost and "returned" or "error", show(res)))
        if okPost and res == true and C_AuctionHouse.ConfirmPostItem then
            local okC, resC = pcall(C_AuctionHouse.ConfirmPostItem, loc, 1, 1, nil, BUYOUT)
            out(("ConfirmPostItem: %s %s"):format(okC and "returned" or "error", show(resC)))
        end
    end
end

-- The newest of your auctions of the slot's item (the owned list is asked
-- for when the panel opens and after each post).
function AP.Cancel()
    local loc = location()
    local itemID = loc and C_Item.GetItemID(loc)
    local best
    for i = 1, (C_AuctionHouse.GetNumOwnedAuctions() or 0) do
        local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if a and a.itemKey and (not itemID or a.itemKey.itemID == itemID) and a.status == 0 then
            if not best or a.auctionID > best.auctionID then best = a end
        end
    end
    if not best then
        out("no auction of yours for that item yet (asking the house for your auctions; try again in a moment)")
        pcall(C_AuctionHouse.QueryOwnedAuctions, {})
        return
    end
    local okC, res = pcall(C_AuctionHouse.CancelAuction, best.auctionID)
    out(("CancelAuction(%s): %s %s"):format(tostring(best.auctionID), okC and "returned" or "error", show(res)))
end

function AP.Command()
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        ns.Print("AH post probe: open the auction house first.")
        return
    end
    AP.panel = AP.panel or build()
    AP.panel:Show()
    if not AP.listening then
        AP.listening = true
        local f = CreateFrame("Frame")
        for _, e in ipairs({ "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_CANCELED", "AUCTION_HOUSE_POST_ERROR",
                             "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_SHOW_NOTIFICATION",
                             "OWNED_AUCTIONS_UPDATED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UI_ERROR_MESSAGE" }) do
            pcall(f.RegisterEvent, f, e)
        end
        f:SetScript("OnEvent", function(_, event, a, b)
            if event == "OWNED_AUCTIONS_UPDATED" then
                out("your auctions: " .. tostring(C_AuctionHouse.GetNumOwnedAuctions()))
                return
            end
            if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
                out(("%s by %s: %s"):format(event, tostring(a), tostring(b)))
                return
            end
            out(("%s %s %s"):format(event, show(a), show(b)))
            if event == "AUCTION_HOUSE_AUCTION_CREATED" then pcall(C_AuctionHouse.QueryOwnedAuctions, {}) end
        end)
    end
    pcall(C_AuctionHouse.QueryOwnedAuctions, {})
    out("ready: put a cheap item in the slot, Post test, then Cancel test; /reload to save")
end
