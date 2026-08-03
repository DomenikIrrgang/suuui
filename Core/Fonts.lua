local pairs, ipairs, type, pcall = pairs, ipairs, type, pcall
local sort, tinsert = table.sort, table.insert
local lower, gsub, match = string.lower, string.gsub, string.match

local M = {}

--- The face every unresolvable value falls back to. Present in every locale's client.
M.FALLBACK = "Fonts/FRIZQT__.TTF"

-- Names match LibSharedMedia-3.0's for the same files. A font is stored by name rather
-- than by path so the value survives a media addon moving its file, which only works if
-- both registries agree on the name: a theme saved while SharedMedia was installed must
-- still resolve once it is gone, and the reverse.
local CLIENT_FACES = {
    { name = "Friz Quadrata TT", path = "Fonts/FRIZQT__.TTF" },
    { name = "Arial Narrow",     path = "Fonts/ARIALN.TTF" },
    { name = "Morpheus",         path = "Fonts/MORPHEUS.TTF" },
    { name = "Skurri",           path = "Fonts/skurri.TTF" },
}

-- The client's own font globals. Non-enUS clients ship entirely different files under
-- these names, so harvesting them is what keeps the list correct outside enUS.
local LOCALE_GLOBALS = {
    { global = "STANDARD_TEXT_FONT", name = "Standard"   },
    { global = "UNIT_NAME_FONT",     name = "Unit Names" },
    { global = "DAMAGE_TEXT_FONT",   name = "Damage"     },
    { global = "NAMEPLATE_FONT",     name = "Nameplates" },
}

local byName  = {}    -- [name] = { name, path, source }
local byPath  = {}    -- [normalised path] = entry
local order   = nil   -- sorted List() cache, nil when dirty
local scanned = false

-- Fonts registered from outside a scan: a plugin bundling its own face, or a raw path
-- honoured by Path(). A rescan rebuilds the tables from scratch, so these are replayed
-- afterwards or the login refresh would silently drop every plugin's font.
local external = {}

-- WoW accepts either slash and is case-insensitive about font paths, while LSM
-- registers with backslashes and this addon writes forward ones. Both have to key to
-- the same entry or the same face lands in the list twice.
local function normalise(path)
    return lower(gsub(path, "\\", "/"))
end

-- Name for a harvested path that no curated entry covers: the bare filename. Names are
-- the persisted key, so this stays deliberately dumb — a prettifier that changed later
-- would orphan every value saved under the old spelling.
local function nameFromPath(path)
    return match(gsub(path, "\\", "/"), "([^/]+)%.[^%.]*$")
        or match(gsub(path, "\\", "/"), "([^/]+)$")
        or path
end

-- Probing lives in TextMetrics because that is what owns a font string. Absent (this
-- file loads first), assume loadable rather than returning an empty font list.
local function loadable(path)
    if not (SuuUI.TextMetrics and SuuUI.TextMetrics.CanLoadFont) then return true end
    return SuuUI.TextMetrics.CanLoadFont(path)
end

local function scan()
    scanned = true

    for _, face in ipairs(CLIENT_FACES) do
        M:Register(face.name, face.path, "client")
    end

    for _, entry in ipairs(LOCALE_GLOBALS) do
        local path = _G[entry.global]
        if type(path) == "string" then M:Register(entry.name, path, "locale") end
    end

    -- GetFonts returns font *object* names, not paths; the path comes off the object.
    -- This is the only way to see the faces a locale actually shipped, and it is absent
    -- on some clients, hence the guard.
    if type(_G.GetFonts) == "function" then
        local ok, list = pcall(_G.GetFonts)
        if ok and type(list) == "table" then
            for _, entry in ipairs(list) do
                local obj = type(entry) == "table" and entry or _G[entry]
                if type(obj) == "table" and obj.GetFont then
                    local gotPath, path = pcall(obj.GetFont, obj)
                    if gotPath and type(path) == "string" and path ~= "" then
                        M:Register(nameFromPath(path), path, "client")
                    end
                end
            end
        end
    end

    -- LibSharedMedia-3.0 is not a dependency: it is read if the player already has it,
    -- which is how fonts from SharedMedia, ElvUI and friends show up here.
    if type(_G.LibStub) == "function" then
        local ok, lsm = pcall(_G.LibStub, "LibSharedMedia-3.0", true)
        if ok and type(lsm) == "table" and lsm.HashTable then
            local gotHash, hash = pcall(lsm.HashTable, lsm, "font")
            if gotHash and type(hash) == "table" then
                for name, path in pairs(hash) do
                    if type(name) == "string" and type(path) == "string" then
                        M:Register(name, path, "lsm")
                    end
                end
            end
        end
    end

    -- Replayed last: a discovered face wins the name, and a plugin's font is never lost
    -- to a rescan.
    for _, entry in ipairs(external) do
        M:Register(entry.name, entry.path, entry.source)
    end
