local ipairs = ipairs
local S = SuuUI.UISignals

-- Horizontal breathing room inside the button and inside an option row. No space token
-- is 6px, so this stays a literal rather than moving the geometry onto spaceXs/spaceSm.
local TEXT_INSET = 6

-- Option rows hold text, so their height is floored against the font size token.
local function rowHeight()
    return SuuUI.Theme:GetControlHeight("sizeControlMd")
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
            self._selT:SetText(opt.label)
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
        if self._clickAway then self._clickAway:Disarm() end
    end
end

-- Builds or reuses one option row inside the row list container
function DdMeta:_row(index, opt)
    local B = SuuUI.Backdrop

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
        self._rowList:Add(row, { width = "fill", height = rowHeight() })
    else
        self._rowList:SetChildProps(row, { width = "fill", height = rowHeight() })
    end

    B.Apply(row, { bg = "colorBgAlt", border = "colorBorder" })
    row._lblT:SetText(opt.label)

    local optVal, optLabel = opt.value, opt.label
    -- Hover is transient state: recolour only, never rebuild the backdrop table.
    row:SetScript("OnEnter", function() B.SetBg(row, "colorBgHover") end)
    row:SetScript("OnLeave", function() B.SetBg(row, "colorBgAlt") end)
    row:SetScript("OnMouseUp", function()
        local old = self._value
        self._value = optVal
        self._selT:SetText(optLabel)
        self:_closePanel()
        if self._onChange then self._onChange(optVal) end
        S:Emit(self, S.SIGNALS.VALUE_CHANGED, optVal, old)
    end)

    row:Show()
    return row
end

function DdMeta:_openPanel()
    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceXs") or 4
    local panel = self._panel

    for _, row in ipairs(self._rows) do row:Hide() end
    for i, opt in ipairs(self._options) do self:_row(i, opt) end

    -- Panel placement and size come from the anchor container
    self._panelHost:SetChildAnchor(panel, {
        point         = "TOPLEFT",
        relativeTo    = self._f,
        relativePoint = "BOTTOMLEFT",
        x = 0, y = -2,
        width  = self._f:GetWidth(),
        height = #self._options * rowHeight() + gap * 2,
    })
    panel:SetFrameStrata("TOOLTIP")

    panel:SetAlpha(0)
    panel:Show()
    SuuUI.Anim.Presets.FadeIn(panel, T:GetToken("animFast"))

    if self._clickAway then self._clickAway:Arm() end
end

function DdMeta:ApplyTheme()
    local T = SuuUI.Theme
    local B = SuuUI.Backdrop

    -- Font and size tokens both move at runtime, so re-derive the height unless the
    -- caller pinned one, and report it so the containing layout re-flows.
    if self._autoH then
        local h = T:GetControlHeight("sizeControlLg")
        if math.abs((self._f:GetHeight() or 0) - h) > 0.5 then
            self._f:SetHeight(h)
        end
    end

    local surface = { bg = "colorBgAlt", border = "colorBorder" }
    B.Apply(self._f, surface)
    B.Apply(self._panel, surface)
    -- Rows are only rebuilt when the panel opens, so restyle the pooled ones here too
    -- or an open panel keeps the previous theme's border width.
    for _, row in ipairs(self._rows) do B.Apply(row, surface) end

    self._selT:ApplyTheme()
    self._arrowT:ApplyTheme()
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
    local T = SuuUI.Theme
    local selT = SuuUI.Components.Text({ justify = "LEFT" }, f)
    -- The right inset reserves the arrow column: its box plus the arrow's own inset.
    box:Add(selT, {
        valign = "center",
        inset  = { left = TEXT_INSET, right = T:GetToken("spaceLg") or 16 },
    })

    local arrowT = SuuUI.Components.Text({ text = "v", color = "muted",
                                           justify = "CENTER" }, f)
    box:Add(arrowT, {
        align  = "end",
        valign = "center",
        inset  = { right = T:GetToken("spaceXs") or 4 },
        width  = T:GetToken("spaceSm") or 8,
    })

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
        _autoH=props.h == nil,
    }, DdMeta)

    if props.value then handle:SetValue(props.value) end

    f:SetScript("OnMouseUp", function()
        if handle._enabled == false then return end
        if panel:IsShown() then handle:_closePanel()
        else handle:_openPanel() end
    end)
    f:SetScript("OnEnter", function() S:Emit(handle, S.SIGNALS.MOUSE_ENTER) end)
    f:SetScript("OnLeave", function() S:Emit(handle, S.SIGNALS.MOUSE_LEAVE) end)

    handle._clickAway = SuuUI.Components.ClickAway({
        frame     = panel,
        guards    = { f },
        onOutside = function() handle:_closePanel() end,
    })

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
