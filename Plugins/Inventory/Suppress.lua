-- Hides Blizzard's bag containers and routes the bag-opening functions to SuuUI's window, then hands
-- both back exactly.
--
-- WHY THIS IS NOT A COPY OF Plugins/ActionBars/Suppress.lua, which does the same job for the bottom
-- cluster. That module defers every visibility change to PLAYER_REGEN_ENABLED because MainMenuBar
-- holds SecureActionButtonTemplate buttons, so protection propagates down and the client refuses
-- Hide() mid-fight. A bag container holds `ContainerFrameItemButtonTemplate` cells, which are NOT a
-- secure template -- measured, since SuuUI builds its own cells from that same template and they take
-- no attributes. So NOTHING HERE IS PROTECTED and there is deliberately no combat guard: adding one
-- would be unreachable code, which mutation testing would then show as a survivor.
--
-- The three rules from plugin-authoring.md still apply verbatim, and each is load-bearing:
--
--   * NEVER UnregisterAllEvents. Nothing enumerates a frame's registered events, so it is a one-way
--     door and onDisable could never hand the frame back.
--   * NEVER SetParent(nil). It taints, and a tainted container frame is worse than a visible one.
--   * The suppression flag is cleared BEFORE the restoring Show(), or the OnShow hook we cannot
--     uninstall hides it again on the way out.
--
-- TWO MECHANISMS, NOT ONE, and they answer different questions. Suppression stops Blizzard's frames
-- appearing when something else shows them; the function replacement is what makes the `B` key open
-- OUR window instead. Either alone is a broken feature: suppression alone gives a key that appears to
-- do nothing, and replacement alone leaves Blizzard's bags opening behind ours whenever any other
-- addon or client path calls one of these globals.
local ipairs, pairs, type = ipairs, pairs, type

local M = {}

