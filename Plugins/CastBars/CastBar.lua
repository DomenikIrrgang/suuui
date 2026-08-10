-- CastBars plugin: the reusable cast bar widget.
--
-- One implementation serves every unit. A unit differs only by its config — which unit
-- token to read, which settings prefix its keys carry, whether it is attached — so nothing
-- about the player is baked in here and target/focus need no new widget code.
--
-- Layout: an optional square icon beside a bar, with the spell name and the cast time
-- overlaid inside the bar (name left, time right).
local C = SuuUI.Components
local S = SuuUI.UISignals
local T = SuuUI.Theme

local format, floor, abs = string.format, math.floor, math.abs
local type, ipairs = type, ipairs

-- Overlay text sits inside the bar rather than above it, so it takes the small step: at
-- the medium step it crowds a bar only as tall as its own line height.
local TEXT_SIZE = "sm"

-- Shown while edit mode is on and nothing is casting, so an attached bar shows the band it
-- occupies and a detached one has something to look at while being dragged. The question
-- mark is a client asset, and a placeholder's fill level is not a design decision any
-- theme would want to make — neither belongs in a token.
local PREVIEW_ICON     = "Interface\\Icons\\INV_Misc_QuestionMark"
local PREVIEW_FRACTION = 0.6
local PREVIEW_TOTAL    = 2.5

-- The bar's own motion comes from the cast timer, so its value transitions are off: a
-- second smoothing pass on top of a linear tween makes the fill lag the spell.
local BAR_TRANSITION = "instant"

-- Settings this widget re-derives from, grouped by what a change actually costs. Anchor
-- mode is deliberately absent: it decides which parent the widget lives under, which is
-- the plugin's business, not the widget's.
local LAYOUT_KEYS = { "height", "width", "show_icon", "show_name", "show_time", "icon_position" }
-- Repaint, not relayout — except show_shield, which moves the bar's inset by a pixel and
-- therefore belongs with the paint pass that applies it rather than a layout pass.
local PAINT_KEYS  = { "cast_color", "channel_color", "school_color", "show_shield" }
local FORMAT_KEYS = { "time_format" }

-- The uninterruptible outline's colour. A theme token rather than a setting: it is a fixed
-- piece of the design language, and the whole point of an outline cue is that it stays
-- readable whatever colour the player gives the fill.
local SHIELD_COLOR = "colorShield"

-- How long a SPELL_INTERRUPT log line and UNIT_SPELLCAST_INTERRUPTED may be apart and
-- still describe the same event. A correlation window between two client events, not a
-- visual value, so it is a structural constant rather than a token.
local INTERRUPT_WINDOW = 0.5

-- Cast time readouts. Each returns the string to display AND a quantised token that
-- changes only when the string would: the tween applies every frame, and rebuilding a
-- string sixty times a second to paint the same glyphs is what the performance rules
-- forbid. The token is the guard, not an optimisation bolted on afterwards.
local TIME_FORMATS = {
    remaining = function(elapsed, total)
        local r = total - elapsed
        if r < 0 then r = 0 end
        return format("%.1f", r), floor(r * 10)
    end,
    elapsed = function(elapsed)
        return format("%.1f", elapsed), floor(elapsed * 10)
    end,
    both = function(elapsed, total)
        return format("%.1f / %.1f", elapsed, total), floor(elapsed * 10)
    end,
    percent = function(elapsed, total)
        local p = total > 0 and floor(elapsed / total * 100) or 0
        if p > 100 then p = 100 end
        return format("%d%%", p), p
    end,
}

local DEFAULT_FORMAT = "remaining"

---------------------------------------------------------------------------
-- Metrics
--
-- Two sources, split by what the value is: the bar's own dimensions and its colours are
-- plugin settings, so they are profile-aware and tunable on the Cast Bars page; spacing
-- and font size are theme tokens, because they are design language shared with the rest of
-- the UI. Nothing here is a literal.
---------------------------------------------------------------------------
local function metrics(cfg)
    local get = function(key) return SuuUI.Settings:Get(cfg.pluginId, cfg.prefix .. key) end
    return {
        height   = get("height"),
        width    = get("width"),
        showIcon = get("show_icon"),
        showName = get("show_name"),
        showTime = get("show_time"),
        showShield = get("show_shield"),
        iconSide = get("icon_position"),
        gap      = T:GetToken("spaceXxs"),
        padX     = T:GetToken("spaceXs"),
    }
