local max, pairs = math.max, pairs

local S = SuuUI.UISignals

--- Signals specific to StatusBar.
SuuUI.Components.STATUSBAR_SIGNALS = {
    FILL_SETTLED = "statusbar.fill_settled",  -- Args: fraction (the painted value caught up)
}
local SB_SIGNALS = SuuUI.Components.STATUSBAR_SIGNALS

-- The three overlay text slots, and how each sits in the bar's box. Cross-axis placement
-- is the same for all three, so only the main axis differs — which is the whole of what
-- "left, centre, right" means to a layout strategy.
local TEXT_SLOTS = {
    left   = { align = "start",  justify = "LEFT" },
    center = { align = "center", justify = "CENTER" },
    right  = { align = "end",    justify = "RIGHT" },
}

local StatusBarMeta = {}
StatusBarMeta.__index = StatusBarMeta

---------------------------------------------------------------------------
-- Transition context
--
-- What a transition strategy is given. Deliberately not the bar handle: Set() is the
-- only write path, so a strategy cannot reach into the fill container, cannot move the
-- logical value, and cannot skip the pixel guard. See Animation/Transitions.lua.
---------------------------------------------------------------------------
local CtxMeta = {}
CtxMeta.__index = CtxMeta

--- Paints a fraction now. The only write path a strategy has.
-- @param v number  0..1, clamped
function CtxMeta:Set(v)
    self.owner:_paintFraction(v)
end

--- The currently painted fraction.
-- @return number
function CtxMeta:Get()
    return self.owner._display or 0
end

--- The current logical target fraction.
-- @return number
function CtxMeta:Target()
    return self.owner._pct or 0
end

--- Seconds for a full 0..1 sweep, from the bar's override or the animBarFill token.
-- @return number
function CtxMeta:Duration()
    return self.owner:_fillDuration()
end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------

--- How far the fill and the track sit inside the bar frame.
--- A bordered bar insets both by the border width so neither paints under the edge. A
--- borderless bar insets by nothing: there is no edge to avoid, and an inset there would
--- leave the track showing as a hairline ring around a full bar and make an empty bar a
--- pixel wider on every side than the fill that replaces it.
-- @return number
function StatusBarMeta:_inset()
    if not self._showBorder then return 0 end
    return SuuUI.Pixel.Line(SuuUI.Theme:GetToken("borderWidth") or 1)
end

--- The pixel width StackLayout will give the fill for a fraction.
-- Mirrors the strategy's own arithmetic rather than approximating it, because it is used
-- to decide whether a write can be skipped: a guard that disagreed with the layout by a
-- pixel would drop updates that were actually visible.
-- @param f number  Fraction 0..1
-- @return number
function StatusBarMeta:_fillPixels(f)
    local Pixel = SuuUI.Pixel
    local box = Pixel.Floor(max(0, self._f:GetWidth() or 0)) - Pixel.Snap(self:_inset()) * 2
    if box < 0 then box = 0 end
    return Pixel.Floor(max(0, box * f))
end

--- Restates the fill's inset on the host container. Border width is a token, so this has
--- to be re-stated on a theme change rather than fixed at construction. The fill's
--- position and size are the container's business; this only says how far in it sits.
function StatusBarMeta:_anchorFill()
    if not self._fillBox then return end
    self._fillBox:SetChildProps(self._fillFrame, {
        inset          = self:_inset(),
        align          = "start",
        valign         = "stretch",
        -- The painted fraction, not the target: restating geometry must never animate,
        -- and must never jump the fill to a value the transition has not reached.
        widthFraction  = self._display or 0,
    })
end

