local pairs, ipairs, type, assert = pairs, ipairs, type, assert
local tinsert, tremove = table.insert, table.remove
local ceil, abs, min = math.ceil, math.abs, math.min

local strategies = {
    flow   = function(c) SuuUI._FlowLayout.Apply(c) end,
    grid   = function(c) SuuUI._GridLayout.Apply(c) end,
    anchor = function(c) SuuUI._AnchorLayout.Apply(c) end,
    stack  = function(c) SuuUI._StackLayout.Apply(c) end,
}

local ContMeta = {}
ContMeta.__index = ContMeta

--- Returns the raw WoW frame this container lays out inside.
-- @return frame
function ContMeta:GetFrame()
    return self._frame
end

--- Returns the container's current width.
-- @return number
function ContMeta:GetWidth()
    return self._frame:GetWidth()
end

--- Returns the container's current height.
-- @return number
function ContMeta:GetHeight()
    return self._frame:GetHeight()
end

--- Sets the container width and re-runs layout.
-- @param w number
function ContMeta:SetWidth(w)
    self._frame:SetWidth(w)
    self:Layout()
end

--- Sets the container height and re-runs layout.
-- @param h number
function ContMeta:SetHeight(h)
    self._frame:SetHeight(h)
    self:Layout()
end

--- Sets container size and re-runs layout.
-- @param w number
-- @param h number
function ContMeta:SetSize(w, h)
    self._frame:SetSize(w, h)
    self:Layout()
end

--- Sets the gap between children and re-runs layout.
-- Gaps come from spacing tokens, which are user-editable, so anything that reads a token
-- at build time needs a way to re-state it when the theme changes.
-- @param gap number
function ContMeta:SetGap(gap)
    self._gap = gap or 0
    self:Layout()
end

--- Returns the current gap between children.
-- @return number
function ContMeta:GetGap()
    return self._gap
end

--- Shows the container. Emits VISIBILITY_CHANGED.
function ContMeta:Show()
    self._frame:Show()
    SuuUI.UISignals:Emit(self, SuuUI.UISignals.SIGNALS.VISIBILITY_CHANGED, true)
end

--- Hides the container. Emits VISIBILITY_CHANGED.
function ContMeta:Hide()
    self._frame:Hide()
    SuuUI.UISignals:Emit(self, SuuUI.UISignals.SIGNALS.VISIBILITY_CHANGED, false)
end

--- Returns whether the container is shown.
-- @return bool
function ContMeta:IsShown()
    return self._frame:IsShown()
end

-- Layout strategies position frames; signals are emitted by handles. Unwrap once
-- here so components never need to reimplement the frame interface.
local function targetOf(child)
    if type(child) == "table" and child.GetFrame then return child:GetFrame() end
    return child
end

--- Adds a child to the container and re-runs layout.
-- Accepts a raw frame/texture/fontstring, a component handle, or another container.
-- @param child frame|table
-- @param layoutProps table  Optional strategy-specific properties
--   flow/grid: { width, height, align }
--   stack:     { inset, align, valign, width, height }
--   anchor:    { anchor = { point, relativeTo, relativePoint, x, y, width, height } }
function ContMeta:Add(child, layoutProps)
    local target = targetOf(child)
    if layoutProps then target._layoutProps = layoutProps end

    -- A nested container stops sizing its own frame on any axis the parent controls
    if getmetatable(child) == ContMeta then
        child._managed = true
        local h = layoutProps and layoutProps.height
        if h == "fill" or type(h) == "number" or self._layoutType == "stack" then
            child._hug = false
        end
    end

    tinsert(self._children, target)
    self._sources[target] = child

    -- Re-layout when a child reports a new size
    local connId = SuuUI.UISignals:Connect(child, SuuUI.UISignals.SIGNALS.SIZE_CHANGED, function()
        self:Layout()
    end)
    self._childConns[child] = connId

    self:Layout()
    return child
end

