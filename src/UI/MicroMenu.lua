-- UI/MicroMenu.lua
-- The micro menu (design board "Micro menu and XP"): a glass panel of
-- `menu-button` square buttons, space-2 apart, each a line glyph (18px, ink)
-- that lifts to surface-raised with a gilt-line edge on hover; an arcane
-- diamond in its top right corner while there's something to act on there.
--
--   local m = UI.MicroMenu(parent, { name = "SuuUIMicroMenu" })
--   m:SetItems({ { key, glyph, label, click = "CharacterMicroButton" | onClick = fn }, ... })
--   m:SetAlert(key, text or nil)
--   m:SetActive(key, on)      -- its window is open: the hover look stays
--
-- An item with `click` is a secure button clicking that Blizzard micro
-- button (so it works in combat wherever the game allows the window); one
-- with `onClick` is a plain button. SetItems lays the menu out again, out of
-- combat only (secure buttons): call it then.

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"

local Menu = {}
ns.Mixins.MicroMenu = Menu

-- The tooltip: the item's label, and the key from Blizzard's own tooltip.
local function keyOf(blizzard)
    local b = blizzard and _G[blizzard]
    local tip = b and b.tooltipText
    if type(tip) ~= "string" then return nil end
    local key = tip:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("%(([^%)]+)%)%s*$")
    return key
end

local function buildButton(m, item)
    local secure = item.click ~= nil
    local b = CreateFrame("Button", m.name and (m.name .. item.key) or nil, m, secure and "SecureActionButtonTemplate" or nil)
    local px = UI.Size("menu-button")
    b:SetSize(px, px)
    -- both: a secure button acts on the one the game's ActionButtonUseKeyDown names
    if secure then b:RegisterForClicks("AnyDown", "AnyUp") else b:RegisterForClicks("LeftButtonUp") end
    if secure then
        b:SetAttribute("type", "click")
        b:SetAttribute("clickbutton", _G[item.click])
    else
        b:SetScript("OnClick", function() if item.onClick then item.onClick() end end)
    end
    b.hover = UI.Fill(b, "surface-raised", "BACKGROUND")
    b.hover:SetAllPoints()
    b.hover:Hide()
    b.edge = UI.Border(b, "gilt-line")
    b.edge:SetShown(false)
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetSize(18, 18)
    b.glyph:SetPoint("CENTER")
    b.glyph:SetTexture(GLYPHS .. item.glyph .. ".tga")
    b.glyph:SetVertexColor(UI.RGBA("ink"))
    -- the alert: a 6px arcane diamond, 3px in from the top right, glowing
    b.alert = CreateFrame("Frame", nil, b)
    b.alert:SetSize(8, 8)
    b.alert:SetPoint("CENTER", b, "TOPRIGHT", -6, -6)
    b.alert:SetFrameLevel(b:GetFrameLevel() + 2)
    b.alertRing = UI.Diamond(b.alert, 8, "surface", "OVERLAY", 6)
    b.alertRing:SetPoint("CENTER")
    b.alertDot = UI.Diamond(b.alert, 6, "arcane", "OVERLAY", 7)
    b.alertDot:SetPoint("CENTER")
    b.alertGlow = UI.Shadow(b.alert, "glow-arcane")
    b.alert:Hide()
    b.item = item
    b:HookScript("OnEnter", function(self)
        self.hover:Show()
        self.edge:SetShown(true)
        local key = keyOf(self.item.click)
        UI.ShowTooltip(self, { title = self.item.label, subtitle = key and ("Key: " .. key) or nil,
            description = self.alertText })
    end)
    b:HookScript("OnLeave", function(self)
        self.hover:SetShown(self.active and true or false)
        self.edge:SetShown(self.active and true or false)
        UI.HideTooltip()
    end)
    b:HookScript("OnMouseDown", function(self) self.glyph:SetPoint("CENTER", 0, -1) end)
    b:HookScript("OnMouseUp", function(self) self.glyph:SetPoint("CENTER", 0, 0) end)
    return b
end

function Menu:SetItems(items)
    if InCombatLockdown() then return false end
    self.items = items
    local px, gap, pad = UI.Size("menu-button"), S["space-2"], S["space-2"]
    for _, b in pairs(self.buttons) do b:Hide() end
    local x = pad
    for _, item in ipairs(items) do
        local b = self.buttons[item.key]
        if not b then
            b = buildButton(self, item)
            self.buttons[item.key] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, -pad)
        b:Show()
        x = x + px + gap
    end
    self:SetSize(math.max(1, x - gap + pad), px + pad * 2)
    return true
end

function Menu:SetActive(key, on)
    local b = self.buttons[key]
    on = on and true or false
    if not b or b.active == on then return end
    b.active = on
    if not b:IsMouseOver() then
        b.hover:SetShown(on)
        b.edge:SetShown(on)
    end
end

function Menu:SetAlert(key, text)
    local b = self.buttons[key]
    if not b then return end
    b.alertText = text
    b.alert:SetShown(text ~= nil)
end

function UI.MicroMenu(parent, opts)
    opts = opts or {}
    local m = CreateFrame("Frame", opts.name, parent)
    Mixin(m, Menu)
    m.name = opts.name
    m.buttons = {}
    UI.Fill(m, "surface-glass", "BACKGROUND"):SetAllPoints()
    UI.Border(m, "gilt-line")
    UI.Shadow(m, "shadow-panel")
    m:SetSize(1, 1)
    ns.Extend.Add("micromenu", m, { name = opts and opts.name })
    return m
end
