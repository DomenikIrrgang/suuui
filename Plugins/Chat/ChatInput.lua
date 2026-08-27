local type, pairs = type, pairs

local M = {}

--[[ ===========================================================================================
     BLIZZARD'S EDIT BOX, ADOPTED.

     This file creates NO EditBox, and that is not a preference -- two walls make a custom one
     permanently worse, and both were measured rather than assumed:

       * `hash_SecureCmdList` is a FILE-LOCAL table in Blizzard's chat code with no global handle,
         so a box that parses its own input permanently loses /cast, /target, /click, /use,
         /castsequence, /focus, /equip and /startattack. There is no way to ask the client to run a
         secure command on our behalf.
       * Shift-clicking an item, spell or achievement inserts its link only into
         `ACTIVE_CHAT_EDIT_BOX`, which only Blizzard's own ActivateChat sets. A custom box gets
         nothing from a shift-click, silently.

     So the seam is: OUTPUT is ours, INPUT is Blizzard's. We reparent its box onto our frame, skin
     it, and read its state. Its own OnEnterPressed, ParseText and SendText are never touched.

     WHY THIS IS NEEDED AT ALL, rather than a nicety: the client parents `ChatFrame1EditBox` to
     `ChatFrame1`, and suppression parks that frame on a permanently hidden holder. A child of a
     hidden parent renders nothing whatever its own shown flag says -- so with Blizzard's chat
     suppressed and the box unadopted, pressing Enter opens an input the player cannot see. They can
     still type and send; they just cannot read what they are typing.
     =========================================================================================== ]]

--- The edit box to adopt, resolved from the frame that owns it rather than by global name.
---
--- By OWNERSHIP because the global name is not load-bearing on every client generation while the
--- `editBox` field on the chat frame is what Blizzard's own code reads. The global is tried second.
-- @return frame|nil
function M.Resolve()
    local cf = _G.ChatFrame1
    if type(cf) == "table" and type(cf.editBox) == "table" then return cf.editBox end
    local named = _G.ChatFrame1EditBox
    if type(named) == "table" then return named end
    return nil
end

local original = nil
local hooked = {}
local adopted = nil

-- FORWARD DECLARED. Both are called by functions defined above their bodies, and a Lua local
-- referenced before its declaration resolves as a NIL GLOBAL at runtime rather than failing at
-- load -- which has broken a file in this addon twice before, each time silently.
local replace, hookHeader

--- Reparents Blizzard's edit box onto `parent` and returns it.
---
--- The original parent and anchor are recorded ONCE, on the first adopt, so Restore can hand the box
--- back exactly. Recording on every call would capture our own frame on a re-adopt and make the box
--- unrestorable -- the same trap `BlizzardChat.park` documents, and the same fix.
-- @param parent frame
-- @return frame|nil
function M.Adopt(parent)
    local eb = M.Resolve()
    if not eb or not parent then return nil end

    if not original then
        original = { parent = eb:GetParent(), points = {} }
        for i = 1, (eb.GetNumPoints and eb:GetNumPoints() or 0) do
            local p, rel, relP, x, y = eb:GetPoint(i)
            original.points[i] = { p, rel, relP, x, y }
        end
    end

    eb:SetParent(parent)
    eb:ClearAllPoints()
    adopted = eb
    -- Skinned AFTER the reparent, because the frame level is derived from the new parent.
    M.Skin(eb)
    hookHeader()
    return eb
end

