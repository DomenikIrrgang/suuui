local abs = math.abs
local floor = math.floor
local format = string.format
local S = SuuUI.UISignals

-- The ring an aura icon wears when nothing has tinted it. Its own semantic rather than the
-- panel border: colorBorder is a near-black hairline that reads against the game world but
-- vanishes against spell art, which is itself dark at the edges.
local BORDER_TOKEN = "colorBorderIcon"

local AuraIconMeta = {}
AuraIconMeta.__index = AuraIconMeta

---------------------------------------------------------------------------
-- Duration formatting
---------------------------------------------------------------------------

-- Duration text lives IN the component because every consumer of an aura remaining-time
-- would write the same three-tier format otherwise. This deliberately differs from
-- StatusBar (which takes plain strings only and leaves formatting to the caller): a bar's
-- remaining-time meaning varies by context; an aura's does not.

local function formatDuration(seconds)
    if seconds >= 3600 then
        return format("%dh", floor(seconds / 3600))
    elseif seconds >= 60 then
        return format("%dm", floor(seconds / 60))
    elseif seconds >= 1 then
        return format("%ds", floor(seconds))
    end
    -- Below one second is the only band where a decimal carries information: the whole-second
    -- form would read "0s" for the entire final second. Floored rather than rounded, because
    -- "%.1f" on 0.99 prints "1.0s" -- contradicting the branch that chose it, and a glyph
    -- wider than anything else this formatter can produce.
    return format("%.1fs", floor(seconds * 10) / 10)
end

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

function AuraIconMeta:_paintDuration()
    if not self._durationText then return end
    if not self._showDuration or not self._timeLeft then
        self._durationText:Hide()
        return
    end
    self._durationText:SetText(formatDuration(self._timeLeft))
    -- Under 5 seconds the text takes colorWarning so an expiring buff reads at a glance;
    -- above that it takes colorText. Text's built-in colmap does not have a "warning" key,
    -- so the colour is applied directly through SetTextColor on the font string.
    local T = SuuUI.Theme
    if self._timeLeft < 5 then
        local c = T:GetToken("colorWarning")
        if c then
            self._durationText:GetFrame():SetTextColor(c[1], c[2], c[3], c[4] or 1)
            self._durColorOverride = true
        end
    elseif self._durColorOverride then
        self._durationText:SetColor("text")
        self._durColorOverride = false
    end
    self._durationText:Show()
end

function AuraIconMeta:_updateCount()
    if not self._countText then return end
    if self._count and self._count > 1 then
        self._countText:SetText(tostring(self._count))
        self._countText:Show()
    else
        self._countText:Hide()
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Sets the displayed icon texture path.
-- @param path string|nil
function AuraIconMeta:SetIcon(path)
    self._iconComp:SetIcon(path)
end

--- Returns the current icon texture path.
-- @return string|nil
function AuraIconMeta:GetIcon()
    return self._iconComp:GetIcon()
end

--- Sets the stack count. Counts of 0 or 1 hide the count readout; the live client
--- reports 0 for a non-stacking aura, so >1 is the visibility threshold.
-- @param n number|nil
function AuraIconMeta:SetCount(n)
    self._count = n
    self:_updateCount()
end

--- Sets the swipe timer on the Cooldown frame.
-- Pass nil for both to clear the swipe and hide the duration text.
-- @param duration number|nil  Total duration of the aura in seconds
-- @param expirationTime number|nil  GetTime() when the aura expires
function AuraIconMeta:SetTimer(duration, expirationTime)
    self._duration = duration
    self._expirationTime = expirationTime
    if duration and expirationTime and duration > 0 then
        local start = expirationTime - duration
        self._cooldown:SetCooldown(start, duration)
    else
        self._cooldown:SetCooldown(0, 0)
        self._timeLeft = nil
        self:_paintDuration()
    end
end

--- Updates the time-left display. The owner's shared ticker calls this rather than each
--- icon computing GetTime() independently.
-- @param seconds number|nil  Remaining seconds; nil or 0 clears the display
function AuraIconMeta:SetTimeLeft(seconds)
    if not seconds or seconds <= 0 then
        self._timeLeft = nil
    else
        self._timeLeft = seconds
    end
    self:_paintDuration()
