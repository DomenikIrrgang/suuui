-- SuuUI's own action bars.
--
-- PHASE 5a: all five bars, each independently positionable, plus secure paging on bar 1.
-- Blizzard's cluster is suppressed by Plugins/ActionBars/Suppress.lua (phase 4b).
--
-- The B3 DOCK IS PHASE 5b, deliberately split off. Phase 5 as planned bundled "five bars exist"
-- with "bars attach to a dock", and the first is what makes the feature usable -- sixty buttons a
-- player can place -- while the second is an arrangement convenience on top of it. Splitting them
-- keeps each reviewable, the same reason phase 4 was split.
--
-- EVERY SLOT BLOCK HERE WAS MEASURED IN GAME, not assumed. See the Round 3 table in
-- .kiro/specs/bottom-ui-replacement.md: bar 1 is 1..12 and PAGES, while the four multibars are
-- fixed to 61..72, 49..60, 37..48 and 25..36. Pages 3..6 of bar 1 therefore land on the very
-- slots the other bars own, which is why two SuuUI buttons can legitimately address one slot and
-- why only bar 1 gets a state driver.
local ipairs = ipairs

local PLUGIN_ID = "action_bars"
local OWNER     = "action_bars"

local MAX_BUTTONS = 12
-- The client's own pet-slot count, with ElvUI's fallback. Read rather than hardcoded, but bounded:
-- a client that renames the global must not silently give the bar zero cells.
local PET_SLOTS = (type(NUM_PET_ACTION_SLOTS) == "number" and NUM_PET_ACTION_SLOTS) or 10

-- One entry per bar. `first` is the slot the bar starts at; `paged` marks the only bar whose
-- slots move at runtime.
--
-- BOTH THE SLOT BLOCK AND THE BINDING FAMILY WERE MEASURED IN GAME. Blizzard's own buttons carry
-- their binding family in a `buttonType` field, and reading it corrected a guess that had bars 4
-- and 5 swapped: the numbering does NOT follow the frame names in the order you would expect --
-- `MultiBarLeft` is MULTIACTIONBAR**4** and `MultiBarRight` is MULTIACTIONBAR**3**. Getting it
-- wrong shows the wrong hotkey on a working button, which is why it survived until the probe.
--
-- `ActionButton1.buttonType` is nil, and that is expected rather than missing: the main bar is
-- the default family, so its buttons set no override. `ACTIONBUTTON1` is the client's own binding
-- name for it. That one command family is therefore the only entry here still resting on the
-- documented name rather than on a reading -- if bar 1's hotkeys come up blank in game, it is the
-- first thing to look at.
local BARS = {
    {
        id = 1, label = "Bar 1", first = 1, paged = true,
        bindingPrefix = "ACTIONBUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 28 },
    },
    {
        -- MultiBarBottomLeft
        id = 2, label = "Bar 2", first = 61,
        bindingPrefix = "MULTIACTIONBAR1BUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 68 },
    },
    {
        -- MultiBarBottomRight
        id = 3, label = "Bar 3", first = 49,
        bindingPrefix = "MULTIACTIONBAR2BUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 108 },
        -- Off by default: five bars on screen at first login is sixty buttons a new player did
        -- not ask for. Bars 1 and 2 are the pair Blizzard itself shows by default.
        enabled = false,
    },
    {
        -- MultiBarLeft, which is MULTIACTIONBAR4 and not 3. Measured, not inferred.
        id = 4, label = "Bar 4", first = 37,
        bindingPrefix = "MULTIACTIONBAR4BUTTON",
        -- Down the right edge, in one column, which is where the client puts this one.
        position = { point = "RIGHT", relPoint = "RIGHT", x = -8, y = 0 },
        rows = MAX_BUTTONS,
        enabled = false,
    },
    {
        -- MultiBarRight, which is MULTIACTIONBAR3.
        id = 5, label = "Bar 5", first = 25,
        bindingPrefix = "MULTIACTIONBAR3BUTTON",
        position = { point = "RIGHT", relPoint = "RIGHT", x = -48, y = 0 },
        rows = MAX_BUTTONS,
        enabled = false,
    },
    -- Bars 6 to 8: MultiBar5, MultiBar6, MultiBar7, slots 145-156 / 157-168 / 169-180. Present on
    -- this client and listed in Blizzard's own options, and missed entirely by Phase 0, which
    -- probed the five bars TBC is known for and stopped.
    --
    -- Note the numbering DOES follow the frame name here -- MultiBar5 is MULTIACTIONBAR5 -- which is
    -- the opposite of bars 4 and 5, where MultiBarLeft is 4 and MultiBarRight is 3. There is no rule
    -- to infer; each pairing was read off Blizzard's own `buttonType` field.
    --
    -- Horizontal and stacked upward rather than more columns down the right edge: three extra
    -- vertical bars beside bars 4 and 5 would wall off a third of the screen.
    {
        id = 6, label = "Bar 6", first = 145,
        bindingPrefix = "MULTIACTIONBAR5BUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 148 },
        enabled = false,
    },
    {
        id = 7, label = "Bar 7", first = 157,
        bindingPrefix = "MULTIACTIONBAR6BUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 188 },
        enabled = false,
    },
    {
        id = 8, label = "Bar 8", first = 169,
        bindingPrefix = "MULTIACTIONBAR7BUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 228 },
        enabled = false,
    },
    -- BARS 9 TO 13: the action slots NO Blizzard bar exposes.
    --
    -- Measured in game, and this is the gap that mattered: of 72 abilities on the character, 27 sat in
    -- slots SuuUI could not reach. Pages 2 and 7-10 (slots 13-24 and 73-120) have no Blizzard frame and
    -- no Blizzard binding family, so a UI that only mirrors Blizzard's bars simply cannot show them --
    -- yet the client stores actions there and every serious bar addon exposes them. ElvUI calls these
    -- its bar2 and bar7-10, and page N is slots (N-1)*12+1 upward, which is how the two numbering
    -- schemes line up:
    --
    --   page 1  = 1-12    Bar 1        page 6  = 61-72   Bar 2
    --   page 2  = 13-24   Bar 9  <--   page 7  = 73-84   Bar 10 <--
    --   page 3  = 25-36   Bar 5        page 8  = 85-96   Bar 11 <--
    --   page 4  = 37-48   Bar 4        page 9  = 97-108  Bar 12 <--
    --   page 5  = 49-60   Bar 3        page 10 = 109-120 Bar 13 <--
    --   page 13 = 145-156 Bar 6        page 14/15 = 157-180  Bars 7, 8
    --
    -- NUMBERED 9 UPWARD RATHER THAN RENUMBERED TO MATCH THE PAGES. Bars 1-8 already correspond to
    -- Blizzard's own Action Bar 1-8, which is the numbering a player reads in the client's keybinding
    -- UI, and the ids are profile data as well as dock participant ids -- renumbering would move every
    -- stored position and silently repoint every dock attachment.
    --
    -- `ownBindings` marks the ones whose binding names SuuUI DECLARES itself, in Bindings.xml, and
    -- that is all it means -- it does not decide which bars get routed. EVERY bar routes its own keys
    -- through SetOverrideBindingClick, including these eight, because an override beats the base
    -- binding and intercepting is what removes the dependency on Blizzard's own action plumbing. See
    -- applyOwnBindings for what depending on it cost. Pages 2 and 7-10 need the declaration because
    -- Blizzard ships no binding family for those slots at all.
    {
        id = 9, label = "Bar 9", first = 13, page = 2, ownBindings = true,
        bindingPrefix = "SUUUIBAR9BUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 268 },
        enabled = false,
    },
    {
        id = 10, label = "Bar 10", first = 73, page = 7, ownBindings = true,
        bindingPrefix = "SUUUIBAR10BUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 308 },
        enabled = false,
    },
    {
        id = 11, label = "Bar 11", first = 85, page = 8, ownBindings = true,
        bindingPrefix = "SUUUIBAR11BUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 348 },
        enabled = false,
    },
    {
        id = 12, label = "Bar 12", first = 97, page = 9, ownBindings = true,
        bindingPrefix = "SUUUIBAR12BUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 388 },
        enabled = false,
    },
    {
        id = 13, label = "Bar 13", first = 109, page = 10, ownBindings = true,
        bindingPrefix = "SUUUIBAR13BUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 428 },
        enabled = false,
    },
    -- The two CLASS BARS. Listed here rather than given their own plugin because everything around a
    -- bar is identical: a position, a moveable frame, a settings tab, and bar-to-bar docking. Only
    -- the buttons differ, and that is one factory each.
    --
    -- Both take a STRING id, deliberately. Slots 13-24 are still unclaimed and would naturally
    -- become "Bar 9", so numbering either of these would collide with that later and silently share
    -- its settings keys. `order` is separate and numeric because the dock sorts a stack by it, and
    -- comparing a string with a number is a hard error in Lua.

    -- The PET bar. Its buttons are our own ActionButtons with kind="pet" -- the same secure template
    -- and the same `action` attribute as an action slot, only `type="pet"`. Verified from
    -- LibActionButton, which does exactly that inside a live secure snippet on this client.
    --
    -- Unlike the stance bar its slot count is FIXED, not derived: Blizzard's pet bar is always
    -- NUM_PET_ACTION_SLOTS wide with the unused slots simply empty, so the count is a player setting
    -- like every action bar rather than something read from the client.
    {
        id = "pet", label = "Pet", kind = "pet", order = 98,
        bindingPrefix = "BONUSACTIONBUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 260, y = 28 },
    },

    -- The SHAPESHIFT bar. NOT "stances" -- it is whatever mechanic the client hangs on the
    -- shapeshift API: warrior stances, druid forms, rogue stealth, priest shadowform, PALADIN AURAS.
    -- A paladin has eight, which is the widest case it has to size for and was measured in game.
    {
        id = "stance", label = "Stance", kind = "stance", order = 99,
        bindingPrefix = "SHAPESHIFTBUTTON",
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = -260, y = 28 },
        -- ON by default, unlike bars 3-8. A paladin's auras and a warrior's stances are not extra
        -- buttons a player opted into -- they are core class controls, and Blizzard shows this bar
        -- by default too.
    },
}