--- Recolours the bar fill and background.
function StatusBarMeta:_paint()
    local B = SuuUI.Backdrop
    B.SetBg(self._f, self._bgColor or "colorBgAlt")
    B.SetBorder(self._f, self._showBorder and (self._borderColor or "colorBorder") or false)
    local r, g, b, a = self._fillColor[1], self._fillColor[2], self._fillColor[3], self._fillColor[4] or 1
    self._bar:SetColorTexture(r, g, b, a)

    -- THE GHOST DERIVES FROM THE FILL *UNLESS* GIVEN A COLOUR OF ITS OWN.
    --
    -- Derivation is the default because it needs no token: a ghost reads as a paler version of whatever
    -- progress looks like on that bar.
    --
    -- But it is WRONG when the ghost means something the fill does not, and experience is exactly that
    -- case: in WoW blue IS the rested colour, so a blue-derived ghost on a blue fill tells the player
    -- they are rested whenever they have any progress at all. An explicit colour is used AS GIVEN,
    -- alpha included, so the theme controls it outright rather than having opacityBarGhost applied on
    -- top of a value the theme already chose.
    --
    -- (An earlier version of this comment argued derivation must be forced so one primitive could serve
    -- both watch bars. That was wrong: the reputation bar has no rested concept and never sets a
    -- secondary at all, so there was no second case to serve.)
    if self._secTex then
        local sc = self._secColor
        if sc then
            self._secTex:SetColorTexture(sc[1], sc[2], sc[3], sc[4] or 1)
        else
            local ga = a * (SuuUI.Theme:GetToken("opacityBarGhost") or 0.35)
            self._secTex:SetColorTexture(r, g, b, ga)
        end
    end
end

---------------------------------------------------------------------------
-- Value / display split
--
-- _value and _pct are the logical truth: what SetValue was told, and what fraction that
-- is. _display is what is painted. GetValue, GetPercent and VALUE_CHANGED all report the
-- logical value immediately, so a consumer never reads a number that is merely on its way
-- — only the pixels lag.
---------------------------------------------------------------------------

--- The fraction the current value/max represents.
-- @return number
function StatusBarMeta:_targetPercent()
    if self._max <= 0 then return 0 end
    local p = self._value / self._max
    if p < 0 then return 0 elseif p > 1 then return 1 end
    return p
end

--- Seconds for a full sweep of the fill.
-- @return number
function StatusBarMeta:_fillDuration()
    if self._duration then return self._duration end
    return SuuUI.Theme:GetToken("animBarFill") or 0
end

--- Sets the secondary (ghost) fraction, e.g. how far rested experience reaches.
--
-- CLAMPED TO AT LEAST THE MAIN FILL. A ghost that fell behind progress would be drawn entirely under
-- it and read as absent, which is indistinguishable from a bug -- so the floor is stated here rather
-- than left to every caller to remember.
-- @param f number|nil  0..1; nil or 0 hides it
function StatusBarMeta:SetSecondary(f)
    f = f or 0
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    self._secondary = f
    self:_paintSecondary()
end

--- The secondary fraction as last set.
-- @return number
function StatusBarMeta:GetSecondary()
    return self._secondary or 0
end

function StatusBarMeta:_paintSecondary()
    if not (self._fillBox and self._secFrame) then return end
    local f = self._secondary or 0
    -- Never behind the main fill -- see SetSecondary.
    local main = self._display or 0
    if f > 0 and f < main then f = main end

    -- Its own quantisation guard, same reasoning as the main fill's and its own cache.
    local px = self:_fillPixels(f)
    if px ~= self._secLastPx then
        self._secLastPx = px
        self._fillBox:SetChildFraction(self._secFrame, "width", f)
    end

    -- Hidden at zero rather than left as a zero-width frame: a zero-width child still costs the
    -- container a cell, and a hidden one is skipped.
    if f <= 0 or (self._secFrame:GetWidth() or 0) < 0.5 then
        self._secFrame:Hide()
    else
        self._secFrame:Show()
    end
end

--- Paints one fraction. Every write to the fill goes through here — the transition
--- strategies, the immediate paths, and the geometry restatements alike.
-- @param f number  0..1, clamped
function StatusBarMeta:_paintFraction(f)
    f = f or 0
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    local was = self._display
    self._display = f

    if self._fillBox then
        -- Quantisation guard. A strategy writes a continuous fraction, but the fill is
        -- floored onto the pixel grid, so a change too small to move it a whole pixel
        -- renders identically. Each skipped write is a whole container layout pass
        -- avoided, which is what keeps a screen full of bars affordable: a 2% energy tick
        -- on a 300-unit bar is 6 pixels of travel, not 17 frames' worth of layout.
        local px = self:_fillPixels(f)
        if px ~= self._lastPx then
            self._lastPx = px
            self._fillBox:SetChildFraction(self._fillFrame, "width", f)
            self:_syncFillVisibility()
            -- The ghost's floor is the main fill, so progress moving can push it -- re-asserted here
            -- rather than only when the caller sets it.
            self:_paintSecondary()
        end
    end

    -- Settled is defined here rather than left to each strategy, so every strategy
    -- reports it identically — including instant, which settles on the same call.
    if was ~= f and f == self._pct then
        S:Emit(self, SB_SIGNALS.FILL_SETTLED, f)
    end
