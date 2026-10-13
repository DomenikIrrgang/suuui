-- Core/Anchors.lua
-- Published anchors: how modules (and plugins) find each other's frames
-- without reaching into each other. A module publishes a frame under a name;
-- others look it up, and hear when it appears, changes or goes away.
--
--   SuuUI.PublishAnchor("target", frame)    -- nil unpublishes
--   SuuUI.GetAnchor("target")               -- the frame, or nil
--   message SUUUI_ANCHOR_CHANGED (name, frame)
--
-- Names in use: player, target, targettarget, focus, pet, boss1 ... boss5
-- (unit frames).

local _, ns = ...

local Anchors = {}
ns.Anchors = Anchors

local frames = {}

function Anchors.Publish(name, frame)
    if frames[name] == frame then return end
    frames[name] = frame
    ns.Events.Emit("SUUUI_ANCHOR_CHANGED", name, frame)
end

function Anchors.Get(name)
    return frames[name]
end
