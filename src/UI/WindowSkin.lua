-- UI/WindowSkin.lua
-- One of Blizzard's windows in SuuUI's WindowFrame look (design board
-- "Window frame"), restyled in place: its clicks, tabs and panes stay
-- Blizzard's. The header grows above the window: the gilt diamond at the top
-- left, the icon and title in `header` gilt-text, the key chip, the close
-- button (Blizzard's own, with SuuUI's cross), then the tab row: the window's
-- own tab buttons as text tabs (ink-muted, gilt-text with a gilt hairline and
-- diamond when selected), over a gilt-faint rule. surface-glass under a
-- gilt-line edge behind it all.
--
--   local chrome = UI.SkinWindow(frame, {
--       title = "Character", icon = "person", binding = "TOGGLECHARACTER0",
--       close = CharacterFrameCloseButton,
--       hide = { frame.NineSlice, frame.PortraitContainer, … },  -- alpha 0
--       topInset = 20,   -- the window's own strip above its content, kept
--       under = "microMenu", -- an anchor name: the window opens lined up
--                            -- under it (its left edge, space-5 below), and
--                            -- goes back there when Blizzard places it
--   })
--   chrome:SetTabs({ { button = tab, label = "Character", short = "Char",
--                      selected = function() … end }, … })   -- in order
--   chrome:UpdateTabs()   -- after the window switched tab

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local TITLE_H = S["space-5"] + T.type.header.lineHeight -- top padding and the title line
local TAB_H = S["space-2"] + T.type.header.lineHeight + S["space-3"]
local HEAD_H = TITLE_H + S["space-3"] + TAB_H

local Chrome = {}

local function hideRegions(f)
    for _, r in ipairs({ f:GetRegions() }) do r:SetAlpha(0) end
end

-- A Blizzard tab button as a SuuUI text tab.
local function skinTab(chrome, def)
    local b = def.button
    if b.suuTab then return b.suuTab end
    hideRegions(b)
    local t = {}
    t.label = UI.Text(b, "header", "ink-muted")
    t.label:SetPoint("CENTER", 0, (S["space-3"] - S["space-2"]) / 2)
    t.label:SetShadowColor(0, 0, 0, 0.9)
    t.label:SetShadowOffset(0, -1)
    t.rule = UI.Hairline(b, "gilt-line", "both")
    t.rule:SetPoint("BOTTOMLEFT", 0, 0)
    t.rule:SetPoint("BOTTOMRIGHT", 0, 0)
    t.jewel = UI.Diamond(b, 5, "gilt")
    t.jewel:SetPoint("CENTER", b, "BOTTOM", 0, 0)
    b:HookScript("OnEnter", function() t.hover = true; chrome:UpdateTabs() end)
    b:HookScript("OnLeave", function() t.hover = false; chrome:UpdateTabs() end)
    -- Blizzard lays its tabs out again now and then: back in the row
    hooksecurefunc(b, "SetPoint", function()
        if chrome.placing then return end
        C_Timer.After(0, function() chrome:LayoutTabs() end)
    end)
    -- the selected look follows Blizzard's own selected texture (or the
    -- texture the def names: a tab system's LeftActive)
    local sel = def.selectedTexture or b.SelectedTexture or b.LeftActive
    if sel then
        for _, m in ipairs({ "Show", "Hide", "SetShown" }) do
            hooksecurefunc(sel, m, function() chrome:UpdateTabs() end)
        end
    end
    b.suuTab = t
    return t
end

function Chrome:SetTabs(list)
    self.tabs = list
    for _, def in ipairs(list) do def.skin = skinTab(self, def) end
    self:LayoutTabs()
end

-- The row, left to right; short labels and a smaller gap when the window is
-- too narrow for the full ones.
function Chrome:LayoutTabs()
    local tabs = self.tabs
    if not tabs then return end
    -- a protected window (the spells window): its parts move only out of combat
    if self.protected and InCombatLockdown() then
        self.layoutAfterCombat = true
        return
    end
    local room = self.frame:GetWidth() - S["space-5"] * 2
    local function width(short, gap)
        local w = 0
        for i, def in ipairs(tabs) do
            local text = (short and def.short) or def.label
            w = w + UI.MeasureText("header", text) + (i > 1 and gap or 0)
        end
        return w
    end
    local short, gap = false, S["space-5"]
    if width(false, gap) > room then
        gap = S["space-4"]
        if width(false, gap) > room then short = true end
    end
    self.placing = true
    local prev
    for _, def in ipairs(tabs) do
        local b = def.button
        local text = (short and def.short) or def.label
        def.skin.label:SetValue(text)
        b:SetSize(math.ceil(UI.MeasureText("header", text)), TAB_H)
        b:ClearAllPoints()
        if prev then
            b:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", gap, 0)
        else
            b:SetPoint("BOTTOMLEFT", self.head, "BOTTOMLEFT", S["space-5"], 0)
        end
        b:SetFrameLevel(self.head:GetFrameLevel() + 2)
        prev = b
    end
    self.placing = false
    self:UpdateTabs()