end

---------------------------------------------------------------------------
-- Widget
---------------------------------------------------------------------------
local CastBarMeta = {}
CastBarMeta.__index = CastBarMeta

-- The fill colour for the state the bar is currently in, plus the uninterruptible cue.
-- Interruption borrows the intent token rather than a fourth colour setting: "this failed"
-- is the same idea everywhere in the UI, and a player who retints danger expects it to
-- follow here too.
function CastBarMeta:_paint()
    local st = self._state
    if st == "interrupted" or st == "failed" then
        self._bar:SetFillColor(T:GetToken("colorDanger"))
    else
        self._bar:SetFillColor(self:_fillColor())
    end
    self:_paintShield()
end

-- The fill for a live cast: the spell's school when the player asked for school colouring
-- and something has told us which school it is, otherwise the configured colour for casts
-- or channels.
--
-- The school falls back rather than substituting a colour of its own, because a spell whose
-- school is not known yet is indistinguishable from one that has no school — and inventing
-- a colour for "unknown" would give the player a cue that means nothing. The preview has no
-- spell at all, so it lands on the same fallback.
-- @return table  {r,g,b,a}
function CastBarMeta:_fillColor()
    local cfg = self._cfg
    local function get(key) return SuuUI.Settings:Get(cfg.pluginId, cfg.prefix .. key) end
    if get("school_color") then
        local rec = self._active
        local color = rec and SuuUI.Game:SchoolColor(rec.school)
        if color then return color end
    end
    return get((self._state == "channeling") and "channel_color" or "cast_color")
end

-- A hairline outline round the bar and its icon while the spell cannot be interrupted.
--
-- An outline rather than a fill colour, because the fill is the player's to configure: a
-- colour-only cue disappears the moment they pick something close to it, while an edge that
-- was not there before is a change of shape. Only ever shown for a real cast — the preview
-- and the interrupted state have nothing to say about interruptibility.
function CastBarMeta:_paintShield()
    local rec = self._active
    local on  = (rec ~= nil) and rec.shielded
                and SuuUI.Settings:Get(self._cfg.pluginId, self._cfg.prefix .. "show_shield")
                and true or false
    self._bar:SetBorderColor(SHIELD_COLOR)
    self._bar:SetBorderShown(on)
    self._icon:SetBorderColor(on and SHIELD_COLOR or "colorBorder")
end

-- Which child comes first in the row. Order is the only thing that decides the icon's
-- side, so switching sides is a re-add rather than a repositioning — the layout engine
-- owns every coordinate either way.
function CastBarMeta:_applyOrder(side)
    if self._iconSide == side then return end
    self._iconSide = side
    self._row:Remove(self._icon)
    self._row:Remove(self._barArea)
    if side == "right" then
        self._row:Add(self._barArea, self._barAreaProps)
        self._row:Add(self._icon, self._iconProps)
    else
        self._row:Add(self._icon, self._iconProps)
        self._row:Add(self._barArea, self._barAreaProps)
    end
end

-- Height always comes from the setting. Width only when the bar stands alone: an attached
-- bar is stretched by the frame it lives in, and writing a width here would fight the
-- layout that owns it — and lose a pass later, leaving the two disagreeing.
function CastBarMeta:_applySize()
    local m = metrics(self._cfg)
    local h = m.height
    if self._cfg.attached then
        if abs((self._wrapper:GetHeight() or 0) - h) > 0.5 then
            self._wrapper:SetHeight(h)
        end
        return
    end
    local w = m.width
    if abs((self._wrapper:GetWidth() or 0) - w) > 0.5
       or abs((self._wrapper:GetHeight() or 0) - h) > 0.5 then
        self._wrapper:SetSize(w, h)
    end
end

--- Re-derives every metric and re-lays the bar. Bound to the theme and to the layout
--- settings, so a slider or a spacing token takes effect without a reload.
function CastBarMeta:Relayout()
    local m = metrics(self._cfg)

    self._row:SetGap(m.gap)
    self._textRow:SetGap(m.padX)

    -- Square icon: as tall as the bar, therefore as wide.
    self._iconProps.width = m.height
    self._row:SetChildProps(self._icon, self._iconProps)

    self._textInset.left  = m.padX
    self._textInset.right = m.padX
    self._barStack:SetChildProps(self._textRow, self._textProps)

    self:_applyOrder(m.iconSide)
    self:_applySize()
    self:_syncParts(m)
    self._row:Layout()