end

--- Moves the target and lets the active transition chase it.
-- @param pct number  Target fraction
-- @param immediate bool  Skip the transition and paint now
function StatusBarMeta:_setTarget(pct, immediate)
    local from = self._display or 0
    self._pct = pct
    if immediate or not self._fillBox then
        self._transition.Cancel(self._tctx)
        self:_paintFraction(pct)
        return
    end
    if from == pct then
        -- Already there. Cancel anything in flight so a superseded transition cannot
        -- keep walking the fill away from a target it has already reached.
        self._transition.Cancel(self._tctx)
        return
    end
    self._transition.Apply(self._tctx, from, pct)
end

--- Abandons any transition in flight and paints the target immediately.
function StatusBarMeta:SnapToTarget()
    self._transition.Cancel(self._tctx)
    self:_paintFraction(self._pct or 0)
end

---------------------------------------------------------------------------
-- Transitions
---------------------------------------------------------------------------

--- Sets how the fill moves when the value changes.
-- Accepts a registered name ("instant", "smooth", "rate"), or an inline strategy table
-- for a bespoke transition that needs no registration:
--
--   bar:SetTransition({ Apply = function(ctx, from, to) ... ctx:Set(v) ... end })
--
-- Switching strategy is not a value change, so the fill snaps to the target rather than
-- animating the handover with the strategy that is being replaced.
-- @param spec string|table|nil  nil restores the registry default
function StatusBarMeta:SetTransition(spec)
    local nextStrategy = SuuUI.Anim.Transitions:Resolve(spec)
    if nextStrategy == self._transition then return end
    if self._transition then
        self._transition.Cancel(self._tctx)
        self._transition.Detach(self._tctx)
    end
    self._transition = nextStrategy
    -- A fresh scratch table: the previous strategy's animation handles are gone, and
    -- leaving them visible to the new one is how a stale tween gets revived.
    self._tctx.state = {}
    nextStrategy.Attach(self._tctx)
    self:_paintFraction(self._pct or 0)
end

--- Returns the active strategy's name.
-- @return string
function StatusBarMeta:GetTransition()
    return self._transition and self._transition.name or nil
end

--- Overrides the fill duration for this bar only. nil returns it to the animBarFill token.
-- @param seconds number|nil
function StatusBarMeta:SetTransitionDuration(seconds)
    self._duration = seconds
end

---------------------------------------------------------------------------
-- Fill visibility
---------------------------------------------------------------------------

--- Hides the fill when it rounds below half a pixel.
-- A sub-pixel fill renders as a sliver of colour pinned to the left edge, which reads as
-- a rendering artefact rather than an empty bar.
function StatusBarMeta:_syncFillVisibility()
    if not self._fillFrame then return end
    if (self._fillFrame:GetWidth() or 0) < 0.5 then
        self._fillFrame:Hide()
    else
        self._fillFrame:Show()
    end
end

---------------------------------------------------------------------------
-- Overlay text
--
-- Three readout slots inside the bar's own box. The bar is the right home for them: it
-- owns the box, the border inset that text has to clear, and the z-order — the fill lives
-- in a CHILD frame, so anything drawn in the bar's own layers would sit under it, and a
-- caller building its own overlay would have to reach past that frame to get above it.
--
-- Slots take plain strings and nothing else. What a number MEANS — current over max, a
-- percentage, an abbreviation — belongs to whoever owns the value, so no formatting and
-- no unit data reaches this file.
--
-- Built lazily. An extra frame and up to three font strings is not something a bar with
-- no text should pay for, and a raid's worth of frames is exactly where that would show.
---------------------------------------------------------------------------

--- How far a readout sits in from the bar's edge: past the border, then one space step.
--- Both are tokens, so a theme change moves it — which is why this is re-derived rather
--- than captured at construction.
-- @return number
function StatusBarMeta:_textInset()
    return self:_inset() + (SuuUI.Theme:GetToken("spaceXs") or 4)
