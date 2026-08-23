-- Bar-to-bar docking: any bar can attach to any other, on any edge, and chains are allowed.
--
-- ANCHORED, NOT CONTAINED, and that is a deliberate departure from the plan's rule 2. The plan had
-- attached bars extend the dock's bounding box outward, with the dock reporting `coreInset` so the
-- player's stored position kept meaning "where my buttons are". That works, but it makes the dock's
-- frame RESIZE whenever a bar attaches or detaches -- and the dock holds protected buttons, so the
-- client refuses that resize in combat. Rule 2 existed to manage a hazard this design does not
-- create: nothing here resizes, so there is nothing to refuse and no coreInset to keep in step.
--
-- CHAINS WORK FOR FREE because an anchor is a live relationship. Bar 4 on bar 5 on bar 1 needs no
-- extra machinery: moving bar 1 moves bar 5, which moves bar 4, without anything being recomputed.
-- Only a SIZE change needs a reflow, because the stacking offsets are sums of the spans beside them.
--
-- CYCLES ARE THE ONE THING THAT MUST NOT GET THROUGH. A circular anchor is not a cosmetic fault --
-- the client raises a hard error on it and the frame is left unplaced. So Attach refuses one rather
-- than half-applying it, and the settings layer rejects the choice before it is ever stored.
--
-- The one constraint from rule 2 that does carry over: an anchor is the same dependency as
-- parentage. The client refuses geometry on a frame whose movement would move a protected one, and
-- it does not care whether the link is a parent or a point. Which is why the PLUGIN defers the whole
-- dock/free transition out of combat -- see applyAttach there.
local ipairs, pairs, next, tostring = ipairs, pairs, next, tostring

local M = {}

-- Where a child sits relative to its dock, and which way a second child on the same edge stacks.
--
-- `axis` and `sign` turn one offset into the right coordinate: SetPoint's y grows UP and its x grows
-- RIGHT, so stacking below or to the left counts negative.
local EDGES = {
    above = { point = "BOTTOM", relativePoint = "TOP",    axis = "y", sign =  1, span = "GetHeight" },
    below = { point = "TOP",    relativePoint = "BOTTOM", axis = "y", sign = -1, span = "GetHeight" },
    left  = { point = "RIGHT",  relativePoint = "LEFT",   axis = "x", sign = -1, span = "GetWidth"  },
    right = { point = "LEFT",   relativePoint = "RIGHT",  axis = "x", sign =  1, span = "GetWidth"  },
}

M.EDGES = { "above", "below", "left", "right" }

-- dock grid -> { box = anchor container, children = ordered array, conns = child -> signal id }
local docks = {}
-- child grid -> the dock it is attached to. The reverse edge, kept because cycle detection walks
-- UPWARD from a candidate dock and there is no other way to go that direction.
local parentOf = {}

-- The gap between two docked bars. A deliberate hairline rather than zero: each bar carries its own
-- glass plate with its own gradient, so plates flush against each other show a seam where the fade
-- of one meets the dense edge of the next. A small gap reads as a group of bars instead.
local function gap()
    return SuuUI.Theme:GetToken("spaceXxs") or 2
end

local function record(dock)
    local rec = docks[dock]
    if not rec then
        rec = {
            -- Hosted on the DOCK's frame. The anchor descriptors name their relativeTo explicitly
            -- anyway (see Reflow), so this host is about ownership rather than resolution.
            box = SuuUI.Layout:CreateContainer({ host = dock:GetFrame(), layout = "anchor" }),
            children = {},
            -- child -> SIZE_CHANGED connection id, kept because UISignals keys a connection by the
            -- id it hands back rather than by an owner token.
            conns = {},
        }
        docks[dock] = rec
    end
    return rec
end

--- Whether attaching `child` to `dock` would close a loop.
--
-- Walks upward from the candidate dock: if the chain reaches the child, the child would end up
-- anchored to something anchored to itself. The step count is bounded as well as the identity
-- checked, so an already-corrupt graph cannot spin here.
-- @param dock table
-- @param child table
-- @return bool
function M.WouldCycle(dock, child)
    if dock == child then return true end
    local node, steps = dock, 0
    while node do
        if node == child then return true end
        node = parentOf[node]
        steps = steps + 1
        if steps > 64 then return true end
    end
    return false
end

--- Re-anchors every bar attached to a dock, stacking each edge independently.
--
-- NO COMBAT GUARD HERE, and that is deliberate rather than an oversight. Re-anchoring a docked bar
-- IS refused in combat, but nothing can ask for a reflow during a fight: the plugin defers the whole
-- dock/free transition, and a docked bar's own resize is deferred by ActionBarGrid, so its
-- SIZE_CHANGED does not arrive until combat ends either. An earlier draft carried a guard and a
-- PLAYER_REGEN_ENABLED watcher of its own; mutation testing showed the guard unreachable.
-- @param dock table  the dock's ActionBarGrid handle
function M.Reflow(dock)
    local rec = docks[dock]
    if not rec then return end

    local g = gap()
    local dockFrame = dock:GetFrame()
    local offsets = { above = g, below = g, left = g, right = g }

    for _, child in ipairs(rec.children) do
        local edge = child._dockEdge or "above"
        local e = EDGES[edge] or EDGES.above
        local off = offsets[edge] or g

        -- `relativeTo` is stated EXPLICITLY, and that is load-bearing rather than tidy. Layout props
        -- live on the FRAME, not on the container, so a frame belonging to two containers has ONE
        -- props table -- and an anchor with no relativeTo resolves against whichever container is
        -- applying it. The root container re-applied this very descriptor with ITSELF as the
        -- relative frame, which pinned every docked bar to the top of the screen the first time the
        -- dock moved. Naming the frame makes the descriptor mean the same thing whoever reads it.
        local desc = {
            point = e.point, relativeTo = dockFrame, relativePoint = e.relativePoint, x = 0, y = 0,
        }
        desc[e.axis] = off * e.sign
        rec.box:SetChildAnchor(child:GetFrame(), desc)

        local span = child[e.span] and child[e.span](child) or 0
        offsets[edge] = off + span + g
    end
    rec.box:Layout()
