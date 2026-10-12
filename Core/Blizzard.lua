-- Core/Blizzard.lua
-- Standing Blizzard's own frames down when a SuuUI module replaces them.
--
--   ns.SuppressBlizzard(frame, { children = { "healthbar", "HealthBarsContainer.healthBar" }, keepParent = false })
--
-- The frame (and the named children) stop their events, hide, and move under
-- a hidden parent. Never with an OnShow -> Hide hook: Hide() on a protected
-- frame is refused in combat, while a hidden parent keeps it out of sight
-- whatever Blizzard's code does. The reparent waits for the end of combat for
-- protected frames, and never runs while the game's Edit Mode is open: Edit
-- Mode's layout pass reparents the frames it manages, and reparenting inside
-- it taints code that reads secret values. If the game reparents the frame
-- again, it goes back under the hidden parent on the next frame.
-- keepParent only stops events and hides, for frames whose reparenting itself
-- would taint. noHide skips the Hide: for frames Edit Mode shows and hides
-- through a protected setter (the action bars), where an addon's Hide taints
-- the next combat transition; the hidden parent keeps them out of sight.
-- Only a reload brings a suppressed frame back.

local _, ns = ...

local Combat = ns.Combat

local hiddenParent = CreateFrame("Frame", "SuuUIHiddenParent", UIParent)
hiddenParent:Hide()

local suppressed, hooked, pending = {}, {}, {}

local function resolve(frame, path)
    local v = frame
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end

local function reparent(frame)
    pending[frame] = nil
    if frame:GetParent() == hiddenParent then return end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        pending[frame] = true
        C_Timer.After(0.25, function() reparent(frame) end)
    elseif InCombatLockdown() and frame:IsProtected() then
        pending[frame] = true
        Combat.Run("blizzard:" .. (frame:GetName() or tostring(frame)), function() reparent(frame) end, "Hide Blizzard frame")
    else
        frame:SetParent(hiddenParent)
    end
end

function ns.SuppressBlizzard(frame, opts)
    if type(frame) == "string" then frame = _G[frame] end
    if not frame or suppressed[frame] then return end
    suppressed[frame] = true
    opts = opts or {}

    frame:UnregisterAllEvents()
    for _, path in ipairs(opts.children or {}) do
        local child = resolve(frame, path)
        if type(child) == "table" and child.UnregisterAllEvents then child:UnregisterAllEvents() end
    end
    if not opts.noHide and not (InCombatLockdown() and frame:IsProtected()) then frame:Hide() end
    if opts.keepParent then return end

    reparent(frame)
    if not hooked[frame] then
        hooked[frame] = true
        hooksecurefunc(frame, "SetParent", function(self, parent)
            if parent ~= hiddenParent and not pending[self] then
                pending[self] = true
                C_Timer.After(0, function() reparent(self) end)
            end
        end)
    end
end

-- Suppressed frames come back only with a reload; this says whether one is.
function ns.IsSuppressed(frame)
    if type(frame) == "string" then frame = _G[frame] end
    return frame ~= nil and suppressed[frame] == true
end

-- Kept for the public API: always false for a suppressed frame (reload to restore).
function ns.RestoreBlizzard(frame)
    return not ns.IsSuppressed(frame)
end
