local max, min, floor = math.max, math.min, math.floor
local S = SuuUI.UISignals

local TRACK_H   = 4
local TRACK_PAD = 6
local THUMB_W   = 8
local THUMB_H   = 12

local SldMeta = {}
SldMeta.__index = SldMeta

function SldMeta:GetWidth()     return self._f:GetWidth() end
function SldMeta:GetHeight()    return self._f:GetHeight() end
function SldMeta:IsShown()      return self._f:IsShown() end
function SldMeta:GetFrame()     return self._f end

function SldMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    self:_render()
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

function SldMeta:Show()
    self._f:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function SldMeta:Hide()
    self._f:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

function SldMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._f:SetScript("OnUpdate", nil)
    self._box:Destroy()
end

--- Enables or disables the slider. Emits ENABLED_CHANGED.
-- @param en bool
function SldMeta:SetEnabled(en)
    self._enabled = en
    self._hit:EnableMouse(en)
    S:Emit(self, S.SIGNALS.ENABLED_CHANGED, en)
end

--- Returns the current slider value.
-- @return number
function SldMeta:GetValue()
    return self._value
end

--- Sets slider value without emitting VALUE_CHANGED.
-- @param v number
function SldMeta:SetValue(v)
    self._value = max(self._vmin, min(self._vmax, v))
    self:_render()
end

function SldMeta:_render()
    local T   = SuuUI.Theme
    local pct = (self._value - self._vmin) / (self._vmax - self._vmin)
    local tw  = max(0, (self._f:GetWidth() or 0) - TRACK_PAD * 2)
    local ac  = T:GetToken("colorAccent")
    local bg  = T:GetToken("colorBgAlt")

    local fillW = max(1, tw * pct)
    -- Fill and thumb are positioned by the track's anchor container
    self._fillAnchor.width = fillW
    self._trackBox:SetChildAnchor(self._fill, self._fillAnchor)

    self._thumbAnchor.x = (tw * pct) - THUMB_W / 2
    self._trackBox:SetChildAnchor(self._thumb, self._thumbAnchor)

    if ac then
        self._fill:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
        self._thumb:SetBackdropColor(ac[1], ac[2], ac[3], ac[4])
    end
    if bg then self._trackBg:SetColorTexture(bg[1], bg[2], bg[3], bg[4]) end

    local disp = (self._step >= 1) and floor(self._value) or self._value
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
-- Emits VALUE_CHANGED (new, old), ENABLED_CHANGED, SIZE_CHANGED.
-- @param props table  { label, value, min, max, step, onChange, w, h }
-- @param parent frame
-- @return table  Slider handle
function SuuUI.Components.Slider(props, parent)
    local w    = props.w or 200
    local h    = props.h or 36
    local vmin = props.min  or 0
    local vmax = props.max  or 100
    local step = props.step or 1
    local val  = max(vmin, min(vmax, props.value or vmin))

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)

    -- Rows are laid out by the engine: label row on top, track below
    local box = SuuUI.Layout:CreateContainer({
        host = f, layout = "flow", dir = "vertical", gap = 0,
    })

    local labelRow = SuuUI.Layout:CreateContainer({
        parent = f, layout = "flow", dir = "horizontal", gap = 4, h = 14,
    })
    local labelText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetText(props.label or "")
    labelText:SetJustifyH("LEFT")
    local valText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valText:SetJustifyH("RIGHT")
    labelRow:Add(labelText, { width = "fill" })
    labelRow:Add(valText, { width = 40 })
    box:Add(labelRow, { width = "fill", height = 14 })

    -- Track strip: a stack container inset horizontally, holding the 4px track
    local trackStrip = SuuUI.Layout:CreateContainer({
        parent = f, layout = "stack",
        padding = { left = TRACK_PAD, right = TRACK_PAD },
    })
    local track = CreateFrame("Frame", nil, f)
    trackStrip:Add(track, { valign = "center", height = TRACK_H })
    box:Add(trackStrip, { width = "fill", height = h - 14 })

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    local trackBox = SuuUI.Layout:CreateContainer({ host = track, layout = "anchor" })

    local fill = track:CreateTexture(nil, "ARTWORK")
    local fillAnchor = {
        point = "LEFT", relativePoint = "LEFT", x = 0, y = 0, height = TRACK_H, width = 1,
    }
    trackBox:Add(fill, { anchor = fillAnchor })

    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    thumb:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=1, insets={left=1,right=1,top=1,bottom=1},
    })
    local thumbAnchor = {
        point = "LEFT", relativePoint = "LEFT", x = 0, y = 0,
        width = THUMB_W, height = THUMB_H,
    }
    trackBox:Add(thumb, { anchor = thumbAnchor })

    -- Background texture fills the track via its own stack container
    local trackBgBox = SuuUI.Layout:CreateContainer({ host = track, layout = "stack" })
    trackBgBox:Add(trackBg)

    local hitBox = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
    local hit = CreateFrame("Frame", nil, f)
    hit:EnableMouse(true)
    hitBox:Add(hit)

    local id = "sld_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _box=box, _track=track, _trackBox=trackBox,
        _trackBg=trackBg, _fill=fill, _thumb=thumb, _hit=hit,
        _fillAnchor=fillAnchor, _thumbAnchor=thumbAnchor,
        _labelText=labelText, _valText=valText,
        _eid=id, _value=val, _vmin=vmin, _vmax=vmax, _step=step,
        _onChange=props.onChange, _enabled=true,
    }, SldMeta)

    -- Tracks the cursor only while dragging, then unregisters (no idle OnUpdate)
    local function onUpdate()
        local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
        local tl  = track:GetLeft() or 0
        local tw  = track:GetWidth()
        if not tw or tw <= 0 then return end
        local pct = max(0, min(1, (cx - tl) / tw))
        local snapped = floor((vmin + (vmax - vmin) * pct) / step + 0.5) * step

        if snapped ~= handle._value then
            local old = handle._value
            handle:SetValue(snapped)
            if handle._onChange then handle._onChange(handle._value) end
            S:Emit(handle, S.SIGNALS.VALUE_CHANGED, handle._value, old)
        end
    end

    local function stopDrag() f:SetScript("OnUpdate", nil) end

    hit:SetScript("OnMouseDown", function(_, btn)
        if handle._enabled == false or btn ~= "LeftButton" then return end
        onUpdate()
        f:SetScript("OnUpdate", onUpdate)
    end)
    hit:SetScript("OnMouseUp", stopDrag)
    hit:SetScript("OnHide", stopDrag)
    hit:SetScript("OnEnter", function() S:Emit(handle, S.SIGNALS.MOUSE_ENTER) end)
    hit:SetScript("OnLeave", function() S:Emit(handle, S.SIGNALS.MOUSE_LEAVE) end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
