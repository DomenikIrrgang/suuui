-- Diagnostics/UnlearnProbe.lua
-- "/suu probe unlearn": how Forever unlearns a profession (AbandonSkill is
-- missing: "attempt to call a nil value", found in game). Saved in
-- SuuUIProbe.unlearn on /reload.
--   * every global function and every C_ namespace function whose name has
--     "abandon", "unlearn" or "forget" in it
--   * Blizzard's unlearn popups (UNLEARN_SKILL and its gamepad one), once
--     the professions book has loaded: their fields
--
--   /suu probe unlearn     then /reload

local _, ns = ...

local UP = {}
ns.UnlearnProbe = UP

local WORDS = { "abandon", "unlearn", "forget" }

local function matches(name)
    local low = name:lower()
    for _, w in ipairs(WORDS) do if low:find(w, 1, true) then return true end end
    return false
end

local function fields(t)
    local out = {}
    for k, v in pairs(t) do out[#out + 1] = tostring(k) .. "=" .. type(v) .. (type(v) ~= "function" and type(v) ~= "table" and (":" .. tostring(v)) or "") end
    table.sort(out)
    return out
end

function UP.Sample()
    SuuUIProbe = SuuUIProbe or {}
    local store = { at = date("%Y-%m-%d %H:%M:%S"), globals = {}, namespaces = {}, popups = {} }
    SuuUIProbe.unlearn = store
    for _, addon in ipairs({ "Blizzard_ProfessionsBook", "Blizzard_Professions" }) do
        if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, addon) end
    end
    for k, v in pairs(_G) do
        if type(k) == "string" then
            if type(v) == "function" and matches(k) then
                store.globals[#store.globals + 1] = k
            elseif type(v) == "table" and k:match("^C_") then
                for fk, fv in pairs(v) do
                    if type(fk) == "string" and type(fv) == "function" and matches(fk) then
                        store.namespaces[#store.namespaces + 1] = k .. "." .. fk
                    end
                end
            end
        end
    end
    table.sort(store.globals)
    table.sort(store.namespaces)
    for name, d in pairs(StaticPopupDialogs or {}) do
        if type(name) == "string" and matches(name) and type(d) == "table" then
            store.popups[name] = fields(d)
        end
    end
    return store
end

function UP.Command()
    local store = UP.Sample()
    local popups = 0
    for _ in pairs(store.popups) do popups = popups + 1 end
    ns.Print(("Unlearn probe: %d global and %d namespace functions, %d popups. /reload to save."):format(
        #store.globals, #store.namespaces, popups))
    for _, n in ipairs(store.globals) do ns.Print("  " .. n) end
    for _, n in ipairs(store.namespaces) do ns.Print("  " .. n) end
end
