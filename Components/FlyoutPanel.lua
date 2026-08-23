-- A floating vertical roster: one row per entry, an adopted icon on the left and that entry's
-- name to the right of it, closing when the cursor leaves the panel.
--
-- Nothing here knows about minimap buttons. A guild roster, a gearset switcher and an addon
-- button tray are the same shape -- a list of things each identified by an icon and a name --
-- which is why this is a component rather than a panel living inside one plugin.
--
-- It ADOPTS the frame it displays, and that is load-bearing rather than incidental: the rows
-- hold frames another addon created, so hiding the panel has to hide them too, and only
-- PARENTAGE does that. A frame merely anchored to the panel stays on screen after the panel
-- goes away. The panel therefore reparents in SetRows and puts nothing back in Clear -- it
-- never knew where the frame came from. Whoever handed it over owns the restore.
local ipairs, max, type, tostring = ipairs, math.max, type, tostring
local S = SuuUI.UISignals

local PanelMeta = {}
PanelMeta.__index = PanelMeta

-- The icon column's own size. A row holds text as well, so its height is floored against the
-- font metrics the same way every other text-bearing control is -- an icon larger than the
-- text step grows the row, a smaller one does not shrink it below a readable line.
function PanelMeta:_rowHeight()
    local T = SuuUI.Theme
    return max(T:GetControlHeight("sizeControlMd"),
               self._iconSize + (T:GetToken("spaceXxs") or 2) * 2)
end

-- Widest label in the set, measured through Box rather than Measure: the number becomes the
-- font string's OWN box, and the client truncates with zero tolerance, so a box at the bare
-- metric is a clip. Re-measured on every rebuild and every theme change, since the font face
-- and step are both user-editable.
function PanelMeta:_labelWidth()
    local T = SuuUI.Theme
    local font = SuuUI.Fonts:Path(T:GetToken("fontFamilyMain"))
    local size = T:GetToken("fontSizeMd") or 13
    local w = 0
    for _, entry in ipairs(self._entries) do
        local bw = SuuUI.TextMetrics.Box(entry.label or "", font, size)
        if bw > w then w = bw end
    end
    return w
end

-- Builds or reuses one row. Rows are pooled exactly as Dropdown's option rows are: the set
-- is rebuilt whenever the roster changes, and a fresh frame per rebuild would leak a frame
-- and a Text handle every time.
--
-- Every part is a DIRECT child of one stack, with the label's left inset reserving the icon
-- column -- the same arrangement Dropdown uses to reserve its arrow column. The obvious build
-- is a nested horizontal flow for "icon then label", and it hangs the client: a flow with no
-- height of its own hugs its content, a stack child with valign "stretch" is sized by its
-- parent, and a container that is both takes its height from the stack while the stack takes
-- its height from it. They ping-pong forever on the first layout pass.
function PanelMeta:_row(index)
    local T = SuuUI.Theme
    local row = self._rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, self._panel, "BackdropTemplate")
    row._box = SuuUI.Layout:CreateContainer({ host = row, layout = "stack" })

    -- The rail sits in the row's left gutter, where the label's inset keeps it clear of the
    -- text -- the same accent-rail cue Accordion and DataField paint.
    row._rail = row:CreateTexture(nil, "ARTWORK")
    row._railProps = { align = "start", valign = "stretch",
                       width = SuuUI.Pixel.Line(T:GetToken("sizeRail") or 2) }
    row._box:Add(row._rail, row._railProps)

    row._labelT = SuuUI.Components.Text({ justify = "LEFT" }, row)
    row._label  = row._labelT:GetFrame()
    row._labelProps = { valign = "center", inset = { left = 0, right = 0 } }
    row._box:Add(row._labelT, row._labelProps)

    row._iconProps = { align = "start", valign = "center", inset = { left = 0 } }

    self._rows[index] = row
    self._rowList:Add(row, { width = "fill", height = self:_rowHeight() })
    return row
end

-- Hover paint only: bg plus the rail's alpha. Never rebuilds the backdrop table, since this
-- runs on every cursor movement across the roster.
function PanelMeta:_paintRow(row, hovered)
    local B = SuuUI.Backdrop
    if hovered then
        B.SetBg(row, "colorBgHover")
    else
        B.SetBg(row, false)
    end
    row._rail:SetShown(hovered and row._interactive == true)
