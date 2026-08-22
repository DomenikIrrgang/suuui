-- Accordion: a collapsible group of rows behind a clickable header, with an accent rail
-- down its left edge while it is open.
--
-- Rows go into GetBody(). Exclusivity is NOT here -- "only one open at a time" is policy,
-- and it belongs to AccordionGroup at the bottom of this file, which also owns the single
-- animation that drives a close and an open together.
--
-- Four things are load-bearing, and each is a trap this codebase has already paid for
-- once somewhere else:
--
--   * The body's window is a SEPARATE container with an explicit height, never the body
--     itself. A container with no height of its own HUGS its content and re-states that
--     height from inside Layout() -- on the very tick an animation set it. Animating a
--     hugging container is a fight the hug always wins.
--   * The window is SHOWN before it is animated, and hidden only once a close finishes.
--     The animator skips intermediate writes on a hidden target and flow layout skips a
--     hidden child outright, so a reveal driven while hidden simply jumps.
--   * The root column's gap is ZERO, with the spacing carried inside the header and the
--     body instead. A collapsed window contributes no height either way, but a SHOWN one
--     would still contribute a gap -- which then vanishes the instant it is hidden,
--     popping every group below it by spaceXs at the end of every close.
--   * The header and the body surface are SIBLINGS painted with the same token. Both
--     carry opacityPanel, so nesting one inside the other would blend the fill against
--     itself and put a visible seam across a group that is meant to read as one surface.
local S = SuuUI.UISignals
local ipairs, max = ipairs, math.max

-- Expand/collapse affordance, in ASCII. Components/Dropdown.lua spends a plain "v" on its
-- arrow for the same reason: the client's faces do not reliably carry the geometric-shape
-- triangles (U+25B8 and friends), and a face missing one draws a box or nothing at all. A
-- glyph that only renders in a mockup is worse than a letter that renders everywhere.
local GLYPH = { [true] = "v", [false] = ">" }

--- Signals emitted by an AccordionGroup.
SuuUI.Components.ACCORDION_SIGNALS = {
    -- Args: openAccordion|nil, previouslyOpen|nil  (nil = the group is fully collapsed)
    OPEN_CHANGED = "accordion.open_changed",
}

local AccMeta = {}
AccMeta.__index = AccMeta

-- Floored at one physical pixel, like every other line in the addon: a rail that rounds
-- away is the only cue distinguishing the open group from the closed ones.
local function railWidth()
    return SuuUI.Pixel.Line(SuuUI.Theme:GetToken("sizeRail") or 2)
end

-- The height the body wants right now. Measured rather than read back off the frame, so a
-- row that has grown (a font token, a dependency ungreying a control) is accounted for
-- even before the client has laid the body out.
--
-- Cached for the duration of a tween. GetContentSize allocates a table on every call
-- (FlowLayout.visibleChildren), and SetReveal runs on every animation tick — so measuring
-- live here put an allocation in an OnUpdate path for a number that cannot change while
-- the tween runs. The body's own SIZE_CHANGED re-syncs the window whenever it can.
function AccMeta:_bodyHeight()
    if self._animating and self._animBodyH then return self._animBodyH end
    local _, h = self._body:GetContentSize()
    h = h or 0
    if self._animating then self._animBodyH = h end
    return h
end

-- Both tween paths go through these: the standalone SetOpen below and AccordionGroup's own
-- one tween. `_animating` gates the body-resize handler, which would otherwise snap the
-- reveal to full mid-transition — and it was previously set ONLY by SetOpen, leaving the
-- guard dead on the group path, which is the one the settings UI actually uses.
function AccMeta:_beginTween()
    self._animating = true
    self._animBodyH = nil
end

function AccMeta:_endTween()
    self._animating = false
    self._animBodyH = nil
    -- A body resize that arrived DURING the tween was deliberately ignored, so the window
    -- is sitting at the height the tween aimed at — which that resize has since made stale.
    -- Catching up here is what makes ignoring it safe rather than lossy. Only when open: a
    -- member the tween was closing must stay closed.
    if self._open then self:SetReveal(1) end
