-- Public harness API used by spec files.
--
-- Run:  lua Tests/run.lua                      (from the addon root)
--       lua Tests/run.lua --filter Button
--       lua Tests/run.lua Tests/spec/11_button_spec.lua -v
--
-- A spec file looks like this:
--
--   local H = require("harness")
--
--   describe("Components.Thing", function()
--       local host
--       before_each(function()
--           H.setup()                 -- fresh addon in a fresh simulated client
--           host = H.parent(300, 200)  -- a parent frame with real geometry
--       end)
--
--       it("hugs its label", function()
--           local thing = H.C.Thing({ label = "Go" }, host)
--           H.expectSize(thing, H.textWidth("Go", H.token("fontSizeMd")) + 18, nil)
--       end)
--
--       it("centres its label", function()
--           local thing = H.mount(H.C.Thing({ label = "Go" }, host))
--           H.expectCenteredH(thing._label, thing:GetFrame())
--       end)
--   end)
--
-- Two rules make component geometry assertions work:
--
--   * Components never position themselves; a container does. A component built for a
--     test and never added to one has no anchors, so every position inside it is
--     unresolvable. Either add it to a container or call H.mount(handle).
--   * Derive expected pixel values from tokens and H.textWidth/H.lineHeight rather than
--     hardcoding them, so the assertion survives a theme change.
--
-- Assertions:  expect(v).eq/.near/.gt/.gte/.lt/.lte/.between/.deepEq/.truthy/.falsy
--              .isNil/.notNil/.matches/.contains/.len/.throws/.notThrows, and .as("note")
-- Geometry:    H.box H.offset H.expectBox H.expectSize H.expectOffset H.expectInside
--              H.expectNoOverlap H.expectStackedVertically H.expectRowHorizontally
--              H.expectCenteredH H.expectCenteredV H.expectTokenColor H.expectDrawsAbove
-- Text:        H.textWidth H.textBox H.textHeight H.lineHeight H.fontOf H.expectTextNotClipped
--              (each measuring helper takes an optional font path: faces differ)
-- Input:       H.click H.forceClick H.mouseDown H.mouseUp H.hover H.unhover H.scroll
--              H.dragResize H.key H.typeText H.pressEnter H.pressEscape H.cursor
--              H.cursorOn H.setMouseDown H.mods
-- Spellcasts:  H.startCast H.startChannel H.stopCast H.finishCast H.interruptCast
--              H.failCast H.stopChannel H.delayCast H.updateChannel H.combatLogInterrupt
--              H.combatLogSpell
-- Observation: H.signalSpy H.eventSpy H.debugLog H.tick H.runAnimations
--
-- H.setup() reloads the whole addon into a fresh sandbox against a fresh simulated
-- client, so every test starts from a known state.
local geometry = require("harness.wow.geometry")
local state    = require("harness.wow.state")
local font     = require("harness.wow.font")
local addon    = require("harness.addon")

local M = {}

M.geometry = geometry
M.state    = state
M.font     = font

M.root = "."

----------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------

--- Loads a fresh addon instance. Returns the SuuUI namespace.
-- screenWidth/Height are unit space (always 768 tall in the real client);
-- physicalWidth/Height are pixels and drive the pixel grid. They default to unit space,
-- which gives mult == 1 and integer snapping. Pass physicalHeight = 1080 to exercise a
-- fractional grid.
--
-- Status bar fill transitions default to "instant" for the same reason: a value written
-- under the shipped "smooth" default arrives over several frames, so a spec asserting a
-- fill width straight after SetValue would be measuring a value still in transit. The
-- simple configuration by default, the real one where the spec is about it — pass
-- barTransitions = true for that.
-- @param opts table  { boot = true, debug = false, screenWidth, screenHeight,
--                      physicalWidth, physicalHeight, uiScale, barTransitions,
--                      castBarGlobals }
-- @return table  SuuUI
function M.setup(opts)
    opts = opts or {}
    state.screenWidth  = opts.screenWidth  or 1024
    state.screenHeight = opts.screenHeight or 768
    state.uiScale      = opts.uiScale or 1
    state.physicalWidth  = opts.physicalWidth  or state.screenWidth
    state.physicalHeight = opts.physicalHeight or state.screenHeight
    -- Which player-cast-bar globals this client admits to having. nil means both
    -- generations, which is the default the CastBars plugin has to cope with. Assigned on
    -- every setup so a spec that narrows it cannot leak into the next one.
    state.castBarGlobals = opts.castBarGlobals

    local loaded = addon.load({ root = M.root, boot = opts.boot, debug = opts.debug })
    M.env      = loaded.env
    M.SuuUI    = loaded.SuuUI
    M.wow      = loaded.wow
    M.UIParent = loaded.wow.UIParent
    M.Minimap  = loaded.wow.Minimap
    M.C        = loaded.SuuUI.Components
    M.S        = loaded.SuuUI.UISignals
    M.T        = loaded.SuuUI.Theme
    M.Layout   = loaded.SuuUI.Layout
    if not opts.barTransitions then
        M.SuuUI.Anim.Transitions:SetDefault("instant")
    end
    return M.SuuUI
