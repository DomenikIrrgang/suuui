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
    regions.resetGradientSupport()

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
            f:SetScript("OnClick", function(self, button, down)
                frame.secureAction(self, button, down)
            end)
        end
        -- StanceButtonTemplate. Modelled because SuuUI has no choice but to inherit it: the real
        -- button carries NO `type` attribute (probed in game) and `CastShapeshiftForm` is BLOCKED
        -- for tainted code (probed, bracketed -- form 7, cast 3, still form 7, silently), so an
        -- addon cannot drive a stance change from its own handler. The template is the only path.
        --
        -- What it supplies is the three child regions its consumers address by field and the
        -- OnClick that does the casting. The regions are the reason this is worth modelling at
        -- all: a component built on this template PAINTS THROUGH THEM rather than creating its
        -- own, so a spec that cannot see them cannot assert anything about the icon or cooldown.
        if template == "StanceButtonTemplate" and f._canScript then
            f.icon = f:CreateTexture(nil, "ARTWORK")
            f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
            f.HotKey = f:CreateFontString(nil, "OVERLAY")
            -- The template ships its OWN border and highlight art, and a consumer that composes
            -- its own visuals has to clear them. Modelled so that clearing is OBSERVABLE: with no
            -- art here, "we removed Blizzard's border" asserts against nothing.
            -- TEXTURE OBJECTS, not asset strings, because that is what the client's getters hand
            -- back -- and hiding the object is the only legal way to clear one, since the setters
            -- refuse nil. A spec asserting "we removed Blizzard's border" needs the object.
            local normal = f:CreateTexture(nil, "BORDER")
            normal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            f:SetNormalTexture(normal)
            local hl = f:CreateTexture(nil, "HIGHLIGHT")
            hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            f:SetHighlightTexture(hl)
            -- The cast reads GetID() and nothing else -- there is no attribute to consult. This
            -- lands in state.castStance via the recorded CastShapeshiftForm, so a spec asserts
            -- "clicking button 3 casts form 3" against the same observable the client would move.
            --
            -- REGISTRATION IS A GUESS AND IS DELIBERATELY CONTAINED HERE. GetRegisteredClicks was
            -- not readable in game, so which phase the real template acts on is UNMEASURED. It is
            -- safe to model it wrongly precisely because SuuUI never calls RegisterForClicks on
            -- these buttons -- the template owns that decision -- so a wrong guess can only make a
            -- spec test the wrong phase, never make SuuUI behave wrongly.
            f:RegisterForClicks("AnyUp")
            f:SetScript("OnClick", function(self, button, down)
                if type(env.CastShapeshiftForm) == "function" then
                    env.CastShapeshiftForm(self:GetID())
                end
                -- The client fires PostClick after any button's OnClick, and it is the only hook a
                -- consumer may take without stealing the mechanism -- so a model that omitted it
                -- would make "observe the click without replacing OnClick" untestable.
                self:_fire("PostClick", button, down)
            end)
        end
        -- ContainerFrameItemButtonTemplate. Modelled for the same reason StanceButtonTemplate is:
        -- SuuUI has no choice but to inherit it. USING an item from tainted Lua is BLOCKED on this
        -- client -- measured 2026-08-24 as the ForceTaint_Strong popup, with pcall returning true
        -- and the stack count unchanged -- so a cell cannot use an item from a handler of its own.
        -- The template's OWN OnClick is the whole mechanism, which is also why replacing it with
        -- SetScript("OnClick") yields a cell that looks perfect and does nothing.
        --
        -- SLOT AND BAG ARE POSITIONAL: the slot is this frame's id, the bag is its PARENT's. That
        -- is what lets a cell state both once at construction and never re-point them as contents
        -- change -- the discipline ActionButton arrived at the hard way. Modelled this way round on
        -- purpose: a model that read the bag off the button itself would let a consumer get the
        -- parentage wrong and still pass.
        if template == "ContainerFrameItemButtonTemplate" and f._canScript then            -- The regions a consumer addresses by field. They are the reason this is worth
            -- modelling: a cell built on the template can paint through them, and a spec that
            -- cannot see them cannot assert anything about the icon or the count.
            f.icon       = f:CreateTexture(nil, "ARTWORK")
            f.Count      = f:CreateFontString(nil, "OVERLAY")
            f.Cooldown   = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
            f.IconBorder = f:CreateTexture(nil, "OVERLAY")
            -- The template's own art, present so that CLEARING it is observable. With no art here,
            -- "we removed Blizzard's border" asserts against nothing.
            local normal = f:CreateTexture(nil, "BORDER")
            normal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            f:SetNormalTexture(normal)
            local hl = f:CreateTexture(nil, "HIGHLIGHT")
            hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            f:SetHighlightTexture(hl)
            -- THE REGIONS NO FIELD NAME REACHES, and they are the point of this block rather than a
            -- detail. Measured in game 2026-08-24: after a consumer cleared `icon`, `Count`,
            -- `IconBorder` and the four texture getters, the real cell STILL had three visible
            -- textures -- fileID 969828 twice and 902180 once. 969828 is
            -- `Interface\Common\WhiteIconFrame`, a white square outline vertex-tinted for item
            -- quality, and it ships at a FIXED 37x37 instead of being anchored to the button, which
            -- is why it read as a cell border at one size and pulled inward at a larger one.
            --
            -- They are deliberately UNREACHABLE by field and SHOWN by default, because a model whose
            -- every region carries a name the consumer already knows cannot fail: the hand-written
            -- list that shipped the bug would pass against it. Clearing these requires ENUMERATING
            -- GetRegions, which is the property worth pinning.
            local quality = f:CreateTexture(nil, "OVERLAY")
            quality:SetTexture(969828)
            quality:SetVertexColor(0.12, 0.44, 0.87, 1)
            quality:SetSize(37, 37)
            local overlay2 = f:CreateTexture(nil, "OVERLAY")
            overlay2:SetTexture(902180)
            -- One phase, and the guess is contained for the same reason as StanceButtonTemplate:
            -- SuuUI never calls RegisterForClicks on these, so the template owns the decision.
            f:RegisterForClicks("AnyUp")
            f:SetScript("OnClick", function(self, button, down)
                local C   = env.C_Container
                local par = self:GetParent()
                local bag  = par and par.GetID and par:GetID()
                local slot = self:GetID()
                if C and bag and slot then
                    if env.CursorHasItem() then
                        -- Place. Goes through the same pickup, so the swap is one implementation.
                        C.PickupContainerItem(bag, slot)
                    elseif env.IsShiftKeyDown and env.IsShiftKeyDown() then
                        C.SplitContainerItem(bag, slot, 1)
                    else
                        -- TRUSTED, so this is not the refused path a tainted caller takes.
                        state.trustedUseContainerItem(bag, slot)
                    end
                end
                self:_fire("PostClick", button, down)
            end)
        end

        -- BankItemButtonGenericTemplate -- the BANK's OWN 28-slot container, a different template
        -- family from a bag. Modelled because the difference IS the bug this found: this handler
        -- HARDCODES the bank container and reads only the SLOT from GetID(), where the bag template
        -- reads the container from its parent's id. A cell on the wrong one acts on the wrong
        -- container, which is why the bank window opened and could not move anything.
        --
        -- Bank BAGS (5..11) are ordinary containers and keep the bag template; only -1 comes here,
        -- exactly as ElvUI branches on this same client.
        if template == "BankItemButtonGenericTemplate" and f._canScript then
            f.icon     = f:CreateTexture(nil, "ARTWORK")
            f.Count    = f:CreateFontString(nil, "OVERLAY")
            f.Cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
            local bnormal = f:CreateTexture(nil, "BORDER")
            bnormal:SetTexture("Interface\\Buttons\\UI-Slot-Background")
            f:SetNormalTexture(bnormal)
            f:RegisterForClicks("AnyUp")
            f:SetScript("OnClick", function(self, button, down)
                local C = env.C_Container
                -- THE BANK CONTAINER, not the parent's id. That is the modelled difference.
                local bag  = (env.Enum and env.Enum.BagIndex and env.Enum.BagIndex.Bank) or -1
                local slot = self:GetID()
                if C and slot then
                    if env.CursorHasItem() then
                        C.PickupContainerItem(bag, slot)
                    elseif env.IsShiftKeyDown and env.IsShiftKeyDown() then
                        C.SplitContainerItem(bag, slot, 1)
                    else
                        state.trustedUseContainerItem(bag, slot)
                    end
                end
                self:_fire("PostClick", button, down)
            end)
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
        function o:GetFont() return self._path, self._size, self._flags or "" end
        function o:GetName() return self._name end

        --- Font objects are SETTABLE in the client, and that is the whole point of them:
        --- assigning one covers every FontString that inherits it, including ones created
        --- later. Restyling tooltip text is done this way rather than by walking
        --- GameTooltipTextLeft1..N, so without a settable model that decision would be
        --- untestable and a per-line walk would look like the only option.
        ---
        --- **Raises** for an unloadable asset, exactly as FontString:SetFont does. Same
        --- reason: modelling it as a return value once let a login-breaking error through,
        --- so anything probing font paths has to protect the call.
        function o:SetFont(p, s, flags)
            if not font.hasFace(p) then
                error("Font:SetFont(): Invalid font asset (" .. tostring(p)
                      .. "): file not found", 2)
            end
            self._path, self._size, self._flags = p, s, flags
            return true
        end

        function o:SetTextColor(r, g, b, a)
            self._color = { r, g, b, a == nil and 1 or a }
        end

        function o:GetTextColor()
            local c = self._color
            if not c then return 1, 1, 1, 1 end
            return c[1], c[2], c[3], c[4]
        end

        function o:SetShadowOffset(x, y) self._shadowX, self._shadowY = x, y end
        function o:GetShadowOffset() return self._shadowX or 0, self._shadowY or 0 end
        function o:SetShadowColor(r, g, b, a)
            self._shadowColor = { r, g, b, a == nil and 1 or a }
        end
        function o:SetJustifyH(j) self._justifyH = j end
        function o:GetJustifyH() return self._justifyH or "LEFT" end
        function o:SetJustifyV(j) self._justifyV = j end
        function o:GetJustifyV() return self._justifyV or "MIDDLE" end

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
    -- Copper, as GetMoney() reports it. Staged rather than fixed because the inventory footer
    -- prints it and the cache stores it per character.
    env.GetMoney      = function() return state.money or 0 end
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
    -- Blizzard's bottom action bar cluster (the ActionBars plugin suppresses it)
    --------------------------------------------------------------------------

    -- MEASURED IN GAME by walking up from the button:
    --   ActionButton1 > MainActionBarButtonContainer1 > MainActionBar > UIParent
    --
    -- So this client has BOTH MainActionBar and MainMenuBar, and they are different frames: the
    -- first holds the buttons, the second carries the art. Modelled that way because the earlier
    -- model put the buttons inside MainMenuBar, which made "hiding MainMenuBar hides the buttons"
    -- true here and false in game -- suppression removed the gryphons and left all twelve buttons
    -- on screen while every spec passed.
    --
    -- MainActionBar carries the CLIENT'S OWN secure buttons, which is why hiding it is a protected
    -- operation: protection propagates down to them and the refusal propagates back up.
    local MainActionBar = blizzardSystemFrame(CreateFrame("Frame", "MainActionBar", UIParent))
    MainActionBar:SetSize(512, 44)
    MainActionBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    local MainButtonContainer = CreateFrame("Frame", "MainActionBarButtonContainer1", MainActionBar)
    MainButtonContainer:SetSize(512, 44)
    MainButtonContainer:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 0, 0)
    for i = 1, 12 do
        local b = CreateFrame("Button", "ActionButton" .. i, MainButtonContainer,
            "SecureActionButtonTemplate")
        b:SetSize(36, 36)
        b:SetPoint("BOTTOMLEFT", MainButtonContainer, "BOTTOMLEFT", (i - 1) * 40, 4)
        b:SetAttribute("type", "action")
        b:SetAttribute("action", i)
    end

    -- The art frame, a SEPARATE top-level frame from the one above.
    local MainMenuBar = blizzardSystemFrame(CreateFrame("Frame", "MainMenuBar", UIParent))
    MainMenuBar:SetSize(512, 60)
    MainMenuBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)

    -- The four multibars, each carrying the slot block MEASURED IN GAME during Phase 0 of the
    -- bottom-UI work. Modelled with their real blocks so a spec reading a button's action
    -- attribute gets the mapping the client actually has, rather than a guess.
    for _, def in ipairs({
        { name = "MultiBarBottomLeft",  first = 61 },
        { name = "MultiBarBottomRight", first = 49 },
        { name = "MultiBarLeft",        first = 37 },
        { name = "MultiBarRight",       first = 25 },
    }) do
        local bar = blizzardSystemFrame(CreateFrame("Frame", def.name, UIParent))
        bar:SetSize(512, 40)
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 60)
        for i = 1, 12 do
            local b = CreateFrame("Button", def.name .. "Button" .. i, bar,
                "SecureActionButtonTemplate")
            b:SetSize(36, 36)
            b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", (i - 1) * 40, 2)
            b:SetAttribute("type", "action")
            b:SetAttribute("action", def.first + i - 1)
        end
    end

    -- Bars 6, 7 and 8. Present on this client -- measured, and Blizzard's own options list them --
    -- with the slot blocks read off their own buttons: 145, 157, 169. The numbering follows the
    -- frame name here, which it does NOT for bars 4 and 5, so each pairing was measured rather than
    -- inferred from the one before it.
    for _, def in ipairs({
        { name = "MultiBar5", first = 145 },
        { name = "MultiBar6", first = 157 },
        { name = "MultiBar7", first = 169 },
    }) do
        local bar = blizzardSystemFrame(CreateFrame("Frame", def.name, UIParent))
        bar:SetSize(512, 40)
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 100)
        for i = 1, 12 do
            local b = CreateFrame("Button", def.name .. "Button" .. i, bar,
                "SecureActionButtonTemplate")
            b:SetSize(36, 36)
            b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", (i - 1) * 40, 2)
            b:SetAttribute("type", "action")
            b:SetAttribute("action", def.first + i - 1)
        end
    end

    -- The bar art and the gryphons, children of MainMenuBar as in the live client. They hold no
    -- secure frames of their own and no secure ANCESTOR -- the buttons are their siblings, not
    -- their parents -- so hiding these is never refused, even mid-fight. That asymmetry is why
    -- they are separate suppression targets from the bars themselves.
    for _, name in ipairs({ "MainMenuBarArtFrame", "MainMenuBarLeftEndCap",
                            "MainMenuBarRightEndCap", "MainMenuBarMaxLevelBar" }) do
        local f = blizzardSystemFrame(CreateFrame("Frame", name, MainMenuBar))
        f:SetSize(256, 60)
        f:SetPoint("BOTTOMLEFT", MainMenuBar, "BOTTOMLEFT", 0, 0)
    end

    -- Neighbours in the same cluster that LATER phases own: the micro menu (7), the bags (9),
    -- the watch bars (8), the class bars (6). Present so a spec asserting "phase 4b does not
    -- touch these" is testing something rather than skipping an absent frame.
    for _, name in ipairs({ "MicroMenuContainer", "MicroButtonAndBagsBar",
                            "StatusTrackingBarManager",
                            "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
                            "StanceBar", "PetActionBar", "PossessActionBar",
                            }) do
        local f = blizzardSystemFrame(CreateFrame("Frame", name, UIParent))
        f:SetSize(120, 30)
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
    end

    -- THE PANEL TOGGLES the micro menu calls.
    --
    -- Recorded rather than enacted: a spec's question is whether the field asked the client to open
    -- this panel, and actually building a character sheet is the client's job. Modelled because
    -- `CharacterMicroButton:Click()` is a NO-OP on this client -- it has no OnClick script (probed) --
    -- so the panel API is the only route, and a consumer checks each function EXISTS before offering
    -- the entry at all.
    --
    -- `ToggleKeyRing` is deliberately ABSENT so a spec can prove an entry whose action is missing is
    -- skipped rather than rendered as a control that does nothing.
    env.BOOKTYPE_SPELL = "spell"
    for _, name in ipairs({
        "ToggleCharacter", "ToggleSpellBook", "ToggleQuestLog", "ToggleGameMenu",
        "ToggleHelpFrame", "ToggleGuildFrame", "ToggleTalentFrame", "ToggleFriendsFrame",
        "TogglePVPFrame", "ToggleLFGParentFrame", "ToggleWorldMap",
    }) do
        env[name] = function(arg)
            state.panelToggles[#state.panelToggles + 1] = { name = name, arg = arg }
        end
    end

    -- BLIZZARD'S OWN BAG CONTAINERS AND THE FUNCTIONS THAT OPEN THEM.
    --
    -- Modelled so SUPPRESSION is observable. A guarded OnShow hook can only be proven to work if
    -- something actually shows the frame, and a witness cell can only prove "a bag slot is off the
    -- screen" if the cell exists -- hiding a container is the MEANS, a cell being gone is the END, and
    -- the action bar work already shipped a version where every signal said success while twelve
    -- buttons sat in plain view.
    --
    -- ContainerFrame1..13: thirteen because that is backpack + 4 bags + 7 bank bags + the bank's own
    -- grid, which is what the client allocates. `ContainerFrame1Item1` is the CLASSIC cell name and is
    -- the one measured present on this build; `ContainerFrameItemButton1` is the retail spelling and is
    -- deliberately NOT modelled, because probing for it was already a mistake once.
    --
    -- These are PLAIN Buttons, not a secure template, which is itself the fact a spec should be able
    -- to rely on: unlike an action bar, hiding a bag container is not protected and needs no combat
    -- deferral. Modelling them as plain frames is what keeps that true here as well as in game.
    for i = 1, 13 do
        local cf = CreateFrame("Frame", "ContainerFrame" .. i, env.UIParent)
        cf:SetSize(200, 300)
        cf:Hide()
        local cell = CreateFrame("Button", "ContainerFrame" .. i .. "Item1", cf)
        cell:SetSize(37, 37)
        cell:SetID(1)
    end

    -- MerchantFrame, so "am I at a vendor" is answerable. A consumer gates its SELL path on this --
    -- UseContainerItem means USE away from a merchant (refused) and SELL at one (permitted) -- so
    -- without the frame that branch is unreachable and the harness silently tests the no-op path.
    -- Its shown state follows state.merchantOpen, which H.setMerchantOpen already drives.
    env.MerchantFrame = CreateFrame("Frame", "MerchantFrame", env.UIParent)
    env.MerchantFrame.IsShown = function() return state.merchantOpen == true end
    env.MerchantFrame.IsVisible = env.MerchantFrame.IsShown

    env.BankFrame = CreateFrame("Frame", "BankFrame", env.UIParent)
    env.BankFrame:SetSize(400, 300)
    env.BankFrame:Hide()
    -- HIDING THIS FRAME CLOSES THE BANK, and modelling that is the whole point of it being here.
    -- Blizzard's BankFrame_OnHide calls CloseBankFrame(), so a consumer that suppresses the frame the
    -- way it suppresses a bag container ends the session server-side: the bank then reads as 28 slots
    -- with 0 free and NOTHING can be moved into it. That shipped, and the suite could not see it
    -- because the harness treated this frame as inert scenery.
    --
    -- ElvUI's DisableFrame nils OnHide BEFORE it ever hides this frame, which is the corroboration
    -- that this is the client's real behaviour rather than a guess.
    env.BankFrame:SetScript("OnHide", function()
        state.bankOpen = false
    end)
    env.BankFrame:SetScript("OnShow", function()
        state.bankOpen = true
    end)
    local bankCell = CreateFrame("Button", "BankFrameItem1", env.BankFrame)
    bankCell:SetSize(37, 37)
    bankCell:SetID(1)

    -- The bag-opening globals. REAL FUNCTIONS THAT SHOW THE FRAMES, not recorders, and that choice is
    -- the whole point: a consumer REPLACES these to make the `B` key open its own window, so a spec
    -- has to be able to tell "our replacement ran" from "Blizzard's original ran". A recorder would
    -- look identical either way, because neither would put a container on screen.
    --
    -- ToggleAllBags is defined HERE rather than in the panel-toggle list above for the same reason --
    -- it needs a real effect. It is also the one ElvUI secure-hooks in game, which is why the
    -- suppression module has to cope with its global being wrapped underneath it.
    local function bagFrame(id)
        return _G["ContainerFrame" .. ((id or 0) + 1)]
    end
    env.OpenBackpack = function()
        local f = bagFrame(0)
        if f then f:Show() end
    end
    env.CloseBackpack = function()
        local f = bagFrame(0)
        if f then f:Hide() end
    end
    env.ToggleBackpack = function()
        local f = bagFrame(0)
        if not f then return end
        if f:IsShown() then f:Hide() else f:Show() end
    end
    env.OpenBag = function(id)
        local f = bagFrame(id)
        if f then f:Show() end
    end
    env.CloseBag = function(id)
        local f = bagFrame(id)
        if f then f:Hide() end
    end
    env.ToggleBag = function(id)
        local f = bagFrame(id)
        if not f then return end
        if f:IsShown() then f:Hide() else f:Show() end
    end
    env.OpenAllBags = function()
        for i = 0, (env.NUM_BAG_SLOTS or 4) do
            local f = bagFrame(i)
            if f then f:Show() end
        end
    end
    env.CloseAllBags = function()
        for i = 0, (env.NUM_BAG_SLOTS or 4) do
            local f = bagFrame(i)
            if f then f:Hide() end
        end
    end
    env.ToggleAllBags = function()
        -- RECORDED AS WELL AS ACTED ON. Plugins/DataBar/BagsWidget's spec asserts this call lands in
        -- the panel-toggle log -- its question is "did the field ask the client to open the bags",
        -- which is answered by the request rather than by the outcome. The real effect is added for
        -- the suppression work without taking that away.
        state.panelToggles[#state.panelToggles + 1] = { name = "ToggleAllBags" }
        local first = bagFrame(0)
        if first and first:IsShown() then env.CloseAllBags() else env.OpenAllBags() end
    end

    -- BLIZZARD'S OWN PET BUTTONS, with the handler that makes them worth modelling.
    --
    -- These exist so a consumer can FORWARD a click into them. `TogglePetAutocast` is protected, so
    -- an addon cannot toggle autocast itself -- the only legitimate route is `type2 = "click"` plus
    -- `clickbutton2` pointing here, after which the CLIENT presses this button and its own trusted
    -- handler does the protected work.
    --
    -- The handler below is Blizzard's branch, modelled: right-click toggles autocast, anything else
    -- casts. Without it the forward would land on an inert frame and the spec would assert nothing.
    for i = 1, (env.NUM_PET_ACTION_SLOTS or 10) do
        local b = CreateFrame("Button", "PetActionButton" .. i, env.PetActionBar)
        b:SetSize(30, 30)
        b:SetID(i)
        b:RegisterForClicks("AnyUp")
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if type(env.TogglePetAutocast) == "function" then
                    env.TogglePetAutocast(self:GetID())
                end
            elseif type(env.CastPetAction) == "function" then
                env.CastPetAction(self:GetID())
            end
        end)
    end

    -- Recorded, like every other client action: the spec's question is whether the button asked the
    -- client to use this pet slot.
    env.CastPetAction = function(index)
        state.castPetAction = index
    end

    -- MicroMenu is a child of MicroMenuContainer, NOT of MainMenuBar. Measured in game, because
    -- the answer decided whether Phase 4b could hide the bar cluster at all: under MainMenuBar
    -- the player would have lost the character pane, the spellbook and the bags until Phase 7.
    -- Modelled with the real parent so a Phase 7 spec hiding the container gets the real cascade.
    local MicroMenu = blizzardSystemFrame(
        CreateFrame("Frame", "MicroMenu", env.MicroMenuContainer))
    MicroMenu:SetSize(120, 30)
    MicroMenu:SetPoint("BOTTOMLEFT", env.MicroMenuContainer, "BOTTOMLEFT", 0, 0)

    -- BLIZZARD'S OWN MICRO BUTTONS.
    --
    -- Modelled as real Buttons with a recording OnClick, because the micro menu REPLACES the strip
    -- with data-bar fields and each field triggers the matching Blizzard button. Without these there
    -- is nothing to resolve and nothing for a click to reach.
    --
    -- THE LIST IS DELIBERATELY INCOMPLETE. `LFDMicroButton` and every retail-only name ElvUI carries
    -- (ProfessionMicroButton, PlayerSpellsMicroButton, AchievementMicroButton, EJMicroButton,
    -- StoreMicroButton, HousingMicroButton) are LEFT OUT, so a spec can prove the consumer skips a
    -- button that does not exist rather than rendering a dead field. Phase 0 measured MICRO_BUTTONS
    -- as nil on this client, so nothing enumerates them for us.
    -- CREATED AFTER MicroMenu, and that ordering is load-bearing: the first version of this block sat
    -- above it, so `env.MicroMenu` was nil and every button was parented to UIParent instead. Hiding
    -- the container then left them all visible, and the suppression witness caught it.
    assert(env.MicroMenu, "harness: micro buttons must be created after MicroMenu exists")
    for _, name in ipairs({
        "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
        "QuestLogMicroButton", "SocialsMicroButton", "GuildMicroButton",
        "PVPMicroButton", "LFGMicroButton", "WorldMapMicroButton",
        "MainMenuMicroButton", "HelpMicroButton", "CollectionsMicroButton",
    }) do
        local b = CreateFrame("Button", name, env.MicroMenu)
        b:SetSize(28, 36)
        b:RegisterForClicks("AnyUp")
        b:SetScript("OnClick", function(self)
            state.microClicks[#state.microClicks + 1] = self:GetName()
        end)
    end
    -- The bag and keyring buttons are BUTTONS on the real client, not plain frames -- a consumer
    -- checks for a Click method before wiring a field to one, so modelling them as Frames would make
    -- the consumer skip them and the spec would agree with the wrong answer.
    for _, name in ipairs({ "MainMenuBarBackpackButton", "KeyRingButton" }) do
        local b = blizzardSystemFrame(CreateFrame("Button", name, UIParent))
        b:SetSize(32, 32)
        b:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
        b:RegisterForClicks("AnyUp")
        b:SetScript("OnClick", function(self)
            state.microClicks[#state.microClicks + 1] = self:GetName()
        end)
    end


    -- CVars the addon reads. Only the boolean form is modelled, because that is all anything here
    -- asks for, and an unset CVar answers false -- which is what the client does for one it does
    -- not know. Staged through H.setCVarBool.
    --
    -- `ActionButtonUseKeyDown` matters more than it looks: an action button reads it to decide
    -- whether the client acts on the press or the release, and getting that wrong produces a button
    -- with correct attributes and no action. Left FALSE by default so the existing specs describe
    -- the release path; a spec that cares about the press stages it.
    env.GetCVarBool = function(name)
        return state.cvars[name] and true or false
    end

    env.GetCVar = function(name)
        local v = state.cvars[name]
        if v == nil then return nil end
        if v == true then return "1" elseif v == false then return "0" end
        return tostring(v)
    end

    --------------------------------------------------------------------------
    -- Action bar slots
    --------------------------------------------------------------------------

    -- Measured in game during Phase 0 of the bottom-UI work, not assumed: 12 buttons across
    -- 6 pages on this client. Pages 3..6 are the same slots the four multibars own, so a
    -- paged bar 1 and a fixed bar 3 can legitimately address one slot at the same time.
    env.NUM_ACTIONBAR_BUTTONS = 12
    env.NUM_ACTIONBAR_PAGES   = 6

    -- A CVar-backed plain global, so it is a string "0"/"1" rather than a boolean, and a
    -- spec changes it by writing H.env.LOCK_ACTIONBAR the way the client's own options do.
    env.LOCK_ACTIONBAR = state.actionBarLocked

    -- One slot as the client describes one. Defaults fill every field a real action carries
    -- so a staged entry declares only what its test is about.
    --
    -- Note what is NOT defaulted: `text` (a macro's name, which a spell does not have) and
    -- `inRange`. Both are meaningfully nil, and defaulting either would hide a real
    -- distinction -- see IsActionInRange below.
    local ACTION_DEFAULTS = {
        type = "spell", id = 0, subType = "spell",
        texture = "Interface\\Icons\\INV_Misc_QuestionMark",
        count = 0,
        cooldownStart = 0, cooldownDuration = 0, cooldownEnable = 1,
    }

    local function slotRecord(slot)
        if type(slot) ~= "number" then return nil end
        return state.actions[slot]
    end

    env.HasAction = function(slot)
        return slotRecord(slot) ~= nil
    end

    env.GetActionInfo = function(slot)
        local a = slotRecord(slot)
        if not a then return nil end
        return a.type or ACTION_DEFAULTS.type,
               a.id or ACTION_DEFAULTS.id,
               a.subType or ACTION_DEFAULTS.subType
    end

    env.GetActionTexture = function(slot)
        local a = slotRecord(slot)
        if not a then return nil end
        return a.texture or ACTION_DEFAULTS.texture
    end

    -- A macro's name, drawn under the icon. nil for a spell or an item, which is precisely
    -- why a caller must not use this to decide whether a slot is occupied.
    env.GetActionText = function(slot)
        local a = slotRecord(slot)
        if not a then return nil end
        return a.text
    end

    env.GetActionCount = function(slot)
        local a = slotRecord(slot)
        if not a then return 0 end
        return a.count or ACTION_DEFAULTS.count
    end

    -- start, duration, enable. An empty slot answers 0, 0, 0 rather than nil: the client
    -- does, and a Cooldown frame handed nil errors instead of clearing.
    env.GetActionCooldown = function(slot)
        local a = slotRecord(slot)
        if not a then return 0, 0, 0 end
        return a.cooldownStart or ACTION_DEFAULTS.cooldownStart,
               a.cooldownDuration or ACTION_DEFAULTS.cooldownDuration,
               a.cooldownEnable == nil and ACTION_DEFAULTS.cooldownEnable or a.cooldownEnable
    end

    -- usable, notEnoughMana. An empty slot is not usable, and is not short of mana either.
    env.IsUsableAction = function(slot)
        local a = slotRecord(slot)
        if not a then return false, false end
        return a.usable ~= false, a.notEnoughMana == true
    end

    -- true, false, or NIL -- and the nil is load-bearing. It means range is not a question
    -- for this action (a self buff, a macro with no target), which a button has to render
    -- differently from genuinely out of range. Defaulting it to true would erase that.
    env.IsActionInRange = function(slot)
        local a = slotRecord(slot)
        if not a then return nil end
        return a.inRange
    end

    env.IsCurrentAction = function(slot)
        local a = slotRecord(slot)
        return a ~= nil and a.current == true
    end

    env.IsAutoRepeatAction = function(slot)
        local a = slotRecord(slot)
        return a ~= nil and a.autoRepeat == true
    end

    env.GetActionBarPage = function() return state.actionBarPage or 1 end

    -- Drag and drop. The cursor carries a slot's CONTENTS, not a reference to the slot, which
    -- is why dropping onto an occupied slot SWAPS: PlaceAction hands back what was there.
    -- Both fire ACTIONBAR_SLOT_CHANGED, because the slot really did change.
    env.PickupAction = function(slot)
        if type(slot) ~= "number" then return end
        state.pickedUpAction = state.actions[slot]
        state.actions[slot] = nil
        fireEvent("ACTIONBAR_SLOT_CHANGED", slot)
    end

    env.PlaceAction = function(slot)
        if type(slot) ~= "number" then return end
        local held = state.pickedUpAction
        state.pickedUpAction = state.actions[slot]
        state.actions[slot] = held
        fireEvent("ACTIONBAR_SLOT_CHANGED", slot)
    end

    --------------------------------------------------------------------------
    --------------------------------------------------------------------------
    -- Experience and the watched faction
    --------------------------------------------------------------------------

    -- Experience. An unset store answers 0/0, which is what a max-level character looks like to a
    -- consumer -- and the bar's whole hide condition is "nothing to say", so that default matters.
    env.UnitXP = function(unit)
        if unit ~= "player" then return 0 end
        return state.xp.current or 0
    end
    env.UnitXPMax = function(unit)
        if unit ~= "player" then return 0 end
        return state.xp.max or 0
    end

    -- RESTED is nil, not 0, when there is none. The client distinguishes "no rested bonus" from "a
    -- bonus of zero", and a consumer that treats nil as 0 draws a ghost fill of nothing rather than no
    -- ghost fill -- which is a visible difference.
    env.GetXPExhaustion = function()
        return state.xp.rested
    end

    -- Experience switched off deliberately (a trial account, or /xpoff on some builds). Distinct from
    -- being max level, and a bar that only checked the level would still show for one of these.
    env.IsXPUserDisabled = function()
        return state.xp.disabled == true
    end

    -- TWO SHAPES, because this client could present either and the addon must survive both.
    --
    -- `state.repApi` selects which one exists:
    --   "legacy" (default) -- only the positional GetWatchedFactionInfo
    --   "modern"           -- only C_Reputation.GetWatchedFactionData, returning a TABLE
    --   "none"             -- NEITHER, which is a real possibility on a modern backend and must be
    --                         distinguishable from "no faction is watched"
    --
    -- The legacy order is SIX values, taken from ElvUI's shim on this client rather than from memory:
    -- name, reaction, currentReactionThreshold, nextReactionThreshold, currentStanding, factionID.
    -- The old model returned five and stopped at `value`, which is why nothing caught the table form.
    env.GetWatchedFactionInfo = function()
        local w = state.watchedFaction
        if not w then return nil end
        return w.name, w.standing or 4, w.min or 0, w.max or 0, w.value or 0, w.factionID or 1168
    end
    -- Kept so H.setRepApi can REMOVE this global and put it back. Removal has to be real: a version of
    -- "no API" that leaves the function in place and merely returns nil is indistinguishable from "no
    -- faction is watched", which is the exact conflation that hid the bar in game.
    state.legacyRepFn = env.GetWatchedFactionInfo

    -- Containers / bags
    --------------------------------------------------------------------------
    -- TWO SHAPES, same as reputation, and for the same reason: a modern backend moved these onto
    -- `C_Container` and may not carry the bare globals. ElvUI dereferences
    -- `C_Container.GetContainerNumFreeSlots` at file scope with no nil guard and works on this client,
    -- so the namespace is present there. `state.bagApi` selects which one exists -- see H.setBagApi.
    --
    -- `state.bags` is an array indexed BY BAG ID FROM 0, each { free = n, slots = n, bagType = n }. A
    -- bagType other than 0 is a specialised container (quiver, ammo pouch, soul shard bag), whose free
    -- slots cannot hold loot -- which is why anything counting them has to be able to see the type.
    env.NUM_BAG_SLOTS         = 4
    env.NUM_BANKBAGSLOTS      = 7
    env.NUM_BANKGENERIC_SLOTS = 28
    env.Enum = env.Enum or {}
    env.Enum.BagIndex = env.Enum.BagIndex or { Backpack = 0, Bank = -1, Keyring = -2 }

    local BANK_CONTAINER = -1
    local BANK_BAG_FIRST, BANK_BAG_LAST = 5, 11

    -- Is this a bank container whose CONTENTS the client will not read right now? The slot COUNT
    -- survives a shut bank; the contents do not. See the note on state.bankOpen.
    local function bankShut(bag)
        if bag ~= BANK_CONTAINER and not (bag >= BANK_BAG_FIRST and bag <= BANK_BAG_LAST) then
            return false
        end
        return not state.bankOpen
    end

    local function bagFree(bag)
        if bankShut(bag) then return 0, 0 end
        local b = state.bags and state.bags[bag]
        if not b then return 0, 0 end
        return b.free or 0, b.bagType or 0
    end

    local function bagSlots(bag)
        local b = state.bags and state.bags[bag]
        if b then return b.slots or 0 end
        -- The bank's own grid is a client constant, answered even with the frame shut -- which is
        -- exactly what makes "28 slots, 0 free" the signature of no data rather than an empty bank.
        if bag == BANK_CONTAINER then return env.NUM_BANKGENERIC_SLOTS end
        return 0
    end

    local function slotRecord(bag, slot)
        if bankShut(bag) then return nil end
        local perBag = state.containerItems and state.containerItems[bag]
        return perBag and perBag[slot] or nil
    end

    -- Returns a FRESH table per call, as the client does, so a caller mutating what it got back
    -- cannot reach into the store. nil for an empty slot -- never a record of zeroes, because
    -- "is there anything here" has to be answerable.
    local function getContainerItemInfo(bag, slot)
        local it = slotRecord(bag, slot)
        if not it then return nil end
        return {
            hasLoot    = it.hasLoot or false,
            hasNoValue = it.hasNoValue or false,
            hyperlink  = it.hyperlink,
            iconFileID = it.iconFileID,
            isBound    = it.isBound or false,
            isFiltered = it.isFiltered or false,
            isLocked   = it.isLocked or false,
            isReadable = it.isReadable or false,
            itemID     = it.itemID,
            itemName   = it.itemName,
            quality    = it.quality,
            stackCount = it.stackCount,
        }
    end

    local function getContainerItemLink(bag, slot)
        local it = slotRecord(bag, slot)
        return it and it.hyperlink or nil
    end

    local function getContainerItemID(bag, slot)
        local it = slotRecord(bag, slot)
        return it and it.itemID or nil
    end

    -- Item cooldowns, kept in their own store rather than on the slot record because they are not
    -- part of what GetContainerItemInfo returns -- folding them in would invite a spec to stage a
    -- field the real client never reports there.
    --
    -- Returns three values like the action-slot version, and `enable` is a NUMBER: 0 means no
    -- cooldown. A consumer testing truthiness paints a permanent sweep over every item, because 0
    -- is truthy in Lua.
    local function getContainerItemCooldown(bag, slot)
        local perBag = state.containerCooldowns and state.containerCooldowns[bag]
        local cd = perBag and perBag[slot]
        if not cd then return 0, 0, 0 end
        return cd.start or 0, cd.duration or 0, cd.enable or 1
    end

    -- Drag and drop, the same contents-on-the-cursor model as PickupAction: the cursor carries a
    -- slot's CONTENTS, so a pickup onto a loaded cursor SWAPS and hands the previous occupant back.
    -- A cell that assumed overwrite would destroy an item every time the player rearranged a bag.
    --
    -- MEASURED 2026-08-24: this is NOT protected. pcall returned true and GetCursorInfo answered
    -- `item 27860 [Purified Draenic Water]` from a tainted /run with no block.
    local function pickupContainerItem(bag, slot)
        if type(bag) ~= "number" or type(slot) ~= "number" then return end
        if bankShut(bag) then return end
        local perBag = state.containerItems[bag]
        local there  = perBag and perBag[slot] or nil
        local held   = state.cursorItem
        if there == nil and held == nil then return end
        state.containerItems[bag] = perBag or {}
        state.containerItems[bag][slot] = held
        state.cursorItem = there
        fireEvent("BAG_UPDATE", bag)
    end

    local function splitContainerItem(bag, slot, count)
        if type(count) ~= "number" or count <= 0 then return end
        local it = slotRecord(bag, slot)
        if not it or not it.stackCount or it.stackCount <= count then return end
        local part = {}
        for k, v in pairs(it) do part[k] = v end
        part.stackCount = count
        it.stackCount   = it.stackCount - count
        state.cursorItem = part
        fireEvent("BAG_UPDATE", bag)
    end

    -- The accepted path, shared by the merchant sale and by the TEMPLATE's own trusted handler.
    -- `via` keeps the two distinguishable, because they are not the same event: one is a sale, the
    -- other is the client using the item on our behalf.
    local function acceptUse(bag, slot, via)
        local perBag = state.containerItems[bag]
        if not (perBag and perBag[slot]) then return false end
        state.usedContainerItems[#state.usedContainerItems + 1] =
            { bag = bag, slot = slot, via = via }
        perBag[slot] = nil
        fireEvent("BAG_UPDATE", bag)
        return true
    end

    -- What ContainerFrameItemButtonTemplate's own OnClick does. It is TRUSTED code, so it is not
    -- subject to the refusal a tainted caller gets -- and that asymmetry is the entire reason a
    -- SuuUI cell inherits the template instead of calling the API itself. A model that routed both
    -- through the same gate would make the template look as useless as the direct call.
    state.trustedUseContainerItem = function(bag, slot) return acceptUse(bag, slot, "template") end

    -- UseContainerItem has TWO protection profiles and the harness models both, because the
    -- difference was measured rather than inferred. At a MERCHANT it SELLS, which ElvUI drives from
    -- an OnUpdate on this client. Away from one it USES the item -- and that is BLOCKED, measured
    -- 2026-08-24 as `*** ForceTaint_Strong *** has been blocked from an action only available to
    -- the Blizzard UI`, with pcall returning true and the stack count unchanged.
    --
    -- A refused call is therefore RECORDED in blockedActions rather than raising, exactly as a
    -- refused geometry call is, because that is what the client does: it returns having changed
    -- nothing. Recording is the only observable a spec has, and it makes calling this from Lua a
    -- detectable defect instead of a silent no-op.
    --
    -- NOTE the merchant half is evidenced but not yet measured -- see the vendor probe in
    -- .kiro/specs/inventory.md section 0. If selling turns out to be blocked too, this gate is
    -- where that changes.
    -- THREE MEANINGS, TWO PERMITTED. At a MERCHANT it SELLS -- measured 2026-08-25, the item left the
    -- bag. At an OPEN BANK it TRANSFERS between bank and bags, which is the client's own right-click
    -- shortcut. Anywhere else it USES the item, and that is the one refused for tainted code.
    --
    -- The merchant half is now MEASURED rather than merely evidenced; the vendor probe in
    -- .kiro/specs/inventory.md section 0 records it.
    local function useContainerItem(bag, slot)
        if type(bag) ~= "number" or type(slot) ~= "number" then return end
        if state.merchantOpen then
            acceptUse(bag, slot, "merchant")
            return
        end
        if state.bankOpen then
            acceptUse(bag, slot, "bank")
            return
        end
        state.blockedActions[#state.blockedActions + 1] = {
            action = "UseContainerItem", bag = bag, slot = slot,
        }
    end

    -- The cursor as the client reports it. GetCursorInfo's item form is `"item", itemID, itemLink`,
    -- measured as `item 27860 [Purified Draenic Water]`.
    env.GetCursorInfo = function()
        local it = state.cursorItem
        if not it then return nil end
        return "item", it.itemID, it.hyperlink
    end
    env.CursorHasItem = function() return state.cursorItem ~= nil end
    env.ClearCursor   = function() state.cursorItem = nil end

    local containerApi = {
        GetContainerNumFreeSlots = bagFree,
        GetContainerNumSlots     = bagSlots,
        GetContainerItemInfo     = getContainerItemInfo,
        GetContainerItemLink     = getContainerItemLink,
        GetContainerItemID       = getContainerItemID,
        GetContainerItemCooldown = getContainerItemCooldown,
        PickupContainerItem      = pickupContainerItem,
        SplitContainerItem       = splitContainerItem,
        UseContainerItem         = useContainerItem,
    }

    -- The LEGACY shape is POSITIONAL, not the modern table under an old name. That difference is
    -- the entire reason both modes exist: a legacy mode handing back a table cannot exercise a
    -- positional reader at all, so a spec written against it would pass while the real legacy
    -- client fed the reader eleven values it never unpacked. Order taken from the shims three
    -- installed addons ship on this machine (RXPGuides, Gargul, Questie), not from memory.
    local function getContainerItemInfoLegacy(bag, slot)
        local i = getContainerItemInfo(bag, slot)
        if not i then return nil end
        return i.iconFileID, i.stackCount, i.isLocked, i.quality, i.isReadable, i.hasLoot,
               i.hyperlink, i.isFiltered, i.hasNoValue, i.itemID, i.isBound
    end

    local legacyApi = {}
    for name, fn in pairs(containerApi) do legacyApi[name] = fn end
    legacyApi.GetContainerItemInfo = getContainerItemInfoLegacy

    -- ONE installer for every mode, shared with H.setBagApi and called by state.reset(), so the two
    -- cannot drift about which globals a mode implies. Removal is REAL for the "none" case: a
    -- version leaving the function in place returning nil is indistinguishable from an empty bag,
    -- which is the conflation that hid the reputation bar in game.
    function state.applyBagApi(mode)
        local legacy = (mode == "legacy")
        for name in pairs(containerApi) do
            env[name] = legacy and legacyApi[name] or nil
        end
        env.C_Container = (mode == "modern") and containerApi or nil
    end

    state.applyBagApi(state.bagApi or "modern")
    -- The env itself, so reset can restore the API globals. The addon's chunks read from THIS table,
    -- not from the real _G, so anything touching _G is changing a table nothing under test reads.
    state.env = env

    -- `C_Reputation` itself is installed and removed by H.setRepApi rather than here, so there is ONE
    -- place that decides which API exists. Default (no helper call) is legacy-only, matching a client
    -- that never had the table form.
    env.C_Reputation = nil

    -- Shapeshift / stance forms
    --------------------------------------------------------------------------
    -- Return ORDERS here are not guessed. They are taken from the destructuring sites in
    -- ElvUI's StanceBar.lua, which runs correctly on this client -- the same route that
    -- settled the eight-bar slot mapping. Where ElvUI captures fewer returns than the client
    -- sends, only the captured ones are modelled, and that is called out.

    -- The client's own cap. 10 rather than 4: NUM_STANCE_SLOTS is the array bound, not the
    -- number of forms any class actually has, and a consumer that conflates the two sizes its
    -- bar to the cap instead of to the player.
    env.NUM_STANCE_SLOTS = 10

    local function stanceCount()
        local n = 0
        while state.stanceForms[n + 1] do n = n + 1 end
        return n
    end

    -- A spell's icon by id. Modelled because a shapeshift form is identified by spellID, not by a
    -- slot, and the stance icon is derived through here.
    env.GetSpellTexture = function(spellID)
        if type(spellID) ~= "number" then return nil end
        return state.spellTextures[spellID]
    end

    env.GetNumShapeshiftForms = function()
        return stanceCount()
    end

    -- The ACTIVE form index, or 0 for none. DERIVED from the records' isActive rather than
    -- stored alongside them, deliberately: the client cannot report form 2 active while form
    -- 2's own info says otherwise, so the harness must not be able to either. A second stored
    -- field would let a spec stage a disagreement and then assert against it.
    env.GetShapeshiftForm = function()
        for i = 1, stanceCount() do
            if state.stanceForms[i].isActive then return i end
        end
        return 0
    end

    -- texture, isActive, isCastable, spellID -- FOUR returns, in that order.
    -- ElvUI: `local texture, isActive, isCastable, spellID = GetShapeshiftFormInfo(i)`.
    --
    -- Note ElvUI ignores `texture` for the icon and derives it from spellID instead, using
    -- texture only as a truthiness test. Both are modelled so a consumer can do either.
    env.GetShapeshiftFormInfo = function(index)
        local f = type(index) == "number" and state.stanceForms[index] or nil
        if not f then return nil end
        return f.texture or "Interface\\Icons\\INV_Misc_QuestionMark",
               f.isActive == true,
               f.isCastable ~= false,
               f.spellID
    end

    -- start, duration, active -- THREE returns. ElvUI checks `active` against BOTH nil and 0
    -- (`if (active and active ~= 0) and start > 0 and duration > 0`), so a number is modelled
    -- rather than a boolean: answering true/false here would let a consumer that only tests
    -- truthiness pass while the real client, sending 0, made it fail.
    env.GetShapeshiftFormCooldown = function(index)
        local f = type(index) == "number" and state.stanceForms[index] or nil
        if not f then return 0, 0, 0 end
        return f.cooldownStart or 0, f.cooldownDuration or 0, f.cooldownActive or 0
    end

    -- Recorded, not enacted. Actually changing form would mean the harness deciding what that
    -- does to every other reading -- which form is active, what the bonus bar offset becomes,
    -- which cooldowns start. A spec asserts the cast, then stages the consequence it cares about.
    env.CastShapeshiftForm = function(index)
        state.castStance = index
    end

    -- How a druid's form or a rogue's stealth moves the paged bar. Read DEFENSIVELY by the
    -- caller: the plan parked "does form drive bonusbar or a page" as an open question, so a
    -- consumer must cope with this being absent on a client that lacks it.
    env.GetBonusBarOffset = function()
        return state.bonusBarOffset or 0
    end

    --------------------------------------------------------------------------
    -- Pet action bar
    --------------------------------------------------------------------------

    env.NUM_PET_ACTION_SLOTS = 10

    local function petRecord(index)
        if type(index) ~= "number" then return nil end
        return state.petActions[index]
    end

    -- name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID
    -- SEVEN returns, in that order. ElvUI PetBar.lua:35, verbatim:
    --   local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID
    --       = GetPetActionInfo(i)
    --
    -- THE TRAP, and the reason this comment is long: when `isToken` is true, `name` and
    -- `texture` are the NAMES OF GLOBALS, not a display name and a texture path. The consumer
    -- must resolve them through _G. Nothing is resolved here -- a harness that quietly did the
    -- lookup would let a consumer that forgot it pass, and then show a blank icon in game.
    env.GetPetActionInfo = function(index)
        local p = petRecord(index)
        if not p then return nil end
        return p.name,
               p.texture,
               p.isToken == true,
               p.isActive == true,
               p.autoCastAllowed == true,
               p.autoCastEnabled == true,
               p.spellID
    end

    -- start, duration. ElvUI captures only two (`local start, duration = GetPetActionCooldown(i)`)
    -- so only two are modelled; the client's third return is not something any consumer here reads.
    env.GetPetActionCooldown = function(index)
        local p = petRecord(index)
        if not p then return 0, 0 end
        return p.cooldownStart or 0, p.cooldownDuration or 0
    end

    env.GetPetActionSlotUsable = function(index)
        local p = petRecord(index)
        if not p then return false end
        return p.usable ~= false
    end

    -- Whether the pet's bar is usable AT ALL. Distinct from whether a pet exists: a present pet
    -- with an unusable bar greys its icons, an absent pet hides the bar. Collapsing the two is
    -- the mistake this separation exists to prevent.
    env.PetHasActionBar = function()
        return state.petHasActionBar == true
    end

    env.IsPetAttackAction = function(index)
        local p = petRecord(index)
        return p ~= nil and p.attack == true
    end

    -- Recorded AND enacted, unlike CastShapeshiftForm -- because the consequence is unambiguous
    -- and local: toggling autocast flips exactly one flag on one slot and nothing else.
    -- TogglePetAutocast(slotID, enabled). TWO arguments on this client -- the signature comes from
    -- the client's own API stub, and it is a SET rather than a blind flip. The one-argument form is
    -- still honoured, because a caller that omits the state means "the other one".
    env.TogglePetAutocast = function(index, enabled)
        local p = petRecord(index)
        state.petAutocastToggles[#state.petAutocastToggles + 1] = index
        if not p then return end
        if enabled == nil then
            p.autoCastEnabled = not p.autoCastEnabled
        else
            p.autoCastEnabled = enabled and true or false
        end
        fireEvent("PET_BAR_UPDATE")
    end

    --------------------------------------------------------------------------
    -- The page the client swaps bar 1 to for a TEMPORARY shapeshift -- the one a warlock's
    -- Demonic Circle or a priest's Shadowform-like temporary bar uses, as distinct from the
    -- bonus bars a form sets.
    --
    -- Called at runtime rather than hardcoded, exactly as ElvUI does, because its VALUE is a fact
    -- about the client that nothing here has measured. Staged so a spec can assert the driver
    -- without pinning a number the game owns.
    env.GetTempShapeshiftBarIndex = function()
        return state.tempShapeshiftBarIndex
    end

    -- Bindings
    --------------------------------------------------------------------------

    env.GetBindingKey = function(command)
        if type(command) ~= "string" then return nil end
        return state.bindings[command]
    end

    -- Recorded rather than enacted: a spec's question is "did the button claim this key",
    -- and simulating a keypress route would mean modelling the client's binding precedence.
    env.SetOverrideBindingClick = function(owner, isPriority, key, buttonName, mouseButton)
        state.overrideBindings[#state.overrideBindings + 1] = {
            owner = owner, isPriority = isPriority and true or false,
            key = key, button = buttonName, mouseButton = mouseButton,
        }
        return true
    end

    env.ClearOverrideBindings = function(owner)
        local kept = {}
        for _, b in ipairs(state.overrideBindings) do
            if b.owner ~= owner then kept[#kept + 1] = b end
        end
        state.overrideBindings = kept
    end

    --------------------------------------------------------------------------
    -- Secure state drivers
    --------------------------------------------------------------------------

    -- A RECORDER, deliberately not an evaluator. The conditional is a macro expression, and
    -- resolving one here would be the harness guessing what the client decides -- a spec
    -- would then assert against the guess. Record the string, assert the string, and check
    -- the consequence in game. This is the one paging mechanism that works in combat, so
    -- there is nothing else a spec could assert about it locally.
    env.RegisterStateDriver = function(frame, stateName, conditional)
        if not frame or type(stateName) ~= "string" then return end
        local rec = state.stateDrivers[frame]
        if not rec then
            rec = {}
            state.stateDrivers[frame] = rec
        end
        rec[stateName] = conditional
    end

    env.UnregisterStateDriver = function(frame, stateName)
        local rec = frame and state.stateDrivers[frame]
        if rec then rec[stateName] = nil end
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
        -- Computed BEFORE the return rather than inline: `x == false and nil or x or DEFAULT`
        -- does NOT work, because nil and false are both falsy so the `or` chain falls straight
        -- through to the default. That mistake made this look implemented while it was not.
        --
        -- `source = false` means the client names NO caster, which is a real and common state: an
        -- environmental debuff has none, and neither does one from a unit the client has stopped
        -- tracking. Without it the default masked the case, and a consumer that printed "Unknown"
        -- for every such aura would have looked correct. Same false-clears convention as
        -- H.setXP({ rested = false }).
        local src
        if entry.source ~= false then
            src = entry.source or AURA_DEFAULTS.source
        end
        return entry.name                  or AURA_DEFAULTS.name,
               entry.icon                  or AURA_DEFAULTS.icon,
               entry.count                 or AURA_DEFAULTS.count,
               entry.debuffType            or AURA_DEFAULTS.debuffType,
               entry.duration              or AURA_DEFAULTS.duration,
               entry.expirationTime        or AURA_DEFAULTS.expirationTime,
               src,
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
    -- Creature difficulty and guild info
    --------------------------------------------------------------------------
    -- GetCreatureDifficultyColor is the client's own answer and is preferred by SuuUI.Game, so
    -- it is modelled here rather than left absent -- otherwise every spec exercises the FALLBACK
    -- formula and the branch production actually takes is never run.
    env.GetCreatureDifficultyColor = function(level)
        local mine = (state.units and state.units.player and state.units.player.level)
                     or state.unitLevel or 70
        if type(level) ~= "number" then return { r = 1, g = 1, b = 0 } end
        local diff = level - mine
        if diff > 4  then return { r = 1.00, g = 0.10, b = 0.10 } end
        if diff > 2  then return { r = 1.00, g = 0.50, b = 0.25 } end
        if diff >= -2 then return { r = 1.00, g = 1.00, b = 0.00 } end
        if level > mine - (state.questGreenRange or 5) then
            return { r = 0.25, g = 0.75, b = 0.25 }
        end
        return { r = 0.50, g = 0.50, b = 0.50 }
    end

    -- Widens as the player levels, which is why a fixed grey offset is wrong.
    env.GetQuestGreenRange = function() return state.questGreenRange or 5 end

    -- Returns guildName, rankName, rankIndex -- the order SuuUI reads positionally.
    env.GetGuildInfo = function(unit)
        local u = unit and state.units and state.units[unit]
        if not u or not u.guild then return nil end
        return u.guild, u.guildRank, u.guildRankIndex or 0
    end

    --------------------------------------------------------------------------
    -- GetItemCount
    --------------------------------------------------------------------------
    -- Second argument is includeBank, and the client returns the TOTAL when it is true -- not
    -- the bank's own figure. A consumer wanting the split has to subtract, which is what makes
    -- staging the two numbers separately here worth doing: a model that returned the bank
    -- directly would let a consumer that forgot the subtraction pass.
    env.GetItemCount = function(link, includeBank)
        local rec = state.items and state.items[link]
        if not rec then return 0 end
        local bags = rec.countBags or 0
        if includeBank then return bags + (rec.countBank or 0) end
        return bags
    end

    --------------------------------------------------------------------------
    -- UnitGroupRolesAssigned
    --------------------------------------------------------------------------
    -- Answers the client's own strings: TANK / HEALER / DAMAGER / NONE. Measured in game --
    -- notably "DAMAGER" and not "DPS", so a consumer printing the raw value verbatim shows the
    -- wrong word. NONE for an unstaged unit, which is also what a solo player reports.
    env.UnitGroupRolesAssigned = function(unit)
        local u = unit and state.units and state.units[unit]
        return (u and u.role) or "NONE"
    end

    --------------------------------------------------------------------------
    -- GetItemInfo
    --------------------------------------------------------------------------
    -- Absent until now, which meant an item's QUALITY was unreachable in a spec -- so the
    -- quality-coloured tooltip border, the whole point of the signal-border treatment, could
    -- not be tested at all and its mutation would have survived.
    --
    -- Return ORDER matters and is the client's, recovered from on-disk consumers rather than
    -- memory: field 3 is quality, field 4 is the item level, field 11 is the sell price. Those
    -- three are the ones SuuUI reads; the rest are present so a positional `select` written
    -- against the real client lands on the same slot here.
    --
    -- An UNSTAGED link returns nothing at all, which is what the client does for an item it has
    -- not cached yet -- a real state a consumer has to survive, not an error.
    env.GetItemInfo = function(link)
        if type(link) ~= "string" and type(link) ~= "number" then return nil end
        local rec = state.items and state.items[link]
        if not rec then return nil end
        return rec.name, rec.link, rec.quality, rec.itemLevel, rec.reqLevel,
               rec.class, rec.subclass, rec.maxStack, rec.equipSlot, rec.texture,
               rec.sellPrice
    end

    -- client's own `.hex` field -- which is a |cff… COLOUR ESCAPE and not a colour.
    -- It is modelled deliberately, and deliberately WRONG-looking to read as a
    -- colour, because a caller that grabs `.hex` expecting numbers produces a
    -- string that silently swallows whatever it is concatenated into. Keeping it
    -- here means a spec can prove Game:ItemQualityColor ignores it.
    --------------------------------------------------------------------------
    env.ITEM_QUALITY_COLORS = {
        [0] = { r = 0.62, g = 0.62, b = 0.62, hex = "|cff9d9d9d" },
        [1] = { r = 1.00, g = 1.00, b = 1.00, hex = "|cffffffff" },
        [2] = { r = 0.12, g = 1.00, b = 0.00, hex = "|cff1eff00" },
        [3] = { r = 0.00, g = 0.44, b = 0.87, hex = "|cff0070dd" },
        [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "|cffa335ee" },
        [5] = { r = 1.00, g = 0.50, b = 0.00, hex = "|cffff8000" },
        [6] = { r = 0.90, g = 0.80, b = 0.50, hex = "|cffe6cc80" },
        [7] = { r = 0.00, g = 0.80, b = 1.00, hex = "|cff00ccff" },
    }

    --------------------------------------------------------------------------
    -- GameTooltip
    --------------------------------------------------------------------------

    -- Built from the GameTooltip frame type in wow/frame.lua rather than assembled here.
    -- It used to be a plain Frame with tooltip verbs bolted on, which meant CreateFrame
    -- refused the type ("does not simulate type GameTooltip") and no second instance was
    -- possible -- so embedded code that creates its own tooltip could not load at all, and
    -- the singleton had no AddLine for a spec to read content back from.
    -- WITH BackdropTemplate, because the client's tooltips genuinely are backdrop frames --
    -- they ship BACKDROP_TOOLTIP_16_16_5555 and ElvUI calls SetBackdrop straight onto them.
    -- Created without it, SetBackdrop raises here, which is a state the real GameTooltip is
    -- never in and which sent a reskin down its "this frame cannot take a backdrop" branch.
    local GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent, "BackdropTemplate")
    GameTooltip._tooltipShown = false

    -- The border Blizzard actually draws. MEASURED present on this client (interface 20504),
    -- against an earlier guess that it was absent -- which matters because a reskin that only
    -- calls SetBackdrop leaves this visible underneath and the player sees a double frame. It
    -- is modelled so `if tt.NineSlice then tt.NineSlice:SetAlpha(0) end` is a REACHABLE branch
    -- rather than dead code a mutation could delete unnoticed.
    GameTooltip.NineSlice = CreateFrame("Frame", "GameTooltipNineSlice", GameTooltip)

    -- The client's unit health bar. Its own frame, parented to the tooltip, and it ships with
    -- NO text and NO colour -- both are the addon's to supply, which is why a spec has to be
    -- able to read SetValue and SetStatusBarColor back off it.
    local statusBar = CreateFrame("StatusBar", "GameTooltipStatusBar", GameTooltip)
    statusBar:SetMinMaxValues(0, 100)
    statusBar:SetValue(100)
    env.GameTooltipStatusBar = statusBar

    -- The three Font OBJECTS every tooltip FontString inherits from. Modelled because the
    -- sanctioned way to restyle tooltip text is to assign these three once -- one call then
    -- covers lines that do not exist yet -- and without them here that decision would be
    -- untestable, leaving a per-line walk as the only shape a spec could describe.
    --
    -- GameTooltipHeaderText is line 1 and carries its own size; GameTooltipTextSmall is the
    -- comparison tooltips'. They are separate objects in the client, so they are separate here.
    env.GameTooltipText       = fontObject("GameTooltipText", 12)
    env.GameTooltipHeaderText = fontObject("GameTooltipHeaderText", 14)
    env.GameTooltipTextSmall  = fontObject("GameTooltipTextSmall", 11)

    --------------------------------------------------------------------------
    -- The two tooltip globals an addon HOOKS rather than calls
    --------------------------------------------------------------------------
    -- Both measured present on this client. They are modelled as real functions because
    -- hooksecurefunc needs something to hook -- without them a plugin's durability hook and
    -- its placement hook are never installed, and the branch that copes with their absence
    -- fires instead, which is a different code path from the one production takes.
    --
    -- Deliberately near-empty: what a spec asserts is that OUR hook ran and what it did, not
    -- Blizzard's own backdrop or its own anchor arithmetic. Reproducing either would mean
    -- asserting against the harness's version of it.

    --- Blizzard's shared backdrop restyle. Calling it is how a spec simulates the client
    --- re-stamping a tooltip, which is the event the durability hook exists to survive.
    env.SharedTooltip_SetBackdropStyle = function(tooltip, style, embedded)
        if type(tooltip) ~= "table" then return end
        tooltip._blizzBackdropStyle = style or "default"
        tooltip._blizzEmbedded = embedded and true or false
    end

    --- Blizzard's default placement. A spec calls it to reach the placement hook.
    env.GameTooltip_SetDefaultAnchor = function(tooltip, parent)
        if type(tooltip) ~= "table" then return end
        if type(tooltip.SetOwner) == "function" then
            tooltip:SetOwner(parent or UIParent, "ANCHOR_NONE")
        end
    end

    --------------------------------------------------------------------------
    -- The other tooltip frames the client ships
    --------------------------------------------------------------------------
    -- All measured present on this client (Phase 0 probe 1). They exist here so a consumer's
    -- FRAME LIST is a real list: with only GameTooltip modelled, a list iterated with ipairs
    -- and one iterated with `next` behave identically, because there is nothing behind the
    -- first hole for ipairs to drop. That made a real bug untestable.
    --
    -- Each is a GameTooltip carrying a backdrop, which is what they are for skinning purposes.
    -- EmbeddedItemTooltip's inner icon and IconBorder are NOT modelled -- nothing reads them
    -- yet, and inventing them would invite assertions against a shape that is not the client's.
    for _, ttName in ipairs({
        "ItemRefTooltip", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
        "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip",
        "WorldMapTooltip", "FriendsTooltip",
    }) do
        env[ttName] = CreateFrame("GameTooltip", ttName, UIParent, "BackdropTemplate")
    end

    -- The close button on the hyperlink tooltip, skinned by name in every reskin that touches it.
    env.ItemRefCloseButton = CreateFrame("Button", "ItemRefCloseButton", env.ItemRefTooltip)

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