end

--- Replaces the roster. Each entry is { key, label, frame, onClick }.
--- `frame` is ADOPTED -- reparented into the row, so the panel's visibility governs it.
--- `onClick(entry, mouseButton)` makes the whole row a click target; omit it and only the
--- adopted frame itself is clickable, and the row paints no rail.
-- @param entries table  Array of { key, label, frame, onClick }
-- Lifts an adopted frame above this panel's own backdrop.
--
-- This is the difference between a roster of names and a roster of icons. LibDBIcon builds every
-- button it makes with SetFrameStrata("MEDIUM") followed by SetFixedFrameStrata(true), and the
-- FIXED part is what bites: a pinned frame does NOT re-inherit its new parent's strata, so an
-- adopted button stays on MEDIUM while this panel sits on the tooltip rung, and it draws behind
-- a backdrop that carries opacityPanel. The labels are ours and appear; the icons are theirs and
-- do not. The pin has to be RELEASED before the strata can be re-stated -- writing the strata
-- first is silently ignored, which is what makes this look like a layout fault rather than a
-- z-order one.
--
-- Re-asserted on every rebuild rather than once at adoption, because the owning addon is free
-- to re-pin its own button at any point and this is a handful of calls.
function PanelMeta:_raise(frame)
    if type(frame.SetFixedFrameStrata) == "function" then
        pcall(frame.SetFixedFrameStrata, frame, false)
    end
    if type(frame.SetFixedFrameLevel) == "function" then
        pcall(frame.SetFixedFrameLevel, frame, false)
    end
    -- Through the layer system, never a raw strata string: same rung as the panel, above it.
    pcall(SuuUI.UIRoot.RaiseAbove, SuuUI.UIRoot, frame, self._panel, 2)
end

-- Every adopted frame currently held by a row.
function PanelMeta:_raiseAll()
    for _, row in ipairs(self._rows) do
        if row._held then self:_raise(row._held) end
    end
end

function PanelMeta:SetRows(entries)
    local T = SuuUI.Theme
    self._entries = entries or {}

    for _, row in ipairs(self._rows) do row:Hide() end

    local rowH   = self:_rowHeight()
    local labelW = self:_labelWidth()
    local pad    = T:GetToken("spaceXs") or 4
    local gutter = T:GetToken("spaceSm") or 8
    local gap    = T:GetToken("spaceSm") or 8
    local rowGap = T:GetToken("spaceXxs") or 2

    for i, entry in ipairs(self._entries) do
        local row = self:_row(i)
        row._interactive = type(entry.onClick) == "function"
        self._rowList:SetChildProps(row, { width = "fill", height = rowH })

        row._iconProps.width      = self._iconSize
        row._iconProps.height     = self._iconSize
        row._iconProps.inset.left = gutter

        -- The label is inset past the icon column rather than flowed after it, so nothing in
        -- the row derives its height from the row's own height. See _row.
        row._labelProps.inset.left  = gutter + self._iconSize + gap
        row._labelProps.inset.right = gutter
        row._box:SetChildProps(row._labelT, row._labelProps)
        row._labelT:SetText(entry.label or "")

        -- Swapped only when the frame actually differs. Add is a MEMBERSHIP operation, not an
        -- upsert, so re-adding on every rebuild appends the same child again and again: the
        -- child list grows without bound and each pass costs more than the last.
        if row._held and row._held ~= entry.frame then
            row._box:Remove(row._held)
            row._held = nil
        end
        if entry.frame then
            if row._held ~= entry.frame then
                -- Parented to the stack's OWN host frame, which is the row. A hidden frame
                -- has no rect and a child anchored to one never resolves a position, so a
                -- foreign frame parented anywhere else would draw nothing while still
                -- reporting the size it was assigned -- the trap LAYOUT_SYSTEM.md names.
                entry.frame:SetParent(row)
                row._box:Add(entry.frame, row._iconProps)
                row._held = entry.frame
            else
                row._box:SetChildProps(entry.frame, row._iconProps)
            end
            self:_raise(entry.frame)
        end

        -- Mouse is enabled only for a row that can actually do something, so the highlight
        -- and the rail never promise an interaction that is not there.
        row:EnableMouse(row._interactive)
        row:SetScript("OnEnter", function() self:_paintRow(row, true) end)
        row:SetScript("OnLeave", function() self:_paintRow(row, false) end)
        row:SetScript("OnMouseUp", function(_, btn)
            if not row._interactive then return end
            entry.onClick(entry, btn or "LeftButton")
        end)

        self:_paintRow(row, false)
        row:Show()
    end

    local n = #self._entries
    self._contentW = pad * 2 + gutter * 2 + self._iconSize + gap + labelW
    self._contentH = pad * 2 + n * rowH + max(0, n - 1) * rowGap
