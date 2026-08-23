-- Bar 1's paging, done the only way that works in combat.
--
-- WHY THIS IS A SECURE SNIPPET AND NOT AN EVENT HANDLER. Paging means rewriting each button's
-- `action` attribute, and SetAttribute on a protected frame is refused while
-- InCombatLockdown() is true. Every trigger for a page change is an IN-COMBAT transition by
-- definition -- a warrior swapping stance, a druid shifting form, a rogue entering stealth -- so
-- a Lua handler would be refused at exactly the moment it was needed, every time. The client
-- evaluates the conditional and runs the snippet itself, inside the secure environment, where
-- rewriting the attribute is allowed.
--
-- ONLY BAR 1 NEEDS THIS. Phase 0's Round 3 probe measured the slot blocks: bar 1 is slots 1..12
-- and pages through 13..24, 25..36 and so on, while the four multibars are FIXED to 61..72,
-- 49..60, 37..48 and 25..36. So pages 3..6 of bar 1 land on the same slots the other bars own,
-- and those bars need no driver at all -- which removed four secure headers from this phase.
--
-- WHAT A SPEC CAN AND CANNOT PROVE HERE. The harness records driver strings and never evaluates
-- them, deliberately: resolving a macro conditional locally would mean asserting against the
-- harness's guess at what the client decides. So a spec asserts the driver string, the frame
-- references and the attributes -- the STRUCTURE -- and paging's actual behaviour is an in-game
-- check. Stance-swap on a warrior or a druid is the verification.
local ipairs, pairs, tostring = ipairs, pairs, tostring
local S = SuuUI.UISignals

local M = {}

-- The client's own page conditions, highest first, falling through to page 1. `bar:N` is true
-- while the main bar is showing page N.
--
-- Ordered highest-to-lowest because a macro conditional list is first-match-wins: written the
-- other way round, `[bar:1]` would match before anything else was tested and the bar would never
-- leave page 1 -- a failure that looks exactly like paging not being wired up at all.
M.DRIVER = "[bar:6]6;[bar:5]5;[bar:4]4;[bar:3]3;[bar:2]2;1"

-- Runs INSIDE the secure environment on every page change. It can see no Lua upvalue and no
-- global from this file, so everything it needs arrives as an attribute or a frame reference set
-- out of combat: the page size, how many buttons there are, and one reference per button.
--
-- `newstate` is what the driver resolved to, as a string.
M.SNIPPET = [[
    local page = tonumber(newstate) or 1
    local size = tonumber(self:GetAttribute("pageSize")) or 12
    local count = tonumber(self:GetAttribute("buttonCount")) or 0
    local first = (page - 1) * size + 1
    for i = 1, count do
        local button = self:GetFrameRef("button" .. i)
        if button then
            button:SetAttribute("action", first + i - 1)
        end
    end
]]

-- grid handle -> its header. Module-local rather than a field on the grid, so the grid keeps
-- knowing nothing about paging -- it owns the A2 look and no action slots, which is the line the
-- plan draws and the reason this is a separate file.
local headers = {}
-- grid handle -> the CHILDREN_CHANGED connection id. UISignals keys a connection by the id
-- Connect hands back, not by an owner token, so it has to be kept to be released.
local connections = {}

-- Re-states one reference per button, plus the count the snippet loops to.
--
-- Called again on every rebuild, because the grid DESTROYS and recreates its buttons when the
-- count or a slot changes -- references to the old ones would point at dead frames, and the
-- snippet's `if button then` would silently page nothing. Out of combat only: SetFrameRef is
-- refused on a protected frame during a fight, exactly like SetAttribute.
--
-- `buttonCount` IS THE BOUND, and that is load-bearing rather than incidental. Shrinking a bar
-- from twelve buttons to four leaves references 5..12 in place, pointing at frames the grid has
-- destroyed -- the snippet never reads them because it loops to buttonCount, so they are inert,
-- but they are NOT cleared and a caller must not treat the ref set as describing the current bar.
-- Clearing them would mean SetFrameRef(name, nil), and whether this client accepts a nil frame
-- there is unverified; guessing wrong would raise inside a secure setter at login. The count is
-- the honest contract.
local function syncRefs(header, grid)
    local buttons = grid:GetButtons()
    for i, button in ipairs(buttons) do
        header:SetFrameRef("button" .. i, button:GetFrame())
    end
    header:SetAttribute("buttonCount", #buttons)
end

--- Gives a grid secure paging, or re-syncs it if it already has some.
--
-- Idempotent: safe to call on a grid that is already paged, which is what makes the
-- CHILDREN_CHANGED subscription below able to just call it again.
-- @param grid table  an ActionBarGrid handle
-- @param opts table|nil  { pageSize = 12 }
-- @return table  the secure header
function M.Attach(grid, opts)
    opts = opts or {}
    local pageSize = opts.pageSize or 12

    local header = headers[grid]
    if not header then
        -- Parented to the grid's frame so it goes when the bar does. That adds no protection the
        -- grid did not already have -- it holds secure buttons by construction.
        header = CreateFrame("Frame", nil, grid:GetFrame(), "SecureHandlerStateTemplate")
        headers[grid] = header

        -- Re-sync on every rebuild. This subscription is the whole reason ActionBarGrid emits
        -- CHILDREN_CHANGED: a rebuild can be DEFERRED to the end of a fight, so nothing else
        -- tells this module when the buttons it holds references to were replaced. Watching the
        -- setting that caused the rebuild would fire too early, while the old buttons were still
        -- on screen.
        connections[grid] = S:Connect(grid, S.SIGNALS.CHILDREN_CHANGED, function()
            local h = headers[grid]
            if h then syncRefs(h, grid) end
        end)
    end

    header:SetAttribute("pageSize", pageSize)
    syncRefs(header, grid)
    header:SetAttribute("_onstate-page", M.SNIPPET)
    RegisterStateDriver(header, "page", M.DRIVER)

    return header
end

--- Removes secure paging from a grid.
--
-- The attributes are left where they are: the header is about to be dropped, and clearing an
-- attribute on a protected frame is one more call the client can refuse.
-- @param grid table
function M.Detach(grid)
    local header = headers[grid]
    if not header then return end
    headers[grid] = nil
    S:Disconnect(grid, S.SIGNALS.CHILDREN_CHANGED, connections[grid])
    connections[grid] = nil
    UnregisterStateDriver(header, "page")
    header:Hide()
end

--- The secure header driving a grid's paging, or nil.
-- @param grid table
-- @return table|nil
function M.HeaderFor(grid)
    return headers[grid]
end

SuuUI._ActionBars = SuuUI._ActionBars or {}
SuuUI._ActionBars.Paging = M
