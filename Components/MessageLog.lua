-- ScrollingMessageFrame is a Blizzard-required component: word wrap, a line cap, timed fading,
-- scrolling and per-line hyperlink hit-testing are the client's, and none of them is reasonably
-- reimplementable over N row frames. This wraps it with SuuUI theming, exactly as Input.lua
-- wraps EditBox.
--
-- It formats NOTHING. Callers hand it a finished string, because what a message MEANS belongs to
-- whoever owns it -- the same division StatusBar's text slots draw.
local S = SuuUI.UISignals

-- Message-log-specific signals.
SuuUI.Components.MESSAGELOG_SIGNALS = {
    HYPERLINK_CLICK  = "messagelog.hyperlink_click",  -- Args: link, text, button
    HYPERLINK_ENTER  = "messagelog.hyperlink_enter",  -- Args: link
    HYPERLINK_LEAVE  = "messagelog.hyperlink_leave",  -- Args: none
    AT_BOTTOM_CHANGED = "messagelog.at_bottom_changed", -- Args: isAtBottom
}

local SIG = SuuUI.Components.MESSAGELOG_SIGNALS

local LogMeta = {}
LogMeta.__index = LogMeta

--- Appends one finished line. Colour is per-message because the client stores it per line, which
--- is what lets one log hold guild green and whisper magenta at once.
-- @param text string
-- @param r number|nil
-- @param g number|nil
-- @param b number|nil
-- @param lineID number|nil  The client's own line id, needed by SetItemRef for a player link
function LogMeta:AddMessage(text, r, g, b, lineID)
    local wasBottom = self._log:AtBottom()
    self._log:AddMessage(text or "", r, g, b, lineID)
    -- A reader who was scrolled up stays there and the unread accumulates below them, which is
    -- what a jump-to-bottom affordance exists to report. Emit only on a real edge.
    local isBottom = self._log:AtBottom()
    if wasBottom ~= isBottom then S:Emit(self, SIG.AT_BOTTOM_CHANGED, isBottom) end
end

function LogMeta:Clear()
    local wasBottom = self._log:AtBottom()
    self._log:Clear()
    if not wasBottom then S:Emit(self, SIG.AT_BOTTOM_CHANGED, true) end
end

function LogMeta:GetNumMessages()      return self._log:GetNumMessages() end
function LogMeta:GetMessageInfo(i)     return self._log:GetMessageInfo(i) end
function LogMeta:GetMaxLines()         return self._log:GetMaxLines() end
function LogMeta:SetMaxLines(n)        self._log:SetMaxLines(n) end
function LogMeta:AtBottom()            return self._log:AtBottom() end

--- Channel logs fade, conversation logs do not. One call, set per log rather than globally --
--- a firehose should evaporate and a conversation is history you scroll back through.
-- @param on boolean
-- @param timeVisible number|nil  seconds a line stays solid
-- @param fadeDuration number|nil seconds the fade itself takes
function LogMeta:SetFading(on, timeVisible, fadeDuration)
    self._log:SetFading(on and true or false)
    if timeVisible  then self._log:SetTimeVisible(timeVisible) end
    if fadeDuration then self._log:SetFadeDuration(fadeDuration) end
end

function LogMeta:IsFading() return self._log:GetFading() end

--- Hides or reveals the WHOLE buffer at once, independently of per-line fading.
---
--- Per-line fading cannot express "already faded", because the client starts a line's fade clock
--- when the line is ADDED -- so history replayed at login is `timeVisible` seconds from fading
--- however old the messages actually are. Whole-buffer alpha is the only thing that can say "this
--- text is stale, do not show it until asked".
---
--- Revealing resets every line's fade clock as well. Without that a revealed line vanishes again on
--- the next frame, its own fade time having expired long ago; `ResetAllFadeTimes` is what ElvUI
--- calls immediately before its own frame fade-in, which is where the call was found.
function LogMeta:SetFaded(faded)
    self._faded = faded and true or false
    if self._faded then
        self._log:SetAlpha(0)
        return
    end
    self._log:SetAlpha(1)
    if type(self._log.ResetAllFadeTimes) == "function" then self._log:ResetAllFadeTimes() end
end

function LogMeta:IsFaded() return self._faded == true end