end

--- Fires a WoW event to every frame registered for it.
function M.fireEvent(event, ...)
    return M.wow.fireEvent(event, ...)
end

--- Returns a themed token value.
-- @param key string
function M.token(key) return M.T:GetToken(key) end

--- Returns the token-derived height for a text-bearing control.
function M.controlHeight(sizeKey, fontKey) return M.T:GetControlHeight(sizeKey, fontKey) end

--- Creates a plain parent frame with real geometry, anchored to the screen top-left.
-- @param w number
-- @param h number
-- @return frame
function M.parent(w, h)
    local f = M.env.CreateFrame("Frame", nil, M.UIParent)
    f:SetSize(w or 400, h or 300)
    f:SetPoint("TOPLEFT", M.UIParent, "TOPLEFT", 0, 0)
    return f
end

--- Unwraps a component handle or container to its frame. Passes frames through.
-- @param target table
-- @return table
function M.frameOf(target)
    if type(target) == "table" and target.GetFrame then return target:GetFrame() end
    return target
end

--- Anchors a component inside its parent so its geometry resolves.
--
-- Components never position themselves: in real code a container does it. A component
-- built for a test and never added to a container therefore has no anchors, and every
-- position inside it is unresolvable. Mounting it through an anchor container is what
-- the addon does, so the resulting geometry is the real thing.
-- @param target table   Component handle, container, or frame
-- @param opts table     { x, y, parent, width, height }
-- @return table  The target, for chaining
function M.mount(target, opts)
    opts = opts or {}
    local f = M.frameOf(target)
    local parent = opts.parent and M.frameOf(opts.parent) or f:GetParent()
    assert(parent, "harness: mount needs a parent frame")

    local box = M.Layout:CreateContainer({ host = parent, layout = "anchor" })
    box:Add(f, { anchor = {
        point = "TOPLEFT", relativePoint = "TOPLEFT",
        x = opts.x or 0, y = opts.y or 0,
        width = opts.width, height = opts.height,
    } })
    return target
end

----------------------------------------------------------------------------------
-- Simulated frame loop
----------------------------------------------------------------------------------

--- Runs one simulated frame.
-- @param dt number  Seconds (default 1/60)
function M.tick(dt)
    state.clock = (state.clock or 0) + (dt or 1 / 60)
    state.tick(dt or 1 / 60)
end

--- Advances far enough for every queued animation, including chained sequences, to
--- finish. Sequences enqueue their next step during a tick, so several passes run.
-- @param passes number  Default 8
function M.runAnimations(passes)
    for _ = 1, passes or 8 do M.tick(10) end
end

----------------------------------------------------------------------------------
-- Spellcasts
--
-- The client reports a cast through UnitCastingInfo / UnitChannelInfo and announces the
-- transitions through UNIT_SPELLCAST_* events. These helpers move both together, because
-- a spec that fires the event without moving the state (or the reverse) tests a situation
-- the client never produces.
----------------------------------------------------------------------------------

local function castRecord(opts)
    opts = opts or {}
    local nowMS = (state.clock or 0) * 1000
    local dur   = (opts.duration or 2.5) * 1000
    local start = opts.startTime or nowMS
    return {
        unit      = opts.unit or "player",
        name      = opts.name or "Fireball",
        text      = opts.text,
        texture   = opts.texture or "Interface\\Icons\\Spell_Fire_FlameBolt",
        startTime = start,
        endTime   = opts.endTime or (start + dur),
        castID    = opts.castID or "cast-1",
        spellId   = opts.spellId or 133,
        notInterruptible = opts.notInterruptible or false,
        isTradeSkill     = opts.isTradeSkill or false,
    }
end

