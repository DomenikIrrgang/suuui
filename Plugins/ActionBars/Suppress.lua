-- Takes Blizzard's bottom action bar cluster off the screen, and hands it back on a reload.
--
-- THE MECHANISM CHANGED, AND THE REASON IS THE WHOLE POINT OF THIS FILE. It used to answer
-- Blizzard's re-show with Hide(), deferring that call whenever the client refused it in combat.
-- That cannot be made to work, and the bug it produced was game-breaking rather than cosmetic:
--
--   * Blizzard's `ActionBarController` registers ACTIONBAR_PAGE_CHANGED -- its own comment reads
--     "This is used for shapeshifts/stances" -- and UPDATE_BONUS_ACTIONBAR, routing both into
--     ValidateActionBarTransition, which calls MainActionBar:Show(), StanceBar:Show(),
--     MultiActionBar_Update() and ManageFramePositions() UNCONDITIONALLY. A warrior changing
--     stance or a druid shifting form IS that event.
--   * Hide() on a frame holding secure buttons is refused while InCombatLockdown() is true, so our
--     answer to that Show() never landed. The cluster stayed on screen -- bags and micro menu with
--     it, since they travel through this same table -- until the fight ended.
--   * A /reload or a reconnect mid-fight was the same failure through a different door: Apply()
--     ran under lockdown, every frame was queued, and the whole cluster was visible.
--
-- So nothing here hides a bar in response to anything any more. The frames are made STRUCTURALLY
-- INCAPABLE of appearing, using only calls the client does not restrict -- which is what ElvUI,
-- Bartender4 and Dominos each arrived at independently:
--
--   1. UnregisterAllEvents on `ActionBarController` and its two event frames, which deletes the
--      re-show mechanism outright rather than racing it. Safe ONLY because every bar override-binds
--      its own keys -- see the note on CONTROLLERS for what silencing them cost when it did not.
--   2. SetParent onto a permanently hidden frame. A child of a hidden parent does not render
--      whatever its own shown flag says, so a later Show() from Blizzard is a no-op.
--
-- Note what is NOT in that list: unregistering each bar's own events. Parking already makes a bar
-- invisible, so silencing it adds nothing.
--
-- There is no race left to lose, and no OnShow hook: the hook this file used to carry existed only
-- to fight step 3's absence.
--
-- MEASURED IN GAME, 2026-08-26, because the whole design turns on which calls survive a lockdown:
--
--   | RegisterStateDriver on a protected frame  | REFUSED   |
--   | SetParent on a frame with a secure child  | REFUSED   |
--   | UnregisterAllEvents                       | permitted |
--   | SetAlpha                                  | permitted |
--
-- The second row is why the reparent defers to PLAYER_REGEN_ENABLED while the controller unload does
-- not. Deferring ONLY the reparent is the right split rather than a compromise: our own buttons
-- cannot be built in combat either (ActionBarGrid:_apply returns early), so alpha-ing the cluster out
-- immediately -- the one other legal move -- would leave the player with no clickable bars at all
-- for the rest of the fight. Killing the controller and leaving Blizzard's bars usable until the swap
-- costs one fight of default bars and loses nothing.
--
-- ALSO MEASURED: a plain Frame holding one SecureActionButtonTemplate child reports
-- `IsProtected() == true, false` -- protected by PROPAGATION, not explicitly. That is the rule both
-- refusals follow, and it is why the art frames were never the problem: they are SIBLINGS of the
-- buttons, not ancestors.
--
-- UNREGISTERALLEVENTS IS A ONE-WAY DOOR. Nothing in the API enumerates a frame's registered events,
-- so Restore() reparents and shows but cannot hand a LIVE frame back -- which is why both `enabled`
-- and `hide_blizzard` carry a ReloadGuard. That trade was ruled on deliberately: a live toggle that
-- leaves the bug in place is worth less than suppression that works. plugin-authoring.md's "never
-- UnregisterAllEvents" rule stands everywhere a live restore is still possible; this is the one
-- documented exception, and the guard is what pays for it.
--
-- STILL NEVER: SetParent(nil), which taints. And never `frame:Hide()` on an Edit-Mode-managed frame
-- when `HideBase` exists -- Edit Mode replaces Hide/Show/IsShown with overrides, and calling an
-- override taints. THIS CLIENT HAS EDIT MODE, so the guarded form is not defensive padding.
--
-- ONE CONSEQUENCE WORTH KNOWING: with the controller's events gone, Blizzard's own vehicle and
-- override bars no longer appear by themselves. SuuUI's bar 1 covers that through its own paging
-- driver (`[overridebar]` and `[possessbar]` in Paging.BuildDriver), which is evaluated by
-- SecureStateDriverManager and is independent of the controller. `PossessActionBar` and
-- `OverrideActionBar` are deliberately NOT suppressed below for the same reason the possess bar was
-- deferred: there is no SuuUI replacement frame, so leaving Blizzard's on screen is the safe side.
--
-- RESOLVED BY CANDIDATE LIST, NEVER BY A LITERAL NAME. The Phase 0 results are a snapshot of one
-- client build, and this one is already mid-migration -- it answers to MainMenuBarArtFrame AND
-- StatusTrackingBarManager in the same breath. A patch that backports one more subsystem renames a
-- frame out from under a literal, and the failure is silent: suppression simply stops hiding
-- something.
local ipairs, pairs, type = ipairs, pairs, type