--- Makes Blizzard's box legible inside OUR row.
---
--- The template ships art and insets sized for its original home under the chat frame, and none of
--- that survives being moved into a 22-unit row:
---
---   * The ART REGIONS (a left cap, a stretched middle, a right cap) are drawn at the template's own
---     size and read as a second, wrong-sized frame around ours. Enumerated through GetRegions
---     rather than by name, because a hand-written name list is what drew a stray blue lattice over
---     the inventory grid -- the names differ across client generations and a missing one is silent.
---   * The TEXT INSETS are large enough to push a short string out of a short row.
---   * The FONT is the client's chat font, not ours, so the field would not match the log above it.
---
--- Every call is pcall'd: this runs at login against a frame we do not own, and SetFont RAISES on an
--- asset the client cannot load rather than returning false.
-- @param eb frame
--- Hides Blizzard's OWN channel label inside the box, and re-tightens the insets it sized for it.
---
--- The box draws a `Guild:` header of its own, so with our chip beside it the channel was named
--- TWICE and the two disagreed -- the chip said `Say` (see ChatType) while the header said `Guild:`.
--- The concept has one indicator, and it is the chip.
---
--- Blizzard re-creates both the header and the insets in ChatEdit_UpdateHeader, which runs whenever
--- the channel changes -- including a Tab cycle while the box stays open -- so this is re-applied
--- from a hook on that function rather than once at adoption.
-- @param eb frame
function M.SuppressHeader(eb)
    if not eb then return end
    for _, key in ipairs({ "header", "headerSuffix" }) do
        local region = eb[key]
        if type(region) == "table" then
            -- BOTH, and the alpha is the durable half: a path we did not hook can call Show() on the
            -- region, and SetTextColor's implicit alpha of 1 applies to the TEXT rather than to the
            -- region -- so a region alpha of 0 survives everything Blizzard's header update does.
            if region.Hide then pcall(function() region:Hide() end) end
            if region.SetAlpha then pcall(function() region:SetAlpha(0) end) end
        end
    end
    local pad = SuuUI.Theme:GetToken("spaceXs") or 4
    pcall(function() eb:SetTextInsets(pad, pad, 0, 0) end)
end

local headerHooked = false

--- Installs the hooks that keep the header suppressed as the channel changes.
---
--- TWO SHAPES, and BOTH are hooked -- the same rule as `C_Reputation` versus
--- `GetWatchedFactionInfo` in WOW_API_ENCAPSULATION.md. This client's refactored chat code exposes
--- the update as a METHOD on the edit box (`editbox.UpdateHeader`); the legacy form is a GLOBAL
--- (`ChatEdit_UpdateHeader`). ElvUI hooks both, each behind its own guard, which is the evidence
--- that it is not reliably one or the other on a given build.
---
--- Checking only the global is what shipped: it was absent, the guard returned silently, NO hook was
--- installed, and Blizzard put `Guild:` straight back after our OnShow hook had hidden it. A silent
--- no-op is the worst outcome for a two-shape API, so neither branch is assumed and a total miss is
--- reported rather than swallowed.
local headerCb

local function onHeaderUpdated(box)
    if not adopted then return end
    if box ~= nil and box ~= adopted then return end
    M.SuppressHeader(adopted)
    -- The channel is CHANGED through this path -- Tab and `/1` both land here -- so the owner is
    -- told before the box is placed: relabelling the chip re-measures it, and the placement that
    -- follows is the one that has to use the new width.
    if headerCb then pcall(headerCb) end
    replace(adopted)
end

--- Notified whenever the client updates the box's header, i.e. whenever the channel changes.
-- @param cb function()|nil  nil disarms
function M.OnHeader(cb)
    headerCb = cb
end

function hookHeader()
    if headerHooked then return end
    if type(_G.hooksecurefunc) ~= "function" then return end
    local eb = adopted or M.Resolve()
    local any = false

    -- The METHOD form, which is what the refactored client on this build carries.
    if eb and type(eb.UpdateHeader) == "function" then
        if pcall(_G.hooksecurefunc, eb, "UpdateHeader", onHeaderUpdated) then any = true end
    end
    -- The GLOBAL form, for a build that still exposes it.
    if type(_G.ChatEdit_UpdateHeader) == "function" then
        if pcall(_G.hooksecurefunc, "ChatEdit_UpdateHeader", onHeaderUpdated) then any = true end
    end

    headerHooked = any
    if not any then
        SuuUI.Debug("chat: no UpdateHeader hook available -- Blizzard's channel header may reappear")
    end
end

