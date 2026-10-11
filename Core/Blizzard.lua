-- Core/Blizzard.lua
-- Hiding Blizzard's own frames when a SuuUI module replaces them.
--
-- A frame is hidden by reparenting it to a hidden frame, never with an
-- OnShow -> Hide hook: Hide() on a protected frame is refused in combat, while
-- a hidden parent keeps it out of sight whatever Blizzard's code does. Both
-- changes go through the combat queue.

local _, ns = ...

local Combat = ns.Combat

local hiddenParent = CreateFrame("Frame", "SuuUIHiddenParent", UIParent)
hiddenParent:Hide()

local saved = {} -- frame -> { parent, unregistered }

-- Hides `frame`. With opts.unregisterEvents it also stops the frame's events,
-- for frames that would otherwise keep working while hidden; such a frame
-- only comes back after a reload.
function ns.SuppressBlizzard(frame, opts)
    if not frame or saved[frame] then return end
    local name = frame:GetName() or tostring(frame)
    Combat.Run("blizzard:" .. name, function()
        saved[frame] = { parent = frame:GetParent() }
        if opts and opts.unregisterEvents then
            frame:UnregisterAllEvents()
            saved[frame].unregistered = true
        end
        frame:SetParent(hiddenParent)
    end, "Hide " .. name)
end

-- Gives a suppressed frame back to its parent. Returns false when only a
-- reload can bring it back (its events were stopped).
function ns.RestoreBlizzard(frame)
    local s = frame and saved[frame]
    if not s then return true end
    if s.unregistered then return false end
    local name = frame:GetName() or tostring(frame)
    Combat.Run("blizzard:" .. name, function()
        frame:SetParent(s.parent)
        saved[frame] = nil
    end, "Restore " .. name)
    return true
end

function ns.IsSuppressed(frame)
    return saved[frame] ~= nil
end