local M = {}

-- Ordered modern-first, classic-second. EVERY name that exists is claimed, not just the first --
-- see resolveAll. An entry that resolves to nothing is skipped with a Debug line rather than
-- raising: an absent frame is a client generation, not a bug.
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
    -- The shapeshift bar. Safe to claim because SuuUI creates its OWN buttons from
    -- StanceButtonTemplate rather than adopting Blizzard's -- which is also why Blizzard's own
    -- StanceBar_Update, which walks StanceButton1..N by name, never touches ours.
    --
    -- `StanceBar` is the live name on this client (Edit Mode build); `StanceBarFrame` is the
    -- Classic-Era spelling. Both are listed because an absent name is skipped, and because these
    -- frames have coexisted under two names before -- MainMenuBar and MainActionBar did exactly
    -- that, and picking one cost a round of rework.
    { id = "stance_bar",   names = { "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame" } },
    -- The pet bar. `PetActionBar` is the live name on this Edit Mode build; `PetActionBarFrame` is
    -- the Classic-Era spelling. Both listed for the same reason as the stance pair.
    { id = "pet_bar",      names = { "PetActionBar", "PetActionBarFrame" } },
    -- The micro menu. Replaced by the data bar's `left` section in Phase 7.
    --
    -- Safe to claim precisely BECAUSE the replacement calls the panel APIs rather than forwarding
    -- clicks into these buttons: nothing SuuUI draws depends on them existing on screen. Had the
    -- fields forwarded clicks (the first attempt), claiming their targets would have been the pet
    -- bar's problem all over again.
    --
    -- `MicroButtonAndBagsBar` is NOT listed: it is an ANCESTOR of the bag container as well, so
    -- claiming it would cascade to the bags. Same shape as MainActionBar versus MainMenuBar -- the
    -- frame that exists is not always the frame that holds the buttons.
    { id = "micro_menu",   names = { "MicroMenuContainer", "MicroMenu" } },
    -- The experience and reputation bars, replaced in Phase 8.
    --
    -- `StatusTrackingBarManager` is the container; the two inner containers are listed as well
    -- because this client is a hybrid and has produced coexisting frames three times now.
    { id = "watch_bars",   names = { "StatusTrackingBarManager",
                                     "MainStatusTrackingBarContainer",
                                     "SecondaryStatusTrackingBarContainer" } },
    -- The bag bar, replaced in Phase 9 by the data bar's BAGS field.
    --
    -- `BagsBar` is the frame that HOLDS the bag buttons -- established by walking the parent chain
    -- from `MainMenuBarBackpackButton`, which answered "BagsBar". `KeyRingButton` is listed
    -- separately because it is not inside `BagsBar` on every build.
    { id = "bags",         names = { "BagsBar", "KeyRingButton" } },
    -- The art and the gryphons. Separate entries because a client that keeps the bar but drops
    -- the art is a shape this list has to be able to describe.
    { id = "bar_art",      names = { "MainMenuBarArtFrame" } },
    { id = "left_cap",     names = { "MainMenuBarLeftEndCap" } },
    { id = "right_cap",    names = { "MainMenuBarRightEndCap" } },
    { id = "max_level",    names = { "MainMenuBarMaxLevelBar" } },
}

