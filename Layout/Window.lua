local assert, type = assert, type
local tinsert = table.insert
local C = SuuUI.Components
local S = SuuUI.UISignals

-- Window chrome is token-driven. The title strip and the close button both carry text,
-- so their heights are floored against the font metrics — a literal would clip once the
-- user raises a font token. The resize grip sizes itself from the icon token.
local function titleHeight() return SuuUI.Theme:GetControlHeight("sizeTitleBar") end
local function closeSize()   return SuuUI.Theme:GetControlHeight("sizeControlMd") end
local function borderWidth() return SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1) end
local function chromeGap()   return SuuUI.Theme:GetToken("spaceMd") or 12 end

-- ASCII only. FRIZQT__.TTF has no glyph for U+00D7 (the multiplication sign that reads
-- as a nicer close mark in a text editor), so it drew as blank in the client.
local CLOSE_GLYPH = "X"

-- Left gutter for the title text. Falls between spaceSm (8) and spaceMd (12), so it is
-- a named constant rather than a space token bent to fit.
local TITLE_PAD_L = 10

-- Gap between the close button and the window's right edge. Deliberately tighter than
-- spaceSm (8) so the button reads as part of the chrome rather than a floating control,
-- and wider than spaceXs (4) so it is not flush with the border.
local CLOSE_EDGE_GAP = 6

-- The close button is a fixed square sized from the control token, so its glyph is given
-- the whole box: the component's default text padding would clamp the label narrower
-- than its own metrics and the client would clip it.
local CLOSE_GLYPH_PAD = 0

local WinMeta = {}
WinMeta.__index = WinMeta
local registry = {}

local function applyTheme(self)
    SuuUI.Backdrop.Apply(self._frame, { bg = "colorBg", border = "colorBorder" })

    -- Chrome geometry moves with the size and font tokens. The title text and the drag
    -- region both have to clear the close button, so both insets are expressed from its
    -- token size rather than from a magic width.
    local cs, gap = closeSize(), chromeGap()
    self._shell:SetChildProps(self._titleStrip, { width = "fill", height = titleHeight() })
    self._titleBox:SetChildProps(self._titleT, {
        valign = "center",
        inset  = { left = TITLE_PAD_L, right = cs + CLOSE_EDGE_GAP + gap },
    })
    self._titleBox:SetChildProps(self._drag, { inset = { right = cs + gap } })
    self._titleBox:SetChildProps(self._closeBtn, {
        align = "end", valign = "center",
        width = cs, height = cs, inset = { right = CLOSE_EDGE_GAP },
    })

    -- The chrome components own their own tokens, but the event bus fires listeners
    -- newest-first: left to their own handlers they would restyle after the window had
    -- already re-flowed the strip, so the title would be measured at the previous font.
    self._titleStrip:ApplyTheme()
    self._titleT:ApplyTheme()
    self._closeBtn:ApplyTheme()
    if self._gripComp then self._gripComp:ApplyTheme() end

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

-- The window's offset from the UI root's top-left, which is the frame of reference the
-- anchor descriptor is applied in.
--
-- Measured against the root's own rect, never against GetScreenHeight(). A widget reports
-- its rect in its own region units, and the root carries the pixel-grid scale, so a window
-- under it is in a different unit space from UIParent — GetScreenHeight() is in UIParent's.
-- Mixing them leaves y wrong by the difference between the two screen heights (312 units
-- at 1080p) while x, needing no screen constant, stays correct. The root and the window
-- share a space, so measuring between them has no conversion to get wrong.
local function offsetFromRoot(f)
    local ref = SuuUI.UIRoot and SuuUI.UIRoot.GetRootContainer
                and SuuUI.UIRoot:GetRootContainer()
    local rf  = ref and ref:GetFrame()
    local rl, rt = rf and rf:GetLeft(), rf and rf:GetTop()
    if not (rl and rt) then
        -- No root yet: derive the screen top in this frame's own units instead. 768 is
        -- the engine's virtual screen height, so this is the same conversion the client
        -- applies, just done explicitly.
        local scale = f:GetEffectiveScale()
        if type(scale) ~= "number" or scale <= 0 then scale = 1 end
        rl, rt = 0, 768 / scale
    end
    local snap = SuuUI.Pixel.Snap
    return snap((f:GetLeft() or 0) - rl), snap((f:GetTop() or 0) - rt)