-- The containers, resolved by NAME because these are numbered rather than renamed. Thirteen is what
-- the client allocates: backpack + 4 bags + 7 bank bags + the bank's own grid. An absent number is
-- skipped, so a build with fewer costs nothing.
--
-- `ContainerFrameCombinedBags` is listed because a backported build may have it and it is a DIFFERENT
-- frame from the numbered ones -- the same coexistence trap as MainMenuBar versus MainActionBar, where
-- stopping at the frame that existed left every button on screen.
local function containerNames()
    local names = {}
    for i = 1, 13 do names[#names + 1] = "ContainerFrame" .. i end
    names[#names + 1] = "ContainerFrameCombinedBags"
    names[#names + 1] = "BankFrame"
    return names
end

M.containerNames = containerNames

-- The cells this module exists to get off the screen. Used by Verify() as a SELF-CHECK: hiding a
-- container is the means, a bag slot being gone is the end, and the action bar module already shipped
-- a version where every other signal reported success while twelve buttons sat in plain view.
--
-- `ContainerFrame1Item1` is the CLASSIC name and the one measured present on this build.
-- `ContainerFrameItemButton1` is the retail spelling and is deliberately absent -- probing for it was
-- already a mistake once in this project.
local WITNESS_CELLS = { "ContainerFrame1Item1", "BankFrameItem1" }
M.WITNESS_CELLS = WITNESS_CELLS

-- The FrameXML globals that open bags. All plain Lua and replaceable.
--
-- `kind` says what our window should do, so one table drives every replacement and a new name needs
-- no new branch. The bag id an Open/Toggle/CloseBag receives is deliberately IGNORED: the window is one
-- combined grid of every bag, so "open bag 3" and "open bag 0" are the same request.
local ROUTES = {
    { name = "ToggleBackpack", kind = "toggle" },
    { name = "OpenBackpack",   kind = "open"   },
    { name = "CloseBackpack",  kind = "close"  },
    { name = "ToggleBag",      kind = "toggle" },
    { name = "OpenBag",        kind = "open"   },
    { name = "CloseBag",       kind = "close"  },
    { name = "ToggleAllBags",  kind = "toggle" },
    { name = "OpenAllBags",    kind = "open"   },
    { name = "CloseAllBags",   kind = "close"  },
}
M.ROUTES = ROUTES

-- Frame -> true for everything this module has hidden. Keyed by FRAME rather than by name, so a build
-- that renames one cannot leave a stale entry behind.
local suppressed = {}
-- HookScript cannot be undone, so the hook asks `suppressed` on every call rather than assuming it
-- should always hide. That is exactly what makes Restore possible.
local hooked = {}
-- name -> the client's own function, so onDisable can put every one of them back.
local originals = {}
-- What our replacements drive. Injected rather than reached for, so this module does not need to know
-- how the plugin finds its window -- and so a spec can drive it with a fake.
local handler

--- Points the replacements at something that can open and close a window.
-- @param h table|nil  { Toggle = fn, Open = fn, Close = fn }; nil clears it
function M.SetHandler(h)
    handler = h
end

local function callHandler(kind)
    if not handler then return false end
    local fn = kind == "toggle" and handler.Toggle
        or kind == "open" and handler.Open
        or handler.Close
    if type(fn) ~= "function" then return false end
    -- pcall because these run from a KEYBINDING: a throw here would surface to the player as an
    -- action-blocked error on the B key with nothing on screen to explain it.
    local ok, err = pcall(fn, handler)
    if not ok and SuuUI.Debug then
        SuuUI.Debug("Inventory: bag route failed -- " .. tostring(err))
    end
    return true
end

--- Hides every container that exists and routes every bag-opening global to our window.
--
-- Idempotent: a second call installs no second hook, saves no second original, and hides nothing
-- twice. That matters because a settings watcher can re-run it.
-- @return table  the container names that resolved, so a caller can log what was found
function M.Apply()
    local found = {}
    for _, name in ipairs(containerNames()) do
        local frame = _G[name]
        if frame then
            found[#found + 1] = name
            suppressed[frame] = true
            if not hooked[frame] then
                hooked[frame] = true
                frame:HookScript("OnShow", function(self)
                    -- Asked on every call, never assumed: this hook outlives Restore.
                    if suppressed[self] then self:Hide() end
                end)
            end
            frame:Hide()
        end
    end

    for _, route in ipairs(ROUTES) do
        local current = _G[route.name]
        if type(current) == "function" and originals[route.name] == nil then
            -- Saved BEFORE the replacement, and only once. A second Apply must not save our own
            -- replacement as "the original", which would make Restore a no-op that looks successful.
            originals[route.name] = current
            _G[route.name] = function(...)
                -- Falls through to the client's own function when nothing is listening, rather than
                -- swallowing the call: a replacement that silently does nothing turns the B key into
                -- a dead key, which is worse than Blizzard's bags opening.
                if not callHandler(route.kind) then
                    return originals[route.name](...)
                end
            end
        end
    end

    -- Self-check, and not decoration: this is the exact failure that hid behind a happy report in the
    -- action bar work. Logged rather than raised -- a stray visible bag is cosmetic, not a reason to
    -- take the plugin down mid-session.
    local visible = M.Verify()
    if #visible > 0 and SuuUI.Debug then
        SuuUI.Debug("Inventory: suppression missed " .. table.concat(visible, ", ")
                    .. " -- their container is not in containerNames()")
    end
    return found
end

--- Which witness cells are still on screen, by name. Empty means it worked.
-- @return table
function M.Verify()
    local visible = {}
    for _, name in ipairs(WITNESS_CELLS) do
        local cell = _G[name]
        if cell and cell.IsVisible and cell:IsVisible() then
            visible[#visible + 1] = name
        end
    end
    return visible
end

--- Shows everything this module hid and restores every function it replaced.
--
-- Never touches a frame it did not hide: with suppression off we never hid anything, and showing it
-- here would override whatever else did.
function M.Restore()
    for frame in pairs(suppressed) do
        -- Cleared BEFORE the Show, or the permanent hook hides it again on the way out.
        suppressed[frame] = nil
        frame:Show()
    end
    for name, fn in pairs(originals) do
        _G[name] = fn
        originals[name] = nil
    end
end

--- Whether this module is currently claiming the named frame.
-- @param name string
-- @return bool
function M.IsSuppressed(name)
    local frame = _G[name]
    return frame ~= nil and suppressed[frame] == true
end

--- Whether the named bag-opening global is currently routed to our window.
-- @param name string
-- @return bool
function M.IsRouted(name)
    return originals[name] ~= nil
end

SuuUI._Inventory = SuuUI._Inventory or {}
SuuUI._Inventory.Suppress = M
