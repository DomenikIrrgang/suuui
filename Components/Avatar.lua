-- One entry on the conversation rail: a class-coloured disc carrying an initial, an optional
-- unread count, and a name that brightens when it is the active entry.
--
-- Composed from Backdrop.Circle (a backdrop cannot be rounded -- its corners are its texture's
-- corners) plus Components.Text. The disc's colour is a LITERAL far more often than a token,
-- because a class colour is a game fact from SuuUI.Game rather than a theme decision.
local S = SuuUI.UISignals

local AvatarMeta = {}
AvatarMeta.__index = AvatarMeta

--- Sets the name. The initial is derived from it unless one was given explicitly.
function AvatarMeta:SetLabel(text)
    self._labelStr = text or ""
    if self._labelText then self._labelText:SetText(self._labelStr) end
    if not self._initialFixed then
        self._initialText:SetText((self._labelStr:sub(1, 1)):upper())
    end
    self:_autosize()
end

function AvatarMeta:GetLabel() return self._labelStr end

--- Pins the glyph on the disc, for an entry whose first letter is not what it should show
--- (a channel showing "#" rather than "G" for General).
function AvatarMeta:SetInitial(glyph)
    self._initialFixed = glyph ~= nil
    self._initialText:SetText(glyph or (self._labelStr:sub(1, 1)):upper())
    -- Same reason as the badge: a glyph swap changes the width and not the height, so nothing
    -- re-flows the disc on its own. Latent today only because construction lays out AFTER setting
    -- the initial -- a later call would leave the glyph at its previous width.
    self._discBox:Layout()
end

--- @param color table|string  a literal {r,g,b,a} (a class colour) or a token key
function AvatarMeta:SetColor(color)
    self._color = color
    self:_paint()
end

--- The unread count. nil OR 0 hides the badge: the client reports 0 for plenty of things and a
--- "0" badge on every entry is noise, which is the same rule AuraIcon's stack count follows.
---
--- Counts are for PEOPLE, not channels -- a guild count of 200 means nothing. The caller decides
--- which entries get one; this only renders what it is handed.
function AvatarMeta:SetCount(n)
    self._count = (type(n) == "number" and n > 0) and n or nil
    self:_renderCount()
end

function AvatarMeta:GetCount() return self._count end

--- Which entry the rail is currently showing. Drives the LABEL's colour rather than the disc's
--- alpha: a dimmed class colour reads as a different class, and muted-to-full is the cue the
--- rest of this UI already uses for "you are here".
function AvatarMeta:SetActive(on)
    self._active = on and true or false
    self:_paint()
end

function AvatarMeta:IsActive() return self._active == true end

--- Shows or hides the name beside the disc.
---
--- The rail is collapsed to discs at rest and widens to names on hover, which is one widget with
--- its label hidden rather than two forms -- flow skips a hidden child, so the row shrinks to the
--- disc on its own.
function AvatarMeta:SetShowLabel(on)
    if not self._labelText then return end
    if on then self._labelText:Show() else self._labelText:Hide() end
    self._box:Layout()
    self:_autosize()
end

function AvatarMeta:IsShowingLabel()
    return self._labelText ~= nil and self._labelText:IsShown() == true
end

local function resolve(color)
    if type(color) == "string" then return SuuUI.Theme:GetToken(color) end
    if type(color) == "table" then return color end
    return SuuUI.Theme:GetToken("colorTextMuted")
end

--- The box an unread count needs: line height plus padding, widened for a multi-digit count.
---
--- Height comes from the LINE HEIGHT, never the point size. `GetFontSize("sm")` is 11 while an 11px
--- line occupies about 13, so a badge sized from the point size is a box at exactly the metric --
--- which this client renders as a CLIP, and the digit ends up drawn outside the badge rather than in
--- it. Width grows with the text because the badge is a Pill: a square one fits a single digit at
--- best, and "12" is wider than it is tall at any legible size.
---
--- Derived from tokens on every call rather than cached, so a font-token edit re-measures.
local function badgeMetrics(text)
    local T = SuuUI.Theme
    local font = SuuUI.Fonts:Path(T:GetToken("fontFamilyMain"))
    local pad  = T:GetToken("spaceXxs") or 2
    local tw, th = SuuUI.TextMetrics.Box(text or "0", font, T:GetFontSize("sm"))
    local h = SuuUI.Pixel.Ceil((th or 13) + pad * 2)
    local w = SuuUI.Pixel.Ceil((tw or 0) + pad * 2)
    if w < h then w = h end
    return w, h
