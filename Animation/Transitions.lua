-- Value transitions: named strategies describing HOW a displayed scalar approaches its
-- target when that target moves.
--
-- The registry is deliberately not bar-specific. The contract is "a painted value chases
-- a logical value", which is the same shape for a progress fill, a numeric readout
-- counting up, or a needle following a setting. StatusBar is the first consumer.
--
-- A strategy never touches the widget. It receives a context whose Set() is the single
-- write path, so a third-party strategy cannot reach past the component into the layout
-- engine, cannot desync the logical value from the painted one, and cannot skip the
-- pixel-quantisation guard that keeps 40 raid frames from re-laying out 60 times a second.
--
--   Attach(ctx)            optional  the owner adopted this strategy; build scratch here
--   Apply(ctx, from, to)   REQUIRED  the target moved; drive ctx:Set from `from` to `to`
--   Cancel(ctx)            optional  abandon motion in flight, leaving the value put
--   Detach(ctx)            optional  the owner dropped this strategy; release scratch
--
-- Context:
--   ctx.owner      the handle that owns the value (a StatusBar handle)
--   ctx.state      scratch table the strategy owns; allocated once per attach
--   ctx:Set(v)     paint v now — the ONLY write path
--   ctx:Get()      the currently painted value
--   ctx:Target()   the current logical target
--   ctx:Duration() resolved seconds for a full 0..1 sweep
local type, pairs, tsort = type, pairs, table.sort

local M = {}

local registry = {}
local defaultName = "smooth"

local function noop() end

--- Fills the optional hooks so callers never have to nil-check one.
-- Returns a copy, so an inline strategy table handed in by a plugin is never mutated and
-- cannot be mutated later to change a bar's behaviour behind its back.
local function normalise(strategy, name)
    assert(type(strategy) == "table",
        "SuuUI Transitions: strategy must be a table")
    assert(type(strategy.Apply) == "function",
        "SuuUI Transitions: strategy must define Apply(ctx, from, to)")
    return {
        name   = name or strategy.name or "custom",
        Attach = strategy.Attach or noop,
        Apply  = strategy.Apply,
        Cancel = strategy.Cancel or noop,
        Detach = strategy.Detach or noop,
    }
end

--- Registers a named transition strategy.
-- @param name string
-- @param strategy table  { Apply, [Attach], [Cancel], [Detach] }
function M:Register(name, strategy)
    assert(type(name) == "string" and name ~= "",
        "SuuUI Transitions: name must be a non-empty string")
    registry[name] = normalise(strategy, name)
end

--- Returns whether a name is registered.
-- @param name string
-- @return bool
function M:Has(name)
    return registry[name] ~= nil
end

--- Returns the registered strategy for a name, or nil.
-- @param name string
-- @return table|nil
function M:Get(name)
    return registry[name]
end

--- Returns every registered name, sorted.
-- @return table  Array of strings
function M:List()
    local out = {}
    for name in pairs(registry) do out[#out + 1] = name end
    tsort(out)
    return out
end

--- Sets the strategy new owners use when they name none.
-- @param name string
function M:SetDefault(name)
    assert(registry[name], "SuuUI Transitions: unknown strategy '" .. tostring(name) .. "'")
    defaultName = name
end

--- Returns the current default strategy name.
-- @return string
function M:GetDefault()
    return defaultName
end

--- Normalises a transition spec into a usable strategy.
-- Accepts nil (the default), a registered name, or an inline strategy table — the
-- escape hatch that lets a plugin hand one widget a bespoke transition without
-- registering anything or touching the component.
-- An unknown name falls back to the default and logs, rather than erroring: a typo'd
-- name in a plugin should not take a unit frame down with it.
-- @param spec string|table|nil
-- @return table  Normalised strategy
function M:Resolve(spec)
    if spec == nil then
        return registry[defaultName]
    end
    if type(spec) == "table" then
        return normalise(spec)
    end
    local found = registry[spec]
    if found then return found end
    SuuUI.Debug("Transitions: unknown strategy '" .. tostring(spec)
        .. "', using '" .. defaultName .. "'")
    return registry[defaultName]
end

---------------------------------------------------------------------------
-- Built-in strategies
---------------------------------------------------------------------------

--- Builds a strategy backed by a single reusable tween.
-- The animation handle is created once per owner at Attach and re-aimed on every Apply,
-- rather than allocated per update: a health bar in combat retargets many times a second,
-- and a fresh handle plus closure each time would allocate steadily under exactly the
-- load that matters. Retargeting also re-bases `from` to the currently painted value, so
-- an interrupted transition continues from where it is instead of jumping.
-- @param easing string
-- @param durationFor function  (ctx, from, to) -> seconds
-- @return table  Strategy
local function tweened(easing, durationFor)
    return {
        Attach = function(ctx)
            ctx.state.anim = SuuUI.Anim:New({
                target   = ctx.owner,
                property = "value",
                easing   = easing,
                apply    = function(v) ctx:Set(v) end,
            })
        end,
        Apply = function(ctx, from, to)
            local a = ctx.state.anim
            -- No scratch means Attach never ran. Painting straight through is the
            -- honest degradation: a missing animation is better than a stuck bar.
            if not a then ctx:Set(to) return end
            a:Stop()
            a.from     = from
            a.to       = to
            a.duration = durationFor(ctx, from, to)
            a:Play()
        end,
        Cancel = function(ctx)
            if ctx.state.anim then ctx.state.anim:Stop() end
        end,
        Detach = function(ctx)
            if ctx.state.anim then
                ctx.state.anim:Stop()
                ctx.state.anim = nil
            end
        end,
    }
end

-- No transition: the painted value is the target value. This is what the bar did before
-- transitions existed, kept as a named choice rather than a special case — "off" should
-- be selectable, and a spec that wants deterministic geometry names it instead of
-- pumping the animation clock.
M:Register("instant", {
    Apply = function(ctx, _, to) ctx:Set(to) end,
})

-- Fixed-duration ease, regardless of how far the value moved. Reads as smoothing and
-- suits sparse, large changes — a health bar taking a hit. Frequent small updates
-- restart the ease, so the value trails the target continuously; use "rate" for those.
M:Register("smooth", tweened("easeOut", function(ctx)
    return ctx:Duration()
end))

-- Constant speed: the duration is scaled by the distance travelled, so the value moves
-- at a fixed fraction per second and always arrives.
--
-- This exists because a fixed-duration ease has a real failure mode under frequent
-- updates. UNIT_POWER_UPDATE for energy fires faster than a 0.2s ease completes, so each
-- event restarts the tween from a value that never reached the last target: the bar
-- stutters and permanently lags. Scaling the duration by the delta makes a small change
-- take proportionally little time, which converges.
M:Register("rate", tweened("linear", function(ctx, from, to)
    local delta = to - from
    if delta < 0 then delta = -delta end
    return ctx:Duration() * delta
end))

SuuUI.Anim.Transitions = M
