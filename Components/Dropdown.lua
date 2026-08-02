local ipairs = ipairs

local DdMeta = {}
DdMeta.__index = DdMeta

function DdMeta:SetPoint(...)  self._f:SetPoint(...) end
function DdMeta:SetSize(w, h)  self._f:SetSize(w, h) end
function DdMeta:Show()         self._f:Show() end
function DdMeta:Hide()         self._f:Hide() end
function DdMeta:IsShown()      return self._f:IsShown() end
function DdMeta:GetFrame()     return self._f end
function DdMeta:Destroy()
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    if self._panel then self._panel:Hide() end
end
function DdMeta:SetEnabled(en)
    self._enabled = en
    self._f:EnableMouse(en)
end

--- Returns the selected option value.
-- @return any
function DdMeta:GetValue()
    return self._value
end

--- Sets selected value and updates label. Does not fire onChange.
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
    end
end

function DdMeta:_openPanel()
    local T    = SuuUI.Theme
    local bg   = T:GetToken("colorBgAlt")
    local bd   = T:GetToken("colorBorder")
    local bw   = T:GetToken("borderWidth") or 1
    local gap  = T:GetToken("spaceSm") or 4
    local rowH = 22
    local panel = self._panel

    panel:SetSize(self._f:GetWidth(), #self._options * rowH + gap * 2)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", self._f, "BOTTOMLEFT", 0, -2)
    panel:SetFrameStrata("TOOLTIP")

    -- hide all existing rows first (reuse below if possible)
    for _, row in ipairs(self._rows) do row:Hide() end

    for i, opt in ipairs(self._options) do
        local row = self._rows[i]
        if not row then
            row = CreateFrame("Frame", nil, panel, "BackdropTemplate")
            self._rows[i] = row
        end
        row:SetSize(panel:GetWidth() - bw * 2, rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", bw, -(gap + (i-1)*rowH))
        row:SetBackdrop({
            bgFile="Interface\\Buttons\\WHITE8x8",
            edgeFile="Interface\\Buttons\\WHITE8x8",
            edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
        })
        if bg then row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
        if bd then row:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
        row:EnableMouse(true)
        row:Show()

        -- reuse or create label
        local lbl = row._lbl
        if not lbl then
            lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("LEFT", row, "LEFT", 6, 0)
            row._lbl = lbl
        end
        lbl:SetFont(T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
            T:GetToken("fontSizeMd") or 13, "")
        lbl:SetText(opt.label)
        local tc = T:GetToken("colorText")
        if tc then lbl:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end

        local optVal  = opt.value
        local optLabel = opt.label
        local self_ref = self
        row:SetScript("OnEnter", function()
            local hov = T:GetToken("colorBgHover")
            if hov then row:SetBackdropColor(hov[1], hov[2], hov[3], hov[4]) end
        end)
        row:SetScript("OnLeave", function()
            if bg then row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
        end)
        row:SetScript("OnMouseUp", function()
            self_ref._value = optVal
            self_ref._selText:SetText(optLabel)
            self_ref:_closePanel()
            if self_ref._onChange then self_ref._onChange(optVal) end
        end)
    end

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
end

function DdMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bg = T:GetToken("colorBgAlt")
    local bd = T:GetToken("colorBorder")
    local bw = T:GetToken("borderWidth") or 1
    local tc = T:GetToken("colorText")
    local muted = T:GetToken("colorTextMuted")
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
-- @param props table  { options, value, onChange, w, h }
--   options: array of { value, label }
-- @param parent frame
-- @return table  Dropdown handle
function SuuUI.Components.Dropdown(props, parent)
    local w = props.w or 160
    local h = props.h or 24

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:EnableMouse(true)

    local selText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selText:SetPoint("LEFT", f, "LEFT", 6, 0)
    selText:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    selText:SetJustifyH("LEFT")

    local arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    arrow:SetText("▾")

    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:Hide()

    local id = "dd_" .. tostring(f)
    local options = props.options or {}
    local handle = setmetatable({
        _f=f, _selText=selText, _arrow=arrow, _panel=panel,
        _options=options, _rows={}, _eid=id,
        _value=props.value, _onChange=props.onChange, _enabled=true,
    }, DdMeta)

    -- set initial label
    if props.value then handle:SetValue(props.value) end

    f:SetScript("OnMouseUp", function()
        if handle._enabled == false then return end
        if panel:IsShown() then handle:_closePanel()
        else handle:_openPanel() end
    end)

    -- close on click elsewhere
    panel:SetScript("OnHide", function() end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