--- Updates one child's layout properties and re-runs layout.
-- Use this instead of repositioning a child by hand.
-- @param child frame|table
-- @param layoutProps table
function ContMeta:SetChildProps(child, layoutProps)
    local target = targetOf(child)
    target._layoutProps = layoutProps
    self:Layout()
end

--- Updates one child's anchor descriptor (anchor layout) and re-runs layout.
-- @param child frame|table
-- @param anchorDesc table  { point, relativeTo, relativePoint, x, y, width, height }
function ContMeta:SetChildAnchor(child, anchorDesc)
    local target = targetOf(child)
    target._layoutProps = target._layoutProps or {}
    target._layoutProps.anchor = anchorDesc
    self:Layout()
end

--- Updates one child's fractional size on a single axis and re-runs layout (stack layout).
-- This is how a progress fill states "I am 60% of the track" without ever touching a
-- point: the strategy recomputes the pixel size from the container's current box on
-- every pass, so the fill stays correct through resizes and theme changes for free.
-- Merges into the child's existing props, so inset and alignment survive the update.
-- @param child frame|table
-- @param axisName string  "width" | "height"
-- @param fraction number  0..1, clamped
function ContMeta:SetChildFraction(child, axisName, fraction)
    assert(axisName == "width" or axisName == "height",
        "SuuUI Container: SetChildFraction axis must be \"width\" or \"height\"")
    local target = targetOf(child)
    target._layoutProps = target._layoutProps or {}
    target._layoutProps[axisName .. "Fraction"] = fraction
    self:Layout()
end

--- Removes a child and re-runs layout. Accepts the handle or its frame.
-- @param child frame|table
function ContMeta:Remove(child)
    local target = targetOf(child)
    local source = self._sources[target] or child

    local connId = self._childConns[source]
    if connId then
        -- Only drop our own connection, never the child's other listeners
        SuuUI.UISignals:Disconnect(source, SuuUI.UISignals.SIGNALS.SIZE_CHANGED, connId)
        self._childConns[source] = nil
    end
    self._sources[target] = nil

    for i = #self._children, 1, -1 do
        if self._children[i] == target then
            tremove(self._children, i)
            break
        end
    end
    self:Layout()
end

--- Removes and hides every child, then re-runs layout.
function ContMeta:Clear()
    for i = #self._children, 1, -1 do
        local target = self._children[i]
        local source = self._sources[target] or target
        local connId = self._childConns[source]
        if connId then
            SuuUI.UISignals:Disconnect(source, SuuUI.UISignals.SIGNALS.SIZE_CHANGED, connId)
            self._childConns[source] = nil
        end
        if source.Hide then source:Hide() end
        self._sources[target] = nil
        tremove(self._children, i)
    end
    self:Layout()
end

--- Returns the container's children in insertion order.
-- @return table
function ContMeta:GetChildren()
    return self._children
end

--- Re-calculates and applies child positions. Emits SIZE_CHANGED when the size changes.
function ContMeta:Layout()
    if self._laying then return end
    local fn = strategies[self._layoutType]
    if not fn then return end

    self._laying = true
    fn(self)

    -- Half the grid step, so a change of one pixel is always significant. A flat 0.5
    -- would swallow a real move on a high-DPI display, where a pixel is a third of a unit.
    local eps = min(0.5, SuuUI.Pixel.grid / 2)

    -- Hug content height when nothing else owns this container's height
    if self._hug then
        local _, contentH = self:GetContentSize()
        if abs((self._frame:GetHeight() or 0) - contentH) > eps then
            self._frame:SetHeight(contentH)
            -- Cross-axis alignment is measured against the container's own height, so
            -- re-run the strategy now that hugging has settled it. The resize itself
            -- cannot re-enter: the _laying guard is still held.
            fn(self)
        end
    end
    self._laying = false

    local w, h = self._frame:GetWidth(), self._frame:GetHeight()
    if abs((self._lastW or -1) - w) > eps or abs((self._lastH or -1) - h) > eps then
        self._lastW, self._lastH = w, h
        SuuUI.UISignals:Emit(self, SuuUI.UISignals.SIGNALS.SIZE_CHANGED, w, h)
    end
