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