end

-- Layout props for one slot. The inset applies on both sides for every slot: it is what
-- keeps a left readout off the edge, and shrinking the box symmetrically leaves a centred
-- one exactly where it was.
function StatusBarMeta:_slotProps(slot)
    local pad = self:_textInset()
    return {
        align  = TEXT_SLOTS[slot].align,
        valign = "center",
        inset  = { left = pad, right = pad },
    }
end

function StatusBarMeta:_ensureTextBox()
    if self._textBox then return self._textBox end
    -- Placed by the bar's own stack box rather than by a container of its own, so the
    -- overlay tracks the bar's geometry in the very pass that moves the fill. A separate
    -- parent-resize tracker would run after the bar has already emitted SIZE_CHANGED, and
    -- the two would disagree for a frame.
    local overlay = CreateFrame("Frame", nil, self._f)
    self._fillBox:Add(overlay)
    SuuUI.UIRoot:RaiseAbove(overlay, self._fillFrame, 1)
    self._textOverlay = overlay
    self._textBox = SuuUI.Layout:CreateContainer({ host = overlay, layout = "stack" })
    return self._textBox
end

function StatusBarMeta:_ensureText(slot)
    local el = self._texts[slot]
    if el then return el end
    local box = self:_ensureTextBox()
    el = SuuUI.Components.Text({
        text    = "",
        size    = self._textSize,
        color   = "text",
        justify = TEXT_SLOTS[slot].justify,
    }, self._textOverlay)
    self._texts[slot] = el
    box:Add(el, self:_slotProps(slot))
    return el
end

--- Sets the readout in one of the bar's three overlay slots.
--
-- Passing nil or "" clears the slot, so a caller switching a readout off writes the same
-- way it writes a value — there is no separate clear call to forget.
-- @param slot string  "left" | "center" | "right"
-- @param text string|nil
function StatusBarMeta:SetText(slot, text)
    assert(TEXT_SLOTS[slot],
        "SuuUI StatusBar: SetText slot must be \"left\", \"center\" or \"right\"")
    if text == "" then text = nil end
    -- Guarded on the stored value, because a readout is usually written on every game
    -- event and usually says the same thing: a percentage stays 51% for most of the ticks
    -- that produce it. Each skipped write is a re-measure and a container pass avoided.
    if self._textVals[slot] == text then return end
    self._textVals[slot] = text
    -- Nothing built and nothing to show: there is no element to clear.
    if not text and not self._texts[slot] then return end

    local el = self:_ensureText(slot)
    el:SetText(text or "")
    if text then el:Show() else el:Hide() end
    -- Text reports SIZE_CHANGED on a HEIGHT change only — it lets the layout own its
    -- width — so a string that changes width at the same height leaves the slot at the
    -- width the previous pass pinned, and the client clips rather than overflows.
    self._textBox:Layout()
end

--- Returns the readout in one slot, or nil when the slot is empty.
-- @param slot string  "left" | "center" | "right"
-- @return string|nil
function StatusBarMeta:GetText(slot)
    assert(TEXT_SLOTS[slot],
        "SuuUI StatusBar: GetText slot must be \"left\", \"center\" or \"right\"")
    return self._textVals[slot]
end

--- Sets which font-size step the readouts render at.
--
-- A token KEY, not a pixel size: the number still comes from the theme, so a bar switched
-- to "lg" follows a user's edit of `fontSizeLg`. That is what lets a plugin expose the step
-- as a setting without any of them storing a font size of their own.
--
-- Applies to slots already built AND to any built later, so the order a caller sets the
-- size and writes a readout in does not matter.
-- @param size string  "sm" | "md" | "lg" | "xl"
function StatusBarMeta:SetTextSize(size)
    if not size or self._textSize == size then return end
    self._textSize = size
    for _, el in pairs(self._texts) do
        el:SetFontSize(size)
    end
    -- A taller step needs a wider box, and Text only reports a height change — so nothing
    -- else re-measures the slot's width and the client would clip it.
    if self._textBox then self._textBox:Layout() end
end

--- Returns the font-size step the readouts render at.
-- @return string
function StatusBarMeta:GetTextSize()
    return self._textSize
end

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------

