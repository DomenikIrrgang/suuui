-- Diagnostics/SpellbookProbe.lua
-- "/suu probe spellbook": what Forever's spellbook data looks like, for
-- SuuUI's own Spellbook page (step 3.2b). Saved in SuuUIProbe.spellbook on
-- /reload.
--   * C_SpellBook's functions, the item and bank enums
--   * every skill line (school) and its items as the game gives them: type,
--     spell, name, rank text, icon, passive, off spec, level learned, known;
--     plus every C_SpellBook / C_Spell function that sounds like training or
--     cost, called on each item
--   * Blizzard's spellbook page, three levels deep (how it shows unlearned
--     and trainable spells)
--
--   /suu probe spellbook          with the spellbook open (run it on a
--                                 couple of schools), then /reload
--   /suu probe spellbook pickup   SuuUI's code picks up your first spell
--                                 (as a drag would) and puts it back: may
--                                 an addon? then /reload
--   /suu probe spellbook cast     from now until /reload, every click on a
--                                 spell in SuuUI's page (down and up, the
--                                 button's attributes, combat, protected,
--                                 what the mouse is on), blocked actions,
--                                 cast events and error messages: click a
--                                 spell out of combat, then in combat, then
--                                 /reload. Saved in SuuUIProbe.castbook

local _, ns = ...

local SP = {}
ns.SpellbookProbe = SP

