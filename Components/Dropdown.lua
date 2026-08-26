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

-- The arrow is ATLAS ART, from Core/Icons' shared sheet, and it used to be the ASCII "v" that
-- Accordion still spends on its chevron. The reason for a character in the first place stands and is
-- worth keeping straight: this client's faces do not reliably carry the geometric-shape triangles,
-- so a face missing one draws a box, and "v" is the safe fallback every face has. What a character
-- cannot do is stop looking like a character -- it arrives with the font's own weight, optical
-- centre and baseline -- and it cannot be TURNED OVER, which is the cue that says the panel below is
-- already open. A texture does both.
local ARROW_GLYPH = "chevron"

-- The arrow column is a SQUARE derived from the FONT STEP rather than from sizeIcon. Two reasons.
-- The affordance grew with the label before this change and should keep doing so -- a control whose
-- text is at fontSizeXl with a 16px arrow beside it reads as a mismatch. And sizeIcon (16) inside a
-- 24-unit control leaves the glyph touching the border, the same trap Input's leading glyph
-- documents for its own search icon.
--
-- Snapped here rather than left to the layout strategy: the number is also the label's reserved
-- gutter, so the two have to agree on the same integer or the gap between them drifts by a rounding.
local function arrowSize()
    local T = SuuUI.Theme
    return SuuUI.Pixel.Snap(T:GetToken("fontSizeMd") or 13)
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
    -- The face's own label handle. Easy to miss because the box owns its font string, but the
    -- Text handle holds its own theme subscription and outlives the box without this -- one per
    -- dropdown, for the rest of the session. The arrow needs no counterpart: it is a texture the
    -- frame owns, so it goes when the frame does.
    self._selT:Destroy()
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
    self._f:Hide()
end

--- Extra disabling behaviour beyond the canonical fade + mouse-drop. The panel rows
--- are separate frames with their own mouse — disabling at the root does not block
--- them. Closing the panel when disabling ensures no row click can fire VALUE_CHANGED.
--- Hover state is also cleared so the border returns to rest.
function DdMeta:_onEnabledChanged(en)
    if not en then
        self:_closePanel()
        self._hovered = false
        self:_paint()
    end
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
    -- The surface is overridable because a dropdown is not always on the page's own background. On a
    -- window's TITLE STRIP -- which is itself colorBgAlt -- the default makes the field invisible: you
    -- get a focus ring with nothing behind it, which reads as a stray outline rather than a control.
    -- The concept's own `.dd` is darker than the strip it sits on, for exactly this reason.
    B.SetBg(self._f, self._bg or "colorBgAlt")
    B.SetBorder(self._f, (self._hovered or self._open)
        and "colorBorderFocus" or "colorBorder")
    self:_paintArrow()
end

-- The arrow's glyph, crop, tint and ORIENTATION. Called from _paint, so it follows hover and open
-- through the same path the border ring does -- the arrow lighting up with the ring is one cue in two
-- places rather than a second meaning, which is the distinction a new indicator has to earn.
function DdMeta:_paintArrow()
    local tex = self._arrow
    if not tex then return end
    local path, c = SuuUI.Icons:Get(ARROW_GLYPH)
    -- A glyph the sheet does not carry would raise from inside ApplyTheme, which the constructor
    -- calls -- so a renamed cell would cost the login rather than the arrow. The dropdown's spec
    -- asserts Icons:Has(ARROW_GLYPH) so the rename is caught there instead.
    if not (path and c) then return end
    tex:SetTexture(path)

    -- TURNED OVER WHILE OPEN, by swapping top and bottom: the chevron then points back at the
    -- button rather than at a panel that is already showing. The client offers no rotation for a
    -- plain texture and this needs none, since a vertical flip of a symmetrical chevron IS the
    -- 180-degree rotation. This is the whole reason the glyph is art and not a character.
    if self._open then
        tex:SetTexCoord(c[1], c[2], c[4], c[3])
    else
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    end

    -- White art, tinted here, exactly as the sheet's docstring requires -- any hue baked into the
    -- texture would ignore the theme.
    local col = SuuUI.Theme:GetToken((self._hovered or self._open)
        and "colorAccent" or "colorTextMuted")
    if col then tex:SetVertexColor(col[1], col[2], col[3], col[4]) end
end

