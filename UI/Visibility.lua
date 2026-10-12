-- UI/Visibility.lua
-- When a frame shows: always, only in combat, on mouseover, or never.
--
--   UI.SetVisibility(frame, "always" | "combat" | "mouseover" | "hidden", also)
--
-- `also` (0.9, optional): frames outside `frame` whose hover counts as its
-- own for "mouseover" (bars attached to the dock, which fade with it but sit
-- outside it). Setting the mode a frame already has changes nothing (a
-- hovered mouseover frame stays faded in).
--
-- "combat" is a secure state driver, so it works for frames holding secure
-- buttons and switches in combat too. "mouseover" keeps the frame shown at
-- alpha 0 and fades it in while the mouse is over it or you drag something
-- (its buttons stay clickable, as Blizzard's mouseover bars do). Changing the
-- mode waits for the end of combat. While edit mode or keybind mode is open,
-- every managed frame that isn't "hidden" shows fully, so it can be placed
-- and bound.
--
-- UI.VISIBILITY_OPTIONS (0.9): the choices a "Shows" setting offers, as a
-- segmented control's options. "hidden" isn't one of them.

local _, ns = ...

local UI, T, Events, Combat, Motion = ns.UI, ns.Tokens, ns.Events, ns.Combat, ns.Motion

local modes = {}   -- frame -> mode
local hover = {}   -- frames fading on mouseover
local also = {}    -- frame -> frames whose hover counts as its own
local forced = false

UI.VISIBILITY_OPTIONS = {
    { value = "always", label = "Always" },
    { value = "combat", label = "In combat" },
    { value = "mouseover", label = "Mouseover" },
}

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

function UI.SetVisibility(frame, mode, extra)
    mode = mode or "always"
    also[frame] = extra
    if modes[frame] == mode then return end
    modes[frame] = mode
    apply(frame)
end

local function reapply()
    forced = (ns.EditMode and ns.EditMode.IsActive()) or (ns.KeybindMode and ns.KeybindMode.IsActive()) or false
    for frame in pairs(modes) do apply(frame) end
end
Events.On("SUUUI_EDITMODE_CHANGED", reapply, "Visibility")
Events.On("SUUUI_KEYBINDMODE_CHANGED", reapply, "Visibility")

-- Whether the mouse is over a frame or one of its `also` frames.
local function mouseOver(frame)
    if not frame:IsVisible() then return false end
    if frame:IsMouseOver() then return true end
    for _, f in ipairs(also[frame] or {}) do
        if f:IsVisible() and f:IsMouseOver() then return true end
    end
    return false
end

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
        local on = dragging or mouseOver(frame)
        if on ~= frame.suuHoverOn then
            frame.suuHoverOn = on
            Motion.AlphaTo(frame, on and 1 or 0, T.duration["dur-base"])
        end
    end
end)
