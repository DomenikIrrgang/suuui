local max, min = math.max, math.min
local select   = select
local S = SuuUI.UISignals

-- Vertical inset of the bar track inside the frame, and the gap between the viewport
-- and the bar. No space token is this small (spaceXs is 4), so both stay named
-- constants rather than forcing a token that does not fit.
local TRACK_INSET_Y = 2
local BAR_GAP       = 1

local function barWidth()
    return SuuUI.Theme:GetToken("sizeScrollbar") or 8
end

local function borderWidth()
    return SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1)
end

-- Gutter reserved for the bar: its width, the border inset it sits in, and the gap
-- that keeps it clear of the viewport.
local function gutter()
    return barWidth() + borderWidth() + BAR_GAP
end

-- Stack props for the track. Rebuilt on every theme change because both the bar width
-- and the border inset are token-driven.
local function trackProps()
    local bw = borderWidth()
    return {
        align = "end",
        width = barWidth(),
        inset = { right = bw, top = TRACK_INSET_Y, bottom = TRACK_INSET_Y },
    }
end

local ScrMeta = {}
ScrMeta.__index = ScrMeta

function ScrMeta:SetEnabled()   end

function ScrMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._thumb:SetScript("OnUpdate", nil)
    self._thumbBox:Destroy()
    self._box:Destroy()
end

--- Returns the inner content frame for attaching children.
-- @return frame
function ScrMeta:GetContent()
    return self._content
end

--- Returns the available content width (accounting for scrollbar).
-- @return number
function ScrMeta:GetContentWidth()
    return self:_needsBar() and (self._f:GetWidth() - gutter()) or self._f:GetWidth()
end

--- Sets the scrollable content height and refreshes the scrollbar.
-- @param height number
function ScrMeta:SetContentHeight(height)
    self._contentH = height
    self:_updateBar()
end

-- Whether a bar is needed, judged against the reported content height rather than the
-- content frame's height. The frame's height is floored at the viewport, so reading it
-- back makes a shrinking viewport look like overflowing content and reserves a gutter
-- for a bar that is not there.
function ScrMeta:_needsBar()
    return (self._contentH or 0) > self._sf:GetHeight()
end

--- Scrolls to the top of the content.
function ScrMeta:ScrollToTop()
    self._sf:SetVerticalScroll(0)
    self:_updateBar()
    S:Emit(self, S.SIGNALS.SCROLL_CHANGED, 0)
end

function ScrMeta:_updateBar()
    local sh      = self._sf:GetHeight()
    local needsBar = self:_needsBar()
    local ch      = max(self._contentH or 0, sh)
    self._content:SetHeight(ch)

    local trackH  = self._track:GetHeight()
    local maxScroll = max(0, ch - sh)
    local cur     = self._sf:GetVerticalScroll()
    local pct     = (maxScroll > 0) and (cur / maxScroll) or 0
    local thumbH  = max(SuuUI.Theme:GetToken("sizeIcon") or 16, trackH * (sh / max(ch, 1)))

    -- Thumb size and offset go through the anchor container
    self._thumbAnchor.height = thumbH
    self._thumbAnchor.y      = -(pct * (trackH - thumbH))
    self._thumbBox:SetChildAnchor(self._thumb, self._thumbAnchor)

    self._track:SetShown(needsBar)

    -- Reserve gutter space for the scrollbar by insetting the viewport
    self._box:SetChildProps(self._sf, needsBar and { inset = { right = gutter() } } or nil)
    local contentW = self._sf:GetWidth()
    self._content:SetWidth(contentW)

    -- The scrollbar appearing or vanishing changes the usable width, so tell consumers.
    -- Without this, content laid out before the bar appeared overflows underneath it.
    if self._lastContentW ~= contentW then
        self._lastContentW = contentW
        if not self._reporting then
            self._reporting = true
            S:Emit(self, S.SIGNALS.SIZE_CHANGED, self._f:GetWidth(), self._f:GetHeight())
            self._reporting = false
        end
    end
end

function ScrMeta:ApplyTheme()
    local B = SuuUI.Backdrop
    B.Apply(self._track, { bg = "colorBgAlt", border = "colorBorder" })
    B.Apply(self._thumb, { bg = "colorAccent", border = "colorBorder" })

    -- Bar width and border inset are both editable tokens, so re-apply them to the
    -- track and thumb.
    self._box:SetChildProps(self._track, trackProps())
    self._thumbAnchor.width = barWidth()
    self:_updateBar()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize, Show, Hide.
SuuUI.Components.InstallBase(ScrMeta, "_f")

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

    -- React whenever the frame is resized, including by a parent layout (which sizes
    -- the frame directly and never calls SetSize). Registered before the host container
    -- adopts the frame so the container chains onto it.
    local handle
    f:SetScript("OnSizeChanged", function(_, newW, newH)
        if not (handle and handle._box) then return end
        handle:_updateBar()
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, newW, newH)
    end)

    -- Viewport and scrollbar track are stacked in the outer frame
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local sf = CreateFrame("ScrollFrame", nil, f)
    box:Add(sf)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(w, h)
    sf:SetScrollChild(content)

    local track = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:Add(track, trackProps())

    -- Thumb position is driven through the track's anchor container
    local thumbBox = SuuUI.Layout:CreateContainer({ host = track, layout = "anchor" })
    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    thumb:EnableMouse(true)
    local thumbAnchor = {
        point = "TOP", relativePoint = "TOP", x = 0, y = 0, width = barWidth(), height = 30,
    }
    thumbBox:Add(thumb, { anchor = thumbAnchor })

    local id = "scr_" .. tostring(f)
    handle = setmetatable({
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
        local _, cy = SuuUI.Pixel.CursorIn(thumb)
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
        dragStartY = select(2, SuuUI.Pixel.CursorIn(thumb))
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