--- Starts a cast and fires UNIT_SPELLCAST_START.
-- @param opts table  { unit, name, texture, duration, startTime, endTime, spellId,
--                      castID, notInterruptible, isTradeSkill }
-- @return table  The cast record, so a spec can read startTime/endTime back
function M.startCast(opts)
    local c = castRecord(opts)
    state.cast, state.channel = c, nil
    M.fireEvent("UNIT_SPELLCAST_START", c.unit, c.castID, c.spellId)
    return c
end

--- Starts a channel and fires UNIT_SPELLCAST_CHANNEL_START.
-- @param opts table  Same shape as startCast
-- @return table
function M.startChannel(opts)
    local c = castRecord(opts)
    state.channel, state.cast = c, nil
    M.fireEvent("UNIT_SPELLCAST_CHANNEL_START", c.unit, c.castID, c.spellId)
    return c
end

-- Clears the cast BEFORE firing, which is the order the client uses: by the time a stop
-- event arrives, UnitCastingInfo already reports nothing.
local function endCast(unit, event)
    local c = state.cast or state.channel
    local u = unit or (c and c.unit) or "player"
    local castID, spellId = c and c.castID, c and c.spellId
    state.cast, state.channel = nil, nil
    M.fireEvent(event, u, castID, spellId)
end

--- Ends a cast with UNIT_SPELLCAST_STOP.
function M.stopCast(unit) endCast(unit, "UNIT_SPELLCAST_STOP") end

--- Completes a cast with UNIT_SPELLCAST_SUCCEEDED.
function M.finishCast(unit) endCast(unit, "UNIT_SPELLCAST_SUCCEEDED") end

