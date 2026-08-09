local M = {}

local function easeIn(t)    return t * t end
local function easeOut(t)   return t * (2 - t) end
local function easeInOut(t)
    return t < 0.5 and (2 * t * t) or (-1 + (4 - 2 * t) * t)
end
-- easeOutBack: overshoots past the target then settles back. The cubed term is what
-- pins f(0) to 0; with a squared term the curve starts at 2 and the animation would
-- begin at double its target value.
local function easeOutBack(t)
    local s = 1.70158
    local d = t - 1
    return d * d * ((s + 1) * d + s) + 1
end

local easings = {
    linear    = function(t) return t end,
    easeIn    = easeIn,
    easeOut   = easeOut,
    easeInOut = easeInOut,
    -- The overshoot curve under both names. "spring" is what the codebase called it
    -- first and stays supported; easeOutBack is what it actually is, and is the name to
    -- reach for in new code. A real spring is a damped oscillator with a settle time
    -- rather than a fixed duration, which this is not.
    easeOutBack = easeOutBack,
    spring      = easeOutBack,
}

-- Unknown names fall back to linear rather than erroring, since Ease runs inside the
-- animation tick and throwing there would take the client's frame with it. Warned once
-- per name: a silent fallback is how a typo'd easing ships looking "nearly right", but
-- warning every tick would bury the log.
local warned = {}

--- Returns an eased value for t in [0,1] using the named easing type.
-- @param t number  Progress in [0, 1]
-- @param easingType string  linear|easeIn|easeOut|easeInOut|easeOutBack|spring
-- @return number
function M.Ease(t, easingType)
    local fn = easings[easingType]
    if not fn then
        if easingType ~= nil and not warned[easingType] then
            warned[easingType] = true
            SuuUI.Debug("Tween: unknown easing '" .. tostring(easingType) .. "', using linear")
        end
        fn = easings.linear
    end
    return fn(t)
end

--- Returns whether an easing name is registered.
-- @param name string
-- @return bool
function M.Has(name)
    return easings[name] ~= nil
end

SuuUI.Tween = M
