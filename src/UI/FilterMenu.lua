-- UI/FilterMenu.lua
-- A grouped filter menu (design component FilterMenu, board "Professions ·
-- Filters"): a field like Select's, the filter glyph, "Filters", a chevron;
-- "Filters · 3" (the glyph in arcane) while choices other than the defaults
-- are on. It opens a panel of groups under it (surface, gilt-line edge,
-- 292 px, space-5 padding, the groups space-4 apart, each labelled in
-- caption ink-muted):
--   one      a single choice, a Segmented row ("Show: All · Learned ·
--            Unlearned"): for filters that exclude each other
--   many     chips, several at once, none chosen = no filter; a chip carries
--            its colour as a 6 px diamond; chosen: arcane edge on arcane-soft
--   toggles  independent checkboxes ("Have materials")
-- and a foot over a gilt-faint rule: "3 filters on" (or "Defaults") and
-- Reset. Choices apply at once; a click outside or Esc closes the panel.
--
--   local menu = UI.FilterMenu(parent, {
--       groups = { { key, label, kind = "one" | "many" | "toggles",
--                    options = { { value, label, color = token } } } },
--       defaults = { show = "learned", difficulty = {}, other = {} },
--       value = { ... }, placeholder = "Filters", width = 122,
--       onChange = fn(value),   -- value by group key: one → a value,
--   })                          -- many and toggles → a list of values
--   menu:SetValue(value), menu:GetValue(), menu:Count(), menu:Close()

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local PANEL_W = 292
local CHIP_H = 24

-- One panel open at a time, and a screen-wide catcher under it that closes it.
local openMenu
local catcher = CreateFrame("Button", nil, UIParent)
catcher:SetAllPoints(UIParent)
catcher:SetFrameStrata("FULLSCREEN_DIALOG")
catcher:Hide()
catcher:RegisterForClicks("AnyDown")
catcher:SetScript("OnClick", function() if openMenu then openMenu:Close() end end)

local Menu = {}

local function copyList(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    return out
end

local function has(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

-- The value with every group filled in from the defaults.
function Menu:Full(value)
    local out = {}
    for _, g in ipairs(self.groups) do
        local v = value and value[g.key]
        if v == nil then v = self.defaults[g.key] end
        if g.kind == "one" then out[g.key] = v else out[g.key] = copyList(v) end
    end
    return out
end

-- How many choices differ from the defaults.
function Menu:Count()
    local n = 0
    for _, g in ipairs(self.groups) do
        local v, d = self.value[g.key], self.defaults[g.key]
        if g.kind == "one" then
            if v ~= d then n = n + 1 end
        else
            for _, x in ipairs(v or {}) do if not has(d, x) then n = n + 1 end end
            for _, x in ipairs(d or {}) do if not has(v, x) then n = n + 1 end end
        end
    end
    return n
end

function Menu:GetValue() return self:Full(self.value) end

function Menu:SetValue(value)
    self.value = self:Full(value)
    self:Draw()
end

function Menu:Changed()
    self:Draw()
    if self.onChange then self.onChange(self:GetValue()) end
end

-- The field and, when built, the panel's controls, from the value.
function Menu:Draw()
    local n = self:Count()
    self.text:SetValue((self.placeholder or "Filters") .. (n > 0 and (" · " .. n) or ""))
    self.glyph:SetVertexColor(UI.RGBA(n > 0 and "arcane" or "ink-muted"))
    local p = self.panel
    if not p then return end
    for _, row in ipairs(p.rows) do
        local g, v = row.group, self.value[row.group.key]
        if g.kind == "one" then
            row.control:SetValue(v)
        elseif g.kind == "many" then
            for _, chip in ipairs(row.chips) do
                local on = has(v, chip.option.value)
                chip.bg:SetShown(on)
                chip.edgeOn:SetShown(on)
                chip.label:SetColor(on and "ink" or "ink-muted")
            end
        else
            for _, box in ipairs(row.boxes) do box:SetValue(has(v, box.option.value)) end
        end
    end
    p.count:SetValue(n > 0 and (n .. (n == 1 and " filter on" or " filters on")) or "Defaults")
    p.reset:SetEnabledState(n > 0)
end

local function makeChip(menu, parent, group, option)
    local b = CreateFrame("Button", nil, parent)
    b.option = option
    UI.Fill(b, "surface-sunk"):SetAllPoints()
    UI.Border(b, "gilt-line")
    b.bg = UI.Fill(b, "arcane-soft", "BACKGROUND", 1)
    b.bg:SetAllPoints()
    b.edgeOn = CreateFrame("Frame", nil, b)
    b.edgeOn:SetAllPoints()
    UI.Border(b.edgeOn, "arcane")
    local left = S["space-4"]
    if option.color then
        b.dot = UI.Diamond(b, 6, option.color)
        b.dot:SetPoint("LEFT", S["space-4"] + 3, 0)
        left = S["space-4"] + 6 + S["space-3"]
    end
    b.label = UI.Text(b, "label", "ink-muted")
    b.label:SetPoint("LEFT", left, 0)
    b.label:SetValue(option.label)
    b:SetSize(math.ceil(left + b.label:GetUnboundedStringWidth() + S["space-4"]), CHIP_H)
    b:SetScript("OnClick", function()
        local list = menu.value[group.key]
        if has(list, option.value) then
            local kept = {}
            for _, x in ipairs(list) do if x ~= option.value then kept[#kept + 1] = x end end
            menu.value[group.key] = kept
        else
            list[#list + 1] = option.value
        end
        menu:Changed()
    end)
    return b
end

function Menu:Build()
    local menu = self
    local p = CreateFrame("Frame", nil, UIParent)
    self.panel = p
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel(catcher:GetFrameLevel() + 10)
    p:SetWidth(PANEL_W)
    p:EnableMouse(true)
    p:SetClampedToScreen(true)
    UI.Fill(p, "surface"):SetAllPoints()
    UI.Border(p, "gilt-line")
    UI.Shadow(p, "shadow-panel")
    p.rows = {}
    local pad, inner = S["space-5"], PANEL_W - S["space-5"] * 2
    local y = pad
    for gi, g in ipairs(self.groups) do
        if gi > 1 then y = y + S["space-4"] end
        local row = { group = g }
        local label = UI.Text(p, "caption", "ink-muted")
        label:SetPoint("TOPLEFT", pad, -y)
        label:SetValue(g.label)
        y = y + T.type.caption.lineHeight + S["space-2"]
        if g.kind == "one" then
            row.control = UI.Segmented(p, { options = g.options, onChange = function(v)
                menu.value[g.key] = v
                menu:Changed()
            end })
            row.control:SetPoint("TOPLEFT", pad, -y)
            y = y + row.control:GetHeight()
        elseif g.kind == "many" then
            -- chips, wrapping onto the next line
            row.chips = {}
            local x = 0
            for _, o in ipairs(g.options) do
                local chip = makeChip(menu, p, g, o)
                if x > 0 and x + chip:GetWidth() > inner then
                    x = 0
                    y = y + CHIP_H + S["space-2"]
                end
                chip:SetPoint("TOPLEFT", pad + x, -y)
                x = x + chip:GetWidth() + S["space-2"]
                row.chips[#row.chips + 1] = chip
            end
            y = y + CHIP_H
        else
            row.boxes = {}
            for i, o in ipairs(g.options) do
                if i > 1 then y = y + S["space-2"] end
                local box = UI.Checkbox(p, { label = o.label, onChange = function(on)
                    local list = menu.value[g.key]
                    if on then
                        if not has(list, o.value) then list[#list + 1] = o.value end
                    else
                        local kept = {}
                        for _, x in ipairs(list) do if x ~= o.value then kept[#kept + 1] = x end end
                        menu.value[g.key] = kept
                    end
                    menu:Changed()
                end })
                box.option = o
                box:SetPoint("TOPLEFT", pad, -y)
                y = y + box:GetHeight()
                row.boxes[#row.boxes + 1] = box
            end
        end
        p.rows[#p.rows + 1] = row
    end
    -- the foot: how many are on, and Reset
    y = y + S["space-5"]
    local rule = UI.Fill(p, "gilt-faint", "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", pad, -y)
    rule:SetPoint("TOPRIGHT", -pad, -y)
    y = y + 1 + S["space-4"]
    p.reset = UI.Button(p, { text = "Reset", variant = "quiet", onClick = function()
        menu.value = menu:Full(nil)
        menu:Changed()
    end })
    p.reset:SetPoint("TOPRIGHT", -pad, -y)
    p.count = UI.Text(p, "caption", "ink-muted")
    p.count:SetPoint("LEFT", p, "TOPLEFT", pad, -(y + p.reset:GetHeight() / 2))
    y = y + p.reset:GetHeight() + pad
    p:SetHeight(y)
    -- Esc closes it (out of combat: the key can't be held back in one)
    p:EnableKeyboard(true)
    p:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            menu:Close()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    p:Hide()
end

function Menu:Open()
    if openMenu and openMenu ~= self then openMenu:Close() end
    if not self.panel then self:Build() end
    local p = self.panel
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -S["space-2"])
    self:Draw()
    openMenu = self
    catcher:Show()
    p:Show()
    self.chevron:SetTexture(GLYPHS .. "chevronDown.tga")
    self.edge:SetColor("arcane")
end

function Menu:Close()
    if self.panel then self.panel:Hide() end
    if openMenu == self then
        openMenu = nil
        catcher:Hide()
    end
    self.edge:SetColor("gilt-line")
end

function UI.FilterMenu(parent, opts)
    local f = CreateFrame("Button", nil, parent)
    Mixin(f, Menu)
    f.groups, f.onChange, f.placeholder = opts.groups or {}, opts.onChange, opts.placeholder
    f.defaults = opts.defaults or {}
    f:SetSize(opts.width or 140, 30)
    UI.Fill(f, "surface-sunk"):SetAllPoints()
    f.edge = UI.Border(f, "gilt-line")
    f.glyph = f:CreateTexture(nil, "ARTWORK")
    f.glyph:SetTexture(GLYPHS .. "filter.tga")
    f.glyph:SetSize(14, 14)
    f.glyph:SetPoint("LEFT", S["space-4"], 0)
    f.chevron = f:CreateTexture(nil, "ARTWORK")
    f.chevron:SetTexture(GLYPHS .. "chevronDown.tga")
    f.chevron:SetSize(12, 12)
    f.chevron:SetPoint("RIGHT", -S["space-4"], 0)
    f.chevron:SetVertexColor(UI.RGBA("ink-muted"))
    f.text = UI.Text(f, "body", "ink")
    f.text:SetPoint("LEFT", f.glyph, "RIGHT", S["space-3"], 0)
    f.text:SetPoint("RIGHT", f.chevron, "LEFT", -S["space-3"], 0)
    f.text:SetJustifyH("LEFT")
    f:SetScript("OnClick", function(self)
        if openMenu == self then self:Close() else self:Open() end
    end)
    f:SetScript("OnEnter", function(self) if openMenu ~= self then self.edge:SetColor("gilt") end end)
    f:SetScript("OnLeave", function(self) if openMenu ~= self then self.edge:SetColor("gilt-line") end end)
    f:HookScript("OnHide", function(self) self:Close() end)
    f.value = f:Full(opts.value)
    f:Draw()
    return f
end