local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "table" then
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. (isSecret(x) and "secret" or (type(x) == "table" and "table" or tostring(x)))
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error: " .. tostring(res[2]):sub(1, 120) end
    local parts = {}
    for i = 2, math.max(2, select("#", unpack(res))) do parts[#parts + 1] = show(res[i]) end
    return table.concat(parts, " | ")
end

local function namesIn(t)
    local out = {}
    if type(t) ~= "table" then return { "missing" } end
    for k, v in pairs(t) do if type(k) == "string" and type(v) == "function" then out[#out + 1] = k end end
    table.sort(out)
    return out
end

local function enumList(e)
    local out = {}
    if type(e) ~= "table" then return { "missing" } end
    for k, v in pairs(e) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(out)
    return out
end

-- Functions whose names sound like training, cost or ranks.
local function trainingFunctions()
    local out = {}
    for _, ns2 in ipairs({ "C_SpellBook", "C_Spell", "C_Trainer", "C_SpellTrainer" }) do
        local t = _G[ns2]
        if type(t) == "table" then
            for k, v in pairs(t) do
                local l = k:lower()
                -- only what reads (Get/Is/Has/Can/Should): nothing that buys or learns
                local reads = k:match("^Get") or k:match("^Is") or k:match("^Has") or k:match("^Can") or k:match("^Should")
                if type(v) == "function" and reads and (l:find("train") or l:find("cost") or l:find("rank") or l:find("future")
                    or l:find("learn") or l:find("level") or l:find("unlearned") or l:find("available")) then
                    out[#out + 1] = ns2 .. "." .. k
                end
            end
        end
    end
    -- global names only listed (never called)
    local globals = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "function" and (k:find("Trainer") or k:find("SpellRank")) then globals[#globals + 1] = k end
    end
    table.sort(globals)
    out.globals = globals
    table.sort(out)
    return out
end

local function sampleItems(store)
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local lines = {}
    local numLines = C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
    local extra = store.trainingFunctions or {}
    for line = 1, numLines do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        local l = { info = show(info), items = {} }
        if info then
            for i = info.itemIndexOffset + 1, math.min(info.itemIndexOffset + info.numSpellBookItems, info.itemIndexOffset + 40) do
                local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                local spellID = item and item.spellID
                local e = { slot = i, info = show(item) }
                e.name = call(C_SpellBook.GetSpellBookItemName, i, bank)
                e.levelLearned = call(C_SpellBook.GetSpellBookItemLevelLearned, i, bank)
                e.passive = call(C_SpellBook.IsSpellBookItemPassive, i, bank)
                e.offSpec = call(C_SpellBook.IsSpellBookItemOffSpec, i, bank)
                e.texture = call(C_SpellBook.GetSpellBookItemTexture, i, bank)
                if spellID and not isSecret(spellID) then
                    e.subtext = call(C_Spell.GetSpellSubtext, spellID)
                    e.known = call(IsSpellKnown, spellID)
                    e.playerSpell = call(IsPlayerSpell, spellID)
                    e.levelLearnedSpell = call(C_Spell.GetSpellLevelLearned, spellID)
                end
                -- whatever sounds like training: called with (slot, bank) and with the spell
                local tried = {}
                for _, path in ipairs(extra) do
                    local ns2, fn = path:match("^(.-)%.(.+)$")
                    local f = ns2 and _G[ns2] and _G[ns2][fn]
                    if f then
                        tried[#tried + 1] = path .. "(slot)=" .. call(f, i, bank):sub(1, 80)
                        if spellID then tried[#tried + 1] = path .. "(spell)=" .. call(f, spellID):sub(1, 80) end
                    end
                end
                e.tried = tried
                l.items[#l.items + 1] = e
            end
        end
        lines[#lines + 1] = l
    end
    return lines
end

-- Blizzard's spellbook page, three levels deep: keys, types, sizes, texts.
local function pageTree(f, depth, out, prefix)
    if not f or depth > 3 or #out > 400 then return end
    for _, c in ipairs({ f:GetChildren() }) do
        local ok, line = pcall(function()
            local key
            for k, v in pairs(f) do if v == c and type(k) == "string" then key = k end end
            local w, h = c:GetSize()
            return ("%s%s %s %dx%d shown=%s"):format(prefix, c:GetObjectType(), key or c:GetName() or "-", w or 0, h or 0, tostring(c:IsShown()))
        end)
        if ok and line then out[#out + 1] = line end
        for _, r in ipairs({ c:GetRegions() }) do
            if r:GetObjectType() == "FontString" then
                local t = r:GetText()
                if t and not isSecret(t) and t ~= "" then out[#out + 1] = prefix .. "  text: " .. t:sub(1, 50) end
            end
        end
        pageTree(c, depth + 1, out, prefix .. "  ")
    end
end

function SP.Sample()
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.spellbook or {}
    SuuUIProbe.spellbook = store
    store.at = date("%Y-%m-%d %H:%M:%S")
    store.C_SpellBook = namesIn(C_SpellBook)
    store.itemTypes = enumList(Enum.SpellBookItemType)
    store.banks = enumList(Enum.SpellBookSpellBank)
    store.trainingFunctions = trainingFunctions()
    store.trainerGlobals = store.trainingFunctions.globals
    store.trainingFunctions.globals = nil
    store.lines = sampleItems(store)
    local f = _G.PlayerSpellsFrame
    local page = f and (f.SpellBookFrame or f.SpellbookFrame)
    if page and page:IsVisible() then
        local out = {}
        pageTree(page, 0, out, "")
        store.page = out
        store.pageAt = store.at
    end
    return store
end

-- SuuUI's code picks up the first learned spell and puts it back.
function SP.Pickup()
    if InCombatLockdown() then ns.Print("Spellbook probe: out of combat, please.") return end
    SuuUIProbe = SuuUIProbe or {}
    local store = SuuUIProbe.spellbook or {}
    SuuUIProbe.spellbook = store
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local blocked = {}
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_ACTION_BLOCKED")
    f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, e, a, b) blocked[#blocked + 1] = e .. " " .. show(a) .. " " .. show(b) end)
    local slot
    local info = C_SpellBook.GetSpellBookSkillLineInfo(2) or C_SpellBook.GetSpellBookSkillLineInfo(1)
    if info then
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
            if item and item.itemType == (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) and not item.isPassive then slot = i break end
        end
    end
    local r = { at = date("%H:%M:%S"), slot = show(slot) }
    if slot then
        r.pickup = call(C_SpellBook.PickupSpellBookItem, slot, bank)
        r.cursor = call(GetCursorInfo)
        ClearCursor()
    end
    C_Timer.After(0.5, function()
        r.blocked = blocked
        f:UnregisterAllEvents()
        ns.Print("Spellbook probe: pickup " .. tostring(r.pickup) .. ", cursor " .. tostring(r.cursor) .. (#blocked > 0 and (", BLOCKED: " .. blocked[1]) or ", nothing blocked") .. ". /reload to save.")
    end)
    store.pickupTest = r
end

function SP.Cast()
    local m = ns.Modules.Get("spellbook")
    local book = m and m.book
    if not book then ns.Print("Spellbook probe: open the Spellbook once first.") return end
    SuuUIProbe = SuuUIProbe or {}
    local log = {}
    SuuUIProbe.castbook = { at = date("%H:%M:%S"), keyDownCVar = show(GetCVar and GetCVar("ActionButtonUseKeyDown")), log = log }
    local t0 = GetTime()
    local function note(s)
        if #log < 300 then log[#log + 1] = ("%.2f %s %s"):format(GetTime() - t0, InCombatLockdown() and "[combat]" or "[calm]", s) end
    end
    SP.castNote = note
    if SP.castHooked then note("re-armed") ns.Print("Spellbook probe: recording again. Click spells, then /reload.") return end
    SP.castHooked = true
    local function foci()
        local out = {}
        for _, f in ipairs(GetMouseFoci and GetMouseFoci() or {}) do
            local ok, n = pcall(function() return f:GetDebugName() end)
            out[#out + 1] = ok and n or tostring(f)
        end
        return table.concat(out, ", ")
    end
    local function describe(b)
        local ok1, prot = pcall(b.IsProtected, b)
        return ("type=%s spell=%s protected=%s shown=%s visible=%s mouse=%s alpha=%.2f foci=[%s]"):format(
            show(b:GetAttribute("type")), show(b:GetAttribute("spell")), ok1 and show(prot) or "?",
            show(b:IsShown()), show(b:IsVisible()), show(b:IsMouseEnabled()), b:GetEffectiveAlpha() or -1, foci())
    end
    local hooked = {}
    local function hookCells()
        for i, c in ipairs(book.cells or {}) do
            local b = c.button
            if b and not hooked[b] then
                hooked[b] = true
                b:HookScript("OnMouseDown", function(_, btn) SP.castNote(("cell %d mousedown %s %s"):format(i, tostring(btn), describe(b))) end)
                b:HookScript("PreClick", function(_, btn, down) SP.castNote(("cell %d preclick %s down=%s %s"):format(i, tostring(btn), tostring(down), describe(b))) end)
                b:HookScript("PostClick", function(_, btn, down) SP.castNote(("cell %d postclick %s down=%s"):format(i, tostring(btn), tostring(down))) end)
            end
        end
    end
    hookCells()
    hooksecurefunc(book, "SetSpells", hookCells)
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UI_ERROR_MESSAGE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED" }) do
        pcall(f.RegisterUnitEvent, f, e, "player")
    end
    f:SetScript("OnEvent", function(_, e, a, b, c, d)
        SP.castNote(("%s %s %s %s %s"):format(e, show(a), show(b), show(c), show(d)))
    end)
    note("armed " .. #(book.cells or {}) .. " cells")
    ns.Print("Spellbook probe: recording clicks. Click a spell out of combat, then in combat, then /reload.")
end

function SP.Command(arg)
    if arg == "pickup" then return SP.Pickup() end
    if arg == "cast" then return SP.Cast() end
    local store = SP.Sample()
    ns.Print(("Spellbook probe: %d schools sampled%s. Run it on another school too, then /reload."):format(#store.lines,
        store.page and ", Blizzard's page read" or " (open the spellbook to read Blizzard's page)"))
end
