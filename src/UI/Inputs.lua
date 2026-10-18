-- UI/Inputs.lua
-- The settings controls: Toggle, Checkbox, Segmented, Slider, Stepper and
-- TextField (Select has its own file). Every control shares one shape:
--
--   ctl:SetValue(v)            shows v; never calls onChange
--   ctl.onChange = fn(v)       called when the player changes it
--   ctl:SetDisabled(disabled)  dims it to opacity-disabled and stops input
--
-- Arcane marks the value you chose, as it marks what you can act on in the HUD.

local _, ns = ...

local UI, T, Motion, Settings = ns.UI, ns.Tokens, ns.Motion, ns.Settings
local S = T.space

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"

local function reduced()
    return Settings.Ready() and Settings.Get("ui", "reducedMotion")
end

--------------------------------------------------------------------------------
-- Glyphs: strokes drawn from a white texture, so they take any token colour.
--------------------------------------------------------------------------------

local function stroke(parent, length, angle, thickness)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(WHITE)
    t:SetSize(length, thickness or 1.5)
    t:SetRotation(math.rad(angle or 0))
    return t
end

local function glyph(parent, size, color, strokes)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(size, size)
    g.parts = {}
    for _, s in ipairs(strokes) do
        local t = stroke(g, s[1], s[2], s[5])
        t:SetPoint("CENTER", s[3] or 0, s[4] or 0)
        g.parts[#g.parts + 1] = t
    end
    function g:SetColor(name)
        for _, t in ipairs(self.parts) do UI.Paint(t, name) end
    end
    g:SetColor(color or "ink-muted")
    return g
end

-- A downward chevron, a minus and a plus.
function UI.Chevron(parent, color)
    return glyph(parent, 12, color, { { 6, -45, -2, 0 }, { 6, 45, 2, 0 } })
end

function UI.Minus(parent, color)
    return glyph(parent, 12, color, { { 9, 0 } })
end

function UI.Plus(parent, color)
    return glyph(parent, 12, color, { { 9, 0 }, { 9, 90 } })
end

-- A check mark in a token colour.
function UI.Check(parent, size, color)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(CHECK)
    t:SetDesaturated(true)
    t:SetSize(size, size)
    UI.Paint(t, color or "on-signal")
    return t
end

-- Shared disabled behaviour for controls built on one frame.
local function setDisabled(self, disabled)
    self.disabled = disabled and true or false
    self:SetAlpha(self.disabled and T.opacity["opacity-disabled"] or 1)
    if self.EnableMouse then self:EnableMouse(not self.disabled) end
end

-- An EditBox given its text while hidden can open with that text scrolled
-- out of view, or not drawn, until it changes: show it from the start and
-- draw it again each time the box is shown.
local function showText(e, text)
    e:SetText(text)
    e:SetCursorPosition(0)
end

local function redrawOnShow(e)
    e:HookScript("OnShow", function(self)
        if self:HasFocus() then return end
        local text = self:GetText()
        self:SetText("")
        showText(self, text)
    end)
end

--------------------------------------------------------------------------------
-- Toggle: a 34x18 track with the Jewel's diamond as its knob.
--------------------------------------------------------------------------------

local Toggle = {}

local KNOB_OFF, KNOB_ON = 9, 25

function Toggle:SetValue(on, animate)
    on = on and true or false
    local was = self.value
    self.value = on
    UI.PaintFill(self.bg, on and "arcane-soft" or "surface-sunk")
    self.border:SetColor(on and "arcane" or (self:IsMouseOver() and "gilt" or "gilt-line"))
    UI.Paint(self.knob, on and "arcane" or "ink-muted")
    local to = on and KNOB_ON or KNOB_OFF
    self:SetScript("OnUpdate", nil)
    self.knob:ClearAllPoints()
    if animate and was ~= nil and was ~= on and not reduced() then
        -- Slide over dur-fast with an ease-out (a cubic).
        local from, start, dur = on and KNOB_OFF or KNOB_ON, GetTime(), T.duration["dur-fast"]
        self.knob:SetPoint("CENTER", self, "TOPLEFT", from, -9)
        self:SetScript("OnUpdate", function(b)
            local t = math.min(1, (GetTime() - start) / dur)
            local e = 1 - (1 - t) ^ 3
            b.knob:SetPoint("CENTER", b, "TOPLEFT", from + (to - from) * e, -9)
            if t >= 1 then b:SetScript("OnUpdate", nil) end
        end)
    else
        self.knob:SetPoint("CENTER", self, "TOPLEFT", to, -9)
    end
end

Toggle.SetDisabled = setDisabled

function UI.Toggle(parent, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent)
    Mixin(b, Toggle)
    b:SetSize(34, 18)
    b.bg = UI.Fill(b, "surface-sunk")
    b.bg:SetAllPoints()
    b.border = UI.Border(b, "gilt-line")
    b.knob = UI.Diamond(b, 8, "ink-muted")
    b.onChange = opts.onChange
    b:SetScript("OnClick", function(self)
        if self.disabled then return end
        self:SetValue(not self.value, true)
        if self.onChange then self.onChange(self.value) end
    end)
    b:SetScript("OnEnter", function(self) if not self.value then self.border:SetColor("gilt") end end)
    b:SetScript("OnLeave", function(self) if not self.value then self.border:SetColor("gilt-line") end end)
    b:SetValue(opts.value)
    return b
end

--------------------------------------------------------------------------------
-- Checkbox: a 16px box and a body label; the whole row is the hit area.
--------------------------------------------------------------------------------

local Checkbox = {}

function Checkbox:SetValue(on)
    self.value = on and true or false
    UI.PaintFill(self.box, self.value and "arcane" or "surface-sunk")
    self.boxBorder:SetColor(self.value and "arcane" or "gilt-line")
    self.check:SetShown(self.value)
end

Checkbox.SetDisabled = setDisabled

function UI.Checkbox(parent, opts)
    opts = opts or {}
    local size = opts.size or 16
    local b = CreateFrame("Button", nil, parent)
    Mixin(b, Checkbox)
    b.boxFrame = CreateFrame("Frame", nil, b)
    b.boxFrame:SetSize(size, size)
    b.boxFrame:SetPoint("LEFT")
    b.box = UI.Fill(b.boxFrame, "surface-sunk")
    b.box:SetAllPoints()
    b.boxBorder = UI.Border(b.boxFrame, "gilt-line")
    b.check = UI.Check(b.boxFrame, size - 2, "on-signal")
    b.check:SetPoint("CENTER")
    local w = size
    if opts.label then
        b.label = UI.Text(b, "body", "ink")
        b.label:SetPoint("LEFT", b.boxFrame, "RIGHT", S["space-4"], 0)
        b.label:SetValue(opts.label)
        w = w + S["space-4"] + b.label:GetUnboundedStringWidth()
    end
    b:SetSize(opts.width or w, math.max(22, size))
    b.onChange = opts.onChange
    b:SetScript("OnClick", function(self)
        if self.disabled then return end
        self:SetValue(not self.value)
        if self.onChange then self.onChange(self.value) end
    end)
    b:SetScript("OnEnter", function(self) if not self.value then self.boxBorder:SetColor("gilt") end end)
    b:SetScript("OnLeave", function(self) if not self.value then self.boxBorder:SetColor("gilt-line") end end)
    b:SetValue(opts.value)
    return b
end

--------------------------------------------------------------------------------
-- Segmented: two to five named options in one frame.
--   options = { { value = 1, label = "Bar 1" }, { value = 2, label = "Bars 1 and 2", disabled = true, reason = "…" } }
--------------------------------------------------------------------------------

local Segmented = {}

function Segmented:SetValue(v)
    self.value = v
    for _, o in ipairs(self.buttons) do
        local on = o.option.value == v
        o.bg:SetShown(on)
        o.edge:SetShown(on)
        o.label:SetColor(on and "arcane" or (o.option.disabled and "ink-faint" or "ink-muted"))
    end
end

Segmented.SetDisabled = setDisabled

function UI.Segmented(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Segmented)
    UI.Fill(f, "surface-sunk"):SetAllPoints()
    UI.Border(f, "gilt-line")
    f.buttons = {}
    f.onChange = opts.onChange
    local x = 3
    for _, option in ipairs(opts.options) do
        local b = CreateFrame("Button", nil, f)
        b.option = option
        b.bg = UI.Fill(b, "arcane-soft")
        b.bg:SetAllPoints()
        b.edge = UI.Border(b, "arcane")
        b.label = UI.Text(b, "label", "ink-muted")
        b.label:SetPoint("CENTER")
        b.label:SetValue(option.label)
        b:SetSize(b.label:GetUnboundedStringWidth() + S["space-5"] * 2, 24)
        b:SetPoint("TOPLEFT", x, -3)
        x = x + b:GetWidth() + 2
        b:SetScript("OnClick", function(self)
            if f.disabled or self.option.disabled then return end
            f:SetValue(self.option.value)
            if f.onChange then f.onChange(self.option.value) end
        end)
        b:SetScript("OnEnter", function(self)
            if self.option.value ~= f.value and not self.option.disabled and not f.disabled then
                self.label:SetColor("ink")
            end
            if self.option.disabled and self.option.reason then
                UI.ShowTooltip(self, { title = self.option.label, description = self.option.reason })
            end
        end)
        b:SetScript("OnLeave", function(self)
            f:SetValue(f.value)
            UI.HideTooltip()
        end)
        f.buttons[#f.buttons + 1] = b
    end
    f:SetSize(x + 1, 30)
    f:SetValue(opts.value)
    return f
end

--------------------------------------------------------------------------------
-- Slider: the value in numeric on top, a 4px track filled arcane up to the
-- value, and an 11px ink diamond thumb with an arcane edge. Live while dragging.
--   { min, max, step, value, width = 200, unit = "px", format = fn(v) -> text,
--     live = true }   -- false: onChange only when the drag ends (for settings that
--                     -- move the very window being dragged in, like the scale)
--------------------------------------------------------------------------------

local Slider = {}

local function snap(v, min, step)
    if not step or step <= 0 then return v end
    return min + math.floor((v - min) / step + 0.5) * step
end

function Slider:ShowValue(v)
    local text = self.format and self.format(v) or (self.unit and (v .. self.unit) or tostring(v))
    self.valueText:SetValue(text)
end

function Slider:SetValue(v)
    self.value, self.committed = v, v
    self.updating = true
    self.slider:SetValue(v)
    self.updating = false
    self:ShowValue(v)
end

Slider.SetDisabled = function(self, disabled)
    setDisabled(self, disabled)
    self.slider:SetEnabled(not self.disabled)
    self.slider:EnableMouse(not self.disabled)
end

-- the value line's height comes from the numeric style, which a theme can change
local sliders = setmetatable({}, { __mode = "k" })
local function sliderHeight()
    return T.type.numeric.lineHeight + S["space-2"] + 18
end
ns.Events.On("SUUUI_THEME_CHANGED", function()
    for f in pairs(sliders) do f:SetHeight(sliderHeight()) end
end, "UI.Slider")

function UI.Slider(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Slider)
    local width = opts.width or 200
    f:SetSize(width, sliderHeight())
    sliders[f] = true
    f.min, f.max, f.step = opts.min or 0, opts.max or 1, opts.step
    f.unit, f.format, f.onChange = opts.unit, opts.format, opts.onChange
    f.live = opts.live ~= false

    f.valueText = UI.Text(f, "numeric", "ink")
    f.valueText:SetPoint("TOPRIGHT")
    if opts.label then
        f.label = UI.Text(f, "label", "ink")
        f.label:SetPoint("TOPLEFT")
        f.label:SetValue(opts.label)
    end

    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("BOTTOMLEFT")
    s:SetPoint("BOTTOMRIGHT")
    s:SetHeight(18)
    s:SetMinMaxValues(f.min, f.max)
    if f.step then
        s:SetValueStep(f.step)
        s:SetObeyStepOnDrag(true)
    end
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(13, 13)
    thumb:SetColorTexture(0, 0, 0, 0)
    s:SetThumbTexture(thumb)
    local track = UI.Fill(s, "track", "BACKGROUND")
    track:SetHeight(4)
    track:SetPoint("LEFT", 6, 0)
    track:SetPoint("RIGHT", -6, 0)
    local fill = UI.Fill(s, "arcane", "ARTWORK")
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    -- The thumb: an ink diamond with a 1px surface border and a 1px arcane edge.
    for i, d in ipairs({ { 13, "arcane" }, { 11, "surface" }, { 9, "ink" } }) do
        local dia = UI.Diamond(s, d[1], d[2], "OVERLAY", 4 + i)
        dia:SetPoint("CENTER", thumb, "CENTER")
    end
    -- No mouse wheel: it belongs to the page the slider sits on, which scrolls.
    local function commit()
        if f.pending ~= nil and f.pending ~= f.committed then
            f.committed = f.pending
            if f.onChange then f.onChange(f.pending) end
        end
        f.pending = nil
    end
    s:SetScript("OnMouseUp", commit)
    s:SetScript("OnValueChanged", function(_, v)
        if f.updating or f.disabled then return end
        v = snap(v, f.min, f.step)
        if v == f.value then return end
        f.value = v
        f:ShowValue(v)
        f.pending = v
        if f.live then commit() end
    end)
    f.slider = s
    f:SetValue(opts.value or f.min)
    return f
end

--------------------------------------------------------------------------------
-- Stepper: minus, the number (typed or nudged, clamped to min..max and to a
-- whole number of steps from min), the unit, plus.
--   { min, max, step = 1, value, unit = "px" }
--------------------------------------------------------------------------------

local Stepper = {}

function Stepper:Clamp(v)
    v = tonumber(v) or self.value or 0
    if self.step and self.step > 0 then
        local base = self.min or 0
        v = base + math.floor((v - base) / self.step + 0.5) * self.step
        v = tonumber(("%.4f"):format(v)) -- no float noise (0.1 steps make 0.30000000000000004)
    end
    if self.min then v = math.max(self.min, v) end
    if self.max then v = math.min(self.max, v) end
    return v
end

function Stepper:SetValue(v)
    self.value = v
    showText(self.edit, tostring(v or ""))
end

function Stepper:Commit(v)
    if self.disabled then
        self:SetValue(self.value) -- drop what was typed
        return
    end
    v = self:Clamp(v)
    local changed = v ~= self.value
    self:SetValue(v)
    if changed and self.onChange then self.onChange(v) end
end

Stepper.SetDisabled = function(self, disabled)
    setDisabled(self, disabled)
    self.edit:EnableMouse(not self.disabled)
    self.minus:EnableMouse(not self.disabled)
    self.plus:EnableMouse(not self.disabled)
    if self.disabled then self.edit:ClearFocus() end
end

local function stepButton(parent, make)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 28)
    b.hover = UI.Fill(b, "surface-raised")
    b.hover:SetAllPoints()
    b.hover:Hide()
    b.glyph = make(b, "ink-muted")
    b.glyph:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self) self.hover:Show(); self.glyph:SetColor("ink") end)
    b:SetScript("OnLeave", function(self) self.hover:Hide(); self.glyph:SetColor("ink-muted") end)
    return b