end

--- Number of rows currently in the roster.
-- @return number
function PanelMeta:GetRowCount()
    return #self._entries
end

--- Sets the square each adopted frame is fitted into. The size is a property of the things
--- being shown rather than of the panel -- a roster of minimap buttons cannot know how big
--- they are until it has found them -- so it arrives after construction. A no-op when
--- unchanged, because this is called on every rebuild and each real change re-measures and
--- re-lays out every row.
-- @param size number
function PanelMeta:SetIconSize(size)
    if type(size) ~= "number" or size <= 0 then return end
    if self._iconSize == size then return end
    self._iconSize = size
    self:SetRows(self._entries)
    if self:IsOpen() then self:_place() end
end

--- The current icon column size.
-- @return number
function PanelMeta:GetIconSize()
    return self._iconSize
end

-- Places and sizes the panel against its anchor. `align` decides which vertical edge lines
-- up, so a field in the bar's right section drops a panel that stays on screen.
function PanelMeta:_place()
    local point, relPoint
    if self._align == "right" then
        point, relPoint = "TOPRIGHT", "BOTTOMRIGHT"
    else
        point, relPoint = "TOPLEFT", "BOTTOMLEFT"
    end
    self._host:SetChildAnchor(self._panel, {
        point         = point,
        relativeTo    = self._anchorTo,
        relativePoint = relPoint,
        -- Flush against the anchor on purpose: any gap is a strip the cursor crosses where
        -- neither rect contains it, which is exactly what HoverAway's grace period is
        -- absorbing. Removing the gap removes most of the need for it.
        x = 0, y = 0,
        width  = self._contentW or 0,
        height = self._contentH or 0,
    })
end

--- Shows the panel and arms the close-on-leave watcher.
function PanelMeta:Open()
    if self._panel:IsShown() then
        self:_place()
        return
    end
    -- Shown BEFORE the rows are placed. A hidden frame has no rect, so the adopted frames
    -- anchored inside it would never resolve a position -- they would report their assigned
    -- size, report as shown, and draw nothing.
    self._panel:SetAlpha(0)
    self._panel:Show()
    self:_place()
    SuuUI.UIRoot:SetLayer(self._panel, "tooltip")
    -- Re-asserted after the panel's own layer is (re-)stated, since that can move the level
    -- every adopted frame was lifted above.
    self:_raiseAll()
    SuuUI.Anim.Presets.FadeIn(self._panel, SuuUI.Theme:GetToken("animFast"))
    self._hoverAway:Arm()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

--- Hides the panel and disarms the watcher.
function PanelMeta:Close()
    self._hoverAway:Disarm()
    if not self._panel:IsShown() then return end
    self._panel:Hide()
    for _, row in ipairs(self._rows) do self:_paintRow(row, false) end
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

--- Whether the panel is currently on screen.
-- @return bool
function PanelMeta:IsOpen()
    return self._panel:IsShown() and true or false
end