--- Delivers one SPELL_INTERRUPT combat log line against a unit.
--
-- The interrupter's name exists ONLY here: UNIT_SPELLCAST_INTERRUPTED does not carry it.
-- The payload is laid out exactly as CombatLogGetCurrentEventInfo() returns it, and is
-- cleared again afterwards, so code that reads it outside the handler gets nothing — the
-- same failure it would hit in game.
-- @param opts table  { unit, by, destName, spell, spellId, interrupted, interruptedId }
--   by:          the interrupter's name (source)
--   spell:       the interrupting spell (default "Counterspell")
--   interrupted: the spell that was stopped (extraSpell in the client's payload)
-- @return table  The payload delivered
function M.combatLogInterrupt(opts)
    opts = opts or {}
    local unit = opts.unit or "player"
    local payload = {
        state.clock or 0,                                   -- 1  timestamp
        "SPELL_INTERRUPT",                                  -- 2  subevent
        false,                                              -- 3  hideCaster
        "GUID-src-" .. tostring(opts.by or "interrupter"),  -- 4  sourceGUID
        opts.by or "Interrupter",                           -- 5  sourceName
        0, 0,                                               -- 6  sourceFlags, 7 raidFlags
        M.env.UnitGUID(unit),                               -- 8  destGUID
        opts.destName or "Testchar",                        -- 9  destName
        0, 0,                                               -- 10 destFlags, 11 raidFlags
        opts.spellId or 2139,                               -- 12 interrupting spell id
        opts.spell or "Counterspell",                       -- 13 interrupting spell name
        0,                                                  -- 14 school
        opts.interruptedId or 133,                          -- 15 extraSpellId
        opts.interrupted or "Fireball",                     -- 16 extraSpellName
        0,                                                  -- 17 extraSchool
    }
    payload.n = #payload
    state.combatLogEvent = payload
    M.fireEvent("COMBAT_LOG_EVENT_UNFILTERED")
    state.combatLogEvent = nil
    return payload
end

--- Delivers one spell-carrying combat log line.
--
-- This is the ONLY route by which a spell's school reaches the UI: no client API maps a
-- spell to its school, so anything that colours by school has to learn it here. The
-- subevent is a parameter because which one carries a given spell differs — a cast fires
-- SPELL_CAST_START, a channel never does and is only described by its ticks.
-- @param opts table  { unit, subevent, spellId, spell, school, destName }
--   unit:     the CASTER, whose GUID lands in sourceGUID (default "player")
--   subevent: default "SPELL_CAST_START"
--   school:   the school mask (default 0x04, Fire)
-- @return table  The payload delivered
function M.combatLogSpell(opts)
    opts = opts or {}
    local unit = opts.unit or "player"
    local payload = {
        state.clock or 0,                        -- 1  timestamp
        opts.subevent or "SPELL_CAST_START",     -- 2  subevent
        false,                                   -- 3  hideCaster
        M.env.UnitGUID(unit),                    -- 4  sourceGUID
        opts.sourceName or "Testchar",           -- 5  sourceName
        0, 0,                                    -- 6  sourceFlags, 7 raidFlags
        opts.destGUID or M.env.UnitGUID("target"),  -- 8  destGUID
        opts.destName or "Target",               -- 9  destName
        0, 0,                                    -- 10 destFlags, 11 raidFlags
        opts.spellId or 133,                     -- 12 spellId
        opts.spell or "Fireball",                -- 13 spellName
        opts.school or 0x04,                     -- 14 spellSchool
    }
    payload.n = #payload
    state.combatLogEvent = payload
    M.fireEvent("COMBAT_LOG_EVENT_UNFILTERED")
    state.combatLogEvent = nil
    return payload
end

--- Interrupts a cast with UNIT_SPELLCAST_INTERRUPTED.
--
-- Pass `by` to also deliver the SPELL_INTERRUPT combat log line, which is the only source
-- of the interrupter's name. The client does not guarantee which of the two arrives first,
-- so `logAfter` produces the other order — anything that correlates them has to survive
-- both.
-- @param opts nil|string|table  unit token, or { unit, by, logAfter }
function M.interruptCast(opts)
    local unit, by, logAfter
    if type(opts) == "string" then
        unit = opts
    elseif type(opts) == "table" then
        unit, by, logAfter = opts.unit, opts.by, opts.logAfter
    end
    local active = state.cast or state.channel
    unit = unit or (active and active.unit) or "player"
    local spellName = active and active.name

    if by and not logAfter then
        M.combatLogInterrupt({ unit = unit, by = by, interrupted = spellName })
    end
    endCast(unit, "UNIT_SPELLCAST_INTERRUPTED")
    if by and logAfter then
        M.combatLogInterrupt({ unit = unit, by = by, interrupted = spellName })
    end
end

--- Fails a cast with UNIT_SPELLCAST_FAILED.
function M.failCast(unit) endCast(unit, "UNIT_SPELLCAST_FAILED") end

--- Ends a channel with UNIT_SPELLCAST_CHANNEL_STOP.
function M.stopChannel(unit) endCast(unit, "UNIT_SPELLCAST_CHANNEL_STOP") end

--- Pushes a cast's end time out and fires UNIT_SPELLCAST_DELAYED, as spell pushback does.
-- @param seconds number  Added to the end time (default 0.5)
-- @param unit string
-- @return table|nil  The cast record, or nil when nothing is casting
function M.delayCast(seconds, unit)
    local c = state.cast
    if not c then return nil end
    c.endTime = c.endTime + (seconds or 0.5) * 1000
    M.fireEvent("UNIT_SPELLCAST_DELAYED", unit or c.unit, c.castID, c.spellId)
    return c
end

--- Moves a channel's end time and fires UNIT_SPELLCAST_CHANNEL_UPDATE.
-- @param seconds number  Added to the end time; negative shortens the channel
-- @param unit string
-- @return table|nil
function M.updateChannel(seconds, unit)
    local c = state.channel
    if not c then return nil end
    c.endTime = c.endTime + (seconds or 0.5) * 1000
    M.fireEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unit or c.unit, c.castID, c.spellId)
    return c
end

----------------------------------------------------------------------------------
-- Input simulation
----------------------------------------------------------------------------------

--- Places the cursor, given coordinates in a frame's own space.
--
-- GetCursorPosition reports raw screen coordinates; a frame's GetLeft/GetBottom are in
-- that frame's space. The two differ by the frame's effective scale, so the space the
-- coordinates belong to has to be named. Defaults to UIParent, which is the same thing
-- only while nothing in the chain carries a scale.
-- @param x number
-- @param y number
-- @param space table  Optional frame or handle whose space x/y are expressed in
function M.cursor(x, y, space)
    local f = space and M.frameOf(space) or M.UIParent
    local scale = f:GetEffectiveScale()
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    state.cursorX, state.cursorY = x * scale, y * scale
end

--- Places the cursor at the centre of a widget, in that widget's own space.
-- @param target table
function M.cursorOn(target)
    local f = M.frameOf(target)
    local cx, cy = f:GetCenter()
    assert(cx, "harness: cursorOn target has no resolvable position")
    M.cursor(cx, cy, f)
end

