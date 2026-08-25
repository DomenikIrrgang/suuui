-- Two or three mutually exclusive labelled segments in one bordered strip.
--
-- WHY A COMPONENT RATHER THAN THREE BUTTONS. The segments share one border and one background, with
-- hairline dividers BETWEEN them rather than around each -- so the strip reads as one control offering
-- a choice, not as a row of things to press. Three Buttons side by side cannot express that: each would
-- draw its own edge, and the gaps between them would break the strip into pieces.
--
-- It is the concept's `.seg`, and it replaces the pattern the settings UI currently reaches for -- a
-- Dropdown for a two-state choice, which costs a click and a panel to show two words.
local CreateFrame, ipairs, type = CreateFrame, ipairs, type

local S = SuuUI.UISignals
local T = SuuUI.Theme

local SegMeta = {}
SegMeta.__index = SegMeta

--- Repaints every segment from the current value.
--
-- The SELECTED segment takes colorAccentSubtle behind accent text; the rest are muted on nothing at
-- all. Painting the unselected ones with the strip's own background would put a second translucent
-- panel colour over the first and leave a visible seam at each divider -- the trap Accordion's header
-- and body avoid by being siblings.
function SegMeta:_paint()
    for i, seg in ipairs(self._segs) do
        local on = (self._options[i] and self._options[i].value) == self._value
        if on then
            SuuUI.Backdrop.SetBg(seg.f, "colorAccentSubtle")
            seg.text:SetColor("accent")
        else
            SuuUI.Backdrop.SetBg(seg.f, false)
            seg.text:SetColor("muted")
        end
    end
end

--- Rebuilds the strip's geometry from the token sizes and the measured labels.
--
-- Each segment is as wide as its own label plus padding, so "Bags" and "Bank" come out near enough
-- equal while a longer pair still fits. Measured through TextMetrics.Box rather than Measure, because
-- the number becomes the label's own box and the client truncates with zero tolerance.
function SegMeta:_fit()
    local padX = T:GetToken("spaceSm") or 8
    local padY = T:GetToken("spaceXxs") or 2
    local size = T:GetFontSize("sm")
    local line = T:GetToken("borderWidth") or 1
    local h = T:GetControlHeight("sizeControlSm", "sm")
    local total = 0
    for i, seg in ipairs(self._segs) do
        local w = SuuUI.TextMetrics.Box(seg.text:GetText() or "", nil, size) + padX * 2
        seg.f:SetSize(w, h - padY * 0)
        self._box:SetChildProps(seg.f, { width = w, valign = "stretch" })
        total = total + w
        -- A DIVIDER BETWEEN, NEVER AROUND. The strip owns the outer border, so a divider after the last
        -- segment would draw a second line on top of it.
        if seg.divider then
            if i < #self._segs then
                seg.divider:Show()
                self._box:SetChildProps(seg.divider, { width = line, valign = "stretch" })
                total = total + line
            else
                seg.divider:Hide()
            end
        end
    end
    self._f:SetSize(total + line * 2, h)
end

function SegMeta:ApplyTheme()
    SuuUI.Backdrop.Apply(self._f, { bg = "colorBg", border = "colorBorder" })
    for _, seg in ipairs(self._segs) do
        -- EACH SEGMENT NEEDS ITS OWN BACKDROP, transparent and borderless, or _paint's SetBg has nothing
        -- to recolour and the selected wash silently never draws. Found by a mutation that survived:
        -- removing the wash changed nothing, because there was no wash. `inset = 0` so the fill covers
        -- the whole segment and meets its dividers, exactly as a frameless StatusBar's does.
        SuuUI.Backdrop.Apply(seg.f, { bg = false, border = false, inset = 0 })
        if seg.text.ApplyTheme then seg.text:ApplyTheme() end
        if seg.divider then
            local c = T:GetToken("colorBorder")
            if c then seg.divider:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
        end
    end
    self:_paint()
    self:_applyEnabled()
    self:_fit()
end

--- The selected value.
-- @return any
function SegMeta:GetValue() return self._value end