end

function AvatarMeta:_renderCount()
    if not self._count then
        self._badge:Hide()
        return
    end
    self._badge:Show()
    local text = tostring(self._count)
    self._badgeText:SetText(text)
    -- REQUIRED, not defensive. `Text` emits SIZE_CHANGED on a HEIGHT change only -- it owns its
    -- height and lets the layout assign its width -- so a count going from "" to "2" changes the
    -- width with no signal behind it, the container never re-flows, and the glyph keeps the
    -- zero-width box it was laid out with while empty. That is why the number drew outside the
    -- badge instead of in it. `Components/Divider.lua` carries the same call for the same reason,
    -- and its spec fails without it.
    self._badgeBox:Layout()
    -- Re-anchored rather than only resized: the anchor descriptor carries the box, so a width that
    -- changed with the digit count has to be restated there or the layout keeps the old one.
    local w, h = badgeMetrics(text)
    self._anchorBox:SetChildAnchor(self._badge, {
        point = "TOPRIGHT", relativePoint = "TOPRIGHT",
        -- Offset OUTWARD, so the badge hangs off the disc's corner instead of covering the initial
        -- the disc exists to show. Scaled to the badge, not the disc, so the overhang stays constant
        -- relative to the thing being offset.
        x = h * 0.4, y = h * 0.3,
        width = w, height = h,
    })
end

function AvatarMeta:_paint()
    local c = resolve(self._color) or { 1, 1, 1, 1 }
    -- An INACTIVE disc is dimmed, which the concept states outright (`.rw.dim .av {opacity:.5}`).
    -- It is the rail's primary "you are not here" cue: the label colour alone is too quiet at
    -- 11px over the game world, and the 2px marker is the *active* cue rather than its inverse.
    local idle = SuuUI.Theme:GetToken("opacityRailIdle") or 0.5
    self._disc:SetBg({ c[1], c[2], c[3], self._active and 1 or idle })
    -- The glyph sits ON a saturated class colour, so it takes the darkest neutral rather than
    -- the text token -- there is no tier-2 "text on a coloured surface" semantic, and
    -- colorText on Rogue yellow is illegible.
    local ink = SuuUI.Theme:GetToken("colorGray950") or { 0, 0, 0, 1 }
    self._initialText:SetColor({ ink[1], ink[2], ink[3], 1 })
    if self._labelText then
        self._labelText:SetColor(self._active and "text" or "muted")
    end
    local accent = SuuUI.Theme:GetToken("colorAccent") or { 0.3, 0.6, 1, 1 }
    -- The marker is the ACTIVE cue, transparent at rest so an inactive row reads as one shape and
    -- only the active one grows an edge. The concept's `.rw.on .mk`.
    if self._marker then
        if self._active then
            self._marker:SetVertexColor(accent[1], accent[2], accent[3], 1)
        else
            self._marker:SetVertexColor(0, 0, 0, 0)
        end
    end
    self._badgePill:SetBg({ accent[1], accent[2], accent[3], 1 })
    self._badgeText:SetColor({ ink[1], ink[2], ink[3], 1 })
end

