-- Presets reference SuuUI.Anim lazily (not at load time) to avoid ordering issues.
SuuUI.Anim.Presets = {}
local P = SuuUI.Anim.Presets

--- Fades frame in from alpha 0 to 1.
-- @param frame frame
-- @param duration number  Seconds (default: animFast token)
function P.FadeIn(frame, duration)
    frame:SetAlpha(0)
    frame:Show()
    SuuUI.Anim:New({
        target   = frame,
        property = "alpha",
        from     = 0, to = 1,
        duration = duration or SuuUI.Theme:GetToken("animFast") or 0.12,
        easing   = "easeOut",
    }):Play()
end

--- Fades frame out to alpha 0 then hides it.
-- @param frame frame
-- @param duration number
function P.FadeOut(frame, duration)
    SuuUI.Anim:New({
        target   = frame,
        property = "alpha",
        from     = frame:GetAlpha(), to = 0,
        duration = duration or SuuUI.Theme:GetToken("animFast") or 0.12,
        easing   = "easeIn",
        onDone   = function() frame:Hide() end,
    }):Play()
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
-- @param dist number  Pixel distance (default 12)
-- @param duration number
function P.SlideIn(container, child, anchor, dir, dist, duration)
    local target = child.GetFrame and child:GetFrame() or child
    target:Show()
    slide(container, child, anchor, dir, dist or 12,
        duration or SuuUI.Theme:GetToken("animMid") or 0.20, "easeOut"):Play()
end

--- Slides a container child out in a direction then hides it.
-- @param container table  Anchor-layout container holding the child
-- @param child frame|table
-- @param anchor table  Base anchor descriptor the offset is applied to
-- @param dir string  "up"|"down"|"left"|"right"
-- @param dist number
-- @param duration number
function P.SlideOut(container, child, anchor, dir, dist, duration)
    local target = child.GetFrame and child:GetFrame() or child
    slide(container, child, anchor, dir, dist or 12,
        duration or SuuUI.Theme:GetToken("animMid") or 0.20, "easeIn",
        function() target:Hide() end):Play()
end

--- Quick scale pop: 1 → 1.08 → 1.
-- @param frame frame
-- @param duration number
function P.ScalePop(frame, duration)
    local half = ((duration or SuuUI.Theme:GetToken("animFast") or 0.12) * 0.5)
    SuuUI.Anim:Sequence({
        SuuUI.Anim:New({ target=frame, property="scale", from=1,    to=1.08, duration=half, easing="easeOut" }),
        SuuUI.Anim:New({ target=frame, property="scale", from=1.08, to=1,    duration=half, easing="easeIn"  }),
    })
end
