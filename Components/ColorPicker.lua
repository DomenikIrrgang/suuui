local max, min, floor, abs = math.max, math.min, math.floor, math.abs
local format = string.format
local C = SuuUI.Components

local CpMeta = {}
CpMeta.__index = CpMeta

function CpMeta:SetPoint(...)  self._f:SetPoint(...) end
function CpMeta:SetSize(w, h)  self._f:SetSize(w, h) end
function CpMeta:Show()         
    self._f:Show()
    -- Register global click listener when shown
    if self._clickFrame then
        self._resetClickDetection()
        self._clickFrame:Show()
    end
end
function CpMeta:Hide()         
    self._f:Hide()
    -- Unregister global click listener when hidden
    if self._clickFrame then
        self._clickFrame:Hide()
    end
end
function CpMeta:IsShown()      return self._f:IsShown() end
function CpMeta:GetFrame()     return self._f end
function CpMeta:SetEnabled(en) self._enabled = en end
function CpMeta:Destroy()      
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    if self._clickFrame then
        self._clickFrame:Hide()
        self._clickFrame = nil
    end
end

--- Registers a function to be called when clicking outside the picker.
-- @param fn function
function CpMeta:OnRequestClose(fn)
    self._onRequestClose = fn
end

--- Returns current color as r, g, b, a (0-1 each).
-- @return number, number, number, number
function CpMeta:GetValue()
    return self._r, self._g, self._b, self._a
end

--- Sets color without firing onChange.
-- @param r number  @param g number  @param b number  @param a number
function CpMeta:SetValue(r, g, b, a)
    self._r, self._g, self._b = r or 1, g or 1, b or 1
    self._a = a or 1
    self:_render()
end

-- HSV <-> RGB helpers
local function rgbToHsv(r, g, b)
    local mx = max(r, g, b)
    local mn = min(r, g, b)
    local d  = mx - mn
    local h, s, v = 0, 0, mx
    if mx ~= 0 then s = d / mx end
    if d ~= 0 then
        if mx == r then h = (g - b) / d % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, s, v
end

local function hsvToRgb(h, s, v)
    local i = floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    local r, g, b
    i = i % 6
    if     i == 0 then r,g,b = v,t,p
    elseif i == 1 then r,g,b = q,v,p
    elseif i == 2 then r,g,b = p,v,t
    elseif i == 3 then r,g,b = p,q,v
    elseif i == 4 then r,g,b = t,p,v
    else               r,g,b = v,p,q end
    return r, g, b
end

local function toHex(r, g, b, a)
    return format("%02X%02X%02X%02X",
        floor(r*255+0.5), floor(g*255+0.5),
        floor(b*255+0.5), floor(a*255+0.5))
end

function CpMeta:_render()
    self._preview:SetColorTexture(self._r, self._g, self._b, self._a)
    self._hexInput:SetText(toHex(self._r, self._g, self._b, self._a))
end

function CpMeta:_pickFromSV(px, py)
    local fw = self._svBox:GetWidth()
    local fh = self._svBox:GetHeight()
    local bl = self._svBox:GetLeft() or 0
    local bt = self._svBox:GetTop()  or 0
    local s  = max(0, min(1, (px - bl) / fw))
    local v  = max(0, min(1, (bt - py) / fh))
    self._s, self._v = s, v
    local r, g, b = hsvToRgb(self._h, s, v)
    self._r, self._g, self._b = r, g, b
    self:_render()
    self._svThumb:SetPoint("CENTER", self._svBox, "TOPLEFT", s * fw, -v * fh)
    if self._onChange then self._onChange(r, g, b, self._a) end
end

function CpMeta:_pickFromHue(px)
    local bl = self._hueBar:GetLeft() or 0
    local bw = self._hueBar:GetWidth()
    local h  = max(0, min(1, (px - bl) / bw))
    self._h  = h
    -- update SV box gradient color (hue at full S+V)
    local hr, hg, hb = hsvToRgb(h, 1, 1)
    self._svHueTex:SetColorTexture(hr, hg, hb, 1)
    local r, g, b = hsvToRgb(h, self._s, self._v)
    self._r, self._g, self._b = r, g, b
    self:_render()
    self._hueThumb:SetPoint("CENTER", self._hueBar, "LEFT", h * bw, 0)
    if self._onChange then self._onChange(r, g, b, self._a) end
end

function CpMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bg = T:GetToken("colorBgAlt")
    local bd = T:GetToken("colorBorder")
    local bw = T:GetToken("borderWidth") or 1
    self._f:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=bw, insets={left=bw,right=bw,top=bw,bottom=bw},
    })
    if bg then self._f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
    local tc = T:GetToken("colorTextMuted")
    self._hexInput:SetFont(T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeSm") or 11, "")
    if tc then self._hexInput:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
end

--- Creates a custom HSV color picker panel.
-- @param props table  { value, onChange }  value = {r,g,b,a}
-- @param parent frame
-- @return table  ColorPicker handle
function SuuUI.Components.ColorPicker(props, parent)
    local T = SuuUI.Theme
    local initColor = props.value or {1, 1, 1, 1}
    local r0, g0, b0, a0 = initColor[1], initColor[2], initColor[3], initColor[4] or 1
    local h0, s0, v0 = rgbToHsv(r0, g0, b0)

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(240, 180)

    -- Root container
    local rootContainer = SuuUI.Layout:CreateContainer({
        parent  = f,
        layout  = "flow",
        dir     = "vertical",
        gap     = 4,
        padding = {
            top    = 8,
            right  = 8,
            bottom = 8,
            left   = 8,
        },
    })
    rootContainer:GetFrame():SetAllPoints(f)

    -- Top row: SV box + preview
    local topRow = CreateFrame("Frame", nil, f)
    topRow:SetSize(224, 120)
    
    local topRowContainer = SuuUI.Layout:CreateContainer({
        parent  = topRow,
        layout  = "flow",
        dir     = "horizontal",
        gap     = 8,
        padding = {top=0, right=0, bottom=0, left=0},
    })
    topRowContainer:GetFrame():SetAllPoints(topRow)

    -- SV box (saturation/value square)
    local svBox = CreateFrame("Frame", nil, topRow)
    svBox:SetSize(120, 120)
    svBox:EnableMouse(true)

    -- base hue layer
    local svHueTex = svBox:CreateTexture(nil, "BACKGROUND")
    svHueTex:SetAllPoints(svBox)
    local hhr, hhg, hhb = hsvToRgb(h0, 1, 1)
    svHueTex:SetColorTexture(hhr, hhg, hhb, 1)

    -- white->transparent gradient (left to right) - creates saturation axis
    local svWhite = svBox:CreateTexture(nil, "ARTWORK")
    svWhite:SetAllPoints(svBox)
    svWhite:SetTexture("Interface\\Buttons\\WHITE8x8")
    svWhite:SetGradient("HORIZONTAL", 
        CreateColor(1, 1, 1, 1),  -- left: white
        CreateColor(1, 1, 1, 0))  -- right: transparent
    svWhite:SetDrawLayer("ARTWORK", 0)

    -- transparent->black gradient (top to bottom) - creates value axis
    local svBlack = svBox:CreateTexture(nil, "OVERLAY")
    svBlack:SetAllPoints(svBox)
    svBlack:SetTexture("Interface\\Buttons\\WHITE8x8")
    svBlack:SetGradient("VERTICAL",
        CreateColor(0, 0, 0, 0),  -- top: transparent
        CreateColor(0, 0, 0, 1))  -- bottom: black
    svBlack:SetDrawLayer("OVERLAY", 0)

    -- SV thumb
    local svThumb = CreateFrame("Frame", nil, svBox)
    svThumb:SetSize(8, 8)
    svThumb:SetPoint("CENTER", svBox, "TOPLEFT", s0*120, -v0*120)
    local svTex = svThumb:CreateTexture(nil, "OVERLAY")
    svTex:SetAllPoints(svThumb)
    svTex:SetColorTexture(1, 1, 1, 0.9)
    
    topRowContainer:Add(svBox, { width = 120, height = 120 })

    -- Right side: preview and hex input
    local rightCol = CreateFrame("Frame", nil, topRow)
    rightCol:SetSize(96, 120)
    
    local rightContainer = SuuUI.Layout:CreateContainer({
        parent  = rightCol,
        layout  = "flow",
        dir     = "vertical",
        gap     = 4,
        padding = {top=0, right=0, bottom=0, left=0},
    })
    rightContainer:GetFrame():SetAllPoints(rightCol)

    -- Preview swatch
    local previewFrame = CreateFrame("Frame", nil, rightCol)
    previewFrame:SetSize(96, 96)
    local preview = previewFrame:CreateTexture(nil, "ARTWORK")
    preview:SetAllPoints(previewFrame)
    preview:SetColorTexture(r0, g0, b0, a0)
    
    rightContainer:Add(previewFrame, { width = 96, height = 96 })

    -- Hex input with label
    local hexRow = CreateFrame("Frame", nil, rightCol)
    hexRow:SetSize(96, 20)
    
    local hexLabel = C.Text({
        text  = "Hex:",
        size  = "sm",
        color = "textMuted",
    }, hexRow)
    hexLabel:GetFrame():SetPoint("LEFT", hexRow, "LEFT", 0, 4)
    hexLabel:GetFrame():SetWidth(30)
    
    local hexInput = CreateFrame("EditBox", nil, hexRow)
    hexInput:SetSize(66, 16)
    hexInput:SetPoint("RIGHT", hexRow, "RIGHT", 0, 0)
    hexInput:SetAutoFocus(false)
    hexInput:SetMaxLetters(8)
    hexInput:SetFont("Fonts/FRIZQT__.TTF", 11, "")
    hexInput:SetText(toHex(r0, g0, b0, a0))
    hexInput:SetTextColor(0.9, 0.9, 0.9, 1)
    
    rightContainer:Add(hexRow, { width = 96, height = 20 })
    
    topRowContainer:Add(rightCol, { width = 96, height = 120 })
    
    rootContainer:Add(topRow, { width = "fill", height = 120 })

    -- Hue bar with label
    local hueRow = CreateFrame("Frame", nil, f)
    hueRow:SetSize(224, 14)
    
    local hueRowContainer = SuuUI.Layout:CreateContainer({
        parent  = hueRow,
        layout  = "flow",
        dir     = "horizontal",
        gap     = 4,
        padding = {top=0, right=0, bottom=0, left=0},
    })
    hueRowContainer:GetFrame():SetAllPoints(hueRow)
    
    local hueLabel = C.Text({
        text  = "Hue:",
        size  = "sm",
        color = "text",
    }, hueRow)
    hueLabel:GetFrame():SetWidth(35)
    hueRowContainer:Add(hueLabel:GetFrame(), { width = 35, height = 14 })

    -- Hue bar
    local hueBar = CreateFrame("Frame", nil, hueRow)
    hueBar:SetSize(185, 14)
    hueBar:EnableMouse(true)

    -- Use the Blizzard color picker hue texture
    local hueTex = hueBar:CreateTexture(nil, "ARTWORK")
    hueTex:SetAllPoints(hueBar)
    hueTex:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-ColorSwatch")

    -- hue thumb
    local hueThumb = CreateFrame("Frame", nil, hueBar)
    hueThumb:SetSize(6, 18)
    hueThumb:SetPoint("CENTER", hueBar, "LEFT", h0 * 185, 0)
    local htTex = hueThumb:CreateTexture(nil, "OVERLAY")
    htTex:SetAllPoints(hueThumb)
    htTex:SetColorTexture(1, 1, 1, 0.9)
    
    hueRowContainer:Add(hueBar, { width = 185, height = 14 })
    
    rootContainer:Add(hueRow, { width = "fill", height = 14 })

    -- Alpha slider with label
    local alphaRow = CreateFrame("Frame", nil, f)
    alphaRow:SetSize(224, 14)
    
    local alphaRowContainer = SuuUI.Layout:CreateContainer({
        parent  = alphaRow,
        layout  = "flow",
        dir     = "horizontal",
        gap     = 4,
        padding = {top=0, right=0, bottom=0, left=0},
    })
    alphaRowContainer:GetFrame():SetAllPoints(alphaRow)
    
    local alphaLabel = C.Text({
        text  = "Alpha:",
        size  = "sm",
        color = "text",
    }, alphaRow)
    alphaLabel:GetFrame():SetWidth(35)
    alphaRowContainer:Add(alphaLabel:GetFrame(), { width = 35, height = 14 })

    -- Alpha slider
    local alphaBar = CreateFrame("Frame", nil, alphaRow)
    alphaBar:SetSize(185, 14)
    alphaBar:EnableMouse(true)
    local alphaTex = alphaBar:CreateTexture(nil, "ARTWORK")
    alphaTex:SetAllPoints(alphaBar)
    alphaTex:SetTexture("Interface\\Buttons\\WHITE8x8")
    alphaTex:SetGradient("HORIZONTAL",
        CreateColor(0.5, 0.5, 0.5, 0),  -- left: transparent gray
        CreateColor(0.5, 0.5, 0.5, 1))  -- right: opaque gray
    local alphaThumb = CreateFrame("Frame", nil, alphaBar)
    alphaThumb:SetSize(6, 18)
    alphaThumb:SetPoint("CENTER", alphaBar, "LEFT", a0 * 185, 0)
    local atTex = alphaThumb:CreateTexture(nil, "OVERLAY")
    atTex:SetAllPoints(alphaThumb)
    atTex:SetColorTexture(1, 1, 1, 0.9)
    
    alphaRowContainer:Add(alphaBar, { width = 185, height = 14 })
    
    rootContainer:Add(alphaRow, { width = "fill", height = 14 })

    local id = "cp_" .. tostring(f)
    local handle = setmetatable({
        _f=f, _svBox=svBox, _svHueTex=svHueTex,
        _svThumb=svThumb, _hueBar=hueBar, _hueThumb=hueThumb,
        _alphaBar=alphaBar, _alphaThumb=alphaThumb,
        _preview=preview, _hexInput=hexInput,
        _eid=id, _enabled=true, _onChange=props.onChange,
        _r=r0, _g=g0, _b=b0, _a=a0,
        _h=h0, _s=s0, _v=v0,
    }, CpMeta)

    local isDraggingSV = false
    local isDraggingHue = false
    local isDraggingAlpha = false

    svBox:SetScript("OnMouseDown", function()
        isDraggingSV = true
    end)
    
    svBox:SetScript("OnMouseUp", function()
        isDraggingSV = false
    end)

    hueBar:SetScript("OnMouseDown", function()
        isDraggingHue = true
    end)
    
    hueBar:SetScript("OnMouseUp", function()
        isDraggingHue = false
    end)

    alphaBar:SetScript("OnMouseDown", function()
        isDraggingAlpha = true
    end)
    
    alphaBar:SetScript("OnMouseUp", function()
        isDraggingAlpha = false
    end)
    
    -- OnUpdate handler for continuous tracking
    f:SetScript("OnUpdate", function()
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx = cx / scale
        cy = cy / scale
        
        if isDraggingSV then
            handle:_pickFromSV(cx, cy)
        elseif isDraggingHue then
            handle:_pickFromHue(cx)
        elseif isDraggingAlpha then
            local bl = alphaBar:GetLeft() or 0
            local bw = alphaBar:GetWidth()
            local a  = max(0, min(1, (cx - bl) / bw))
            handle._a = a
            alphaThumb:SetPoint("CENTER", alphaBar, "LEFT", a * bw, 0)
            handle:_render()
            if handle._onChange then handle._onChange(handle._r, handle._g, handle._b, a) end
        end
    end)
    
    -- Stop dragging when mouse is released anywhere
    f:SetScript("OnMouseUp", function()
        isDraggingSV = false
        isDraggingHue = false
        isDraggingAlpha = false
    end)

    hexInput:SetScript("OnEnterPressed", function()
        local hex = hexInput:GetText()
        if #hex == 8 then
            local ri = tonumber(hex:sub(1,2), 16)
            local gi = tonumber(hex:sub(3,4), 16)
            local bi = tonumber(hex:sub(5,6), 16)
            local ai = tonumber(hex:sub(7,8), 16)
            if ri and gi and bi and ai then
                handle:SetValue(ri/255, gi/255, bi/255, ai/255)
                if handle._onChange then
                    handle._onChange(handle._r, handle._g, handle._b, handle._a)
                end
            end
        end
        hexInput:ClearFocus()
    end)
    hexInput:SetScript("OnEscapePressed", function() hexInput:ClearFocus() end)

    -- Click-outside-to-close detection using mouse state polling
    local clickFrame = CreateFrame("Frame")
    clickFrame:Hide()
    local wasMouseDown = false
    local ignoreNextClick = false
    
    clickFrame:SetScript("OnUpdate", function()
        if not f:IsShown() then
            clickFrame:Hide()
            wasMouseDown = false
            ignoreNextClick = false
            return
        end
        
        local isMouseDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        
        -- Detect click (mouse down -> mouse up transition)
        if wasMouseDown and not isMouseDown then
            if ignoreNextClick then
                -- Skip this click (it was the one that opened the picker)
                ignoreNextClick = false
            else
                local cx, cy = GetCursorPosition()
                local scale = UIParent:GetEffectiveScale()
                cx = cx / scale
                cy = cy / scale
                
                local fl = f:GetLeft() or 0
                local fr = f:GetRight() or 0
                local ft = f:GetTop() or 0
                local fb = f:GetBottom() or 0
                
                if cx < fl or cx > fr or cy < fb or cy > ft then
                    -- Click is outside - close the picker
                    if handle._onRequestClose then
                        handle._onRequestClose()
                    end
                end
            end
        end
        
        wasMouseDown = isMouseDown
    end)
    
    -- Method to reset the ignore flag when showing
    handle._resetClickDetection = function()
        ignoreNextClick = true
        wasMouseDown = true  -- Assume mouse is down when opening
    end
    
    handle._clickFrame = clickFrame

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end