end

--- Returns computed bounding size of all children.
-- @return number, number  width, height
function ContMeta:GetContentSize()
    local pad = self._padding
    local gap = SuuUI.Pixel.Snap(self._gap)
    local n   = #self._children
    local pxceil = SuuUI.Pixel.Ceil

    if n == 0 then
        return pxceil(pad.left + pad.right), pxceil(pad.top + pad.bottom)
    end

    if self._layoutType == "stack" then
        return SuuUI._StackLayout.ContentSize(self)

    elseif self._layoutType == "flow" then
        if self._dir == "vertical" then
            local maxW, totalH = 0, pad.top + pad.bottom
            for i, child in ipairs(self._children) do
                local w = child:GetWidth() or 0
                if w > maxW then maxW = w end
                totalH = totalH + (child:GetHeight() or 0)
                if i < n then totalH = totalH + gap end
            end
            return pxceil(maxW + pad.left + pad.right), pxceil(totalH)
        end

        local maxH, totalW = 0, pad.left + pad.right
        for i, child in ipairs(self._children) do
            local props = child._layoutProps or {}
            -- A content-hug child is measured, not read back: its pinned width is
            -- whatever the last pass assigned, which predates any text change.
            local w = (props.width == "auto")
                      and SuuUI._FlowLayout.NaturalWidth(child)
                      or (child:GetWidth() or 0)
            local h = child:GetHeight() or 0
            if h > maxH then maxH = h end
            totalW = totalW + w
            if i < n then totalW = totalW + gap end
        end
        return pxceil(totalW), pxceil(maxH + pad.top + pad.bottom)

    elseif self._layoutType == "grid" then
        local cols = self._cols
        local rows = ceil(n / cols)
        -- Sum the real column widths: the strategy spreads the flooring remainder across
        -- the leftmost columns, so cols * firstWidth no longer describes the row.
        local widths, colGap = SuuUI._GridLayout.columnWidths(self)
        local totalW = pad.left + pad.right + colGap * (cols - 1)
        for c = 1, cols do totalW = totalW + (widths[c] or 0) end

        local totalH = pad.top + pad.bottom
        for r = 1, rows do
            local rowH = 0
            for c = 1, cols do
                local idx = (r - 1) * cols + c
                if idx <= n then
                    local h = self._children[idx]:GetHeight() or 0
                    if h > rowH then rowH = h end
                end
            end
            totalH = totalH + rowH
            if r < rows then totalH = totalH + colGap end
        end

        return pxceil(totalW), pxceil(totalH)
    end

    return self._frame:GetWidth(), self._frame:GetHeight()
end

--- Destroys the container and every child it owns, dropping all connections.
-- Retires the parent-resize tracker installed for a fill container: the handler itself
-- cannot be safely unhooked (something may have chained onto it since), so it is flagged
-- dead and returns early instead of resizing a destroyed frame on every parent resize.
function ContMeta:Destroy()
    self._destroyed = true
    for child, connId in pairs(self._childConns) do
        SuuUI.UISignals:Disconnect(child, SuuUI.UISignals.SIGNALS.SIZE_CHANGED, connId)
        if child.Destroy and child ~= self then child:Destroy() end
    end
    self._childConns = {}
    self._sources    = {}
    self._children   = {}
    SuuUI.UISignals:DisconnectAll(self)
    if not self._adopted then self._frame:Hide() end
end

local floatingHost