-- A host container ADOPTS a frame and sizes nothing -- only the self-created branch anchors and
-- sets a width. So the row's own width has to be stated here, or the label overflows a frame
-- frozen at the disc's size and the collapsed and expanded forms measure identically.
function AvatarMeta:_autosize()
    local T = SuuUI.Theme
    local gap = T:GetToken("spaceXs") or 4
    -- The marker sits left of the disc and is always present, so its column is always reserved --
    -- otherwise every row would shift sideways by 2 units when it became the active one.
    local w, h = SuuUI.Pixel.Line(2) + gap + self._size, self._size
    -- Measured from the label's SHOWN state rather than its existence: the label is always created
    -- now, so testing existence made the collapsed and expanded forms measure identically.
    if self._labelText and self._labelText:IsShown() then
        local lw = SuuUI.TextMetrics.Box(self._labelStr,
            SuuUI.Fonts:Path(T:GetToken("fontFamilyMain")), T:GetFontSize("md"))
        w = w + gap + lw
        h = math.max(h, T:GetControlHeight("sizeControlSm", "md"))
    end
    w, h = SuuUI.Pixel.Ceil(w), SuuUI.Pixel.Ceil(h)
    if math.abs((self._f:GetWidth() or 0) - w) > 0.5
        or math.abs((self._f:GetHeight() or 0) - h) > 0.5 then
        self._f:SetSize(w, h)
    end
end

function AvatarMeta:ApplyTheme()
    self._initialText:ApplyTheme()
    self._badgeText:ApplyTheme()
    if self._labelText then self._labelText:ApplyTheme() end
    -- Circle exposes SetBg and Destroy only -- no Refresh, because a disc's geometry follows its
    -- frame and carries no border width to re-derive. Pill does have one.
    self._badgePill:Refresh()
    -- Re-measured, not just restyled: the badge's box comes from the count's line height, so a
    -- fontSize* edit changes the size it needs and nothing else would notice.
    self:_renderCount()
    self:_paint()
    self:_autosize()
end

function AvatarMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._initialText:Destroy()
    self._badgeText:Destroy()
    if self._labelText then self._labelText:Destroy() end
    self._disc:Destroy()
    self._badgePill:Destroy()
    self._box:Destroy()
    self._discBox:Destroy()
    self._badgeBox:Destroy()
    self._f:Hide()
end

SuuUI.Components.InstallBase(AvatarMeta, "_f")
SuuUI.Components.InstallEnable(AvatarMeta, "_f")

