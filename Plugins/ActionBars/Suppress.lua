-- Hides Blizzard's bottom action bar cluster, and hands it back exactly.
--
-- THE CONSTRAINT THE PLAN DID NOT SPELL OUT: hiding a Blizzard action bar is itself a
-- protected operation. MainMenuBar holds ActionButton1..12, which inherit
-- SecureActionButtonTemplate, so protection propagates down to them and the client's refusal
-- propagates back up -- Hide() on the bar is refused while InCombatLockdown() is true, and the
-- player gets "Interface action failed because of an AddOn". The same is true of Show() on the
-- way back out, which matters more than it sounds: it is the escape hatch.
--
-- So every visibility change here goes through the same deferral the grid uses. Suppressing
-- during a fight sets a flag and completes on PLAYER_REGEN_ENABLED; so does restoring. The
-- cost is that a bar which re-shows itself mid-fight stays visible until the fight ends, which
-- is a cosmetic lapse rather than a broken UI.
--
-- Three rules from plugin-authoring.md, and each of them is load-bearing:
--
--   * NEVER UnregisterAllEvents. Nothing in the API enumerates a frame's registered events, so
--     unregistering is a one-way door and onDisable could never hand the frame back.
--   * NEVER SetParent(nil), and never reparent one of these at all -- reparenting a frame that
--     holds protected children is protected too.
--   * The suppression flag is cleared BEFORE the restoring Show(), or the OnShow hook we
--     cannot uninstall hides it again on the way out.
--
-- RESOLVED BY CANDIDATE LIST, NEVER BY A LITERAL NAME. The Phase 0 results are a snapshot of
-- one client build, and this one is already mid-migration -- it answers to MainMenuBarArtFrame
-- AND StatusTrackingBarManager in the same breath. A patch that backports one more subsystem
-- renames a frame out from under a literal, and the failure is silent: suppression simply
-- stops hiding something.
local ipairs, pairs, type = ipairs, pairs, type

local M = {}

-- Ordered modern-first, classic-second; the first name that exists wins. An entry that
-- resolves to nothing is skipped with a Debug line rather than raising -- an absent frame is a
-- client generation, not a bug.
--
-- Deliberately NOT here, because nothing replaces them yet and hiding them would take away
-- function the player still needs: the micro menu (Phase 7), the bags (Phase 9) and the XP and
-- reputation bars (Phase 8).
--
-- `PetActionBar` is NOT here either, and for a DIFFERENT reason that must not be tidied away: the
-- pet bar's replacement ADOPTS Blizzard's PetActionButton1..N and reparents them, so hiding their
-- container would take the buttons we are using with it. The stance bar has the opposite shape --
-- SuuUI creates its own buttons from StanceButtonTemplate, so Blizzard's stay in the container and
-- the container can go.
local TARGETS = {
    -- The BUTTONS. Measured in game by walking up from ActionButton1:
    --   ActionButton1 > MainActionBarButtonContainer1 > MainActionBar > UIParent
    -- `MainActionBar` is a DIFFERENT frame from `MainMenuBar` and both exist on this client. Phase
    -- 0 probed for MainMenuBar, found it, and this list took it for the bar -- so the art went and
    -- every button stayed. Existing is not the same as holding the buttons, and only walking the
    -- parent chain settles which is which.
    { id = "main_buttons", names = { "MainActionBar", "MainMenuBarActionButtonContainer" } },
    { id = "main_bar",     names = { "MainMenuBar" } },
    { id = "multi_bl",     names = { "MultiBarBottomLeft" } },
    { id = "multi_br",     names = { "MultiBarBottomRight" } },
    { id = "multi_l",      names = { "MultiBarLeft" } },
    { id = "multi_r",      names = { "MultiBarRight" } },
    -- Bars 6, 7 and 8. Measured present on this client, and Blizzard's own options list them, so
    -- they are real bars a player can turn on -- not retail-only frames that happen to exist. They
    -- were missing from this list entirely because Phase 0 never asked about them: it probed the
    -- five bars TBC is known for and stopped, which is the same mistake as taking MainMenuBar for
    -- the button container. An absent name is skipped, so listing them costs nothing on a client
    -- that lacks them.
    { id = "multi_5",      names = { "MultiBar5" } },
    { id = "multi_6",      names = { "MultiBar6" } },
    { id = "multi_7",      names = { "MultiBar7" } },
    -- The shapeshift bar. Safe to hide because SuuUI creates its OWN buttons from
    -- StanceButtonTemplate rather than adopting Blizzard's -- which is also why Blizzard's own
    -- StanceBar_Update, which walks StanceButton1..N by name, never touches ours.
    --
    -- `StanceBar` is the live name on this client (Edit Mode build); `StanceBarFrame` is the
    -- Classic-Era spelling. Both are listed because an absent name is skipped, and because these
    -- frames have coexisted under two names before -- MainMenuBar and MainActionBar did exactly
    -- that, and picking one cost a round of rework.
    { id = "stance_bar",   names = { "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame" } },
    -- The art and the gryphons. Separate entries because a client that keeps the bar but drops
    -- the art is a shape this list has to be able to describe.
    { id = "bar_art",      names = { "MainMenuBarArtFrame" } },
    { id = "left_cap",     names = { "MainMenuBarLeftEndCap" } },
    { id = "right_cap",    names = { "MainMenuBarRightEndCap" } },
    { id = "max_level",    names = { "MainMenuBarMaxLevelBar" } },
}