end

-- The chevron column is the WIDER of the two glyphs, not the current one, so swapping
-- them never shifts the label sideways by the difference. Box rather than Measure: this
-- number becomes the font string's own box, and the client truncates with zero tolerance.
function AccMeta:_chevWidth()
    local fs = self._chev:GetFrame()
    local font, size, flags = fs:GetFont()
    if not (font and size) then return 0 end
    local B = SuuUI.TextMetrics.Box
    -- Each width is captured into a local rather than measured inline. Box returns
    -- (width, height) and Lua expands the LAST call in an argument list, so
    -- max(B(a), B(b)) silently compares w1, w2 AND h2 — the glyph's line height, which
    -- wins at every font size the theme ships and sized this column at 17 instead of 8.
    local openW   = B(GLYPH[true],  font, size, flags)
    local closedW = B(GLYPH[false], font, size, flags)
    return SuuUI.Pixel.Ceil(max(openW, closedW))
end

-- Transient state only: surface tint, label colour, glyph, rail visibility. Never rebuilds
-- a backdrop table, so hovering costs nothing.
function AccMeta:_paint()
    SuuUI.Backdrop.SetBg(self._header, self._hovered and "colorBgHover" or "colorBgAlt")
    self._label:SetColor(self._open and "text" or "muted")
    self._chev:SetColor(self._open and "accent" or "muted")
    self._chev:SetText(GLYPH[self._open])
    self:_paintRail()
end

-- The only part of the paint that moves during a reveal, split out because SetReveal runs
-- on every animation tick: a full _paint re-resolves three colour tokens and rewrites the
-- chevron, none of which can change while the tween runs.
--
-- Tied to the REVEAL, not to the logical state: the rail has to stay lit for the whole of a
-- close, and a body still 80% visible with no rail beside it reads as a glitch.
function AccMeta:_paintRail()
    if self._reveal > 0 then self._rail:Show() else self._rail:Hide() end
end

--- Paints the body window at a fraction of the body's full height.
-- The single write path for the reveal geometry, so a snap, an animation tick and a
-- row-height change all travel the same route. Emits nothing itself: the window is a
-- container, so its own resize propagates to the column and onward to the page.
-- @param f number  0..1; 0 collapses the group, 1 opens it fully
function AccMeta:SetReveal(f)
    f = f < 0 and 0 or (f > 1 and 1 or f)
    self._reveal = f
    local clip = self._clip
    if f <= 0 then
        -- Hidden, not zero-height: flow skips a hidden child entirely, so a collapsed
        -- group contributes neither height nor gap, and a zero-sized frame is a shape the
        -- client is entitled to treat oddly.
        if clip:IsShown() then clip:Hide() end
    else
        -- Ceil, not Floor: this is a window onto content, and one unit short clips the
        -- last row's descenders at full reveal.
        if not clip:IsShown() then
            clip:Show()
            -- Everything inside was built while this window was HIDDEN, where the client
            -- gives a frame no rect — so every row measured itself blind, and Container's
            -- own OnShow hook cannot fix it because OnShow does not fire for a descendant
            -- when an ANCESTOR is shown. Left alone this draws as a blank band at the top
            -- of a section the first time it is opened, with one row's worth of space
            -- reserved and nothing in it. Re-measure now that the subtree has a rect;
            -- once only, since the window stays shown afterwards.
            self._animBodyH = nil
            self._body:LayoutTree()
        end
        clip:SetHeight(SuuUI.Pixel.Ceil(self:_bodyHeight() * f))
    end
    self:_paintRail()
end

--- Returns the current reveal fraction (0 collapsed, 1 fully open).
-- @return number
function AccMeta:GetReveal()
    return self._reveal
end

--- Sets the logical open state and repaints the header. Does NOT touch the geometry.
-- For an owner that drives the reveal itself -- AccordionGroup animates two members from
-- one tween, so it must be able to flip the state without each member starting a tween of
-- its own. Standalone callers want SetOpen instead.
-- @param open bool
function AccMeta:SetOpenState(open)
    self._open = open == true
    self:_paint()
end

