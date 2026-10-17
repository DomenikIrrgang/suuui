-- Core/Extend.lua
-- Plugins reach into SuuUI's own UI (plan 4.3, asked 2026-10-18): every
-- instance of a kind (unit frames, nameplates, cast bars, action buttons…)
-- is registered here when it's made, so a module can
--   M:Each(kind, fn[, undo])          run fn(object, info) on every one, now
--                                     and on each one made later
--   M:Hook(kind, method, fn)          fn(object, ...) after the method
--   M:Override(kind, method, fn)      fn(object, original, ...) instead of it
-- and everything a module added here goes away when it turns off (undo runs
-- for each instance). Hooks patch each instance: most components copy their
-- methods onto the frame (Mixin), so a patched method table would miss the
-- frames that exist; their events call self:Method(), so the instance's own
-- method is the one that runs. A hook's error is reported under its module's
-- name and SuuUI's own drawing carries on.

local _, ns = ...

local Fault = ns.Fault

local Extend = {}
ns.Extend = Extend

Extend.KINDS = {
    "unitframe", "nameplate", "castbar", "auracontainer", "actionbar", "actionbutton",
    "window", "inventory", "tracker", "cooldowns", "meter", "micromenu", "notification",
}
local known = {}
for _, k in ipairs(Extend.KINDS) do known[k] = true end

local instances = {} -- kind -> { [object] = info } (weak)
local seq = 0        -- the order instances were made in
local extenders = {} -- kind -> { { fn, undo, owner } }
local hooks = {}     -- kind -> method -> { { fn, owner, override } }
local bases = setmetatable({}, { __mode = "k" }) -- object -> method -> { fn, raw }

for _, k in ipairs(Extend.KINDS) do
    instances[k] = setmetatable({}, { __mode = "k" })
    extenders[k], hooks[k] = {}, {}
end

local function check(kind)
    if not known[kind] then error(("SuuUI: unknown kind %q (SuuUI.KINDS lists them)"):format(tostring(kind)), 3) end
end

local function ownerName(owner)
    return type(owner) == "table" and owner.name or tostring(owner)
end

--------------------------------------------------------------------------------
-- Hooks: one wrapper per instance and method, rebuilt when hooks change
--------------------------------------------------------------------------------

