local max, min, floor, ceil = math.max, math.min, math.floor, math.ceil
local S = SuuUI.UISignals

local TRACK_H     = 4
local TRACK_PAD   = 6
local THUMB_SIZE  = 12
-- Vertical space reserved below the label for the track and thumb. The label strip
-- above it is measured from the font token, so the slider's height is intrinsic.
local TRACK_AREA  = 22
local LABEL_MIN_H = 14
local RING_WIDTH  = 1
local WHITE       = "Interface\\Buttons\\WHITE8x8"
local CIRCLE_MASK = "Interface\\Minimap\\UI-Minimap-Background"

-- Rounds a solid texture into a circle. The mask art is a round asset present on
-- Classic clients, and CLAMPTOBLACKADDITIVE wrapping is required for it to cut a
-- circle rather than leave the texture untouched. Returns the mask so the caller's
-- layout container can size it onto the texture; nil when masking is unavailable,
-- in which case the texture stays square rather than rendering nothing.
local function circleMask(frame, tex)
    tex:SetTexture(WHITE)
    if not (frame.CreateMaskTexture and tex.AddMaskTexture) then return nil end
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(mask)
    return mask
end

local SldMeta = {}
SldMeta.__index = SldMeta

function SldMeta:GetWidth()     return self._f:GetWidth() end
function SldMeta:GetHeight()    return self._f:GetHeight() end
function SldMeta:IsShown()      return self._f:IsShown() end
function SldMeta:GetFrame()     return self._f end

function SldMeta:SetSize(w, h)
    self._f:SetSize(w, h)
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
    self._thumbBox:Destroy()
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

    self._thumbAnchor.x = (tw * pct) - THUMB_SIZE / 2
    self._trackBox:SetChildAnchor(self._thumb, self._thumbAnchor)

    if ac then
        self._fill:SetColorTexture(ac[1], ac[2], ac[3], ac[4])
        self._thumbDot:SetVertexColor(ac[1], ac[2], ac[3], ac[4])
    end
    local bd = T:GetToken("colorBorder")
    if bd then self._thumbRing:SetVertexColor(bd[1], bd[2], bd[3], bd[4]) end
    if bg then self._trackBg:SetColorTexture(bg[1], bg[2], bg[3], bg[4]) end

    local disp = (self._step >= 1) and floor(self._value) or self._value
    self._valText:SetText(tostring(disp))
end

function SldMeta:ApplyTheme()
    self:_render()
    local T  = SuuUI.Theme
    local tc = T:GetToken("colorText")
    local f  = T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF"
    -- Primary label, same weight as every other row label (C.Text size "md")
    local sz = T:GetToken("fontSizeMd") or 13
    if tc then
        self._labelText:SetTextColor(tc[1], tc[2], tc[3], tc[4])
        self._valText:SetTextColor(tc[1], tc[2], tc[3], tc[4])
    end
    self._labelText:SetFont(f, sz, "")
    self._valText:SetFont(f, sz, "")
    self:_resizeLabelStrip()
end

-- The label strip grows with the font size token, so re-measure it and re-height the
-- slider itself. Changing the frame height fires OnSizeChanged, which re-renders and
-- emits SIZE_CHANGED so the containing layout re-flows.
function SldMeta:_resizeLabelStrip()
    local h = ceil(max(LABEL_MIN_H, self._labelText:GetStringHeight() or 0))
    if h == self._labelH then return end
    self._labelH = h
    self._box:SetChildProps(self._labelRow, { width = "fill", height = h })
    self._f:SetHeight(h + TRACK_AREA)
end

--- Creates a custom slider.
-- Emits VALUE_CHANGED (new, old), ENABLED_CHANGED, SIZE_CHANGED.
-- @param props table  { label, value, min, max, step, onChange, w, h }
-- @param parent frame
-- @return table  Slider handle
function SuuUI.Components.Slider(props, parent)
    local w    = props.w or 200
    local h    = props.h or (LABEL_MIN_H + TRACK_AREA)
    local vmin = props.min  or 0
    local vmax = props.max  or 100
    local step = props.step or 1
    local val  = max(vmin, min(vmax, props.value or vmin))

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)

    -- Fill and thumb offsets derive from the frame width, so re-render whenever the
    -- frame is resized, including by a parent layout. Registered before the host
    -- container adopts the frame so the container chains onto it.
    local handle
    f:SetScript("OnSizeChanged", function(_, newW, newH)
        if not (handle and handle._trackBox) then return end
        handle:_render()
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, newW, newH)
    end)

    -- Rows are laid out by the engine: label row on top, track below
    local box = SuuUI.Layout:CreateContainer({
        host = f, layout = "flow", dir = "vertical", gap = 0,
    })

    local labelRow = SuuUI.Layout:CreateContainer({
        parent = f, layout = "flow", dir = "horizontal", gap = 4, h = LABEL_MIN_H,
    })
    local labelText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetText(props.label or "")
    labelText:SetJustifyH("LEFT")
    local valText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valText:SetJustifyH("RIGHT")
    labelRow:Add(labelText, { width = "fill" })
    labelRow:Add(valText, { width = 40 })
    box:Add(labelRow, { width = "fill", height = LABEL_MIN_H })

    -- Track strip: a stack container inset horizontally, holding the 4px track
    local trackStrip = SuuUI.Layout:CreateContainer({
        parent = f, layout = "stack",
        padding = { left = TRACK_PAD, right = TRACK_PAD },
    })
    local track = CreateFrame("Frame", nil, f)
    trackStrip:Add(track, { valign = "center", height = TRACK_H })
    box:Add(trackStrip, { width = "fill", height = TRACK_AREA })

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    local trackBox = SuuUI.Layout:CreateContainer({ host = track, layout = "anchor" })

    local fill = track:CreateTexture(nil, "ARTWORK")
    local fillAnchor = {
        point = "LEFT", relativePoint = "LEFT", x = 0, y = 0, height = TRACK_H, width = 1,
    }
    trackBox:Add(fill, { anchor = fillAnchor })

    -- Circular thumb: a thin ring texture with the accent dot inset inside it
    local thumb = CreateFrame("Frame", nil, track)
    local thumbBox = SuuUI.Layout:CreateContainer({ host = thumb, layout = "stack" })
    -- Each texture gets its own mask sized to itself: one shared mask would clip the
    -- inset dot's corners instead of rounding it, leaving flat edges.
    local thumbRing = thumb:CreateTexture(nil, "ARTWORK")
    local ringMask  = circleMask(thumb, thumbRing)
    thumbBox:Add(thumbRing)
    if ringMask then thumbBox:Add(ringMask) end

    local thumbDot = thumb:CreateTexture(nil, "OVERLAY")
    local dotMask  = circleMask(thumb, thumbDot)
    thumbBox:Add(thumbDot, { inset = RING_WIDTH })
    if dotMask then thumbBox:Add(dotMask, { inset = RING_WIDTH }) end

    local thumbAnchor = {
        point = "LEFT", relativePoint = "LEFT", x = 0, y = 0,
        width = THUMB_SIZE, height = THUMB_SIZE,
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
    handle = setmetatable({
        _f=f, _box=box, _track=track, _trackBox=trackBox,
        _trackBg=trackBg, _fill=fill, _hit=hit,
        _thumb=thumb, _thumbBox=thumbBox, _thumbRing=thumbRing, _thumbDot=thumbDot,
        _fillAnchor=fillAnchor, _thumbAnchor=thumbAnchor,
        _labelText=labelText, _valText=valText,
        _labelRow=labelRow, _labelH=LABEL_MIN_H,
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