-- The buttons this module exists to get off the screen, one per bar family. Used by Verify() as a
-- SELF-CHECK: hiding a container is a means, and these are the end. A container renamed out from
-- under the list above leaves these visible while every other signal says the suppression worked,
-- which is exactly what happened -- so it is checked rather than trusted.
local WITNESS_BUTTONS = {
    "ActionButton1",
    "MultiBarBottomLeftButton1",
    "MultiBarBottomRightButton1",
    "MultiBarLeftButton1",
    "MultiBarRightButton1",
    "MultiBar5Button1",
    "MultiBar6Button1",
    "MultiBar7Button1",
    "StanceButton1",
}

M.WITNESS_BUTTONS = WITNESS_BUTTONS

M.TARGETS = TARGETS

-- Frame -> true for everything this module has hidden. Keyed by frame rather than by name so a
-- client that renames one between builds cannot leave a stale entry behind.
local suppressed = {}
-- HookScript cannot be undone, exactly like hooksecurefunc, so the hook asks `suppressed` on
-- every call rather than assuming it should always hide. That is what lets Restore work.
local hooked  = {}
-- Visibility changes the client refused, waiting for the fight to end.
local pendingHide    = {}
local pendingRestore = {}

local regen

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

-- Every name in an entry that EXISTS is hidden, not just the first.
--
-- This started as first-match-wins and that was silently, badly wrong. Candidate lists mix two
-- different things: genuine RENAMES across client generations, where only one name ever exists and
-- first-match is right, and frames that COEXIST. This client has both `MainMenuBar` and
-- `MainActionBar` -- the first carries the art, the second holds the buttons -- so stopping at the
-- first match hid the gryphons and left all twelve buttons on screen, while IsSuppressed() happily
-- reported success. Hiding every match is identical for a rename and correct for a coexistence.
local function resolveAll(entry, fn)
    local found = 0
    for _, name in ipairs(entry.names) do
        local frame = _G[name]
        if frame then
            found = found + 1
            fn(frame, name)
        end
    end
    return found
end

-- Deferred UNCONDITIONALLY in combat, rather than only for the frames the client would
-- actually refuse. Only the bars hold secure buttons; the art and the gryphons hold none and
-- could legally be hidden mid-fight. Taking them separately would make half the cluster vanish
-- the moment a fight started and the other half appear when it ended, which reads as a bug. The
-- whole cluster moves together or not at all.
local function doHide(frame)
    if inCombat() then
        pendingHide[frame] = true
        return false
    end
    pendingHide[frame] = nil
    frame:Hide()
    return true
end

local function doShow(frame)
    if inCombat() then
        pendingRestore[frame] = true
        return false
    end
    pendingRestore[frame] = nil
    frame:Show()
    return true
end

