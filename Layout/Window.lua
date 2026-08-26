local assert, type = assert, type
local tinsert, tremove = table.insert, table.remove
local C = SuuUI.Components
local S = SuuUI.UISignals

-- Window chrome is token-driven. The title strip and the close button both carry text,
-- so their heights are floored against the font metrics — a literal would clip once the
-- user raises a font token. The resize grip sizes itself from the icon token.
local function titleHeight() return SuuUI.Theme:GetControlHeight("sizeTitleBar") end
local function closeSize()   return SuuUI.Theme:GetControlHeight("sizeControlMd") end
local function borderWidth() return SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1) end
local function chromeGap()   return SuuUI.Theme:GetToken("spaceMd") or 12 end

-- Title-bar accessories are icon controls, so they take the raw size token rather than
-- GetControlHeight: flooring against the font metrics is what a text-bearing control
-- needs, and it would grow a bare icon for no reason. Same reading as ColorSwatch and
-- Toggle, which size their squares from sizeControlSm too.
local function accessorySize() return SuuUI.Theme:GetToken("sizeControlSm") or 18 end

-- Separates one accessory from the next, and the first from the close button. Tighter
-- than chromeGap so a run of icon buttons reads as one cluster in the chrome rather than
-- as separate controls.
local function accessoryGap() return SuuUI.Theme:GetToken("spaceXs") or 4 end

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

-- An accessory's square, resolved at layout time rather than stored at add time so a
-- token edit moves it. Floored against the strip: sizeControlSm reaches 32 while
-- sizeTitleBar starts at 18 and the two are edited independently, so a raised control
-- token would otherwise hang the icon out of the chrome it lives in.
local function accessoryBox(entry)
    local size = entry.size or accessorySize()
    local strip = titleHeight()
    return size < strip and size or strip
end

-- Places the accessories and re-derives the two gutters that have to clear them.
--
-- The single place either is computed. An add, a remove and a theme change all route
-- through here, so the title text's gutter, the drag surface's gutter and the accessory
-- offsets can never be recomputed from different premises — which is the failure mode
-- when a caller updates the strip and ApplyTheme later restates the old numbers.
local function layoutAccessories(self)
    local cs, gap, agap = closeSize(), chromeGap(), accessoryGap()

    -- align = "end" plus a right inset puts a child's RIGHT edge that far in from the
    -- strip's right edge, so each accessory clears the close button and every accessory
    -- added before it. band accumulates the strip that has been consumed so far, which
    -- makes the order added read outward-to-inward from the close button.
    local band = 0
    for i = 1, #self._accessories do
        local entry = self._accessories[i]
        local size  = accessoryBox(entry)
        self._titleBox:SetChildProps(entry.handle, {
            align = "end", valign = "center",
            width = size, height = size,
            inset = { right = CLOSE_EDGE_GAP + cs + agap + band },
        })
        band = band + size + agap
    end

    -- Both gutters were already expressed from the close button's token size; the
    -- accessories sit between it and the title, so both grow by the whole band. chromeGap
    -- exceeds CLOSE_EDGE_GAP, which is what keeps the drag surface short of the leftmost
    -- accessory by the same margin it already kept off the close button.
    self._titleBox:SetChildProps(self._titleT, {
        valign = "center",
        inset  = { left = TITLE_PAD_L, right = cs + CLOSE_EDGE_GAP + gap + band },
    })
    -- A TITLE WIDGET SITS WHERE THE TEXT DOES, and takes its natural width rather than filling the
    -- strip: it is a control the player aims at, so it must not stretch to the close button and it
    -- must not be measured against the accessory band the way the text is.
    if self._titleWidget then
        self._titleBox:SetChildProps(self._titleWidget, {
            align = "start", valign = "center",
            width = self._titleWidgetW,
            height = self._titleWidgetH,
            inset = { left = TITLE_PAD_L },
        })
    end
    -- THE DRAG REGION STOPS SHORT OF A TITLE WIDGET. Raising the widget above it is what makes the
    -- click land, but leaving the drag underneath means a press that misses the control by a pixel
    -- starts moving the window instead -- so the region is inset past it as well. Belt and braces on
    -- purpose: one of the two is a z-order guarantee and the other is a geometry one.
    local dragLeft = 0
    if self._titleWidget then
        dragLeft = TITLE_PAD_L + (self._titleWidgetW or 0) + gap
    end
    self._titleBox:SetChildProps(self._drag, {
        inset = { left = dragLeft, right = cs + gap + band },
    })
end

