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
    -- the selected look follows Blizzard's own selected texture
    local sel = b.SelectedTexture
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
    for _, f in ipairs(opts.hide or {}) do if f then f:SetAlpha(0) end end
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

    -- the panel-position rule: lined up under an anchor (the micro menu)
    if opts.under then
        chrome.under, chrome.rise = opts.under, rise
        hooksecurefunc(frame, "SetPoint", function()
            if chrome.placingWindow then return end
            C_Timer.After(0, function() chrome:PlaceWindow() end)
        end)
        frame:HookScript("OnShow", function() chrome:PlaceWindow() end)
    end
    return chrome
end

-- Under the anchor: the header's top left space-5 below its bottom left.
function Chrome:PlaceWindow()
    local anchor = self.under and ns.Anchors.Get(self.under)
    if not anchor or not anchor:IsVisible() or InCombatLockdown() and self.frame:IsProtected() then return end
    local f = self.frame
    local scale = anchor:GetEffectiveScale() / f:GetEffectiveScale()
    local left, bottom = anchor:GetLeft(), anchor:GetBottom()
    if not (left and bottom) then return end
    self.placingWindow = true
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale - S["space-5"] - self.rise)
    self.placingWindow = false
end

UI.WINDOW_HEAD_H = HEAD_H