end

--- Theme hook: children first, then colours, then geometry.
function CastBarMeta:ApplyTheme()
    -- The event bus dispatches newest-first, so an owned child's own subscription may not
    -- have run yet. Applying them explicitly means this widget measures current metrics
    -- rather than the ones the previous theme produced.
    self._icon:ApplyTheme()
    self._bar:ApplyTheme()
    self._nameText:ApplyTheme()
    self._timeText:ApplyTheme()
    self:_paint()
    self:Relayout()
end

-- Applies the show_* settings to the parts. Visibility of the parts is independent of
-- whether the bar as a whole is showing anything, which is why it is separate from
-- _showContent: a bar with its icon switched off still has an icon to keep hidden.
function CastBarMeta:_syncParts(m)
    m = m or metrics(self._cfg)
    if m.showIcon then self._icon:Show() else self._icon:Hide() end
    if m.showName then self._nameText:Show() else self._nameText:Hide() end
    if m.showTime then self._timeText:Show() else self._timeText:Hide() end
end

---------------------------------------------------------------------------
-- Content visibility
--
-- The wrapper stays shown and keeps its full size for as long as the bar is enabled, and
-- only the content row inside it comes and goes. That is what stops an attached bar from
-- resizing the unit frame every time a spell is cast — the band is reserved, so the health
-- bars above it never jump. It is also what keeps a detached bar draggable while idle:
-- edit mode's overlay hangs off the wrapper, which is still there.
---------------------------------------------------------------------------

function CastBarMeta:_showContent()
    local f = self._row:GetFrame()
    -- An interrupted cast leaves a fade in flight and an alpha on its way to 0. Both have
    -- to go before the next cast paints, or the new bar inherits the old one's exit.
    SuuUI.Anim:CancelAll(f)
    f:SetAlpha(1)
    if not self._row:IsShown() then self._row:Show() end
end

function CastBarMeta:_hideContent()
    SuuUI.Anim:CancelAll(self._row:GetFrame())
    if self._row:IsShown() then self._row:Hide() end
end

-- Nothing is casting: either the edit-mode preview or nothing at all.
function CastBarMeta:_syncIdle()
    if self._active then return end
    if SuuUI.ToggleUI:IsEditMode() then
        self:_showPreview()
    else
        self._state = "idle"
        self:_hideContent()
    end
end

-- A placeholder cast, so edit mode shows what the bar will look like where it sits.
function CastBarMeta:_showPreview()
    self._state = "preview"
    self._icon:SetIcon(PREVIEW_ICON)
    self._nameText:SetText(self._cfg.displayName or "")
    self._timeToken = nil
    self:_paint()
    self:_syncParts()
    self:_showContent()
    self._bar:SetValue(PREVIEW_FRACTION)
    self:_setTimeText(PREVIEW_TOTAL * PREVIEW_FRACTION, PREVIEW_TOTAL)
    self._textRow:Layout()
end

---------------------------------------------------------------------------
-- Progress
---------------------------------------------------------------------------

-- Paints one readout. Guarded on the format's own quantised token so the string is only
-- rebuilt when it would actually differ.
function CastBarMeta:_setTimeText(elapsed, total)
    local fmt = self._timeFmt or TIME_FORMATS[DEFAULT_FORMAT]
    local str, token = fmt(elapsed, total)
    if token == self._timeToken then return end
    self._timeToken = token
    self._timeText:SetText(str)
    -- The readout hugs its own width, and Text only reports a SIZE_CHANGED when its
    -- HEIGHT moves, so nothing else re-flows the row after a text change. Same reason
    -- Divider re-runs its box: a wider string would otherwise keep the old width and be
    -- clipped by the client rather than overflow visibly.
    self._textRow:Layout()
end

-- The single write path for the animated fraction. Elapsed time is derived from the
-- painted fraction rather than read from the clock, so the readout can never disagree with
-- the fill by a frame.
function CastBarMeta:_onProgress(fraction)
    self._bar:SetValue(fraction)
    local rec = self._active
    if not rec or not self._timeText:IsShown() then return end
    local elapsed = rec.channel and (rec.total * (1 - fraction)) or (rec.total * fraction)
    self:_setTimeText(elapsed, rec.total)
end