--- Restyles for theme changes. A restyle is never a value change: the fill keeps the
--- fraction it is currently painting, and any transition in flight continues undisturbed.
function StatusBarMeta:ApplyTheme()
    -- The inset and the frame width both feed the pixel guard, and a theme change can
    -- move the border width, so the cached pixel count is no longer comparable.
    self._lastPx = nil
    SuuUI.Backdrop.Apply(self._f, {
        bg     = self._bgColor or "colorBgAlt",
        border = self._showBorder and (self._borderColor or "colorBorder") or false,
        inset  = self:_inset(),
    })
    self:_anchorFill()
    self:_paint()
    self:_paintFraction(self._display or 0)
    -- Readouts are applied explicitly: the event bus dispatches newest-first, so a child
    -- handle's own subscription may not have run yet and the slot would be measured at the
    -- previous theme's font. Their insets move too — both the border width and the space
    -- step behind them are tokens.
    for slot, el in pairs(self._texts) do
        el:ApplyTheme()
        self._textBox:SetChildProps(el, self:_slotProps(slot))
    end
end

---------------------------------------------------------------------------
-- Public value API
---------------------------------------------------------------------------

--- Sets the current value. Clamps to [0, max].
-- @param v number
-- @param opts table|nil  { immediate = true } to skip the transition
function StatusBarMeta:SetValue(v, opts)
    v = v or 0
    if v < 0 then v = 0 end
    if v > self._max then v = self._max end
    local old = self._value
    self._value = v
    self:_setTarget(self:_targetPercent(), opts and opts.immediate)
    if old ~= v then
        S:Emit(self, S.SIGNALS.VALUE_CHANGED, v, old)
    end
end

--- Sets the maximum value.
-- @param m number
-- @param opts table|nil  { immediate = true } to skip the transition
function StatusBarMeta:SetMax(m, opts)
    m = m or 1
    if m < 0 then m = 0 end
    self._max = m
    if self._value > m then self._value = m end
    self:_setTarget(self:_targetPercent(), opts and opts.immediate)
end

--- Returns the current value.
-- @return number
function StatusBarMeta:GetValue()
    return self._value
end

--- Returns the current max.
-- @return number
function StatusBarMeta:GetMax()
    return self._max
end

--- Returns the target fill percentage (0..1) — what the value implies, not what is drawn.
-- @return number
function StatusBarMeta:GetPercent()
    return self._pct
end

--- Returns the painted fill percentage (0..1), which lags the target mid-transition.
-- @return number
function StatusBarMeta:GetDisplayPercent()
    return self._display
end

--- Returns whether the fill is still catching up with the value.
-- @return bool
function StatusBarMeta:IsTransitioning()
    return self._display ~= self._pct
end

--- Sets the fill colour as a literal {r,g,b,a} table.
-- @param color table  {r, g, b, a}
function StatusBarMeta:SetFillColor(color)
    self._fillColor = color or {1, 1, 1, 1}
    self:_paint()
end

--- Sets the secondary (ghost) fill's own colour, or clears it back to deriving from the fill.
-- Pass nil to go back to the derived paler-fill behaviour. The colour is used exactly as given,
-- including its alpha -- opacityBarGhost is NOT applied on top, because a theme that names this
-- colour has already decided how present it should be.
-- @param color table|nil  {r, g, b, a}
function StatusBarMeta:SetSecondaryColor(color)
    self._secColor = color
    self:_paint()
end

--- Sets the background colour token or literal.
-- @param color string|table|false
function StatusBarMeta:SetBgColor(color)
    self._bgColor = color
    self:_paint()
end

--- Sets the border colour token or literal, without changing whether a border is shown.
-- For a bar that has to say something about its own state through its edge — a cast bar
-- marking an uninterruptible spell — rather than through its fill, which the player owns.
-- @param color string|table|false
function StatusBarMeta:SetBorderColor(color)
    if self._borderColor == color then return end
    self._borderColor = color
    self:_paint()
end

--- Shows or hides the border after construction.
--
-- Not just a repaint: the border decides how far the track and fill sit inside the frame
-- (see _inset), so toggling it moves real geometry. ApplyTheme is the one path that
-- restates all of it — backdrop, inset, fill anchor and the pixel guard — so it is reused
-- here rather than duplicated. No-ops when the state is unchanged, which keeps a caller
-- free to assert the current value on every paint.
-- @param on bool
function StatusBarMeta:SetBorderShown(on)
    on = on and true or false
    if self._showBorder == on then return end
    self._showBorder = on
    self:ApplyTheme()