function M.Skin(eb)
    if not eb then return false end

    -- Art first, so anything below draws over a cleared surface rather than under stale caps.
    if eb.GetRegions then
        local ok, regions = pcall(function() return { eb:GetRegions() } end)
        if ok then
            for _, r in ipairs(regions) do
                if type(r) == "table" and r.GetObjectType and r:GetObjectType() == "Texture" then
                    pcall(function() r:SetTexture(nil) end)
                    pcall(function() r:Hide() end)
                end
            end
        end
    end

    M.SuppressHeader(eb)

    -- Declared HERE because the block that used to declare it was replaced by the SuppressHeader
    -- call above, leaving `T` a nil global for the three reads below -- which raised, took Adopt and
    -- the whole plugin build with it, and left the player with no SuuUI chat AND Blizzard's chat
    -- unsuppressed. `luac -p` passes on it, because a nil global is a runtime fault, not a syntax
    -- one, and the plugin build is pcall'd into a debug-only log.
    local T = SuuUI.Theme

    -- Resolved through Fonts:Path because SetFont raises on an unloadable asset. The font OBJECT is
    -- the fallback rather than the first choice, so the field matches the log's face.
    local path = SuuUI.Fonts:Path(T:GetToken("fontFamilyMain"))
    local size = T:GetFontSize("md")
    local ok = pcall(function() eb:SetFont(path, size, "") end)
    if not ok then
        pcall(function() eb:SetFontObject("ChatFontNormal") end)
    end
    -- Typed text takes the plain text colour; the CHANNEL is carried by the chip and the border, so
    -- colouring the text too would make a Say message read as disabled next to a Guild one.
    local c = T:GetToken("colorText") or { 1, 1, 1, 1 }
    pcall(function() eb:SetTextColor(c[1], c[2], c[3], c[4] or 1) end)

    -- Above the row's own backdrop. A reparent gives the child parent+1, but the box may carry an
    -- explicit level from its template, and a field whose text draws under the surface it sits on is
    -- indistinguishable from a field with no text at all.
    pcall(function()
        local parent = eb:GetParent()
        if parent and parent.GetFrameLevel then
            eb:SetFrameLevel(parent:GetFrameLevel() + 2)
        end
    end)
    return true
end

--- Registers a placer that re-anchors the box every time it opens.
---
--- MEASURED, not assumed: after adoption an in-game probe read the box focused, holding the typed
--- text, carrying a font -- and parented to a FULLSCREEN frame at (163, 478), nowhere near our row.
--- So the text had been rendering correctly the whole time, off in the middle of the screen with its
--- background art stripped, which makes it invisible.
---
--- Something re-parents and re-anchors the box after we adopt it; Blizzard's chat code does this on
--- activation. Placing it once and trusting that is therefore wrong, exactly as a one-shot SetPoint
--- on any Blizzard frame is wrong -- see "Repositioning A Blizzard Frame" in
--- WOW_API_ENCAPSULATION.md. The placer runs on every OnShow, which is the moment that matters.
-- @param fn function(editBox)|nil  nil disarms
function M.SetPlacer(fn)
    M._place = fn
    -- Applied immediately as well as on every open: the box may already be adopted by the time a
    -- placer is registered, and waiting for the first open would leave it mis-anchored until then.
    local eb = adopted or M.Resolve()
    if fn and eb then pcall(fn, eb) end
end

function replace(eb)
    if not M._place then return end
    pcall(M._place, eb)
end

--- Hands the box back to the parent and anchor it came from.
function M.Restore()
    local eb = adopted
    if not eb or not original then return false end
    -- Cleared before the reparent for symmetry with BlizzardChat's suppression flag, where the
    -- order IS load-bearing because an OnShow hook re-hides. Here it is defensive only: no hook of
    -- ours fires on SetParent, and mutation testing proved swapping the two changes nothing
    -- observable. Kept because the hooks are permanent and a future one might fire on this path.
    adopted = nil
    -- The placer goes with it: a stale closure would re-anchor the restored box back into our row on
    -- its next open, undoing the hand-back from a hook we cannot uninstall.
    M._place = nil
    -- Same reasoning, and the same permanence: `onHeaderUpdated` already returns early once
    -- `adopted` is nil, so this is belt-and-braces rather than the guard -- but the hook it hangs
    -- off cannot be uninstalled, and a closure onto a destroyed plugin is not worth keeping alive.
    headerCb = nil
    eb:SetParent(original.parent)
    eb:ClearAllPoints()
    for _, pt in ipairs(original.points) do
        eb:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
    end
    return true
end

function M.Adopted() return adopted end

--- Re-applies the registered placer now.
---
--- Exposed because the box's left inset is derived from the CHIP's width, and the chip only reaches
--- its final width after its text has been set and it has re-measured. Placing on OnShow alone used
--- a STALE chip width -- a short `1` inherited the inset of a longer name and left a visible gap.
--- The owner calls this straight after refreshing the chip, so the two can never disagree.
function M.Replace()
    local eb = adopted
    if eb then replace(eb) end
end

