local ipairs, max, abs = ipairs, math.max, math.abs
local S = SuuUI.UISignals

-- Horizontal breathing room inside the button and inside an option row. No space token
-- is 6px, so this stays a literal rather than moving the geometry onto spaceXs/spaceSm.
local TEXT_INSET = 6

-- Option rows hold text, so their height is floored against the font size token.
local function rowHeight()
    return SuuUI.Theme:GetControlHeight("sizeControlMd")
end

-- An option's face comes from a caller, so it is resolved to something loadable before
-- use. SetFont raises on an invalid asset, and a dropdown option is not worth an error.
local function faceOf(opt)
    if not (opt and opt.font) then return nil end
    return SuuUI.Fonts:Path(opt.font)
end

-- Height a label needs in an explicit face. An option may render in its own font (a font
-- picker does), and a face's line height is not derivable from the point size alone, so
-- the token floor is not enough on its own — a tall face would draw clipped glyphs.
local function faceHeight(text, font, floor)
    if not font then return floor end
    local T = SuuUI.Theme
    local _, th = SuuUI.TextMetrics.Measure(text or "", font, T:GetToken("fontSizeMd") or 13)
    return max(floor, th + (T:GetToken("spaceXs") or 4) * 2)
end

local ARROW_GLYPH = "v"