function CastBarMeta:_stopTween()
    if self._tween then
        self._tween:Stop()
        self._tween = nil
    end
end

-- Progress is driven by the animator's frameless `value` property rather than an OnUpdate
-- of our own: the addon already runs exactly one update ticker, a linear tween over the
-- remaining cast time is precisely what a cast bar needs, and starting a new one pre-empts
-- the old automatically — so a re-cast cannot leave two tweens fighting over the fill.
function CastBarMeta:_startTween(fromF, toF, seconds)
    self:_stopTween()
    self._tween = SuuUI.Anim:New({
        target   = self,
        property = "value",
        apply    = function(v) self:_onProgress(v) end,
        from     = fromF,
        to       = toF,
        duration = seconds,
        easing   = "linear",
        onDone   = function()
            -- The client normally sends a stop event first; this covers the case where it
            -- does not arrive, so the bar cannot sit at full for ever.
            self:_end("stopped")
        end,
    })
    self._tween:Play()
end

---------------------------------------------------------------------------
-- Cast lifecycle
---------------------------------------------------------------------------

function CastBarMeta:_begin(rec)
    local total = (rec.endMS - rec.startMS) / 1000
    if total <= 0 then
        self:_end("stopped")
        return
    end
    local elapsed = (GetTime() * 1000 - rec.startMS) / 1000
    if elapsed < 0 then elapsed = 0 end
    if elapsed > total then elapsed = total end

    rec.total    = total
    -- The warm path for school colouring: a spell cast before is coloured on the first
    -- frame with no repaint at all. A miss leaves this nil, and the combat log fills it in
    -- mid-cast through _schoolLearned.
    rec.school   = SuuUI.Game:SchoolOf(rec.spellId)
    self._active = rec
    self._state  = rec.channel and "channeling" or "casting"

    -- A new cast is a clean slate: whoever broke the last one has nothing to do with this
    -- one, and a cached name left in place could resurface on an unattributed interrupt
    -- moments later.
    self._intName, self._intAt = nil, nil

    self._icon:SetIcon(rec.texture)
    self._nameText:SetText(rec.name or "")
    self._timeToken = nil
    self:_paint()
    self:_syncParts()
    self:_showContent()

    -- A cast fills; a channel drains. Both are one linear run over the remaining time,
    -- which is why the same tween serves both.
    local fromF = rec.channel and (1 - elapsed / total) or (elapsed / total)
    local toF   = rec.channel and 0 or 1
    self:_onProgress(fromF)

    local remaining = total - elapsed
    if remaining <= 0 then
        self:_onProgress(toF)
        self:_end("stopped")
        return
    end
    self:_startTween(fromF, toF, remaining)
    self._textRow:Layout()
end