--- Returns the shared anchor container for floating panels (dropdown panels,
-- tooltips, popups). Transient panels must use this rather than each creating their
-- own screen-level container, which would accumulate resize handlers on UIParent.
-- Remove your panel from it when you destroy it; never destroy the host itself.
-- @return table  Container handle (anchor layout)
function SuuUI.Layout:GetFloatingHost()
    if not floatingHost then
        -- Same invariant as ColorPopup: the host is cached for the session, so falling back
        -- to UIParent would permanently bind every floating panel to the client's own frame
        -- — and install the resize handler on UIParent that this host exists to avoid.
        -- UIRoot:AddElement asserts the same way; a cached singleton deserves it more.
        local parent = SuuUI.UIRoot and SuuUI.UIRoot.GetRoot and SuuUI.UIRoot:GetRoot()
        assert(parent, "SuuUI Layout: GetFloatingHost() requires UIRoot:Init() to have run")
        floatingHost = self:CreateContainer({ host = parent, layout = "anchor" })
    end
    return floatingHost
end

--- Creates a new Container with a layout strategy.
-- @param props table  { parent, host, layout, dir, gap, padding, cols, align, valign, fill, w, h }
--   parent: frame the container is created inside
--   host:   adopt an existing frame as the layout box instead of creating one.
--           Components use this so internal layout costs no extra frame.
--   fill:   mirror the parent's size and track its resizes
--   layout: "flow" | "grid" | "anchor" | "stack"
-- @return table  Container handle
function SuuUI.Layout:CreateContainer(props)
    assert(props.parent or props.host, "SuuUI Container: parent or host required")

    local padInput = props.padding or {}
    local pad = {
        top    = padInput.top    or 0,
        right  = padInput.right  or 0,
        bottom = padInput.bottom or 0,
        left   = padInput.left   or 0,
    }

    local f, adopted, parentFrame
    if props.host then
        f = props.host.GetFrame and props.host:GetFrame() or props.host
        adopted = true
    else
        parentFrame = props.parent.GetFrame and props.parent:GetFrame() or props.parent
        f = CreateFrame("Frame", nil, parentFrame)
        -- Self-anchor: nothing outside the layout engine ever positions a container.
        -- A parent container overrides this when it lays the container out.
        f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, 0)
        -- Size explicitly rather than relying on anchor-derived geometry: WoW does not
        -- resolve anchor sizes for frames that have never been laid out (e.g. inside a
        -- window that starts hidden), which would report 0 and collapse every child.
        f:SetWidth(props.w or parentFrame:GetWidth() or 0)
        if props.fill then
            f:SetHeight(parentFrame:GetHeight() or 0)
        elseif props.h then
            f:SetHeight(props.h)
        end
    end

    local handle = setmetatable({
        _frame       = f,
        _adopted     = adopted or false,
        _children    = {},
        _childConns  = {},
        _sources     = {},
        _layoutType  = props.layout or "flow",
        _dir         = props.dir or "vertical",
        _gap         = props.gap or 0,
        _padding     = pad,
        _cols        = props.cols or 2,
        _align       = props.align,
        _valign      = props.valign,
        _fill        = props.fill or false,
        _hug         = not props.fill and not props.h and not adopted,
    }, ContMeta)

    -- Own-frame resize drives re-layout. Allowed here: this file is the layout engine.
    -- Chain any existing handler so adopting a frame never steals its script.
    local prev = f:GetScript("OnSizeChanged")
    f:SetScript("OnSizeChanged", function(self_, w, h)
        if prev then prev(self_, w, h) end
        if handle._destroyed then return end
        handle:Layout()
    end)

    -- A fill container mirrors its parent's size. Tracking the parent explicitly keeps
    -- the container's own size real (never anchor-derived), which children depend on.
    if parentFrame and props.fill then
        local prevParent = parentFrame:GetScript("OnSizeChanged")
        parentFrame:SetScript("OnSizeChanged", function(self_, w, h)
            if prevParent then prevParent(self_, w, h) end
            if handle._destroyed then return end
            f:SetSize(w, h)
        end)
    end

    -- Geometry may only become known once the frame is first displayed
    local prevShow = f:GetScript("OnShow")
    f:SetScript("OnShow", function(self_, ...)
        if prevShow then prevShow(self_, ...) end
        if handle._destroyed then return end
        handle:Layout()
    end)

    return handle
end
