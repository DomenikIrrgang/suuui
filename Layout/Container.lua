local pairs, type, assert = pairs, type, assert
local tinsert, tremove = table.insert, table.remove
local ceil = math.ceil

local strategies = {
    flow   = function(c) SuuUI._FlowLayout.Apply(c) end,
    grid   = function(c) SuuUI._GridLayout.Apply(c) end,
    anchor = function(c) SuuUI._AnchorLayout.Apply(c) end,
}

local ContMeta = {}
ContMeta.__index = ContMeta

--- Adds a child frame to the container and re-runs layout.
-- @param child frame or handle
-- @param layoutProps table  Optional { width="fill"|number, height="fill"|number }
function ContMeta:Add(child, layoutProps)
    if layoutProps then
        child._layoutProps = layoutProps
    end
    tinsert(self._children, child)
    
    -- Connect to SIZE_CHANGED signal for automatic re-layout
    local connId = SuuUI.UISignals:Connect(child, SuuUI.UISignals.SIGNALS.SIZE_CHANGED, function(w, h)
        -- Just trigger layout - Layout() will emit SIZE_CHANGED if needed
        self:Layout()
    end)
    
    -- Store connection ID for cleanup
    if not self._signalConnections then
        self._signalConnections = {}
    end
    self._signalConnections[child] = connId
    
    self:Layout()
end

--- Removes a child frame and re-runs layout.
-- @param child frame
function ContMeta:Remove(child)
    -- Clean up signal connection
    if self._signalConnections and self._signalConnections[child] then
        SuuUI.UISignals:DisconnectAll(child)
        self._signalConnections[child] = nil
    end
    
    for i = #self._children, 1, -1 do
        if self._children[i] == child then
            tremove(self._children, i)
            break
        end
    end
    self:Layout()
end

--- Re-calculates and applies child positions.
function ContMeta:Layout()
    local fn = strategies[self._layoutType]
    if fn then 
        fn(self) 
        
        -- Always emit SIZE_CHANGED after layout to notify parents
        local _, h = self:GetContentSize()
        self._frame:SetHeight(h)
        SuuUI.UISignals:Emit(self, SuuUI.UISignals.SIGNALS.SIZE_CHANGED, self._frame:GetWidth(), h)
    end
end

--- Sets container size.
-- @param w number
-- @param h number
function ContMeta:SetSize(w, h)
    self._frame:SetSize(w, h)
    self:Layout()
end

--- Returns the raw WoW frame.
-- @return frame
function ContMeta:GetFrame()
    return self._frame
end

--- Returns computed bounding size of all children.
-- @return number, number  width, height
function ContMeta:GetContentSize()
    if #self._children == 0 then
        return 0, 0
    end
    
    local pad = self._padding
    local gap = self._gap
    
    if self._layoutType == "flow" then
        if self._dir == "vertical" then
            -- Vertical flow: width is widest child, height is sum of heights + gaps + padding
            local maxW = 0
            local totalH = pad.top + pad.bottom
            for i, child in ipairs(self._children) do
                local w = child:GetWidth()
                if w > maxW then maxW = w end
                totalH = totalH + child:GetHeight()
                if i < #self._children then
                    totalH = totalH + gap
                end
            end
            return maxW + pad.left + pad.right, totalH
        else
            -- Horizontal flow: width is sum of widths + gaps + padding, height is tallest child
            local maxH = 0
            local totalW = pad.left + pad.right
            for i, child in ipairs(self._children) do
                local h = child:GetHeight()
                if h > maxH then maxH = h end
                totalW = totalW + child:GetWidth()
                if i < #self._children then
                    totalW = totalW + gap
                end
            end
            return totalW, maxH + pad.top + pad.bottom
        end
    elseif self._layoutType == "grid" then
        -- Grid layout: calculate based on columns
        local cols = self._cols
        local rows = ceil(#self._children / cols)
        local colW = 0
        local totalH = pad.top + pad.bottom
        
        -- Find max column width (all equal in grid)
        if #self._children > 0 then
            colW = self._children[1]:GetWidth()
        end
        
        -- Calculate total height
        for r = 1, rows do
            local rowH = 0
            for c = 1, cols do
                local idx = (r - 1) * cols + c
                if idx <= #self._children then
                    local h = self._children[idx]:GetHeight()
                    if h > rowH then rowH = h end
                end
            end
            totalH = totalH + rowH
            if r < rows then
                totalH = totalH + gap
            end
        end
        
        local totalW = pad.left + pad.right + (colW * cols) + (gap * (cols - 1))
        return totalW, totalH
    end
    
    -- Fallback for anchor layout or unknown
    return self._frame:GetWidth(), self._frame:GetHeight()
end

--- Creates a new Container with a layout strategy.
-- @param props table  { parent, layout, dir, gap, padding, cols, fillWidth, fillHeight }
-- @return table  Container handle
function SuuUI.Layout:CreateContainer(props)
    assert(props.parent, "SuuUI Container: parent required")
    local padInput = props.padding or {}
    local pad = {
        top    = padInput.top    or 0,
        right  = padInput.right  or 0,
        bottom = padInput.bottom or 0,
        left   = padInput.left   or 0,
    }
    local f   = CreateFrame("Frame", nil, props.parent)
    
    -- Set initial size based on fillWidth/fillHeight or explicit w/h
    if props.fillWidth then
        f:SetWidth(props.parent:GetWidth())
    elseif props.w then
        f:SetWidth(props.w)
    end
    
    if props.fillHeight then
        f:SetHeight(props.parent:GetHeight())
    elseif props.h then
        f:SetHeight(props.h)
    end

    local handle = setmetatable({
        _frame      = f,
        _children   = {},
        _layoutType = props.layout or "flow",
        _dir        = props.dir or "vertical",
        _gap        = props.gap or 0,
        _padding    = pad,
        _cols       = props.cols or 2,
        _fillWidth  = props.fillWidth or false,
        _fillHeight = props.fillHeight or false,
    }, ContMeta)
    
    -- Auto-relayout when container is resized
    f:SetScript("OnSizeChanged", function()
        handle:Layout()
    end)
    
    -- If fillWidth or fillHeight, update when parent resizes
    if props.fillWidth or props.fillHeight then
        props.parent:SetScript("OnSizeChanged", function()
            if handle._fillWidth then
                f:SetWidth(props.parent:GetWidth())
            end
            if handle._fillHeight then
                f:SetHeight(props.parent:GetHeight())
            end
        end)
    end
    
    return handle
end
