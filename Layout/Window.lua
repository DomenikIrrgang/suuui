local assert, type = assert, type
local tinsert = table.insert
local S = SuuUI.UISignals

-- Window chrome is token-driven. The title strip holds text, so its height is floored
-- against the font size; the close button and grip carry no text of their own.
local function titleHeight() return SuuUI.Theme:GetControlHeight("sizeTitleBar") end
local function closeSize()   return SuuUI.Theme:GetToken("sizeControlMd") or 22 end
local function gripSize()    return SuuUI.Theme:GetToken("sizeIcon") or 16 end

-- ASCII only. FRIZQT__.TTF has no glyph for U+00D7 (the multiplication sign that reads
-- as a nicer close mark in a text editor), so it drew as blank in the client.
local CLOSE_GLYPH = "X"

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

    local bar = T:GetToken("colorBgAlt")
    if bar then self._titleBar:SetColorTexture(bar[1], bar[2], bar[3], bar[4]) end

    local tc = T:GetToken("colorText")
    if tc then self._titleText:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
    self._titleText:SetFont(
        T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeMd") or 13, "")

    local mc = T:GetToken("colorTextMuted")
    if mc then self._closeText:SetTextColor(mc[1], mc[2], mc[3], mc[4]) end
    self._closeText:SetFont(
        T:GetToken("fontFamilyMain") or "Fonts/FRIZQT__.TTF",
        T:GetToken("fontSizeLg") or 15, "")

    -- The close mark is sized from its font, so its box has to be re-measured here.
    -- Nothing else re-lays it out: the button keeps the same token size, so no resize
    -- fires, and the mark would stay pinned to the metrics of the previous font.
    self._closeBox:Layout()

    -- Chrome geometry moves with the size and font tokens
    self._shell:SetChildProps(self._titleStrip, { width = "fill", height = titleHeight() })
    self._titleBox:SetChildProps(self._drag, { inset = { right = closeSize() + 12 } })
    self._titleBox:SetChildProps(self._closeBtn, {
        align = "end", valign = "center",
        width = closeSize(), height = closeSize(), inset = { right = 6 },
    })
end

-- Hands the size limits to the client so a drag stops dead at the bound instead of
-- overshooting and snapping back when the mouse is released. SetMinResize/SetMaxResize
-- are the pre-10.0 spelling, kept as a fallback.
local function applyResizeBounds(f, minW, minH, maxW, maxH)
    if f.SetResizeBounds then
        f:SetResizeBounds(minW, minH, maxW, maxH)
    else
        if f.SetMinResize then f:SetMinResize(minW, minH) end
        if f.SetMaxResize then f:SetMaxResize(maxW, maxH) end
    end
end

-- Keeps the UIRoot anchor descriptor in step with the window's real position,
-- so a root re-layout never snaps the window back to where it started.
local function syncAnchor(f)
    if not (SuuUI.UIRoot and SuuUI.UIRoot.GetRoot and SuuUI.UIRoot:GetRoot()) then return end
    if not f._suuui_anchor then return end
    SuuUI.UIRoot:UpdateElementAnchor(f, {
        point = "TOPLEFT",
        x     = f:GetLeft() or 0,
        y     = (f:GetTop() or 0) - GetScreenHeight(),
    })
end

local function savePos(self)
    if not SuuUIConfig then SuuUIConfig = {} end
    if not SuuUIConfig.windows then SuuUIConfig.windows = {} end
    local x = self._frame:GetLeft()
    local y = self._frame:GetTop()
    SuuUIConfig.windows[self._id] = { x = x, y = y - GetScreenHeight() }
    syncAnchor(self._frame)
end

-- UIRoot owns window placement. Register as soon as the root exists.
local function registerWithRoot(f, layer, id)
    if not (SuuUI.UIRoot and SuuUI.UIRoot.GetRoot and SuuUI.UIRoot:GetRoot()) then return false end
    local cfg = SuuUIConfig and SuuUIConfig.windows and SuuUIConfig.windows[id]
    local ok, err = pcall(function()
        SuuUI.UIRoot:AddElement(f, layer, cfg
            and { point = "TOPLEFT", x = cfg.x, y = cfg.y }
            or  { point = "CENTER",  x = 0,     y = 0 })
    end)
    if not ok then
        SuuUI.Debug("Window UIRoot registration failed: " .. tostring(err))
    end
    return true
end

--- Shows the window with a fade-in animation. Emits VISIBILITY_CHANGED.
function WinMeta:Show()
    self._frame:SetAlpha(0)
    self._frame:Show()
    SuuUI.Anim.Presets.FadeIn(self._frame, SuuUI.Theme:GetToken("animFast"))
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

--- Hides the window with a fade-out animation. Emits VISIBILITY_CHANGED.
function WinMeta:Hide()
    SuuUI.Anim.Presets.FadeOut(self._frame, SuuUI.Theme:GetToken("animFast"))
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

--- Toggles window visibility.
function WinMeta:Toggle()
    if self._frame:IsShown() then self:Hide() else self:Show() end
end

--- Returns whether the window is shown.
-- @return bool
function WinMeta:IsShown()   return self._frame:IsShown() end

--- Returns the window's outer frame.
-- @return frame
function WinMeta:GetFrame()  return self._frame end

--- Returns the window width.
-- @return number
function WinMeta:GetWidth()  return self._frame:GetWidth() end

--- Returns the window height.
-- @return number
function WinMeta:GetHeight() return self._frame:GetHeight() end

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

--- Returns a container that lays out children in the window's content area.
-- @param props table  Optional container props
-- @return table  Container handle
function WinMeta:GetContentContainer(props)
    if not self._contentBox then
        props = props or {}
        props.host = self._content
        self._contentBox = SuuUI.Layout:CreateContainer(props)
    end
    return self._contentBox
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
    local minW, minH = props.minW or 200, props.minH or 200
    local maxW, maxH = props.maxW or 2000, props.maxH or 2000
    local w = props.w or 400
    local h = props.h or 300
    if props.resizable then
        w = math.max(minW, math.min(maxW, w))
        h = math.max(minH, math.min(maxH, h))
    end
    local layer = props.layer or "normal"

    local parent = UIParent
    if SuuUI.UIRoot and SuuUI.UIRoot.GetRoot then
        local root = SuuUI.UIRoot:GetRoot()
        if root then parent = root end
    end

    local f = CreateFrame("Frame", "SuuUI_win_" .. props.id, parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)

    -- Declared up front so the resize script can reference it. This must be registered
    -- BEFORE the shell container adopts the frame, so the container chains onto it
    -- instead of replacing it — otherwise nothing re-lays out on resize.
    local handle
    f:SetScript("OnSizeChanged", function(_, width, height)
        if handle then S:Emit(handle, S.SIGNALS.SIZE_CHANGED, width, height) end
    end)

    -- Chrome is laid out by the engine: title strip on top, content below
    local shell = SuuUI.Layout:CreateContainer({
        host = f, layout = "flow", dir = "vertical", gap = 0,
        padding = { top = 1, right = 1, bottom = 1, left = 1 },
    })

    -- Title strip: bar texture behind, title text left, close button right
    local titleStrip = CreateFrame("Frame", nil, f)
    shell:Add(titleStrip, { width = "fill", height = titleHeight() })

    local titleBox = SuuUI.Layout:CreateContainer({ host = titleStrip, layout = "stack" })
    local bar = titleStrip:CreateTexture(nil, "BACKGROUND")
    titleBox:Add(bar)

    local title = titleStrip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetText(props.title or props.id)
    title:SetJustifyH("LEFT")
    titleBox:Add(title, { valign = "center", inset = { left = 10, right = 40 } })

    -- Drag region covers the strip but stops short of the close button
    local drag = CreateFrame("Frame", nil, titleStrip)
    drag:EnableMouse(true)
    titleBox:Add(drag, { inset = { right = closeSize() + 12 } })

    local closeBtn = CreateFrame("Frame", nil, titleStrip, "BackdropTemplate")
    closeBtn:EnableMouse(true)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    closeBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1, insets = { left=1, right=1, top=1, bottom=1 },
    })
    closeBtn:SetBackdropColor(0, 0, 0, 0)
    closeBtn:SetBackdropBorderColor(0, 0, 0, 0)
    titleBox:Add(closeBtn, {
        align = "end", valign = "center",
        width = closeSize(), height = closeSize(), inset = { right = 6 },
    })

    local closeBox = SuuUI.Layout:CreateContainer({ host = closeBtn, layout = "stack" })
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetText(CLOSE_GLYPH)
    closeBox:Add(closeText, { align = "center", valign = "center" })

    -- Content area takes the remaining height
    local content = CreateFrame("Frame", nil, f)
    shell:Add(content, { width = "fill", height = "fill" })

    drag:SetScript("OnMouseDown", function() f:StartMoving() end)
    drag:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        savePos({ _frame = f, _id = props.id })
    end)

    handle = setmetatable({
        _id        = props.id,
        _frame     = f,
        _shell     = shell,
        _titleStrip= titleStrip,
        _titleBox  = titleBox,
        _drag      = drag,
        _titleBar  = bar,
        _titleText = title,
        _closeBtn  = closeBtn,
        _closeBox  = closeBox,
        _closeText = closeText,
        _content   = content,
        _layer     = layer,
    }, WinMeta)

    -- Resize grip, placed by an anchor container on the window frame
    if props.resizable then
        applyResizeBounds(f, minW, minH, maxW, maxH)

        local gripBox = SuuUI.Layout:CreateContainer({ host = f, layout = "anchor" })
        local grip = CreateFrame("Frame", nil, f)
        grip:EnableMouse(true)
        grip:SetFrameLevel(f:GetFrameLevel() + 10)
        gripBox:Add(grip, {
            anchor = {
                point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
                x = 0, y = 0, width = gripSize(), height = gripSize(),
            },
        })

        local gripTexBox = SuuUI.Layout:CreateContainer({ host = grip, layout = "stack" })
        local tex = grip:CreateTexture(nil, "OVERLAY")
        gripTexBox:Add(tex)

        local function gripColor(hover)
            local c = SuuUI.Theme:GetToken(hover and "colorTextMuted" or "colorBorder")
                   or {0.5, 0.5, 0.5, 1}
            tex:SetColorTexture(c[1], c[2], c[3], hover and 0.9 or 0.6)
        end
        gripColor(false)

        grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp", function()
            f:StopMovingOrSizing()
            savePos({ _frame = f, _id = props.id })
        end)
        grip:SetScript("OnEnter", function() gripColor(true) end)
        grip:SetScript("OnLeave", function() gripColor(false) end)
        handle._gripBox = gripBox
    end

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
    closeBtn:SetScript("OnMouseUp", function() handle:Hide() end)

    applyTheme(handle)
    f:Hide()

    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, "win_" .. props.id)

    -- Register now if the root already exists, otherwise as soon as it does
    if not registerWithRoot(f, layer, props.id) then
        SuuUI.Events:Once("SUUUI_CORE_READY", function()
            registerWithRoot(f, layer, props.id)
        end, "win_root_" .. props.id)
    end

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