end

--- Sets the border tint. Pass nil to return to the neutral icon ring.
-- @param color table|nil  {r,g,b,a} literal, or nil
function AuraIconMeta:SetTypeColor(color)
    self._typeColor = color
    if color then
        self._iconComp:SetBorderColor(color)
    else
        self._iconComp:SetBorderColor(BORDER_TOKEN)
    end
end

--- Sets whether the duration readout is shown when a timer is active.
-- @param show bool
function AuraIconMeta:SetShowDuration(show)
    self._showDuration = show ~= false
    self:_paintDuration()
end

--- Overrides the automatic token-driven sizing, disabling it.
-- SIZE_CHANGED comes from the frame's own resize hook, not from here.
-- @param w number
-- @param h number
function AuraIconMeta:SetSize(w, h)
    self._autoSize = false
    self._f:SetSize(w, h)
end

-- No text of its own, so the size comes straight from the token.
function AuraIconMeta:_autosize()
    if not self._autoSize then return end
    local size = SuuUI.Theme:GetToken("sizeIcon") or 16
    if abs((self._f:GetWidth() or 0) - size) > 0.5
       or abs((self._f:GetHeight() or 0) - size) > 0.5 then
        self._f:SetSize(size, size)
    end
end

-- How far the cooldown sits inside the frame: the border width, so the swipe covers the
-- ART and not the frame's own edge. A child frame draws above every layer of its parent,
-- backdrop border included, so a full-bleed cooldown paints over the border ring -- which
-- is the one part of the icon the dispel colour is carried on. Re-stated on a theme change
-- because borderWidth is a token; a value fixed at construction stops tracking it.
function AuraIconMeta:_applyCooldownInset()
    local inset = SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1)
    if self._cdProps.inset ~= inset then
        self._cdProps.inset = inset
        self._box:SetChildProps(self._cooldown, self._cdProps)
    end
end

function AuraIconMeta:ApplyTheme()
    self._iconComp:ApplyTheme()
    self:_applyCooldownInset()
    self:_applyEnabled()
    self:_autosize()
    -- Re-derive the duration colour in case colorWarning changed
    self:_paintDuration()
end

function AuraIconMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    if self._countText then self._countText:Destroy() end
    if self._durationText then self._durationText:Destroy() end
    self._iconComp:Destroy()
    self._box:Destroy()
    self._f:Hide()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide.
