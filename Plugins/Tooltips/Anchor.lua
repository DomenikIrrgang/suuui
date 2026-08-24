-- Tooltip placement: a moveable anchor the player positions in edit mode, plus cursor-follow
-- as an alternative.
--
-- Blizzard's GameTooltip_SetDefaultAnchor is HOOKED, never replaced. The hook re-owns the
-- tooltip with ANCHOR_NONE and re-points it, which is how ElvUI does it on this client.
local type, next = type, next

local M = {}

local PLUGIN_ID = "tooltips"

-- Where a tooltip attaches to the mover, given which corner the mover sits in. A tooltip
-- anchored bottom-right must grow UP and LEFT, or it grows off the screen.
local INVERSE = {
    TOPLEFT     = "BOTTOMRIGHT",
    TOPRIGHT    = "BOTTOMLEFT",
    BOTTOMLEFT  = "TOPRIGHT",
    BOTTOMRIGHT = "TOPLEFT",
    TOP         = "BOTTOM",
    BOTTOM      = "TOP",
    LEFT        = "RIGHT",
    RIGHT       = "LEFT",
    CENTER      = "CENTER",
}

M.INVERSE = INVERSE

local mover

--- The frame the player drags in edit mode. Small and invisible: it marks a CORNER, and the
--- tooltip grows away from it.
function M.EnsureMover()
    if mover then return mover end
    local root = SuuUI.UIRoot:GetRootContainer()
    if not root then return nil end

    mover = CreateFrame("Frame", "SuuUI_tooltips_anchor", root:GetFrame())
    mover:SetSize(140, 20)
    SuuUI.UIRoot:SetLayer(mover, "normal")

    SuuUI.MoveableFrame:Apply(mover, {
        pluginId    = PLUGIN_ID,
        key         = "position",
        displayName = "Tooltip",
        defaults    = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -200, y = 200 },
    })
    return mover
end

function M.GetMover() return mover end

--- Which of the mover's own corners the tooltip should hang off.
--
-- Read from the stored position rather than kept as a second setting: the player already said
-- which corner they wanted by dragging the mover there, and a separate dropdown could disagree
-- with it.
local function moverPoint()
    local pos = SuuUI.Settings:Get(PLUGIN_ID, "position")
    local p = type(pos) == "table" and pos.point or nil
    return INVERSE[p] and p or "BOTTOMRIGHT"
end

M.moverPoint = moverPoint

--- Anchors that count as UNCLAIMED -- ones we may take over.
--
-- The whitelist is what stops SuuUI fighting another addon that placed the tooltip
-- deliberately. Anything not in here was put where it is on purpose.
local function unclaimed(anchor)
    if anchor == nil then return true end
    if anchor == _G.UIParent then return true end
    if mover and anchor == mover then return true end
    local rootC = SuuUI.UIRoot:GetRootContainer()
    if rootC and anchor == rootC:GetFrame() then return true end
    if anchor == _G.GameTooltipDefaultContainer then return true end
    return false
end

M.unclaimed = unclaimed

--- The hook body for GameTooltip_SetDefaultAnchor.
-- @return string|nil  "cursor" | "mover" | nil when it declined
function M.Place(tt, parent)
    if type(tt) ~= "table" then return nil end
    if not SuuUI.Settings:Get(PLUGIN_ID, "enabled") then return nil end
    if type(tt.IsForbidden) == "function" and tt:IsForbidden() then return nil end
    -- Something already owns the anchor. Bail rather than argue with it.
    if type(tt.GetAnchorType) == "function" and tt:GetAnchorType() ~= "ANCHOR_NONE" then
        return nil
    end

    if SuuUI.Settings:Get(PLUGIN_ID, "anchor_mode") == "cursor" then
        if parent and type(tt.SetOwner) == "function" then
            -- The client does the following; we only pick the anchor type.
            tt:SetOwner(parent, "ANCHOR_CURSOR",
                SuuUI.Settings:Get(PLUGIN_ID, "x_offset") or 0,
                SuuUI.Settings:Get(PLUGIN_ID, "y_offset") or 0)
        end
        return "cursor"
    end

    if parent and type(tt.SetOwner) == "function" then
        tt:SetOwner(parent, "ANCHOR_NONE")
    end

    local anchorFrame = M.EnsureMover()
    if not anchorFrame then return nil end

    local _, current = tt:GetPoint()
    if not unclaimed(current) then return nil end

    local point = moverPoint()
    tt:ClearAllPoints()
    -- A Blizzard frame, so SetPoint here is the sanctioned carve-out: a tooltip cannot be
    -- adopted into one of our containers without tainting it, so the layout engine has no
    -- route to it at all.
    --
    -- ARGUMENT ORDER IS LOAD-BEARING. The TOOLTIP's `point` attaches to the mover's INVERSE,
    -- which is what makes the tooltip grow AWAY from the mover: a mover in the bottom-right
    -- has the tooltip's BOTTOMRIGHT on its TOPLEFT, so the box extends up and left, into the
    -- screen. Reversed -- the tooltip's TOPLEFT on the mover's BOTTOMRIGHT -- it grows down and
    -- right, straight off the edge, which is how this was first written.
    tt:SetPoint(point, anchorFrame, INVERSE[point],
        SuuUI.Settings:Get(PLUGIN_ID, "x_offset") or 0,
        SuuUI.Settings:Get(PLUGIN_ID, "y_offset") or 0)
    return "mover"
end

--- Drops the mover on teardown.
function M.Release()
    if not mover then return end
    SuuUI.MoveableFrame:Remove(mover)
    mover:Hide()
    mover = nil
end

SuuUI._Tooltips = SuuUI._Tooltips or {}
SuuUI._Tooltips.Anchor = M