-- @param reason string  "stopped" | "interrupted" | "failed"
function CastBarMeta:_end(reason)
    self:_stopTween()
    local wasActive = self._active ~= nil
    self._active = nil

    if wasActive and (reason == "interrupted" or reason == "failed") then
        self._state = reason
        -- The spell name stays where it is and the outcome goes in the slot the cast timer
        -- just vacated: a broken cast has no remaining time to report, so naming who
        -- stopped it costs no space and the bar still says WHAT was stopped.
        self:_paint()
        self._timeToken = nil
        self:_showOutcome(reason)
        -- Held full and then faded. A bar that vanished the instant a cast broke gives no
        -- sign that it broke at all; easeIn (the fade's curve) keeps it legible through
        -- most of the fade, so no separate hold timer is needed.
        self._bar:SetValue(1)
        self:_fadeOutContent()
        return
    end

    self._state = "idle"
    self:_syncIdle()
end

--- Writes the outcome into the readout slot: the interrupter's name when the combat log
--- attributed one, and the client's own localised word when it did not.
--
-- A fallback is not optional here. UNIT_SPELLCAST_INTERRUPTED never carries a source, and
-- the combat log can legitimately fail to supply one, so a design that only ever printed a
-- name would silently show an empty bar for the case it exists to describe.
-- @param reason string
function CastBarMeta:_showOutcome(reason)
    local label
    if reason == "interrupted" then
        label = self:_recentInterrupter() or INTERRUPTED or "Interrupted"
    else
        label = FAILED or "Failed"
    end
    self._timeText:SetText(label)
    self._textRow:Layout()
end

-- The interrupter's name, if one was reported close enough in time to belong to this cast.
-- Both events are the client's and their order is not guaranteed, so they are correlated by
-- time rather than by arrival.
-- @return string|nil
function CastBarMeta:_recentInterrupter()
    if not self._intName then return nil end
    if (GetTime() - (self._intAt or 0)) > INTERRUPT_WINDOW then return nil end
    return self._intName
end

-- Reads a SPELL_INTERRUPT line off the combat log, which is the only place the interrupter
-- is named. Matched on destGUID: the log speaks in GUIDs and never in unit tokens.
function CastBarMeta:_readCombatLog()
    if type(CombatLogGetCurrentEventInfo) ~= "function" then return end

    -- Every line naming a spell teaches the shared cache what school it is, whoever cast
    -- it. Any line will do, which is the point: a channel never fires SPELL_CAST_START, so
    -- waiting for a cast line specifically would leave every channel uncoloured.
    local learnedId, learnedSchool = SuuUI.Game:LearnFromCombatLog()
    if learnedId then self:_schoolLearned(learnedId, learnedSchool) end

    local _, subevent, _, _, sourceName, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if subevent ~= "SPELL_INTERRUPT" then return end
    if not destGUID or destGUID ~= UnitGUID(self._cfg.unit) then return end

    self._intName = sourceName
    self._intAt   = GetTime()
    -- The log line can arrive AFTER the cast event, so a bar already showing the outcome
    -- has its readout filled in retroactively rather than staying on the fallback.
    if self._state == "interrupted" then self:_showOutcome("interrupted") end
end

-- The cold path for school colouring: the spell in flight was cast for the first time this
-- session, so it started on the fallback colour and the log has only now said what it is.
--
-- Recolouring mid-cast is safe because _paint touches the fill colour and the outline and
-- nothing else — not the tween, not the fraction, not the layout — so the bar cannot jump
-- or lose progress. Guarded on the record's own school so a raid's worth of lines for the
-- same spell cannot repaint on every one of them: once known, there is nothing to change.
-- @param spellId number
-- @param school number
function CastBarMeta:_schoolLearned(spellId, school)
    local rec = self._active
    if not rec or rec.school or rec.spellId ~= spellId then return end
    rec.school = school
    self:_paint()
end

-- Fades the content out and then hands control back to the idle path.
--
-- Not Presets.FadeOut: that hides the frame and stops there, which left the widget
-- claiming "interrupted" for ever and — worse — never brought the edit-mode preview back
-- after a cast broke while the player was arranging their frames. The fade's completion is
-- part of the state machine, so it has to say so.
function CastBarMeta:_fadeOutContent()
    local f = self._row:GetFrame()
    SuuUI.Anim:New({
        target   = f,
        property = "alpha",
        from     = f:GetAlpha() or 1,
        to       = 0,
        duration = T:GetToken("animSlow"),
        -- easeIn holds it legible through most of the fade, so the outcome is readable
        -- without a separate hold timer.
        easing   = "easeIn",
        onDone   = function()
            self._row:Hide()
            self._state = "idle"
            -- Edit mode may want its preview back now that the outcome has been shown.
            self:_syncIdle()
        end,
    }):Play()
end

--- Re-reads the unit and brings the bar into agreement with it.
--
-- Every cast event funnels through here rather than trusting its own payload: the client's
-- UNIT_SPELLCAST_* arguments differ between flavours, while UnitCastingInfo /
-- UnitChannelInfo describe a cast the same way on all of them.
function CastBarMeta:Refresh()
    local unit = self._cfg.unit
    local channel = false
    local name, _, texture, startMS, endMS, _, _, shielded, spellId = UnitCastingInfo(unit)
    if not name then
        -- One value shorter than a cast: a channel has no castID, so notInterruptible
        -- moves up a slot. Reading it at the cast's position would report every channel
        -- as uninterruptible.
        local cName, _, cTex, cStart, cEnd, _, cShield, cSpellId = UnitChannelInfo(unit)
        name, texture, startMS, endMS, shielded = cName, cTex, cStart, cEnd, cShield
        spellId = cSpellId
        channel = name ~= nil
    end
    if not name or type(startMS) ~= "number" or type(endMS) ~= "number" then
        self:_end("stopped")
        return
    end
    self:_begin({
        name     = name,
        texture  = texture,
        startMS  = startMS,
        endMS    = endMS,
        channel  = channel,
        spellId  = spellId,
        shielded = shielded and true or false,
    })
end

--- Returns whether a cast is currently being shown.
-- @return bool
function CastBarMeta:IsCasting()
    return self._active ~= nil
end

--- Returns the state the bar is painting: idle, casting, channeling, interrupted, failed
--- or preview. Used by specs and by the plugin's own diagnostics.
-- @return string
function CastBarMeta:GetState()
    return self._state
end

function CastBarMeta:Destroy()
    self:_stopTween()
    SuuUI.Anim:CancelAll(self._row:GetFrame())
    SuuUI.Anim:CancelAll(self)
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._owner)
    -- Every watcher this widget registered shares the owner prefix, so one call retires
    -- the lot — including the edit-mode watcher, which lives under another plugin's key.
    SuuUI.Settings:UnwatchPrefix(self._owner)
    self._events:UnregisterAllEvents()
    self._events:Hide()
    self._nameText:Destroy()
    self._timeText:Destroy()
    self._icon:Destroy()
    self._bar:Destroy()
    self._textRow:Destroy()
    self._barStack:Destroy()
    self._row:Destroy()
    self._contentBox:Destroy()
    self._wrapper:Hide()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize, Show, Hide. Installed after