-- Blizzard's bar CONTROLLER and its two event frames, and the events each one keeps.
--
-- THIS IS THE HALF THE OLD MECHANISM HAD NO EQUIVALENT FOR, and the controller alone removes the
-- stance-change symptom: with no events, ActionBarController_UpdateAll never runs, so nothing calls
-- Show() on a bar in the first place.
--
-- THE TWO EVENT FRAMES CAME AND WENT AND CAME BACK, and the round trip is the useful part of this
-- comment. They drive `ActionButton_UpdateAction`, which keeps the cached slot on Blizzard's own
-- `ActionButton1..12` current. Silencing them while bars 1-8 still used BLIZZARD'S BINDING FAMILIES
-- (`ACTIONBUTTON1`..) broke every keybind on those bars: a keypress resolved through the stale cache
-- and fired the pre-form spell, while our own icon -- which reads the `action` attribute the paging
-- snippet rewrote -- showed the right one. Clicking worked throughout, which is what identified it.
--
-- They are silenced again now only because that dependency is GONE: every bar override-binds its own
-- keys onto its own secure button (see `applyOwnBindings`), so nothing of ours resolves through
-- Blizzard's buttons at all. **If that routing is ever narrowed back to a subset of bars, these two
-- entries have to come out in the same change**, or the bug returns exactly as before.
--
-- Blizzard's buttons are deliberately NOT touched beyond this -- no `statehidden`, no per-button
-- Hide. Bartender4 and Dominos both do it; here it would buy nothing, because parking is what makes
-- a bar invisible and its buttons go with it, while `SetAttribute` and `Hide` on a protected button
-- are both refused in combat -- so it would add a deferred protected-call path with no observable
-- effect to test.
--
-- SETTINGS_LOADED lets the page controller spawn properly and UPDATE_EXTRA_ACTIONBAR still lets an
-- ExtraActionButton appear; the two ACTIONBAR_* events on the button frame are what let it cool
-- down. ElvUI keeps exactly these, for exactly these reasons.
local CONTROLLERS = {
    { name = "ActionBarController",        keep = { "SETTINGS_LOADED", "UPDATE_EXTRA_ACTIONBAR" } },
    { name = "ActionBarActionEventsFrame", keep = nil },
    { name = "ActionBarButtonEventsFrame", keep = { "ACTIONBAR_SLOT_CHANGED",
                                                    "ACTIONBAR_UPDATE_COOLDOWN" } },
}

-- The buttons this module exists to get off the screen, one per bar family. Used by Verify() as a
-- SELF-CHECK: claiming a container is a means, and these are the end. A container renamed out from
-- under the list above leaves these visible while every other signal says the suppression worked,
-- which is exactly what happened once -- so it is checked rather than trusted.
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
    "PetActionButton1",
    -- The micro menu's first button.
    "CharacterMicroButton",
}

M.WITNESS_BUTTONS = WITNESS_BUTTONS

M.TARGETS = TARGETS

M.CONTROLLERS = CONTROLLERS

-- frame -> { parent = <original parent>, name = <the name it resolved under> }
--
-- Keyed by frame rather than by name so a client that renames one between builds cannot leave a
-- stale entry behind. The original parent is recorded because it is the only thing Restore has to
-- go on -- there is no "unparent" that means anything.
local claimed = {}
-- Reparents the client refused, waiting for the fight to end. Nothing else defers.
local pendingPark   = {}
local pendingUnpark = {}

-- Set once, and deliberately never cleared: the controllers cannot be re-registered, so there is
-- nothing for a second pass to do and nothing for Restore to undo.
local controllersUnloaded = false

local hider
local regen

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

-- The parking frame. ANONYMOUS on purpose: a named frame can be targeted by a state driver or by
-- another addon walking globals, and this one must stay hidden for the whole session. Created lazily
-- so merely loading the file builds nothing.
local function hiderFrame()
    if not hider then
        hider = CreateFrame("Frame", nil, UIParent)
        hider:Hide()
    end
    return hider
end

M.GetHider = function() return hider end

