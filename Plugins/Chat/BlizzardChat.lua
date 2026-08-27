-- Suppressing Blizzard's chat, and mirroring what would otherwise be lost with it.
--
-- THIS IS THE DESTRUCTIVE HALF of the chat plugin, and it is deliberately much smaller than the
-- action bars' equivalent, because chat frames differ in two ways that remove most of the danger:
--
--   * They hold no secure templates, so nothing here is refused in combat. The action bars had to
--     unregister ActionBarController's events precisely because `Hide()` loses a race the client
--     wins during a fight; there is no such race here.
--   * We WANT Blizzard's frames alive and receiving. The mirror reads off them, so unregistering
--     anything would break the very thing this file exists to preserve. Nothing here is one-way,
--     which is why there is no ReloadGuard on the setting.
--
-- So suppression is purely visual: reparent onto a permanently hidden holder. A child of a hidden
-- parent renders nothing whatever its own shown flag says, so there is no re-show to fight and no
-- `Hide()` for Blizzard to undo.
local ipairs, pairs, type = ipairs, pairs, type

local M = {}

-- Resolved by CANDIDATE LIST, never a literal: the Classic clients have been given the modern
-- frame names in stages, so a rename lands as suppression that silently stops suppressing. Only
-- the chat logs and their tabs are here; anything the player still needs stays alone.
local TARGETS = {
    { "GeneralDockManager" },
    { "ChatFrameMenuButton" },
}

local hiddenHolder
local suppressed, hooked, originals = {}, {}, {}
local mirrorCb

local function holder()
    if not hiddenHolder then
        -- Anonymous and permanently hidden. Anonymous on purpose: a global name invites another
        -- addon to find it and show it.
        hiddenHolder = CreateFrame("Frame")
        hiddenHolder:Hide()
    end
    return hiddenHolder
end

--- Every chat log frame the client actually has, resolved rather than assumed.
function M.Frames()
    local out = {}
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local f = _G["ChatFrame" .. i]
        if f then out[#out + 1] = f end
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab then out[#out + 1] = tab end
    end
    for _, candidates in ipairs(TARGETS) do
        for _, name in ipairs(candidates) do
            local f = _G[name]
            -- EVERY matching name, not the first: this client answers to both a container and its
            -- child in several places, and stopping at the first left twelve action buttons on
            -- screen once already.
            if f then out[#out + 1] = f end
        end
    end
    return out
end

--- Parks a frame under the hidden holder, remembering where it came from.
---
--- The original is re-recorded on every GENUINE park -- when the frame is not already ours -- and
--- deliberately not when it is. Both halves matter and each was found by a mutation:
---
---   * Recording only once (the first version) restores to a stale home. Suppression can be
---     toggled off and on, and if another addon reparents the frame in between, SuuUI would drag
---     it back to where it lived at login instead of where it lives now.
---   * Recording UNCONDITIONALLY captures the holder itself the second time round, so Restore
---     would park the frame permanently under a hidden frame -- an unrecoverable chat.
---
--- SetParent runs either way, which makes Suppress self-healing: if something steals one of these
--- frames, the next Suppress puts it back rather than believing its own flag.
local function park(frame)
    if not suppressed[frame] then
        originals[frame] = { parent = frame:GetParent() }
    end
    suppressed[frame] = true
    frame:SetParent(holder())
end

local function unpark(frame)
    -- No `suppressed[frame]` guard: Restore is the only caller and it iterates that very table,
    -- so the flag is true by construction. Mutation testing proved a guard here unreachable.
    -- The flag is cleared BEFORE the reparent, for the reason a suppression flag is always
    -- cleared before a Show(): any hook consulting it must see the frame as no longer ours on the
    -- way out.
    suppressed[frame] = nil
    local o = originals[frame]
    frame:SetParent((o and o.parent) or _G.UIParent)
end

--- Mirrors addon output -- and ONLY addon output -- into a callback.
---
--- HOOKED, NEVER REPLACED. Replacing AddMessage on a Blizzard chat frame taints 10/10 times and
--- is what retired LS: Glass; the filter-only alternative loses left and right click on player
--- names. A post-hook is additive and costs neither.
---
--- The discriminator is the CHAT-TYPE ID. Blizzard's own message handler calls
--- `AddMessage(text, r, g, b, info.id)`, while `print()` reaches the same frame as
--- `AddMessage(text)` with nothing after it. So a call with no id is output that arrived by no
--- chat event -- an addon's print -- and is the only kind we mirror. Mirroring everything would
--- double every chat line, since our own CHAT_MSG registration already formatted it.
-- @param cb function|nil  called with (text) for each addon line; nil disables mirroring
function M.MirrorAddonOutput(cb)
    mirrorCb = cb
    local frame = _G.DEFAULT_CHAT_FRAME
    if not frame or not frame.AddMessage then return false end
    if hooked[frame] then return true end
    hooked[frame] = true
    -- hooksecurefunc cannot be undone, so the hook asks the callback on every call rather than
    -- assuming it should always mirror. Same shape as the guarded OnShow in every other
    -- suppression in this addon.
    hooksecurefunc(frame, "AddMessage", function(_, text, _, _, _, id)
        if not mirrorCb then return end
        if id ~= nil then return end
        if type(text) ~= "string" or text == "" then return end
        mirrorCb(text)
    end)
    return true
end

--- Hides Blizzard's chat. Reversible, and safe in combat -- no secure frames are involved.
function M.Suppress()
    for _, frame in ipairs(M.Frames()) do park(frame) end
end

--- Hands every frame back to the parent it came from.
function M.Restore()
    for frame in pairs(suppressed) do unpark(frame) end
end

function M.IsSuppressed(frame) return suppressed[frame] == true end

--- How many frames are currently parked. Lets a spec assert the whole set rather than a sample.
function M.SuppressedCount()
    local n = 0
    for _ in pairs(suppressed) do n = n + 1 end
    return n
end

--- Witness check: hiding a container is the MEANS, a frame off the screen is the END. Reports
--- rather than raises -- a stray visible chat frame is cosmetic, not a reason to take the plugin
--- down mid-session.
-- @return boolean ok, table stillVisible
function M.Verify()
    local bad = {}
    for frame in pairs(suppressed) do
        if frame.IsVisible and frame:IsVisible() then bad[#bad + 1] = frame end
    end
    if #bad > 0 then
        SuuUI.Debug("chat: " .. #bad .. " Blizzard chat frame(s) still visible after suppression")
    end
    return #bad == 0, bad
end

SuuUI._ChatBlizzard = M