--- The scroll offset, or nil on a client that does not name it this.
---
--- MEASURED: the getter is `GetScrollOffset`. `GetCurrentScroll` was called here and DOES NOT EXIST
--- on this build -- it raised "attempt to call a nil value" on the very first wheel turn, 29 times
--- before the player stopped scrolling, and the harness had modelled it under that wrong name so
--- every scroll spec passed against an API the client does not have.
---
--- The type guard stays because a nil call is exactly what happened here, but the second candidate
--- name is gone: with the harness corrected it was unreachable in both game and suite, which this
--- project deletes rather than keeps as untestable defence. nil remains a real answer — nothing
--- consumes SCROLL_CHANGED's payload, so an absent number costs less than a raise.
local function scrollOffset(log)
    if type(log.GetScrollOffset) ~= "function" then return nil end
    local ok, v = pcall(log.GetScrollOffset, log)
    if ok then return v end
    return nil
end

local function scrolled(self, fn)
    local wasBottom = self._log:AtBottom()
    fn(self._log)
    S:Emit(self, S.SIGNALS.SCROLL_CHANGED, scrollOffset(self._log))
    local isBottom = self._log:AtBottom()
    if wasBottom ~= isBottom then S:Emit(self, SIG.AT_BOTTOM_CHANGED, isBottom) end
end

function LogMeta:ScrollUp()       scrolled(self, function(l) l:ScrollUp() end) end
function LogMeta:ScrollDown()     scrolled(self, function(l) l:ScrollDown() end) end
function LogMeta:PageUp()         scrolled(self, function(l) l:PageUp() end) end
function LogMeta:PageDown()       scrolled(self, function(l) l:PageDown() end) end
function LogMeta:ScrollToTop()    scrolled(self, function(l) l:ScrollToTop() end) end
function LogMeta:ScrollToBottom() scrolled(self, function(l) l:ScrollToBottom() end) end

--- Moves the log onto another font step. A token KEY, never a pixel size, so a plugin exposing
--- the step as a setting still follows a user's edit of that token.
-- @param key string  "sm"|"md"|"lg"|"xl"
function LogMeta:SetFontSize(key)
    self._sizeKey = key or "md"
    self:_applyFont()
end

function LogMeta:GetFontSize() return self._sizeKey end

--- The chrome: a hairline border, or none at all. The concept's log is frameless at rest, so this
--- is a runtime state rather than a construction-time one.
---
--- It no longer controls the SURFACE. Every log now carries the bottom-weighted wash
--- unconditionally, because that surface is a legibility mechanism rather than decoration -- white
--- text on snow or water is genuinely hard to read with the text shadow alone, which is what the
--- frameless concept shipped and what Domenik reported. So `chrome` is the border and nothing else;
--- a solid `colorBg` on top of the wash would be two surfaces, and at opacityPanel the wash would
--- be invisible underneath it.
-- @param on boolean
function LogMeta:SetChrome(on)
    self._chrome = on and true or false
    self:_paint()
end

function LogMeta:HasChrome() return self._chrome == true end

-- Surface only, so a chrome flip never rebuilds the backdrop table.
--- A one-unit shadow under every line.
---
--- A frameless log draws straight over the game world, so a glyph on pale terrain has nothing to
--- separate it from the background. The concept specifies a text-shadow on every chat line for
--- exactly this reason -- it is not decoration, it is what makes the frameless design legible.
--- Applied through the font path so a font-size change keeps it.
function LogMeta:_applyShadow()
    local T = SuuUI.Theme
    local ink = T:GetToken("colorGray950") or { 0, 0, 0, 1 }
    local a = T:GetToken("opacityTextShadow")
    if type(a) ~= "number" then a = 0.9 end
    if self._log.SetShadowColor then
        self._log:SetShadowColor(ink[1], ink[2], ink[3], a)
        self._log:SetShadowOffset(SuuUI.Pixel.Line(1), -SuuUI.Pixel.Line(1))
    end
end

function LogMeta:_paint()
    -- BORDER ONLY. The surface is the wash, which is always on -- see SetChrome.
    SuuUI.Backdrop.SetBorder(self._f, self._chrome and "colorBorder" or false)
end

--- Whether the wash is drawing a real gradient, or the flat fallback on a client with no gradient
--- API. Reported rather than assumed, exactly as Backdrop.Glass reports it: a flat wash at the
--- dense end would be far heavier than intended, so a caller that cares can say so.
function LogMeta:IsWashGradient()
    return self._wash ~= nil and self._wash:IsGradient() == true
end