-- Whether a bar's cells are shapeshift forms rather than action slots.
local function isStance(def)
    return def.kind == "stance"
end

-- Whether a bar's cells are pet commands.
local function isPet(def)
    return def.kind == "pet"
end

-- Whether a cell's identity IS its index, rather than an offset into a measured slot block. True for
-- both class bars: form 2 lives in cell 2, pet command 2 in cell 2. Only the eight action bars map
-- a cell onto a slot somewhere else in the client's 1-180 range.
local function usesIndexSlots(def)
    return isStance(def) or isPet(def)
end

-- The visibility macro conditional for the pet bar, evaluated by the CLIENT in its secure
-- environment. This is the one thing on the pet bar that cannot be done from Lua: a pet is summoned,
-- dismissed, killed and revived mid-combat, and hiding a frame holding protected buttons is refused
-- while the player is in a fight. A state driver is evaluated inside the secure environment, so it
-- works in combat and taints nothing.
--
-- The conditionals are ElvUI's TBC branch verbatim, and the omission is deliberate: `novehicleui` is
-- present in its Retail and Wrath strings and absent here, because vehicles are not a mechanic on
-- this client. `nooverridebar` and `nopossessbar` ARE, so a possessed unit's bar replaces the pet's
-- rather than fighting it.
local PET_VISIBILITY = "[pet,nooverridebar,nopossessbar] show; hide"

-- How many cells a stance bar has: whatever the client says the player's form count is.
--
-- READ, NEVER ASSUMED FROM A CONSTANT. NUM_STANCE_SLOTS is an array bound (10), not what a class
-- has -- a mage has 0, a rogue 1, a warrior 3, a paladin 8. Sizing to the bound would leave a
-- paladin correct by accident and everyone else with a row of empty cells.
local function stanceFormCount()
    if type(GetNumShapeshiftForms) ~= "function" then return 0 end
    return GetNumShapeshiftForms() or 0
end

local function key(def, name)
    return "bar" .. def.id .. "_" .. name
end

-- One attach point per bar, so any bar can be a dock. Namespaced by plugin, as AttachPoints requires.
local function dockPoint(id)
    return "actionbar.dock." .. id
