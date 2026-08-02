local max, min, floor = math.max, math.min, math.floor

local SldMeta = {}
SldMeta.__index = SldMeta

function SldMeta:SetPoint(...)  self._f:SetPoint(...) end
function SldMeta:SetSize(w, h)  self._f:SetSize(w, h) end
function SldMeta:Show()         self._f:Show() end
function SldMeta:Hide()         self._f:Hide() end
function SldMeta:IsShown()      return self._f:IsShown() end
function SldMeta:GetFrame()     return self._f end
function SldMeta:Destroy()      SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid) end
function SldMeta:SetEnabled(en)
    self._enabled = en
    self._hit:EnableMouse(en)
end

--- Returns the current slider value.
-- @return number
function SldMeta:GetValue()
    return self._value
end

--- Sets slider value without firing onChange.
-- @param v number
function SldMeta:SetValue(v)
    self._value = max(self._vmin, min(self._vmax, v))
    self:_render()
end

function SldMeta:_render()
    local T   = SuuUI.Theme
    local pct = (self._value - self._vmin) / (self._vmax - self._vmin)
    local tw  = self._f:GetWidth() - 12
    local ac  = T:GetToken("colorAccent")
    local bg  = T:GetToken("colorBgAlt")
    local bw  = T:GetToken("borderWidth") or 1
    local trackW = tw * pct
    if trackW < 0 then trackW = 0 end
    self._fill:SetWidth(trackW < 1 and 1 or trackW)
    self._thumb:SetPoint("LEFT", self._track, "LEFT", trackW - 4, 0)
    if ac then
        self._fill:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
        self._thumb:SetBackdropColor(ac[1], ac[2], ac[3], ac[4])
    end
    if bg then self._trackBg:SetColorTexture(bg[1], bg[2], bg[3], bg[4]) end
    -- update label
    local step = self._step
    local disp = (step >= 1) and floor(self._value) or self._value
    self._valText:SetText(tostring(disp))
end

function SldMeta:ApplyTheme()
    self:_render()
    local T  = SuuUI.Theme
    local tc = T:GetToken("colorText")
    local f  = T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF"
    local sz = T:GetToken("fontSizeSm") or 11
    if tc then
        self._labelText:SetTextColor(tc[1], tc[2], tc[3], tc[4])
        self._valText:SetTextColor(tc[1], tc[2], tc[3], tc[4])
    end
    self._labelText:SetFont(f, sz, "")
    self._valText:SetFont(f, sz, "")
end

--- Creates a custom slider.
-- @param props table  { label, value, min, max, step, onChange, w }
-- @param parent frame
-- @return table  Slider handle
function SuuUI.Components.Slider(props, parent)
    local w    = props.w or 200
    local vmin = props.min  or 0
    local vmax = props.max  or 100
    local step = props.step or 1
    local val  = max(vmin, min(vmax, props.value or vmin))

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, 36)

    local labelText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    labelText:SetText(props.label or "")

    local valText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valText:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

    local track = CreateFrame("Frame", nil, f)
    track:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",   6, 4)
    track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
    track:SetHeight(4)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints(track)

    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetHeight(4)

    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    thumb:SetSize(8, 12)
    thumb:SetPoint("LEFT", track, "LEFT", 0, 0)
    thumb:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=1, insets={left=1,right=1,top=1,bottom=1},
    })

    local hit = CreateFrame("Frame", nil, f)
    hit:SetAllPoints(f)
    hit:EnableMouse(true)

    local id = "sld_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _track=track, _trackBg=trackBg, _fill=fill,
        _thumb=thumb, _hit=hit,
        _labelText=labelText, _valText=valText,
        _eid=id, _value=val, _vmin=vmin, _vmax=vmax, _step=step,
        _onChange=props.onChange, _enabled=true,
    }, SldMeta)

    hit:SetScript("OnMouseDown", function(_, btn)
        if handle._enabled == false or btn ~= "LeftButton" then return end
        local cx, _cy = GetCursorPosition()
        cx = cx / UIParent:GetEffectiveScale()
        local tl   = track:GetLeft() or 0
        local tw   = track:GetWidth()
        local pct  = max(0, min(1, (cx - tl) / tw))
        local raw  = vmin + (vmax - vmin) * pct
        local snapped = floor(raw / step + 0.5) * step
        handle:SetValue(snapped)
        if handle._onChange then handle._onChange(handle._value) end
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
