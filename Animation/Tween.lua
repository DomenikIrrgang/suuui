local sqrt, sin, pi = math.sqrt, math.sin, math.pi

local M = {}

local function easeIn(t)    return t * t end
local function easeOut(t)   return t * (2 - t) end
local function easeInOut(t)
    return t < 0.5 and (2 * t * t) or (-1 + (4 - 2 * t) * t)
end
local function spring(t)
    local s = 1.70158
    return t == 1 and 1 or ((t - 1) * ((s + 1) * (t - 1) + s) + 1)
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
