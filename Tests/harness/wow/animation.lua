-- AnimationGroups. Nothing in SuuUI uses them -- the addon runs its own shared-OnUpdate
-- animator by design (Animation/Animator.lua) -- so this exists for EMBEDDED THIRD-PARTY
-- code, which does: LibDBIcon builds a fade-out group for its minimap button at register
-- time and the load dies without CreateAnimationGroup.
--
-- Deliberately a CONFIGURATION RECORDER, not a runner: it stores what was asked for and
-- tracks whether the group is playing, and it does NOT tick over time. H.tick drives
-- SuuUI's own animator, not this, so a spec must never read a mid-flight value here and
-- believe it. The one real effect modelled is the client's SetToFinalAlpha contract: on
-- Finish, an Alpha animation's end value is left on the target instead of reverting.
local M = {}

local AnimMeta = {}
AnimMeta.__index = AnimMeta

function AnimMeta:SetDuration(d)     self._duration = d end
function AnimMeta:GetDuration()      return self._duration or 0 end
function AnimMeta:SetStartDelay(d)   self._startDelay = d end
function AnimMeta:GetStartDelay()    return self._startDelay or 0 end
function AnimMeta:SetOrder(o)        self._order = o end
function AnimMeta:GetOrder()         return self._order or 1 end
function AnimMeta:SetSmoothing(s)    self._smoothing = s end
function AnimMeta:GetSmoothing()     return self._smoothing end
function AnimMeta:SetFromAlpha(a)    self._fromAlpha = a end
function AnimMeta:GetFromAlpha()     return self._fromAlpha end
function AnimMeta:SetToAlpha(a)      self._toAlpha = a end
function AnimMeta:GetToAlpha()       return self._toAlpha end
function AnimMeta:SetChange(c)       self._change = c end
function AnimMeta:SetDegrees(d)      self._degrees = d end
function AnimMeta:SetScale(x, y)     self._scaleX, self._scaleY = x, y end
function AnimMeta:SetOffset(x, y)    self._offsetX, self._offsetY = x, y end
function AnimMeta:GetObjectType()    return self._kind end
function AnimMeta:IsObjectType(t)    return self._kind == t end

local GroupMeta = {}
GroupMeta.__index = GroupMeta

--- Adds an animation to the group.
-- @param kind string  "Alpha" | "Scale" | "Translation" | "Rotation" | "Path"
-- @return table
function GroupMeta:CreateAnimation(kind)
    local a = setmetatable({ _kind = kind or "Alpha", _group = self }, AnimMeta)
    self._anims[#self._anims + 1] = a
    return a
end

function GroupMeta:GetAnimations()  return table.unpack(self._anims) end
function GroupMeta:GetParent()      return self._parent end
function GroupMeta:GetObjectType()  return "AnimationGroup" end
function GroupMeta:IsObjectType(t)  return t == "AnimationGroup" end

function GroupMeta:SetLooping(mode) self._looping = mode end
function GroupMeta:GetLooping()     return self._looping end

--- The client's contract: when true, the target keeps the final alpha once the group
--- finishes rather than snapping back to what it had before.
function GroupMeta:SetToFinalAlpha(on) self._toFinalAlpha = on and true or false end
function GroupMeta:IsSetToFinalAlpha()  return self._toFinalAlpha == true end

function GroupMeta:Play()      self._playing = true  ; self:_fire("OnPlay") end
function GroupMeta:Pause()     self._playing = false ; self:_fire("OnPause") end
function GroupMeta:Stop()      self._playing = false ; self:_fire("OnStop") end
function GroupMeta:IsPlaying() return self._playing == true end
function GroupMeta:IsDone()    return self._playing ~= true end
function GroupMeta:GetProgress() return self._playing and 0 or 1 end
function GroupMeta:GetDuration()
    local total = 0
    for _, a in ipairs(self._anims) do
        total = math.max(total, (a:GetStartDelay() or 0) + (a:GetDuration() or 0))
    end
    return total
end

--- Jumps the group to its end. Applies the SetToFinalAlpha contract, which is the only
--- observable effect this model reproduces.
function GroupMeta:Finish()
    self._playing = false
    if self._toFinalAlpha and self._parent then
        for _, a in ipairs(self._anims) do
            if a._kind == "Alpha" and a._toAlpha ~= nil then
                self._parent:SetAlpha(a._toAlpha)
            end
        end
    end
    self:_fire("OnFinished")
end

local SCRIPTS = {
    OnPlay = true, OnPause = true, OnStop = true, OnFinished = true,
    OnUpdate = true, OnLoop = true,
}

function GroupMeta:SetScript(name, fn)
    assert(SCRIPTS[name], "harness: AnimationGroup has no script " .. tostring(name))
    self._scripts[name] = fn
end

function GroupMeta:GetScript(name) return self._scripts[name] end
function GroupMeta:HasScript(name) return SCRIPTS[name] == true end

function GroupMeta:HookScript(name, fn)
    local prev = self._scripts[name]
    self._scripts[name] = function(...)
        if prev then prev(...) end
        return fn(...)
    end
end

function GroupMeta:_fire(name, ...)
    local fn = self._scripts[name]
    if fn then return fn(self, ...) end
end

--- Creates an animation group owned by a frame.
-- @param parent table   The frame calling CreateAnimationGroup
-- @param name string    Optional global name, as the client accepts
-- @return table
function M.newGroup(parent, name)
    return setmetatable({
        _parent  = parent,
        _name    = name,
        _anims   = {},
        _scripts = {},
        _playing = false,
    }, GroupMeta)
end

M.GroupMeta = GroupMeta
M.AnimMeta  = AnimMeta

return M
