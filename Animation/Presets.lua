-- Presets reference SuuUI.Anim lazily (not at load time) to avoid ordering issues.
SuuUI.Anim.Presets = {}
local P = SuuUI.Anim.Presets

--- Fades frame in to alpha 1.
-- Starts from the frame's current alpha when it is already visible, so interrupting a
-- fade-out picks up where it left off instead of snapping to 0 and re-running the whole
-- fade. A hidden frame has nothing on screen to preserve, so it starts at 0.
-- The competing tween is retired by the animator: starting an alpha animation pre-empts
-- any other alpha animation on the same frame.
-- @param frame frame
-- @param duration number  Seconds (default: animFast token)
-- @return table  Animation handle
function P.FadeIn(frame, duration)
    local from = 0
    if frame:IsShown() then from = frame:GetAlpha() or 0 end
    frame:SetAlpha(from)
    frame:Show()
    local a = SuuUI.Anim:New({
        target   = frame,
        property = "alpha",
        from     = from, to = 1,
        duration = duration or SuuUI.Theme:GetToken("animFast"),
        easing   = "easeOut",
    })
    a:Play()
    return a
end

--- Fades frame out to alpha 0 then hides it.
-- @param frame frame
-- @param duration number
-- @return table  Animation handle
function P.FadeOut(frame, duration)
    local a = SuuUI.Anim:New({
        target   = frame,
        property = "alpha",
        from     = frame:GetAlpha(), to = 0,
        duration = duration or SuuUI.Theme:GetToken("animFast"),
        easing   = "easeIn",
        onDone   = function() frame:Hide() end,
    })
    a:Play()
    return a
end

-- Position animation goes through an anchor-layout container, so the layout engine
-- stays the only thing that positions anything.
local function slide(container, child, anchor, dir, dist, duration, easing, onDone)
    local horizontal = (dir == "left" or dir == "right")
    local prop = horizontal and "x" or "y"
    local base = horizontal and (anchor.x or 0) or (anchor.y or 0)
    local offset = (dir == "right" or dir == "up") and (base + dist) or (base - dist)
    return SuuUI.Anim:New({
        container = container,
        target    = child,
        anchor    = anchor,
        property  = prop,
        from      = easing == "easeOut" and offset or base,
        to        = easing == "easeOut" and base   or offset,
        duration  = duration,
        easing    = easing,
        onDone    = onDone,
    })
end

--- Slides a container child in from an offset direction.
-- @param container table  Anchor-layout container holding the child
-- @param child frame|table
-- @param anchor table  Base anchor descriptor the offset is applied to
-- @param dir string  "up"|"down"|"left"|"right"
-- @param dist number  Distance in units (default: spaceMd token)
-- @param duration number
-- @return table  Animation handle
function P.SlideIn(container, child, anchor, dir, dist, duration)
    local target = child.GetFrame and child:GetFrame() or child
    target:Show()
    local a = slide(container, child, anchor, dir,
        dist or SuuUI.Theme:GetToken("spaceMd"),
        duration or SuuUI.Theme:GetToken("animMid"), "easeOut")
    a:Play()
    return a
end

--- Slides a container child out in a direction then hides it.
-- @param container table  Anchor-layout container holding the child
-- @param child frame|table
-- @param anchor table  Base anchor descriptor the offset is applied to
-- @param dir string  "up"|"down"|"left"|"right"
-- @param dist number  Distance in units (default: spaceMd token)
-- @param duration number
-- @return table  Animation handle
function P.SlideOut(container, child, anchor, dir, dist, duration)
    local target = child.GetFrame and child:GetFrame() or child
    local a = slide(container, child, anchor, dir,
        dist or SuuUI.Theme:GetToken("spaceMd"),
        duration or SuuUI.Theme:GetToken("animMid"), "easeIn",
        function() target:Hide() end)
    a:Play()
    return a
end

--- Quick press feedback: scales up and back down to exactly 1.
--
-- This is the addon's ONE sanctioned SetScale, and the carve-out is narrow: the pixel
-- grid forbids a second scale in the chain because it puts layout units back between
-- physical pixels. That argument is about a scale a frame *keeps*. This one is transient
-- and self-reverting — the final write is exactly 1.0, restoring the grid — and it is
-- never nested, never persisted, and never read back by layout.
--
-- The guarantee depends on the animator always writing an animation's final value even
-- when the target is hidden. Without that, a frame hidden mid-pop kept a fractional
-- scale indefinitely, which is precisely the persistent violation the rule exists to
-- prevent. See applyValue in Animator.lua.
--
-- Callers wanting no scaling at all pass scalePop = false (Button, IconButton), or set
-- the animPopScale token to 1 to disable it UI-wide.
-- @param frame frame
-- @param duration number
-- @return table  Group handle
function P.ScalePop(frame, duration)
    local T = SuuUI.Theme
    local half = ((duration or T:GetToken("animFast")) * 0.5)
    local peak = T:GetToken("animPopScale")
    return SuuUI.Anim:Sequence({
        SuuUI.Anim:New({ target=frame, property="scale", from=1,    to=peak, duration=half, easing="easeOut" }),
        SuuUI.Anim:New({ target=frame, property="scale", from=peak, to=1,    duration=half, easing="easeIn"  }),
    })
end
