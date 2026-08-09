local tinsert = table.insert
local pcall, ipairs, pairs, type = pcall, ipairs, pairs, type

local M = {}

-- Active animation handles. Entries are never removed mid-tick: a finished or cancelled
-- animation is flagged dead and compacted out after the pass. Removing during dispatch
-- shifts unvisited indices, which silently skipped an animation for a frame whenever an
-- onDone stopped one of its siblings — the same hazard EventBus:Emit solved with a
-- snapshot. A dead flag solves it here without allocating a snapshot table per tick.
local active  = {}
local running = false
local ticking = false

local ticker = CreateFrame("Frame")

-- Properties whose value is not written to a frame, so the visibility guard does not
-- apply. "value" drives an arbitrary scalar through def.apply — a StatusBar's fill
-- fraction, a numeric readout counting up — on the one shared ticker rather than each
-- consumer registering its own OnUpdate.
local FRAMELESS = { value = true }

-- Position is animated through the layout engine, never by touching SetPoint.
-- "x"/"y" require def.container (an anchor-layout container holding the target)
-- plus def.anchor, the base descriptor whose offset is being driven.
local function animateAnchor(a, axis, v)
    if not a.container then
        SuuUI.Debug("Anim: property '" .. axis .. "' requires a container")
        return
    end
    local base = a.anchor or {}
    -- Reused scratch descriptor. A fresh table per tick would allocate inside an
    -- OnUpdate handler, which the performance rules forbid outright. The table is
    -- private to this handle, and AnchorLayout reads it synchronously during
    -- SetChildAnchor, so there is no window in which a mutation can be observed.
    --
    -- Copied field-by-field via pairs rather than by an explicit field list: the list
    -- would silently drop any descriptor field AnchorLayout gains later, and an
    -- animated child would lose it for the duration of every tween.
    local d = a._anchorScratch
    for k in pairs(d) do d[k] = nil end
    for k, val in pairs(base) do d[k] = val end
    d.x = (axis == "x") and v or (base.x or 0)
    d.y = (axis == "y") and v or (base.y or 0)
    a.container:SetChildAnchor(a.target, d)
end

local setters = {
    alpha = function(_, v, a) a.target:SetAlpha(v) end,
    width = function(_, v, a) a.target:SetWidth(v) end,
    height= function(_, v, a) a.target:SetHeight(v) end,
    scale = function(_, v, a) a.target:SetScale(v) end,
    x     = function(_, v, a) animateAnchor(a, "x", v) end,
    y     = function(_, v, a) animateAnchor(a, "y", v) end,
    value = function(_, v, a) a.apply(v, a) end,
}

--- Writes one animated value to its destination.
-- @param a table    Animation handle
-- @param v number   The eased value
-- @param final bool Whether this is the animation's last write
local function applyValue(a, v, final)
    local setter = setters[a.property]
    if not setter then return end
    if not FRAMELESS[a.property] then
        local t = a.target
        -- Call IsShown, do not merely check that it exists: a method reference is
        -- always truthy, so testing `a.target.IsShown` guarded nothing and let the
        -- animator keep driving frames that were hidden or already torn down.
        if not (t and t.IsShown) then return end
        -- Intermediate writes are skipped while hidden — nothing can observe them. The
        -- FINAL write always lands, because skipping it strands the frame at whatever
        -- partial value it held when it was hidden. That is not cosmetic: a Button
        -- hidden mid-ScalePop kept a 1.08 scale forever, turning a transient off-grid
        -- scale into a permanent one and blurring every glyph in the frame.
        if not final and not t:IsShown() then return end
    end
    setter(a.target, v, a)
end

local function markDead(a)
    a._playing = false
    a._dead    = true
    a._finish  = nil
end

--- Compacts the dead entries out of `active` in place, without allocating.
local function compact()
    local n, w = #active, 0
    for r = 1, n do
        local a = active[r]
        if a._dead then
            a._dead   = nil
            a._queued = false
        else
            w = w + 1
            active[w] = a
        end
    end
    for i = n, w + 1, -1 do active[i] = nil end
end

