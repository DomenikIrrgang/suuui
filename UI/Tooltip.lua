-- UI/Tooltip.lua
-- SuuUI's own tooltip, the detail layer for its frames: a panel with a single
-- top-left diamond, at most 280px wide, space-4 from its owner. It appears
-- after a 120ms hover intent with a dur-fast fade and hides at once.
-- (Blizzard's GameTooltip is restyled separately, in step 2.7.)
--
--   UI.ShowTooltip(owner, {
--       title = "Shield Wall", titleColor = "quality-epic",   -- default ink
--       subtitle = "Warrior · Protection",
--       lines = { { "Instant", "30 min cooldown" }, { "Requires a shield" } },
--       description = "Reduces all damage taken by 75% for 10 sec.",
--       meta = "Ready in 21m",
--   })
--   UI.HideTooltip()
--   UI.TooltipFrame(parent) -> a standalone tooltip with :SetContent(data)

local _, ns = ...

local UI, T, Layout, Motion = ns.UI, ns.Tokens, ns.Layout, ns.Motion
local S = T.space

local MAX_W = 280
local INTENT = 0.12

local Tip = {}

local function row(self, i)
    self.rows[i] = self.rows[i] or (function()
        local r = CreateFrame("Frame", nil, self.stackFrame)
        r.left = UI.Text(r, "body", "ink")
        r.left:SetPoint("LEFT")
        r.right = UI.Text(r, "body", "ink-muted")
        r.right:SetPoint("RIGHT")
        return r
    end)()
    return self.rows[i]
end

function Tip:SetContent(d)
    local stack = self.stack
    stack:Clear()
    local pad = S["space-5"]

    self.heading:SetColor(d.titleColor or "ink")
    self.heading:SetValue(d.title or "")
    local natural = self.heading:GetUnboundedStringWidth()
    stack:Add(self.heading)

    self.sub:SetValue(d.subtitle or "")
    self.sub:SetShown(d.subtitle ~= nil)
    if d.subtitle then
        stack:Add(self.sub)
        natural = math.max(natural, self.sub:GetUnboundedStringWidth())
    end

    for _, r in ipairs(self.rows) do r:Hide() end
    for i, l in ipairs(d.lines or {}) do
        local r = row(self, i)
        r.left:SetValue(l[1] or "")
        r.right:SetValue(l[2] or "")
        local w = r.left:GetUnboundedStringWidth() + (l[2] and (S["space-5"] + r.right:GetUnboundedStringWidth()) or 0)
        natural = math.max(natural, w)
        r:SetHeight(T.type.body.lineHeight)
        r:Show()
        stack:Add(r, { gapBefore = i == 1 and d.subtitle and S["space-2"] + S["space-1"] or nil })
    end

    local width = math.min(MAX_W, math.max(natural, 120) + pad * 2)
    local inner = width - pad * 2

    self.desc:SetShown(d.description ~= nil)
    if d.description then
        self.desc:SetFixedWidth(inner)
        self.desc:SetValue(d.description)
        stack:Add(self.desc, { gapBefore = S["space-2"] + S["space-1"] })
    end
    self.status:SetShown(d.meta ~= nil)
    if d.meta then
        self.status:SetValue(d.meta)
        stack:Add(self.status, { gapBefore = S["space-2"] + S["space-1"] })
    end
    for _, r in ipairs(self.rows) do r:SetWidth(inner) end
    self:SetWidth(width)
    stack:ApplyNow()
    self:SetHeight(self.stackFrame:GetHeight() + pad * 2)
end

function UI.TooltipFrame(parent)
    local f = UI.Panel(parent, { ornament = true, solid = false })
    Mixin(f, Tip)
    -- Sized by SetContent, not by the panel body.
    f.body:SetScript("OnSizeChanged", nil)
    f.body:Hide()
    f.stackFrame = CreateFrame("Frame", nil, f)
    f.stackFrame:SetPoint("TOPLEFT", S["space-5"], -S["space-5"])
    f.stack = Layout.Stack(f.stackFrame, { gap = S["space-1"] })
    f.heading = UI.Text(f.stackFrame, "unit-name-lg", "ink")
    f.sub = UI.Text(f.stackFrame, "caption", "ink-muted")
    f.desc = UI.Text(f.stackFrame, "body", "ink")
    f.desc:SetWordWrap(true)
    f.desc:SetJustifyH("LEFT")
    f.status = UI.Text(f.stackFrame, "caption", "ink-muted")
    f.rows = {}
    return f
end

--------------------------------------------------------------------------------
-- The shared tooltip
--------------------------------------------------------------------------------

local shared, intent

function UI.HideTooltip()
    if intent then intent:Cancel() intent = nil end
    if shared then shared:Hide() end
end

function UI.ShowTooltip(owner, data)
    UI.HideTooltip()
    intent = C_Timer.NewTimer(INTENT, function()
        intent = nil
        if not owner:IsVisible() then return end
        shared = shared or UI.TooltipFrame(ns.Root)
        shared:SetFrameStrata("TOOLTIP")
        shared:SetClampedToScreen(true)
        shared:SetContent(type(data) == "function" and data(owner) or data)
        shared:ClearAllPoints()
        shared:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", S["space-4"], S["space-4"])
        shared:Show()
        Motion.FadeIn(shared, T.duration["dur-fast"])
    end)
end

-- Shows `data` (a table, or a function of the frame) while the mouse is over `frame`.
function UI.AttachTooltip(frame, data)
    frame:HookScript("OnEnter", function(self) UI.ShowTooltip(self, data) end)
    frame:HookScript("OnLeave", UI.HideTooltip)
end

--------------------------------------------------------------------------------
-- Blizzard's tooltips in SuuUI's look (design board "Tooltips")
--
--   UI.SkinTooltip(tooltip)  -- GameTooltip, the compare tooltips, ItemRefTooltip
--
-- surface-glass under a gilt-line edge with the gilt diamond at the top left,
-- drawn on the tooltip's own BACKGROUND layer; Blizzard's NineSlice at alpha
-- 0 (again after each SharedTooltip_SetBackdropStyle, which runs on every
-- show). Only art is added: lines, sizes, anchors and every set function stay
-- Blizzard's.
--------------------------------------------------------------------------------

local skinned = {}

local function hideBlizzardArt(tooltip)
    if tooltip.NineSlice then tooltip.NineSlice:SetAlpha(0) end
end

function UI.SkinTooltip(tooltip)
    if not tooltip or skinned[tooltip] then return end
    local art = {}
    art.bg = tooltip:CreateTexture(nil, "BACKGROUND", nil, -8)
    art.bg:SetColorTexture(UI.RGBA("surface-glass"))
    art.bg:SetAllPoints()
    art.border = UI.Border(tooltip, "gilt-line", { layer = "BACKGROUND", sublevel = -7 })
    art.ornament = UI.Diamond(tooltip, 7, "gilt", "OVERLAY", 7)
    art.ornament:SetPoint("CENTER", tooltip, "TOPLEFT", 0, 0)
    skinned[tooltip] = art
    hideBlizzardArt(tooltip)
    return art
end

function UI.IsTooltipSkinned(tooltip) return skinned[tooltip] ~= nil end

if type(SharedTooltip_SetBackdropStyle) == "function" then
    hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip)
        if skinned[tooltip] then hideBlizzardArt(tooltip) end
    end)
end
