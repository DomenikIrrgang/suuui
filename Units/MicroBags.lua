-- Units/MicroBags.lua
-- Blizzard's micro menu and bag bar, moved out of the dock's way until SuuUI
-- draws its own (step 2.1). A built-in module written against the public API
-- only.
--
-- Each one moves into a holder of its own that edit mode can place: the micro
-- menu top left, where the design's micro menu sits (space-7 from the edges),
-- the bag bar bottom right. Both keep their Blizzard size, times the Scale
-- setting, and show as Shows says (always, in combat, on mouseover). Neither
-- is secure, so moving them is safe in combat too. When the game takes the
-- micro menu for itself (a vehicle's or a pet battle's bar), it is left
-- there, and comes back to its holder when the game hands it home.

local UI = SuuUI.UI

local M = SuuUI.RegisterModule({
    id = "microbags",
    name = "Micro menu and bags",
    description = "Moves Blizzard's micro menu and bag bar out of the action bar dock's way, into places you can set in edit mode.",
    api = "0.9",
    reloadToToggle = true,
    defaults = {
        microPosition = { point = "TOPLEFT", x = 28, y = -28 },
        bagsPosition = { point = "BOTTOMRIGHT", x = -28, y = 28 },
        shows = "always",
        scale = 1,
    },
})

-- What moves, where Blizzard keeps it when it's home, and its setting.
local ITEMS = {
    { frame = "MicroMenu", home = "MicroMenuContainer", key = "microPosition", label = "Micro menu", holder = "SuuUIMicroHolder" },
    { frame = "BagsBar", key = "bagsPosition", label = "Bag bar", holder = "SuuUIBagsHolder" },
}

local placing = false

-- Into the holder, at Blizzard's size times the Scale setting (the root runs
-- at its own scale).
local function adopt(item)
    local f, h = _G[item.frame], item.holderFrame
    if not (f and h) then return end
    placing = true
    f:SetParent(h)
    f:SetScale(UIParent:GetEffectiveScale() / h:GetEffectiveScale() * M:Get("scale"))
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", h, "TOPLEFT")
    placing = false
    local w, hgt = f:GetSize()
    h:SetSize(math.max(1, w * f:GetScale()), math.max(1, hgt * f:GetScale()))
end

-- Blizzard moves it back (layout passes, Edit Mode): adopt it again next
-- frame, unless the game parented it somewhere else on purpose.
local function guard(item)
    local f = _G[item.frame]
    local pending = false
    local function again()
        pending = false
        local parent = f:GetParent()
        if parent == item.holderFrame or parent == (item.home and _G[item.home]) or parent == UIParent then
            adopt(item)
        end
    end
    local function soon()
        if placing or pending then return end
        pending = true
        C_Timer.After(0, again)
    end
    hooksecurefunc(f, "SetPoint", soon)
    hooksecurefunc(f, "SetParent", soon)
end

-- Each holder by Shows, or hidden when edit mode hid it.
function M:ApplyShows()
    for _, item in ipairs(ITEMS) do
        local h = item.holderFrame
        if h then UI.SetVisibility(h, self:Get(item.key).hidden and "hidden" or self:Get("shows")) end
    end
end

local SECTION = {
    id = "microbags", label = "Micro menu & bags", category = "Frames", order = 28,
    groups = {
        { title = "Micro menu and bag bar", description = "Blizzard's own, until SuuUI draws its own. Move them in edit mode (General › Appearance › Edit layout).", rows = {
            { key = "shows", label = "Shows", control = "segmented", options = UI.VISIBILITY_OPTIONS, combat = true,
              description = "Always, only in combat, or when the mouse is over it." },
            { key = "scale", label = "Scale", control = "slider", min = 0.6, max = 1.4, step = 0.05,
              format = function(v) return ("%d%%"):format(v * 100 + 0.5) end,
              description = "Both at once, from Blizzard's size." },
        } },
    },
}

function M:OnEnable()
    for _, item in ipairs(ITEMS) do
        local f = _G[item.frame]
        if f then
            if not item.holderFrame then
                item.holderFrame = CreateFrame("Frame", item.holder, SuuUI.Root)
                item.holderFrame:SetSize(1, 1)
                adopt(item)
                guard(item)
            else
                adopt(item)
            end
            -- shown by Shows (and position.hidden), not by edit mode
            item.holderFrame.suuManagedShow = true
            self:RegisterMover(item.holderFrame, { key = item.key, label = item.label })
        end
    end
    self:RegisterSettings(SECTION)
    self:ApplyShows()
    for _, key in ipairs({ "shows", "microPosition", "bagsPosition" }) do
        self:Watch(key, function() self:ApplyShows() end)
    end
    self:Watch("scale", function()
        for _, item in ipairs(ITEMS) do if item.holderFrame then adopt(item) end end
    end)
    -- The root rescales with the UI scale: keep Blizzard's size.
    self:On("SUUUI_ROOT_SCALED", function()
        for _, item in ipairs(ITEMS) do if item.holderFrame then adopt(item) end end
    end)
end