-- WHICH MECHANISM ACTUALLY DECIDES THE FINAL STATE, because three of them overlap here and
-- mutation testing showed only one can be made to fail:
--
--   * THE ONSHOW HOOK is load-bearing. It consults `suppressed` on every call, so whatever the
--     player asked for LAST is what survives -- including on the restore pass below, where a
--     Show() on a still-suppressed frame is immediately undone. Remove it and suppression stops
--     working outright.
--   * The two queue-cancels (Apply clearing pendingRestore, Restore clearing pendingHide) are
--     FLICKER guards, not correctness ones. Without them a frame can be hidden and shown once
--     each on the same PLAYER_REGEN_ENABLED before the hook settles it, which is a visible
--     blink and nothing worse. Neither can be mutated to a failing assertion, and saying so is
--     better than leaving a reader to wonder which test covers them.
--   * Draining hides before restores is belt and braces for a state the cancels make
--     unreachable; if it ever became reachable it leaves the frame VISIBLE, which is the
--     direction a player can recover from.
local function onRegen()
    for frame in pairs(pendingHide) do
        pendingHide[frame] = nil
        frame:Hide()
    end
    for frame in pairs(pendingRestore) do
        pendingRestore[frame] = nil
        frame:Show()
    end
end

local function syncWatcher()
    local want = next(suppressed) ~= nil
        or next(pendingHide) ~= nil or next(pendingRestore) ~= nil
    if want then
        if not regen then
            regen = CreateFrame("Frame")
            regen:SetScript("OnEvent", onRegen)
        end
        regen:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif regen then
        regen:UnregisterAllEvents()
    end
end

--- Hides every target that exists on this client.
--
-- Idempotent: calling it twice installs no second hook and hides nothing twice.
-- @return table  the ids that resolved, so a caller can log or assert what was found
function M.Apply()
    local found = {}
    for _, entry in ipairs(TARGETS) do
        local n = resolveAll(entry, function(frame)
            pendingRestore[frame] = nil
            suppressed[frame] = true
            if not hooked[frame] then
                hooked[frame] = true
                frame:HookScript("OnShow", function(self)
                    -- Asked on every call, never assumed: this hook outlives Restore.
                    if suppressed[self] then doHide(self) end
                end)
            end
            doHide(frame)
        end)
        if n > 0 then
            found[#found + 1] = entry.id
        elseif SuuUI.Debug then
            SuuUI.Debug("ActionBars: no frame for suppression target " .. entry.id)
        end
    end
    syncWatcher()

    -- Self-check, and it is not decoration: hiding a container is the MEANS, a button off the
    -- screen is the END, and this module already shipped a version where every other signal said
    -- success while twelve buttons sat in plain view. Logged rather than raised -- a stray visible
    -- button is a cosmetic fault, not a reason to take the plugin down mid-session.
    local visible = M.Verify()
    if #visible > 0 and SuuUI.Debug then
        SuuUI.Debug("ActionBars: suppression missed " .. table.concat(visible, ", ") ..
                    " -- their container is not in TARGETS")
    end
    return found
end

--- Which witness buttons are still on screen after suppression, by name.
--
-- Empty is the answer that means it worked. A non-empty list names buttons whose container this
-- module does not know about, which is the failure that hides behind a happy IsSuppressed().
-- @return table  array of frame names
function M.Verify()
    local visible = {}
    for _, name in ipairs(WITNESS_BUTTONS) do
        local b = _G[name]
        if b and b.IsVisible and b:IsVisible() then
            visible[#visible + 1] = name
        end
    end
    return visible
end

--- Shows everything this module hid, and stops claiming it.
--
-- Never touches a frame it did not hide: with suppression switched off we never hid anything,
-- and showing it here would override whatever else did.
function M.Restore()
    for frame in pairs(suppressed) do
        -- Cleared BEFORE the Show, or the hook we cannot uninstall hides it again on the way
        -- out. Same ordering rule as Plugins/UnitFrames restore and DataBar's restoreTop.
        suppressed[frame] = nil
        pendingHide[frame] = nil
        doShow(frame)
    end
    syncWatcher()
end

--- Whether this module is currently claiming the named frame.
-- @param name string
-- @return bool
function M.IsSuppressed(name)
    local frame = _G[name]
    return frame ~= nil and suppressed[frame] == true
end

--- Whether a visibility change is waiting for the fight to end.
-- @return bool
function M.IsDeferred()
    return next(pendingHide) ~= nil or next(pendingRestore) ~= nil
end

SuuUI._ActionBars = SuuUI._ActionBars or {}
SuuUI._ActionBars.Suppress = M
