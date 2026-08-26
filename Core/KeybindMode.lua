-- KeybindMode: the hover-to-bind mode's state, and nothing else.
--
-- Turn it on, hover an action button, press a key combination and it binds. ESC on a button
-- clears every key bound to it. Edits apply LIVE and are persisted only when the player saves,
-- which is why the mode has a panel rather than being a silent toggle.
--
-- State: the authoritative value is Settings("_layout", "keybind_mode"), a transient
-- (non-persisted) key registered alongside edit_mode in Core/ToggleUI.lua. There is NO local
-- shadow variable -- reads go through Settings:Get, writes through Settings:Set, and subscribers
-- use Settings:Watch, so the slash command, the settings toggle and the panel cannot disagree.
-- Exactly the shape ToggleUI uses for edit mode, for exactly the same reason.
--
-- WHY THIS LIVES IN Core/ RATHER THAN Plugins/ActionBars/. Two reasons, both structural:
--
--   1. Mutual exclusion with edit mode has to be decided by something that owns neither. Edit
--      mode's overlays (Core/MoveableFrame.lua) sit at host+5 with mouse enabled, and a keybind
--      overlay on the same frame would stack with them -- a state neither was designed for. The
--      arbiter belongs beside the two modes, not inside one of their consumers.
--   2. `/suuui keybind` extends SettingsWindow's handler, and Plugins/Inventory/Inventory.lua
--      states the rule that made /sbags its own command: a PLUGIN must not put its knowledge in
--      that handler. A Core mode legitimately can, the way `toggle`/`lock`/`unlock` already do.
--
-- WHAT IS NOT HERE: every pixel. This file knows nothing about buttons, overlays, key capture or
-- the binding API. Participants register a PROVIDER and subscribe to the setting, so the bars can
-- own their own rendering and a later feature (bags, the spellbook) can join without this file
-- learning about it -- the same participant seam Core/Dock.lua uses across plugins.
local ipairs, type = ipairs, type

local M = {}

-- Providers of bindable buttons, in registration order. Each is { id, fn }, where fn returns a
-- list of button HANDLES (anything answering GetFrame and GetBinding).
local providers = {}

--- Whether keybind mode is currently active.
-- @return bool
function M:IsActive()
    return SuuUI.Settings:Get("_layout", "keybind_mode") or false
end

--- Turns keybind mode on. Refused in combat.
--
-- REFUSED RATHER THAN QUEUED, and that is the honest behaviour: SetBinding returns false in
-- combat (measured 2026-08-26) AND the client prints "Interface action failed because of an
-- AddOn", so a mode that opened anyway would look live and bind nothing. Compare Phase 7, where
-- combat starting while already inside the mode PAUSES it instead of closing -- there the player
-- has work in progress worth keeping, here they have none.
-- @return bool  whether the mode is now active
function M:Enable()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false
    end
    SuuUI.Settings:Set("_layout", "keybind_mode", true)
    return true
end

--- Turns keybind mode off.
function M:Disable()
    SuuUI.Settings:Set("_layout", "keybind_mode", false)
end

--- Flips the mode.
-- @return bool  whether the mode is now active
function M:Toggle()
    if self:IsActive() then
        self:Disable()
        return false
    end
    return self:Enable()
end

