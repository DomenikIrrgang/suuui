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
--              H.expectCenteredH H.expectCenteredV H.expectTokenColor
-- Input:       H.click H.forceClick H.mouseDown H.mouseUp H.hover H.unhover H.scroll
--              H.key H.typeText H.pressEnter H.pressEscape H.cursor H.cursorOn
--              H.setMouseDown H.mods
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
-- @param opts table  { boot = true, debug = false, screenWidth, screenHeight }
-- @return table  SuuUI
function M.setup(opts)
    opts = opts or {}
    state.screenWidth  = opts.screenWidth  or 1024
    state.screenHeight = opts.screenHeight or 768
    state.uiScale      = opts.uiScale or 1

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
-- Input simulation
----------------------------------------------------------------------------------

--- Places the cursor in UI coordinates (the space components work in after dividing
--- by the effective scale).
-- @param x number
-- @param y number
function M.cursor(x, y)
    local scale = M.UIParent:GetEffectiveScale()
    state.cursorX, state.cursorY = x * scale, y * scale
end

--- Places the cursor at the centre of a widget.
-- @param target table
function M.cursorOn(target)
    local f = M.frameOf(target)
    local cx, cy = f:GetCenter()
    assert(cx, "harness: cursorOn target has no resolvable position")
    M.cursor(cx, cy)
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
-- @return number
function M.textWidth(text, size)
    return font.unbounded(text, size or M.token("fontSizeMd"))
end

--- Measured text height using the harness font model.
function M.textHeight(text, size, wrap, bound)
    local _, h = font.measure(text, size or M.token("fontSizeMd"), wrap, bound)
    return h
end

--- Single-line height at a font size.
function M.lineHeight(size) return font.lineHeight(size or M.token("fontSizeMd")) end

require("harness.expect_layout")(M)

return M