end

function UI.Stepper(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Stepper)
    f.min, f.max, f.step, f.onChange = opts.min, opts.max, opts.step or 1, opts.onChange
    UI.Fill(f, "surface-sunk"):SetAllPoints()
    UI.Border(f, "gilt-line")

    f.minus = stepButton(f, UI.Minus)
    f.minus:SetPoint("LEFT", 1, 0)
    f.minus:SetScript("OnClick", function() if not f.disabled then f:Commit((f.value or 0) - f.step) end end)

    local e = CreateFrame("EditBox", nil, f)
    e:SetAutoFocus(false)
    e:SetFontObject(ns.Fonts.Get("numeric"))
    e:SetJustifyH("CENTER")
    e:SetSize(44, 28)
    e:SetPoint("LEFT", f.minus, "RIGHT")
    e:SetScript("OnEnterPressed", function(self) f:Commit(self:GetText()); self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) f:SetValue(f.value); self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(self) f:Commit(self:GetText()) end)
    redrawOnShow(e)
    f.edit = e

    local right = e
    if opts.unit then
        f.unitText = UI.Text(f, "caption", "ink-muted")
        f.unitText:SetValue(opts.unit)
        f.unitText:SetPoint("LEFT", e, "RIGHT", 0, 0)
        right = f.unitText
    end
    f.plus = stepButton(f, UI.Plus)
    f.plus:SetPoint("LEFT", right, "RIGHT", opts.unit and S["space-2"] or 0, 0)
    f.plus:SetScript("OnClick", function() if not f.disabled then f:Commit((f.value or 0) + f.step) end end)

    local w = 26 + 44 + 26 + 2 + (opts.unit and (f.unitText:GetUnboundedStringWidth() + S["space-2"]) or 0)
    f:SetSize(w, 30)
    f:SetValue(opts.value)
    return f