local function tick(_, dt)
    ticking = true
    -- Forward iteration is safe because nothing is removed during the pass. A handle
    -- started from inside an onDone is appended past `n` and first runs next frame.
    local n = #active
    for i = 1, n do
        local a = active[i]
        if a._playing and not a._dead then
            a._elapsed = a._elapsed + dt
            -- A zero (or negative) duration is an instant jump to the end value, not a
            -- division: dividing here yields inf, and inf through an overshooting ease
            -- produces a NaN that the client then rejects on every setter.
            local t
            if not a.duration or a.duration <= 0 then
                t = 1
            else
                t = a._elapsed / a.duration
                if t >= 1 then t = 1 end
            end
            local final = t >= 1
            -- The last write is the target value itself, not the eased computation.
            -- `from + (to - from) * 1.0` can land a ULP away from `to` in floating point,
            -- which leaves a fill that never compares equal to its target (so it never
            -- reports settled) and a ScalePop that returns to 0.9999999 instead of 1.
            local val
            if final then
                val = a.to
            else
                val = a.from + (a.to - a.from) * SuuUI.Tween.Ease(t, a.easing)
            end
            applyValue(a, val, final)
            if final then
                -- Captured before markDead clears it, and cleared before the callbacks
                -- run so a handle replayed from inside onDone starts clean.
                local fin = a._finish
                markDead(a)
                if a.onDone then
                    local ok, err = pcall(a.onDone)
                    if not ok then SuuUI.Debug("Anim onDone error: " .. tostring(err)) end
                end
                if fin then
                    local ok, err = pcall(fin)
                    if not ok then SuuUI.Debug("Anim chain error: " .. tostring(err)) end
                end
            end
        end
    end
    ticking = false
    compact()
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

--- Flags any other running animation writing the same property of the same target.
-- The latest animation for a (target, property) pair wins. Two live tweens on one
-- property fight every tick and settle by array order, which is how a rapid
-- hover-on/hover-off produced a frame stuck at a half-faded alpha: FadeIn and FadeOut
-- were both writing alpha, and which one landed last was undefined.
local function preempt(self)
    for i = 1, #active do
        local a = active[i]
        if a ~= self and not a._dead and a._playing
           and a.target == self.target and a.property == self.property then
            markDead(a)
        end
    end
end

local AnimMeta = {}
AnimMeta.__index = AnimMeta

--- Starts playback of this animation, pre-empting any other animation on the same
--- target and property.
function AnimMeta:Play()
    if self._playing and not self._dead then return end
    self._elapsed = 0
    self._dead    = nil
    self._playing = true
    preempt(self)
    -- A handle flagged dead but not yet compacted is still in the array, so reviving it
    -- must not insert a second copy.
    if not self._queued then
        self._queued = true
        tinsert(active, self)
    end
    startTicker()
end

--- Stops playback without firing onDone, and drops any queued chain continuation.
function AnimMeta:Stop()
    if not self._queued and not self._playing then return end
    markDead(self)
    if not ticking then compact() end
end

--- Swaps from and to. Reverses in place when already playing, otherwise plays.
-- Mirroring the elapsed time is what makes an in-flight reverse continue from where the
-- value currently is. Swapping alone left the clock untouched, so the next tick
-- evaluated the new curve at the old progress and the value teleported to the mirrored
-- point before travelling to the value it had started from.
function AnimMeta:Reverse()
    self.from, self.to = self.to, self.from
    if self._playing and not self._dead then
        local d = self.duration or 0
        if d > 0 then
            local e = self._elapsed
            if e > d then e = d end
            self._elapsed = d - e
        end
        return
    end
    self:Play()
end

--- Returns whether this animation is currently playing.
-- @return bool
function AnimMeta:IsPlaying()
    return self._playing == true and not self._dead
end