--- The chat type the box will send to, e.g. "SAY", "GUILD", "WHISPER", "CHANNEL".
---
--- Read from the BOX rather than from ChatTypeInfo's `sticky` flag, which is the mistake Phase 4a
--- shipped: `sticky = 1` means "this type may be remembered", not "you last spoke here", and six
--- types carry it -- so scanning for it returned whichever came first in an arbitrary iteration
--- order. The edit box is where the answer actually lives.
-- @return string chatType, string|nil target
function M.ChatType()
    local eb = adopted or M.Resolve()
    if not eb then return "SAY", nil end
    -- ATTRIBUTES, not fields. The client stores the channel as `GetAttribute("chatType")` -- ElvUI
    -- reads it that way in two places -- and the plain field is nil, so reading the field made this
    -- return "SAY" for every channel. In game the chip read `Say` while the field itself said
    -- `Guild:`. The harness modelled it as a field, so every spec passed against the wrong
    -- mechanism: a permissive model of a real API, which is this project's most repeated failure.
    --
    -- The field is kept as a FALLBACK rather than dropped, because it costs one `or` and a client
    -- generation that exposes it either way then needs no change here.
    local t
    if eb.GetAttribute then
        local ok, v = pcall(eb.GetAttribute, eb, "chatType")
        if ok then t = v end
    end
    if type(t) ~= "string" or t == "" then t = eb.chatType end
    if type(t) ~= "string" or t == "" then t = "SAY" end

    local function attr(name, field)
        if eb.GetAttribute then
            local ok, v = pcall(eb.GetAttribute, eb, name)
            if ok and v ~= nil and v ~= "" then return v end
        end
        return field
    end

    local target
    if t == "WHISPER" or t == "BN_WHISPER" then
        target = attr("tellTarget", eb.tellTarget)
    elseif t == "CHANNEL" then
        target = attr("channelTarget", eb.channelTarget)
    end
    return t, target
end

--- Whether the box is currently open.
function M.IsOpen()
    local eb = adopted or M.Resolve()
    return eb ~= nil and eb:IsShown() == true
end

--- Watches the box opening and closing.
---
--- HookScript, never SetScript: the box's own OnShow/OnHide drive Blizzard's history and sticky-
--- channel bookkeeping, and replacing either breaks them silently. A hook cannot be undone, so it
--- consults the callback table on every fire rather than assuming it should always report.
-- @param cb function(isOpen)|nil  nil disarms
function M.Watch(cb)
    M._cb = cb
    local eb = adopted or M.Resolve()
    if not eb or hooked[eb] then return end
    hooked[eb] = true
    eb:HookScript("OnShow", function(self)
        -- PLACEMENT FIRST. The box is re-parented and re-anchored away from our row by Blizzard's
        -- own chat code, so it is put back on every open rather than once at adoption -- measured in
        -- game as a focused box holding real text, sitting at (163, 478) under a fullscreen parent.
        replace(self)
        -- THEN focus. Blizzard's ChatEdit_ActivateChat calls SetFocus() BEFORE Show(), and the client
        -- refuses focus to a HIDDEN EditBox, so that call is silently dropped. This hook runs from
        -- inside Show(), where the shown flag is already true, which makes it the one place a focus
        -- call sticks. A no-op where Blizzard's own call already worked.
        pcall(function() if not self:HasFocus() then self:SetFocus() end end)
        if M._cb then M._cb(true) end
    end)
    eb:HookScript("OnHide", function() if M._cb then M._cb(false) end end)
    -- The channel can change WITHOUT the box closing -- Tab cycles it in place -- so the chip has to
    -- follow a text change too, which is the only script that fires on every keystroke.
    eb:HookScript("OnTextChanged", function() if M._cb then M._cb(true) end end)
end

--- Opens the box through the CLIENT's own activation, which is what sets ACTIVE_CHAT_EDIT_BOX and
--- therefore what makes shift-click-to-insert-a-link work at all.
---
--- Prefers the modern `ChatFrameUtil` name: this client runs the refactored Blizzard_ChatFrameBase
--- and the bare `ChatEdit_*` globals are deprecation shims.
function M.Open()
    local eb = adopted or M.Resolve()
    if not eb then return false end
    local U = _G.ChatFrameUtil
    if type(U) == "table" and type(U.ActivateChat) == "function" then
        U.ActivateChat(eb)
        return true
    end
    if type(_G.ChatEdit_ActivateChat) == "function" then
        _G.ChatEdit_ActivateChat(eb)
        return true
    end
    return false
end

function M.Close()
    local eb = adopted or M.Resolve()
    if not eb then return false end
    local U = _G.ChatFrameUtil
    if type(U) == "table" and type(U.DeactivateChat) == "function" then
        U.DeactivateChat(eb)
        return true
    end
    if type(_G.ChatEdit_DeactivateChat) == "function" then
        _G.ChatEdit_DeactivateChat(eb)
        return true
    end
    return false
end

SuuUI._ChatInput = M