end

function Chrome:UpdateTabs()
    for _, def in ipairs(self.tabs or {}) do
        local t = def.skin
        local on = def.selected and def.selected() or false
        t.label:SetColor(on and "gilt-text" or (t.hover and "ink" or "ink-muted"))
        t.rule:SetShown(on)
        t.jewel:SetShown(on)
    end
end

function UI.SkinWindow(frame, opts)
    if frame.suuChrome then return frame.suuChrome end
    opts = opts or {}
    local chrome = setmetatable({ frame = frame }, { __index = Chrome })
    frame.suuChrome = chrome
    chrome.protected = frame:IsProtected() and true or false
    for _, f in pairs(opts.hide or {}) do if f and f.SetAlpha then f:SetAlpha(0) end end
    local inset = opts.topInset or 0
    local rise = HEAD_H - inset -- the header's height above the window's top

    -- the art, on the window itself (behind every pane)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(UI.RGBA("surface-glass"))
    bg:SetPoint("TOPLEFT", 0, rise)
    bg:SetPoint("BOTTOMRIGHT")
    chrome.bg = bg
    local edgeHolder = CreateFrame("Frame", nil, frame)
    edgeHolder:SetPoint("TOPLEFT", 0, rise)
    edgeHolder:SetPoint("BOTTOMRIGHT")
    edgeHolder:SetFrameLevel(frame:GetFrameLevel() + 499)
    edgeHolder:EnableMouse(false)
    chrome.edge = UI.Border(edgeHolder, "gilt-line")

    -- the header: diamond, icon, title, key, close; the tab row under it
    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT", 0, rise)
    head:SetPoint("TOPRIGHT", 0, rise)
    head:SetHeight(HEAD_H)
    head:SetFrameLevel(frame:GetFrameLevel() + 500)
    chrome.head = head
    chrome.jewel = UI.Diamond(head, 7, "gilt")
    chrome.jewel:SetPoint("CENTER", head, "TOPLEFT", 0, 0)
    local lineY = -(S["space-5"] + T.type.header.lineHeight / 2)
    local x = S["space-5"]
    if opts.icon then
        chrome.icon = head:CreateTexture(nil, "ARTWORK")
        chrome.icon:SetTexture(GLYPHS .. opts.icon .. ".tga")
        chrome.icon:SetSize(15, 15)
        chrome.icon:SetPoint("LEFT", head, "TOPLEFT", x, lineY)
        chrome.icon:SetVertexColor(UI.RGBA("gilt-text"))
        x = x + 15 + S["space-4"]
    end
    chrome.title = UI.Text(head, "header", "gilt-text")
    chrome.title:SetPoint("LEFT", head, "TOPLEFT", x, lineY)
    chrome.title:SetValue(opts.title or "")
    -- close: Blizzard's button (its click closes the window as always), SuuUI's cross
    local close = opts.close
    local right = S["space-5"]
    if close then
        hideRegions(close)
        close:SetSize(22, 22)
        close:ClearAllPoints()
        close:SetPoint("RIGHT", head, "TOPRIGHT", -S["space-5"], lineY)
        close:SetFrameLevel(head:GetFrameLevel() + 3)
        local border = UI.Border(close, "gilt-line")
        border:SetShown(false)
        local cross = UI.Cross(close, 10, "ink-muted")
        cross:SetPoint("CENTER")
        close:HookScript("OnEnter", function() border:SetShown(true); cross:SetColor("ink") end)
        close:HookScript("OnLeave", function() border:SetShown(false); cross:SetColor("ink-muted") end)
        chrome.close = close
        right = right + 22 + S["space-4"]
    end
    -- the key chip: the binding's first key
    local key = opts.binding and GetBindingKey(opts.binding)
    if key then
        chrome.key = UI.KeyChip(head, GetBindingText and GetBindingText(key, "KEY_") or key)
        chrome.key:SetPoint("RIGHT", head, "TOPRIGHT", -right, lineY)
    end
    -- the tab row's rule
    chrome.rule = head:CreateTexture(nil, "ARTWORK")
    chrome.rule:SetColorTexture(UI.RGBA("gilt-faint"))
    chrome.rule:SetHeight(1)
    chrome.rule:SetPoint("BOTTOMLEFT", S["space-5"], 0)
    chrome.rule:SetPoint("BOTTOMRIGHT", -S["space-5"], 0)

    frame:HookScript("OnSizeChanged", function() chrome:LayoutTabs() end)
    if chrome.protected then
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("PLAYER_REGEN_ENABLED")
        wait:SetScript("OnEvent", function()
            if chrome.layoutAfterCombat then
                chrome.layoutAfterCombat = false
                chrome:LayoutTabs()
            end
        end)
    end

    -- the panel-position rule: in a row under an anchor (the micro menu)
    if opts.under then
        chrome.under, chrome.rise = opts.under, rise
        ns.WindowRow.Add(chrome)
    end
    return chrome