-- The arrow column is measured, never a space token. A column narrower than the glyph
-- does not overflow: the client clips it and draws an ellipsis instead of the arrow.
-- Font sizes are user-editable, so this is re-derived on every theme change.
local function arrowWidth()
    local T = SuuUI.Theme
    local w = SuuUI.TextMetrics.Measure(ARROW_GLYPH,
        T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeMd") or 13)
    -- A pixel of slack, as Button does: a column pinned to exactly the measured width
    -- can still trip truncation on rounding.
    return w + 2
end

local DdMeta = {}
DdMeta.__index = DdMeta

--- Sets an explicit size, dropping token-driven height.
-- SIZE_CHANGED comes from the frame's resize hook.
-- @param w number
-- @param h number
function DdMeta:SetSize(w, h)
    self._autoH = false
    self._f:SetSize(w, h)
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
    -- Pooled rows are not the row list's to free: it holds raw frames, so their own
    -- boxes and label handles have to be released here or they keep a theme
    -- subscription alive for the lifetime of the session.
    for _, row in ipairs(self._rows) do
        row._box:Destroy()
        row._lblT:Destroy()
    end
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
            self:_select(opt)
            return
        end
    end
end

-- Shows an option as the selection. An option carrying a font renders in it, which also
-- changes how tall the button has to be, so the height is re-derived here too.
function DdMeta:_select(opt)
    self._selFont = faceOf(opt)
    self._selT:SetFont(self._selFont)
    self._selT:SetText(opt.label)
    self:_autosize()
    -- The label is token-sized, so a face change resizes nothing and nothing else
    -- re-measures it: without this the box keeps the old face's width and clips.
    self._box:Layout()
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
    self._open = false
    self:_paint()
end

-- Surface and border colour only. Hover and open changes take this path so a state
-- flip never rebuilds the backdrop table.
function DdMeta:_paint()
    local B = SuuUI.Backdrop
    B.SetBg(self._f, "colorBgAlt")
    B.SetBorder(self._f, (self._hovered or self._open)
        and "colorBorderFocus" or "colorBorder")
end

-- The arrow column is as wide as the glyph, and the label's right inset reserves that
-- column plus a gap either side of it. Both move with the font and space tokens.
function DdMeta:_reflow()
    local pad = SuuUI.Theme:GetToken("spaceXs") or 4
    local aw  = arrowWidth()
    self._box:SetChildProps(self._arrowT, {
        align  = "end",
        valign = "center",
        inset  = { right = pad },
        width  = aw,
    })
    self._box:SetChildProps(self._selT, {
        valign = "center",
        inset  = { left = TEXT_INSET, right = pad * 2 + aw },
    })
end

-- Re-derives the button height from the size token and the selected face, unless the
-- caller pinned a height. The frame's resize hook reports the change onwards.
function DdMeta:_autosize()
    if not self._autoH then return end
    local h = faceHeight(self._selT:GetText(), self._selFont,
                         SuuUI.Theme:GetControlHeight("sizeControlLg"))
    if abs((self._f:GetHeight() or 0) - h) <= 0.5 then return end
    self._f:SetHeight(h)
end

-- Builds or reuses one option row inside the row list container. Returns the row and the
-- height it took, which the panel sums rather than assuming every row is the same.
function DdMeta:_row(index, opt)
    local B = SuuUI.Backdrop
    local face = faceOf(opt)
    local h = faceHeight(opt.label, face, rowHeight())

    local row = self._rows[index]
    if not row then
        row = CreateFrame("Frame", nil, self._panel, "BackdropTemplate")
        row:EnableMouse(true)
        row._box = SuuUI.Layout:CreateContainer({ host = row, layout = "stack" })
        -- One Text handle per pooled row, reused as the option list is rebuilt, so a
        -- rebuild never accumulates handles. _lbl stays the font string other code and
        -- the specs reach for.
        row._lblT = SuuUI.Components.Text({ justify = "LEFT" }, row)
        row._lbl  = row._lblT:GetFrame()
        row._box:Add(row._lblT, {
            valign = "center",
            inset  = { left = TEXT_INSET, right = TEXT_INSET },
        })
        self._rows[index] = row
        self._rowList:Add(row, { width = "fill", height = h })
    else
        self._rowList:SetChildProps(row, { width = "fill", height = h })
    end

    B.Apply(row, { bg = "colorBgAlt", border = "colorBorder" })
    row._lblT:SetFont(face)
    row._lblT:SetText(opt.label)
    -- Same reason as _select: a token-sized label does not resize when its face changes,
    -- so the host box has to re-measure it explicitly.
    row._box:Layout()

    local optVal, optLabel = opt.value, opt.label
    -- Hover is transient state: recolour only, never rebuild the backdrop table.
    row:SetScript("OnEnter", function() B.SetBg(row, "colorBgHover") end)
    row:SetScript("OnLeave", function() B.SetBg(row, "colorBgAlt") end)
    local optFont = opt.font
    row:SetScript("OnMouseUp", function()
        local old = self._value
        self._value = optVal
        self:_select({ value = optVal, label = optLabel, font = optFont })
        self:_closePanel()
        if self._onChange then self._onChange(optVal) end
        S:Emit(self, S.SIGNALS.VALUE_CHANGED, optVal, old)
    end)

    row:Show()
    return row, h
end

function DdMeta:_openPanel()
    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceXs") or 4
    local panel = self._panel

    for _, row in ipairs(self._rows) do row:Hide() end
    -- Rows can differ in height when options carry their own faces, so the panel is
    -- sized from what the rows actually took rather than from a single row height.
    local total = 0
    for i, opt in ipairs(self._options) do
        local _, h = self:_row(i, opt)
        total = total + h
    end

    -- Panel placement and size come from the anchor container
    self._panelHost:SetChildAnchor(panel, {
        point         = "TOPLEFT",
        relativeTo    = self._f,
        relativePoint = "BOTTOMLEFT",
        x = 0, y = -2,
        width  = self._f:GetWidth(),
        height = total + gap * 2,
    })
    panel:SetFrameStrata("TOOLTIP")

    panel:SetAlpha(0)
    panel:Show()
    SuuUI.Anim.Presets.FadeIn(panel, T:GetToken("animFast"))

    self._open = true
    self:_paint()

    if self._clickAway then self._clickAway:Arm() end
end

function DdMeta:ApplyTheme()
    local T = SuuUI.Theme
    local B = SuuUI.Backdrop

    local surface = { bg = "colorBgAlt", border = "colorBorder" }
    B.Apply(self._f, surface)
    B.Apply(self._panel, surface)
    -- Rows are only rebuilt when the panel opens, so restyle the pooled ones here too
    -- or an open panel keeps the previous theme's border width.
    for _, row in ipairs(self._rows) do B.Apply(row, surface) end

    -- Re-assert the live state: a theme change must not drop the hover or open ring.
    self:_paint()

    self._selT:ApplyTheme()
    self._arrowT:ApplyTheme()
    -- Font and size tokens both move at runtime, so the height is re-derived after the
    -- label has restyled — it depends on the selected face's metrics at the new size.
    self:_autosize()
    self:_reflow()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show. SetSize and Hide are defined
-- above and survive: one clears the autosize flag, the other closes the panel.
SuuUI.Components.InstallBase(DdMeta, "_f")

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

    -- Registered before the host container adopts the frame so the container chains
    -- onto this hook. A parent layout resizes the frame directly, never via SetSize.
    local handle
    f:SetScript("OnSizeChanged", function(_, w2, h2)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w2, h2)
    end)

    -- Selected label spans the button, arrow pinned to the right edge
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- Text owns the font and colour tokens and re-measures on a token change; the
    -- handles are added so the box re-flows off their SIZE_CHANGED.
    -- Both children's insets are re-derived in _reflow, called from ApplyTheme, so the
    -- arrow column and the label's reserved gutter track the font and space tokens.
    local selT = SuuUI.Components.Text({ justify = "LEFT" }, f)
    box:Add(selT, { valign = "center", inset = { left = TEXT_INSET } })

    local arrowT = SuuUI.Components.Text({ text = ARROW_GLYPH, color = "muted",
                                           justify = "CENTER" }, f)
    box:Add(arrowT, { align = "end", valign = "center" })

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
    handle = setmetatable({
        _f=f, _panel=panel,
        -- _selText and _arrow stay the font strings so callers and specs reach the same
        -- regions; _selT and _arrowT are the Text handles that own them.
        _selT=selT, _arrowT=arrowT,
        _selText=selT:GetFrame(), _arrow=arrowT:GetFrame(),
        _box=box, _panelHost=panelHost, _rowList=rowList,
        _options=props.options or {}, _rows={}, _eid=id,
        _value=props.value, _onChange=props.onChange, _enabled=true,
        _autoH=props.h == nil, _hovered=false, _open=false,
    }, DdMeta)

    if props.value then handle:SetValue(props.value) end

    f:SetScript("OnMouseUp", function()
        if handle._enabled == false then return end
        if panel:IsShown() then handle:_closePanel()
        else handle:_openPanel() end
    end)
    f:SetScript("OnEnter", function()
        handle._hovered = true
        handle:_paint()
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    f:SetScript("OnLeave", function()
        handle._hovered = false
        handle:_paint()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)

    handle._clickAway = SuuUI.Components.ClickAway({
        frame     = panel,
        guards    = { f },
        onOutside = function() handle:_closePanel() end,
    })

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
