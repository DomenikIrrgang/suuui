-- Core/Motion.lua
-- The design's motion presets as AnimationGroups. Motion only ever decorates:
-- a value is always set at once, and an animation never delays it. With
-- ui.reducedMotion on, every preset jumps straight to its end state.
--
--   Motion.FadeIn(frame[, duration])  alpha 0 -> 1 (default dur-base, ease-out)
--   Motion.Enter(frame[, duration])   the alert's enter: 6px drop and fade (dur-base)
--   Motion.Pop(frame)                 a ready cooldown: scale 0.86 -> 1, alpha 0.4 -> 1 (dur-base)
--   Motion.Stop(frame)

local _, ns = ...

local Motion = {}
ns.Motion = Motion

local T, Settings = ns.Tokens, ns.Settings

local function reduced()
    return Settings.Ready() and Settings.Get("ui", "reducedMotion")
end

local function smoothing(easing)
    return T.easing[easing].smoothing
end

-- Running AlphaTo fades, frame -> { from, to, start, duration }.
local fades = {}

-- One AnimationGroup per frame and preset, built on first use.
local function group(frame, name, build)
    frame.suuMotion = frame.suuMotion or {}
    local g = frame.suuMotion[name]
    if not g then
        g = frame:CreateAnimationGroup()
        build(g)
        g:SetScript("OnFinished", function() frame:SetAlpha(1) end)
        frame.suuMotion[name] = g
    end
    return g
end

function Motion.Stop(frame)
    if frame.suuMotion then
        for _, g in pairs(frame.suuMotion) do g:Stop() end
    end
    fades[frame] = nil -- a running AlphaTo would override the alpha set here
    frame:SetAlpha(1)
end

function Motion.FadeIn(frame, duration)
    Motion.Stop(frame)
    if reduced() then return end
    local g = group(frame, "fadeIn", function(g)
        local a = g:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetSmoothing(smoothing("ease-out"))
        g.alpha = a
    end)
    g.alpha:SetDuration(duration or T.duration["dur-base"])
    g:Play()
end

function Motion.Enter(frame, duration)
    Motion.Stop(frame)
    if reduced() then return end
    local g = group(frame, "enter", function(g)
        -- Jump 6px up instantly, then move back down while fading in.
        local up = g:CreateAnimation("Translation")
        up:SetOffset(0, 6)
        up:SetDuration(0)
        up:SetOrder(1)
        local down = g:CreateAnimation("Translation")
        down:SetOffset(0, -6)
        down:SetSmoothing(smoothing("ease-out"))
        down:SetOrder(2)
        local a = g:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetSmoothing(smoothing("ease-out"))
        a:SetOrder(2)
        g.down, g.alpha = down, a
    end)
    local d = duration or T.duration["dur-base"]
    g.down:SetDuration(d)
    g.alpha:SetDuration(d)
    g:Play()
end

-- Fades `frame` from its current alpha to `to` over `duration` (ease-out).
-- One shared driver runs every fade, so it also works on secure frames,
-- whose scripts can't be set in combat (alpha itself is never protected).
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
    local now, any = GetTime(), false
    for frame, f in pairs(fades) do
        local t = math.min(1, (now - f.start) / f.duration)
        local e = 1 - (1 - t) ^ 3
        frame:SetAlpha(f.from + (f.to - f.from) * e)
        if t >= 1 then fades[frame] = nil else any = true end
    end
    if not any then self:Hide() end
end)

function Motion.AlphaTo(frame, to, duration)
    duration = duration or T.duration["dur-slow"]
    local from = frame:GetAlpha()
    if reduced() or duration <= 0 or math.abs(from - to) < 0.01 then
        fades[frame] = nil
        frame:SetAlpha(to)
        return
    end
    local f = fades[frame]
    if f and f.to == to then return end
    fades[frame] = { from = from, to = to, start = GetTime(), duration = duration }
    driver:Show()
end

function Motion.Pop(frame)
    Motion.Stop(frame)
    if reduced() then return end
    local g = group(frame, "pop", function(g)
        local s = g:CreateAnimation("Scale")
        s:SetScaleFrom(0.86, 0.86)
        s:SetScaleTo(1, 1)
        s:SetDuration(T.duration["dur-base"])
        s:SetSmoothing(smoothing("ease-out"))
        local a = g:CreateAnimation("Alpha")
        a:SetFromAlpha(0.4)
        a:SetToAlpha(1)
        a:SetDuration(T.duration["dur-base"])
        a:SetSmoothing(smoothing("ease-out"))
    end)
    g:Play()
end
