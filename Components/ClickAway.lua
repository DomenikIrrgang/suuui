-- Shared click-outside detector. Used by transient panels (Dropdown, ColorPicker).
-- Polls only while armed, so there is no idle OnUpdate cost.
local IsMouseButtonDown, GetCursorPosition = IsMouseButtonDown, GetCursorPosition

local AwayMeta = {}
AwayMeta.__index = AwayMeta

local function contains(frame, cx, cy)
    if not frame or not frame:IsShown() then return false end
    local l = frame:GetLeft()
    local r = frame:GetRight()
    local t = frame:GetTop()
    local b = frame:GetBottom()
    if not (l and r and t and b) then return false end
    return cx >= l and cx <= r and cy >= b and cy <= t
end

--- Starts watching for clicks outside the guarded frames.
-- Ignores the click that armed the watcher.
function AwayMeta:Arm()
    self._ignoreNext = true
    self._wasDown    = true
    self._watcher:Show()
end

--- Stops watching.
function AwayMeta:Disarm()
    self._watcher:Hide()
    self._wasDown    = false
    self._ignoreNext = false
end

--- Adds another frame that counts as "inside".
-- @param frame frame
function AwayMeta:AddGuard(frame)
    self._guards[#self._guards + 1] = frame
end

--- Releases the watcher.
function AwayMeta:Destroy()
    self._watcher:SetScript("OnUpdate", nil)
    self._watcher:Hide()
    -- Nothing is connected today, but the component contract is unconditional: a Destroy
    -- that skips this is a leak waiting for the first signal someone adds here.
    SuuUI.UISignals:DisconnectAll(self)
end

--- Creates a click-outside watcher.
-- @param props table  { frame, guards, onOutside }
--   frame: the panel that must stay open while clicked
--   guards: optional array of extra frames that count as inside
--   onOutside: called once when a click lands outside every guarded frame
-- @return table  ClickAway handle
function SuuUI.Components.ClickAway(props)
    local watcher = CreateFrame("Frame")
    watcher:Hide()

    local guards = { props.frame }
    if props.guards then
        for i = 1, #props.guards do guards[#guards + 1] = props.guards[i] end
    end

    local handle = setmetatable({
        _watcher    = watcher,
        _guards     = guards,
        _frame      = props.frame,
        _wasDown    = false,
        _ignoreNext = false,
    }, AwayMeta)

    watcher:SetScript("OnUpdate", function()
        if not handle._frame:IsShown() then
            handle:Disarm()
            return
        end

        local isDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")

        if handle._wasDown and not isDown then
            if handle._ignoreNext then
                handle._ignoreNext = false
            else
                -- Guard rects are in the panel's own space, so read the cursor there
                -- rather than UIParent's: the two differ under the scaled UI root.
                local cx, cy = SuuUI.Pixel.CursorIn(handle._frame)

                local inside = false
                for i = 1, #handle._guards do
                    if contains(handle._guards[i], cx, cy) then
                        inside = true
                        break
                    end
                end

                if not inside and props.onOutside then props.onOutside() end
            end
        end

        handle._wasDown = isDown
    end)

    return handle
end

--- Whether the cursor is currently inside a frame's rect.
--- Shared rather than re-derived, so a component that needs the same question OUTSIDE a poll
--- loop does not grow a second copy of the rect test. Reads the cursor in the frame's own
--- space, which is the only reading that is correct under the scaled UI root.
-- @param frame frame
-- @return bool
function SuuUI.Components.CursorInside(frame)
    if not frame then return false end
    local cx, cy = SuuUI.Pixel.CursorIn(frame)
    return contains(frame, cx, cy)
end

---------------------------------------------------------------------------
-- Hover-away
---------------------------------------------------------------------------
-- The same question ClickAway answers -- "is the cursor outside this set of frames" -- asked
-- on a different edge, which is why it shares the rect test above rather than growing a
-- second copy of it.
--
-- It exists because OnLeave CANNOT answer it for a panel whose children take mouse input.
-- The client moves mouse focus to the child, so the parent receives OnLeave the instant the
-- cursor enters one of its own rows -- a panel that closed on its own OnLeave would vanish
-- the moment you reached for the thing you were reaching for. Polling the rect is the only
-- reading that treats a panel and its contents as one region.

-- How long the cursor may read as outside before the panel closes. Input tolerance, not
-- design language: the cursor crosses a hairline seam between the anchor and the panel, and
-- a sample taken mid-crossing says "outside" for a frame or two. Deliberately NOT a theme
-- token -- no theme should be able to set this to 0 and make a panel unreachable.
local HOVER_GRACE = 0.15

local HoverMeta = {}
HoverMeta.__index = HoverMeta

--- Starts watching for the cursor leaving every guarded frame.
function HoverMeta:Arm()
    self._outside = 0
    self._watcher:Show()
end

--- Stops watching.
function HoverMeta:Disarm()
    self._watcher:Hide()
    self._outside = 0
end

--- Adds another frame that counts as "inside".
-- @param frame frame
function HoverMeta:AddGuard(frame)
    self._guards[#self._guards + 1] = frame
end

--- REPLACES the extra guards, keeping the panel itself.
---
--- Needed because AddGuard only appends: when the frame a panel hangs off is DESTROYED AND RECREATED
--- (a rail row rebuilt after its list changed), appending the new one leaves the dead one in the list
--- and grows it on every rebuild. A destroyed frame has no rect, so it can never read as inside --
--- which presents as a panel that closes the instant it opens.
-- @param frames table|nil  array of frames that count as inside, besides the panel
function HoverMeta:SetGuards(frames)
    local guards = { self._frame }
    if frames then
        for i = 1, #frames do guards[#guards + 1] = frames[i] end
    end
    self._guards = guards
end

--- Releases the watcher.
function HoverMeta:Destroy()
    self._watcher:SetScript("OnUpdate", nil)
    self._watcher:Hide()
    SuuUI.UISignals:DisconnectAll(self)
end

--- Creates a cursor-left-the-region watcher.
-- @param props table  { frame, guards, onOutside }
--   frame: the panel that must stay open while the cursor is over it
--   guards: optional array of extra frames that count as inside (the anchor it hangs off)
--   onOutside: called once when the cursor has been outside every guard for the grace period
-- @return table  HoverAway handle
function SuuUI.Components.HoverAway(props)
    local watcher = CreateFrame("Frame")
    watcher:Hide()

    local guards = { props.frame }
    if props.guards then
        for i = 1, #props.guards do guards[#guards + 1] = props.guards[i] end
    end

    local handle = setmetatable({
        _watcher = watcher,
        _guards  = guards,
        _frame   = props.frame,
        _outside = 0,
    }, HoverMeta)

    watcher:SetScript("OnUpdate", function(_, dt)
        if not handle._frame:IsShown() then
            handle:Disarm()
            return
        end

        -- Guard rects are in the panel's own space, so the cursor is read there rather than
        -- against UIParent: the two differ under the scaled UI root.
        local cx, cy = SuuUI.Pixel.CursorIn(handle._frame)

        local inside = false
        for i = 1, #handle._guards do
            if contains(handle._guards[i], cx, cy) then
                inside = true
                break
            end
        end

        if inside then
            handle._outside = 0
            return
        end

        handle._outside = handle._outside + (dt or 0)
        if handle._outside >= HOVER_GRACE then
            handle:Disarm()
            if props.onOutside then props.onOutside() end
        end
    end)

    return handle
end
