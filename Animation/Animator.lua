local tremove, tinsert = table.remove, table.insert
local type, pcall = type, pcall

local M = {}
local active   = {}   -- array of running anim handles
local running  = false

local ticker = CreateFrame("Frame")

local setters = {
    alpha = function(f, v) f:SetAlpha(v) end,
    width = function(f, v) f:SetWidth(v) end,
    height= function(f, v) f:SetHeight(v) end,
    scale = function(f, v) f:SetScale(v) end,
    x = function(f, v)
        local point, rel, rp, _, yofs = f:GetPoint(1)
        f:ClearAllPoints()
        f:SetPoint(point or "TOPLEFT", rel, rp, v, yofs or 0)
    end,
    y = function(f, v)
        local point, rel, rp, xofs = f:GetPoint(1)
        f:ClearAllPoints()
        f:SetPoint(point or "TOPLEFT", rel, rp, xofs or 0, v)
    end,
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
                setter(a.target, val)
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
-- @param def table  { target, property, from, to, duration, easing, onDone }
-- @return table  Animation handle
function M:New(def)
    return setmetatable({
        target   = def.target,
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