--- Selects a segment. SILENT, per the setter contract: only a click emits VALUE_CHANGED.
-- @param value any
function SegMeta:SetValue(value)
    if self._value == value then return end
    self._value = value
    self:_paint()
end

--- Replaces the options. Keeps the current value when it is still on offer, so a rebuild of the same
--- choice does not silently move the selection.
-- @param options table  { { value, label } }
function SegMeta:SetOptions(options)
    self._options = options or {}
    -- Rebuilt rather than patched: the segment count is what the layout is derived from, and a strip
    -- that kept a stale segment would leave a divider with nothing beside it.
    for _, seg in ipairs(self._segs) do
        self._box:Remove(seg.f)
        if seg.divider then self._box:Remove(seg.divider) end
        seg.text:Destroy()
        seg.f:Hide()
    end
    self._segs = {}
    self:_build()
    local found
    for _, o in ipairs(self._options) do
        if o.value == self._value then found = true end
    end
    if not found then self._value = self._options[1] and self._options[1].value or nil end
    self:ApplyTheme()
end

function SegMeta:_onEnabledChanged(en)
    for _, seg in ipairs(self._segs) do seg.f:EnableMouse(en) end
end

function SegMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    for _, seg in ipairs(self._segs) do seg.text:Destroy() end
    if self._box then self._box:Destroy() end
    self._f:Hide()
end

SuuUI.Components.InstallBase(SegMeta, "_f")
SuuUI.Components.InstallEnable(SegMeta, "_f")

--- Two or three mutually exclusive labelled segments in one bordered strip.
--
-- Emits VALUE_CHANGED (newValue, oldValue) on a click, and nothing on SetValue.
-- @param props table  { options = { { value, label } }, value }
-- @param parent frame
-- @return table  handle
function SuuUI.Components.SegmentedControl(props, parent)
    props = props or {}
    local f = CreateFrame("Frame", props.name, parent, "BackdropTemplate")
    f:SetSize(1, T:GetControlHeight("sizeControlSm", "sm"))

    local handle
    -- REGISTERED BEFORE THE HOST CONTAINER ADOPTS THE FRAME, so the container chains onto this rather
    -- than replacing it. Getting this backwards is what left a window's glass surface at its original
    -- size for the whole session.
    f:SetScript("OnSizeChanged", function(_, w, h)
        if handle then S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h) end
    end)

    local box = SuuUI.Layout:CreateContainer({
        host = f, layout = "flow", dir = "horizontal", gap = 0,
        padding = { top = 0, right = 0, bottom = 0, left = 0 },
    })

    handle = setmetatable({
        _f = f, _box = box, _eid = "seg_" .. tostring(f),
        _enabled = true,
        _options = props.options or {},
        _value = props.value,
        _segs = {},
    }, SegMeta)

    function handle:_build()
        for i, opt in ipairs(self._options) do
            local sf = CreateFrame("Button", nil, self._f, "BackdropTemplate")
            sf:EnableMouse(true)
            local label = SuuUI.Components.Text({
                text = opt.label or tostring(opt.value), size = "sm", color = "muted",
                justify = "CENTER", wrap = false,
            }, sf)
            label._fade = false
            local lbox = SuuUI.Layout:CreateContainer({ host = sf, layout = "stack" })
            lbox:Add(label, { align = "center", valign = "center" })
            -- The click is translated into a signal here and never escapes this file. A segment that is
            -- already selected still emits nothing, since nothing changed.
            sf:SetScript("OnMouseUp", function()
                if self._enabled == false then return end
                local old = self._value
                if old == opt.value then return end
                self._value = opt.value
                self:_paint()
                S:Emit(self, S.SIGNALS.VALUE_CHANGED, opt.value, old)
            end)
            local divider = self._f:CreateTexture(nil, "OVERLAY")
            self._segs[i] = { f = sf, text = label, divider = divider, box = lbox }
            self._box:Add(sf, { valign = "stretch" })
            self._box:Add(divider, { valign = "stretch" })
        end
    end

    handle:_build()
    if handle._value == nil then
        handle._value = handle._options[1] and handle._options[1].value or nil
    end
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, handle._eid)
    return handle
end