end

--------------------------------------------------------------------------------
-- TextField: a 30px field on surface-sunk with a placeholder.
--   { width, placeholder, value, onChange = fn(text) on Enter or focus lost,
--     onTextChanged = fn(text) on every keystroke }
--------------------------------------------------------------------------------

local TextField = {}

function TextField:SetValue(text)
    self.value = text or ""
    self.lastTyped = self.value -- set from code: not typing
    showText(self.edit, self.value)
    self.placeholder:SetShown(self.value == "" and not self.edit:HasFocus())
end

function TextField:GetValue()
    return self.edit:GetText()
end

TextField.SetDisabled = function(self, disabled)
    setDisabled(self, disabled)
    self.edit:EnableMouse(not self.disabled)
    if self.disabled then self.edit:ClearFocus() end
end

function UI.TextField(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, TextField)
    f:SetSize(opts.width or 200, 30)
    UI.Fill(f, "surface-sunk"):SetAllPoints()
    f.border = UI.Border(f, "gilt-line")
    f.onChange, f.onTextChanged = opts.onChange, opts.onTextChanged

    local e = CreateFrame("EditBox", nil, f)
    e:SetAutoFocus(false)
    e:SetFontObject(ns.Fonts.Get("body"))
    e:SetPoint("TOPLEFT", S["space-4"], 0)
    e:SetPoint("BOTTOMRIGHT", -S["space-4"], 0)
    e:SetTextInsets(0, 0, 0, 0)
    redrawOnShow(e)
    f.edit = e

    f.placeholder = UI.Text(f, "body", "ink-muted")
    f.placeholder:SetPoint("LEFT", S["space-4"], 0)
    f.placeholder:SetValue(opts.placeholder or "")

    local function commit(self)
        local text = self:GetText()
        if text ~= f.value then
            f.value = text
            if f.onChange then f.onChange(text) end
        end
    end
    e:SetScript("OnEditFocusGained", function() f.placeholder:Hide(); f.border:SetColor("arcane") end)
    e:SetScript("OnEditFocusLost", function(self)
        f.border:SetColor("gilt-line")
        f.placeholder:SetShown(self:GetText() == "")
        commit(self)
    end)
    e:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- what's typed, live: any change while the field has focus (the game
    -- doesn't always flag typing as user input on Forever)
    e:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if self:HasFocus() and text ~= f.lastTyped then
            f.lastTyped = text
            if f.onTextChanged then f.onTextChanged(text) end
        end
        if self:HasFocus() then f.placeholder:Hide() end
    end)
    f:SetValue(opts.value or "")
    return f