end

-- Keeps the UIRoot anchor descriptor in step with the window's real position,
-- so a root re-layout never snaps the window back to where it started.
local function syncAnchor(f)
    if not (SuuUI.UIRoot and SuuUI.UIRoot.GetRoot and SuuUI.UIRoot:GetRoot()) then return end
    if not f._suuui_anchor then return end
    local x, y = offsetFromRoot(f)
    SuuUI.UIRoot:UpdateElementAnchor(f, { point = "TOPLEFT", x = x, y = y })
end

-- A drag-resize is the one geometry in the addon the client writes directly, so it never
-- passes through a layout strategy and can leave the window a fraction of a unit wide —
-- which puts its border back across a pixel boundary. Snap it once the drag ends.
local function snapSize(f)
    local snap = SuuUI.Pixel.Snap
    local w, h = snap(f:GetWidth() or 0), snap(f:GetHeight() or 0)
    if w > 0 and h > 0 then f:SetSize(w, h) end
end

-- A window lives in the root's unit space, and the pixel grid makes that space the
-- screen: one unit is `multiplier` physical pixels, so the root is
-- physicalHeight / multiplier units tall. A window sized past that hangs its lower edge
-- and its resize grip off-screen, where SetClampedToScreen is no help — that clamps
-- position, not size. So the screen, not an arbitrary constant, is the default ceiling.
-- A margin is left so a maximal window still reads as a window.
local ROOT_FIT      = 0.9
local FALLBACK_MAX  = 2000

-- nil when the root does not exist yet, which leaves the fallback in charge rather than
-- capping against a size we cannot know.
local function rootExtent()
    local root = SuuUI.UIRoot and SuuUI.UIRoot.GetRoot and SuuUI.UIRoot:GetRoot()
    if not root then return nil, nil end
    local w, h = root:GetWidth(), root:GetHeight()
    if type(w) ~= "number" or w <= 0 then w = nil end
    if type(h) ~= "number" or h <= 0 then h = nil end
    return w, h
end

local function fitCap(avail)
    if not avail then return FALLBACK_MAX end
    return SuuUI.Pixel.Floor(avail * ROOT_FIT)
end

local function savePos(self)
    if not SuuUIConfig then SuuUIConfig = {} end
    if not SuuUIConfig.windows then SuuUIConfig.windows = {} end
    -- The same offsets the anchor is rebuilt from, so a save and a restore agree.
    local x, y = offsetFromRoot(self._frame)
    SuuUIConfig.windows[self._id] = { x = x, y = y }
    syncAnchor(self._frame)
end

-- UIRoot owns window placement. Register as soon as the root exists.
local function registerWithRoot(f, layer, id, centered)
    if not (SuuUI.UIRoot and SuuUI.UIRoot.GetRoot and SuuUI.UIRoot:GetRoot()) then return false end
    local cfg = (not centered) and SuuUIConfig and SuuUIConfig.windows and SuuUIConfig.windows[id]
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

--- Re-asserts a CENTER placement through UIRoot, which also puts the anchor descriptor
--- back in step with the frame after a drag moved it behind the layout's back.
function WinMeta:Center()
    if not (SuuUI.UIRoot and SuuUI.UIRoot.UpdateElementAnchor) then return end
    SuuUI.UIRoot:UpdateElementAnchor(self._frame, { point = "CENTER", x = 0, y = 0 })
end

--- Shows the window with a fade-in animation. Emits VISIBILITY_CHANGED.
function WinMeta:Show()
    -- A centered window keeps no position, so every open starts from the middle again
    -- rather than wherever the last drag in this session happened to leave it.
    if self._centered then self:Center() end
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

