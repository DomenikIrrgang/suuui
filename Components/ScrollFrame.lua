local max, min = math.max, math.min
local select   = select
local S = SuuUI.UISignals

local ScrMeta = {}
ScrMeta.__index = ScrMeta

function ScrMeta:GetWidth()     return self._f:GetWidth() end
function ScrMeta:GetHeight()    return self._f:GetHeight() end
function ScrMeta:IsShown()      return self._f:IsShown() end
function ScrMeta:GetFrame()     return self._f end
function ScrMeta:SetEnabled()   end

function ScrMeta:Show()
    self._f:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function ScrMeta:Hide()
    self._f:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

function ScrMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._thumb:SetScript("OnUpdate", nil)
    self._thumbBox:Destroy()
    self._box:Destroy()
end

--- Resizes the scroll frame. Emits SIZE_CHANGED.
-- @param w number
-- @param h number
function ScrMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    self:_updateBar()
    S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
end

--- Returns the inner content frame for attaching children.
-- @return frame
function ScrMeta:GetContent()
    return self._content
end

--- Returns the available content width (accounting for scrollbar).
-- @return number
function ScrMeta:GetContentWidth()
    local needsBar = self._content:GetHeight() > self._sf:GetHeight()
    return needsBar and (self._f:GetWidth() - 10) or self._f:GetWidth()
end

--- Sets the scrollable content height and refreshes the scrollbar.
-- @param height number
function ScrMeta:SetContentHeight(height)
    self._content:SetHeight(max(height, self._sf:GetHeight()))
    self:_updateBar()
end

--- Scrolls to the top of the content.
function ScrMeta:ScrollToTop()
    self._sf:SetVerticalScroll(0)
    self:_updateBar()
    S:Emit(self, S.SIGNALS.SCROLL_CHANGED, 0)
end

function ScrMeta:_updateBar()
    local ch      = self._content:GetHeight()
    local sh      = self._sf:GetHeight()
    local trackH  = self._track:GetHeight()
    local maxScroll = max(0, ch - sh)
    local cur     = self._sf:GetVerticalScroll()
    local pct     = (maxScroll > 0) and (cur / maxScroll) or 0
    local thumbH  = max(16, trackH * (sh / max(ch, 1)))

    -- Thumb size and offset go through the anchor container
    self._thumbAnchor.height = thumbH
    self._thumbAnchor.y      = -(pct * (trackH - thumbH))
    self._thumbBox:SetChildAnchor(self._thumb, self._thumbAnchor)

    local needsBar = ch > sh
    self._track:SetShown(needsBar)

    -- Reserve gutter space for the scrollbar by insetting the viewport
    self._box:SetChildProps(self._sf, needsBar and { inset = { right = 10 } } or nil)
    self._content:SetWidth(self._sf:GetWidth())
end

function ScrMeta:ApplyTheme()
    local T   = SuuUI.Theme
    local bg  = T:GetToken("colorBgAlt")
    local ac  = T:GetToken("colorAccent")
    local bd  = T:GetToken("colorBorder")
    local bw  = T:GetToken("borderWidth") or 1
    self._track:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then self._track:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._track:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    self._thumb:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if ac then self._thumb:SetBackdropColor(ac[1], ac[2], ac[3], ac[4]) end
    if bd then self._thumb:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    self:_updateBar()
end

--- Creates a custom scroll frame with a styled scrollbar.
-- Emits SCROLL_CHANGED (scrollY), SIZE_CHANGED, VISIBILITY_CHANGED.
-- Connect CONTENT_RESIZED on the handle to report a new content height.
-- @param props table  { w, h }
-- @param parent frame
-- @return table  ScrollFrame handle
function SuuUI.Components.ScrollFrame(props, parent)
    local w = props.w or 200
    local h = props.h or 300

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)

    -- Viewport and scrollbar track are stacked in the outer frame
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local sf = CreateFrame("ScrollFrame", nil, f)
    box:Add(sf)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(w, h)
    sf:SetScrollChild(content)

    local track = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:Add(track, { align = "end", width = 8, inset = { right = 1, top = 2, bottom = 2 } })

    -- Thumb position is driven through the track's anchor container
    local thumbBox = SuuUI.Layout:CreateContainer({ host = track, layout = "anchor" })
    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    thumb:EnableMouse(true)
    local thumbAnchor = { point = "TOP", relativePoint = "TOP", x = 0, y = 0, width = 8, height = 30 }
    thumbBox:Add(thumb, { anchor = thumbAnchor })

    local id = "scr_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _sf=sf, _content=content, _box=box,
        _track=track, _thumb=thumb,
        _thumbBox=thumbBox, _thumbAnchor=thumbAnchor, _eid=id,
    }, ScrMeta)

    sf:SetScript("OnMouseWheel", function(_, delta)
        if content:GetHeight() <= sf:GetHeight() then return end
        local cur = sf:GetVerticalScroll()
        local maxScroll = max(0, content:GetHeight() - sf:GetHeight())
        local newScroll = max(0, min(maxScroll, cur - delta * 20))
        sf:SetVerticalScroll(newScroll)
        handle:_updateBar()
        S:Emit(handle, S.SIGNALS.SCROLL_CHANGED, newScroll)
    end)

    local dragging, dragStartY, dragStartScroll = false, 0, 0
    local function onDragUpdate()
        if not dragging then
            thumb:SetScript("OnUpdate", nil)
            return
        end
        local cy = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local delta = dragStartY - cy
        local trackH   = track:GetHeight()
        local thumbH   = thumb:GetHeight()
        local maxScroll = max(0, content:GetHeight() - sf:GetHeight())
        local ratio    = maxScroll / max(1, trackH - thumbH)
        local newScroll = max(0, min(maxScroll, dragStartScroll + delta * ratio))
        sf:SetVerticalScroll(newScroll)
        handle:_updateBar()
        S:Emit(handle, S.SIGNALS.SCROLL_CHANGED, newScroll)
    end

    thumb:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" then return end
        dragging = true
        dragStartY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        dragStartScroll = sf:GetVerticalScroll()
        thumb:SetScript("OnUpdate", onDragUpdate)
    end)
    thumb:SetScript("OnMouseUp", function()
        dragging = false
        thumb:SetScript("OnUpdate", nil)
    end)

    -- Content reports its own height growth through the signal bus
    S:Connect(handle, S.SIGNALS.CONTENT_RESIZED, function(contentHeight)
        handle:SetContentHeight(contentHeight)
    end)

    handle:ApplyTheme()
    handle:_updateBar()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
