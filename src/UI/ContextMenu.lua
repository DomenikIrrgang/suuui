-- UI/ContextMenu.lua
-- SuuUI's right-click menu, in the tooltip's look (asked for in game: the
-- game's menus were Blizzard's): the glass panel with its gilt corner
-- diamond, an optional title in the tooltip's heading face, then the
-- actions, one per row (label in ink, a row on hover on arcane-soft;
-- disabled ones in ink-faint), a gilt-faint rule between groups. It opens
-- at the cursor; a click outside, Esc or picking an action closes it.
--
--   UI.ContextMenu(owner, { title = "The Ashmaw Den", items = {
--       { label = "Focus", onClick = fn }, { separator = true },
--       { label = "Stop tracking", onClick = fn, disabled = false } } })
--   UI.CloseContextMenu()
-- 0.17: opts.id names the menu and opts.context says what it's about;
-- plugins' entries for that id join before it opens (M:ExtendMenu).

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local ROW_H = 24
local MIN_W = 160

local menu, catcher

local function close()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end
UI.CloseContextMenu = close

local function build()
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:RegisterForClicks("AnyDown")
    catcher:SetScript("OnClick", close)
    catcher:Hide()
    menu = UI.Panel(ns.Root, { ornament = true, solid = false })
    menu.body:Hide()
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu.title = UI.Text(menu, "unit-name-lg", "ink")
    menu.title:SetPoint("TOPLEFT", S["space-5"], -S["space-5"])
    menu.rows, menu.rules = {}, {}
    -- Esc closes it (out of combat: the key can't be held back in one)
    menu:EnableKeyboard(true)
    menu:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            close()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    menu:Hide()
end

local function row(i)
    local r = menu.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, menu)
    r:SetHeight(ROW_H)
    r.hover = UI.Fill(r, "arcane-soft", "BACKGROUND", 1)
    r.hover:SetAllPoints()
    r.hover:Hide()
    r.label = UI.Text(r, "body", "ink")
    r.label:SetPoint("LEFT", S["space-4"], 0)
    r:SetScript("OnEnter", function(self) if not self.item.disabled then self.hover:Show() end end)
    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
    r:SetScript("OnClick", function(self)
        if self.item.disabled then return end
        close()
        if self.item.onClick then self.item.onClick() end
    end)
    menu.rows[i] = r
    return r
end

local function rule(i)
    local l = menu.rules[i]
    if l then return l end
    l = UI.Fill(menu, "gilt-faint", "ARTWORK")
    l:SetHeight(1)
    menu.rules[i] = l
    return l
end

function UI.ContextMenu(owner, opts)
    if not menu then build() end
    opts = opts or {}
    opts.items = opts.items or {}
    if opts.id then ns.Extend.ApplyMenu(opts.id, opts, opts.context) end
    local pad = S["space-5"]
    local y = pad
    menu.title:SetShown(opts.title ~= nil)
    local width = MIN_W
    if opts.title then
        menu.title:SetValue(opts.title)
        width = math.max(width, math.ceil(menu.title:GetUnboundedStringWidth()) + pad * 2)
        y = y + T.type["unit-name-lg"].lineHeight + S["space-3"]
    end
    local nRow, nRule = 0, 0
    local placed = {}
    for _, item in ipairs(opts.items or {}) do
        if item.separator then
            nRule = nRule + 1
            local l = rule(nRule)
            y = y + S["space-2"]
            placed[#placed + 1] = { region = l, y = y, rule = true }
            y = y + 1 + S["space-2"]
        else
            nRow = nRow + 1
            local r = row(nRow)
            r.item = item
            r.label:SetValue(item.label or "")
            r.label:SetColor(item.disabled and "ink-faint" or "ink")
            width = math.max(width, math.ceil(r.label:GetUnboundedStringWidth()) + S["space-4"] * 2 + pad * 2 - S["space-3"] * 2)
            placed[#placed + 1] = { region = r, y = y }
            y = y + ROW_H
        end
    end
    -- the rows reach the panel's edges less a little, so their hover reads
    -- as a band inside the glass
    local inset = pad - S["space-3"]
    for _, p in ipairs(placed) do
        p.region:ClearAllPoints()
        p.region:SetPoint("TOPLEFT", inset, -p.y)
        p.region:SetPoint("TOPRIGHT", -inset, -p.y)
        p.region:Show()
        if not p.rule then p.region.hover:Hide() end
    end
    for i = nRow + 1, #menu.rows do menu.rows[i]:Hide() end
    for i = nRule + 1, #menu.rules do menu.rules[i]:Hide() end
    menu:SetSize(width, y + pad - S["space-2"])
    -- at the cursor
    local scale = menu:GetEffectiveScale()
    local x, cy = GetCursorPosition()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 2, cy / scale - 2)
    GameTooltip:Hide()
    UI.HideTooltip()
    catcher:Show()
    menu:Show()
    return menu
end

-- The same menu described the way the game's are (MenuUtil's generator:
-- root:CreateTitle(text), root:CreateButton(label, fn), root:CreateDivider()),
-- so a menu moves over by its first line.
--   UI.ContextMenuFrom(owner, function(owner, root) ... end[, id, context])
function UI.ContextMenuFrom(owner, describe, id, context)
    local opts = { items = {}, id = id, context = context }
    local root = {}
    function root:CreateTitle(text) opts.title = opts.title or text end
    function root:CreateButton(label, onClick)
        local item = { label = label, onClick = onClick }
        opts.items[#opts.items + 1] = item
        return { SetEnabled = function(_, on) item.disabled = not on end }
    end
    function root:CreateDivider() opts.items[#opts.items + 1] = { separator = true } end
    describe(owner, root)
    return UI.ContextMenu(owner, opts)
end
