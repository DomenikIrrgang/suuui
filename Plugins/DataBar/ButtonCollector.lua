-- Finds the addon buttons sitting on the minimap ring and hands them over to be shown
-- somewhere else -- then gives them back.
--
-- Nothing here draws anything. Discovery, adoption and restore are game plumbing rather than
-- UI, which is why this file reads the client directly and owns no frames of its own.
--
-- Two sources, because neither is sufficient. LibDBIcon knows every button registered through
-- it BY NAME, which is the clean path and the only one that yields a real display name. Plenty
-- of addons still glue a button onto the minimap by hand, so the ring's own children are
-- scanned as well. The filter for that scan is MBB's, deliberately: it is the shape that has
-- been proven on this client for years, and the two halves of it are both load-bearing --
-- `issecurevariable` excludes every Blizzard ring element without a blacklist to maintain, and
-- the PIN patterns keep out the hundreds of map pins Questie and HandyNotes park on the
-- minimap, which are children of it and look exactly like buttons.
local ipairs, pairs, type, tostring, sort = ipairs, pairs, type, tostring, table.sort

SuuUI._DataBar = SuuUI._DataBar or {}

local M = {}

-- MBB's own name patterns. A POSITIVE filter: a frame has to look like an addon's minimap
-- button to be collected, rather than being collected unless it looks like something else.
local BUTTON_PATTERNS = {
    "^LibDBIcon10_",
    "MinimapButton",
    "MinimapFrame",
    "MinimapIcon",
    "[-_]Minimap[-_]",
    "Minimap$",
}

-- Map pins, not buttons. These addons put a child on the minimap per node, so without this
-- the roster fills with hundreds of nameless pins and the real buttons are lost in them.
local PIN_PATTERNS = {
    "^HandyNotes",
    "^TomTom",
    "^HereBeDragons",
    "^Questie",
    "^GatherMate",
    "^pin",
    "^Pin",
}

-- The addon this feature cannot coexist with: it collects the same frames by the same
-- mechanism, and two collectors reparenting one button take it in turns.
local RIVAL_ADDON = "MinimapButtonButton"

-- frame -> { parent, scale, ignoreParentScale, points = { {point, relTo, relPoint, x, y} } }
local original = {}
-- frame -> true while THIS file is the one holding the button.
local managed = {}
-- frame -> true once hooked. hooksecurefunc cannot be undone, so a hook is installed at most
-- once per frame and asks `managed` on every call instead of assuming it should always act.
local hooked = {}
-- Set while we are the ones moving a button, so our own placement does not re-enter the hook.
local applying = false

local collected = {}
local ldbNames  = {}
local onChange
-- Owner table for the LibDBIcon callback subscription, and whether it is live. A table rather
-- than a string because CallbackHandler keys registrations by identity.
local cbOwner = {}
local watching

---------------------------------------------------------------------------
-- Client probes
---------------------------------------------------------------------------

local function libIcon()
    if type(_G.LibStub) ~= "table" then return nil end
    local ok, lib = pcall(_G.LibStub, "LibDBIcon-1.0", true)
    return ok and lib or nil
end