--- Creates one conversation-rail entry.
-- Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, SIZE_CHANGED (w, h).
-- @param props table   { label, initial, color, count, size, active, showLabel }
-- @param parent frame
-- @return table  Avatar handle
function SuuUI.Components.Avatar(props, parent)
    props = props or {}
    local T = SuuUI.Theme
    local size = props.size or T:GetToken("sizeControlSm") or 18

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:EnableMouse(true)

    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    -- The row: disc, then the name. A horizontal flow so the collapsed form (disc only) and the
    -- expanded form (disc + name) are the same widget with the label hidden, rather than two.
    local box = SuuUI.Layout:CreateContainer({
        host = f, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })

    -- The 2px active MARKER, left of the disc. The concept's `.mk`: transparent at rest, accent on
    -- the active row. It is the row's primary "you are here" cue and the disc's dimming is the
    -- inverse cue -- two channels, because one alone is ambiguous at 18px over the game world.
    --
    -- 14 units tall against an 18 disc in the concept, which is `size - spaceXs` rather than a
    -- second constant, so it tracks the disc.
    local markerFrame = CreateFrame("Frame", nil, f)
    local markerTex = markerFrame:CreateTexture(nil, "ARTWORK")
    -- WHITE, then TINTED with SetVertexColor -- the same channel every other surface here uses.
    -- SetColorTexture replaces the texture instead of tinting it, and reads back differently.
    markerTex:SetColorTexture(1, 1, 1, 1)
    local markerBox = SuuUI.Layout:CreateContainer({ host = markerFrame, layout = "stack" })
    markerBox:Add(markerTex)
    box:Add(markerFrame, {
        width = SuuUI.Pixel.Line(2), height = size - (T:GetToken("spaceXs") or 4),
        align = "center",
    })

    -- The disc is its own frame so the circle mask has a square box to fill; masking the row
    -- frame would draw an ellipse once a label widened it.
    local discFrame = CreateFrame("Frame", nil, f)
    discFrame:SetSize(size, size)
    local disc = SuuUI.Backdrop.Circle(discFrame, { bg = false })
    local discBox = SuuUI.Layout:CreateContainer({ host = discFrame, layout = "stack" })
    -- The glyph step follows the DIAMETER. Pinned at "sm" it shipped an 11px letter in whatever
    -- circle the owner asked for, so growing the disc bought no legibility at all -- the reason the
    -- rail was unreadable at 18. Steps rather than a ratio, because the font sizes are tokens the
    -- user edits and a computed pixel size would ignore that.
    local initialStep = "sm"
    if size >= 34 then
        initialStep = "xl"
    elseif size >= 28 then
        initialStep = "lg"
    elseif size >= 22 then
        initialStep = "md"
    end
    local initialText = SuuUI.Components.Text({
        text = "", size = initialStep, justify = "CENTER",
    }, discFrame)
    discBox:Add(initialText, { align = "center", valign = "center" })
    box:Add(discFrame, { width = size, height = size })

    local labelText
    -- ALWAYS created, and hidden when collapsed rather than absent. Flow skips a hidden child
    -- entirely, so hiding the label collapses the row to the disc without a second widget -- and
    -- the rail's hover expansion needs to toggle this at runtime, which a construction-time branch
    -- could not do.
    -- shadow: the expanded rail OVERLAYS the log rather than pushing it, so the name is read
    -- against chat text and terrain. The concept gives `.lbl` a text-shadow for this.
    labelText = SuuUI.Components.Text({ text = props.label or "", size = "md",
                                        shadow = true }, f)
    box:Add(labelText, { width = "auto" })
    if props.showLabel == false then labelText:Hide() end

    -- The unread badge, parented to the DISC frame so it rides the disc rather than the row --
    -- otherwise it would drift sideways when the label appears.
    local badge = CreateFrame("Frame", nil, discFrame)
    local badgePill = SuuUI.Backdrop.Pill(badge, { bg = false, border = false })
    local badgeBox = SuuUI.Layout:CreateContainer({ host = badge, layout = "stack" })
    local badgeText = SuuUI.Components.Text({ text = "", size = "sm", justify = "CENTER" }, badge)
    badgeBox:Add(badgeText, { align = "center", valign = "center" })
    -- Sized from the COUNT's own metrics, not from the disc. A badge proportional to the disc was
    -- tried and is wrong in both directions: on an 18-unit disc it eclipsed the initial entirely,
    -- and at 45% of a 30-unit disc it was too short for its own digit. What a badge must fit is its
    -- text; where it sits relative to the disc is the anchor's job, not the size's.
    local badgeW, badgeH = badgeMetrics("0")
    badge:SetSize(badgeW, badgeH)
    local anchorBox = SuuUI.Layout:CreateContainer({ host = discFrame, layout = "anchor" })
    anchorBox:Add(badge, { anchor = {
        point = "TOPRIGHT", relativePoint = "TOPRIGHT",
        x = badgeH * 0.4, y = badgeH * 0.3,
        width = badgeW, height = badgeH,
    } })
    badge:Hide()

    local id = "avatar_" .. tostring(f)
    handle = setmetatable({
        _f = f, _box = box, _eid = id,
        _discFrame = discFrame, _disc = disc, _discBox = discBox,
        _marker = markerTex, _markerFrame = markerFrame, _markerBox = markerBox,
        _initialText = initialText,
        _labelText = labelText,
        _badge = badge, _badgePill = badgePill, _badgeText = badgeText,
        _badgeBox = badgeBox, _anchorBox = anchorBox,
        _labelStr = props.label or "",
        _color = props.color,
        _size = size,
        _active = props.active and true or false,
        _enabled = true,
    }, AvatarMeta)

    f:SetScript("OnMouseUp", function(_, button)
        if handle._enabled == false then return end
        S:Emit(handle, S.SIGNALS.CLICKED, button or "LeftButton")
    end)
    f:SetScript("OnEnter", function() S:Emit(handle, S.SIGNALS.MOUSE_ENTER) end)
    f:SetScript("OnLeave", function() S:Emit(handle, S.SIGNALS.MOUSE_LEAVE) end)

    handle:SetLabel(props.label or "")
    if props.initial then handle:SetInitial(props.initial) end
    handle:SetCount(props.count)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