end

local function get(k, fallback)
    local v = SuuUI.Settings:Get(PLUGIN_ID, k)
    if v == nil then return fallback end
    return v
end

-- Which bar this one is set to attach to, as the id STRING it was stored as, or nil for free.
--
-- Not coerced to a number: bar ids are not all numeric (the stance bar's is "stance"), and a
-- tonumber here silently turned that into nil, which reads as "not docked".
local function attachTarget(def)
    local v = get(key(def, "attach"), "detached")
    if v == nil or v == "detached" or v == "" then return nil end
    return tostring(v)
end

-- Walks the attach graph as the SETTINGS describe it, which is what a validator has to do: it runs
-- before the value is stored, so the live dock graph does not know about it yet.
--
-- Bounded as well as identity-checked. A stored graph that already contains a loop -- a hand-edited
-- profile, a version that predates this validator -- must not spin here.
--
-- Delegates to the shared registry rather than reading this plugin's own keys, because the graph now
-- SPANS PLUGINS: a watch bar attached to bar 1 while bar 1 is attached to that watch bar is a real
-- loop, and a walk that only knew about action bars would let it through. The registry asks each
-- participant for its own target, whichever plugin owns it -- and keeps the bound and the
-- identity check that were here.
local function wouldCycleInSettings(fromId, toId)
    return SuuUI.Dock.WouldCycleIds(fromId, toId)
end

--- Registers every bar as a dock participant.
--
-- Declarative, and done before any bar exists, because a participant entry needs no handle -- only
-- identity, its attach point's name, and how to read its stored target. That is what lets the dropdown
-- keep offering a bar that is currently switched off, exactly as the static list did.
--
-- Ids stay the PLAIN bar ids they have always been ("1".."8", "stance", "pet"), because those are
-- already written into player profiles. Anything registering later namespaces its own.
local function registerParticipants()
    for _, def in ipairs(BARS) do
        SuuUI.Dock.RegisterParticipant(def.id, {
            label      = def.label,
            group      = "Action Bars",
            sort       = def.order or 0,
            point      = dockPoint(def.id),
            attachedTo = function() return attachTarget(def) end,
        })
    end
end

-- Asks for a dock, and keeps asking: Request fires the callback immediately with whatever is there --
-- including nil -- and again whenever it appears or goes away. So a bar set to attach to one that
-- does not exist yet is not a special case, and neither is that bar being switched off underneath it.
local function requestDock(p, def)
    local targetId = attachTarget(def)
    if not targetId then return end
    -- Resolved through the REGISTRY rather than built from this plugin's own prefix. The target may
    -- belong to another plugin -- a watch bar publishes "watchbar.dock.xp", not "actionbar.dock.watch:xp"
    -- -- and building the name here is what made an action bar silently fail to dock to one: the request
    -- went to a point that never existed, and Request's "not there yet" path looks identical to that.
    local point = SuuUI.Dock.PointFor(targetId)
    if not point then return end
    SuuUI.AttachPoints:Request(point, function(provider)
        local grid = p._bars[def.id]
        if not grid then return end
        if provider and provider.Attach then
            provider.Attach(grid, {
                -- Ordered by bar id so a stack is stable across the order settings happen to fire in.
                order = def.order or def.id,
                edge  = get(key(def, "attach_edge"), "above"),
            })
        end
    end, OWNER .. ".dock." .. def.id)
end

local function slotsFor(def, count)
    local out = {}
    -- A class bar's cell IS its index -- form 2 in cell 2, pet command 2 in cell 2 -- rather than an
    -- offset into a measured slot block.
    if usesIndexSlots(def) then
        for i = 1, count do out[i] = i end
        return out
    end
    for i = 1, count do out[i] = def.first + i - 1 end
    return out
end

local function bindingsFor(def, count)
    local out = {}
    for i = 1, count do out[i] = def.bindingPrefix .. i end
    return out
end

--- Routes this bar's declared keys to clicks on its own buttons.
--
-- ONLY for bars whose binding names SuuUI declares itself. A Blizzard family acts on the SLOT, so bars
-- EVERY bar routes its own keys, and the gate that used to exempt bars 1-8 is gone.
--
-- That exemption was true on its own terms -- whatever is bound to ACTIONBUTTON1 fires UseAction(1)
-- whether Blizzard's button is on screen or not -- but it made the addon depend on BLIZZARD'S action
-- plumbing staying alive, because that path resolves through the cached slot on its own
-- ActionButton1..12. Suppression silenced that plumbing and every keybind on bars 1-8 started firing
-- the pre-form spell while our own icons stayed correct. Two mechanisms for one job, and the seam is
-- where the bug lived.
--
-- SO WE INTERCEPT INSTEAD. An override binding BEATS the base binding, so reading the player's key
-- with GetBindingKey("ACTIONBUTTON1") and re-routing it to a click on our own button means Blizzard's
-- path is never reached. Nothing migrates: their saved keys are untouched, the client's keybinding UI
-- still shows the families it always did, and `ownBindings` goes back to meaning only what its name
-- says -- that SuuUI DECLARES those names in Bindings.xml, which pages 2 and 7-10 need because
-- Blizzard ships no family for them.
--
-- Cleared and reapplied wholesale rather than diffed: the set is at most twelve keys, and a diff would
-- have to track the player's rebinding to know what to remove.
local function applyOwnBindings(p, def)
    local grid = p._bars[def.id]
    if not grid then return end
    if not def.bindingPrefix then return end

    -- SetOverrideBindingClick is refused in combat, like any other secure mutation. Deferred through the
    -- same pending set the attach transition uses, so leaving combat drains both.
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        p._pendingBindings = p._pendingBindings or {}
        p._pendingBindings[def.id] = def
        return
    end
    if p._pendingBindings then p._pendingBindings[def.id] = nil end

    local frame = grid:GetFrame()
    if type(ClearOverrideBindings) == "function" then ClearOverrideBindings(frame) end
    if type(SetOverrideBindingClick) ~= "function" then return end

    local buttons = grid:GetButtons()
    for i = 1, #buttons do
        local command = def.bindingPrefix .. i
        local key = GetBindingKey and GetBindingKey(command) or nil
        -- The button's GLOBAL NAME, which is what the client resolves -- hence namePrefix being set on
        -- every grid rather than only for /framestack.
        local name = "SuuUIBar" .. def.id .. "Button" .. i
        if key and key ~= "" then
            SetOverrideBindingClick(frame, false, key, name, "LeftButton")
        end
    end
end

---------------------------------------------------------------------------
-- Bar lifecycle
---------------------------------------------------------------------------

-- Whether a bar is currently taking its position from another bar rather than owning it.
local function isDocked(def)
    return attachTarget(def) ~= nil
end

-- Gives a bar its own moveable frame, or takes it away.
--
-- A DOCKED BAR MUST NOT BE MOVEABLE, and not merely as a nicety: MoveableFrame installs a watcher on
-- the stored position that re-anchors the frame whenever that value changes, so leaving it in place
-- would have two owners writing the same frame's anchor -- the dock on every reflow, the watcher on
-- every profile load -- and the winner would be whichever fired last.
local function syncMoveable(p, def)
    local grid = p._bars[def.id]
    if not grid then return end
    local frame = grid:GetFrame()
    local docked = isDocked(def)

    if docked and frame._suuui_moveable then
        SuuUI.MoveableFrame:Remove(frame)
    elseif not docked and not frame._suuui_moveable then
        SuuUI.MoveableFrame:Apply(frame, {
            pluginId    = PLUGIN_ID,
            key         = key(def, "position"),
            displayName = def.label,
            defaults    = def.position,
        })
    end
end

-- Builds a shapeshift-bar cell. Passed to ActionBarGrid as its buttonFactory.
--
-- A stance button CANNOT be an ActionButton: it carries no `type` attribute and CastShapeshiftForm
-- is blocked for addon code (both probed in game), so it has to inherit Blizzard's
-- StanceButtonTemplate. The grid does not care -- the plate, layout, dividers, padding and resize
-- deferral are identical either way.
local function stanceButtonFactory(bp, parent)
    return SuuUI.Components.StanceButton({
        form       = bp.slot,
        size       = bp.size,
        binding    = bp.binding,
        showHotkey = bp.showHotkey,
        name       = bp.name,
    }, parent)
end

-- Builds a pet-bar cell. Passed to ActionBarGrid as its buttonFactory.
--
-- This is an ordinary ActionButton with kind="pet", which is the whole point of the kind seam: the
-- secure template, the click registration and the press-versus-release gate are shared with bars
-- 1-8 rather than reimplemented, and that gate is the part that was got wrong once.
local function petButtonFactory(bp, parent)
    return SuuUI.Components.ActionButton({
        kind       = "pet",
        slot       = bp.slot,
        size       = bp.size,
        binding    = bp.binding,
        showHotkey = bp.showHotkey,
        name       = bp.name,
        -- A pet command has no charge count and no macro name. The provider answers 0 and nil so
        -- nothing would draw anyway; stated here so the intent is not mistaken for an omission.
        showMacroText = false,
        showCount     = false,
    }, parent)
end

-- Hands the pet bar's visibility to the CLIENT, permanently.
--
-- Nothing in this plugin ever calls Show or Hide on the pet bar after this: the driver owns it. Two
-- owners would fight, and ours would lose in combat anyway, which is exactly the case that matters.
local function applyPetVisibility(p, def)
    local grid = p._bars[def.id]
    if not grid then return end
    if type(RegisterStateDriver) ~= "function" then return end
    RegisterStateDriver(grid:GetFrame(), "visibility", PET_VISIBILITY)
end

-- A stance bar with no forms is HIDDEN ENTIRELY -- a mage must not get an empty plate.
--
-- There is no class check anywhere, deliberately: the condition is purely a count of zero, which is
-- how the client itself expresses it and how ElvUI does it. A class list would be one more thing to
-- keep in step with the game.
--
-- A plain Hide is enough here rather than a secure state driver, because the form COUNT only changes
-- at a trainer -- never mid-fight. What changes in combat is which form is ACTIVE, and that repaints
-- without touching geometry or visibility.
local function syncStanceVisibility(p, def)
    local grid = p._bars[def.id]
    if not grid then return end
    if stanceFormCount() > 0 then grid:Show() else grid:Hide() end
end

-- Re-derives the stance bar's cell count from the client and re-checks whether it should exist.
--
-- Called on the PLURAL shapeshift event only. The singular one means a different form became
-- active, which the buttons handle themselves -- routing it here would run a geometry pass on
-- every stance dance, and in combat that pass is refused.
local function syncStanceForms(p)
    for _, def in ipairs(BARS) do
        if isStance(def) then
            local grid = p._bars[def.id]
            if grid then
                local count = stanceFormCount()
                -- SKIPPED WHEN THE COUNT HAS NOT MOVED, and this is not a micro-optimisation.
                -- SetSlots has no equality short-circuit of its own, so it always runs a geometry
                -- pass -- and the client fires this event on login and on other changes that leave
                -- the count alone. In combat that pass is deferred, which would leave the bar
                -- waiting on PLAYER_REGEN_ENABLED for no reason at all.
                if count ~= #grid:GetSlots() then
                    grid:SetSlots(slotsFor(def, count), bindingsFor(def, count))
                    -- INSIDE the short-circuit, not beside it. It used to sit outside, so it ran on
                    -- every plural event whether the count had moved or not -- and the client fires
                    -- this family repeatedly, which is why LibActionButton throttles it to 1/sec
                    -- ("Blizzard broke the event and its now extremely spammy in some clients").
                    --
                    -- Whether Show/Hide on this grid is actually PROTECTED is UNMEASURED: the grid
                    -- parents StanceButtonTemplate CheckButtons, and if that template is secure then
                    -- protection propagates down and the refusal propagates back up, making every
                    -- stance dance in combat a refused call. The harness models the template without
                    -- _secure and the in-game probes covered RegisterStateDriver and SetParent, not
                    -- this -- so treat the protection as unconfirmed and the call as simply wasted.
                    --
                    -- Nothing is lost by moving it either way: visibility here is purely a function
                    -- of the count, so a count that has not changed cannot have changed the answer.
                    syncStanceVisibility(p, def)
                end
            end
        end
    end
end

local function buildBar(p, def)
    if p._bars[def.id] then return end

    local count
    if isStance(def) then
        count = stanceFormCount()
    elseif isPet(def) then
        count = get(key(def, "buttons"), PET_SLOTS)
    else
        count = get(key(def, "buttons"), MAX_BUTTONS)
    end
    local root  = SuuUI.UIRoot:GetRootContainer()

    local grid = SuuUI.Components.ActionBarGrid({
        slots         = slotsFor(def, count),
        bindings      = bindingsFor(def, count),
        buttonFactory = (isStance(def) and stanceButtonFactory)
                        or (isPet(def) and petButtonFactory)
                        or nil,
        rows          = get(key(def, "rows"), def.rows or 1),
        buttonSize    = get(key(def, "button_size"), 32),
        spacing       = get(key(def, "spacing"), 0),
        showHotkeys   = get(key(def, "show_hotkeys"), true),
        showMacroText = get(key(def, "show_macro_text"), true),
        showCount     = get(key(def, "show_count"), true),
        -- Named so /framestack can identify them and a click-casting addon can bind them.
        namePrefix    = "SuuUIBar" .. def.id .. "Button",
    }, root:GetFrame())
    p._bars[def.id] = grid

    local frame = grid:GetFrame()
    -- Player-facing game UI, so the content rung -- stated through the library's layer system
    -- rather than left to inherit, so a settings window or modal is guaranteed to draw over it.
    SuuUI.UIRoot:SetLayer(frame, "normal")

    -- EVERY bar offers itself as a dock, so any bar can carry any other. Published regardless of
    -- whether anything is attached, because Request fires immediately with whatever is there: a bar
    -- waiting on one that does not exist yet is then not a special case.
    SuuUI.AttachPoints:Publish(dockPoint(def.id), {
        frame  = frame,
        Attach = function(child, opts)
            return SuuUI.Dock.Attach(grid, child, opts)
        end,
        Detach = function(child)
            return SuuUI.Dock.Detach(grid, child)
        end,
    })

    if isStance(def) then
        syncStanceVisibility(p, def)
    elseif isPet(def) then
        applyPetVisibility(p, def)
    end

    -- Only bar 1 pages; the others are fixed to their measured block.
    if def.paged then
        SuuUI._ActionBars.Paging.Attach(grid, { pageSize = MAX_BUTTONS })
    end

    -- Moveable only while it owns its own position. A docked bar takes it from the dock.
    syncMoveable(p, def)
    if isDocked(def) then
        requestDock(p, def)
    end

    -- Claims this bar's keys, for the bars whose binding names SuuUI declares itself. A no-op for the
    -- eight that use a Blizzard family, since those act on the slot and need no routing.
    --
    -- ALSO SUBSCRIBED TO THE GRID'S OWN CHILDREN_CHANGED, rather than trusting the call above to be
    -- enough. A bar built in combat has NO BUTTONS yet -- SetSlots defers its geometry pass -- so there
    -- is nothing to bind a key to, and catching up on PLAYER_REGEN_ENABLED raced the grid's own
    -- catch-up on the same event. The signal exists for exactly this: the buttons announce themselves,
    -- and the keys follow whenever they appear instead of on a guess about ordering.
    if def.bindingPrefix then
        p._bindConns = p._bindConns or {}
        p._bindConns[def.id] = SuuUI.UISignals:Connect(
            grid, SuuUI.UISignals.SIGNALS.CHILDREN_CHANGED,
            function() applyOwnBindings(p, def) end)
    end
    applyOwnBindings(p, def)
end

local function destroyBar(p, def)
    local grid = p._bars[def.id]
    if not grid then return end
    p._bars[def.id] = nil

    -- Revoked before anything is torn down: consumers detach on the nil notification, so nothing
    -- foreign is still anchored to a frame that is about to go.
    SuuUI.AttachPoints:Revoke(dockPoint(def.id))
    -- The keys go with the bar. Left in place they would point at a button that no longer exists, and
    -- an override binding outlives the frame it was set on. EVERY bar now, not only the self-declared
    -- ones -- a stale override on bar 1 would swallow the player's key and route it nowhere, which is
    -- worse than the old behaviour where Blizzard's family would still have answered.
    if def.bindingPrefix and type(ClearOverrideBindings) == "function" then
        ClearOverrideBindings(grid:GetFrame())
    end
    if p._bindConns and p._bindConns[def.id] then
        SuuUI.UISignals:Disconnect(grid, SuuUI.UISignals.SIGNALS.CHILDREN_CHANGED,
            p._bindConns[def.id])
        p._bindConns[def.id] = nil
    end
    if p._pendingBindings then p._pendingBindings[def.id] = nil end
    -- Release drops OUR request; Release(dock) drops the bars attached to us. Both, because a bar can
    -- be a dock and be docked at the same time.
    SuuUI.AttachPoints:Release(OWNER .. ".dock." .. def.id)
    SuuUI.Dock.Release(grid)

    -- Released before the frame goes, or the client keeps evaluating a conditional against a frame
    -- that no longer exists.
    if isPet(def) and type(UnregisterStateDriver) == "function" then
        UnregisterStateDriver(grid:GetFrame(), "visibility")
    end

    if def.paged then
        SuuUI._ActionBars.Paging.Detach(grid)
    end

    if grid:GetFrame()._suuui_moveable then
        SuuUI.MoveableFrame:Remove(grid:GetFrame())
    end
    grid:Destroy()
end

-- Settings that change a bar's SHAPE, and therefore its geometry. Each lands in ActionBarGrid,
-- which defers the whole change when InCombatLockdown() is true and catches up on
-- PLAYER_REGEN_ENABLED -- so a player dragging a slider mid-fight sees it apply when the fight
-- ends rather than getting "Interface action failed because of an AddOn".
--
-- Paging needs no hook here: the grid emits CHILDREN_CHANGED when it rebuilds and the paging
-- module re-states its frame references off that, which is what makes a DEFERRED rebuild safe.
local SHAPE = {
    { name = "buttons", apply = function(grid, v, def)
        local n = v or MAX_BUTTONS
        grid:SetSlots(slotsFor(def, n), bindingsFor(def, n))
    end },
    { name = "rows",        apply = function(grid, v, def) grid:SetRows(v or def.rows or 1) end },
    { name = "button_size", apply = function(grid, v) grid:SetButtonSize(v or 32) end },
    { name = "spacing",     apply = function(grid, v) grid:SetSpacing(v or 0) end },
}

-- Readout toggles. These touch no geometry -- a font string showing or hiding is not protected --
-- so they apply immediately, in combat included.
local READOUTS = {
    { name = "show_hotkeys",    apply = function(grid, v) grid:SetShowHotkeys(v ~= false) end },
    { name = "show_macro_text", apply = function(grid, v) grid:SetShowMacroText(v ~= false) end },
    { name = "show_count",      apply = function(grid, v) grid:SetShowCount(v ~= false) end },
}

-- Applies a bar's dock/free choice: who owns its position, and whether it is in the stack.
--
-- DEFERRED IN COMBAT AS A WHOLE, not just the reflow. Handing a position over means calling
-- MoveableFrame:Remove, which clears the frame's points and hides its drag overlay -- geometry on a
-- frame that holds protected buttons, so the client refuses it. Deferring only the reflow left the
-- transition half-applied: the moveable gone, the dock not yet anchoring, and the bar stranded.
local function applyAttach(p, def)
    local grid = p._bars[def.id]
    if not grid then return end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        p._pendingAttach = p._pendingAttach or {}
        p._pendingAttach[def.id] = def
        return
    end
    if p._pendingAttach then p._pendingAttach[def.id] = nil end

    if isDocked(def) then
        syncMoveable(p, def)
        requestDock(p, def)
    else
        -- Released BEFORE the moveable goes back on, so the dock has stopped anchoring the frame by
        -- the time the stored position starts driving it. The other order leaves both writing the
        -- same anchor and the result depends on which fired last.
        SuuUI.AttachPoints:Release(OWNER .. ".dock." .. def.id)
        -- Asked of the dock module rather than assumed to be bar 1: any bar can be the parent now.
        local parent = SuuUI.Dock.ParentOf(grid)
        if parent then SuuUI.Dock.Detach(parent, grid) end
        syncMoveable(p, def)
    end
end

local function watchBar(p, def)
    for _, group in ipairs({ SHAPE, READOUTS }) do
        for _, entry in ipairs(group) do
            local k = key(def, entry.name)
            SuuUI.Settings:Watch(PLUGIN_ID, k, function(v)
                local grid = p._bars[def.id]
                if grid then entry.apply(grid, v, def) end
            end, OWNER .. "." .. k)
        end
    end
    -- Every bar can attach now, bar 1 included, so there is no exception here any more.
    for _, name in ipairs({ "attach", "attach_edge" }) do
        SuuUI.Settings:Watch(PLUGIN_ID, key(def, name), function()
            applyAttach(p, def)
        end, OWNER .. "." .. key(def, name))
    end
    SuuUI.Settings:Watch(PLUGIN_ID, key(def, "enabled"), function(on)
        if on then buildBar(p, def) else destroyBar(p, def) end
    end, OWNER .. "." .. key(def, "enabled"), { immediate = true })
end

local function unwatchBar(def)
    for _, group in ipairs({ SHAPE, READOUTS }) do
        for _, entry in ipairs(group) do
            SuuUI.Settings:Unwatch(OWNER .. "." .. key(def, entry.name))
        end
    end
    for _, name in ipairs({ "attach", "attach_edge" }) do
        SuuUI.Settings:Unwatch(OWNER .. "." .. key(def, name))
    end
    SuuUI.AttachPoints:Release(OWNER .. ".dock." .. def.id)
    SuuUI.Settings:Unwatch(OWNER .. "." .. key(def, "enabled"))
end

local function watchSettings(p)
    for _, def in ipairs(BARS) do
        watchBar(p, def)
    end
    -- Still immediate, but NOT for the reason this comment used to give. It said switching the
    -- toggle off "hands Blizzard's cluster back straight away rather than at the next login. That
    -- is the whole point of it being separate from the plugin toggle." That is no longer true and
    -- has not been since suppression started unregistering Blizzard's events: those cannot be
    -- re-registered, so the cluster comes back visible but inert and the key carries a ReloadGuard.
    --
    -- The toggle stays separate for the OTHER reason the schema gives -- it is the escape hatch, and
    -- a player whose bars are misbehaving must be able to reach it without disabling the plugin
    -- whose settings page they are standing on. `immediate` is what builds the initial state on the
    -- way in, which is reason enough on its own.
    SuuUI.Settings:Watch(PLUGIN_ID, "hide_blizzard", function(on)
        local Suppress = SuuUI._ActionBars.Suppress
        if on then Suppress.Apply() else Suppress.Restore() end
    end, OWNER .. ".hide_blizzard", { immediate = true })
end

local function unwatchSettings()
    for _, def in ipairs(BARS) do
        unwatchBar(def)
    end
    SuuUI.Settings:Unwatch(OWNER .. ".hide_blizzard")
end

---------------------------------------------------------------------------
-- Settings schema
---------------------------------------------------------------------------

-- One tab per bar. Every key is declared exactly ONCE, inside its own tab -- Settings:Register
-- indexes them and a key appearing twice would have one control writing another's value.
local function barTab(def)
    local schema = {
        { key = "", label = "General", type = "section" },
    }

    -- WARNS THAT THIS BAR'S SLOTS ARE A STANCE BAR. Purely a warning -- nothing about how the bar
    -- behaves changes, and the bar stays fully configurable.
    --
    -- A form or stance pages bar 1 onto one of these blocks, so anything the player puts here also
    -- appears on bar 1 the moment they shift -- and whatever bar 1 already had in that form is what they
    -- will find here. That is not a fault; it is how a stance bar is built. But discovering it by
    -- accident, after arranging a bar that then seems to rearrange itself, is a bad afternoon.
    --
    -- MARKED FOR EVERY CLASS, not only the one logged in. A per-class warning would appear and vanish as
    -- the player switched character on a shared profile, and a page that is a bonus bar for somebody is a
    -- page to arrange deliberately for everybody. The classes are NAMED in the note rather than resolved,
    -- so the text stays true whoever reads it.
    if def.page then
        local bonus = SuuUI._ActionBars.Paging.BonusPages()
        if bonus[def.page] then
            schema[#schema + 1] = {
                key = "", type = "note", tone = "warning",
                label = "STANCE BAR. On a druid, warrior, rogue or priest, bar 1 switches to these "
                    .. "slots when you change form or stance -- so this bar and bar 1 share them. "
                    .. "Arrange it deliberately or leave it off.",
            }
        end
    end

    -- Toggles as one block, sliders after: mixing them reads as a broken list.
    schema[#schema + 1] = { key = key(def, "enabled"), label = "Enable Bar", type = "toggle",
        default = def.enabled ~= false }
    schema[#schema + 1] = { key = key(def, "show_hotkeys"), label = "Show Hotkeys", type = "toggle",
        default = true, enabledIf = key(def, "enabled") }

    -- Macro names and charge counts exist only for action slots. A form has neither, so the stance
    -- tab does not offer the toggles rather than showing two switches that do nothing.
    if not usesIndexSlots(def) then
        schema[#schema + 1] = { key = key(def, "show_macro_text"), label = "Show Macro Names",
            type = "toggle", default = true, enabledIf = key(def, "enabled") }
        schema[#schema + 1] = { key = key(def, "show_count"), label = "Show Counts",
            type = "toggle", default = true, enabledIf = key(def, "enabled") }
    end

    -- Any bar can attach to any OTHER dockable thing, on any edge. Placed before the sliders, with the
    -- other placement decision, rather than mixed in among the dimensions.
    --
    -- A FUNCTION, not a fixed list, because the option set now spans plugins: the watch bars register
    -- as participants too, and whether they have done so yet depends on load order. Resolved when the
    -- panel is built, by which point every plugin has registered.
    --
    -- The `validate` is the cycle guard, and it lives HERE rather than in the dock because a
    -- validator runs before the value is stored: a rejected choice never reaches the profile, so the
    -- dropdown cannot end up showing a state that is not in effect. The dock refuses a cycle too,
    -- but that is a backstop for a profile written before this existed.
    schema[#schema + 1] = {
        key = key(def, "attach"), label = "Attach To", type = "dropdown",
        default = "detached", enabledIf = key(def, "enabled"),
        options = function() return SuuUI.Dock.OptionsFor(def.id) end,
        validate = function(value)
            if value == nil or value == "detached" then return true end
            local target = tostring(value)
            -- A circular anchor is not a cosmetic fault: the client raises a hard error and leaves
            -- the frame unplaced. So bar 4 on bar 5 on bar 4 is refused rather than attempted.
            --
            -- Attaching to ITSELF needs no separate check: it is a cycle of length zero, and the walk
            -- matches on its first step. An earlier draft tested for it explicitly and mutation
            -- testing showed the clause could not be made to matter.
            return not wouldCycleInSettings(def.id, target)
        end,
    }
    schema[#schema + 1] = {
        key = key(def, "attach_edge"), label = "Attached Edge", type = "dropdown",
        default = "above",
        -- Dead while the bar owns its own position, rather than silently ignored.
        enabledIf = { key = key(def, "attach"), notEquals = "detached" },
        options = {
            { value = "above", label = "Above" },
            { value = "below", label = "Below" },
            { value = "left",  label = "Left"  },
            { value = "right", label = "Right" },
        },
    }

    local rest = {}
    -- NO Buttons slider on the stance bar: its cell count is the player's form count, which the
    -- client owns. A slider would let a player set 12 and get 8, or set 3 and lose an aura.
    --
    -- The PET bar does get one, because its width genuinely is a preference: Blizzard's pet bar is
    -- always ten slots wide with the unused ones empty, so a player with a four-ability imp can trim
    -- it without losing anything.
    if not isStance(def) then
        local maxN = isPet(def) and PET_SLOTS or MAX_BUTTONS
        rest[#rest + 1] = { key = key(def, "buttons"), label = "Buttons", type = "slider",
            min = 1, max = maxN, step = 1, default = maxN,
            enabledIf = key(def, "enabled") }
    end
    local more = {
        { key = key(def, "rows"), label = "Rows", type = "slider",
          min = 1, max = MAX_BUTTONS, step = 1, default = def.rows or 1,
          enabledIf = key(def, "enabled") },
        -- Button size and spacing are one shape decision, so they sit together.
        { key = key(def, "button_size"), label = "Button Size", type = "slider",
          min = 20, max = 64, step = 1, default = 32, enabledIf = key(def, "enabled") },
        -- 0 is the seamless look, and the only spacing that draws dividers between cells.
        { key = key(def, "spacing"), label = "Spacing", type = "slider",
          min = 0, max = 12, step = 1, default = 0, enabledIf = key(def, "enabled") },
    }
    for _, entry in ipairs(more) do rest[#rest + 1] = entry end
    for _, entry in ipairs(rest) do
        schema[#schema + 1] = entry
    end
    -- Deliberately no "this bar pages" note here. `internal` is a data-only type -- the page
    -- builder skips it by design -- so a label with that type renders nothing at all and would
    -- only mislead the next reader into thinking a player can see it. Paging belongs in the docs.
    return schema
end

local function schema()
    local s = {
        -- Before the first section, so it stays on the page itself: a player must not have to
        -- open a group to find the switch that turns the plugin off.
        { key = "enabled", label = "Enable Action Bars", type = "toggle", default = true },
        -- Its OWN toggle, deliberately alongside the plugin's rather than inside a group: it is
        -- the escape hatch. A player whose bars are misbehaving needs Blizzard's cluster back
        -- without having to disable the plugin whose settings page they are standing on, and a
        -- switch you have to open a group to find is not an escape hatch.
        { key = "hide_blizzard", label = "Hide Blizzard's Action Bars", type = "toggle",
          default = true },
    }

    -- Positions carry no control; the drag and the properties panel write them. They live at the
    -- top level rather than in a tab because the page builder skips them either way, and keeping
    -- them together makes the set visible at a glance.
    for _, def in ipairs(BARS) do
        s[#s + 1] = { key = key(def, "position"), type = "position", default = def.position }
    end

    local tabs = {}
    for _, def in ipairs(BARS) do
        -- `id` is NOT optional: SubTabs builds a lookup with `byId[tab.id] = tab`, so a nil id
        -- raises "table index is nil" and the ENTIRE page build throws -- taking the top-level
        -- toggles down with it, including the suppression escape hatch. Shipped that way in 5a
        -- and only caught by looking at the settings window in game; the schema-shape specs all
        -- passed, because asserting a schema is not asserting that it renders.
        tabs[#tabs + 1] = { id = "bar" .. def.id, label = def.label, schema = barTab(def) }
    end
    s[#s + 1] = { key = "bar", type = "subtabs", tabs = tabs }

    return s
end

---------------------------------------------------------------------------
-- Plugin
---------------------------------------------------------------------------

SuuUI:CreatePlugin({
    id      = PLUGIN_ID,
    name    = "Action Bars",
    version = "0.2",

    onInit = function(p)
        p._bars = {}
        -- BEFORE Settings:Register, so this plugin's own participants exist by the time anything reads
        -- the registry. Cross-plugin visibility does not depend on this ordering -- the Attach To
        -- options are resolved when the panel is built, not now -- but registering first keeps the
        -- invariant simple: a plugin that has initialised has published its participants.
        registerParticipants()
        SuuUI.Settings:Register(PLUGIN_ID, schema())

        -- BOTH keys that reach Suppress.Restore are reload-guarded, and it is the same one reason:
        -- suppression unregisters Blizzard's own bar events, nothing in the API can put them back,
        -- so Restore hands the cluster back VISIBLE BUT INERT. A player who switches either of these
        -- off wants working default bars, and only a reload can produce them.
        --
        -- `enabled` needs it as much as `hide_blizzard` does, because onDisable calls Restore too --
        -- guarding only the suppression toggle would leave the plugin switch as a silent way into
        -- the same half-dead state. UnitFrames and CastBars already guard their own `enabled` for
        -- unrelated reasons, so this also stops ActionBars being the odd one out.
        SuuUI.ReloadGuard:Register(PLUGIN_ID, "enabled", {
            title   = "Reload Required",
            message = "Disabling the action bars hands Blizzard's bars back, which needs a UI " ..
                      "reload to make them work again. Reload now?",
        })
        SuuUI.ReloadGuard:Register(PLUGIN_ID, "hide_blizzard", {
            title   = "Reload Required",
            message = "Showing Blizzard's action bars again needs a UI reload before they will " ..
                      "update. Reload now?",
        })

        -- No `immediate` here on purpose. Plugins:autoEnable already applies the stored value
        -- during the login pass, and an immediate callback would run onEnable from inside the
        -- init pass -- before other plugins' onInit had run, which is the ordering the two phases
        -- exist to guarantee.
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, OWNER .. ".enabled")
    end,

    onEnable = function(p)
        p._bars = p._bars or {}
        -- Catches up any dock transition the client refused mid-fight. One frame for the plugin
        -- rather than one per bar, and registered only while the plugin is up.
        p._evt = p._evt or CreateFrame("Frame")
        p._evt:SetScript("OnEvent", function(_, event)
            if event == "UPDATE_SHAPESHIFT_FORMS" or event == "PLAYER_ENTERING_WORLD" then
                syncStanceForms(p)
                -- Entering the world is also the first moment the player's saved keys are readable,
                -- so it is when the self-declared bars claim theirs.
                if event == "PLAYER_ENTERING_WORLD" then
                    for _, def in ipairs(BARS) do applyOwnBindings(p, def) end
                end
                return
            end

            -- The player rebound a key. Only the self-declared bars care: a Blizzard family acts on
            -- the slot, so its keys need no routing from us.
            if event == "UPDATE_BINDINGS" then
                for _, def in ipairs(BARS) do applyOwnBindings(p, def) end
                return
            end

            -- PLAYER_REGEN_ENABLED: drain everything combat refused, bindings as well as docks.
            local pendingBinds = p._pendingBindings
            if pendingBinds then
                p._pendingBindings = nil
                for _, def in pairs(pendingBinds) do applyOwnBindings(p, def) end
            end
            local pending = p._pendingAttach
            if not pending then return end
            p._pendingAttach = nil
            for _, def in pairs(pending) do
                applyAttach(p, def)
            end
        end)
        p._evt:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- Rebinding is the only thing that can invalidate an override binding, and the client
        -- announces it. Without this a player who moves a key sees the old one keep working until
        -- the next reload.
        p._evt:RegisterEvent("UPDATE_BINDINGS")
        -- The PLURAL event: the SET of forms changed, so the bar needs a different number of cells.
        -- The singular UPDATE_SHAPESHIFT_FORM is NOT registered here -- that is which form is
        -- active, which the buttons repaint themselves and which must not touch geometry.
        p._evt:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
        -- AND entering the world, which is the one that actually makes the bar appear at login.
        --
        -- At the moment a bar is built, GetNumShapeshiftForms can still answer 0 -- the client has
        -- not populated them yet -- so the bar is created with no cells and hides itself. For a
        -- WARRIOR nothing then rescues it: three stances are known from the start, so the client
        -- never fires "the set of forms changed", and the bar stays hidden forever. A druid or a
        -- paladin might get lucky on a later event; a warrior does not.
        --
        -- ElvUI registers this for the same reason. Found in game on a warrior, not by a spec: every
        -- spec here staged its forms BEFORE building the bar, which is the one ordering login never
        -- uses.
        p._evt:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Each bar's enabled watcher is immediate, so it builds on the way in.
        watchSettings(p)
    end,

    onDisable = function(p)
        unwatchSettings()
        if p._evt then
            p._evt:UnregisterAllEvents()
            p._evt:SetScript("OnEvent", nil)
        end
        p._pendingAttach = nil
        -- Blizzard's cluster back BEFORE our own bars go, so there is never a frame where the
        -- player has neither. Restore is a no-op for anything this addon did not hide.
        SuuUI._ActionBars.Suppress.Restore()
        for _, def in ipairs(BARS) do
            destroyBar(p, def)
        end
    end,
})

SuuUI._ActionBars = SuuUI._ActionBars or {}
SuuUI._ActionBars.BARS = BARS
SuuUI._ActionBars.slotsFor = slotsFor
SuuUI._ActionBars.bindingsFor = bindingsFor
