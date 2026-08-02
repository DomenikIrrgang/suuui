local S = SuuUI.UISignals

local DivMeta = {}
DivMeta.__index = DivMeta

function DivMeta:GetWidth()     return self._f:GetWidth() end
function DivMeta:GetHeight()    return self._f:GetHeight() end
function DivMeta:IsShown()      return self._f:IsShown() end
function DivMeta:GetFrame()     return self._f end
function DivMeta:SetEnabled()   end

function DivMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

function DivMeta:Show()
    self._f:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function DivMeta:Hide()
    self._f:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

function DivMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._box:Destroy()
end

--- Sets the divider's label text.
-- @param text string
function DivMeta:SetText(text)
    if self._label then
        self._label:SetText(text)
        S:Emit(self, S.SIGNALS.TEXT_CHANGED, text)
    end
end

function DivMeta:ApplyTheme()
    local T = SuuUI.Theme
    local c = T:GetToken("colorBorder")
    if c then self._line:SetColorTexture(c[1], c[2], c[3], c[4]) end
    if self._label then
        local tc = T:GetToken("colorTextMuted")
        if tc then self._label:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
        self._label:SetFont(
            T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
            T:GetToken("fontSizeSm") or 11, "")
    end
end

--- Creates a horizontal or vertical divider line.
-- Emits SIZE_CHANGED, VISIBILITY_CHANGED, TEXT_CHANGED.
-- @param props table  { dir, label, w, h }  dir: "horizontal"|"vertical"
-- @param parent frame
-- @return table  Divider handle
function SuuUI.Components.Divider(props, parent)
    local vertical = props.dir == "vertical"
    local w = props.w or (vertical and 1 or 200)
    local h = props.h or (vertical and 20 or 1)

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- The line spans one axis and is centred on the other
    local line = f:CreateTexture(nil, "ARTWORK")
    if vertical then
        box:Add(line, { align = "center", width = 1 })
    else
        box:Add(line, { valign = "center", height = 1 })
    end

    local labelFs
    if props.label and props.label ~= "" then
        labelFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelFs:SetText(props.label)
        box:Add(labelFs, { align = "center", valign = "center" })
    end

    local id = "div_" .. tostring(f)
    local handle = setmetatable({ _f=f, _line=line, _label=labelFs, _box=box, _eid=id }, DivMeta)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