--- Registers a source of bindable buttons.
--
-- @param id string  unique, so re-registering replaces rather than duplicating
-- @param fn function  returns a list of button handles answering GetFrame and GetBinding
function M:RegisterProvider(id, fn)
    assert(type(id) == "string" and id ~= "", "KeybindMode:RegisterProvider: id required")
    assert(type(fn) == "function", "KeybindMode:RegisterProvider: fn required")
    for _, p in ipairs(providers) do
        if p.id == id then
            p.fn = fn
            return
        end
    end
    providers[#providers + 1] = { id = id, fn = fn }
end

--- Drops a provider.
-- @param id string
function M:UnregisterProvider(id)
    for i = #providers, 1, -1 do
        if providers[i].id == id then table.remove(providers, i) end
    end
end

--- Every bindable button, from every provider.
--
-- A provider that answers nothing is SKIPPED rather than being an error: a class with no stance
-- bar has no stance buttons, and SuuUIBarstanceButton1 was measured nil on the reference
-- character. Absence is a normal state here, not a fault.
-- @return table  list of button handles
function M:GetButtons()
    local out = {}
    for _, p in ipairs(providers) do
        local list = p.fn()
        if type(list) == "table" then
            for _, b in ipairs(list) do
                if b then out[#out + 1] = b end
            end
        end
    end
    return out
end

-- The keys every command held when the mode last opened, saved or discarded:
-- baseline[command] = { "1", "CTRL-F9" }. The change list is a DIFF against this, not a running
-- tally, and that choice does the work:
--
--   * one entry per command, however many times the player re-binds it -- "unique", as asked
--   * the entry reads from the ORIGINAL key, not the previous intermediate one, so 1 -> 2 -> 3
--     shows "1 -> 3" rather than "2 -> 3"
--   * a change that returns to where it started DISAPPEARS, because there is nothing to save
--   * the OTHER side of a steal appears for free: the command that lost the key differs from its
--     baseline too, and a counter incremented at the write site would never have noticed it
local baseline = nil

local function keysOf(command)
    if not command or type(GetBindingKey) ~= "function" then return {} end
    return { GetBindingKey(command) }
end

local function joinKeys(list)
    if #list == 0 then return nil end
    return table.concat(list, ", ")
end

--- Records the current bindings as the baseline the change list is measured against.
--- Called when the mode opens, and after a save or a discard settles it.
function M:Snapshot()
    baseline = {}
    for _, b in ipairs(self:GetButtons()) do
        local cmd = b.GetBinding and b:GetBinding() or nil
        if cmd then baseline[cmd] = keysOf(cmd) end
    end
end

--- Every binding that differs from the baseline, as display rows.
---
--- Each row is { command, from, to, cleared }, where `from`/`to` are comma-joined key strings and
--- nil means unbound. Sorted by command so the list does not reshuffle under the player between
--- repaints -- pairs() order is arbitrary and a jumping list is unreadable.
-- @return table
function M:Changes()
    local out = {}
    if not baseline then return out end
    for cmd, was in pairs(baseline) do
        local now = keysOf(cmd)
        if joinKeys(was) ~= joinKeys(now) then
            out[#out + 1] = {
                command = cmd,
                from    = joinKeys(was),
                to      = joinKeys(now),
                cleared = #now == 0,
            }
        end
    end
    table.sort(out, function(a, b) return a.command < b.command end)
    return out
end

--- How many bindings differ from the baseline.
function M:ChangedCount() return #self:Changes() end

--- Whether there is unsaved work.
function M:IsDirty() return self:ChangedCount() > 0 end

--- One change rendered for display, e.g. "ACTIONBUTTON1  1 -> 2" or "ACTIONBUTTON2  cleared".
-- @param row table  an entry from Changes()
-- @return string
function M:FormatChange(row)
    if row.cleared then return row.command .. "  cleared" end
    return row.command .. "  " .. (row.from or "unbound") .. " -> " .. (row.to or "unbound")
end

--- Which binding set the client is on: 1 = account-wide, 2 = character-specific.
function M:BindingSet()
    if type(GetCurrentBindingSet) ~= "function" then return 1 end
    return GetCurrentBindingSet() or 1
end

--- Persists every live edit to the set on disk.
---
--- SaveBindings only forces the write EARLIER -- it is NOT what makes an edit durable. Measured in
--- game: an unsaved SetBinding survives a reload on its own, because the client flushes bindings
--- itself on reload and logout. So Save's real job is to make Discard stop being able to undo the
--- work, and the panel's wording must reflect that rather than promising more.
-- @return bool
function M:Save()
    if type(SaveBindings) ~= "function" then return false end
    SaveBindings(self:BindingSet())
    -- The saved state IS the new baseline, so the list empties rather than being cleared by hand.
    self:Snapshot()
    return true
end

--- Reverts every live edit to the last SAVED state.
---
--- A SESSION undo, not an undo of everything. LoadBindings re-reads the set on disk, so the saved
--- set IS the snapshot and no snapshot table of our own is needed -- but it also reverts anything
--- changed outside this mode and never saved, and it cannot help once a logout has committed.
-- @return bool
function M:Discard()
    if type(LoadBindings) ~= "function" then return false end
    LoadBindings(self:BindingSet())
    self:Snapshot()
    return true
end

--- Switches between the account-wide and character-specific binding sets.
---
--- REFUSES while there is unsaved work, because the switch loads the target set OVER the live one
--- and would silently throw those edits away. The caller offers save-or-discard first.
-- @param perCharacter bool
-- @return bool  whether the switch happened
function M:SetPerCharacter(perCharacter)
    if self:IsDirty() then return false end
    if type(LoadBindings) ~= "function" or type(SaveBindings) ~= "function" then return false end
    local which = perCharacter and 2 or 1
    LoadBindings(which)
    SaveBindings(which)
    return true
end

SuuUI.KeybindMode = M

-- THE BASELINE IS TAKEN HERE, NOT IN Enable(), and the difference is a bug that shipped: the
-- settings-panel toggle writes this key DIRECTLY through Settings:Set, so it never reaches Enable().
-- The snapshot was therefore never taken on that path, `baseline` stayed nil, and the change list
-- could only ever say "No changes yet" -- which is exactly what was reported in game. This file's
-- own stated principle is that the setting is the single source of truth; hanging a side effect off
-- one of several writers contradicts it. Anything that must happen when the mode opens belongs on
-- the watcher, which every entry point goes through.
--
-- THE COMBAT GATE MOVES HERE FOR THE SAME REASON. Enable() refuses in combat, but the settings
-- toggle bypassed that too and could open a mode that cannot write a single binding.
SuuUI.Settings:Watch("_layout", "keybind_mode", function(isActive)
    if not isActive then return end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        SuuUI.Settings:Set("_layout", "keybind_mode", false)
        if SuuUI.Components and SuuUI.Components.Notice then
            SuuUI.Components.Notice({
                title   = "Keybind Mode",
                message = "Keybinds cannot be changed in combat. Try again once you are out of "
                    .. "the fight.",
                tone    = "warning",
            })
        end
        return
    end

    M:Snapshot()
end, "_keybindmode_baseline")

-- MUTUAL EXCLUSION, both directions, each written where the mode being LEFT is the one reacting.
-- Two watchers rather than one branch, so neither mode has to know the other's internals -- and
-- so a spec can assert each direction independently.
SuuUI.Settings:Watch("_layout", "keybind_mode", function(isKeybind)
    if isKeybind and SuuUI.ToggleUI and SuuUI.ToggleUI:IsEditMode() then
        SuuUI.ToggleUI:Disable()
    end
end, "_keybindmode_excludes_edit")

SuuUI.Settings:Watch("_layout", "edit_mode", function(isEdit)
    if isEdit and M:IsActive() then
        M:Disable()
    end
end, "_editmode_excludes_keybind")