--- Sets a mouse button's held state, as IsMouseButtonDown reports it.
-- @param button string
-- @param down bool
function M.setMouseDown(button, down)
    state.mouseDown[button or "LeftButton"] = down and true or false
end

--- Sets modifier key state for IsControlKeyDown and friends.
-- @param mods table  { ctrl, alt, shift }
function M.mods(mods)
    mods = mods or {}
    state.ctrlDown  = mods.ctrl == true
    state.altDown   = mods.alt == true
    state.shiftDown = mods.shift == true
end

local function deliverable(f)
    return f and f:IsVisible() and f:IsMouseEnabled()
end

--- Presses and releases the mouse over a widget, as the client would.
-- Returns false without firing anything when the widget cannot receive mouse input,
-- which is how a disabled control behaves in game.
-- @param target table
-- @param button string  Default "LeftButton"
-- @return bool  Whether the click was delivered
function M.click(target, button)
    local f = M.frameOf(target)
    if not deliverable(f) then return false end
    button = button or "LeftButton"
    M.setMouseDown(button, true)
    f:_fire("OnMouseDown", button)
    M.setMouseDown(button, false)
    f:_fire("OnMouseUp", button)
    return true
end

--- Fires the click scripts regardless of mouse-enabled state, to exercise a
--- component's own internal guard rather than the client's input routing.
function M.forceClick(target, button)
    local f = M.frameOf(target)
    button = button or "LeftButton"
    f:_fire("OnMouseDown", button)
    f:_fire("OnMouseUp", button)
    return true
end

function M.mouseDown(target, button)
    local f = M.frameOf(target)
    if not deliverable(f) then return false end
    M.setMouseDown(button or "LeftButton", true)
    f:_fire("OnMouseDown", button or "LeftButton")
    return true
end

function M.mouseUp(target, button)
    local f = M.frameOf(target)
    if not deliverable(f) then return false end
    M.setMouseDown(button or "LeftButton", false)
    f:_fire("OnMouseUp", button or "LeftButton")
    return true
end

--- Drags a resize grip by a delta, the way the client resizes a frame: press the grip,
--- let the client move the edge, release. The client clamps the result to the frame's
--- resize bounds, so a drag past a bound simply stops there.
-- @param grip table    The grip widget that calls StartSizing
-- @param dw number     Width delta in pixels
-- @param dh number     Height delta in pixels
-- @return bool  Whether the drag was delivered
function M.dragResize(grip, dw, dh)
    local g = M.frameOf(grip)
    if not M.mouseDown(g) then return false end
    local f = g
    while f and not f._sizing do f = f:GetParent() end
    assert(f, "harness: dragResize found no frame sizing after OnMouseDown")
    f:_userResize(f:GetWidth() + (dw or 0), f:GetHeight() + (dh or 0))
    M.mouseUp(g)
    return true
end

function M.hover(target)
    local f = M.frameOf(target)
    if not deliverable(f) then return false end
    f:_fire("OnEnter")
    return true
end

function M.unhover(target)
    local f = M.frameOf(target)
    if not f then return false end
    f:_fire("OnLeave")
    return true
end

--- Sends a mouse wheel notch.
-- @param target table
-- @param delta number  1 up, -1 down
function M.scroll(target, delta)
    local f = M.frameOf(target)
    f:_fire("OnMouseWheel", delta or -1)
end

--- Sends a key press to a widget with keyboard input enabled.
-- @param target table
-- @param key string
-- @return bool  Whether the key was delivered
function M.key(target, key)
    local f = M.frameOf(target)
    if not (f:IsVisible() and f:IsKeyboardEnabled()) then return false end
    f:_fire("OnKeyDown", key)
    return true
end

--- Types into an Input handle the way a user does: focus, set text, fire the change.
-- @param inputHandle table  SuuUI Input component handle
-- @param text string
function M.typeText(inputHandle, text)
    local eb = inputHandle._eb or inputHandle
    eb:SetFocus()
    eb._text = text
    eb._cursor = #text
    eb:_fire("OnTextChanged", true)
end

--- Presses Enter in an Input handle.
function M.pressEnter(inputHandle)
    local eb = inputHandle._eb or inputHandle
    eb:_fire("OnEnterPressed")
end

--- Presses Escape in an Input handle.
function M.pressEscape(inputHandle)
    local eb = inputHandle._eb or inputHandle
    eb:_fire("OnEscapePressed")
end