-- Resolved through Fonts:Path because SetFont RAISES on an asset the client cannot load, and an
-- unguarded probe here has already cost this addon a login.
function LogMeta:_applyFont()
    local T = SuuUI.Theme
    local path = SuuUI.Fonts:Path(T:GetToken("fontFamilyMain"))
    local size = T:GetFontSize(self._sizeKey)
    local ok = pcall(function() self._log:SetFont(path, size, "") end)
    self:_applyShadow()
    if not ok then
        self._log:SetFont(SuuUI.Fonts.FALLBACK, size, "")
    end
    -- THE ROW GAP. A bare ScrollingMessageFrame stacks its lines flush, which is what made the log a
    -- wall of text against the concept's separated rows -- it puts 3px between them. `spaceXxs` for its
    -- MEANING: a hairline gap between things stacked inside one widget, which is exactly this.
    --
    -- Here rather than at construction because it is token-derived, so it has to be re-stated whenever
    -- the spacing scale is edited -- the same reason the font is re-read here rather than cached.
    if self._log.SetSpacing then
        self._log:SetSpacing(SuuUI.Pixel.Snap(T:GetToken("spaceXxs") or 2))
    end
end

function LogMeta:ApplyTheme()
    -- The BACKDROP carries the border only. Apply builds the full table whatever it is handed, so
    -- `_paint` can flip the border to transparent later; `bg = false` keeps the background channel
    -- transparent for good, because the surface is the wash below rather than a backdrop fill.
    SuuUI.Backdrop.Apply(self._f, { bg = false, border = "colorBorder" })
    -- Re-derived rather than left alone: the wash's colours are token derivations, and its band
    -- geometry depends on borderWidth, which a theme edit can move.
    if self._wash then self._wash:Refresh() end
    self:_paint()
    self:_applyFont()
end

function LogMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    if self._wash then self._wash:Destroy() self._wash = nil end
    self._box:Destroy()
    self._f:Hide()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize, Show, Hide.
--
-- InstallEnable is deliberately NOT installed. A log is display-only, is never a settings-page
-- control, and the one real disabling left -- dropping mouse input -- would kill the hyperlink
-- hit-testing that is the whole reason it takes the mouse. An empty SetEnabled would be worse
-- than none: Dependency.Bind's `if target.SetEnabled` guard would pass while nothing was inert.
-- Same call as StatusBar, Tooltip and UnitClickArea.
SuuUI.Components.InstallBase(LogMeta, "_f")