local function applyTheme(self)
    -- GLASS OR FLAT, decided once at construction. `glass = true` paints the translucent vertical
    -- gradient plus the lit hairline top edge instead of a flat panel -- the plate an action bar
    -- already draws itself on, and what the inventory concept specifies for its own surface
    -- (dense at the TOP, fading downward, with a 10%-white inset highlight along the top edge).
    --
    -- Not a runtime switch: Glass builds seven textures per layer and returns a handle, so
    -- swapping surfaces mid-life would mean tearing one down and standing the other up on a frame
    -- that already has children anchored over it. A window's surface is a property of what kind of
    -- window it is, not a state it moves through.
    if self._glass then
        self._glass:SetBorder("colorBorder")
        self._glass:Refresh()
    else
        SuuUI.Backdrop.Apply(self._frame, { bg = "colorBg", border = "colorBorder" })
    end

    -- Chrome geometry moves with the size and font tokens. The title text and the drag
    -- region both have to clear the close button, so both insets are expressed from its
    -- token size rather than from a magic width.
    local cs = closeSize()
    self._shell:SetChildProps(self._titleStrip, { width = "fill", height = titleHeight() })
    self._titleBox:SetChildProps(self._closeBtn, {
        align = "end", valign = "center",
        width = cs, height = cs, inset = { right = CLOSE_EDGE_GAP },
    })
    -- Title gutter, drag gutter and accessory offsets, from one arithmetic.
    layoutAccessories(self)

    -- The chrome components own their own tokens, but the event bus fires listeners
    -- newest-first: left to their own handlers they would restyle after the window had
    -- already re-flowed the strip, so the title would be measured at the previous font.
    self._titleStrip:ApplyTheme()
    self._titleT:ApplyTheme()
    self._closeBtn:ApplyTheme()
    if self._gripComp then self._gripComp:ApplyTheme() end

    -- Accessories are deliberately NOT re-themed here. The window sizes them (above) but
    -- does not own them: each is a component the caller built, with its own
    -- SUUUI_THEME_CHANGED subscription, and re-applying it from here would paint a handle
    -- this window is not responsible for.
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
--
-- The optional offset is what lets a PAIR of windows sit side by side -- the inventory's bank session
-- opens two and centres the pair rather than each one, so neither lands on top of the other. It is an
-- offset from centre rather than an absolute position deliberately: a centred window already discards
-- its drags and re-centres on every open, so a paired offset recomputed per open is consistent with
-- that instead of fighting a stored position that is never saved.
-- @param dx number|nil  units right of centre
-- @param dy number|nil  units up from centre
function WinMeta:Center(dx, dy)
    if not (SuuUI.UIRoot and SuuUI.UIRoot.UpdateElementAnchor) then return end
    -- Remembered so a resize can re-centre without losing a paired offset (see SetSize below).
    self._cdx, self._cdy = dx or 0, dy or 0

    -- NOT a CENTER-to-CENTER anchor any more. The client resolves that as (container - window) / 2,
    -- so an ODD dimension lands the window on a HALF UNIT -- and with the pixel grid active one unit
    -- is one physical pixel, so every 1px border anywhere inside the window straddles two pixel rows
    -- and rasterises at roughly half alpha.
    --
    -- Measured in game at 1440p: an inventory window sized from a 41-unit cell put every row of item
    -- cells on X.5, and the quality borders along the icons' TOP and BOTTOM edges vanished while the
    -- left and right ones looked perfect. It appeared and disappeared as the window was dragged, which
    -- is the tell -- the drag path re-anchors through `offsetFromRoot`, which snaps, so a dragged
    -- window was correct and a freshly centred one was not.
    --
    -- The offset cannot carry a half-unit correction either -- but it does not need to: AnchorLayout
    -- snaps every coordinate on its way to SetPoint, so ANY numeric offset lands on the grid. That is
    -- the whole fix. A CENTER-to-CENTER pair has no coordinate for the strategy to snap, because the
    -- client resolves it internally; a stated offset does. Snapping here as well was tried and is
    -- redundant -- mutation testing showed removing it changed nothing, because the strategy had
    -- already done it.
    local rc = SuuUI.UIRoot.GetRootContainer and SuuUI.UIRoot:GetRootContainer()
    local cw = rc and rc:GetWidth() or 0
    local ch = rc and rc:GetHeight() or 0
    local w  = self._frame:GetWidth() or 0
    local h  = self._frame:GetHeight() or 0
    if cw > 0 and ch > 0 and w > 0 and h > 0 then
        SuuUI.UIRoot:UpdateElementAnchor(self._frame, {
            point = "TOPLEFT", relativePoint = "TOPLEFT",
            x = (cw - w) / 2 + self._cdx,
            -- `dy` is documented as units UP from centre, and a TOPLEFT offset grows downward.
            y = -((ch - h) / 2 - self._cdy),
        })
        return
    end
    -- Sizes are not resolvable yet -- a window centred before it has ever been laid out. The client's
    -- own centring is still better than anchoring at the corner, and the next resize re-centres it.
    SuuUI.UIRoot:UpdateElementAnchor(self._frame,
        { point = "CENTER", x = self._cdx, y = self._cdy })
