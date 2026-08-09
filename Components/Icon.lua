local abs = math.abs
local S = SuuUI.UISignals

local IconMeta = {}
IconMeta.__index = IconMeta

-- Blizzard's icon files bake a bevelled frame into the outer edge of the art, so a raw
-- icon inside a themed border shows two borders. Cropping to the inner span removes it.
-- A fact about the client's assets rather than a design choice, which is why it is a
-- literal here and not a theme token — no theme can change what is in the file.
local TRIM_MIN, TRIM_MAX = 0.07, 0.93

--- Sets the displayed texture. Pass nil to clear it.
-- @param path string|nil
function IconMeta:SetIcon(path)
    self._icon:SetTexture(path)
    self._path = path
end

--- Returns the current texture path.
-- @return string|nil
function IconMeta:GetIcon()
    return self._path
end

--- Sets an explicit size, dropping token-driven sizing.
-- SIZE_CHANGED comes from the frame's own resize hook, not from here.
-- @param w number
-- @param h number
function IconMeta:SetSize(w, h)
    self._autoSize = false
    self._f:SetSize(w, h)
end

-- How far the art sits inside the frame: the border width when there is a border to stay
-- clear of, nothing at all otherwise. Re-stated on a theme change because borderWidth is
-- a token — a value fixed at construction stops tracking it.
function IconMeta:_applyInset()
    local inset = 0
    if self._border then
        inset = SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1)
    end
    if self._iconProps.inset ~= inset then
        self._iconProps.inset = inset
        self._box:SetChildProps(self._icon, self._iconProps)
    end
end

-- An icon holds no text, so its size comes straight from the token rather than being
-- floored against the font metrics. Skipped when the caller pinned a size.
function IconMeta:_autosize()
    if not self._autoSize then return end
    local size = SuuUI.Theme:GetToken("sizeIcon") or 16
    if abs((self._f:GetWidth() or 0) - size) > 0.5
       or abs((self._f:GetHeight() or 0) - size) > 0.5 then
        self._f:SetSize(size, size)
    end
end

--- Sets the border colour token or literal. No-op on a borderless icon, which has no
--- backdrop to recolour. Lets an icon's edge carry state — a cast bar marks an
--- uninterruptible spell this way — without the caller rebuilding the icon.
-- @param color string|table|false
function IconMeta:SetBorderColor(color)
    if not self._border or self._borderColor == color then return end
    self._borderColor = color
    self:ApplyTheme()
end

function IconMeta:ApplyTheme()
    if self._border then
        SuuUI.Backdrop.Apply(self._f, {
            bg     = "colorBgAlt",
            border = self._borderColor or "colorBorder",
        })
    end
    self:_applyInset()
    self:_autosize()
    -- opacityDisabled is user-editable, so re-assert the fade or a live token edit never
    -- reaches an icon that is already sitting disabled.
    self:_applyEnabled()
end

function IconMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._box:Destroy()
    self._f:Hide()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide. SetSize is defined above
-- and survives: it has to clear the token-sizing flag.
SuuUI.Components.InstallBase(IconMeta, "_f")
-- Canonical enabled state: one root-frame fade via the opacityDisabled token.
SuuUI.Components.InstallEnable(IconMeta, "_f")

--- Creates a display-only icon: a texture in a frame, with an optional themed border.
--
-- For a clickable icon use IconButton — this one takes no mouse input, which is what
-- makes it safe to overlay or nest inside something that does.
--
-- Emits SIZE_CHANGED, VISIBILITY_CHANGED, ENABLED_CHANGED.
-- @param props table  { icon, size, w, h, border, borderColor, trim }
--   icon:   texture path
--   size:   square size; w/h override it per axis. Omit all three to follow sizeIcon.
--   border: draw the themed border and inset the art inside it (default false)
--   borderColor: token key or literal for that border (default "colorBorder")
--   trim:   crop the baked bevel off a Blizzard icon file (default false)
-- @param parent frame
-- @return table  Icon handle
function SuuUI.Components.Icon(props, parent)
    props = props or {}
    local pinned = props.size or props.w or props.h
    local size   = props.size or SuuUI.Theme:GetToken("sizeIcon") or 16
    local border = props.border == true

    -- The backdrop template only comes along when there is a border to draw; a plain icon
    -- is the texture and nothing else.
    local f = CreateFrame("Frame", nil, parent, border and "BackdropTemplate" or nil)
    f:SetSize(props.w or size, props.h or props.w or size)

    -- Registered before the host container adopts the frame so the container chains onto
    -- this hook. A parent layout resizes the frame directly and never calls SetSize, so
    -- this is the only place that sees a layout-driven resize.
    local handle
    f:SetScript("OnSizeChanged", function(_, w2, h2)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w2, h2)
    end)

    local box  = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
    local icon = f:CreateTexture(nil, "ARTWORK")
    if props.icon then icon:SetTexture(props.icon) end
    if props.trim then icon:SetTexCoord(TRIM_MIN, TRIM_MAX, TRIM_MIN, TRIM_MAX) end

    local iconProps = { inset = 0 }
    box:Add(icon, iconProps)

    local id = "icon_" .. tostring(f)
    handle = setmetatable({
        _f          = f,
        _icon       = icon,
        _box        = box,
        _iconProps  = iconProps,
        _eid        = id,
        _enabled    = true,
        _border     = border,
        _borderColor = props.borderColor or "colorBorder",
        _path       = props.icon,
        _autoSize   = pinned == nil,
    }, IconMeta)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