end

local function ensureScanned()
    if not scanned then scan() end
end

--- Registers a font face. Rejects a path the client cannot load, and keeps the first
--- name registered for a given file so the list holds one entry per face.
-- @param name string  Display name, and the value stored in the theme token
-- @param path string  Font file path
-- @param source string  Optional origin tag: "client"|"locale"|"lsm"|"user"
-- @return bool  Whether the font was added
function M:Register(name, path, source)
    if type(name) ~= "string" or name == "" then return false end
    if type(path) ~= "string" or path == "" then return false end
    local key = normalise(path)
    if byPath[key] or byName[name] then return false end
    if not loadable(path) then return false end

    local entry = { name = name, path = path, source = source or "user" }
    byName[name] = entry
    byPath[key]  = entry
    order = nil
    if entry.source == "user" then
        external[#external + 1] = { name = name, path = path, source = "user" }
    end
    return true
end

--- Returns every known font, sorted by name.
-- @return table  Array of { name, path, source }
function M:List()
    ensureScanned()
    if order then return order end
    order = {}
    for _, entry in pairs(byName) do tinsert(order, entry) end
    sort(order, function(a, b) return lower(a.name) < lower(b.name) end)
    return order
end

--- Returns the font list shaped for a Dropdown's options.
-- @return table  Array of { value = name, label = name }
function M:Options()
    local options = {}
    for _, entry in ipairs(self:List()) do
        tinsert(options, { value = entry.name, label = entry.name })
    end
    return options
end

--- Returns whether a font name is known.
-- @param name string
-- @return bool
function M:Has(name)
    ensureScanned()
    return byName[name] ~= nil
end

--- Returns whether the client can load a font path.
-- @param path string
-- @return bool
function M:Validate(path)
    return type(path) == "string" and path ~= "" and loadable(path) or false
end

--- Resolves a stored token value to a usable font path.
-- Accepts a font name (the stored form) or a raw path (what built-in themes carry, and
-- what a hand-edited SavedVariable may hold). Always returns something loadable, so a
-- font that vanished with its addon degrades to the fallback face instead of rendering
-- nothing at all.
-- @param value string
-- @return string
function M:Path(value)
    if type(value) ~= "string" or value == "" then return self.FALLBACK end
    ensureScanned()
    local named = byName[value]
    if named then return named.path end
    local pathed = byPath[normalise(value)]
    if pathed then return pathed.path end
    -- An unregistered path the client can still load: honour it rather than overriding
    -- a working choice, and remember it so it appears in the list.
    if loadable(value) then
        self:Register(nameFromPath(value), value, "user")
        return value
    end
    return self.FALLBACK
end

--- Adds a font by path alone, naming it after its file, and returns the name.
-- For a face nothing else exposes: WoW cannot list files, so a font dropped into an addon
-- folder that no media addon registered is only reachable by its path. Returns nil when
-- the client cannot load it, which is the caller's cue to say so.
-- @param path string
-- @return string|nil  The name it was registered under
function M:Add(path)
    if not self:Validate(path) then return nil end
    ensureScanned()
    local existing = self:Name(path)
    if existing then return existing end

    local name = nameFromPath(path)
    if self:Register(name, path, "user") then return name end
    -- The filename is already taken by a different face. The full path is unambiguous
    -- and still tells the user which file they picked.
    if self:Register(path, path, "user") then return path end
    return nil
end

--- Returns the display name for a font name or path, or nil when unknown.
-- @param value string
-- @return string|nil
function M:Name(value)
    if type(value) ~= "string" or value == "" then return nil end
    ensureScanned()
    if byName[value] then return value end
    local entry = byPath[normalise(value)]
    return entry and entry.name or nil
end

--- Re-scans every source and fires SUUUI_FONTS_CHANGED when the set changed.
-- Media addons can load after SuuUI, so the login pass calls this to pick up fonts that
-- did not exist when the theme cache was first built.
function M:Refresh()
    local before = byName
    byName, byPath, order = {}, {}, nil
    scan()

    local changed = false
    for name in pairs(byName) do
        if not before[name] then changed = true; break end
    end
    if not changed then
        for name in pairs(before) do
            if not byName[name] then changed = true; break end
        end
    end
    if changed then SuuUI.Events:Emit("SUUUI_FONTS_CHANGED") end
end

SuuUI.Fonts = M
