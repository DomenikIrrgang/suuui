local max, min = math.max, math.min
local select   = select

local ScrMeta = {}
ScrMeta.__index = ScrMeta

function ScrMeta:SetPoint(...)  self._f:SetPoint(...) end
function ScrMeta:Show()         self._f:Show() end
function ScrMeta:Hide()         self._f:Hide() end
function ScrMeta:IsShown()      return self._f:IsShown() end
function ScrMeta:GetFrame()     return self._f end
function ScrMeta:SetEnabled()   end
function ScrMeta:Destroy()      SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid) end

--- Resizes the scroll frame.
-- @param w number
-- @param h number
function ScrMeta:SetSize(w, h)
    self._f:SetSize(w, h)
    local needsBar = self._content:GetHeight() > h
    local contentW = needsBar and (w - 10) or w
    self._sf:SetSize(contentW, h)
    self._content:SetWidth(contentW)
    self._track:SetHeight(h - 4)
    self:_updateBar()
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

--- Scrolls to the top of the content.
function ScrMeta:ScrollToTop()
    self._sf:SetVerticalScroll(0)
    self:_updateBar()
end

function ScrMeta:_updateBar()
    local ch      = self._content:GetHeight()
    local sh      = self._sf:GetHeight()
    local trackH  = self._track:GetHeight()
    local maxScroll = max(0, ch - sh)
    local cur     = self._sf:GetVerticalScroll()
    local pct     = (maxScroll > 0) and (cur / maxScroll) or 0
    local thumbH  = max(16, trackH * (sh / max(ch, 1)))
    self._thumb:SetHeight(thumbH)
    self._thumb:SetPoint("TOP", self._track, "TOP", 0, -(pct * (trackH - thumbH)))
    
    local needsBar = ch > sh
    self._track:SetShown(needsBar)
    
    -- Adjust scroll frame and content width when scrollbar visibility changes
    local w = self._f:GetWidth()
    local contentW = needsBar and (w - 10) or w
    self._sf:SetWidth(contentW)
    self._content:SetWidth(contentW)
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
-- @param props table  { w, h }
-- @param parent frame
-- @return table  ScrollFrame handle
function SuuUI.Components.ScrollFrame(props, parent)
    local w = props.w or 200
    local h = props.h or 300

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)

    -- The WoW ScrollFrame widget (initial width will be adjusted)
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetSize(w, h)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)

    -- Content frame (scroll child)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(w, h)  -- minimum = scroll frame height
    sf:SetScrollChild(content)

    -- Scrollbar track (Frame so GetHeight() works)
    local track = CreateFrame("Frame", nil, f, "BackdropTemplate")
    track:SetWidth(8)
    track:SetHeight(h - 4)
    track:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -1, -2)
    track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1,  2)

    -- Scrollbar thumb
    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    thumb:SetWidth(8)
    thumb:SetHeight(30)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:EnableMouse(true)

    local id = "scr_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _sf=sf, _content=content,
        _track=track, _thumb=thumb, _eid=id,
    }, ScrMeta)

    -- Mouse wheel scroll: only when content overflows
    sf:SetScript("OnMouseWheel", function(_, delta)
        if content:GetHeight() <= sf:GetHeight() then return end
        local cur = sf:GetVerticalScroll()
        local maxScroll = max(0, content:GetHeight() - sf:GetHeight())
        sf:SetVerticalScroll(max(0, min(maxScroll, cur - delta * 20)))
        handle:_updateBar()
    end)

    -- Thumb drag
    local dragging, dragStartY, dragStartScroll = false, 0, 0
    thumb:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" then return end
        dragging = true
        dragStartY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        dragStartScroll = sf:GetVerticalScroll()
        thumb:SetScript("OnUpdate", function()
            if not dragging then
                thumb:SetScript("OnUpdate", nil)
                return
            end
            local cy = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            local delta = dragStartY - cy
            local trackH   = track:GetHeight()
            local thumbH   = thumb:GetHeight()
            local ch       = content:GetHeight()
            local sh       = sf:GetHeight()
            local maxScroll = max(0, ch - sh)
            local ratio    = maxScroll / max(1, trackH - thumbH)
            sf:SetVerticalScroll(max(0, min(maxScroll, dragStartScroll + delta * ratio)))
            handle:_updateBar()
        end)
    end)
    thumb:SetScript("OnMouseUp", function()
        dragging = false
        thumb:SetScript("OnUpdate", nil)
    end)

    -- Recompute bar when content size changes via signal
    SuuUI.UISignals:Connect(content, SuuUI.UISignals.SIGNALS.CONTENT_RESIZED, function(contentHeight)
        handle:_updateBar()
    end)

    handle:ApplyTheme()
    handle:_updateBar()  -- set initial thumb visibility and position
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