end

--- Sets the window's size, re-centring a centred window so it stays centred.
--
-- A CENTER-to-CENTER anchor re-centred on resize for free; the explicit snapped offset `Center` now
-- states does not, so the resize has to say so. This is why it is an override rather than an
-- `OnSizeChanged` hook: a hook would also fire in the middle of a resize-grip drag and fight it.
-- Declared before `InstallBase`, which only fills gaps, so this survives.
function WinMeta:SetSize(w, h)
    self._frame:SetSize(w, h)
    if self._centered then self:Center(self._cdx, self._cdy) end
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

--- Adds a small control to the title bar, immediately left of the close button.
--
-- Accessories are right-aligned and stack inward from the close button in the order they
-- were added, so the first one added sits nearest it. The title text and the drag surface
-- each give up exactly the width the accessories take, so neither is overlapped and the
-- rest of the strip still drags the window.
--
-- Sized from sizeControlSm and re-derived on every theme change, so a token edit moves
-- the whole cluster. Pass opts.size only for a control that genuinely is not that scale.
--
-- OWNERSHIP: the window does not own the handle. It is never destroyed and never
-- re-themed by the window, because the caller created it — call RemoveTitleAccessory
-- before destroying it yourself. The frame IS reparented into the title strip, so it
-- hides and shows with the window.
--
-- @param handle table  A component handle (an IconButton is the intended shape)
-- @param opts table    Optional { size = number } overriding the token square
-- @return table  The handle, so a caller can chain off the call
function WinMeta:AddTitleAccessory(handle, opts)
    assert(type(handle) == "table" and handle.GetFrame,
        "SuuUI Window: AddTitleAccessory needs a component handle")
    for i = 1, #self._accessories do
        assert(self._accessories[i].handle ~= handle,
            "SuuUI Window: accessory already added to this window")
    end
    opts = opts or {}

    -- Reparent so the accessory belongs to the strip's subtree: the client hides and hit-
    -- tests a whole subtree together, and an accessory left under its original parent
    -- would stay clickable after the window closed.
    handle:GetFrame():SetParent(self._titleStrip:GetFrame())

    tinsert(self._accessories, { handle = handle, size = opts.size })
    self._titleBox:Add(handle)

    -- The drag surface spans the strip and the client gives a click to the topmost
    -- mouse-enabled frame, so an accessory that merely ties with it on frame level is
    -- decided by creation order — which is not something to depend on. Raised for the
    -- same reason and by the same step as the close button. After SetParent, which
    -- re-derives the level from the new parent.
    SuuUI.UIRoot:RaiseAbove(handle:GetFrame(), self._frame, 10)

    layoutAccessories(self)
    return handle
end

--- Removes a title-bar accessory and gives the title and drag gutters back.
-- The handle is not destroyed — the caller owns it and may re-add or destroy it.
-- @param handle table
-- @return bool  Whether the handle was an accessory of this window
function WinMeta:RemoveTitleAccessory(handle)
    for i = 1, #self._accessories do
        if self._accessories[i].handle == handle then
            tremove(self._accessories, i)
            self._titleBox:Remove(handle)
            layoutAccessories(self)
            return true
        end
    end
    return false
end