----------------------------------------------------------------------------------
-- Observation
----------------------------------------------------------------------------------

--- Records every emission of a UI signal on an object.
-- @param obj table  Component handle or container
-- @param signal string
-- @return table  { count, calls, last, args, reset() }
function M.signalSpy(obj, signal)
    local spy = { count = 0, calls = {} }
    spy.id = M.S:Connect(obj, signal, function(...)
        spy.count = spy.count + 1
        local args = { n = select("#", ...), ... }
        spy.calls[spy.count] = args
        spy.last = args
    end)
    function spy:reset()
        self.count = 0
        self.calls = {}
        self.last = nil
    end
    function spy:arg(i, callIndex)
        local call = self.calls[callIndex or self.count]
        return call and call[i]
    end
    return spy
end

--- Records every emission of an addon-wide event.
-- @param event string
-- @return table  { count, calls, last }
function M.eventSpy(event)
    local spy = { count = 0, calls = {} }
    local owner = "harness_spy_" .. event .. "_" .. tostring(math.random(1e9))
    spy.owner = owner
    M.SuuUI.Events:On(event, function(...)
        spy.count = spy.count + 1
        local args = { n = select("#", ...), ... }
        spy.calls[spy.count] = args
        spy.last = args
    end, owner)
    function spy:arg(i, callIndex)
        local call = self.calls[callIndex or self.count]
        return call and call[i]
    end
    return spy
end

--- Returns lines captured from SuuUI.Debug / print.
function M.debugLog() return state.debugLog end

----------------------------------------------------------------------------------
-- Geometry access
----------------------------------------------------------------------------------

--- Rect of a widget in top-down screen coordinates.
-- @param target table
-- @return table|nil  { left, top, width, height, right, bottom }
function M.box(target)
    return geometry.boxFromTop(M.frameOf(target), state.screenHeight)
end

--- Offset of a child's top-left from an ancestor's top-left.
-- dy grows downward, matching how the layout engine expresses padding and gaps.
-- @param child table
-- @param ancestor table
-- @return number, number  dx, dy
function M.offset(child, ancestor)
    return geometry.offsetFrom(M.frameOf(child), M.frameOf(ancestor))
end

--- Measured text width using the harness font model. Use this instead of literals so
--- assertions stay valid if the model's ratios change.
-- @param text string
-- @param size number
-- @param path string  Optional font path; omitted uses the base metric model
-- @return number
function M.textWidth(text, size, path)
    return font.unbounded(text, size or M.token("fontSizeMd"), path)
end

--- The width the layout engine RESERVES for a string, as distinct from the width the
--- string measures. `TextMetrics.Box` adds one physical pixel on top of the metric,
--- because the client truncates with zero tolerance and its rendered extent need not
--- match the metric exactly. Assert against this wherever a font string's own box is
--- sized from its text — a `width = "auto"` child, a centred Divider label — and against
--- H.textWidth where a component measures text and then adds its own padding.
-- @param text string
-- @param size number
-- @param path string  Optional font path
-- @return number
function M.textBox(text, size, path)
    local w = M.textWidth(text, size, path)
    if w <= 0 then return 0 end
    return M.SuuUI.Pixel.Ceil(w + (M.SuuUI.Pixel.mult or 0))
end

--- Measured text height using the harness font model.
function M.textHeight(text, size, wrap, bound, path)
    local _, h = font.measure(text, size or M.token("fontSizeMd"), wrap, bound, false, path)
    return h
end

--- Single-line height at a font size.
function M.lineHeight(size, path)
    return font.lineHeight(size or M.token("fontSizeMd"), path)
end

--- Makes a font face loadable and gives the client a font object reporting it, the way
--- a locale client or a media addon adds one. The addon's GetFonts harvest can then see
--- it. Faces reset on every H.setup().
-- @param name string   Font object global name
-- @param path string   Font file path
-- @param ratios table  Optional { widthRatio, heightRatio }
-- @return string  The path
function M.addFont(name, path, ratios)
    ratios = ratios or {}
    font.addFace(path, ratios.widthRatio, ratios.heightRatio)
    M.wow.addFontObject(name, path)
    return path
end

--- Font path in force on a widget, component handle or region.
-- @param target table
-- @return string, number, string  path, size, flags
function M.fontOf(target)
    local f = M.frameOf(target)
    assert(f and f.GetFont, "harness: fontOf target has no GetFont")
    return f:GetFont()
end

require("harness.expect_layout")(M)

return M
