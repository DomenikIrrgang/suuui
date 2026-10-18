-- UI/LoadingMark.lua
-- The SuuUI emblem for long waits (design component LoadingMark; first use:
-- the auction house's Scan all): the gilt-framed diamond with its cyan gem,
-- gilt wing lines to either side ending in small diamonds. It assembles once
-- when it starts (the mark grows in, the wings draw out, the jewels fade
-- in), then the gem's four facets catch the light one after another, every
-- 1.6 s, for as long as the wait lasts.
--
--   local m = UI.LoadingMark(parent, { size = 60, wings = true })
--   m:Start()   shows it, plays the assembly, then the loop
--   m:Stop()    hides it at once
--
-- size: the mark's edge in px (default 60); with wings the emblem is
-- 4 × size wide and 1.2 × size tall, without them size × size. Laid out on
-- the design's 400 × 120 grid, scaled by size / 100. With ui.reducedMotion
-- on it shows still: the whole emblem, no assembly, no loop.

local _, ns = ...

local UI, T, Settings = ns.UI, ns.Tokens, ns.Settings

local MEDIA = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"

local function reduced()
    return Settings.Ready() and Settings.Get("ui", "reducedMotion")
end

-- The facets: when each lights in the 1.6 s loop, and how bright.
local LOOP = 1.6
local FACETS = { { offset = 0, peak = 0.62 }, { offset = 0.15, peak = 0.55 }, { offset = 0.25, peak = 0.40 }, { offset = 0.40, peak = 0.50 } }
local LIGHT_IN, LIGHT_OUT = 0.18, 0.42

local function alpha(group, from, to, duration, delay, smoothing, order)
    local a = group:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(duration)
    a:SetStartDelay(delay or 0)
    a:SetSmoothing(smoothing or "OUT")
    a:SetOrder(order or 1)
    return a
end

function UI.LoadingMark(parent, opts)
    opts = opts or {}
    local size = opts.size or 60
    local wings = opts.wings ~= false
    local k = size / 100
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(wings and 400 * k or size, wings and 120 * k or size)
    f:Hide()

    -- the mark (and the facets on it) in a frame of its own, to grow in as one
    local mark = CreateFrame("Frame", nil, f)
    mark:SetSize(size, size)
    mark:SetPoint("TOPLEFT", wings and 150 * k or 0, wings and -10 * k or 0)
    local art = mark:CreateTexture(nil, "ARTWORK", nil, 0)
    art:SetTexture(MEDIA .. "LoadingMark.tga")
    art:SetAllPoints()
    f.facets = {}
    for i in ipairs(FACETS) do
        local t = mark:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetTexture(MEDIA .. "LoadingFacet" .. i .. ".tga")
        t:SetAllPoints()
        t:SetAlpha(0)
        f.facets[i] = t
    end

    -- the assembly: the mark grows in, the wings draw out from it, the jewels fade in
    f.intro = {}
    local grow = mark:CreateAnimationGroup()
    local scale = grow:CreateAnimation("Scale")
    scale:SetScaleFrom(0.86, 0.86)
    scale:SetScaleTo(1, 1)
    scale:SetOrigin("CENTER", 0, 0)
    scale:SetDuration(0.18)
    scale:SetSmoothing("OUT")
    alpha(grow, 0, 1, 0.18)
    f.intro[1] = grow
    f.wingParts = {}
    if wings then
        for side = 1, 2 do
            local left = side == 1
            local w = f:CreateTexture(nil, "BACKGROUND")
            w:SetColorTexture(1, 1, 1, 1)
            UI.PaintGradient(w, "HORIZONTAL", "gilt", "gilt", left and 0.15 or 0.85, left and 0.85 or 0.15)
            w:SetSize(118 * k, 1)
            w:SetPoint("TOPLEFT", (left and 30 or 252) * k, -59.5 * k)
            -- drawn out from its inner end after 0.2 s (hidden until then)
            local g2 = w:CreateAnimationGroup()
            g2:SetToFinalAlpha(true)
            alpha(g2, 0, 1, 0.01, 0.20, "NONE")
            local s = g2:CreateAnimation("Scale")
            s:SetScaleFrom(0.01, 1)
            s:SetScaleTo(1, 1)
            s:SetOrigin(left and "RIGHT" or "LEFT", 0, 0)
            s:SetDuration(0.24)
            s:SetStartDelay(0.20)
            s:SetSmoothing("OUT")
            f.intro[#f.intro + 1] = g2
            local jewel = UI.Diamond(f, 10 * k / math.sqrt(2), "gilt", "ARTWORK", 0)
            jewel:SetPoint("CENTER", f, "TOPLEFT", (left and 25 or 375) * k, -60 * k)
            local g3 = jewel:CreateAnimationGroup()
            g3:SetToFinalAlpha(true)
            alpha(g3, 0, 1, 0.18, 0.44)
            f.intro[#f.intro + 1] = g3
            f.wingParts[#f.wingParts + 1] = w
            f.wingParts[#f.wingParts + 1] = jewel
        end
    end

    -- the wait: each facet lights and fades in its turn, the loop 1.6 s long
    f.loops = {}
    for i, spec in ipairs(FACETS) do
        local g = f.facets[i]:CreateAnimationGroup()
        g:SetLooping("REPEAT")
        alpha(g, 0, spec.peak, LIGHT_IN, spec.offset, "OUT", 1)
        local fade = alpha(g, spec.peak, 0, LIGHT_OUT, 0, "IN_OUT", 2)
        fade:SetEndDelay(LOOP - spec.offset - LIGHT_IN - LIGHT_OUT)
        f.loops[i] = g
    end

    function f:Start()
        self:Stop()
        self:Show()
        if reduced() then return end
        for _, part in ipairs(self.wingParts) do part:SetAlpha(0) end
        for _, g in ipairs(self.intro) do g:Play() end
        -- the loop begins 0.8 s in, once the emblem has assembled
        self.loopTimer = C_Timer.NewTimer(0.8, function()
            self.loopTimer = nil
            for _, g in ipairs(self.loops) do g:Play() end
        end)
    end

    function f:Stop()
        if self.loopTimer then self.loopTimer:Cancel() self.loopTimer = nil end
        for _, g in ipairs(self.intro) do g:Stop() end
        for _, g in ipairs(self.loops) do g:Stop() end
        for _, t in ipairs(self.facets) do t:SetAlpha(0) end
        for _, part in ipairs(self.wingParts) do part:SetAlpha(1) end
        self:Hide()
    end

    return f
end