-- Walks up from a frame looking for something. Bounded as well as terminated, like
-- Dock.WouldCycle: a parent chain is client state, and a corrupt one must not spin.
local function findUp(frame, want)
    local f = frame
    local steps = 0
    while f and steps < 32 do
        if want(f) then return true end
        f = f.GetParent and f:GetParent() or nil
        steps = steps + 1
    end
    return false
end

-- Whether an ANCESTOR of this frame is already claimed.
--
-- The candidate lists deliberately mix two shapes: genuine renames across client generations, and
-- parent/child pairs -- MicroMenuContainer with MicroMenu, BagsBar with KeyRingButton, MainMenuBar
-- with its four art frames. Only a rename wants claiming twice. Parking an ancestor already takes
-- the child off screen, and parking the child as well would reparent it OUT of the container it
-- belongs to, which is real damage rather than redundant work: the micro menu's parentage is a fact
-- this codebase pins deliberately, because it is what keeps the two suppressions independent.
local function ancestorClaimed(frame)
    local parent = frame.GetParent and frame:GetParent() or nil
    if not parent then return false end
    return findUp(parent, function(f) return claimed[f] ~= nil end)
end

-- Every name in an entry that EXISTS is claimed, not just the first.
--
-- This started as first-match-wins and that was silently, badly wrong. Candidate lists mix two
-- different things: genuine RENAMES across client generations, where only one name ever exists and
-- first-match is right, and frames that COEXIST. This client has both `MainMenuBar` and
-- `MainActionBar` -- the first carries the art, the second holds the buttons -- so stopping at the
-- first match hid the gryphons and left all twelve buttons on screen, while IsSuppressed() happily
-- reported success.
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

-- Step 1. Legal in combat, so it is never deferred -- which is what makes a mid-combat login safe
-- even though the reparent below has to wait.
local function unloadControllers()
    if controllersUnloaded then return end
    controllersUnloaded = true
    for _, def in ipairs(CONTROLLERS) do
        local frame = _G[def.name]
        if frame and frame.UnregisterAllEvents then
            frame:UnregisterAllEvents()
            if def.keep then
                for _, event in ipairs(def.keep) do
                    -- pcall: an event absent on this client generation must cost a missing
                    -- ExtraActionButton, never the plugin.
                    pcall(frame.RegisterEvent, frame, event)
                end
            end
        end
    end
end

-- Step 3. The only thing here the client can refuse.
local function park(frame)
    if inCombat() then
        pendingPark[frame] = true
        return false
    end
    pendingPark[frame] = nil
    -- Edit Mode swaps Hide/Show/IsShown for overrides on the frames it manages, and calling an
    -- override taints. HideBase is the untainted one; a client without Edit Mode has only Hide.
    local hide = frame.HideBase or frame.Hide
    if hide then hide(frame) end
    frame:SetParent(hiderFrame())
    return true
end

local function unpark(frame, rec)
    if inCombat() then
        pendingUnpark[frame] = rec
        return false
    end
    pendingUnpark[frame] = nil
    frame:SetParent(rec.parent or UIParent)
    local show = frame.ShowBase or frame.Show
    if show then show(frame) end
    return true
end

-- Drains what combat refused. Parks before unparks: with the queue-cancels below the two can never
-- hold the same frame, and if that ever became reachable, ending up VISIBLE is the direction a
-- player can recover from.
local function onRegen()
    for frame in pairs(pendingPark) do
        pendingPark[frame] = nil
        park(frame)
    end
    for frame, rec in pairs(pendingUnpark) do
        pendingUnpark[frame] = nil
        unpark(frame, rec)
    end
end

-- Registered only while something is actually waiting. Nothing else can add to either queue --
-- there is no hook any more -- so an empty pair means there is nothing to wake up for.
local function syncWatcher()
    local want = next(pendingPark) ~= nil or next(pendingUnpark) ~= nil
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