--- Returns the accessory handles in the order they were added.
-- A copy, as Container:GetPadding is: handing out the live table would let a caller
-- reorder or empty the strip without the gutters ever being recomputed.
-- @return table  Array of component handles
function WinMeta:GetTitleAccessories()
    local out = {}
    for i = 1, #self._accessories do out[i] = self._accessories[i].handle end
    return out
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
--- Puts a component where the title TEXT normally goes, hiding the text.
--
-- For a window whose title IS a control -- the inventory's character dropdown is the case: the name of
-- the character whose bags you are looking at is the title, so a separate word beside it labels the
-- same thing twice.
--
-- NOT AddTitleAccessory, which is the other end of the strip. Accessories stack inward from the CLOSE
-- BUTTON, so a dropdown handed to it lands squeezed against the X and pushes the icons out of the band
-- -- which is exactly what shipped before this existed.
--
-- The text is hidden rather than emptied, so SetTitle keeps working and a caller can drop the widget
-- later and get the title back.
-- @param handle table|nil  a component handle, or nil to restore the text
function WinMeta:SetTitleWidget(handle)
    if self._titleWidget and self._titleWidget ~= handle then
        self._titleBox:Remove(self._titleWidget)
    end
    self._titleWidget = handle or nil
    if handle then
        -- REPARENTED, so the widget belongs to the strip's subtree: the client hides and hit-tests a
        -- whole subtree together, and a widget left under its original parent would stay clickable
        -- after the window closed.
        handle:GetFrame():SetParent(self._titleStrip:GetFrame())
        -- CAPTURED BEFORE THE ADD. A stack child with no width stretches, so reading GetWidth() after
        -- adding returns the width of the whole strip -- which then gets pinned as the "natural" width
        -- and the dropdown covers the title bar, icons and all.
        -- BOTH AXES, captured before the add for the same reason: a stack child pins neither by
        -- default, so an unstated height stretches the widget to the full strip -- which made a
        -- title-bar dropdown exactly as tall as the bar, with no clearance and no visible box.
        self._titleWidgetW = handle:GetWidth()
        self._titleWidgetH = handle:GetHeight()
        self._titleBox:Add(handle)
        -- RAISED ABOVE THE DRAG SURFACE, which is the whole reason a title widget needs more than a
        -- layout slot. The drag region SPANS the strip from the left edge to the accessory band -- so
        -- it covers exactly where the title sits -- and the client gives a click to the topmost
        -- mouse-enabled frame. Reported in game: the dropdown was in the right place and would not
        -- open, because the drag surface was taking every click. Same step as the close button and the
        -- accessories, and after SetParent, which re-derives the level from the new parent.
        SuuUI.UIRoot:RaiseAbove(handle:GetFrame(), self._frame, 10)
        self._titleT:Hide()
    else
        self._titleT:Show()
    end
    applyTheme(self)
end

--- The widget currently standing in for the title, or nil.
-- @return table|nil
function WinMeta:GetTitleWidget() return self._titleWidget end

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
-- glass = true paints the surface with Backdrop.Glass (translucent gradient + lit top edge)
-- instead of a flat panel. Fixed at construction; see applyTheme.
-- @param props table  { id, title, w, h, minW, minH, maxW, maxH, resizable, centered, layer, glass }
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

    -- The glass surface, when asked for. Built here rather than in applyTheme because Glass
    -- creates textures and returns a handle: applyTheme runs on every theme edit, and building
    -- a second set there would stack seven more textures on the frame each time.
    --
    -- It goes on BEFORE any child is added, so the gradient and its top-edge sheen sit under the
    -- title strip and the content rather than over them. Glass draws in the frame's own
    -- background layers, so nothing needs raising afterwards.
    local glass
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

    -- THE GLASS SURFACE, and it is built HERE rather than at CreateFrame time for one reason: Glass
    -- lays its pieces out with a HOST CONTAINER on this frame, and a host container chains onto
    -- whatever OnSizeChanged is already installed. Built before the line above, its hook was REPLACED
    -- by that SetScript -- so the surface never re-laid out and kept whatever size the window had when
    -- it was created. Measured in game: a 219-unit window wearing a 411x546 glass body, which is the
    -- dead band that appeared below the footer whenever the window shrank.
    --
    -- This is the documented trap in LAYOUT_SYSTEM.md, stated the other way round: register the
    -- frame's own resize script BEFORE anything adopts it. Both orderings are one line apart and only
    -- one of them works.
    --
    -- It still goes on before any CHILD is added, so the gradient and its top-edge sheen sit under the
    -- title strip and the content rather than over them.
    if props.glass then
        -- ALL THREE COLOURS ARE REQUIRED. Glass stores `from` / `to` / `sheen` verbatim and applies no
        -- defaults of its own, so a call passing only `border` builds a complete handle whose body has
        -- no colour and draws NOTHING -- the window came up with no surface at all, the game world
        -- showing through it.
        glass = SuuUI.Backdrop.Glass(f, {
            from = "colorGlass", to = "colorGlassFade", sheen = "colorGlassSheen",
            border = "colorBorder",
        })
    end

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
        _glass     = glass,
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
        -- Handles the caller owns, in add order. Entries are { handle, size }: the size is
        -- the opts override, nil meaning the token owns it.
        _accessories = {},
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