end

--- Attaches a bar to a dock on an edge. Idempotent, and refuses a cycle outright.
-- @param dock table   the dock's ActionBarGrid handle
-- @param child table  the attaching bar's ActionBarGrid handle
-- @param opts table|nil  { order = number, edge = "above"|"below"|"left"|"right" }
-- @return bool  false when the attach was refused as a cycle
function M.Attach(dock, child, opts)
    opts = opts or {}
    if M.WouldCycle(dock, child) then
        if SuuUI.Debug then
            SuuUI.Debug("ActionBars: refused a docking that would loop back on itself")
        end
        return false
    end

    -- Moving between docks is a detach and a re-attach, not a second parent.
    local current = parentOf[child]
    if current and current ~= dock then
        M.Detach(current, child)
    end

    child._dockOrder = opts.order or 0
    child._dockEdge = EDGES[opts.edge] and opts.edge or "above"

    local rec = record(dock)
    local already = false
    for _, existing in ipairs(rec.children) do
        if existing == child then already = true break end
    end

    if not already then
        rec.children[#rec.children + 1] = child
        parentOf[child] = dock
        -- Reflow when a docked bar changes SHAPE. The stack's offsets are the sum of the spans
        -- beside them, so a bar gaining a row moves everything past it -- and nothing else would
        -- notice: Attach and Detach are the only other reflow triggers, and neither fires for a
        -- resize.
        rec.conns[child] = SuuUI.UISignals:Connect(child, SuuUI.UISignals.SIGNALS.SIZE_CHANGED,
            function() M.Reflow(dock) end)
        rec.box:Add(child:GetFrame(), {
            anchor = { point = "BOTTOM", relativeTo = dock:GetFrame(), relativePoint = "TOP" },
        })
    end

    -- Sorted so the stack does not depend on the order settings happened to fire in. A bar toggled
    -- off and on again lands back where it was rather than on top.
    table.sort(rec.children, function(a, b)
        local ao, bo = a._dockOrder or 0, b._dockOrder or 0
        if ao ~= bo then return ao < bo end
        return tostring(a) < tostring(b)
    end)

    M.Reflow(dock)
    return true
end

--- Detaches a bar, leaving it wherever it was until its owner re-positions it.
-- @param dock table
-- @param child table
function M.Detach(dock, child)
    local rec = docks[dock]
    if not rec then return end
    for i, existing in ipairs(rec.children) do
        if existing == child then
            table.remove(rec.children, i)
            parentOf[child] = nil
            if rec.conns[child] then
                SuuUI.UISignals:Disconnect(child, SuuUI.UISignals.SIGNALS.SIZE_CHANGED,
                    rec.conns[child])
                rec.conns[child] = nil
            end
            rec.box:Remove(child:GetFrame())
            M.Reflow(dock)
            return
        end
    end
end

--- Drops a dock entirely, when the bar that anchors it goes away.
--
-- Its children are released rather than left pointing at a frame that is about to go: each becomes
-- unattached, which is the state their owner can then re-place them from.
-- @param dock table
function M.Release(dock)
    -- Its OWN parent first, and unconditionally. A bar with nothing attached to it has no record
    -- here, so the early return below skipped this entirely and left the bar anchored to its parent
    -- after it had been destroyed -- a dock stack with a hole in it, reflowing around a dead frame.
    local parent = parentOf[dock]
    if parent then M.Detach(parent, dock) end

    local rec = docks[dock]
    if not rec then return end
    docks[dock] = nil
    for child, id in pairs(rec.conns) do
        SuuUI.UISignals:Disconnect(child, SuuUI.UISignals.SIGNALS.SIZE_CHANGED, id)
    end
    for _, child in ipairs(rec.children) do
        parentOf[child] = nil
    end
    rec.box:Destroy()
end

--- The bars currently docked to this one, in stack order, as a copy.
-- @param dock table
-- @return table
function M.Children(dock)
    local rec = docks[dock]
    local out = {}
    if not rec then return out end
    for i, child in ipairs(rec.children) do out[i] = child end
    return out
end

--- The bar this one is attached to, or nil.
-- @param child table
-- @return table|nil
function M.ParentOf(child)
    return parentOf[child]
end

--- Which edge a docked bar sits on, or nil when it is free.
-- @param child table
-- @return string|nil
function M.EdgeOf(child)
    return parentOf[child] and (child._dockEdge or "above") or nil
end

SuuUI._ActionBars = SuuUI._ActionBars or {}
SuuUI._ActionBars.Dock = M