-- the methods above so nothing here is overwritten.
-- Caches the format function the readout uses. A derived dispatch rather than a copy of
-- the setting: it is re-resolved by the watcher (and on a profile switch, which the watcher
-- also delivers), so it cannot go stale — and the tween is spared a store lookup per frame.
function CastBarMeta:_syncFormat()
    local name = SuuUI.Settings:Get(self._cfg.pluginId, self._cfg.prefix .. "time_format")
    self._timeFmt = TIME_FORMATS[name] or TIME_FORMATS[DEFAULT_FORMAT]
end

-- Re-renders the readout at the current progress after the format changed.
function CastBarMeta:_repaintTime()
    self._timeToken = nil
    local rec = self._active
    if rec then
        local f = self._bar:GetPercent() or 0
        self:_setTimeText(rec.channel and (rec.total * (1 - f)) or (rec.total * f), rec.total)
    elseif self._state == "preview" then
        self:_setTimeText(PREVIEW_TOTAL * PREVIEW_FRACTION, PREVIEW_TOTAL)
    end
end

C.InstallBase(CastBarMeta, "_wrapper")

local CastBar = {}

--- Creates a cast bar.
--
-- Emits SIZE_CHANGED, which is what lets the frame it is attached to follow its height:
-- a parent layout resizes this widget's frame directly and never calls SetSize.
-- @param parent frame
-- @param cfg table  { unit, pluginId, prefix, displayName, attached }
--   unit:        unit token to watch, e.g. "player"
--   prefix:      settings key prefix, e.g. "player_"
--   attached:    true when a foreign layout owns the width
-- @return table  CastBar handle
function CastBar:Create(parent, cfg)
    local self = setmetatable({
        _cfg      = cfg,
        _state    = "idle",
        _owner    = "castbar:" .. cfg.pluginId .. ":" .. cfg.prefix,
    }, CastBarMeta)
    local m = metrics(cfg)

    -- Bare grouping frame: no styling and no scripts of its own beyond the resize hook, so
    -- nothing is drawn behind the bar. It keeps its size while idle, which is what reserves
    -- the band inside an attached unit frame.
    self._wrapper = CreateFrame("Frame", nil, parent)
    self._wrapper:SetSize(m.width, m.height)
    self._owner = self._owner .. tostring(self._wrapper)

    -- Registered BEFORE the host container adopts the frame, so the container chains onto
    -- this hook instead of replacing it.
    self._wrapper:SetScript("OnSizeChanged", function(_, w, h)
        if not self._contentBox then return end
        S:Emit(self, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    -- The content root. Everything visible hangs off this one container so showing,
    -- hiding and fading the bar are single calls that leave the wrapper — and therefore
    -- the reserved band and the edit-mode overlay — untouched.
    self._contentBox = SuuUI.Layout:CreateContainer({ host = self._wrapper, layout = "stack" })

    self._row = SuuUI.Layout:CreateContainer({
        parent = self._wrapper,
        layout = "flow",
        dir    = "horizontal",
        gap    = m.gap,
        align  = "center",
    })
    self._contentBox:Add(self._row)

    self._icon = C.Icon({
        size   = m.height,
        border = true,
        -- Blizzard bakes a bevel into the icon file; cropping it keeps one border, ours.
        trim   = true,
    }, self._row:GetFrame())

    -- Bare grouping frame again: it exists so the bar and the text over it share one box.
    self._barArea = CreateFrame("Frame", nil, self._row:GetFrame())

    self._iconProps    = { width = m.height, height = "fill" }
    self._barAreaProps = { width = "fill", height = "fill" }
    self:_applyOrder(m.iconSide)

    self._barStack = SuuUI.Layout:CreateContainer({ host = self._barArea, layout = "stack" })

    self._bar = C.StatusBar({
        max        = 1,
        value      = 0,
        bgColor    = "colorBarTrack",
        border     = false,
        transition = BAR_TRANSITION,
    }, self._barArea)
    self._barStack:Add(self._bar)

    -- Name and time overlay the bar. The row stretches to the bar's full height and
    -- centres its children, so the text is centred without anyone measuring anything.
    self._textRow = SuuUI.Layout:CreateContainer({
        parent = self._barArea,
        layout = "flow",
        dir    = "horizontal",
        gap    = m.padX,
        align  = "center",
    })
    self._textInset = { left = m.padX, right = m.padX }
    self._textProps = { valign = "stretch", inset = self._textInset }
    self._barStack:Add(self._textRow, self._textProps)

    -- The bar's fill lives in a child frame one level above the bar itself, so clearing
    -- it takes two steps. Stated through the layer system rather than a raw frame level.
    SuuUI.UIRoot:RaiseAbove(self._textRow:GetFrame(), self._bar:GetFrame(), 2)

    self._nameText = C.Text({ text = "", size = TEXT_SIZE, color = "text" },
                            self._textRow:GetFrame())
    self._timeText = C.Text({ text = "", size = TEXT_SIZE, color = "text", justify = "RIGHT" },
                            self._textRow:GetFrame())
    self._textRow:Add(self._nameText, { width = "fill" })
    self._textRow:Add(self._timeText, { width = "auto" })

    self:_hideContent()

    ------------------------------------------------------------------
    -- Reactive bindings
    ------------------------------------------------------------------
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() self:ApplyTheme() end, self._owner)

    for _, key in ipairs(LAYOUT_KEYS) do
        SuuUI.Settings:Watch(cfg.pluginId, cfg.prefix .. key, function()
            self:Relayout()
        end, self._owner .. ":" .. key, { immediate = true })
    end
    for _, key in ipairs(PAINT_KEYS) do
        SuuUI.Settings:Watch(cfg.pluginId, cfg.prefix .. key, function()
            self:_paint()
        end, self._owner .. ":" .. key)
    end
    for _, key in ipairs(FORMAT_KEYS) do
        SuuUI.Settings:Watch(cfg.pluginId, cfg.prefix .. key, function()
            self:_syncFormat()
            self:_repaintTime()
        end, self._owner .. ":" .. key, { immediate = true })
    end

    -- Edit mode decides what an idle bar shows. `immediate` matters: a bar created while
    -- edit mode is already on has to show its preview at once rather than wait for the
    -- next toggle.
    SuuUI.Settings:Watch("_layout", "edit_mode", function()
        self:_syncIdle()
    end, self._owner .. ":edit_mode", { immediate = true })

    ------------------------------------------------------------------
    -- Game data
    ------------------------------------------------------------------
    self._events = CreateFrame("Frame")
    self._events:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- The only source of the interrupter's name; UNIT_SPELLCAST_INTERRUPTED has none.
    self._events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    -- The unit became a different unit, so whatever the bar is showing belongs to someone
    -- who is no longer being watched. Refresh re-reads the unit and stops the bar when the
    -- new one is idle, which is the same path a cast ending already takes — so losing a
    -- target mid-cast clears the bar rather than freezing it at the old spell.
    if cfg.changeEvent then
        self._events:RegisterEvent(cfg.changeEvent)
    end
    for _, event in ipairs({
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
        "UNIT_SPELLCAST_CHANNEL_STOP",
    }) do
        self._events:RegisterEvent(event)
    end
    self._events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" or event == cfg.changeEvent then
            self:Refresh()
            return
        end
        -- Handled before the unit filter: a combat log event carries no unit token at all,
        -- so filtering on one would drop every line.
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            self:_readCombatLog()
            return
        end
        if unit ~= cfg.unit then return end
        if event == "UNIT_SPELLCAST_INTERRUPTED" then
            self:_end("interrupted")
        elseif event == "UNIT_SPELLCAST_FAILED" then
            self:_end("failed")
        else
            self:Refresh()
        end
    end)

    self:Refresh()
    return self