end

--- Returns whether the border is currently drawn.
-- @return bool
function StatusBarMeta:IsBorderShown()
    return self._showBorder and true or false
end

function StatusBarMeta:Destroy()
    -- Before anything is torn down: a transition left running keeps writing a fraction
    -- into a destroyed container on the shared ticker.
    if self._transition then
        self._transition.Cancel(self._tctx)
        self._transition.Detach(self._tctx)
    end
    SuuUI.Anim:CancelAll(self)
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    for slot, el in pairs(self._texts) do
        el:Destroy()
        self._texts[slot] = nil
    end
    if self._textBox then self._textBox:Destroy(); self._textBox = nil end
    if self._barBox  then self._barBox:Destroy();  self._barBox  = nil end
    if self._fillBox then self._fillBox:Destroy(); self._fillBox = nil end
    self._f:Hide()
end

-- StatusBar deliberately does NOT install InstallEnable (and has no SetEnabled).
-- It is a display-only data visualisation that takes no mouse input and is never a
-- settings-page control that Dependency.Bind would grey. It always sits inside a
-- composite (a unit frame, a cast bar) whose OUTER handle owns the enabled state and
-- fades — frame alpha cascades, so a second fade here would multiply (0.40 * 0.40 =
-- 0.16) and render the bar nearly invisible. An InstallEnable with _fade = false
-- would install a SetEnabled that does nothing visible (no fade, no mouse to drop),
-- which is precisely the no-op stub the standing rule forbids: Dependency.Bind's
-- guard (`if target.SetEnabled`) would pass while nothing is actually greyed.
SuuUI.Components.InstallBase(StatusBarMeta, "_f")

local WHITE = "Interface\\Buttons\\WHITE8x8"

