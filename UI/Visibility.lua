-- UI/Visibility.lua
-- When a frame shows: always, only in combat, on mouseover, or never.
--
--   UI.SetVisibility(frame, "always" | "combat" | "mouseover" | "hidden")
--
-- "combat" is a secure state driver, so it works for frames holding secure
-- buttons and switches in combat too. "mouseover" keeps the frame shown at
-- alpha 0 and fades it in while the mouse is over it or you drag something
-- (its buttons stay clickable, as Blizzard's mouseover bars do). Changing the
-- mode waits for the end of combat. While edit mode or keybind mode is open,
-- every managed frame that isn't "hidden" shows fully, so it can be placed
-- and bound.

local _, ns = ...

local UI, T, Events, Combat, Motion = ns.UI, ns.Tokens, ns.Events, ns.Combat, ns.Motion

local modes = {}   -- frame -> mode
local hover = {}   -- frames fading on mouseover
local forced = false

local function apply(frame)
    local mode = modes[frame]
    local useDriver = mode == "combat" and not forced
    frame.suuHoverOn = nil
    Combat.Run("visibility:" .. tostring(frame), function()
        UnregisterStateDriver(frame, "visibility")
        if mode == "hidden" then
            frame:Hide()
        elseif useDriver then
            RegisterStateDriver(frame, "visibility", "[combat] show; hide")
        else
            frame:Show()
        end
    end, "Visibility")
    if mode == "mouseover" and not forced then
        hover[frame] = true
        frame:SetAlpha(0)
    else
        hover[frame] = nil
        Motion.AlphaTo(frame, 1, 0)
    end
end

function UI.SetVisibility(frame, mode)
    mode = mode or "always"
    modes[frame] = mode
    apply(frame)
end

local function reapply()
    forced = (ns.EditMode and ns.EditMode.IsActive()) or (ns.KeybindMode and ns.KeybindMode.IsActive()) or false
    for frame in pairs(modes) do apply(frame) end
end
Events.On("SUUUI_EDITMODE_CHANGED", reapply, "Visibility")
Events.On("SUUUI_KEYBINDMODE_CHANGED", reapply, "Visibility")

-- Mouseover: a light poll, only while some frame uses it.
local poll = CreateFrame("Frame")
local elapsed = 0
poll:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    if not next(hover) then return end
    local dragging = GetCursorInfo() ~= nil
    for frame in pairs(hover) do
        local on = dragging or (frame:IsVisible() and frame:IsMouseOver())
        if on ~= frame.suuHoverOn then
            frame.suuHoverOn = on
            Motion.AlphaTo(frame, on and 1 or 0, T.duration["dur-base"])
        end
    end
end)
