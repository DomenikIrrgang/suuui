-- SettingsUI/Registry.lua
-- The sections of the settings window. A section is plain data; the window
-- builds it the first time it's shown.
--
--   SuuUI.RegisterSettings({         -- or module:RegisterSettings(def): namespace = the module's id,
--       id = "hello",                --    and the section goes away when the module turns off
--       label = "Hello",
--       category = "Plugins",        -- Frames, Insights, World, General or Plugins
--       order = 100,                 -- within the category
--       namespace = "hello",         -- the settings namespace its rows read and write
--       groups = {
--           { title = "Greeting", description = "…", rows = {
--               { key = "greeting", label = "Greeting", description = "What /suu hello says.", control = "text" },
--           } },
--       },
--       build = function(page) end,  -- instead of (or after) groups: page:AddGroup(groupDef)
--   })
--
-- A row: key (or get/set/isDefault/reset functions), label, description (a
-- string or a function), control ("toggle", "checkbox", "segmented", "select",
-- "slider", "stepper", "text", "button", "custom" or nil), the control's own
-- options (options, multiple, min, max, step, unit, format, width, text,
-- onClick, build), stacked, disabled = function() return disabled, reason end,
-- and combat = true for a change that waits for the end of combat (the window
-- adds "Waits for the end of combat." to the description).

local _, ns = ...

local Registry = {}
ns.SettingsRegistry = Registry

local Events = ns.Events

Registry.CATEGORIES = { "Frames", "Insights", "World", "General", "Plugins" }
local CATEGORY_INDEX = {}
for i, c in ipairs(Registry.CATEGORIES) do CATEGORY_INDEX[c] = i end

local sections, byId = {}, {}

function Registry.Register(def, owner)
    assert(type(def) == "table" and type(def.id) == "string", "SuuUI.RegisterSettings: a section needs an id")
    assert(not byId[def.id], "SuuUI.RegisterSettings: the section id " .. def.id .. " is taken")
    assert(def.groups or def.build, "SuuUI.RegisterSettings: a section needs groups or a build function")
    local s = {
        id = def.id,
        label = def.label or def.id,
        category = CATEGORY_INDEX[def.category] and def.category or "Plugins",
        order = def.order or 100,
        namespace = def.namespace,
        groups = def.groups,
        build = def.build,
        preview = def.preview,
        previewTitle = def.previewTitle,
        previewNote = def.previewNote,
        owner = owner,
    }
    sections[#sections + 1] = s
    byId[s.id] = s
    Events.Emit("SUUUI_SETTINGS_SECTIONS_CHANGED")
    return s
end

function Registry.Unregister(owner)
    local removed = false
    for i = #sections, 1, -1 do
        if sections[i].owner == owner then
            byId[sections[i].id] = nil
            table.remove(sections, i)
            removed = true
        end
    end
    if removed then Events.Emit("SUUUI_SETTINGS_SECTIONS_CHANGED") end
end

function Registry.Get(id)
    return byId[id]
end

-- Sections in display order: by category, then order, then label.
function Registry.List()
    local list = { unpack(sections) }
    table.sort(list, function(a, b)
        local ca, cb = CATEGORY_INDEX[a.category], CATEGORY_INDEX[b.category]
        if ca ~= cb then return ca < cb end
        if a.order ~= b.order then return a.order < b.order end
        return a.label < b.label
    end)
    return list
end