end

--- Builds the settings schema for one unit's tab.
--
-- It lives beside the widget rather than in the plugin file because these keys, their
-- option lists and their defaults are the widget's own vocabulary — metrics() and the three
-- watcher key lists read exactly this set — and a schema written elsewhere would be a
-- second declaration of them, free to drift.
--
-- Every key is derived from the prefix, so a new unit is one entry in the plugin's UNITS
-- list and nothing else.
-- @param prefix string  Unit key prefix, e.g. "target_"
-- @param opts table     { attachLabel, width, height }
-- @return table  Schema array for the tab
function CastBar.Schema(prefix, opts)
    return {
        { key = "", label = "General", type = "section" },
        { key = prefix .. "enabled",   label = "Enable Cast Bar", type = "toggle", default = true },
        { key = prefix .. "show_icon", label = "Show Icon",       type = "toggle", default = true },
        { key = prefix .. "show_name", label = "Show Spell Name", type = "toggle", default = true },
        { key = prefix .. "show_time", label = "Show Cast Time",  type = "toggle", default = true },
        -- Information rather than decoration, so it defaults on — but a player who finds
        -- the outline noisy can switch it off.
        { key = prefix .. "show_shield", label = "Mark Uninterruptible Casts",
          type = "toggle", default = true },

        { key = "", label = "Placement", type = "section" },
        { key = prefix .. "anchor", label = "Attach To", type = "dropdown",
          default = "attached", options = {
            { value = "attached", label = opts.attachLabel },
            { value = "detached", label = "Detached" },
          } },
        -- Only meaningful while attached: a detached bar sits wherever it was dragged, so
        -- above/below has nothing to be relative to.
        { key = prefix .. "attach_position", label = "Position", type = "dropdown",
          default = "below", options = {
            { value = "above", label = "Above Frame" },
            { value = "below", label = "Below Frame" },
          },
          enabledIf = { key = prefix .. "anchor", equals = "attached" } },
        -- An attached bar takes its width from the frame it is part of, so the slider is
        -- greyed out rather than silently ignored. Defaulted to the unit frame's own width
        -- so detaching does not resize it.
        { key = prefix .. "width", label = "Width", type = "slider",
          min = 80, max = 500, step = 2, default = opts.width,
          enabledIf = { key = prefix .. "anchor", equals = "detached" } },

        { key = "", label = "Appearance", type = "section" },
        { key = prefix .. "icon_position", label = "Icon Side", type = "dropdown",
          default = "left", options = {
            { value = "left",  label = "Left" },
            { value = "right", label = "Right" },
          } },
        { key = prefix .. "time_format", label = "Cast Time", type = "dropdown",
          default = DEFAULT_FORMAT, options = {
            { value = "remaining", label = "Remaining (1.4)" },
            { value = "elapsed",   label = "Elapsed (1.1)" },
            { value = "both",      label = "Elapsed / Total (1.1 / 2.5)" },
            { value = "percent",   label = "Percent (44%)" },
          } },
        { key = prefix .. "height", label = "Height", type = "slider",
          min = 12, max = 48, step = 1, default = opts.height },

        { key = "", label = "Colour", type = "section" },
        -- School colouring is the default because it carries information the fixed colours
        -- cannot. The pickers below stay, greyed, because they are still the fallback for a
        -- spell whose school nothing has reported — and because a fixed bar colour matching
        -- the rest of someone's UI is a legitimate taste rather than a worse choice.
        { key = prefix .. "school_color", label = "Colour by Spell School",
          type = "toggle", default = true },
        { key = prefix .. "cast_color",    label = "Cast",    type = "color",
          default = { 0.85, 0.63, 0.17, 1 },
          enabledIf = { key = prefix .. "school_color", equals = false } },
        { key = prefix .. "channel_color", label = "Channel", type = "color",
          default = { 0.25, 0.55, 0.85, 1 },
          enabledIf = { key = prefix .. "school_color", equals = false } },
    }
end

SuuUI._CastBars = SuuUI._CastBars or {}
SuuUI._CastBars.CastBar = CastBar