--- Creates a status bar (health/mana/energy/rage bar).
-- @param props table  { w, h, value, max, fillColor, bgColor, border, borderColor,
--                       transition, transitionDuration, textSize }
--   fillColor: {r,g,b,a} literal colour for the bar fill
--   bgColor: token key or literal for the background (default "colorBgAlt")
--   border: bool whether to show border (default true)
--   borderColor: token key or literal for the border (default "colorBorder")
--   transition: strategy name or inline table (default: the registry default)
--   transitionDuration: seconds for a full sweep (default: the animBarFill token)
--   textSize: font size key for the overlay readouts ("sm".."xl", default "sm")
-- @param parent frame
-- @return table  StatusBar handle. Emits VALUE_CHANGED, SIZE_CHANGED, FILL_SETTLED.
function SuuUI.Components.StatusBar(props, parent)
    props = props or {}
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if props.w then f:SetWidth(props.w) end
    if props.h then f:SetHeight(props.h) end

    -- Fill frame: a child frame holding the fill texture. Both are placed by host
    -- containers below, never by hand — the fill is a fractional child of the track.
    -- THE SECONDARY FILL, behind the main one. Rested experience is the case it exists for: a second
    -- fraction that is always at least the first, drawn in a dimmer tone so the player reads "this is
    -- how far the rested bonus reaches" without it competing with actual progress.
    --
    -- A second fractional child rather than a stacked second bar. A stacked pair would need its own
    -- alignment, its own resize handling and its own theme plumbing, all kept in step with the first --
    -- three things to get wrong instead of none.
    local secondaryFrame = CreateFrame("Frame", nil, f)
    local secondaryTex = secondaryFrame:CreateTexture(nil, "ARTWORK")
    secondaryTex:SetTexture(WHITE)
    secondaryTex:SetAllPoints(secondaryFrame)
    secondaryFrame:Hide()

    local fillFrame = CreateFrame("Frame", nil, f)

    local bar = fillFrame:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(WHITE)

    local id = "statusbar_" .. tostring(f)
    local handle = setmetatable({
        _f          = f,
        _fillFrame  = fillFrame,
        _secFrame   = secondaryFrame,
        _secTex     = secondaryTex,
        -- Its OWN pixel cache. Sharing `_lastPx` would make a sub-pixel change to one fill invalidate
        -- the other's guard, and the whole point of that guard is that a change too small to move a
        -- pixel costs no layout pass -- a spec pins exactly that.
        _secLastPx  = nil,
        _secondary  = 0,
        _bar        = bar,
        _eid        = id,
        _value      = props.value or 0,
        _max        = props.max or 1,
        _fillColor  = props.fillColor or {1, 1, 1, 1},
        _bgColor    = props.bgColor or "colorBgAlt",
        _showBorder = props.border ~= false,
        _borderColor = props.borderColor or "colorBorder",
        _duration   = props.transitionDuration,
        -- Overlay readouts. The tables are always here so SetText can read a slot before
        -- anything is built; the elements themselves are not.
        _textSize   = props.textSize or "sm",
        _texts      = {},
        _textVals   = {},
    }, StatusBarMeta)

    -- A new bar starts settled at its initial value rather than animating up from empty:
    -- construction is not a value change, and a raid frame filling in on login reads as
    -- a glitch rather than as feedback.
    handle._pct     = handle:_targetPercent()
    handle._display = handle._pct

    handle._tctx = setmetatable({ owner = handle, state = {} }, CtxMeta)
    handle._transition = SuuUI.Anim.Transitions:Resolve(props.transition)
    handle._transition.Attach(handle._tctx)

    -- The track hosts the fill; the fill hosts its texture. Two adopted containers, no
    -- extra frames, and not one point set by this component.
    handle._fillBox = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
    -- Added BEFORE the main fill, so the main fill draws over it. In a stack container the later child
    -- is the higher one, which is the only ordering that makes a ghost fill read as a backdrop to
    -- progress rather than a stripe on top of it.
    handle._fillBox:Add(secondaryFrame, {
        inset         = handle:_inset(),
        align         = "start",
        valign        = "stretch",
        widthFraction = 0,
    })
    handle._fillBox:Add(fillFrame, {
        inset         = handle:_inset(),
        align         = "start",
        valign        = "stretch",
        widthFraction = handle._display,
    })
    handle._barBox = SuuUI.Layout:CreateContainer({ host = fillFrame, layout = "stack" })
    handle._barBox:Add(bar)

    -- Chain the container's own resize handler rather than replacing it: the container
    -- must re-flow the fill first, so the visibility check below reads a fresh width.
    local prevSize = f:GetScript("OnSizeChanged")
    f:SetScript("OnSizeChanged", function(self_, w, h)
        if prevSize then prevSize(self_, w, h) end
        -- The pixel guard caches a pixel count against the old width, and a skipped
        -- write leaves the container holding a fraction up to one pixel stale — which
        -- resolves to a different pixel at a new width. Re-assert the true fraction.
        -- Guarded against re-entry: this runs inside a resize, and repainting lays out.
        if not handle._inResize then
            handle._inResize = true
            handle._lastPx = nil
            -- Mirrors the main cache above. Mutation testing could NOT construct a case where
            -- removing this changes the outcome -- a width change almost always moves the ghost's
            -- pixel count too, so the guard re-writes anyway. Kept for symmetry rather than deleted:
            -- the two caches are the same mechanism, and an asymmetry here would read as an oversight
            -- and get "fixed" in one direction or the other.
            handle._secLastPx = nil
            handle:_paintFraction(handle._display or 0)
            handle._inResize = false
        end
        handle:_syncFillVisibility()
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    -- A bar hidden mid-transition would come back showing a fraction from before it was
    -- hidden. Nothing on screen can be mid-motion while invisible, so hiding settles the
    -- fill and showing re-asserts it against the current geometry.
    --
    -- Both chain: the host container installs its own OnShow to re-layout, and replacing
    -- it instead of chaining would silently break the container's re-flow on show.
    local prevShow = f:GetScript("OnShow")
    f:SetScript("OnShow", function(self_)
        if prevShow then prevShow(self_) end
        handle._lastPx = nil
        handle:SnapToTarget()
        S:Emit(handle, S.SIGNALS.VISIBILITY_CHANGED, true)
    end)
    local prevHide = f:GetScript("OnHide")
    f:SetScript("OnHide", function(self_)
        if prevHide then prevHide(self_) end
        handle:SnapToTarget()
        S:Emit(handle, S.SIGNALS.VISIBILITY_CHANGED, false)
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
