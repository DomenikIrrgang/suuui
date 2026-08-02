-- EditBox is a Blizzard-required component. This wraps it with SuuUI theming.
local InpMeta = {}
InpMeta.__index = InpMeta

function InpMeta:SetPoint(...)  self._f:SetPoint(...) end
function InpMeta:SetSize(w, h)  self._f:SetSize(w, h) self._eb:SetSize(w - 8, h - 4) end
function InpMeta:Show()         self._f:Show() end
function InpMeta:Hide()         self._f:Hide() end
function InpMeta:IsShown()      return self._f:IsShown() end
function InpMeta:GetFrame()     return self._f end
function InpMeta:Destroy()      SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid) end

--- Enables or disables text input.
-- @param en bool
function InpMeta:SetEnabled(en)
    self._enabled = en
    self._eb:SetEnabled(en)
end

--- Returns current text value.
-- @return string
function InpMeta:GetValue()
    return self._eb:GetText()
end

--- Sets text value.
-- @param text string
function InpMeta:SetValue(text)
    self._eb:SetText(text or "")
end

--- Sets keyboard focus to the input field.
function InpMeta:SetFocus()
    self._eb:SetFocus()
end

function InpMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bg = T:GetToken("colorBgAlt")
    local bd = T:GetToken("colorBorder")
    local bw = T:GetToken("borderWidth") or 1
    local tc = T:GetToken("colorText")
    self._f:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then self._f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    self._eb:SetFont(T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeMd") or 13, "")
    if tc then self._eb:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
end

--- Creates a themed text input.
-- @param props table  { value, placeholder, onChange, onEnter, w, h, maxChars }
-- @param parent frame
-- @return table  Input handle
function SuuUI.Components.Input(props, parent)
    local w = props.w or 160
    local h = props.h or 24

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)

    local eb = CreateFrame("EditBox", nil, f)
    eb:SetPoint("CENTER", f, "CENTER", 0, 0)
    eb:SetSize(w - 8, h - 4)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(props.maxChars or 255)
    if props.value then eb:SetText(props.value) end

    local T = SuuUI.Theme
    local id = "inp_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _eb=eb, _eid=id, _enabled=true,
        _hasFocus=false, _hasHover=false,
    }, InpMeta)

    local function updateBorder()
        local T = SuuUI.Theme
        if handle._hasFocus or handle._hasHover then
            local c = T:GetToken("colorBorderFocus")
            if c then f:SetBackdropBorderColor(c[1], c[2], c[3], c[4]) end
        else
            local bd = T:GetToken("colorBorder")
            if bd then f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
        end
    end

    eb:SetScript("OnTextChanged", function()
        if props.onChange then props.onChange(eb:GetText()) end
    end)
    eb:SetScript("OnEnterPressed", function()
        eb:ClearFocus()
        if props.onEnter then props.onEnter(eb:GetText()) end
    end)
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function()
        handle._hasFocus = true
        updateBorder()
    end)
    eb:SetScript("OnEditFocusLost", function()
        handle._hasFocus = false
        updateBorder()
    end)
    f:SetScript("OnEnter", function()
        handle._hasHover = true
        updateBorder()
    end)
    f:SetScript("OnLeave", function()
        handle._hasHover = false
        updateBorder()
    end)
    
    -- EditBox should also trigger hover state
    eb:SetScript("OnEnter", function()
        handle._hasHover = true
        updateBorder()
    end)
    eb:SetScript("OnLeave", function()
        handle._hasHover = false
        updateBorder()
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
