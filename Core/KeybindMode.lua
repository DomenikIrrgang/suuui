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

-- How many bindings this session has written or cleared. Lives HERE rather than with the bar
-- overlays because it is mode state: the panel reads it to tell "nothing to save" from "unsaved work
-- pending", and a second provider (bags, the spellbook) would otherwise need a counter of its own.
local changed = 0

--- Records that n bindings changed. Called by whichever provider did the writing.
-- @param n number|nil  defaults to 1
function M:NoteChange(n)
    changed = changed + (tonumber(n) or 1)
end

--- How many bindings have been written or cleared since the last save or discard.
function M:ChangedCount() return changed end

--- Whether there is unsaved work.
function M:IsDirty() return changed > 0 end

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
    changed = 0
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
    changed = 0
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
