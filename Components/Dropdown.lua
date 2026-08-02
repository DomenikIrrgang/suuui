local ipairs = ipairs
local S = SuuUI.UISignals

-- Option rows hold text, so their height is floored against the font size token.
local function rowHeight()
    return SuuUI.Theme:GetControlHeight("sizeControlMd")
end

local DdMeta = {}
DdMeta.__index = DdMeta

function DdMeta:GetWidth()     return self._f:GetWidth() end
function DdMeta:GetHeight()    return self._f:GetHeight() end
function DdMeta:IsShown()      return self._f:IsShown() end
function DdMeta:GetFrame()     return self._f end

--- Sets an explicit size, dropping token-driven height.
-- @param w number
-- @param h number
function DdMeta:SetSize(w, h)
    self._autoH = false
    self._f:SetSize(w, h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

function DdMeta:Show()
    self._f:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function DdMeta:Hide()
    self._f:Hide()
    self:_closePanel()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

function DdMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._box:Destroy()
    self._rowList:Destroy()
    -- The floating host is shared: drop our panel, never destroy the host
    self._panelHost:Remove(self._panel)
    self._panel:Hide()
    if self._clickAway then
        self._clickAway:Destroy()
        self._clickAway = nil
    end
end

--- Enables or disables the dropdown. Emits ENABLED_CHANGED.
-- @param en bool
function DdMeta:SetEnabled(en)
    self._enabled = en
    self._f:EnableMouse(en)
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
end

--- Returns the selected option value.
-- @return any
function DdMeta:GetValue()
    return self._value
end

--- Sets selected value and updates label. Does not emit VALUE_CHANGED.
-- @param value any
function DdMeta:SetValue(value)
    self._value = value
    for _, opt in ipairs(self._options) do
        if opt.value == value then
            self._selText:SetText(opt.label)
            return
        end
    end
end

--- Updates the available options array. Closes panel if open.
-- @param options table  Array of { value, label }
function DdMeta:SetOptions(options)
    self._options = options or {}
    self:_closePanel()
    if self._value then self:SetValue(self._value) end
end

function DdMeta:_closePanel()
    if self._panel and self._panel:IsShown() then
        SuuUI.Anim.Presets.FadeOut(self._panel, SuuUI.Theme:GetToken("animFast"))
        if self._clickAway then self._clickAway:Disarm() end
    end
end

-- Builds or reuses one option row inside the row list container
function DdMeta:_row(index, opt)
    local T   = SuuUI.Theme
    local bg  = T:GetToken("colorBgAlt")
    local bd  = T:GetToken("colorBorder")
    local bw  = T:GetToken("borderWidth") or 1

    local row = self._rows[index]
    if not row then
        row = CreateFrame("Frame", nil, self._panel, "BackdropTemplate")
        row:EnableMouse(true)
        row._box = SuuUI.Layout:CreateContainer({ host = row, layout = "stack" })
        row._lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row._box:Add(row._lbl, { valign = "center", inset = { left = 6, right = 6 } })
        self._rows[index] = row
        self._rowList:Add(row, { width = "fill", height = rowHeight() })
    else
        self._rowList:SetChildProps(row, { width = "fill", height = rowHeight() })
    end

    row:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then row:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end

    row._lbl:SetFont(T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeMd") or 13, "")
    row._lbl:SetText(opt.label)
    local tc = T:GetToken("colorText")
    if tc then row._lbl:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end

    local optVal, optLabel = opt.value, opt.label
    row:SetScript("OnEnter", function()
        local hov = T:GetToken("colorBgHover")
        if hov then row:SetBackdropColor(hov[1], hov[2], hov[3], hov[4]) end
    end)
    row:SetScript("OnLeave", function()
        if bg then row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    end)
    row:SetScript("OnMouseUp", function()
        local old = self._value
        self._value = optVal
        self._selText:SetText(optLabel)
        self:_closePanel()
        if self._onChange then self._onChange(optVal) end
        S:Emit(self, S.SIGNALS.VALUE_CHANGED, optVal, old)
    end)

    row:Show()
    return row
end

function DdMeta:_openPanel()
    local T   = SuuUI.Theme
    local bg  = T:GetToken("colorBgAlt")
    local bd  = T:GetToken("colorBorder")
    local bw  = T:GetToken("borderWidth") or 1
    local gap = T:GetToken("spaceXs") or 4
    local panel = self._panel

    for _, row in ipairs(self._rows) do row:Hide() end
    for i, opt in ipairs(self._options) do self:_row(i, opt) end

    -- Panel placement and size come from the anchor container
    self._panelHost:SetChildAnchor(panel, {
        point         = "TOPLEFT",
        relativeTo    = self._f,
        relativePoint = "BOTTOMLEFT",
        x = 0, y = -2,
        width  = self._f:GetWidth(),
        height = #self._options * rowHeight() + gap * 2,
    })
    panel:SetFrameStrata("TOOLTIP")

    panel:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then panel:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then panel:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end

    panel:SetAlpha(0)
    panel:Show()
    SuuUI.Anim.Presets.FadeIn(panel, T:GetToken("animFast"))

    if self._clickAway then self._clickAway:Arm() end
end

function DdMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bg = T:GetToken("colorBgAlt")
    local bd = T:GetToken("colorBorder")
    local bw = T:GetToken("borderWidth") or 1
    local tc = T:GetToken("colorText")
    local muted = T:GetToken("colorTextMuted")

    -- Font and size tokens both move at runtime, so re-derive the height unless the
    -- caller pinned one, and report it so the containing layout re-flows.
    if self._autoH then
        local h = T:GetControlHeight("sizeControlLg")
        if math.abs((self._f:GetHeight() or 0) - h) > 0.5 then
            self._f:SetHeight(h)
            S:Emit(self, S.SIGNALS.SIZE_CHANGED, self._f:GetWidth(), h)
        end
    end

    self._f:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then self._f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    if tc then self._selText:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
    if muted then self._arrow:SetTextColor(muted[1], muted[2], muted[3], muted[4]) end
    self._selText:SetFont(T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeMd") or 13, "")
end

--- Creates a custom dropdown.
-- Emits VALUE_CHANGED (new, old), ENABLED_CHANGED, VISIBILITY_CHANGED.
-- @param props table  { options, value, onChange, w, h }
--   options: array of { value, label }
-- @param parent frame
-- @return table  Dropdown handle
function SuuUI.Components.Dropdown(props, parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(props.w or 160, props.h or SuuUI.Theme:GetControlHeight("sizeControlLg"))
    f:EnableMouse(true)

    -- Selected label spans the button, arrow pinned to the right edge
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local selText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selText:SetJustifyH("LEFT")
    box:Add(selText, { valign = "center", inset = { left = 6, right = 16 } })

    local arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetText("v")
    box:Add(arrow, { align = "end", valign = "center", inset = { right = 4 }, width = 8 })

    -- Panel floats over everything, placed by the shared floating host
    local panelHost = SuuUI.Layout:GetFloatingHost()
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:Hide()
    panelHost:Add(panel, { anchor = { point = "TOPLEFT", x = 0, y = 0 } })

    local rowList = SuuUI.Layout:CreateContainer({
        host = panel, layout = "flow", dir = "vertical", gap = 0,
        padding = { top = SuuUI.Theme:GetToken("spaceXs") or 4 },
    })

    local id = "dd_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _selText=selText, _arrow=arrow, _panel=panel,
        _box=box, _panelHost=panelHost, _rowList=rowList,
        _options=props.options or {}, _rows={}, _eid=id,
        _value=props.value, _onChange=props.onChange, _enabled=true,
        _autoH=props.h == nil,
    }, DdMeta)

    if props.value then handle:SetValue(props.value) end

    f:SetScript("OnMouseUp", function()
        if handle._enabled == false then return end
        if panel:IsShown() then handle:_closePanel()
        else handle:_openPanel() end
    end)
    f:SetScript("OnEnter", function() S:Emit(handle, S.SIGNALS.MOUSE_ENTER) end)
    f:SetScript("OnLeave", function() S:Emit(handle, S.SIGNALS.MOUSE_LEAVE) end)

    handle._clickAway = SuuUI.Components.ClickAway({
        frame     = panel,
        guards    = { f },
        onOutside = function() handle:_closePanel() end,
    })

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