--- Creates a scrolling message log.
-- Emits SCROLL_CHANGED (scrollY), SIZE_CHANGED (w, h), plus MESSAGELOG_SIGNALS
-- HYPERLINK_CLICK (link, text, button), HYPERLINK_ENTER (link), HYPERLINK_LEAVE and
-- AT_BOTTOM_CHANGED (isAtBottom).
-- @param props table   { w, h, maxLines, size, fading, timeVisible, fadeDuration, chrome }
-- @param parent frame
-- @return table  MessageLog handle
function SuuUI.Components.MessageLog(props, parent)
    props = props or {}
    local T = SuuUI.Theme

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(props.w or 400, props.h or 120)

    -- Registered before the host container adopts the frame so the container chains onto this
    -- hook rather than replacing it. A parent layout resizes the frame directly, never via the
    -- handle's SetSize, so this is the only place that sees a layout-driven resize.
    local handle
    f:SetScript("OnSizeChanged", function(_, w2, h2)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w2, h2)
    end)

    -- THE LEGIBILITY WASH, built before the host container adopts the frame so the container chains
    -- onto Glass's own resize hook rather than replacing it -- the same ordering Backdrop.Glass
    -- documents for its callers, and the reason a glass surface elsewhere once drew a 411x546 body
    -- inside a 219-unit window.
    --
    -- `from` and `to` look INVERTED here and are correct. Glass's convention is that `from` is the
    -- DENSE end and it is the TOP (it hands `to` to SetGradient's min slot, which is the bottom). A
    -- chat log fills UPWARD, so the ink has to be at the bottom where the newest lines are: the
    -- light token goes in `from` and the dense one in `to`.
    --
    -- `sheen = false` because the sheen is a lit hairline along the TOP edge -- a highlight on the
    -- dense end of a plate. On a bottom-weighted wash the dense end is the bottom, so the sheen
    -- would draw a bright line across the thinnest part of the gradient, which is a line on the
    -- game world rather than an edge on a surface. `border = false` for the same reason `_paint`
    -- owns it: the border is `chrome`, and it belongs to the backdrop so a chrome flip costs no
    -- rebuild here.
    local wash = SuuUI.Backdrop.Glass(f, {
        from   = "colorChatWashFade",
        to     = "colorChatWash",
        sheen  = false,
        border = false,
    })

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
    local log = CreateFrame("ScrollingMessageFrame", props.name, f)
    -- Inset by the border width so a chromed log's text never sits on its own hairline. A
    -- frameless log insets by the same amount, which keeps the text position stable across a
    -- chrome flip -- otherwise every line would shift by a pixel on hover.
    --
    -- PLUS the concept's own inner padding (`.log { padding: 5px 7px }`), which is why the text does
    -- not run against the glass edge there. Added ON TOP of the border inset rather than replacing it,
    -- so the chrome-flip stability above still holds: both states inset by the same total.
    local inset = T:GetToken("borderWidth") or 1
    local padX = T:GetToken("spaceSm") or 8
    local padY = T:GetToken("spaceXs") or 4
    box:Add(log, { inset = { left = inset + padX, right = inset + padX,
                             top = inset + padY, bottom = inset + padY } })

    -- Hyperlinks: without this the client never hit-tests a link, and item links look perfect
    -- and are dead to the click.
    --
    -- EnableMouse is the OTHER half and is not optional. A ScrollingMessageFrame is a Frame
    -- subtype, so it takes no mouse input until told to -- and `SetHyperlinksEnabled` alone cannot
    -- help, because the click never reaches the frame to be hit-tested. This shipped missing: links
    -- rendered correctly, the scripts below were installed, and clicking a linked item in game did
    -- nothing. It passed every spec because a spec that invokes `OnHyperlinkClick` by hand skips the
    -- delivery this line is responsible for.
    log:EnableMouse(true)
    log:SetHyperlinksEnabled(true)
    log:SetInsertMode("BOTTOM")
    log:SetMaxLines(props.maxLines or 512)
    -- A bare ScrollingMessageFrame CENTRES every line -- Blizzard's own chat frames read left
    -- only because their XML template says so. Left unset, this shipped: a single line sat 135
    -- units right of the chip beneath it, which is half the slack in a 460-wide frame. It is
    -- stated here rather than offered as a prop because a centred chat log is not a look anyone
    -- wants; a message log is a column of text with a left edge.
    log:SetJustifyH("LEFT")

    local id = "msglog_" .. tostring(f)
    handle = setmetatable({
        _f = f, _log = log, _box = box, _eid = id, _wash = wash,
        _sizeKey = props.size or "md",
        _chrome  = props.chrome and true or false,
    }, LogMeta)

    -- Scrolling. The component owns the wheel for the same reason it owns the hover reveal: a log
    -- with ScrollUp/ScrollDown that nothing can reach is not a scrollable log. It shipped with the
    -- methods and no gesture, so the buffer was effectively write-only -- history was in there and
    -- unreachable. A wheel script in plugin code would also be forbidden (UI_SIGNALS.md), so this is
    -- the only correct home for it.
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(_, delta)
        -- Shift jumps to an end rather than paging, which is what Blizzard's own chat does — worth
        -- matching exactly, because it is muscle memory rather than a preference.
        local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
        if delta > 0 then
            if shift then handle:ScrollToTop() else handle:ScrollUp() end
        else
            if shift then handle:ScrollToBottom() else handle:ScrollDown() end
        end
    end)

    log:SetScript("OnHyperlinkClick", function(_, link, text, button)
        S:Emit(handle, SIG.HYPERLINK_CLICK, link, text, button)
    end)
    log:SetScript("OnHyperlinkEnter", function(_, link)
        S:Emit(handle, SIG.HYPERLINK_ENTER, link)
    end)
    log:SetScript("OnHyperlinkLeave", function()
        S:Emit(handle, SIG.HYPERLINK_LEAVE)
    end)

    -- Hovering reveals a faded buffer, and the component owns that rather than emitting and hoping
    -- an owner wires it: a log whose history cannot be read by looking at it is not a fading log,
    -- it is a broken one. The signals are emitted as well, so an owner can still react.
    log:SetScript("OnEnter", function()
        if handle._faded then handle:SetFaded(false) end
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    -- Deliberately does NOT re-fade on leave: per-line fading already expires the lines again on its
    -- own clock, and re-hiding them the instant the cursor left would make a deliberate hover
    -- useless -- you would lose the text before you finished reading it.
    log:SetScript("OnLeave", function()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)

    handle:SetFading(props.fading and true or false, props.timeVisible, props.fadeDuration)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