function PanelMeta:ApplyTheme()
    local T = SuuUI.Theme
    local B = SuuUI.Backdrop

    B.Apply(self._panel, { bg = "colorBg", border = "colorBorder" })
    self._rowList:SetPadding({ top = T:GetToken("spaceXs") or 4,
                               right = T:GetToken("spaceXs") or 4,
                               bottom = T:GetToken("spaceXs") or 4,
                               left = T:GetToken("spaceXs") or 4 })
    self._rowList:SetGap(T:GetToken("spaceXxs") or 2)

    local railC = T:GetToken("colorAccent")
    for _, row in ipairs(self._rows) do
        row._railProps.width = SuuUI.Pixel.Line(T:GetToken("sizeRail") or 2)
        row._box:SetChildProps(row._rail, row._railProps)
        if railC then row._rail:SetColorTexture(railC[1], railC[2], railC[3], railC[4]) end
        -- The event bus fires newest-first, so an owned child's own subscription may not have
        -- run yet: without this the row measures the previous font.
        row._labelT:ApplyTheme()
    end

    -- Row heights and the label column both come from tokens, so a restyle re-derives the
    -- whole roster rather than keeping the geometry measured under the old theme.
    self:SetRows(self._entries)
    if self:IsOpen() then self:_place() end
end

function PanelMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._hoverAway:Destroy()
    for _, row in ipairs(self._rows) do
        -- Dropped from the layout but NOT restored: the panel never knew where the frame came
        -- from. Whoever handed it over owns putting it back, and does so after this.
        if row._held then
            row._box:Remove(row._held)
            row._held = nil
        end
        row._labelT:Destroy()
        row._box:Destroy()
        row:Hide()
    end
    self._rowList:Destroy()
    -- The floating host is shared by every transient panel in the addon: drop ours, never
    -- destroy the host.
    self._host:Remove(self._panel)
    self._panel:Hide()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize, Show, Hide.
SuuUI.Components.InstallBase(PanelMeta, "_panel")

--- Creates a floating icon-and-name roster panel.
-- Emits VISIBILITY_CHANGED (isVisible).
--
-- Deliberately no SetEnabled: a roster holds other things' controls rather than being one,
-- so there is no value to grey, and a root-frame fade would multiply with the fade of
-- anything disabled inside it.
-- @param props table  { anchorTo, align, iconSize }
--   anchorTo: the frame the panel hangs beneath (required)
--   align:    "left" (default) or "right" -- which vertical edge lines up with the anchor
--   iconSize: the square each adopted frame is fitted into; defaults to sizeIcon
-- @param parent frame
-- @return table  FlyoutPanel handle
function SuuUI.Components.FlyoutPanel(props, parent)
    props = props or {}
    local T = SuuUI.Theme

    local host  = SuuUI.Layout:GetFloatingHost()
    local panel = CreateFrame("Frame", props.name, parent or UIParent, "BackdropTemplate")
    panel:Hide()
    -- Mouse enabled so the panel itself counts as "inside" for the hover watcher, and so a
    -- click landing in the gutter between rows does not fall through to the world.
    panel:EnableMouse(true)
    host:Add(panel, { anchor = { point = "TOPLEFT", x = 0, y = 0 } })
    -- Stated at construction, not only on Open: _raise lifts adopted frames onto this panel's
    -- rung, and it runs from SetRows -- which happens BEFORE the first Open. With the layer
    -- registered later, RaiseAbove has no rung to resolve and silently leaves a pinned foreign
    -- frame on whatever strata its owner gave it.
    SuuUI.UIRoot:SetLayer(panel, "tooltip")

    local rowList = SuuUI.Layout:CreateContainer({
        host = panel, layout = "flow", dir = "vertical",
        gap = T:GetToken("spaceXxs") or 2,
        padding = { top = T:GetToken("spaceXs") or 4, right = T:GetToken("spaceXs") or 4,
                    bottom = T:GetToken("spaceXs") or 4, left = T:GetToken("spaceXs") or 4 },
    })

    local id = "flyout_" .. tostring(panel)
    local handle = setmetatable({
        _panel    = panel,
        _host     = host,
        _rowList  = rowList,
        _rows     = {},
        _entries  = {},
        _eid      = id,
        _anchorTo = props.anchorTo,
        _align    = props.align == "right" and "right" or "left",
        _iconSize = props.iconSize or T:GetToken("sizeIcon") or 16,
    }, PanelMeta)

    handle._hoverAway = SuuUI.Components.HoverAway({
        frame     = panel,
        guards    = props.anchorTo and { props.anchorTo } or nil,
        onOutside = function() handle:Close() end,
    })

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
