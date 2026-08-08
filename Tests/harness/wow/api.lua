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
        if name then env[name] = f end
        return f
    end

    ------------------------------------------------------------------------------
    -- Blizzard frames the addon touches
    ------------------------------------------------------------------------------
    local Minimap = CreateFrame("Frame", "Minimap", UIParent)
    Minimap:SetSize(140, 140)
    Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)

    -- Blizzard PlayerFrame stub (UnitFrames plugin hides it)
    local PlayerFrame = CreateFrame("Frame", "PlayerFrame", UIParent)
    PlayerFrame:SetSize(180, 70)
    PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)

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

    env.UnitName      = function(unit) return unit == "player" and "Testchar" or nil end
    env.GetRealmName  = function() return "TestRealm" end
    env.UnitClass     = function() return "Warrior", "WARRIOR", 1 end
    env.UnitLevel     = function() return state.unitLevel or 60 end
    -- The level cap, as the anniversary client reports it. Specs move state.maxPlayerLevel
    -- to exercise the at-cap and below-cap branches of a unit frame.
    env.GetMaxLevelForPlayerExpansion = function() return state.maxPlayerLevel or 60 end
    env.MAX_PLAYER_LEVEL = 60
    env.GetTime       = function() return state.clock or 0 end
    env.InCombatLockdown = function() return state.inCombat == true end

    -- ReloadUI stub for testing (records call rather than actually reloading)
    env.ReloadUI = function()
        state.reloadUICalled = (state.reloadUICalled or 0) + 1
    end

    -- Unit resource APIs for UnitFrames plugin
    env.UnitHealth    = function() return state.unitHealth or 100 end
    env.UnitHealthMax = function() return state.unitHealthMax or 100 end
    env.UnitPower     = function() return state.unitPower or 80 end
    env.UnitPowerMax  = function() return state.unitPowerMax or 100 end
    env.UnitPowerType = function() return state.unitPowerType or 0 end

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
    }
end

return M