--- Claims every target that exists on this client and parks it out of sight.
--
-- Idempotent: a second call re-parks nothing and unregisters nothing twice.
-- @return table  the ids that resolved, so a caller can log or assert what was found
function M.Apply()
    unloadControllers()

    local found = {}
    for _, entry in ipairs(TARGETS) do
        local n = resolveAll(entry, function(frame, name)
            pendingUnpark[frame] = nil
            if ancestorClaimed(frame) then return end
            if not claimed[frame] then
                claimed[frame] = { parent = frame:GetParent(), name = name }
                -- DELIBERATELY NOT UnregisterAllEvents on the bar. Parking is what makes it
                -- invisible -- a child of a hidden parent renders nothing whatever it has
                -- registered -- so silencing it buys no visibility and costs the keybind path:
                -- Blizzard's own action plumbing is what keeps the cached slots the
                -- ACTIONBUTTON* families resolve through, and bars 1-8 use those families. See
                -- the note on CONTROLLERS above; this is the same trade, and it was found by a
                -- keypress in cat form firing the out-of-form spell.
                --
                -- Keep Blizzard's layout pass off a frame that now lives somewhere else. Both
                -- halves, because they are read by different code: the field by
                -- UIParent_ManageFramePositions, the table entry by the Edit Mode position manager.
                frame.ignoreFramePositionManager = true
                local managed = _G.UIPARENT_MANAGED_FRAME_POSITIONS
                if type(managed) == "table" then managed[name] = nil end
            end
            park(frame)
        end)
        if n > 0 then
            found[#found + 1] = entry.id
        elseif SuuUI.Debug then
            SuuUI.Debug("ActionBars: no frame for suppression target " .. entry.id)
        end
    end
    syncWatcher()

    -- Self-check, and it is not decoration: claiming a container is the MEANS, a button off the
    -- screen is the END, and this module already shipped a version where every other signal said
    -- success while twelve buttons sat in plain view. Logged rather than raised -- a stray visible
    -- button is a cosmetic fault, not a reason to take the plugin down mid-session.
    --
    -- Skipped while a park is still queued, because during a fight the answer is "yes, still
    -- visible" and that is correct rather than a failure. The old version ran it at exactly the
    -- moment it was guaranteed to fail and reported a misleading reason.
    if not M.IsDeferred() then
        local visible = M.Verify()
        if #visible > 0 and SuuUI.Debug then
            SuuUI.Debug("ActionBars: suppression missed " .. table.concat(visible, ", ") ..
                        " -- their container is not in TARGETS")
        end
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

--- Puts everything this module claimed back where it found it, and stops claiming it.
--
-- Never touches a frame it did not claim: with suppression switched off we never claimed anything,
-- and showing it here would override whatever else did.
--
-- THE FRAMES COME BACK VISIBLE BUT INERT. Their events are gone and cannot be restored, so they
-- will not update until the UI reloads -- which is why the settings that reach here are
-- reload-guarded. Restoring position and visibility is still worth doing: it is what makes the
-- reload cosmetically seamless, and it is the whole behaviour a spec can assert.
function M.Restore()
    for frame, rec in pairs(claimed) do
        claimed[frame] = nil
        pendingPark[frame] = nil
        unpark(frame, rec)
    end
    syncWatcher()
end

--- Whether the named frame is currently parked out of sight.
--
-- Reports the SCREEN, not the intent. It used to answer from the claim table alone, which meant it
-- said true throughout a fight in which the frame was still in plain view -- the single most
-- misleading signal in the old mechanism. Ask IsClaimed for ownership and IsDeferred for the queue.
--
-- Answers true for a frame parked via an ANCESTOR as well as one parked directly, because that is
-- the same fact from the player's side: MainMenuBarArtFrame is off the screen either way, and
-- ancestorClaimed deliberately leaves it unclaimed.
-- @param name string
-- @return bool
function M.IsSuppressed(name)
    local frame = _G[name]
    if not frame or not hider then return false end
    return findUp(frame, function(f) return f == hider end)
end

--- Whether this module owns the named frame, parked yet or not.
-- @param name string
-- @return bool
function M.IsClaimed(name)
    local frame = _G[name]
    return frame ~= nil and claimed[frame] ~= nil
end

--- Whether a reparent is waiting for the fight to end.
-- @return bool
function M.IsDeferred()
    return next(pendingPark) ~= nil or next(pendingUnpark) ~= nil
end

--- Whether Blizzard's bar drivers have been silenced. One-way, by construction.
-- @return bool
function M.ControllersUnloaded()
    return controllersUnloaded
end

SuuUI._ActionBars = SuuUI._ActionBars or {}
SuuUI._ActionBars.Suppress = M
