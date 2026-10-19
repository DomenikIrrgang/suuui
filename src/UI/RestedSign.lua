-- UI/RestedSign.lua
-- The rested sign (design "Rested on the player frame", option A "Drift",
-- chosen 2026-10-20): three letters, "z Z Z" in the display font and
-- progress-fill with the names' shadow, over a unit frame's top-right corner
-- on its raid marker's layer. While you earn rested XP each drifts up and
-- fades, one after the other; still, they stand at their start points. With
-- the pool full the first letter is a full moon. It is part of the frame:
-- it takes the frame's alpha, moves and scales with it, and never takes the
-- mouse.
--
--   local sign = UI.RestedSign(unitFrame)
--   sign:SetLook(look[, { still = bool, fade = seconds }])
--     look: "earn"  resting with room in the pool: drifting
--           "rest"  resting with nothing to earn (the level cap): still
--           "full"  resting, the pool full: still, the first letter a full moon
--           "carry" out of a rest area with rested XP left: still at opacity-ooc
--           nil     hidden
--     still: stand still even while earning (Animation: Still, edit mode);
--            Reduce motion always does
--     fade: in over that long (ease-out), or out (ease-in); nil: at once

local _, ns = ...

local UI, T = ns.UI, ns.Tokens

local DISC = "Interface\\AddOns\\SuuUI\\Media\\Textures\\CircleFill.tga"

-- Each letter: its text and style (12 and 16 px), its centre from the
-- frame's TOPRIGHT, its alpha when still, and its loop's start delay. One
-- AnimationGroup per letter, all 4.8 s long: start delay, 2.8 s of drift,
-- end delay, so the three stay in step.
local LETTERS = {
    { text = "z", style = "unit-name-sm", x = 7, y = 4, still = 0.55, delay = 0 },
    { text = "Z", style = "unit-name-sm", x = 15, y = 14, still = 0.8, delay = 0.7 },
    { text = "Z", style = "unit-name-lg", x = 26, y = 27, still = 1, delay = 1.4 },
}
local PERIOD, DRIFT = 4.8, 2.8
local DRIFT_X, DRIFT_Y = 3, 8
local FADE_IN, HOLD, FADE_OUT = 0.6, 1.0, 1.2
local MOON = 7

local Sign = {}

local function smoothing(easing) return T.easing[easing].smoothing end

-- A letter's loop: the holder drifts and fades in, its glyph fades out (an
-- alpha animation of its own on another region, so neither waits on the
-- other's end state). The holder rests at alpha 0 while it loops, so the
-- start delay and the end delay show nothing.
local function buildLoop(holder, glyph, d)
    local g = holder:CreateAnimationGroup()
    g:SetLooping("REPEAT")
    local move = g:CreateAnimation("Translation")
    move:SetOffset(DRIFT_X, DRIFT_Y)
    move:SetDuration(DRIFT)
    move:SetStartDelay(d.delay)
    move:SetEndDelay(PERIOD - DRIFT - d.delay)
    move:SetSmoothing(smoothing("ease-out"))
    local fadeIn = g:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(FADE_IN)
    fadeIn:SetStartDelay(d.delay)
    fadeIn:SetSmoothing(smoothing("ease-out"))
    local fadeOut = g:CreateAnimation("Alpha")
    fadeOut:SetTarget(glyph)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(FADE_OUT)
    fadeOut:SetStartDelay(d.delay + FADE_IN + HOLD)
    fadeOut:SetSmoothing(smoothing("ease-in"))
    return g
end

function UI.RestedSign(frame)
    local s = CreateFrame("Frame", nil, frame.markerLayer or frame)
    Mixin(s, Sign)
    s:SetSize(1, 1)
    s:SetPoint("CENTER", frame, "TOPRIGHT", 0, 0)
    s:EnableMouse(false)
    s:Hide()
    -- the body carries opacity-ooc out of a rest area; the sign itself its fades
    s.body = CreateFrame("Frame", nil, s)
    s.body:SetAllPoints()
    s.letters = {}
    for i, d in ipairs(LETTERS) do
        local l = CreateFrame("Frame", nil, s.body)
        l:SetSize(1, 1)
        l:SetPoint("CENTER", frame, "TOPRIGHT", d.x, d.y)
        l.glyph = UI.Text(l, d.style, "progress-fill")
        l.glyph:SetShadowed(true)
        l.glyph:SetPoint("CENTER", l, "CENTER", 0, 0)
        l.glyph:SetValue(d.text)
        l.loop = buildLoop(l, l.glyph, d)
        l.still = d.still
        s.letters[i] = l
    end
    -- the full moon in the first letter's place, with the same shadow (0 1px, black 90%)
    local first = s.letters[1]
    first.shade = first:CreateTexture(nil, "ARTWORK")
    first.shade:SetTexture(DISC)
    first.shade:SetSize(MOON, MOON)
    first.shade:SetPoint("CENTER", first, "CENTER", 0, -1)
    first.shade:SetVertexColor(0, 0, 0, 0.9)
    first.moon = first:CreateTexture(nil, "OVERLAY")
    first.moon:SetTexture(DISC)
    first.moon:SetSize(MOON, MOON)
    first.moon:SetPoint("CENTER", first, "CENTER", 0, 0)
    UI.Paint(first.moon, "progress-fill")

    -- leaving: from where it is to 0, ease-in, then hidden
    s.out = s:CreateAnimationGroup()
    s.out.alpha = s.out:CreateAnimation("Alpha")
    s.out.alpha:SetToAlpha(0)
    s.out.alpha:SetSmoothing(smoothing("ease-in"))
    s.out:SetScript("OnFinished", function() s:Gone() end)
    -- a loop doesn't run while hidden: shown again, the three start together
    s:SetScript("OnShow", function(self) if self.animating then self:Restart() end end)
    s:SetMoon(false)
    return s
end

function Sign:SetMoon(on)
    local first = self.letters[1]
    first.glyph:SetShown(not on)
    first.moon:SetShown(on)
    first.shade:SetShown(on)
end

function Sign:Restart()
    for _, l in ipairs(self.letters) do
        l.loop:Stop()
        l:SetAlpha(0)
        l.loop:Play()
    end
end

-- Drifting, or standing at the start points.
function Sign:Pose(still)
    if still then
        self.animating = false
        for _, l in ipairs(self.letters) do
            l.loop:Stop()
            l:SetAlpha(l.still)
        end
    elseif not self.animating then
        self.animating = true
        self:Restart()
    end
end

function Sign:Gone()
    self:Pose(true)
    self:Hide()
    self:SetAlpha(1)
end

function Sign:SetLook(look, opts)
    opts = opts or {}
    if not look then
        if not self.look then return end
        self.look = nil
        local from = self:GetAlpha()
        ns.Motion.Stop(self)
        if opts.fade and opts.fade > 0 and self:IsVisible() and not ns.Motion.Reduced() then
            self.out.alpha:SetFromAlpha(from)
            self.out.alpha:SetDuration(opts.fade)
            self:SetAlpha(0) -- what's left when the fade ends
            self.out:Play()
        else
            self.out:Stop()
            self:Gone()
        end
        return
    end
    local appearing = not self.look
    self.look = look
    self.body:SetAlpha(look == "carry" and T.opacity["opacity-ooc"] or 1)
    self:SetMoon(look == "full")
    self:Pose(opts.still or look ~= "earn" or ns.Motion.Reduced())
    if appearing then
        self.out:Stop()
        self:Show()
        if opts.fade and opts.fade > 0 then ns.Motion.FadeIn(self, opts.fade) else ns.Motion.Stop(self) end
    end
end