--- Sets the window title text.
-- @param text string
function WinMeta:SetTitle(text)
    self._titleT:SetText(text)
end

--- Returns the inner content frame for attaching children.
-- @return frame
function WinMeta:GetContentFrame()
    return self._content
end

--- Returns the usable size of the content area.
-- The real box, not the requested one: a window caps itself to the screen, so the w/h it
-- was built with are a request that a small display overrides. Callers size their panels
-- from this rather than reaching through GetContentFrame() to the client's own getters.
-- @return number, number  width, height
function WinMeta:GetContentSize()
    return self._content:GetWidth() or 0, self._content:GetHeight() or 0
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

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize. Show and Hide are defined
-- above and survive: they animate. Deferred to first use because the .toc loads the
-- layout engine ahead of Components/Base.lua.
local baseInstalled = false
local function installBase()
    if baseInstalled then return end
    baseInstalled = true
    C.InstallBase(WinMeta, "_frame")
end

--- Creates a new draggable themed window.
-- w/h are a preference: without an explicit maxW/maxH they are capped to the screen, so
-- a window is never born larger than the space it has to live in.
-- centered = true pins the window to the middle on every open and keeps no saved
-- position, for a window that should always appear in the same place.
-- @param props table  { id, title, w, h, minW, minH, maxW, maxH, resizable, centered, layer }
-- @return table  Window handle
function SuuUI.Layout:CreateWindow(props)
    assert(type(props.id) == "string", "SuuUI Window: id required")
    installBase()

    local minW, minH = props.minW or 200, props.minH or 200
    -- An explicit max is honoured as given; otherwise the screen is the ceiling.
    local rootW, rootH = rootExtent()
    local maxW, maxH = props.maxW or fitCap(rootW), props.maxH or fitCap(rootH)
    local w = props.w or 400
    local h = props.h or 300
    if props.resizable then
        w = math.max(minW, math.min(maxW, w))
        h = math.max(minH, math.min(maxH, h))
    else
        -- No resize bounds to satisfy, so only the ceiling applies: a fixed-size window
        -- is never grown, just kept on screen.
        w, h = math.min(maxW, w), math.min(maxH, h)
    end
    local layer = props.layer or "window"
    local centered = props.centered or false

    local parent = UIParent
    if SuuUI.UIRoot and SuuUI.UIRoot.GetRoot then
        local root = SuuUI.UIRoot:GetRoot()
        if root then parent = root end
    end

    local f = CreateFrame("Frame", "SuuUI_win_" .. props.id, parent, "BackdropTemplate")
    f:SetSize(w, h)
    -- Placed by the layer system, not by a hand-written strata: registerWithRoot re-applies
    -- the same layer later, and a window created before the root exists must still land on
    -- the window rung rather than tie with the plugin frames it is meant to cover.
    SuuUI.UIRoot:SetLayer(f, layer)
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

    -- Chrome is laid out by the engine: title strip on top, content below. The shell
    -- padding is the window's own border, so it tracks the border token.
    local bw = borderWidth()
    local shell = SuuUI.Layout:CreateContainer({
        host = f, layout = "flow", dir = "vertical", gap = 0,
        padding = { top = bw, right = bw, bottom = bw, left = bw },
    })

    -- Title strip: an alt-surface frame holding the title text and the close button
    local titleStrip = C.Frame({ variant = "bgAlt", border = false }, f)
    shell:Add(titleStrip, { width = "fill", height = titleHeight() })

    local titleBox = SuuUI.Layout:CreateContainer({ host = titleStrip, layout = "stack" })

    -- Text owns the font, colour and re-measure on a font token change, which a
    -- hand-rolled font string does not.
    local titleT = C.Text({
        text = props.title or props.id, size = "md", color = "text",
        justify = "LEFT", wrap = false,
    }, titleStrip:GetFrame())
    titleBox:Add(titleT, { valign = "center", inset = { left = TITLE_PAD_L } })

    -- Drag region covers the strip but stops short of the close button
    local drag = CreateFrame("Frame", nil, titleStrip:GetFrame())
    drag:EnableMouse(true)
    titleBox:Add(drag)

    -- Button, not IconButton: the close mark is a text glyph, so it needs the label
    -- pipeline that re-measures itself when a font token changes.
    local closeBtn = C.Button({
        label = CLOSE_GLYPH, w = closeSize(), h = closeSize(),
        padX = CLOSE_GLYPH_PAD, padY = CLOSE_GLYPH_PAD,
        -- The glyph is sized to fit the title strip exactly, so the press pop would grow
        -- it outside the strip and read as the button jumping out and back. The pressed
        -- bg and border still land, so the press is still acknowledged.
        scalePop = false,
    }, titleStrip:GetFrame())
    SuuUI.UIRoot:RaiseAbove(closeBtn:GetFrame(), f, 10)
    titleBox:Add(closeBtn)

    -- Content area takes the remaining height
    local content = CreateFrame("Frame", nil, f)
    shell:Add(content, { width = "fill", height = "fill" })

    drag:SetScript("OnMouseDown", function() f:StartMoving() end)
    drag:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if centered then
            -- Sync the anchor descriptor so a root re-layout does not snap back to
            -- CENTER.  Don't persist to SuuUIConfig — the next Show() re-centers.
            syncAnchor(f)
        else
            savePos({ _frame = f, _id = props.id })
        end
    end)

    handle = setmetatable({
        _id        = props.id,
        _frame     = f,
        _shell     = shell,
        _titleStrip= titleStrip,
        _titleBox  = titleBox,
        _drag      = drag,
        _titleT    = titleT,
        _closeBtn  = closeBtn,
        -- _titleText and _closeText stay the font strings so callers and specs reach the
        -- same regions the components own.
        _titleText = titleT:GetFrame(),
        _closeText = closeBtn._label,
        _content   = content,
        _layer     = layer,
        _centered  = centered,
    }, WinMeta)

    -- Resize grip, placed by an anchor container on the window frame
    if props.resizable then
        applyResizeBounds(f, minW, minH, maxW, maxH)

        local gripBox = SuuUI.Layout:CreateContainer({ host = f, layout = "anchor" })
        -- The component owns its own size from the icon token, so the descriptor carries
        -- position only: a raised sizeIcon regrows the grip and the container re-lays it
        -- out off its SIZE_CHANGED, with no size to keep in step here.
        local gripC = C.ResizeGrip({}, f)
        SuuUI.UIRoot:RaiseAbove(gripC:GetFrame(), f, 10)
        gripBox:Add(gripC, {
            anchor = {
                point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = 0, y = 0,
            },
        })

        -- The grip reports a gesture; the window decides what it means. Signals rather
        -- than the grip's frame scripts, so the corner stays a reusable component instead
        -- of something that knows how a window resizes.
        local RG = C.RESIZEGRIP_SIGNALS
        S:Connect(gripC, RG.DRAG_START, function() f:StartSizing("BOTTOMRIGHT") end)
        S:Connect(gripC, RG.DRAG_STOP, function()
            f:StopMovingOrSizing()
            snapSize(f)
            if not centered then savePos({ _frame = f, _id = props.id }) end
        end)

        handle._gripBox  = gripBox
        handle._gripComp = gripC
        -- _grip stays the frame so callers and specs reach the same region the component
        -- owns, as _titleText and _closeText do.
        handle._grip     = gripC:GetFrame()
    end

    S:Connect(closeBtn, S.SIGNALS.CLICKED, function() handle:Hide() end)

    applyTheme(handle)
    f:Hide()

    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, "win_" .. props.id)

    -- Register now if the root already exists, otherwise as soon as it does
    if not registerWithRoot(f, layer, props.id, centered) then
        SuuUI.Events:Once("SUUUI_CORE_READY", function()
            registerWithRoot(f, layer, props.id, centered)
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
