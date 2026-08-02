local tremove, tinsert = table.remove, table.insert
local type, pcall = type, pcall

local M = {}
local active   = {}   -- array of running anim handles
local running  = false

local ticker = CreateFrame("Frame")

-- Position is animated through the layout engine, never by touching SetPoint.
-- "x"/"y" require def.container (an anchor-layout container holding the target)
-- plus def.anchor, the base descriptor whose offset is being driven.
local function animateAnchor(a, axis, v)
    if not a.container then
        SuuUI.Debug("Anim: property '" .. axis .. "' requires a container")
        return
    end
    local base = a.anchor or {}
    a.container:SetChildAnchor(a.target, {
        point         = base.point,
        relativeTo    = base.relativeTo,
        relativePoint = base.relativePoint,
        width         = base.width,
        height        = base.height,
        x             = (axis == "x") and v or (base.x or 0),
        y             = (axis == "y") and v or (base.y or 0),
    })
end

local setters = {
    alpha = function(_, v, a) a.target:SetAlpha(v) end,
    width = function(_, v, a) a.target:SetWidth(v) end,
    height= function(_, v, a) a.target:SetHeight(v) end,
    scale = function(_, v, a) a.target:SetScale(v) end,
    x     = function(_, v, a) animateAnchor(a, "x", v) end,
    y     = function(_, v, a) animateAnchor(a, "y", v) end,
}

local function tick(_, dt)
    for i = #active, 1, -1 do
        local a = active[i]
        if a._playing then
            a._elapsed = a._elapsed + dt
            local t = a._elapsed / a.duration
            if t >= 1 then t = 1 end
            local eased = SuuUI.Tween.Ease(t, a.easing)
            local val   = a.from + (a.to - a.from) * eased
            local setter = setters[a.property]
            if setter and a.target and a.target.IsShown then
                setter(a.target, val, a)
            end
            if t >= 1 then
                a._playing = false
                tremove(active, i)
                if a.onDone then
                    local ok, err = pcall(a.onDone)
                    if not ok then SuuUI.Debug("Anim onDone error: " .. tostring(err)) end
                end
            end
        end
    end
    if #active == 0 then
        ticker:SetScript("OnUpdate", nil)
        running = false
    end
end

local function startTicker()
    if not running then
        running = true
        ticker:SetScript("OnUpdate", tick)
    end
end

local AnimMeta = {}
AnimMeta.__index = AnimMeta

--- Starts playback of this animation.
function AnimMeta:Play()
    if self._playing then return end
    self._elapsed = 0
    self._playing = true
    tinsert(active, self)
    startTicker()
end

--- Stops playback without firing onDone.
function AnimMeta:Stop()
    self._playing = false
    for i = #active, 1, -1 do
        if active[i] == self then tremove(active, i) break end
    end
end

--- Reverses from and to, then plays.
function AnimMeta:Reverse()
    self.from, self.to = self.to, self.from
    self:Play()
end

--- Returns whether this animation is currently playing.
-- @return bool
function AnimMeta:IsPlaying()
    return self._playing == true
end

--- Creates a new animation handle (does not auto-play).
-- @param def table  { target, property, from, to, duration, easing, onDone, container, anchor }
--   property: "alpha"|"width"|"height"|"scale"|"x"|"y"
--   container + anchor: required for "x"/"y" — position is driven through the
--   layout engine via container:SetChildAnchor, never through SetPoint.
-- @return table  Animation handle
function M:New(def)
    return setmetatable({
        target    = def.target,
        container = def.container,
        anchor    = def.anchor,
        property = def.property or "alpha",
        from     = def.from or 0,
        to       = def.to   or 1,
        duration = def.duration or 0.25,
        easing   = def.easing or "easeOut",
        onDone   = def.onDone,
        _elapsed = 0,
        _playing = false,
    }, AnimMeta)
end

--- Plays a set of animations simultaneously.
-- @param anims table  Array of animation handles
function M:Parallel(anims)
    for _, a in pairs(anims) do a:Play() end
end

--- Plays animations one after another.
-- @param anims table  Array of animation handles
function M:Sequence(anims)
    local function chain(i)
        if i > #anims then return end
        local a = anims[i]
        local orig = a.onDone
        a.onDone = function()
            if orig then orig() end
            chain(i + 1)
        end
        a:Play()
    end
    chain(1)
end

SuuUI.Anim = M