-- The method as SuuUI made it: the instance's own function, or the one its
-- metatable gives (then restoring means clearing the instance's field).
local function base(obj, method)
    local b = bases[obj] and bases[obj][method]
    if b then return b end
    local raw = rawget(obj, method)
    b = { fn = raw or obj[method], raw = raw ~= nil }
    bases[obj] = bases[obj] or {}
    bases[obj][method] = b
    return b
end

local function wrap(obj, method, list)
    local b = base(obj, method)
    if type(b.fn) ~= "function" then return end
    if #list == 0 then
        rawset(obj, method, b.raw and b.fn or nil)
        return
    end
    local fn = b.fn
    local posts = {}
    for _, h in ipairs(list) do
        if h.override then
            local inner, user, name = fn, h.fn, ownerName(h.owner)
            fn = function(self, ...)
                -- an override that fails falls back to what it replaced
                local res = { Fault.Call(name, user, self, inner, ...) }
                if res[1] then return unpack(res, 2) end
                return inner(self, ...)
            end
        else
            posts[#posts + 1] = h
        end
    end
    if #posts == 0 then
        rawset(obj, method, fn)
        return
    end
    local inner = fn
    rawset(obj, method, function(self, ...)
        local a, b2, c, d = inner(self, ...)
        for _, h in ipairs(posts) do Fault.Call(ownerName(h.owner), h.fn, self, ...) end
        return a, b2, c, d
    end)
end

local function rewrap(kind, method)
    local list = hooks[kind][method] or {}
    for obj in pairs(instances[kind]) do wrap(obj, method, list) end
end

--------------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------------

-- Each's functions for a new instance run at the end of the frame it was
-- made in, once its module has placed and tagged it.
local queue = {}
local runner = CreateFrame("Frame")
runner:Hide()
runner:SetScript("OnUpdate", function(self)
    self:Hide()
    local list = queue
    queue = {}
    for _, item in ipairs(list) do
        for _, e in ipairs(extenders[item.kind]) do
            Fault.Call(ownerName(e.owner), e.fn, item.object, instances[item.kind][item.object])
        end
    end
end)

function Extend.Add(kind, object, info)
    check(kind)
    if instances[kind][object] then return end
    seq = seq + 1
    info = info or {}
    info.kind, info.seq = kind, seq
    instances[kind][object] = info
    for method, list in pairs(hooks[kind]) do wrap(object, method, list) end
    if #extenders[kind] > 0 then
        queue[#queue + 1] = { kind = kind, object = object }
        runner:Show()
    end
    return info
end

-- More about an instance (its module, its role), set by whoever made it.
function Extend.Tag(object, fields)
    for _, kind in ipairs(Extend.KINDS) do
        local info = instances[kind][object]
        if info then
            for k, v in pairs(fields) do
                if k ~= "kind" and k ~= "seq" then info[k] = v end
            end
        end
    end
end

function Extend.Info(object)
    for _, kind in ipairs(Extend.KINDS) do
        local info = instances[kind][object]
        if info then return info end
    end
end

-- The instances of a kind, in the order they were made.
function Extend.Instances(kind)
    check(kind)
    local out = {}
    for obj, info in pairs(instances[kind]) do out[#out + 1] = { obj, info.seq } end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    for i, o in ipairs(out) do out[i] = o[1] end
    return out
end

--------------------------------------------------------------------------------
-- What modules add
--------------------------------------------------------------------------------

function Extend.Each(kind, fn, undo, owner)
    check(kind)
    assert(type(fn) == "function", "SuuUI Each: a function is required")
    extenders[kind][#extenders[kind] + 1] = { fn = fn, undo = undo, owner = owner }
    for _, obj in ipairs(Extend.Instances(kind)) do
        Fault.Call(ownerName(owner), fn, obj, instances[kind][obj])
    end
end

local function addHook(kind, method, fn, owner, override)
    check(kind)
    assert(type(method) == "string", "SuuUI Hook: a method name is required")
    assert(type(fn) == "function", "SuuUI Hook: a function is required")
    local list = hooks[kind][method] or {}
    hooks[kind][method] = list
    list[#list + 1] = { fn = fn, owner = owner, override = override }
    rewrap(kind, method)
end

function Extend.Hook(kind, method, fn, owner) addHook(kind, method, fn, owner, false) end
function Extend.Override(kind, method, fn, owner) addHook(kind, method, fn, owner, true) end

-- Everything an owner added: its hooks come off every instance, and its
-- undo runs for each instance its Each reached.
function Extend.Unregister(owner)
    for _, kind in ipairs(Extend.KINDS) do
        local kept = {}
        for _, e in ipairs(extenders[kind]) do
            if e.owner == owner then
                if e.undo then
                    for obj, info in pairs(instances[kind]) do Fault.Call(ownerName(owner), e.undo, obj, info) end
                end
            else
                kept[#kept + 1] = e
            end
        end
        extenders[kind] = kept
        for method, list in pairs(hooks[kind]) do
            local rest, changed = {}, false
            for _, h in ipairs(list) do
                if h.owner == owner then changed = true else rest[#rest + 1] = h end
            end
            if changed then
                hooks[kind][method] = rest
                rewrap(kind, method)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Menus and additions
--------------------------------------------------------------------------------

-- SuuUI's own right-click menus by id: fn(menu, context) before one opens,
-- menu = { title, items } (items: { label, onClick, disabled } or
-- { separator = true }; add, insert or remove).
local menus = {} -- id -> { { fn, owner } }

function Extend.ExtendMenu(id, fn, owner)
    assert(type(id) == "string" and type(fn) == "function", "SuuUI ExtendMenu: a menu id and a function")
    menus[id] = menus[id] or {}
    table.insert(menus[id], { fn = fn, owner = owner })
end

-- Called by the menu itself as it opens.
function Extend.ApplyMenu(id, menu, context)
    for _, e in ipairs(id and menus[id] or {}) do
        Fault.Call(ownerName(e.owner), e.fn, menu, context or {})
    end
end

-- Lists modules add to: "micromenu" (buttons), "gamemenu" (entries),
-- "notificationkinds" (popups as cards), "rolepresets" (a module's own
-- settings per role). SUUUI_ADDITIONS_CHANGED(list) when one changes.
local additions = {} -- list -> { { item, owner } }

function Extend.AddTo(list, item, owner)
    additions[list] = additions[list] or {}
    table.insert(additions[list], { item = item, owner = owner })
    ns.Events.Emit("SUUUI_ADDITIONS_CHANGED", list)
end

function Extend.Additions(list)
    local out = {}
    for _, a in ipairs(additions[list] or {}) do out[#out + 1] = a.item end
    return out
end

local unregisterUI = Extend.Unregister
function Extend.Unregister(owner)
    unregisterUI(owner)
    for id, list in pairs(menus) do
        local kept = {}
        for _, e in ipairs(list) do if e.owner ~= owner then kept[#kept + 1] = e end end
        menus[id] = kept
    end
    for name, list in pairs(additions) do
        local kept = {}
        for _, a in ipairs(list) do if a.owner ~= owner then kept[#kept + 1] = a end end
        if #kept ~= #list then
            additions[name] = kept
            ns.Events.Emit("SUUUI_ADDITIONS_CHANGED", name)
        end
    end
end
