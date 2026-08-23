-- Installs the simulated WoW global API into a sandbox environment.
local geometry = require("harness.wow.geometry")
local state    = require("harness.wow.state")
local widget   = require("harness.wow.widget")
local frame    = require("harness.wow.frame")
local regions  = require("harness.wow.regions")
local font     = require("harness.wow.font")

local M = {}

--- Builds a fresh set of WoW globals and installs them into env.
-- @param env table  Sandbox table the addon files run in
-- @return table  Handles the harness needs: { UIParent, Minimap, fireEvent, ... }
function M.install(env)
    widget.resetSerial()
    state.reset()
    font.resetFaces()

    ------------------------------------------------------------------------------
    -- Screen root
    ------------------------------------------------------------------------------
    local UIParent = widget.new("Frame", "UIParent", nil, frame.FrameMeta)
    UIParent._isScreenRoot = true
    UIParent._w = state.screenWidth
    UIParent._h = state.screenHeight
    UIParent._strata = "MEDIUM"
    UIParent._level = 1

    local WorldFrame = widget.new("Frame", "WorldFrame", nil, frame.FrameMeta)
    WorldFrame._isScreenRoot = true
    WorldFrame._w = state.screenWidth
    WorldFrame._h = state.screenHeight

    ------------------------------------------------------------------------------
    -- CreateFrame
    ------------------------------------------------------------------------------
    local function CreateFrame(kind, name, parent, template)
        local meta = frame.metaFor[kind]
        assert(meta, "harness: CreateFrame does not simulate type " .. tostring(kind))
        local f = widget.new(kind, name, parent, meta)
        f._template = template
        if template and template:find("Backdrop") then f._hasBackdropTemplate = true end
        -- A secure action template brings its own OnClick handler, and that handler is the
        -- whole mechanism: it reads the frame's attributes and performs the protected
        -- action. Installed here rather than inside the click path so it behaves like the
        -- real template in both directions — it runs on a click, and it is lost if
        -- something overwrites OnClick.
        if template and template:find("Secure") and f._canScript then
            f._secure = true
            f:SetScript("OnClick", function(self, button) frame.secureAction(self, button) end)
        end
        if name then env[name] = f end
        return f
    end

    ------------------------------------------------------------------------------
    -- Blizzard frames the addon touches
    ------------------------------------------------------------------------------
    local Minimap = CreateFrame("Frame", "Minimap", UIParent)
    Minimap:SetSize(140, 140)
    Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)

    -- A Blizzard system frame arrives with its own events already registered and re-shows
    -- itself from them: entering the world, changing power type, or an Edit Mode layout
    -- being applied. Both halves matter to an addon that suppresses one.
    --
    -- The registration is state the addon must not destroy, because nothing in the API
    -- enumerates a frame's registered events -- so UnregisterAllEvents is a one-way door
    -- and the frame can never be handed back alive. The re-show is what a bare Hide()
    -- cannot survive, and is the whole reason suppression needs an OnShow hook.
    --
    -- A stub with neither let a suppression spec assert "no registered events" against a
    -- frame that never had any: it passed for the wrong reason, in both directions.
    --
    -- None of these events are fired by the boot sequence, so a spec exercises the
    -- re-show path deliberately rather than tripping over it.
    local BLIZZARD_SYSTEM_EVENTS = { "PLAYER_ENTERING_WORLD", "UNIT_HEALTH", "UNIT_DISPLAYPOWER" }
    local function blizzardSystemFrame(frame)
        for _, event in ipairs(BLIZZARD_SYSTEM_EVENTS) do frame:RegisterEvent(event) end
        frame:SetScript("OnEvent", function(self) self:Show() end)
        return frame
    end

    -- Blizzard PlayerFrame stub (UnitFrames plugin hides it)
    local PlayerFrame = blizzardSystemFrame(CreateFrame("Frame", "PlayerFrame", UIParent))
    PlayerFrame:SetSize(180, 70)
    PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)

    -- Blizzard TargetFrame stub (UnitFrames plugin hides it), and its cast bar, which the
    -- CastBars plugin hides separately.
    --
    -- The spell bar is a CHILD of TargetFrame in the live client, and modelled as one here:
    -- that is what makes "the unit frames plugin already takes it down" true, and it is why
    -- the cast bars plugin suppressing it as well has to be tested rather than assumed —
    -- with unit frames disabled, nothing else hides it.
    local TargetFrame = blizzardSystemFrame(CreateFrame("Frame", "TargetFrame", UIParent))
    TargetFrame:SetSize(180, 70)
    TargetFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 250, -10)
    local TargetSpellBar = blizzardSystemFrame(
        CreateFrame("Frame", "TargetFrameSpellBar", TargetFrame))
    TargetSpellBar:SetSize(150, 10)
    TargetSpellBar:SetPoint("TOP", TargetFrame, "BOTTOM", 0, -2)

    -- Blizzard cast bar stub (CastBars plugin hides it). A StatusBar in the live client;
    -- a plain frame is enough here because the addon only hides it and watches it.
    --
    -- The name is a property of the client generation, not a constant: an Edit Mode
    -- client calls it PlayerCastingBarFrame, an older one CastingBarFrame. Both exist by
    -- default so a spec sees whichever the addon reaches for, and a spec that is about
    -- one generation narrows it through state.castBarGlobals.
    for _, name in ipairs(state.castBarGlobals or { "PlayerCastingBarFrame", "CastingBarFrame" }) do
        local bar = blizzardSystemFrame(CreateFrame("Frame", name, UIParent))
        bar:SetSize(195, 13)
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
    end

    ------------------------------------------------------------------------------
    -- Font objects
    ------------------------------------------------------------------------------
    -- Font objects report their own face, as the client's do. That is what makes the
    -- GetFonts harvest meaningful: the addon reads a path off each object, so objects
    -- that all claimed the same face would hide a broken harvest.
    local fontObjects = {}
    local function fontObject(name, size, path)
        local o = { _name = name, _size = size, _path = path or "Fonts/FRIZQT__.TTF" }
        function o:GetFont() return self._path, self._size, "" end
        function o:GetName() return self._name end
        fontObjects[#fontObjects + 1] = name
        return o
    end

    ------------------------------------------------------------------------------
    -- Event dispatch
    ------------------------------------------------------------------------------
    local function fireEvent(event, ...)
        local list, n = {}, #state.frames
        for i = 1, n do list[i] = state.frames[i] end
        for i = 1, n do
            local f = list[i]
            if f._events and f._events[event] and f._scripts and f._scripts.OnEvent then
                f._scripts.OnEvent(f, event, ...)
            end
        end
    end

    ------------------------------------------------------------------------------
    -- Globals
    ------------------------------------------------------------------------------
    env.UIParent   = UIParent
    env.WorldFrame = WorldFrame
    env.Minimap    = Minimap
    env.CreateFrame = CreateFrame

    env.GameFontNormal      = fontObject("GameFontNormal", 12)
    env.GameFontNormalSmall = fontObject("GameFontNormalSmall", 10)
    env.GameFontNormalLarge = fontObject("GameFontNormalLarge", 16)
    env.GameFontHighlight   = fontObject("GameFontHighlight", 12)
    env.ChatFontNormal      = fontObject("ChatFontNormal", 14)
    env.NumberFontNormal    = fontObject("NumberFontNormal", 12, "Fonts/ARIALN.TTF")
    env.QuestTitleFont      = fontObject("QuestTitleFont", 15, "Fonts/MORPHEUS.TTF")

    -- Returns font OBJECT names, not paths. The path comes off each object.
    env.GetFonts = function()
        local out = {}
        for i, name in ipairs(fontObjects) do out[i] = name end
        return out
    end

    env.GameFontWhite = fontObject("GameFontWhite", 12)

    -- The client's locale font globals. enUS values here; other locales ship other files.
    env.STANDARD_TEXT_FONT = "Fonts/FRIZQT__.TTF"
    env.UNIT_NAME_FONT     = "Fonts/FRIZQT__.TTF"
    env.DAMAGE_TEXT_FONT   = "Fonts/skurri.TTF"
    -- Not a path. The live client really does define this one as a font OBJECT name, and
    -- handing it to SetFont raises "Invalid font asset" — the shape that broke login.
    env.NAMEPLATE_FONT     = "GameFontWhite"

    -- UIParent's size in UIParent's own region units, which is what the client returns.
    -- Deliberately not the same as a scaled frame's view of the screen: that difference
    -- is a real bug class and the harness has to be able to show it.
    env.GetScreenWidth  = function() return UIParent:GetWidth() end
    env.GetScreenHeight = function() return UIParent:GetHeight() end

    -- Physical pixels, not units. This is the only way to learn the real resolution,
    -- and the pixel grid is derived from it: one unit spans physicalHeight/768 pixels.
    env.GetPhysicalScreenSize = function()
        return state.physicalWidth, state.physicalHeight
    end

    env.GetCursorPosition = function() return state.cursorX, state.cursorY end
    env.IsMouseButtonDown = function(button)
        if button == nil then
            for _, down in pairs(state.mouseDown) do if down then return true end end
            return false
        end
        return state.mouseDown[button] == true
    end

    env.IsControlKeyDown = function() return state.ctrlDown == true end
    env.IsAltKeyDown     = function() return state.altDown == true end
    env.IsShiftKeyDown   = function() return state.shiftDown == true end
    env.IsModifierKeyDown = function()
        return state.ctrlDown == true or state.altDown == true or state.shiftDown == true
    end

    env.CreateColor = function(r, g, b, a)
        local col = { r = r, g = g, b = b, a = a == nil and 1 or a }
        function col:GetRGBA() return self.r, self.g, self.b, self.a end
        function col:GetRGB()  return self.r, self.g, self.b end
        return col
    end

    -- Per-unit data. Every Unit* accessor below reads through `unitField`, which prefers a
    -- per-unit override and falls back to the flat state.unitX value.
    --
    -- The flat values came first, when the only unit frame was the player's, and they stay
    -- because most specs are still about one unit and `state.unitHealth = 80` is the clearest
    -- way to say so. A second unit frame is what forces the split: a spec painting a mob in
    -- the target frame has to be able to give the target no class and a hostile reaction
    -- while the player is still a warrior at full health, and one global cannot hold both.
    -- @param unit string|nil
    -- @param field string   Per-unit key, e.g. "health"
    -- @param flat any       The flat state.unitX value to fall back to
    -- @return any
    local function unitField(unit, field, flat)
        local u = unit and state.units and state.units[unit]
        local v = u and u[field]
        if v ~= nil then return v end
        return flat
    end

    -- Whether the client would admit this unit exists at all.
    --
    -- The player always does; anything else exists only once a spec has staged it. That
    -- default is what makes a target frame's "no target" branch the one a spec gets for
    -- free, which is the state it spends most of its life in.
    env.UnitExists = function(unit)
        if unit == "player" then return true end
        local u = unit and state.units and state.units[unit]
        if not u then return false end
        return u.exists ~= false
    end

    -- Whether the client calls this unit a player rather than a creature.
    --
    -- The player always is; anything else is a creature unless a spec says otherwise, the
    -- same default reasoning UnitExists uses — a target frame spends most of its life on
    -- mobs. Modelled because UnitClass alone cannot answer it: the client reports a class
    -- for a creature too (see below), so a class-colour rule that skips this test paints
    -- every mob in warrior tan.
    env.UnitIsPlayer = function(unit)
        if unit == "player" then return true end
        return unitField(unit, "isPlayer", false) == true
    end

    -- The reaction of the FIRST unit towards the second, which is the client's own
    -- ordering. Only the first is keyed, so a caller that swaps the arguments reads the
    -- player's own standing and gets nil — the harness reproduces the mistake rather than
    -- hiding it behind a symmetric answer.
    env.UnitReaction = function(unit, other)
        if not unit or not other then return nil end
        return unitField(unit, "reaction", nil)
    end

    -- The client's reaction colour table, in the {r=,g=,b=} object shape it really uses and
    -- with its real values. Modelled for the same reason RAID_CLASS_COLORS is: SuuUI
    -- prefers the client's values over its copied fallback, so a spec has to be able to
    -- tell which source answered.
    env.FACTION_BAR_COLORS = {
        [1] = { r = 0.80, g = 0.30, b = 0.22 },
        [2] = { r = 0.80, g = 0.30, b = 0.22 },
        [3] = { r = 0.75, g = 0.27, b = 0.00 },
        [4] = { r = 0.90, g = 0.70, b = 0.00 },
        [5] = { r = 0.00, g = 0.60, b = 0.10 },
        [6] = { r = 0.00, g = 0.60, b = 0.10 },
        [7] = { r = 0.00, g = 0.60, b = 0.10 },
        [8] = { r = 0.00, g = 0.60, b = 0.10 },
    }

    env.UnitName      = function(unit)
        return unitField(unit, "name", unit == "player" and "Testchar" or nil)
    end
    env.GetRealmName  = function() return "TestRealm" end
    -- UnitClass returns the localised name first and the stable class token second. Specs
    -- move state.unitClass to paint a different class; state.unitClassless models the
    -- narrower case of a unit the client reports NO class for at all.
    --
    -- The "WARRIOR" default is not a convenience — it is what the live client answers for a
    -- creature, which is why a mob must be told apart by UnitIsPlayer and not by asking for
    -- its class. A spec staging a mob therefore leaves `class` unset and gets the same
    -- misleading answer the real client gives.
    env.UnitClass     = function(unit)
        if unitField(unit, "classless", state.unitClassless) then return nil end
        local classFile = unitField(unit, "class", state.unitClass) or "WARRIOR"
        return classFile:sub(1, 1) .. classFile:sub(2):lower(), classFile, 1
    end

    -- The client's own class colour table, in the {r=,g=,b=} object shape it really uses.
    -- Modelled because SuuUI prefers the client's values over its copied fallback, so a
    -- spec has to be able to tell which source answered.
    env.RAID_CLASS_COLORS = {
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
        PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
        HUNTER  = { r = 0.67, g = 0.83, b = 0.45 },
        ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
        PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
        SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 },
        MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
        WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
        DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
    }
    env.UnitLevel     = function(unit) return unitField(unit, "level", state.unitLevel) or 60 end
    -- The level cap, as the anniversary client reports it. Specs move state.maxPlayerLevel
    -- to exercise the at-cap and below-cap branches of a unit frame.
    env.GetMaxLevelForPlayerExpansion = function() return state.maxPlayerLevel or 60 end
    env.MAX_PLAYER_LEVEL = 60
    env.GetTime       = function() return state.clock or 0 end

    -- Wall clock, distinct from GetTime(): GetTime reports seconds since the UI loaded and
    -- starts at 0, while time() reports the epoch and is what a clock widget reads.
    --
    -- date() is MODELLED rather than delegated, and it forces UTC. Handing the format string
    -- straight to os.date would make "what does the clock say" depend on the timezone of the
    -- machine running the suite, so the same spec would pass in Berlin and fail in CI.
    -- state.wallClock therefore names an instant in UTC, and the default is 14:32:07 on
    -- 2026-08-22 so an unconfigured clock reads a recognisable "14:32".
    env.time = function() return state.wallClock or 0 end
    env.date = function(fmt, t)
        fmt = fmt or "%c"
        if fmt:sub(1, 1) ~= "!" then fmt = "!" .. fmt end
        return os.date(fmt, t or state.wallClock or 0)
    end

    -- Performance readouts. Both are polled rather than announced, which is why a widget
    -- reading them declares an `update` interval instead of an event.
    env.GetFramerate = function() return state.framerate or 60 end

    -- Modelled with FOUR returns (in, out, latencyHome, latencyWorld), which is the newer
    -- shape. The older API returns three, with a single latency in the third slot — so a
    -- caller reading the third value works on both, and one reading the fourth has to cope
    -- with it being absent. state.netLatencyWorld = false reproduces the three-value client
    -- so a reader can be tested against it.
    env.GetNetStats = function()
        local down = state.netDown or 0
        local up   = state.netUp or 0
        local home = state.netLatencyHome or 0
        if state.netLatencyWorld == false then return down, up, home end
        return down, up, home, state.netLatencyWorld or 0
    end
    -- Realm time, which the client reports separately because a realm need not agree with the
    -- player's own clock — that difference is the whole reason a clock widget shows both.
    -- Defaults to matching the wall clock, so a spec only stages it when the divergence is
    -- what it is testing.
    env.GetGameTime = function()
        if state.realmHour and state.realmMinute then
            return state.realmHour, state.realmMinute
        end
        local t = state.wallClock or 0
        return tonumber(os.date("!%H", t)), tonumber(os.date("!%M", t))
    end
    -- Combat lockdown. False unless a spec says otherwise (H.setCombat), because that is the
    -- state an addon does all its setup in — and because turning it on by default would fail
    -- every geometry spec in the suite for code that is correct.
    --
    -- The flag is not decoration: while it is true the widget layer refuses geometry on any
    -- frame that is protected or holds a protected descendant, exactly as the client does.
    -- See "Protection and combat lockdown" in wow/widget.lua.
    env.InCombatLockdown = function() return state.inCombat == true end

    -- ReloadUI stub for testing (records call rather than actually reloading)
    env.ReloadUI = function()
        state.reloadUICalled = (state.reloadUICalled or 0) + 1
    end

    -- Unit resource APIs for UnitFrames plugin
    env.UnitHealth    = function(unit) return unitField(unit, "health",    state.unitHealth)    or 100 end
    env.UnitHealthMax = function(unit) return unitField(unit, "healthMax", state.unitHealthMax) or 100 end
    env.UnitPower     = function(unit) return unitField(unit, "power",     state.unitPower)     or 80 end
    env.UnitPowerMax  = function(unit) return unitField(unit, "powerMax",  state.unitPowerMax)  or 100 end
    env.UnitPowerType = function(unit) return unitField(unit, "powerType", state.unitPowerType) or 0 end

    -- Spellcast APIs. Both return nothing at all while the unit is idle, which is how the
    -- client says "not casting" — a caller that treats a nil name as an empty cast rather
    -- than as absence shows an empty bar forever, so the shape matters.
    --
    -- Times are MILLISECONDS since the epoch GetTime() reports in seconds. That mismatch
    -- is the client's, not the harness's, and code that forgets to divide reads a cast as
    -- having ended a thousand times over.
    -- Both are answered for a unit that EXISTS. Losing your target does not leave its cast
    -- readable: the unit is gone, so the client has nothing to report about it. Modelled
    -- because a cast bar's "the unit went away" path is otherwise untestable — a spec would
    -- have to clear the staged cast by hand, which is the harness asking to be lied to.
    env.UnitCastingInfo = function(unit)
        local c = state.cast
        if not c or c.unit ~= unit then return nil end
        if not env.UnitExists(unit) then return nil end
        return c.name, c.text or c.name, c.texture, c.startTime, c.endTime,
               c.isTradeSkill or false, c.castID, c.notInterruptible or false, c.spellId
    end

    -- One value shorter than UnitCastingInfo: a channel has no castID. Reading either
    -- positionally is what real addons do, so the difference is modelled.
    env.UnitChannelInfo = function(unit)
        local c = state.channel
        if not c or c.unit ~= unit then return nil end
        if not env.UnitExists(unit) then return nil end
        return c.name, c.text or c.name, c.texture, c.startTime, c.endTime,
               c.isTradeSkill or false, c.notInterruptible or false, c.spellId
    end

    -- Localised strings the client ships for cast outcomes.
    env.INTERRUPTED = "Interrupted"
    env.FAILED      = "Failed"

    -- A stable GUID per unit token. The combat log identifies units by GUID and never by
    -- token, so anything correlating a log line with a unit frame has to go through this.
    env.UnitGUID = function(unit)
        if not unit then return nil end
        return "GUID-" .. tostring(unit)
    end

    -- The combat log's one accessor: it returns the CURRENT event's payload and nothing at
    -- any other time. Modelled faithfully because the interrupter's name exists only here
    -- — UNIT_SPELLCAST_INTERRUPTED does not carry it — so a caller that read it late, or
    -- outside the handler, would silently get no name.
    env.CombatLogGetCurrentEventInfo = function()
        local e = state.combatLogEvent
        if not e then return nil end
        return table.unpack(e, 1, e.n or #e)
    end

    --------------------------------------------------------------------------
    -- Auras (UnitAura / UnitBuff / UnitDebuff)
    --------------------------------------------------------------------------

    -- The 2.5.4 client returns exactly 15 values from UnitAura. Defaults fill every slot
    -- a real aura carries so a test entry need only declare what matters. A non-stacking
    -- aura reports count = 0, and a BUFF can carry a debuffType ("Magic" on Righteous Fury).
    local AURA_DEFAULTS = {
        name = "Buff",
        icon = "Interface\\Icons\\Ability_Warrior_Sunder",
        count = 0,
        debuffType = nil,
        duration = 0,
        expirationTime = 0,
        source = "player",
        isStealable = false,
        nameplateShowPersonal = false,
        spellId = 0,
        canApplyAura = false,
        isBossDebuff = false,
        castByPlayer = true,
        nameplateShowAll = false,
        timeMod = 1,
    }

    local function resolveAura(entry)
        if not entry then return nil end
        return entry.name                  or AURA_DEFAULTS.name,
               entry.icon                  or AURA_DEFAULTS.icon,
               entry.count                 or AURA_DEFAULTS.count,
               entry.debuffType            or AURA_DEFAULTS.debuffType,
               entry.duration              or AURA_DEFAULTS.duration,
               entry.expirationTime        or AURA_DEFAULTS.expirationTime,
               entry.source                or AURA_DEFAULTS.source,
               entry.isStealable == true,
               entry.nameplateShowPersonal == true,
               entry.spellId              or AURA_DEFAULTS.spellId,
               entry.canApplyAura == true,
               entry.isBossDebuff == true,
               entry.castByPlayer ~= false,
               entry.nameplateShowAll == true,
               entry.timeMod              or AURA_DEFAULTS.timeMod
    end

    -- filter nil = "HELPFUL" per the live client
    env.UnitAura = function(unit, index, filter)
        if not env.UnitExists(unit) then return nil end
        filter = filter or "HELPFUL"
        local unitAuras = state.auras[unit]
        if not unitAuras then return nil end
        local list = filter == "HARMFUL" and unitAuras.harmful or unitAuras.helpful
        if not list then return nil end
        local entry = list[index]
        if not entry then return nil end
        return resolveAura(entry)
    end

    env.UnitBuff = function(unit, index)
        return env.UnitAura(unit, index, "HELPFUL")
    end

    env.UnitDebuff = function(unit, index)
        return env.UnitAura(unit, index, "HARMFUL")
    end

    -- Records the call so a spec can assert which buff was cancelled.
    env.CancelUnitBuff = function(unit, index)
        state.cancelBuff = { unit = unit, index = index }
    end

    --------------------------------------------------------------------------
    -- DebuffTypeColor (same {r=,g=,b=} shape as RAID_CLASS_COLORS)
    --------------------------------------------------------------------------
    env.DebuffTypeColor = {
        Magic   = { r = 0.20, g = 0.60, b = 1.00 },
        Curse   = { r = 0.60, g = 0.00, b = 1.00 },
        Disease = { r = 0.60, g = 0.40, b = 0.00 },
        Poison  = { r = 0.00, g = 0.60, b = 0.00 },
        none    = { r = 0.80, g = 0.00, b = 0.00 },
    }

    --------------------------------------------------------------------------
    -- GameTooltip
    --------------------------------------------------------------------------

    -- Built from the GameTooltip frame type in wow/frame.lua rather than assembled here.
    -- It used to be a plain Frame with tooltip verbs bolted on, which meant CreateFrame
    -- refused the type ("does not simulate type GameTooltip") and no second instance was
    -- possible -- so embedded code that creates its own tooltip could not load at all, and
    -- the singleton had no AddLine for a spec to read content back from.
    local GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    GameTooltip._tooltipShown = false

    -- ANCHOR constants the client ships
    env.ANCHOR_NONE        = "ANCHOR_NONE"
    env.ANCHOR_CURSOR      = "ANCHOR_CURSOR"
    env.ANCHOR_LEFT        = "ANCHOR_LEFT"
    env.ANCHOR_RIGHT       = "ANCHOR_RIGHT"
    env.ANCHOR_TOP         = "ANCHOR_TOP"
    env.ANCHOR_BOTTOM      = "ANCHOR_BOTTOM"
    env.ANCHOR_TOPLEFT     = "ANCHOR_TOPLEFT"
    env.ANCHOR_TOPRIGHT    = "ANCHOR_TOPRIGHT"
    env.ANCHOR_BOTTOMLEFT  = "ANCHOR_BOTTOMLEFT"
    env.ANCHOR_BOTTOMRIGHT = "ANCHOR_BOTTOMRIGHT"
    env.ANCHOR_PRESERVE    = "ANCHOR_PRESERVE"

    env.SlashCmdList = {}
    env.hooksecurefunc = function(tbl, name, fn)
        if type(tbl) == "string" then tbl, name, fn = env, tbl, name end
        local orig = tbl[name]
        tbl[name] = function(...)
            local r = orig and orig(...)
            fn(...)
            return r
        end
    end

    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        state.debugLog[#state.debugLog + 1] = table.concat(parts, " ")
    end

    -- Vanilla-era string helpers some addons expect
    env.strsplit = function(sep, str)
        local out = {}
        for piece in (str .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
            out[#out + 1] = piece
        end
        return table.unpack(out)
    end
    env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

    --------------------------------------------------------------------------
    -- Lua stdlib aliases the client predefines as globals
    --------------------------------------------------------------------------

    -- WoW ships these, so their absence was a harness inaccuracy rather than a choice: any
    -- code written for the client may use them, and embedded libraries do (LibStub reaches
    -- for strmatch). Sandbox reads fall through to real _G, where these do NOT exist, so
    -- they have to be stated here.
    env.strmatch = string.match
    env.strfind  = string.find
    env.strsub   = string.sub
    env.strlower = string.lower
    env.strupper = string.upper
    env.strlen   = string.len
    env.strrep   = string.rep
    env.format   = string.format
    env.gsub     = string.gsub
    env.gmatch   = string.gmatch
    env.tinsert  = table.insert
    env.tremove  = table.remove
    env.sort     = table.sort

    -- Lua 5.1's math.atan2 was removed in 5.3. It survives on a build carrying the compat
    -- flag, which is why this looked fine locally -- LibDBIcon's drag handler reads it, so
    -- on a stricter Lua the drag would die for a reason nothing in SuuUI is responsible for.
    if math.atan2 == nil then math.atan2 = math.atan end

    -- Calls a function in a secure context. Nothing here is tainted, so it is a plain call;
    -- modelled because third-party code calls it unconditionally.
    env.securecallfunction = function(fn, ...) return fn(...) end

    --------------------------------------------------------------------------
    -- Which client this is
    --------------------------------------------------------------------------

    -- This matters more than it looks. Libraries branch on
    -- `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` to pick retail behaviour, and with both
    -- undefined that comparison is `nil == nil`, i.e. TRUE -- so the suite would exercise
    -- the retail path while the game takes the Classic one, and a spec asserting the
    -- Classic branch would pass for the wrong reason. SuuUI targets TBC Anniversary
    -- (interface 20504), so the id is the Burning Crusade one.
    env.WOW_PROJECT_MAINLINE                = 1
    env.WOW_PROJECT_CLASSIC                 = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC           = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC       = 14
    env.WOW_PROJECT_ID                      = 5

    --- Adds a client font object reporting a face, the way a locale client ships extra
    --- fonts. It becomes visible to GetFonts, so the addon's harvest can see it.
    local function addFontObject(name, path, size)
        env[name] = fontObject(name, size or 12, path)
        return env[name]
    end

    return {
        UIParent   = UIParent,
        Minimap    = Minimap,
        CreateFrame = CreateFrame,
        fireEvent  = fireEvent,
        fontObjects = fontObjects,
        addFontObject = addFontObject,
        GameTooltip = GameTooltip,
    }
end

return M
