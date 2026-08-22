-- An invisible surface that hands a click over a unit's frame to the CLIENT's own unit
-- actions: left click targets the unit, right click opens its context menu — the real one,
-- carrying every entry the client would offer for that unit.
--
-- Why this is attributes and not an onClick handler. Targeting and the unit popup are
-- PROTECTED: the client refuses both from addon code, so there is no callback we could
-- write that would work. The only route is the secure template — a Button inheriting
-- SecureUnitButtonTemplate carries a `unit` attribute and a per-button `type` attribute,
-- and the template's OWN click handler reads them and performs the action inside the
-- client. So this component states attributes and gets out of the way; it never sees the
-- click that matters. That is also why the menu needs no code here: which entries a player,
-- an NPC or a corpse offers is the client's decision, and asking it is the whole point.
--
-- Three things about it are load-bearing:
--
--   * NEVER SetScript("OnClick") on this frame. The template installs the handler that
--     performs the action, and replacing it breaks every action silently — the frame still
--     sizes, still takes the mouse, still reports as shown. Observe a click through
--     PostClick, which is the hook the template offers for exactly this.
--   * RegisterForClicks is not optional. A Button fires its handler for left-up alone
--     until told otherwise, so without it the right click never reaches the client at all.
--   * Attributes are stated once, at construction. A frame built from a secure template is
--     protected, and the client refuses to let an addon reshape a protected frame in
--     combat — so nothing here is re-stated later, and this component exposes no setter
--     that would want to be.
--
-- The same protection has one consequence that decides where this surface may live, and it
-- is not a small one: protection propagates DOWN to descendants while the client's refusal
-- propagates UP, so a plain frame is refused addon-driven geometry in combat merely for
-- holding this one somewhere in its subtree. Parent it inside a frame that resizes at
-- runtime and every one of that frame's mid-combat resizes is silently discarded, with
-- "Interface action failed because of an AddOn" in the player's chat.
--
-- That shipped: this surface sat inside the unit frame's wrapper, which grows when an aura
-- band gains a row or a cast bar attaches — both in combat by definition — and the growth
-- was refused for ten days. Measured in game as GetPreferredSize 227 against a GetHeight of
-- 188, with InCombatLockdown() true on every mismatch and false on every match.
--
-- So the owner parents this BESIDE the frame it covers and anchors it to that frame, and
-- guards its own geometry with InCombatLockdown(), deferring to PLAYER_REGEN_ENABLED.
-- Plugins/UnitFrames/UnitFrame.lua (_syncClickArea) is the reference implementation.
local assert, type = assert, type
local S = SuuUI.UISignals

-- Which clicks reach the client. "AnyUp" rather than the default left-up, because the right
-- button is the one this component exists for; on the release rather than the press, so a
-- click that started here and ended elsewhere is not an action.
local CLICK_REGISTRATION = "AnyUp"

local AreaMeta = {}
AreaMeta.__index = AreaMeta

--- The unit token this surface acts on.
-- @return string
function AreaMeta:GetUnit()
    return self._unit
end

--- Releases the surface.
--
-- The attributes are left where they are: the frame is about to be hidden and dropped, and
-- clearing an attribute on a protected frame is one more call the client can refuse.
function AreaMeta:Destroy()
    S:DisconnectAll(self)
    self._f:Hide()
end

-- Deliberately no SetEnabled, and no InstallEnable. This component paints nothing, so the
-- disabled fade would be invisible — and the only real disabling left, dropping mouse
-- input, is a call the client refuses on a protected frame in combat. A SetEnabled that
-- cannot be honoured when it matters is worse than none: Dependency.Bind's
-- `if target.SetEnabled` guard would pass while nothing was actually inert.
SuuUI.Components.InstallBase(AreaMeta, "_f")

--- Creates an invisible secure click surface for one unit.
--
-- Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, SIZE_CHANGED. Position it by adding it
-- to a container, as with any component — but NOT a container hosted on the frame it covers
-- if that frame resizes at runtime: hosting chains onto that frame's OnSizeChanged, so every
-- mid-combat resize re-lays out a protected child. Host the container on something that only
-- resizes with the screen and anchor this surface to the covered frame instead. See the
-- parentage note at the top of this file.
-- @param props table  { unit, name }
--   unit: the unit token clicks act on, e.g. "player", "target"
--   name: optional global frame name, so /framestack and a click-casting addon can name it
-- @param parent frame
-- @return table  handle
function SuuUI.Components.UnitClickArea(props, parent)
    assert(type(props) == "table" and type(props.unit) == "string",
           "SuuUI: UnitClickArea needs a unit token")

    -- A Button, because only a button carries the secure template's click handler.
    local f = CreateFrame("Button", props.name, parent, "SecureUnitButtonTemplate")

    -- The client enables the mouse for a button already; stated anyway, because the whole
    -- component is worthless if it ever is not, and this is not a call that can be refused
    -- at construction.
    f:EnableMouse(true)
    f:RegisterForClicks(CLICK_REGISTRATION)

    -- The unit every action below acts on, and then one action per button. `togglemenu` is
    -- the client's unit context menu — the whole feature, and the reason there is no menu
    -- code here: the client decides which entries a player, an NPC or a corpse offers.
    --
    -- The wildcard spelling ("*type1") is the form that survives the frame being handed to
    -- a click-casting addon, which stamps the unprefixed names for its own bindings.
    f:SetAttribute("unit", props.unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")

    -- Registered before the host container adopts the frame, so the container chains onto
    -- this rather than replacing it.
    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    handle = setmetatable({
        _f    = f,
        _unit = props.unit,
    }, AreaMeta)

    -- PostClick, not OnClick: the template owns OnClick and it is what performs the action.
    -- Hooked rather than set, for the same reason — a template that grows a PostClick of
    -- its own must keep it.
    f:HookScript("PostClick", function(_, btn)
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)
    f:HookScript("OnEnter", function()
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    f:HookScript("OnLeave", function()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)

    -- No ApplyTheme and no SUUUI_THEME_CHANGED subscription: the surface has no colour, no
    -- border and no text, so there is nothing a token could change. Its size comes from the
    -- container that stretches it over the frame it covers.
    return handle
end