--- Opens or closes the group, animating the reveal.
-- Silent by contract: only a header click emits, so driving this from a watcher or a
-- group cannot loop back into whatever asked for it.
-- @param open bool
-- @param opts table|nil  { animate = false } to snap instead of animating
function AccMeta:SetOpen(open, opts)
    open = open == true
    self:SetOpenState(open)

    -- animFast, the token every panel reveal already uses: Dropdown's panel, Modal,
    -- Tooltip, Window. A section opening is the same gesture as a dropdown opening, so
    -- it shares the timing rather than inventing one. 0 degrades to a snap.
    local dur = SuuUI.Theme:GetToken("animFast") or 0
    local animate = not (opts and opts.animate == false)
    -- No clipping means the body's rows would draw straight over the group below for the
    -- whole animation, which is worse than not animating. Same degradation as
    -- Backdrop.Pill falling back to square caps where there is no mask API.
    if not (animate and dur > 0 and self._clips) then
        self:SetReveal(open and 1 or 0)
        return
    end

    local from, to = self._reveal, open and 1 or 0
    if from == to then return end
    self:_beginTween()
    SuuUI.Anim:New({
        target = self, property = "value",
        apply  = function(t) self:SetReveal(from + (to - from) * t) end,
        from   = 0, to = 1, duration = dur, easing = "easeOut",
        onDone = function() self:_endTween() end,
    }):Play()
end

--- Returns whether the group is logically open.
-- @return bool
function AccMeta:IsOpen()
    return self._open
end

--- Returns the container rows are added to.
-- @return table  Container handle
function AccMeta:GetBody()
    return self._body
end

--- Returns the clickable header frame.
-- @return frame
function AccMeta:GetHeader()
    return self._header
end

--- Returns the header label.
-- @return string
function AccMeta:GetLabel()
    return self._label:GetText() or ""
end

--- Sets the header label.
-- @param text string
function AccMeta:SetLabel(text)
    self._label:SetText(text)
    S:Emit(self, S.SIGNALS.TEXT_CHANGED, text)
end

function AccMeta:Show()
    self._root:Show()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
end

function AccMeta:Hide()
    self._root:Hide()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

function AccMeta:ApplyTheme()
    local T, B = SuuUI.Theme, SuuUI.Backdrop
    B.Apply(self._header, { bg = "colorBgAlt", border = false })
    -- inset 0: a borderless surface must cover its whole box, or the body sits a pixel
    -- inside the header's fill and the two read as different colours where they meet.
    B.Apply(self._clip:GetFrame(), { bg = "colorBgAlt", border = false, inset = 0 })

    local c = T:GetToken("colorAccent")
    if c then self._rail:SetColorTexture(c[1], c[2], c[3], c[4]) end

    -- Owned handles are applied explicitly: the bus fires listeners newest-first, so
    -- their own subscriptions may not have run and this would measure the old font.
    self._chev:ApplyTheme()
    self._label:ApplyTheme()

    -- Everything token-driven is re-derived, not read once at construction.
    local rw = railWidth()
    self._root:SetPadding({ left = rw })
    self._railBox:SetChildProps(self._rail, { align = "start", valign = "stretch", width = rw })
    self._headerBox:SetChildProps(self._chev, { width = self:_chevWidth() })
    self._header:SetHeight(T:GetControlHeight("sizeRow"))

    local gap = T:GetToken("spaceXs") or 4
    self._headerBox:SetGap(gap)
    self._headerBox:SetPadding({ left = T:GetToken("spaceSm") or 8,
                                 right = T:GetToken("spaceSm") or 8 })
    self._body:SetGap(gap)
    self._body:SetPadding({ top = gap, bottom = T:GetToken("spaceSm") or 8 })

    self:_paint()
    -- A font or spacing edit moves every row, so an open window has to re-derive or it
    -- clips the last one. Re-stating the same fraction is what recomputes the height.
    if self._reveal > 0 then self:SetReveal(self._reveal) end
    -- The header is a raw frame, so its resize emits no signal the column could hear.
    self._root:Layout()
end

function AccMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    SuuUI.Anim:CancelAll(self)
    -- Adopted containers, so neither is reachable from the column's cascade.
    self._headerBox:Destroy()
    self._railBox:Destroy()
    -- The window's container ADOPTED its frame, and an adopted container deliberately does
    -- not hide the frame it lays out — so the cascade below stops at the window and the
    -- rows inside keep their own shown flag. Same reason Divider hides its frame by hand.
    self._clip:GetFrame():Hide()
    -- Cascades: the window, the body, and every row a caller added to it.
    self._root:Destroy()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize. Show and Hide are defined
-- above and survive: they drive the column so a parent container hears the change.
SuuUI.Components.InstallBase(AccMeta, "_f")

-- Deliberately NO InstallEnable. An accordion holds controls rather than being one: there
-- is no value to grey, and a root-frame fade would multiply with the fade of any disabled
-- row inside it (0.40 x 0.40 = 0.16). Same call as Divider and ScrollFrame -- absent, so
-- Dependency.Bind's `if target.SetEnabled` guard skips it honestly instead of believing a
-- stub greyed something.

--- Creates a collapsible group of rows.
-- Emits CLICKED (button) from the header, plus SIZE_CHANGED, VISIBILITY_CHANGED,
-- MOUSE_ENTER, MOUSE_LEAVE, TEXT_CHANGED. Does NOT open itself on click -- connect
-- CLICKED, or hand it to an AccordionGroup.
-- @param props table   { label, open }
-- @param parent frame
-- @return table  Accordion handle
function SuuUI.Components.Accordion(props, parent)
    local T   = SuuUI.Theme
    local rw  = railWidth()
    local gap = T:GetToken("spaceXs") or 4
    local pad = T:GetToken("spaceSm") or 8

    -- The root IS the column, not a plain frame wrapping one, so it hugs its own content:
    -- a container built with a parent and no height hugs, while one adopting a host frame
    -- never does. Gap 0 -- see the header comment.
    local root = SuuUI.Layout:CreateContainer({
        parent  = parent,
        layout  = "flow",
        dir     = "vertical",
        gap     = 0,
        padding = { left = rw },
    })
    local rootFrame = root:GetFrame()

    -- A second container on the same frame places the rail: a stack, so it spans whatever
    -- height the column settles at. It lives inside the column's left padding, so it never
    -- overlaps the header or the body and cannot blend against their translucent fills.
    local railBox = SuuUI.Layout:CreateContainer({ host = rootFrame, layout = "stack" })
    local rail = rootFrame:CreateTexture(nil, "ARTWORK")
    railBox:Add(rail, { align = "start", valign = "stretch", width = rw })

    local header = CreateFrame("Frame", nil, rootFrame, "BackdropTemplate")
    header:SetHeight(T:GetControlHeight("sizeRow"))
    header:EnableMouse(true)
    root:Add(header, { width = "fill" })

    local headerBox = SuuUI.Layout:CreateContainer({
        host    = header,
        layout  = "flow",
        dir     = "horizontal",
        gap     = gap,
        align   = "center",
        padding = { left = pad, right = pad },
    })

    local chev  = SuuUI.Components.Text({ text = GLYPH[false], size = "md",
                                          color = "muted", justify = "CENTER" }, header)
    local label = SuuUI.Components.Text({ text = props.label or "", size = "md",
                                          color = "muted", justify = "LEFT" }, header)
    -- Fixed column for the glyph, filled label: the real width is measured in ApplyTheme,
    -- which runs before this constructor returns.
    headerBox:Add(chev,  { width = 0 })
    headerBox:Add(label, { width = "fill" })

    -- The window. Its own frame rather than a container-created one: the body surface is a
    -- BACKDROP, and Layout:CreateContainer builds a plain Frame — the client only puts
    -- SetBackdrop on a frame created from BackdropTemplate, so painting a container's own
    -- frame raises and takes the whole page build with it. Adopted rather than parented,
    -- which also buys the explicit height this needs: an adopted container never hugs.
    local clipFrame = CreateFrame("Frame", nil, rootFrame, "BackdropTemplate")
    -- One unit, not zero: a structural placeholder for a frame that SetReveal hides on
    -- the next line, and a zero-sized frame is a shape the client may treat oddly.
    clipFrame:SetHeight(1)
    local clip = SuuUI.Layout:CreateContainer({
        host = clipFrame, layout = "flow", dir = "vertical", gap = 0,
    })
    root:Add(clip, { width = "fill" })
    -- Feature-detected rather than assumed. It is present on this client generation --
    -- WeakAurasOptions and ChonkyCharacterSheet's Classic module both call it unguarded --
    -- but where it is missing the reveal degrades to a snap instead of spilling rows over
    -- the group below.
    local clips = type(clipFrame.SetClipsChildren) == "function"
    if clips then clipFrame:SetClipsChildren(true) end

    -- Added with width = "fill" so the body tracks the window's width, and with no height
    -- so it keeps its own hugged one. Flow anchors the first child at the TOP, which is
    -- what makes a shrinking window hide the BOTTOM rows rather than squashing all of them.
    local body = SuuUI.Layout:CreateContainer({
        parent  = clipFrame,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        padding = { top = gap, bottom = pad },
    })
    clip:Add(body, { width = "fill" })

    local id = "accordion_" .. tostring(rootFrame)
    local handle = setmetatable({
        _f         = rootFrame,
        _root      = root,
        _railBox   = railBox,
        _rail      = rail,
        _header    = header,
        _headerBox = headerBox,
        _chev      = chev,
        _label     = label,
        _clip      = clip,
        _body      = body,
        _clips     = clips,
        _eid       = id,
        _open      = props.open == true,
        _hovered   = false,
        _reveal    = 0,
        _animating = false,
    }, AccMeta)

    -- The column's size is the accordion's size. A parent container connects to whatever
    -- it was handed, so a caller that adds the HANDLE hears nothing unless this re-emits.
    S:Connect(root, S.SIGNALS.SIZE_CHANGED, function(w, h)
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    -- A row appearing, vanishing or growing changes the body's height while the group is
    -- open, and the window is not derived from it, so it has to follow. Skipped mid-tween,
    -- where each tick already re-measures.
    S:Connect(body, S.SIGNALS.SIZE_CHANGED, function()
        if handle._open and not handle._animating then handle:SetReveal(1) end
    end)

    header:SetScript("OnMouseUp", function(_, btn)
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)
    header:SetScript("OnEnter", function()
        handle._hovered = true
        handle:_paint()
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    header:SetScript("OnLeave", function()
        handle._hovered = false
        handle:_paint()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)

    handle:ApplyTheme()
    -- Snap to the initial state: an animation at construction would run during the
    -- PLAYER_LOGIN pass for a page the player may never open.
    handle:SetReveal(handle._open and 1 or 0)
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end

----------------------------------------------------------------------------------
-- AccordionGroup
----------------------------------------------------------------------------------

local GrpMeta = {}
GrpMeta.__index = GrpMeta

--- Adds a member. The group takes over its header click.
-- @param acc table  Accordion handle
-- @return table  The same handle, for chaining
function GrpMeta:Add(acc)
    self._members[#self._members + 1] = acc
    self._conns[acc] = S:Connect(acc, S.SIGNALS.CLICKED, function()
        self:Open(acc)
    end)
    return acc
end

--- Opens one member and closes whichever was open, in a single animation.
-- Passing the member that is already open collapses it: "one at a time" does not mean
-- "one always", and an all-closed page is how a player scans a long one for the group
-- they want. Pass nil to collapse everything.
-- @param acc table|nil  Member to open
-- @param opts table|nil { animate = false } to snap
function GrpMeta:Open(acc, opts)
    local prev = self._open
    if acc and acc == prev then acc = nil end
    if acc == prev then return end
    self._open = acc

    for _, m in ipairs(self._members) do m:SetOpenState(m == acc) end

    -- animFast: see SetOpen. A caller may still override per group via opts.duration.
    local dur = self._duration or SuuUI.Theme:GetToken("animFast") or 0
    local animate = not (opts and opts.animate == false)
    -- Every member must be able to clip, or the one that cannot would spill its rows over
    -- the group below for the whole tween.
    local canAnimate = animate and dur > 0
    for _, m in ipairs(self._members) do
        if not m._clips then canAnimate = false end
    end

    if not canAnimate then
        SuuUI.Anim:CancelAll(self)
        -- Every member, not just prev and acc: a snap that lands on top of an interrupted
        -- tween has the same stranding to clean up that the animated path does.
        for _, m in ipairs(self._members) do m:SetReveal(m == acc and 1 or 0) end
        S:Emit(self, SuuUI.Components.ACCORDION_SIGNALS.OPEN_CHANGED, acc, prev)
        return
    end

    -- ONE tween for the whole group. Two separate height animations would write twice per
    -- tick and re-flow the whole page twice per frame; this moves every member in a single
    -- pass, perfectly in step.
    --
    -- EVERY member is driven, not just `prev` and `acc`. Play() pre-empts any running
    -- animation on (group, "value"), so a member the previous tween was still closing —
    -- click header 1, then 2, then 3 mid-transition — would be referenced by nothing and
    -- stay stranded at a fractional reveal: window shown, height still contributed to the
    -- page, while IsOpen() reported closed. The scratch table is reused across calls, so
    -- arbitration costs no allocation per click.
    local from = self._from
    for _, m in ipairs(self._members) do
        from[m] = m:GetReveal()
        -- Every member is being driven, so every member is mid-tween: the body-resize
        -- handler must stand down on all of them, not just the two the click named.
        m:_beginTween()
    end
    SuuUI.Anim:New({
        target = self, property = "value",
        apply  = function(t)
            for _, m in ipairs(self._members) do
                -- Each member's `from` is its CURRENT reveal, so interrupting a
                -- half-finished transition continues from where it actually is rather
                -- than snapping, and a stranded member glides home instead of jumping.
                local f  = from[m] or 0
                local to = (m == acc) and 1 or 0
                m:SetReveal(f + (to - f) * t)
            end
        end,
        from = 0, to = 1, duration = dur, easing = self._easing or "easeOut",
        onDone = function()
            for _, m in ipairs(self._members) do m:_endTween() end
        end,
    }):Play()

    S:Emit(self, SuuUI.Components.ACCORDION_SIGNALS.OPEN_CHANGED, acc, prev)
end

--- Returns the open member, or nil when the group is fully collapsed.
-- @return table|nil
function GrpMeta:GetOpen()
    return self._open
end

--- Returns the members in the order they were added.
-- @return table  Array of Accordion handles
function GrpMeta:GetMembers()
    return self._members
end

--- Drops the group's own subscriptions and cancels any transition in flight.
-- Does NOT destroy the members: they are laid out by a container, and that container's
-- own teardown owns them.
function GrpMeta:Destroy()
    SuuUI.Anim:CancelAll(self)
    for acc, connId in pairs(self._conns) do
        S:Disconnect(acc, S.SIGNALS.CLICKED, connId)
    end
    self._conns   = {}
    self._members = {}
    -- Cleared too: it keys on member handles, which are about to be destroyed by whichever
    -- container owns them.
    self._from    = {}
    self._open    = nil
    S:DisconnectAll(self)
end

--- Creates an accordion group: at most one member open at a time.
--
-- Policy lives here rather than in Accordion, and so does the MOTION -- see Open. The
-- group is not a widget: it owns no frame, is never laid out, and exists only to arbitrate
-- between members.
-- Emits ACCORDION_SIGNALS.OPEN_CHANGED (openAccordion|nil, previouslyOpen|nil).
-- @param opts table|nil  { duration = seconds, easing = string }
-- @return table  Group handle
function SuuUI.Components.AccordionGroup(opts)
    opts = opts or {}
    return setmetatable({
        _members  = {},
        _conns    = {},
        -- Reused across calls: the tween reads each member's starting reveal from here, so
        -- arbitration allocates nothing per click.
        _from     = {},
        _open     = nil,
        _duration = opts.duration,
        _easing   = opts.easing,
    }, GrpMeta)
end
