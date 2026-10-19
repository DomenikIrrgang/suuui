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
--                 -- 0.17: a line's `gap` = space before it ({ "Next", gap = 8 })
--       description = "Reduces all damage taken by 75% for 10 sec.",
--       meta = "Ready in 21m",
--       maxWidth = 360,                                       -- 0.17; default 280
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
    self.content = d
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
        -- l.gap (0.17): space before a line that starts a new entry
        stack:Add(r, { gapBefore = (i == 1 and d.subtitle and S["space-2"] + S["space-1"]) or l.gap })
    end

    -- with a maxWidth (0.17), a description wraps at that width, not at the
    -- title's (a short title made a quest's objectives wrap early)
    if d.description and d.maxWidth then
        self.desc:SetValue(d.description)
        natural = math.max(natural, self.desc:GetUnboundedStringWidth())
    end
    -- the meta line counts too (a long hint ran past the edge), and wraps
    -- below when wider than the most
    if d.meta then
        self.status:SetValue(d.meta)
        natural = math.max(natural, self.status:GetUnboundedStringWidth())
    end
    local width = math.min(d.maxWidth or MAX_W, math.max(natural, 120) + pad * 2)
    local inner = width - pad * 2

    -- the title and subtitle wrap too when longer than the width
    -- ("Brackenwall Village, Dustwallow Marsh" ran past the edge); always
    -- the inner width (a width of 0 for a short one measured as 0 and
    -- emptied the tooltip; found in game)
    for _, t in ipairs({ self.heading, self.sub }) do
        t:SetWordWrap(true)
        t:SetJustifyH("LEFT")
        t:SetFixedWidth(inner)
    end

    self.desc:SetShown(d.description ~= nil)
    if d.description then
        self.desc:SetFixedWidth(inner)
        self.desc:SetValue(d.description)
        stack:Add(self.desc, { gapBefore = S["space-2"] + S["space-1"] })
    end
    self.status:SetShown(d.meta ~= nil)
    if d.meta then
        self.status:SetWordWrap(true)
        self.status:SetJustifyH("LEFT")
        self.status:SetFixedWidth(inner)
        self.status:SetValue(d.meta)
        stack:Add(self.status, { gapBefore = S["space-2"] + S["space-1"] })
    end
    for i, r in ipairs(self.rows) do
        r:SetWidth(inner)
        -- a line without a right side wraps inside the width (a map pin's
        -- "Varg Windwhisper  Leather Armor Merchant" ran past the edge)
        local l = d.lines and d.lines[i]
        if l and r:IsShown() then
            r.left:ClearAllPoints()
            if l[2] then
                r.left:SetWordWrap(false)
                r.left:SetWidth(0)
                r.left:SetPoint("LEFT")
            else
                r.left:SetWordWrap(true)
                r.left:SetJustifyH("LEFT")
                r.left:SetWidth(inner)
                r.left:SetPoint("TOPLEFT")
                r:SetHeight(math.max(T.type.body.lineHeight, math.ceil(r.left:GetStringHeight())))
            end
        end
    end
    self:SetWidth(width)
    stack:ApplyNow()
    self:SetHeight(self.stackFrame:GetHeight() + pad * 2)
end

-- a theme change: the shown ones laid out again (the text styles' sizes)
local tips = setmetatable({}, { __mode = "k" })
ns.Events.On("SUUUI_THEME_CHANGED", function()
    for t in pairs(tips) do
        if t:IsShown() and t.content then t:SetContent(t.content) end
    end
end, "UI.TooltipFrame")

function UI.TooltipFrame(parent)
    local f = UI.Panel(parent, { ornament = true, solid = false })
    Mixin(f, Tip)
    tips[f] = true
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
-- what the shared tooltip shows now: its owner and its data
local current = {}

function UI.HideTooltip()
    if intent then intent:Cancel() intent = nil end
    if shared then shared:Hide() end
    current.owner, current.data = nil, nil
end

function UI.ShowTooltip(owner, data)
    UI.HideTooltip()
    intent = C_Timer.NewTimer(INTENT, function()
        intent = nil
        if not owner:IsVisible() then return end
        shared = shared or UI.TooltipFrame(ns.Root)
        shared:SetFrameStrata("TOOLTIP")
        -- seen even while the UI is faded out (the NPC dialogue's scene)
        shared:SetIgnoreParentAlpha(true)
        shared:SetClampedToScreen(true)
        current.owner, current.data = owner, data
        shared:SetContent(type(data) == "function" and data(owner) or data)
        shared:ClearAllPoints()
        shared:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", S["space-4"], S["space-4"])
        shared:Show()
        Motion.FadeIn(shared, T.duration["dur-fast"])
    end)
end

-- 0.17: the shared tooltip shown for `owner` again, with its data a function
-- asked again (a modifier key changes what it says): nothing when it shows
-- for another frame, or not yet.
function UI.RefreshTooltip(owner)
    if not (shared and shared:IsShown() and current.owner == owner and type(current.data) == "function") then return end
    shared:SetContent(current.data(owner))
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
    UI.PaintFill(art.bg, "surface-glass")
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

--------------------------------------------------------------------------------
-- A spell's game tooltip with lines of SuuUI's under it (0.12)
--------------------------------------------------------------------------------
-- UI.SpellTooltip(owner, spellID, extra[, anchor]): GameTooltip with the
-- spell (SetSpellByID), then `extra` (text, or a list) as last lines. The
-- game redraws the tooltip when a spell's data arrives (the first hover of a
-- spell not loaded yet), which drops lines added after it: these are added
-- in a post-call too, so every draw carries them (found in game: the cost
-- showed only on the second hover).

local pending -- { id, lines }

local function addExtra(tooltip)
    for _, line in ipairs(pending.lines) do tooltip:AddLine(line, 1, 1, 1, true) end
end

local hooked = false
local function hookSpellTips()
    if hooked then return end
    hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
            if tooltip ~= GameTooltip or not pending then return end
            local id = data and data.id
            if issecretvalue and issecretvalue(id) then return end
            if id == pending.id and tooltip:GetOwner() == pending.owner then
                addExtra(tooltip)
                pending.added = true
            end
        end)
        hooked = "post"
    end
    GameTooltip:HookScript("OnHide", function() pending = nil end)
end

function UI.SpellTooltip(owner, spellID, extra, anchor)
    hookSpellTips()
    local lines = type(extra) == "table" and extra or (extra and { extra } or {})
    -- the owner first: it hides what the tooltip showed, and its OnHide
    -- clears `pending` (found in game)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    local mine = { id = spellID, owner = owner, lines = lines }
    pending = mine
    GameTooltip:SetSpellByID(spellID)
    -- no post-call in this client, or it didn't run: add them now
    if hooked ~= "post" or not mine.added then
        pending = mine
        addExtra(GameTooltip)
        mine.added = true
    end
    GameTooltip:Show()
end