end

-- The title, and the key chip for another binding (a window whose tabs
-- open with different keys).
function Chrome:SetTitle(text)
    self.title:SetValue(text or "")
end

function Chrome:SetBinding(binding)
    local key = binding and GetBindingKey(binding)
    if self.key then
        if key then self.key:SetKey(GetBindingText and GetBindingText(key, "KEY_") or key) end
        self.key:SetShown(key ~= nil)
    end
end

--------------------------------------------------------------------------------
-- The window row: SuuUI-headed windows open in a row under the micro menu,
-- in the order they opened, space-5 apart (the Character window, then the
-- spells window beside it, …). Opening, closing or resizing one lays the
-- row out again. A protected window moves only out of combat; the row goes
-- on from where it stands.
--------------------------------------------------------------------------------

local Row = { list = {}, seq = 0 }
ns.WindowRow = Row

-- A window asked to sit in the middle of the screen (its header included),
-- out of the row; a protected one moves out of combat only.
local function center(c)
    local f = c.frame
    if InCombatLockdown() and c.protected then
        c.placeAfterCombat = true
        return
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -(c.rise or 0) / 2)
end

function Row.Layout()
    if Row.placing then return end
    local open = {}
    Row.placing = true
    for _, c in ipairs(Row.list) do
        if c.frame:IsShown() then
            if c.centered then center(c) else open[#open + 1] = c end
        end
    end
    Row.placing = false
    if #open == 0 then return end
    table.sort(open, function(a, b) return (a.openedAt or 0) < (b.openedAt or 0) end)
    local anchor = ns.Anchors.Get(open[1].under)
    if not anchor or not anchor:IsVisible() then return end
    local as = anchor:GetEffectiveScale()
    local left, bottom = anchor:GetLeft(), anchor:GetBottom()
    if not (left and bottom) then return end
    -- in screen units (coordinates times effective scale)
    local x = left * as
    local top = bottom * as - S["space-5"] * as
    local gap = S["space-5"] * as
    Row.placing = true
    for _, c in ipairs(open) do
        local f = c.frame
        local es = f:GetEffectiveScale()
        if InCombatLockdown() and c.protected then
            c.placeAfterCombat = true
            local r = f:GetRight()
            if r then x = r * es + gap end
        else
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / es, top / es - c.rise)
            x = x + f:GetWidth() * es + gap
        end
    end
    Row.placing = false
end

-- In the middle of the screen (on) or back in the row (off): SuuUI's Talents
-- tab centres the spells window while it shows (asked for in game).
function UI.CenterWindow(frame, on)
    local chrome = frame and frame.suuChrome
    if not chrome or not chrome.under then return end
    on = on and true or false
    if chrome.centered == on then return end
    chrome.centered = on
    Row.Layout()
    Row.Queue()
end

function Row.Queue()
    if Row.queued then return end
    Row.queued = true
    C_Timer.After(0, function()
        Row.queued = false
        Row.Layout()
    end)
end

function Row.Add(chrome)
    Row.list[#Row.list + 1] = chrome
    local f = chrome.frame
    f:HookScript("OnShow", function()
        Row.seq = Row.seq + 1
        chrome.openedAt = Row.seq
        Row.Layout()
        Row.Queue()
    end)
    f:HookScript("OnHide", Row.Queue)
    f:HookScript("OnSizeChanged", Row.Queue)
    -- Blizzard places its panels again now and then (right after showing
    -- one too): back in the row at once, so no frame is drawn elsewhere
    -- (a flicker, found in game); and again a frame later
    hooksecurefunc(f, "SetPoint", function()
        if Row.placing then return end
        Row.Layout()
        Row.Queue()
    end)
    if f:IsShown() then
        Row.seq = Row.seq + 1
        chrome.openedAt = Row.seq
        Row.Queue()
    end
end

local rowWait = CreateFrame("Frame")
rowWait:RegisterEvent("PLAYER_REGEN_ENABLED")
rowWait:SetScript("OnEvent", function() Row.Queue() end)

UI.WINDOW_HEAD_H = HEAD_H
