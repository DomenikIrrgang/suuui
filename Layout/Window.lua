local assert, type = assert, type
local tinsert = table.insert

local WinMeta = {}
WinMeta.__index = WinMeta
local registry = {}

local function applyTheme(self)
    local T  = SuuUI.Theme
    local bg = T:GetToken("colorBg")
    local bd = T:GetToken("colorBorder")
    local bw = T:GetToken("borderWidth") or 1
    self._frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = bw,
        insets   = { left=bw, right=bw, top=bw, bottom=bw },
    })
    if bg then self._frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end

    -- title bar
    local bar = T:GetToken("colorBgAlt")
    if bar then self._titleBar:SetColorTexture(bar[1], bar[2], bar[3], bar[4]) end

    -- title text
    local tc = T:GetToken("colorText")
    if tc then self._titleText:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
    self._titleText:SetFont(
        T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeMd") or 13, "")

    -- close button: × glyph styled with theme colors
    local mc = T:GetToken("colorTextMuted")
    if mc then self._closeText:SetTextColor(mc[1], mc[2], mc[3], mc[4]) end
    self._closeText:SetFont(
        T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeLg") or 15, "")
end

local function savePos(self)
    if not SuuUIConfig then SuuUIConfig = {} end
    if not SuuUIConfig.windows then SuuUIConfig.windows = {} end
    local x = self._frame:GetLeft()
    local y = self._frame:GetTop()
    SuuUIConfig.windows[self._id] = { x = x, y = y - GetScreenHeight() }
end

local function restorePos(self)
    local cfg = SuuUIConfig and SuuUIConfig.windows and SuuUIConfig.windows[self._id]
    if cfg then
        self._frame:ClearAllPoints()
        self._frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cfg.x, cfg.y)
    end
end

--- Shows the window with a fade-in animation.
function WinMeta:Show()
    self._frame:SetAlpha(0)
    self._frame:Show()
    SuuUI.Anim.Presets.FadeIn(self._frame, SuuUI.Theme:GetToken("animFast"))
end

--- Hides the window with a fade-out animation.
function WinMeta:Hide()
    SuuUI.Anim.Presets.FadeOut(self._frame, SuuUI.Theme:GetToken("animFast"))
end

--- Toggles window visibility.
function WinMeta:Toggle()
    if self._frame:IsShown() then self:Hide() else self:Show() end
end

--- Sets the window title text.
-- @param text string
function WinMeta:SetTitle(text)
    self._titleText:SetText(text)
end

--- Returns the inner content frame for attaching children.
-- @return frame
function WinMeta:GetContentFrame()
    return self._content
end

--- Saves window position to per-character SavedVariables.
function WinMeta:SavePosition()
    savePos(self)
end

--- Re-applies theme tokens to this window.
function WinMeta:ApplyTheme()
    applyTheme(self)
end

--- Creates a new draggable themed window.
-- @param props table  { id, title, w, h, minW, minH, resizable, layer }
-- @return table  Window handle
function SuuUI.Layout:CreateWindow(props)
    assert(type(props.id) == "string", "SuuUI Window: id required")
    local w = props.w or 400
    local h = props.h or 300
    local layer = props.layer or "normal"  -- default layer

    -- Use UIRoot if available, otherwise fall back to UIParent
    local parent = UIParent
    if SuuUI.UIRoot and SuuUI.UIRoot.GetRoot then
        local root = SuuUI.UIRoot:GetRoot()
        if root then
            parent = root
        end
    end
    
    local f = CreateFrame("Frame", "SuuUI_win_" .. props.id, parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER")  -- Default center position
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetResizable(true)  -- Allow resizing
    f:EnableMouse(true)
    f:SetClampedToScreen(true)

    -- Title bar texture
    local bar = f:CreateTexture(nil, "BACKGROUND")
    bar:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    bar:SetHeight(26)

    -- Title text
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", bar, "LEFT", 10, 0)
    title:SetText(props.title or props.id)

    -- Drag region (covers title bar, leaves room for close button on the right)
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT",  bar, "TOPLEFT")
    drag:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -34, 0)  -- 22px btn + 6px margin + 6px gap
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function() f:StartMoving() end)
    drag:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        savePos({ _frame = f, _id = props.id })
    end)

    -- Close button: plain Frame with a × FontString, fully custom styled
    local closeBtn = CreateFrame("Frame", nil, f, "BackdropTemplate")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    closeBtn:EnableMouse(true)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 10)  -- above drag region
    closeBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1, insets = { left=1, right=1, top=1, bottom=1 },
    })
    closeBtn:SetBackdropColor(0, 0, 0, 0)        -- transparent until hover
    closeBtn:SetBackdropBorderColor(0, 0, 0, 0)  -- no border

    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeText:SetText("×")

    -- Content area below title bar
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     f, "TOPLEFT",     1, -27)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1,  1)

    -- Resize grip (bottom-right corner) if resizable
    local resizeGrip = nil
    if props.resizable then
        local minW = props.minW or 200
        local minH = props.minH or 200
        local maxW = props.maxW or 2000
        local maxH = props.maxH or 2000
        
        resizeGrip = CreateFrame("Frame", nil, f)
        resizeGrip:SetSize(16, 16)
        resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        resizeGrip:EnableMouse(true)
        resizeGrip:SetFrameLevel(f:GetFrameLevel() + 10)
        
        -- Visual indicator (diagonal lines)
        local tex = resizeGrip:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetColorTexture(0.5, 0.5, 0.5, 0.5)
        
        resizeGrip:SetScript("OnMouseDown", function()
            f:StartSizing("BOTTOMRIGHT")
        end)
        resizeGrip:SetScript("OnMouseUp", function()
            f:StopMovingOrSizing()
            -- Enforce min/max bounds
            local width = f:GetWidth()
            local height = f:GetHeight()
            if width < minW then width = minW end
            if width > maxW then width = maxW end
            if height < minH then height = minH end
            if height > maxH then height = maxH end
            f:SetSize(width, height)
            savePos({ _frame = f, _id = props.id })
        end)
        resizeGrip:SetScript("OnEnter", function()
            tex:SetColorTexture(0.7, 0.7, 0.7, 0.7)
        end)
        resizeGrip:SetScript("OnLeave", function()
            tex:SetColorTexture(0.5, 0.5, 0.5, 0.5)
        end)
    end

    -- Build handle first so the close callback can reference it safely
    local handle = setmetatable({
        _id        = props.id,
        _frame     = f,
        _titleBar  = bar,
        _titleText = title,
        _closeBtn  = closeBtn,
        _closeText = closeText,
        _content   = content,
        _layer     = layer,
    }, WinMeta)

    -- Close button interactions
    local T = SuuUI.Theme
    closeBtn:SetScript("OnEnter", function()
        local ac = T:GetToken("colorText")
        if ac then closeText:SetTextColor(ac[1], ac[2], ac[3], ac[4]) end
        local hov = T:GetToken("colorBgHover")
        if hov then closeBtn:SetBackdropColor(hov[1], hov[2], hov[3], hov[4]) end
    end)
    closeBtn:SetScript("OnLeave", function()
        closeBtn:SetBackdropColor(0, 0, 0, 0)
        local mc = T:GetToken("colorTextMuted")
        if mc then closeText:SetTextColor(mc[1], mc[2], mc[3], mc[4]) end
    end)
    closeBtn:SetScript("OnMouseUp", function()
        handle:Hide()
    end)

    applyTheme(handle)
    f:Hide()

    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, "win_" .. props.id)

    local posFrame = CreateFrame("Frame")
    posFrame:RegisterEvent("PLAYER_LOGIN")
    posFrame:SetScript("OnEvent", function()
        posFrame:UnregisterAllEvents()
        restorePos(handle)
        
        -- Register with UIRoot after position is restored (if UIRoot is available)
        if SuuUI.UIRoot and SuuUI.UIRoot.GetRoot and SuuUI.UIRoot:GetRoot() then
            local x = f:GetLeft() or 0
            local y = (f:GetTop() or 0) - GetScreenHeight()
            local ok, err = pcall(function()
                SuuUI.UIRoot:AddElement(f, layer, {
                    point = "TOPLEFT",
                    x = x,
                    y = y,
                    width = w,
                    height = h,
                })
            end)
            if not ok then
                -- UIRoot registration failed, but window can still function
                SuuUI.Debug("Window UIRoot registration failed: " .. tostring(err))
            end
        end
    end)

    registry[props.id] = handle
    tinsert(SuuUI.Layout._windows or {}, handle)
    return handle
end

SuuUI.Layout._windows = {}

--- Returns a registered window handle by id.
-- @param id string
-- @return table|nil
function SuuUI.Layout:GetWindow(id)
    return registry[id]
end