-- The arrow column is a square as wide as the font step, and the label's right inset reserves that
-- column plus a gap either side of it. Both move with the font and space tokens.
--
-- HEIGHT IS STATED AS WELL AS WIDTH, which the font string it replaced did not need: a stack child
-- pins neither axis on its own, so an unstated height stretches the texture to the button's full
-- inner height and the chevron comes out as a tall smear rather than a glyph.
function DdMeta:_reflow()
    local pad = SuuUI.Theme:GetToken("spaceXs") or 4
    local aw  = arrowSize()
    self._box:SetChildProps(self._arrow, {
        align  = "end",
        valign = "center",
        inset  = { right = pad },
        width  = aw,
        height = aw,
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
        -- Guard against row clicks on a disabled dropdown. The panel should already be
        -- closed by _onEnabledChanged, but a race between the fade-out animation and a
        -- click landing on the row could still fire this.
        if self._enabled == false then return end
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
    SuuUI.UIRoot:SetLayer(panel, "tooltip")

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

    -- Re-assert the live state: a theme change must not drop the hover or open ring. This also
    -- re-tints and re-crops the arrow, so a retint or a regenerated sheet reaches it.
    self:_paint()

    self._selT:ApplyTheme()
    -- Font and size tokens both move at runtime, so the height is re-derived after the
    -- label has restyled — it depends on the selected face's metrics at the new size.
    self:_autosize()
    self:_reflow()
    -- A live opacityDisabled edit reaches an already-disabled widget.
    self:_applyEnabled()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show. SetSize and Hide are defined
-- above and survive: one clears the autosize flag, the other closes the panel.
SuuUI.Components.InstallBase(DdMeta, "_f")
-- Installs SetEnabled, IsEnabled, _applyEnabled via the canonical fade mechanism.
SuuUI.Components.InstallEnable(DdMeta, "_f")

--- Creates a custom dropdown.
-- Emits VALUE_CHANGED (new, old), ENABLED_CHANGED, VISIBILITY_CHANGED.
-- @param props table  { options, value, onChange, w, h }
--   options: array of { value, label }
-- @param parent frame
-- @return table  Dropdown handle
function SuuUI.Components.Dropdown(props, parent)
    -- An optional global name, following "SuuUI_" .. pluginId .. "_" .. role. Anonymous by default,
    -- as every pooled or throwaway frame is -- but a control in a window's chrome is one an in-game
    -- probe has to be able to reach by name when it misbehaves, and there is no other route to it.
    local f = CreateFrame("Frame", props.name, parent, "BackdropTemplate")
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
    -- handle is added so the box re-flows off its SIZE_CHANGED.
    -- Both children's insets are re-derived in _reflow, called from ApplyTheme, so the
    -- arrow column and the label's reserved gutter track the font and space tokens.
    local selT = SuuUI.Components.Text({ justify = "LEFT" }, f)
    box:Add(selT, { valign = "center", inset = { left = TEXT_INSET } })

    -- A plain TEXTURE rather than a Components.Icon, the same call DataField's leading glyph makes:
    -- nothing here needs measuring, reflowing or a border, only offsetting, and an Icon would spend a
    -- frame on it. ARTWORK so it draws above the backdrop. It is painted by _paintArrow, which
    -- ApplyTheme reaches through _paint at the end of this constructor.
    local arrow = f:CreateTexture(nil, "ARTWORK")
    box:Add(arrow, { align = "end", valign = "center" })

    -- Panel floats over everything, placed by the shared floating host.
    --
    -- PARENTED TO THE HOST, NOT UIParent, and the distinction is the whole bug this line used to
    -- carry: the host only decides WHERE the panel sits, while the PARENT decides what a unit is.
    -- The floating host is itself hosted on the UI root, and the root carries the pixel grid's
    -- scale -- so a panel on UIParent measured its own units against the client's frame while the
    -- button measured against the root, and its labels rendered at the ratio between the two.
    -- fontSizeMd is 13 either way; at 1080p the button drew it 9.24 physical pixels tall and the
    -- panel drew it 13.00, so every option row looked 40% larger than the selection above it.
    --
    -- Invisible at the default multiplier, which is why it survived: the two scales coincide at
    -- 768p and the suite's default client is a 1:1 grid. The spec pins it at physicalHeight 1080.
    local panelHost = SuuUI.Layout:GetFloatingHost()
    local panel = CreateFrame("Frame", nil, panelHost:GetFrame(), "BackdropTemplate")
    panel:Hide()
    panelHost:Add(panel, { anchor = { point = "TOPLEFT", x = 0, y = 0 } })

    local rowList = SuuUI.Layout:CreateContainer({
        host = panel, layout = "flow", dir = "vertical", gap = 0,
        padding = { top = SuuUI.Theme:GetToken("spaceXs") or 4 },
    })

    local id = "dd_" .. tostring(f)
    handle = setmetatable({
        _f=f, _panel=panel,
        -- _selText stays the font string so callers and specs reach the same region; _selT is the
        -- Text handle that owns it. _arrow IS the texture -- there is no handle wrapping it.
        _selT=selT,
        _selText=selT:GetFrame(), _arrow=arrow,
        _box=box, _panelHost=panelHost, _rowList=rowList,
        _options=props.options or {}, _rows={}, _eid=id,
        _value=props.value, _onChange=props.onChange, _enabled=true,
        _autoH=props.h == nil, _hovered=false, _open=false, _bg=props.bg,
    }, DdMeta)

    if props.value then handle:SetValue(props.value) end

    f:SetScript("OnMouseUp", function()
        if handle._enabled == false then return end
        if panel:IsShown() then handle:_closePanel()
        else handle:_openPanel() end
    end)
    f:SetScript("OnEnter", function()
        if handle._enabled == false then return end
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