end

--------------------------------------------------------------------------------
-- MoneyInput (0.16): an amount as three fields, gold, silver and copper, each
-- followed by its coin letter in the coin colour.
--
--   local m = UI.MoneyInput(parent, { value = copper, onChange = fn(copper) })
--   m:GetCopper(), m:SetCopper(copper), m:Clear(), m:SetDisabled(disabled)
--------------------------------------------------------------------------------

function UI.MoneyInput(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(200, 30)
    local fields = {}
    local x = 0
    local function changed()
        if opts.onChange then opts.onChange(f:GetCopper()) end
    end
    for _, d in ipairs({ { "g", "coin-gold", 70, 6 }, { "s", "coin-silver", 44, 2 }, { "c", "coin-copper", 44, 2 } }) do
        local t = UI.TextField(f, { width = d[3], onTextChanged = changed })
        t.edit:SetNumeric(true)
        t.edit:SetMaxLetters(d[4])
        t:SetPoint("LEFT", x, 0)
        local unit = UI.Text(f, "label", d[2])
        unit:SetValue(d[1])
        unit:SetPoint("LEFT", t, "RIGHT", 3, 0)
        x = x + d[3] + 14
        fields[#fields + 1] = t
    end
    f:SetWidth(x)
    f.fields = fields
    function f:GetCopper()
        local g = tonumber(fields[1].edit:GetText()) or 0
        local s = tonumber(fields[2].edit:GetText()) or 0
        local c = tonumber(fields[3].edit:GetText()) or 0
        return g * 10000 + math.min(99, s) * 100 + math.min(99, c)
    end
    function f:SetCopper(copper)
        copper = math.max(0, math.floor(copper or 0))
        local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
        fields[1]:SetValue(g > 0 and tostring(g) or "")
        fields[2]:SetValue((s > 0 or g > 0) and tostring(s) or "")
        fields[3]:SetValue(tostring(c))
    end
    function f:Clear() for _, t in ipairs(fields) do t:SetValue("") end end
    function f:SetDisabled(disabled) for _, t in ipairs(fields) do t:SetDisabled(disabled) end end
    if opts.value then f:SetCopper(opts.value) end
    return f
end