--- Creates a new animation handle (does not auto-play).
-- @param def table  { target, property, from, to, duration, easing, onDone,
--                     container, anchor, apply }
--   property: "alpha"|"width"|"height"|"scale"|"x"|"y"|"value"
--   container + anchor: required for "x"/"y" — position is driven through the
--   layout engine via container:SetChildAnchor, never through SetPoint.
--   apply: required for "value" — receives (v, handle) and writes the scalar itself.
-- @return table  Animation handle
function M:New(def)
    local property = def.property or "alpha"
    if property == "value" and type(def.apply) ~= "function" then
        SuuUI.Debug("Anim: property 'value' requires an apply function")
    end
    return setmetatable({
        target    = def.target,
        container = def.container,
        anchor    = def.anchor,
        apply     = def.apply,
        property  = property,
        from      = def.from or 0,
        to        = def.to   or 1,
        -- Durations are design language, so the default is the token rather than a
        -- literal that no theme controls. The fallback covers only a call made before a
        -- theme is active; animMid ships in every built-in theme.
        duration  = def.duration or SuuUI.Theme:GetToken("animMid") or 0.22,
        easing    = def.easing or "easeOut",
        onDone    = def.onDone,
        _elapsed  = 0,
        _playing  = false,
        _anchorScratch = {},
    }, AnimMeta)
end

--- Cancels every running animation on a target, without firing their onDone.
-- Call this before destroying or recycling a frame: an animation left running holds a
-- reference to the frame and keeps writing to it, which on a pooled frame means the next
-- owner inherits a tween that is still fading the previous one out.
-- @param target frame
-- @return number  How many animations were stopped
function M:CancelAll(target)
    if not target then return 0 end
    local stopped = 0
    for i = 1, #active do
        local a = active[i]
        if a.target == target and not a._dead and a._playing then
            markDead(a)
            stopped = stopped + 1
        end
    end
    if not ticking then compact() end
    return stopped
end

--- Returns how many animations are running, optionally for one target.
-- Exists so a spec can assert that teardown left nothing running: an animation leaked
-- past Destroy keeps writing into freed state and is invisible until it does damage.
-- Mirrors Settings:GetWatcherCount.
-- @param target frame|table|nil
-- @return number
function M:GetActiveCount(target)
    local n = 0
    for i = 1, #active do
        local a = active[i]
        if a._playing and not a._dead and (target == nil or a.target == target) then
            n = n + 1
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Groups
--
-- Parallel and Sequence return a handle so a composite animation can be stopped and
-- observed as one thing. Both start immediately, which is what ScalePop and the existing
-- callers rely on; Play() on the handle restarts them.
---------------------------------------------------------------------------
local GroupMeta = {}
GroupMeta.__index = GroupMeta

--- Returns whether any animation in the group is still running.
-- @return bool
function GroupMeta:IsPlaying()
    for i = 1, #self._anims do
        if self._anims[i]:IsPlaying() then return true end
    end
    return false
end

--- Stops every animation in the group, and any pending sequence continuation.
function GroupMeta:Stop()
    for i = 1, #self._anims do self._anims[i]:Stop() end
end

--- Restarts the group from the beginning.
function GroupMeta:Play()
    self._start()
end

local function newGroup(anims)
    return setmetatable({ _anims = anims }, GroupMeta)
end

--- Plays a set of animations simultaneously.
-- @param anims table  Array of animation handles
-- @return table  Group handle
function M:Parallel(anims)
    local group = newGroup(anims)
    group._start = function()
        local remaining = 0
        for _ in ipairs(anims) do remaining = remaining + 1 end
        for _, a in ipairs(anims) do
            a._finish = function()
                remaining = remaining - 1
                if remaining <= 0 and group.onDone then
                    local ok, err = pcall(group.onDone)
                    if not ok then SuuUI.Debug("Anim group onDone error: " .. tostring(err)) end
                end
            end
        end
        for _, a in ipairs(anims) do a:Play() end
    end
    group._start()
    return group
end

--- Plays animations one after another.
-- The continuation lives on an internal _finish field, never on the caller's onDone.
-- Wrapping onDone meant an aborted sequence left the wrapper installed — the completion
-- path restored it, the Stop and CancelAll paths did not — so the handle silently
-- dragged the dead chain into its next standalone Play.
-- @param anims table  Array of animation handles
-- @return table  Group handle
function M:Sequence(anims)
    local group = newGroup(anims)
    local function step(i)
        local a = anims[i]
        if not a then
            if group.onDone then
                local ok, err = pcall(group.onDone)
                if not ok then SuuUI.Debug("Anim group onDone error: " .. tostring(err)) end
            end
            return
        end
        a._finish = function() step(i + 1) end
        a:Play()
    end
    group._start = function() step(1) end
    group._start()
    return group
end

SuuUI.Anim = M
