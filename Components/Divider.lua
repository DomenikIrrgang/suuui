local DivMeta = {}
DivMeta.__index = DivMeta

function DivMeta:SetPoint(...)  self._f:SetPoint(...) end
function DivMeta:SetSize(w, h)  self._f:SetSize(w, h) end
function DivMeta:Show()         self._f:Show() end
function DivMeta:Hide()         self._f:Hide() end
function DivMeta:IsShown()      return self._f:IsShown() end
function DivMeta:GetFrame()     return self._f end
function DivMeta:SetEnabled()   end
function DivMeta:Destroy()      SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid) end

function DivMeta:ApplyTheme()
    local c = SuuUI.Theme:GetToken("colorBorder")
    if c then self._line:SetColorTexture(c[1], c[2], c[3], c[4]) end
    if self._label then
        local tc = SuuUI.Theme:GetToken("colorTextMuted")
        if tc then self._label:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
        self._label:SetFont(
            SuuUI.Theme:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
            SuuUI.Theme:GetToken("fontSizeSm") or 11, "")
    end
end

--- Creates a horizontal or vertical divider line.
-- @param props table  { dir, label, w, h }  dir: "horizontal"|"vertical"
-- @param parent frame
-- @return table  Divider handle
function SuuUI.Components.Divider(props, parent)
    local vertical = props.dir == "vertical"
    local w = props.w or (vertical and 1 or 200)
    local h = props.h or (vertical and 20 or 1)

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)

    local line = f:CreateTexture(nil, "ARTWORK")
    if vertical then
        line:SetWidth(1)
        line:SetPoint("TOP",    f, "TOP",    0, 0)
        line:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    else
        line:SetHeight(1)
        line:SetPoint("LEFT",  f, "LEFT",  0, 0)
        line:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    end

    local labelFs
    if props.label and props.label ~= "" then
        labelFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelFs:SetPoint("CENTER", line, "CENTER", 0, 0)
        labelFs:SetText(props.label)
    end

    local id = "div_" .. tostring(f)
    local handle = setmetatable({ _f=f, _line=line, _label=labelFs, _eid=id }, DivMeta)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
