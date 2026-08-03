local sqrt, sin, pi = math.sqrt, math.sin, math.pi

local M = {}

local function easeIn(t)    return t * t end
local function easeOut(t)   return t * (2 - t) end
local function easeInOut(t)
    return t < 0.5 and (2 * t * t) or (-1 + (4 - 2 * t) * t)
end
-- easeOutBack: overshoots past the target then settles back. The cubed term is what
-- pins f(0) to 0; with a squared term the curve starts at 2 and the animation would
-- begin at double its target value.
local function spring(t)
    local s = 1.70158
    local d = t - 1
    return d * d * ((s + 1) * d + s) + 1
end

local easings = {
    linear    = function(t) return t end,
    easeIn    = easeIn,
    easeOut   = easeOut,
    easeInOut = easeInOut,
    spring    = spring,
}

--- Returns an eased value for t in [0,1] using the named easing type.
-- @param t number  Progress in [0, 1]
-- @param easingType string  linear|easeIn|easeOut|easeInOut|spring
-- @return number
function M.Ease(t, easingType)
    local fn = easings[easingType] or easings.linear
    return fn(t)
end

SuuUI.Tween = M