-- SetSize is defined above and survives.
SuuUI.Components.InstallBase(AuraIconMeta, "_f")
-- Canonical enabled state: one root-frame fade + mouse-drop.
SuuUI.Components.InstallEnable(AuraIconMeta, "_f")

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Creates an aura icon: an icon with a cooldown swipe, optional stack count, duration
--- readout, and debuff-type border colour. Takes mouse input for tooltip and cancel.
--
-- Emits: CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, SIZE_CHANGED, VISIBILITY_CHANGED,
-- ENABLED_CHANGED.
--
-- @param props table  { icon, size, count, duration, expirationTime, showDuration,
--                       typeColor, trim }
--   icon:           texture path
--   size:           square side; omit to follow the sizeIcon token
--   count:          stack count (nil or 0-1 hides the readout)
--   duration:       total duration in seconds (for the cooldown swipe)
--   expirationTime: GetTime() when the aura expires
--   showDuration:   whether the duration text is shown (default true)
--   typeColor:      debuff-type border colour literal {r,g,b,a}, or nil
--   trim:           crop Blizzard's baked bevel (default true)
-- @param parent frame
-- @return table  AuraIcon handle
function SuuUI.Components.AuraIcon(props, parent)
    props = props or {}
    local T = SuuUI.Theme
    local pinned = props.size
    local size   = props.size or T:GetToken("sizeIcon") or 16

    -- Root frame: mouse-enabled so it receives enter/leave/click.
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:EnableMouse(true)

    -- OnSizeChanged registered BEFORE the host container adopts the frame.
    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    -- Host container: the only positioning mechanism inside this component.
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- Icon handle: border=true for the debuff-type coloured edge, trim defaults true
    -- to crop the bevel Blizzard bakes into its icon art.
    local iconComp = SuuUI.Components.Icon({
        icon        = props.icon,
        border      = true,
        borderColor = BORDER_TOKEN,
        trim        = props.trim ~= false,
    }, f)
    -- The icon's internal _fade must be false: the AuraIcon root fades the whole thing,
    -- and a nested fade would multiply (0.4^2 = 0.16).
    iconComp._fade = false
    box:Add(iconComp, { align = "stretch", valign = "stretch" })

    -- Apply the type colour immediately if provided.
    if props.typeColor then
        iconComp:SetBorderColor(props.typeColor)
    end

    -- Cooldown frame: a sanctioned Blizzard template exception (like Input's EditBox),
    -- because nothing else draws a radial sweep. Parented to the icon's frame so it
    -- sits above the art layers but below the text overlay. SetHideCountdownNumbers
    -- prevents its built-in number from fighting our own duration readout.
    -- Positioned by the host stack container (stretch is the stack default), not
    -- by SetAllPoints — SetAllPoints belongs only to the four layout strategies.
    local iconFrame = iconComp:GetFrame()
    local cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    cooldown:SetHideCountdownNumbers(true)
    -- Add to the root box so it fills the icon area, inset by the border width so the
    -- swipe stops at the art and leaves the border ring visible. _applyCooldownInset
    -- owns that number and re-derives it on a theme change.
    local cdProps = { inset = 0 }
    box:Add(cooldown, cdProps)

    -- Overlay frame for text: a child frame that draws ABOVE the cooldown's layers.
    -- A FontString parented to the root frame would sit behind the swipe because a child
    -- frame draws above its parent's layers. RaiseAbove is the only sanctioned z-order
    -- mechanism outside Core/UIRoot.lua. The overlay covers the whole icon so the texts
    -- can be positioned inside it with a stack container.
    local overlay = CreateFrame("Frame", nil, f)
    box:Add(overlay, { align = "stretch", valign = "stretch" })
    SuuUI.UIRoot:RaiseAbove(overlay, iconFrame, 2)

    local overlayBox = SuuUI.Layout:CreateContainer({ host = overlay, layout = "stack" })

    -- Stack count: bottom-right. Only shown when count > 1.
    local padXs = T:GetToken("spaceXxs") or 2
    local countText = SuuUI.Components.Text({
        text = "", size = "sm", color = "text",
    }, overlay)
    countText._fade = false
    overlayBox:Add(countText, {
        align  = "end",
        valign = "end",
        inset  = { right = padXs, bottom = padXs },
    })
    countText:Hide()

    -- Duration readout: centred on the icon. It is the reading a player scans a debuff for,
    -- so it takes the middle rather than an edge -- which also keeps it clear of the count in
    -- the bottom-right corner, where the two used to share the bottom row and collide.
    local durationText = SuuUI.Components.Text({
        text = "", size = "sm", color = "text",
    }, overlay)
    durationText._fade = false
    overlayBox:Add(durationText, {
        align  = "center",
        valign = "center",
    })
    durationText:Hide()

    -- Assemble handle
    local id = "auraicon_" .. tostring(f)
    handle = setmetatable({
        _f              = f,
        _box            = box,
        _iconComp       = iconComp,
        _cooldown       = cooldown,
        _cdProps        = cdProps,
        _overlay        = overlay,
        _overlayBox     = overlayBox,
        _countText      = countText,
        _durationText   = durationText,
        _eid            = id,
        _enabled        = true,
        _autoSize       = pinned == nil,
        _count          = props.count,
        _duration       = props.duration,
        _expirationTime = props.expirationTime,
        _showDuration   = props.showDuration ~= false,
        _typeColor      = props.typeColor,
        _timeLeft       = nil,
        _durColorOverride = false,
    }, AuraIconMeta)

    -- Blizzard scripts translated into signals: never escape this file.
    f:SetScript("OnEnter", function()
        if handle._enabled == false then return end
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    f:SetScript("OnLeave", function()
        if handle._enabled == false then return end
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)
    f:SetScript("OnMouseUp", function(_, btn)
        if handle._enabled == false then return end
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)

    -- Seed the count display
    handle:_updateCount()

    -- Seed the timer if provided at construction
    if props.duration and props.expirationTime then
        handle:SetTimer(props.duration, props.expirationTime)
    end

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