--- Whether MinimapButtonButton is loaded. Both API shapes are probed because the newer
--- namespaced form does not exist on every client generation.
-- @return bool
function M.RivalLoaded()
    local api = _G.C_AddOns
    if api and type(api.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(api.IsAddOnLoaded, RIVAL_ADDON)
        return (ok and loaded) and true or false
    end
    if type(_G.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(_G.IsAddOnLoaded, RIVAL_ADDON)
        return (ok and loaded) and true or false
    end
    return false
end

--- The name of the addon this feature conflicts with, for the message that names it.
M.RIVAL_ADDON = RIVAL_ADDON

---------------------------------------------------------------------------
-- Identification
---------------------------------------------------------------------------

local function matchesAny(name, patterns)
    for _, pattern in ipairs(patterns) do
        if name:match(pattern) then return true end
    end
    return false
end

local function isCollectableName(name)
    if not name or name == "" then return false end
    -- Blizzard's own ring elements are secure globals, so this one question replaces a
    -- blacklist that would need a line per client generation.
    if type(_G.issecurevariable) == "function" then
        local ok, secure = pcall(_G.issecurevariable, _G, name)
        if ok and secure then return false end
    end
    -- A trailing digit is the signature of a generated pin (QuestiePin12), not of a button
    -- somebody named. Checked before the button patterns because some pins carry them too.
    if name:match("%d$") then return false end
    if matchesAny(name, PIN_PATTERNS) then return false end
    return matchesAny(name, BUTTON_PATTERNS)
end

local function isFrame(f)
    return type(f) == "table" and type(f.IsObjectType) == "function"
        and f:IsObjectType("Frame")
end

-- The name a player would recognise. LibDBIcon's registration name is already that, so it is
-- preferred outright; a hand-rolled button only has its frame name, which carries the
-- boilerplate that identified it in the first place and has to come back off.
local function displayName(frame)
    local ldb = ldbNames[frame]
    if ldb and ldb ~= "" then return ldb end

    local raw = (type(frame.GetName) == "function" and frame:GetName()) or nil
    if not raw or raw == "" then return "Unknown" end

    local name = raw
    name = name:gsub("^LibDBIcon10_", "")
    name = name:gsub("MinimapButton", "")
    name = name:gsub("MinimapFrame", "")
    name = name:gsub("MinimapIcon", "")
    name = name:gsub("Minimap$", "")
    name = name:gsub("^[-_%s]+", "")
    name = name:gsub("[-_%s]+$", "")
    if name == "" then return raw end
    return name
end

---------------------------------------------------------------------------
-- Adoption
---------------------------------------------------------------------------

local function isPinned(frame, which)
    -- The SETTER's name is certain -- LibDBIcon calls SetFixedFrameStrata/SetFixedFrameLevel --
    -- but the getter is spelled Is… on some client generations and Has… on others, so both are
    -- probed rather than betting on one. Only the restore reads this; releasing the pin uses
    -- the setter, so a client with neither getter still renders correctly and merely re-pins
    -- nothing on the way out.
    local names = which == "strata"
        and { "IsFixedFrameStrata", "HasFixedFrameStrata" }
        or  { "IsFixedFrameLevel",  "HasFixedFrameLevel" }
    for _, name in ipairs(names) do
        if type(frame[name]) == "function" then
            local ok, pinned = pcall(frame[name], frame)
            if ok then return pinned and true or false end
        end
    end
    return nil
end

local function recordOriginal(frame)
    if original[frame] then return end
    local rec = {
        parent = frame:GetParent(),
        scale  = type(frame.GetScale) == "function" and frame:GetScale() or nil,
        points = {},
        -- The strata pinning LibDBIcon applies to every button it makes (SetFrameStrata
        -- "MEDIUM" + SetFixedFrameStrata(true), level 8 + SetFixedFrameLevel(true)). The FIXED
        -- flags are the load-bearing part: they mean reparenting does NOT re-inherit the new
        -- parent's strata, so an adopted button stays on MEDIUM and draws behind any panel
        -- above it. Recorded so the ring gets its own z-order back untouched.
        strata      = type(frame.GetFrameStrata) == "function" and frame:GetFrameStrata() or nil,
        level       = type(frame.GetFrameLevel) == "function" and frame:GetFrameLevel() or nil,
        fixedStrata = isPinned(frame, "strata"),
        fixedLevel  = isPinned(frame, "level"),
        -- The button's own size, captured BEFORE anything of ours touches it. Read back later
        -- it would be whatever the roster last sized it to, so the icon column would derive
        -- its size from its own previous output and ratchet downwards on every rebuild.
        width  = type(frame.GetWidth) == "function" and frame:GetWidth() or nil,
        height = type(frame.GetHeight) == "function" and frame:GetHeight() or nil,
    }
    local n = (type(frame.GetNumPoints) == "function" and frame:GetNumPoints()) or 0
    for i = 1, n do
        local point, relTo, relPoint, x, y = frame:GetPoint(i)
        rec.points[#rec.points + 1] = {
            point = point, relTo = relTo, relPoint = relPoint, x = x, y = y,
        }
    end
    original[frame] = rec
end

-- Re-entrancy guard for the change notification, and the reason this feature FROZE THE CLIENT
-- on the first hover. The hook below fires on SetPoint; the callback rebuilds the roster; the
-- rebuild lays the button out; laying it out calls SetPoint; the hook fires again. Forever.
--
-- `applying` does not cover it and cannot: that flag is only raised while THIS file collects
-- or restores, whereas the rebuild happens inside the panel, which knows nothing about either
-- and should not have to. The guard therefore sits on the notification itself, which is the
-- one place every path through the cycle passes.
local notifying = false

local function notifyChanged()
    if notifying or not onChange then return end
    notifying = true
    -- pcall because this runs from inside a hook on somebody else's SetPoint: an error raised
    -- here would surface in whichever addon happened to move its own button.
    local ok, err = pcall(onChange)
    notifying = false
    if not ok then
        SuuUI.Debug("addon_buttons: change callback failed: " .. tostring(err))
    end
end

-- An addon that re-anchors its own button would tear it out of the row it is sitting in. The
-- hook is permanent, so it consults `managed` rather than assuming -- the same shape the
-- Blizzard-frame reposition uses, and for the same reason: a hook that always acted would
-- make the restore below impossible.
local function claim(frame)
    if hooked[frame] then return end
    hooked[frame] = true

    if type(_G.hooksecurefunc) ~= "function" then return end

    local function changed()
        if applying or not managed[frame] then return end
        notifyChanged()
    end

    if type(frame.SetPoint) == "function" then
        pcall(_G.hooksecurefunc, frame, "SetPoint", changed)
    end
    -- A button that hides or shows itself changes how many rows the roster has. Hooked on the
    -- frame's own methods rather than via OnShow/OnHide, so it fires when the ADDON changes
    -- its mind and not merely when our panel opens and closes.
    pcall(_G.hooksecurefunc, frame, "Show", changed)
    pcall(_G.hooksecurefunc, frame, "Hide", changed)
end

-- Where an adopted button waits between roster rebuilds. It exists because the ring has to
-- empty the moment a button is collected, not the first time the player opens the panel: the
-- panel is what reparents a button into a row, so without somewhere else to put it a collected
-- button stayed on the minimap until its first hover. An invisible holding frame, so a button
-- parked here is off the ring and drawn nowhere.
local holder

local function holdingFrame()
    if holder then return holder end
    local parent = SuuUI.UIRoot and SuuUI.UIRoot:GetRoot() or _G.UIParent
    holder = CreateFrame("Frame", "SuuUI_addon_buttons_holder", parent)
    holder:Hide()
    return holder
end

local function adopt(frame)
    if managed[frame] then return false end
    recordOriginal(frame)
    managed[frame] = true
    claim(frame)
    -- Off the ring immediately. The roster moves it again when it is next built.
    pcall(frame.SetParent, frame, holdingFrame())
    collected[#collected + 1] = frame
    return true
end

---------------------------------------------------------------------------
-- Discovery
---------------------------------------------------------------------------

local function collectLibDBIcon()
    local lib = libIcon()
    if not lib or type(lib.GetButtonList) ~= "function" then return end

    local ok, list = pcall(lib.GetButtonList, lib)
    if not ok or type(list) ~= "table" then return end

    for _, name in ipairs(list) do
        local ok2, button = pcall(lib.GetMinimapButton, lib, name)
        if ok2 and isFrame(button) then
            ldbNames[button] = name
            adopt(button)
        end
    end
end

local function collectRingChildren()
    local minimap = _G.Minimap
    if not minimap or type(minimap.GetChildren) ~= "function" then return end

    -- pcall, as MBB does: a player carrying thousands of map pins can make GetChildren itself
    -- fail, and that must cost the roster rather than the login.
    local results = { pcall(minimap.GetChildren, minimap) }
    if results[1] == false then
        SuuUI.Debug("addon_buttons: could not read minimap children")
        return
    end

    for i = 2, #results do
        local child = results[i]
        if isFrame(child) and not managed[child] then
            local name = type(child.GetName) == "function" and child:GetName() or nil
            if isCollectableName(name) then adopt(child) end
        end
    end
end

--- Subscribes to LibDBIcon's own "a button was created" callback.
---
--- This is the precise answer to the count reading 0 after login. LibDBIcon does NOT create a
--- button when an addon registers one: `createButton` is gated on `lib.loggedIn`, and anything
--- registered before PLAYER_LOGIN is queued in `lib.notCreated` and built afterwards. So a
--- sweep run during the login pass finds genuinely nothing, and with the next sweep bound to
--- PLAYER_ENTERING_WORLD, combat ending, or a hover, the field could sit at 0 indefinitely.
---
--- Event-driven rather than polled harder, because the library announces exactly this.
function M.Watch()
    if watching then return end
    local lib = libIcon()
    if not lib or type(lib.RegisterCallback) ~= "function" then return end

    local ok = pcall(lib.RegisterCallback, cbOwner, "LibDBIcon_IconCreated",
        function(_, button, name)
            if not isFrame(button) or M.RivalLoaded() then return end
            if name then ldbNames[button] = name end
            -- applying, so reparenting the new button does not trip its own SetPoint hook.
            applying = true
            local added = adopt(button)
            applying = false
            if added then notifyChanged() end
        end)
    watching = ok and true or false
end

--- Drops that subscription.
function M.Unwatch()
    local lib = libIcon()
    if watching and lib and type(lib.UnregisterCallback) == "function" then
        pcall(lib.UnregisterCallback, cbOwner, "LibDBIcon_IconCreated")
    end
    watching = false
end

--- Collects every addon button on the ring. Safe to call repeatedly: a button already held
--- is skipped, so this doubles as "pick up anything that appeared since last time".
-- @return number  How many buttons are held in total
function M.Collect()
    -- A button built from a secure template cannot be reparented in combat, and the client
    -- refuses silently. Collection is deferred rather than attempted and lost.
    if InCombatLockdown and InCombatLockdown() then return #collected end
    if M.RivalLoaded() then return #collected end

    applying = true
    collectLibDBIcon()
    collectRingChildren()
    applying = false
    return #collected
end

---------------------------------------------------------------------------
-- Restore
---------------------------------------------------------------------------

--- Puts every held button back where it was found: original parent, anchors and scale.
--- MBB makes this impossible by replacing SetParent/SetPoint with no-ops; this keeps the
--- methods intact and gates the re-assert hook on `managed` instead, so a disable genuinely
--- hands the ring back.
function M.Restore()
    if InCombatLockdown and InCombatLockdown() then return false end

    applying = true
    for _, frame in ipairs(collected) do
        local rec = original[frame]
        -- Cleared BEFORE the placement. The hook cannot be uninstalled, so in the other
        -- order it would see the button still managed, fire on our restoring SetPoint, and
        -- ask for a rebuild on the way out.
        managed[frame] = nil
        if rec then
            pcall(function()
                if rec.parent then frame:SetParent(rec.parent) end
                if rec.scale and type(frame.SetScale) == "function" then
                    frame:SetScale(rec.scale)
                end
                if rec.width and rec.height and type(frame.SetSize) == "function" then
                    frame:SetSize(rec.width, rec.height)
                end
                -- Strata and level go back BEFORE the fixed flags are re-pinned, or the pin
                -- would freeze whatever the roster last left on the frame.
                if rec.strata and type(frame.SetFrameStrata) == "function" then
                    frame:SetFrameStrata(rec.strata)
                end
                if rec.level and type(frame.SetFrameLevel) == "function" then
                    frame:SetFrameLevel(rec.level)
                end
                if rec.fixedStrata and type(frame.SetFixedFrameStrata) == "function" then
                    frame:SetFixedFrameStrata(true)
                end
                if rec.fixedLevel and type(frame.SetFixedFrameLevel) == "function" then
                    frame:SetFixedFrameLevel(true)
                end
                frame:ClearAllPoints()
                for _, p in ipairs(rec.points) do
                    frame:SetPoint(p.point, p.relTo, p.relPoint, p.x, p.y)
                end
            end)
        end
    end
    applying = false

    for i = #collected, 1, -1 do collected[i] = nil end
    for k in pairs(original) do original[k] = nil end
    return true
end

---------------------------------------------------------------------------
-- Readout
---------------------------------------------------------------------------

--- The held buttons as roster entries, sorted by display name.
--- A button the owning addon has hidden is left out: it contributes no row and is not
--- counted, because a named row with nothing in it reads as a broken icon.
-- @return table  Array of { key, label, frame }, and the largest natural button size
function M.GetEntries()
    local entries = {}
    local maxSize = 0
    for _, frame in ipairs(collected) do
        local shown = type(frame.IsShown) ~= "function" or frame:IsShown()
        if shown then
            entries[#entries + 1] = {
                key   = (type(frame.GetName) == "function" and frame:GetName()) or tostring(frame),
                label = displayName(frame),
                frame = frame,
            }
            local rec = original[frame]
            -- The RECORDED natural size, not the live one: the roster sizes the button, so
            -- reading it back would derive the icon column from its own previous output and
            -- shrink it a little further on every rebuild.
            local w = (rec and rec.width) or 0
            local h = (rec and rec.height) or 0
            if w > maxSize then maxSize = w end
            if h > maxSize then maxSize = h end
        end
    end

    -- Sorted by name, then by key, so the order is TOTAL: two buttons resolving to the same
    -- display name would otherwise come out in the scan's order, which is the client's child
    -- order and not stable between logins.
    sort(entries, function(a, b)
        if a.label == b.label then return a.key < b.key end
        return a.label < b.label
    end)

    return entries, maxSize
end

--- How many buttons are held, hidden ones excluded.
--- Deliberately does NOT go through GetEntries: this is read by the data bar's shared ticker,
--- where a table allocation per tick is exactly what the performance rules forbid.
-- @return number
function M.Count()
    local n = 0
    for i = 1, #collected do
        local frame = collected[i]
        if type(frame.IsShown) ~= "function" or frame:IsShown() then n = n + 1 end
    end
    return n
end

--- Registers the callback fired when a held button moves, shows or hides itself.
-- @param fn function|nil
function M.SetChangeCallback(fn)
    onChange = fn
end

--- Whether a frame is currently held. Specs assert against this.
-- @param frame frame
-- @return bool
function M.IsManaged(frame)
    return managed[frame] == true
end

SuuUI._DataBar.ButtonCollector = M
