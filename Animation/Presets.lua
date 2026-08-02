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

--- Slides frame in from an offset direction.
-- @param frame frame
-- @param dir string  "up"|"down"|"left"|"right"
-- @param dist number  Pixel distance (default 12)
-- @param duration number
function P.SlideIn(frame, dir, dist, duration)
    dist     = dist or 12
    duration = duration or SuuUI.Theme:GetToken("animMid") or 0.20
    local prop       = (dir == "left" or dir == "right") and "x" or "y"
    local _, _, _, ox, oy = frame:GetPoint(1)
    ox, oy = ox or 0, oy or 0
    local from = (dir == "right") and (ox - dist)
              or (dir == "left")  and (ox + dist)
              or (dir == "down")  and (oy + dist)
              or (oy - dist)
    local to = (prop == "x") and ox or oy
    frame:Show()
    SuuUI.Anim:New({
        target=frame, property=prop, from=from, to=to,
        duration=duration, easing="easeOut",
    }):Play()
end

--- Slides frame out in a direction then hides it.
-- @param frame frame
-- @param dir string  "up"|"down"|"left"|"right"
-- @param dist number
-- @param duration number
function P.SlideOut(frame, dir, dist, duration)
    dist     = dist or 12
    duration = duration or SuuUI.Theme:GetToken("animMid") or 0.20
    local prop       = (dir == "left" or dir == "right") and "x" or "y"
    local _, _, _, ox, oy = frame:GetPoint(1)
    ox, oy = ox or 0, oy or 0
    local to = (dir == "right") and (ox + dist)
            or (dir == "left")  and (ox - dist)
            or (dir == "down")  and (oy - dist)
            or (oy + dist)
    local from = (prop == "x") and ox or oy
    SuuUI.Anim:New({
        target=frame, property=prop, from=from, to=to,
        duration=duration, easing="easeIn",
        onDone = function() frame:Hide() end,
    }):Play()
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
