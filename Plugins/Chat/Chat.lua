-- The chat plugin. Phase 4a: ADDITIVE -- one General log alongside Blizzard's chat, which is left
-- completely alone. Suppression is 4b, deliberately separate: it is the one part of this feature
-- that can leave the player unable to read their chat, and the harness cannot verify it.
--
-- Frameless by design (see .kiro/specs/chat-plugin.md, "Glass Conversations"): the log floats over
-- the world with no surface of its own, and the only permanently visible chrome is the resting
-- chip naming the channel Enter would open.
local S = SuuUI.UISignals
local ipairs, type = ipairs, type

-- The kinds whose destination is decided by `whisper_mode` rather than by a panel's stored
-- filter. A set rather than a list because it is asked once per chat event.
local ipairs, pairs, type, tostring = ipairs, pairs, type, tostring
local tinsert = table.insert

local poolRegistered = false

local WHISPER_KINDS = {
    WHISPER = true, WHISPER_INFORM = true, AFK = true, DND = true,
    BN_WHISPER = true, BN_WHISPER_INFORM = true,
}

local PLUGIN_ID = "chat"

local plugin

--- Reads a setting. Wrapped so the whole file has one spelling of it.
local function get(key) return SuuUI.Settings:Get(PLUGIN_ID, key) end

local SCHEMA = {
    { key = "enabled", label = "Enable Chat", type = "toggle", default = true },
    -- Its own TOP-LEVEL toggle, outside every section, for the reason the action bars' one is:
    -- a player whose chat is misbehaving needs Blizzard's back without disabling the plugin whose
    -- settings page they are standing on. No ReloadGuard, unlike the action bars -- nothing here
    -- is one-way, because suppression is a reparent and the mirror is a hook that asks a flag.
    { key = "hide_blizzard", label = "Hide Blizzard's Chat", type = "toggle", default = true },

    { key = "", label = "Appearance", type = "section" },
    { key = "show_timestamps", label = "Show Timestamps", type = "toggle", default = true },
    { key = "timestamp_format", label = "Timestamp Format", type = "dropdown", default = "24h",
      enabledIf = "show_timestamps", options = {
        { value = "24h",  label = "14:32" },
        { value = "12h",  label = "2:32 PM" },
        { value = "24hs", label = "14:32:07" },
      } },
    { key = "show_tags", label = "Show Channel Tags", type = "toggle", default = true },
    { key = "font_size", label = "Text Size", type = "dropdown", default = "md", options = {
        { value = "sm", label = "Small" },
        { value = "md", label = "Medium" },
        { value = "lg", label = "Large" },
      } },
    { key = "width",  label = "Width",  type = "slider", default = 460, min = 240, max = 900, step = 10 },
    -- 1400 is deliberately ABOVE the screen's own height in units (~768 at the default scale, ~1080
    -- once the pixel grid's multiplier kicks in). That is not an oversight: a debugging window that
    -- runs off the top edge is a legitimate thing to want, the frame is moveable, and capping at the
    -- root's height would deny it for a tidiness nobody asked for.
    { key = "height", label = "Height", type = "slider", default = 180, min = 80,  max = 1400, step = 10 },

    { key = "", label = "Fading", type = "section" },
    { key = "fade_channels", label = "Fade Channel Messages", type = "toggle", default = false },
    -- The rail disc's diameter. A plugin SETTING rather than a theme token, per the token-or-setting
    -- split: this is one widget's own dimension, not design language the whole UI shares. It shipped
    -- pinned to `sizeControlSm` (18), which put an 11px glyph in an 18-unit circle and left the
    -- channel unidentifiable at a glance.
    { key = "rail_size", label = "Channel Icon Size", type = "slider", default = 30,
      min = 16, max = 44, step = 2 },
    { key = "fade_after", label = "Fade After", type = "slider", default = 8, min = 2, max = 60,
      step = 1, enabledIf = "fade_channels" },

    { key = "", label = "Conversations", type = "section" },
    { key = "whisper_mode", label = "Whispers Appear In", type = "dropdown", default = "both",
      options = {
        { value = "general", label = "General Only" },
        { value = "panel",   label = "Their Own Panel Only" },
        { value = "both",    label = "Both" },
      } },
    { key = "history_depth", label = "Remembered Messages", type = "slider", default = 50,
      min = 0, max = 500, step = 10 },

    { key = "", label = "Internal", type = "internal" },
    { key = "position", type = "position" },
}

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local Chat = {}

--- The channel the resting chip names.
---
--- 4a ALWAYS ANSWERS THE DEFAULT, and that is a correction rather than a shortcut: `sticky = 1`
--- in ChatTypeInfo does NOT mean "the channel you last spoke in", it means "this type is allowed
--- to be remembered" -- and say, party, raid, guild, officer and whisper all carry it in the
--- client's own defaults. Reading the flags therefore returns whichever type is checked first,
--- which is a chip that looks authoritative and is arbitrary.
---
--- Real sticky tracking lives on the edit box, which Phase 5 adopts. Until then the chip states
--- the honest default instead of guessing.
--- The channel the next message will go to, read from Blizzard's own edit box.
---
--- Phase 4a returned a literal "SAY" here, because `ChatTypeInfo.sticky` was the obvious source and
--- is the wrong one: `sticky = 1` means "this type MAY be remembered", not "you last spoke here",
--- and say, party, raid, guild, officer and whisper all carry it -- so scanning for it returned
--- whichever came first in an arbitrary iteration order. The edit box is where the answer lives.
function Chat:_stickyChannel()
    local t, target = SuuUI._ChatInput.ChatType()
    -- A numbered channel needs two things the type alone cannot give, and BOTH come from this one
    -- reading so the label and the colour cannot disagree about which channel is open.
    --
    -- `GetChannelName` answers the INDEX first and the name second -- ElvUI destructures it as
    -- `chanIndex` and tests `== 0` -- and the colour lives at `ChatTypeInfo.CHANNEL<index>` rather
    -- than at `ChatTypeInfo.CHANNEL`, so reading the plain type painted every numbered channel the
    -- same generic colour.
    local key, name = t, nil
    if t == "CHANNEL" and target ~= nil and type(GetChannelName) == "function" then
        local ok, idx, chanName = pcall(GetChannelName, target)
        -- Index 0 is the client's "you are not in that channel": there is no CHANNEL0 colour and no
        -- name to be had, so the number is left to stand rather than resolved into nothing.
        if ok and type(idx) == "number" and idx > 0 then
            key = "CHANNEL" .. idx
            if type(chanName) == "string" and chanName ~= "" then name = chanName end
        end
    end
    local info = ChatTypeInfo
    -- Falls back to the generic entry, because a client or a harness without the per-channel rows
    -- must still colour the chip rather than leave it plain white.
    local rec = type(info) == "table" and (info[key] or info[t]) or nil
    local colour = rec and { rec.r or 1, rec.g or 1, rec.b or 1, 1 } or nil
    return t, colour, target, name
end

-- The narrowest the typing area is ever allowed to become, whatever the chip says. A file
-- constant rather than a token or a setting, for the reason ClickAway's grace period is one: no
-- theme and no profile should be able to set it to zero and make the chat box untypeable. It is a
-- floor on usability, not a design value anyone tunes.
local MIN_INPUT = 80

local CHIP_LABEL = {
    SAY = "Say", PARTY = "Party", RAID = "Raid", GUILD = "Guild",
    OFFICER = "Officer", WHISPER = "Whisper",
}

--- Offers ONE line's text as selectable plain text, found by the sequence its copy icon carries.
---
--- Per line rather than per buffer, which is what was asked for: dumping the whole log made the
--- player hunt for the line they wanted inside a wall of text they did not.
---
--- The line is read back out of the LOG rather than recomposed from the store, so what is offered is
--- exactly what is on screen -- and the icon's own link is stripped with the rest of the markup,
--- since `|Hsuucopy:12|h|T…|t|h` is not part of what anybody wants to paste.
function Chat:CopyLine(seq)
    local log = self:ActiveLog()
    if not log or seq == nil then return false end
    local needle = "|Hsuucopy:" .. tostring(seq) .. "|h"
    for i = 1, (log:GetNumMessages() or 0) do
        local text = log:GetMessageInfo(i)
        if type(text) == "string" and text:find(needle, 1, true) then
            local plain = SuuUI.ChatFormat.Plain(text)
            -- Only the leading SPACE needs trimming. The icon itself is already gone: `Plain` unwraps
            -- the link to its label -- which for the copy link IS the texture escape -- and then
            -- strips textures, so nothing of the affordance survives except the space that followed
            -- it. A `^|T.-|t` strip was here first and mutation testing proved it never matched.
            plain = plain:gsub("^%s+", "")
            local modal = SuuUI.Components.Modal({
                title = "Copy Line",
                message = "Select and press Ctrl-C.",
                input = true,
                inputValue = plain,
                inputMaxChars = #plain + 1,
                dismissOnly = true,
                autoDestroy = true,
            })
            modal:Show()
            return modal
        end
    end
    return false
end

--- States the rail's cell: an explicit width, and the stretch that gives it the row's full height.
---
--- Takes a NUMBER rather than the expanded flag, because the expansion is animated and every frame of
--- that tween needs an intermediate width the flag cannot express.
---
--- ONE place, because `SetChildProps` REPLACES a child's props rather than patching them -- a call
--- passing only `width` silently dropped `align = "stretch"`, and the rail's scroll frame came out at
--- its own content height instead of the row's. Three call sites had to agree and did not.
function Chat:_setRailCell(width)
    if not (self._top and self._railScroll) then return end
    self._top:SetChildProps(self._railScroll, {
        width = width,
        align = "stretch",
    })
end

--- The height the rail+log row gets: everything the input row and its gap do not use.
---
--- STATED rather than left to `height = "fill"`. The fill produced 88 units inside a 180-unit window
--- -- the row came out at its own content height and the input row floated 66 units above the bottom
--- edge, which is what made the moveable frame look far larger than the chat. Whether that is a
--- limitation of vertical fill for a container child is NOT established: the obvious instrumentation
--- was invisible, because `print` inside the addon sandbox is captured by the harness's chat mirror
--- rather than reaching stdout. So this states the number it can compute instead of relying on a
--- distribution whose behaviour here is unexplained, and the open question is recorded as an xit.
function Chat:_topHeight()
    local T = SuuUI.Theme
    local gap = T:GetToken("spaceXs") or 4
    local total = (self._wrapper and self._wrapper:GetHeight()) or 0
    local input = (self._inputRow and self._inputRow:GetHeight()) or 0
    local h = total - input - gap
    if h < 1 then h = 1 end
    return h
end

--- Shows or hides the input row as Blizzard's box opens and closes.
---
--- The chip is REUSED rather than duplicated: at rest it sits under the log naming the channel Enter
--- will open, and with the field open it moves into the row and labels it. One widget, so the two
--- states cannot disagree about where a message is going -- which is the whole point of the chip.
--- Paints or clears the input row as Blizzard's box opens and closes.
---
--- It NEVER hides the row, because the row is the adopted edit box's parent and a child of a hidden
--- parent draws nothing and cannot take keyboard focus. Hiding it is what broke typing entirely.
--- At rest the row paints nothing and shows only the chip, which is the concept's resting state.
function Chat:_setInputOpen(open)
    open = open and true or false
    self:_refreshChip()
    if open == self._inputOpen then return end
    self._inputOpen = open
    if not self._inputRow then return end
    local B = SuuUI.Backdrop
    if open then
        -- The border colour is restated by _refreshChip from the channel, which has already run.
        B.Apply(self._inputRow, { bg = "colorBg", border = "colorBorder" })
        self:_refreshChip()
    else
        -- `false` is fully transparent, so the row keeps its box and its place while painting
        -- nothing -- there is no panel and no field at rest.
        B.Apply(self._inputRow, { bg = false, border = false })
    end
end

function Chat:IsInputOpen() return self._inputOpen == true end

--- The chip: at rest it names the channel Enter will open; with the input open it labels the field.
---
--- A whisper names the PERSON rather than the channel, because "Whisper" does not answer the
--- question the chip exists to answer. The concept spells it `-> Sylvaine`.
function Chat:_refreshChip()
    local t, colour, target, chanName = self:_stickyChannel()
    local label = CHIP_LABEL[t] or t
    if target and target ~= "" then
        if t == "WHISPER" or t == "BN_WHISPER" then
            label = ">" .. " " .. SuuUI.ChatFormat.ShortName(target, self._realm)
        else
            -- A numbered channel resolves to its NAME. The bare number is what the edit box carries
            -- and it answers nothing -- a chip reading `1` is the bug this branch exists to fix --
            -- so the number stands only when the client will not name the channel (index 0, i.e.
            -- not joined), which is still better than a blank chip.
            label = SuuUI.ChatFormat.ChannelLabel(chanName) or tostring(target)
        end
    end
    self._chip:SetText(label)
    if colour then self._chip:SetColor(colour) end
    -- The open field wears the chip's own channel colour as its border, so "where is this going"
    -- never leaves the screen -- and it MOVES when Tab cycles the channel.
    --
    -- Gated on the field being OPEN: this runs at rest too (the chip follows the sticky channel
    -- whether or not the box is up), and painting the border unconditionally framed the row at rest,
    -- which is the one thing the concept's resting state does not have.
    if self._inputOpen and self._inputBorder and colour then
        SuuUI.Backdrop.SetBorder(self._inputBorder, colour)
    end
    -- The typed text begins where the chip ends, so the placement depends on a width that only
    -- exists once SetText above has re-measured the chip. The placer runs on OnShow and on
    -- Blizzard's header update, both of which can precede this -- so a Tab to a wider channel
    -- would otherwise leave the caret at the PREVIOUS channel's inset. Restate it here, after
    -- the measure, which is the only moment the number is current.
    if self._inputOpen and SuuUI._ChatInput then SuuUI._ChatInput.Replace() end
end

--- Applies every setting that changes a log's shape, to EVERY panel's log.
---
--- Fading is resolved per panel rather than globally: channels fade, conversations persist, and
--- that is one native call differing per tab rather than a setting the player sets twice.
--- The sender's class colour as a `|cffRRGGBB` escape, or nil when the class is unknown.
---
--- Resolved from the GUID the chat event carried, which is the ONLY thing a chat message says about
--- who sent it -- there is no class field. `GetPlayerInfoByGUID` answers englishClass SECOND; the
--- first return is localized ("Mage"), which resolves to no colour at all and fails silently, so the
--- destructure here is deliberate and is the order ElvUI reads on this client.
---
--- CACHED ON THE RECORD, and the cache is what makes this safe to call from the render path: history
--- replay re-renders every stored line at login, and a record restored from a SavedVariable carries
--- a GUID whose player the client may no longer know anything about -- so the answer is memoised
--- including its absence, via a separate flag, or every replayed line would re-query for nothing.
---
--- Only a PLAYER gets one. A creature has no class and the client answers nothing for its GUID, which
--- is the right outcome: a monster's name takes the line's own colour.
function Chat:_classColour(rec)
    if not rec then return nil end
    if rec._classResolved then return rec._classCode end
    rec._classResolved = true
    local guid = rec.guid
    if type(guid) ~= "string" or guid == "" then return nil end
    if type(GetPlayerInfoByGUID) ~= "function" then return nil end
    -- pcall'd because this runs inside the renderer, off data a SavedVariable may have supplied, and
    -- the client raises on a malformed GUID rather than answering nil.
    local ok, _, englishClass = pcall(GetPlayerInfoByGUID, guid)
    if not ok or type(englishClass) ~= "string" then return nil end
    rec._classCode = SuuUI.Game and SuuUI.Game.ClassColorCode
                 and SuuUI.Game:ClassColorCode(englishClass) or nil
    return rec._classCode
end

function Chat:_apply()
    local size = get("font_size") or "md"
    local fadeOn = get("fade_channels")
    for id, log in pairs(self._logs or {}) do
        log:SetFontSize(size)
        local panel = SuuUI.ChatPanels.Find(self._panels, id)
        if panel and panel.fade and fadeOn then
            log:SetFading(true, get("fade_after"), nil)
        else
            log:SetFading(false)
        end
    end
    local w, h = get("width") or 460, get("height") or 180
    self._wrapper:SetSize(w, h)
    -- The ONLY place the row's height is stated -- initial layout included, since `_apply` runs on
    -- enable as well as on every size change. A second statement at build time was here and mutation
    -- testing proved it redundant: this one had already run by the time anything could observe it.
    if self._win and self._top then
        self._win:SetChildProps(self._top:GetFrame(), { width = "fill", height = self:_topHeight() })
    end
    -- RE-STATE the rail's content height once the row above has its final size. The scroll frame
    -- decides on a bar by comparing content against viewport, and at construction the viewport is not
    -- yet sized -- so a bar computed then reflects a viewport of almost nothing and appears when
    -- nothing overflows. In game that showed as a scrollbar after every reload that vanished on the
    -- first hover, because hovering rebuilt the rail and recomputed it correctly.
    --
    -- Deliberately belt-and-braces alongside the ordering fix in ScrollFrame's own resize handler:
    -- the harness lays out synchronously and does NOT reproduce the symptom either way, so neither
    -- change is verified against it. This one does not depend on when the client lays out.
    if self._railScroll and self._rail then
        SuuUI.UISignals:Emit(self._railScroll, SuuUI.UISignals.SIGNALS.CONTENT_RESIZED,
                             select(2, self._rail:GetContentSize()))
    end
end

--- The log a message with no panel of its own belongs in: the Log panel, else the active one.
function Chat:_systemLog()
    local panel = SuuUI.ChatPanels.Find(self._panels, "log")
              or SuuUI.ChatPanels.Find(self._panels, self._active)
              or self._panels[1]
    return panel and self:_logFor(panel) or nil
end

--- Routes one chat event into the log.
---
--- 4a puts EVERY tab's traffic in the ONE log, deliberately. A General-only log would show no
--- guild and no trade chat at all -- Guild is its own tab under the ruling -- which makes a poor
--- thing to judge the concept against. The tab SPLIT arrives with the rail in Phase 6; the event
--- map is already built here, so the routing is proven before anything depends on it.
---
--- The event handler: normalise into a record, store it, route it, render it.
---
--- The three steps are separate on purpose. Storing before routing means a re-pointed panel can
--- re-render from records it never saw live; routing returning a LIST means one message reaches
--- every panel that wants it; and formatting living in _render means a settings change re-reads
--- rather than being baked into whatever was appended at receipt time.
function Chat:_onChatEvent(event, ...)
    local msg, sender, language, channel, _, _, _, channelIndex,
          _, _, lineID, guid = ...

    local kind = event:gsub("^CHAT_MSG_", "")

    -- The language is shown ONLY when it is not the one the player speaks. Passing it through
    -- unconditionally put "[Common]" on every single line -- the client hands it over always, and
    -- Blizzard's own handler gates on `usingDifferentLanguage`. Gated HERE rather than at render
    -- time so the record stores the decision rather than re-deriving it per panel.
    local ownLanguage = type(GetDefaultLanguage) == "function" and GetDefaultLanguage() or nil
    local showLanguage
    if type(language) == "string" and language ~= "" and language ~= ownLanguage then
        showLanguage = language
    end

    -- `Sulisande-Thunderstrike` is what the client hands over even for someone standing beside you.
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil

    -- A whisper's conversation key is what makes its history storable and its panel stable across
    -- logins -- Blizzard's temp frames are forced to id 11+ and persist nothing.
    local conversation
    if WHISPER_KINDS[kind] then
        conversation = SuuUI.ChatRouting.ConversationKey(sender)
    end

    local rec = SuuUI.ChatStore.Record({
        kind         = kind,
        message      = msg,
        sender       = SuuUI.ChatFormat.ShortName(sender, realm),
        senderFull   = sender,
        language     = showLanguage,
        channel      = channel,
        channelIndex = channelIndex,
        lineID       = lineID,
        guid         = guid,
        conversation = conversation,
        at           = type(time) == "function" and time() or nil,
    })

    self._store:Add(rec)
    -- Before _RENDER, which is what actually matters: _render resolves each routed id against the
    -- panel list and falls back when one is missing, so a conversation must exist by then.
    -- WhisperPanels names the id without checking it exists, so this could equally sit after
    -- _route -- mutation testing proved the two orders equivalent. Kept here because "create it,
    -- then decide where it goes" reads in the order it happens.
    self:_ensureConversation(rec)
    rec.panels = self:_route(rec)
    self:_render(rec)
end

--- Shows or hides the jump-to-bottom affordance, and states how many lines arrived while away.
---
--- Driven by AT_BOTTOM_CHANGED, the one signal `MessageLog` emitted that nothing consumed. The
--- count is the messages that landed on the ACTIVE panel while it was scrolled up: a panel you are
--- not looking at already has its rail badge, and this answers the different question of "you are
--- reading history and the conversation has moved on".
---
--- Reaching bottom clears the count rather than the click doing it, so scrolling down by hand and
--- pressing the button end in the same state — the button is a shortcut, not the only route.
function Chat:_refreshJump()
    local btn = self._jump
    if not btn then return end
    local log = self:ActiveLog()
    if not log or log:AtBottom() then
        self._missed = 0
        btn:Hide()
        return
    end
    local n = self._missed or 0
    -- ASCII, not a geometric arrow. The client's faces do not reliably carry the shape glyphs, and a
    -- face missing one draws a box or nothing at all -- the same reason Accordion's chevron is `v`.
    btn:SetLabel(n > 0 and (n .. " new  v") or "v")
    btn:Show()
end

--- Counts one line that arrived on the active panel while it was scrolled away from the bottom.
function Chat:_bumpMissed(panel, log)
    if not panel or panel.id ~= self._active then return end
    if self._replaying then return end
    if log:AtBottom() then return end
    self._missed = (self._missed or 0) + 1
    self:_refreshJump()
end

--- Counts one unread message against a panel the player is not currently reading.
---
--- The ACTIVE panel never counts: its messages are on screen, so a badge over the tab you are
--- looking at would only ever say "you have read this". That single condition is the whole feature —
--- `Avatar` hides the badge at nil or 0 already, so nothing here has to decide when to draw.
function Chat:_bumpUnread(panel)
    if not panel or panel.id == self._active then return end
    -- Restored history is not "waiting for you": it is what you already read last session. Without
    -- this every badge would read 50 on login, which is exactly the noise the badge exists to make
    -- meaningful. (The fade path needs no such guard — it fades AFTER its loop rather than during.)
    if self._replaying then return end
    self._unread = self._unread or {}
    local n = (self._unread[panel.id] or 0) + 1
    self._unread[panel.id] = n
    local row = self._rows and self._rows[panel.id]
    -- No row yet is normal rather than an error: a conversation's rail row is built by the rebuild
    -- that _ensureConversation triggers, and the count is seeded from this table when it appears.
    if row then row:SetCount(n) end
end

--- Replays the restored history into the panels.
---
--- Deliberately does NOT go through `_store:Add`: `ChatStore.Restore` has already populated the
--- store, and re-adding would renumber every sequence and lose the interleaving that restoring by
--- sequence exists to preserve.
---
--- Routing is RE-DERIVED rather than read from the record's saved `panels` list, because the panel
--- set and `whisper_mode` can both have changed since the history was written -- a stored route
--- would send a line to a panel the player has since deleted.
function Chat:_replayHistory()
    if not self._store then return 0 end
    local recs = self._store:Records()
    self._replaying = true
    local failed = 0
    for i = 1, #recs do
        local rec = recs[i]
        -- PER RECORD, and this is the structural lesson from the failure it fixes: replay reads
        -- persisted data written by an older version of this addon, so a record it cannot render is a
        -- question of WHEN, not IF. Unguarded, one such record raised through `_render`, through this
        -- loop, and out of `buildWindow` -- leaving the plugin with no window, Blizzard's chat back on
        -- screen, and every setting apparently inert. A player lost the whole feature over one line.
        --
        -- The cost of skipping is one missing history line. The cost of not skipping is the window.
        local ok = pcall(function()
            self:_ensureConversation(rec)
            rec.panels = self:_route(rec)
            self:_render(rec)
        end)
        if not ok then failed = failed + 1 end
    end
    if failed > 0 then
        -- Reported rather than swallowed: silently dropping history is how a corrupt store stays
        -- undiagnosed for months.
        SuuUI.Fault("chat: skipped " .. failed .. " unreadable history record(s)")
    end
    self._replaying = false
    -- With fading ON, restored history is left FULLY FADED rather than fading out over the next few
    -- seconds. A line's fade clock starts when it is added, so replayed history would otherwise be
    -- as prominent at login as a message that just arrived -- and all of it would then fade out
    -- together, which reads as the UI breaking. Hovering the log brings it back.
    --
    -- With fading OFF -- now the default -- history simply stays on screen, which is what a player
    -- who turned fading off is asking for.
    if get("fade_channels") then
        for _, log in pairs(self._logs or {}) do log:SetFaded(true) end
    end
    return #recs
end

--- Writes the store to the per-character SavedVariable. Called at PLAYER_LOGOUT only.
function Chat:_saveHistory()
    if not self._store then return end
    SuuUIChatHistory = self._store:Serialise()
end

--- Which panels this record belongs in. A LIST, never one panel.
function Chat:_route(rec)
    if rec.conversation then
        -- A whisper's destination is the three-way `whisper_mode`, decided at receipt rather than
        -- by a stored filter: the conversation panel does not exist until someone whispers you.
        return SuuUI.ChatPanels.WhisperPanels(get("whisper_mode"),
                                              "whisper:" .. rec.conversation)
    end
    return SuuUI.ChatPanels.Route(self._panels, rec)
end

--- Formats a record and appends it to EVERY panel it was routed to.
---
--- Formatting happens HERE, per panel, per render, reading the settings that are live now -- never
--- at receipt, which would freeze the player's timestamp format and tag choice into the buffer, and
--- would give both panels the same string when a single-group panel wants no tag at all.
function Chat:_render(rec)
    local targets = {}
    for _, id in ipairs(rec.panels or {}) do
        local panel = SuuUI.ChatPanels.Find(self._panels, id)
        if panel then tinsert(targets, panel) end
    end

    -- A message must never land NOWHERE. Every routed id can fail to resolve -- whisper_mode is
    -- "panel" and the conversation has not been created yet, or the player deleted the only panel
    -- that wanted this group -- and a silently dropped line is the worst outcome this module can
    -- produce, worse than one shown in the wrong place, which is at least visible and correctable.
    if #targets == 0 then
        local fallback = self._panels[1]
        if not fallback then return end
        tinsert(targets, fallback)
    end

    local info = ChatTypeInfo and ChatTypeInfo[rec.kind]
    local r, g, b
    if type(info) == "table" then r, g, b = info.r, info.g, info.b end

    for _, panel in ipairs(targets) do
        local text = SuuUI.ChatFormat.Line({
            chatType     = rec.kind,
            message      = rec.message,
            -- The LINK keeps the full name, because that is what a whisper and a context menu
            -- need; only the displayed text is shortened.
            sender       = SuuUI.ChatFormat.PlayerLink(rec.senderFull, rec.lineID, rec.sender,
                                                       self:_classColour(rec)),
            language     = rec.language,
            channelIndex = rec.channelIndex,
        }, {
            timestamps = get("show_timestamps") and true or false,
            timeFormat = get("timestamp_format"),
            -- A panel carrying ONE group needs no tag: the panel IS the label, so "GLD" on every
            -- line of a Guild panel is the same information twice. This is the property the
            -- per-panel render buys -- one record, two panels, two correct strings.
            tag        = (get("show_tags") and self:_wantsTag(panel)) and true or false,
            -- Every line gets its own copy affordance. The sequence is the handle: it is stamped by
            -- the store before this runs, and it is what the click resolves the line back from.
            copySeq    = rec.seq,
        })
        -- The lineID is passed as the chat-type id, which is what BlizzardChat's mirror
        -- discriminates on: an id-less AddMessage is addon output from print(), and only those
        -- are mirrored.
        local log = self:_logFor(panel)
        -- A live message clears a login fade-out. Without this the first message after a reload
        -- would be added to a buffer sitting at alpha 0 and be invisible until the player happened
        -- to hover -- a worse bug than the one the fade-out fixes.
        --
        -- Safe during replay itself without a guard, because `_replayHistory` fades the logs AFTER
        -- its loop rather than before: nothing is faded while restored lines are being added, so
        -- there is no state here for them to clear.
        if log:IsFaded() then log:SetFaded(false) end
        log:AddMessage(text, r, g, b, rec.lineID)
        self:_bumpUnread(panel)
        self:_bumpMissed(panel, log)
    end
end

--- Whether a panel's rows should carry a channel tag.
---
--- One rule, not two: a tag is drawn only when the panel can hold MORE THAN ONE group, because
--- otherwise it is the same word on every line and the panel itself already says it.
---
--- A conversation is covered by that same rule rather than by a guard of its own -- it filters by
--- STREAM and carries no groups at all, so the count is 0. A separate `panel.conversation` check
--- was here and mutation testing proved it unreachable: both branches agreed on every input.
function Chat:_wantsTag(panel)
    return #(panel.groups or {}) > 1
end

--------------------------------------------------------------------------------
-- Panels: one log per panel, one rail row per panel, one shown at a time
--------------------------------------------------------------------------------

--- The colour a panel's rail disc and its lines carry.
---
--- A panel naming a THEME TOKEN gets that; a panel naming a chat TYPE gets that type's
--- ChatTypeInfo colour, which is a game fact rather than a theme decision; a conversation with no
--- class known yet falls back to the whisper colour, so a rail row is never invisible.
function Chat:_panelColor(panel)
    if type(panel.color) == "table" then return panel.color end
    if type(panel.color) == "string" then
        if panel.color:find("^color") then
            return SuuUI.Theme:GetToken(panel.color)
        end
        local info = ChatTypeInfo and ChatTypeInfo[panel.color]
        if type(info) == "table" then return { info.r, info.g, info.b, 1 } end
    end
    if panel.conversation then
        local info = ChatTypeInfo and ChatTypeInfo["WHISPER"]
        if type(info) == "table" then return { info.r, info.g, info.b, 1 } end
    end
    return SuuUI.Theme:GetToken("colorTextMuted")
end

--- The log for a panel, created on first use.
---
--- Through SuuUI.Pool so a conversation panel the player closes returns its frame rather than
--- leaking one per person they have ever spoken to. Shown/hidden on switch rather than re-rendered,
--- because a panel's FADING differs -- channels fade, conversations do not -- and re-running a
--- shared log's SetFading on every tab change would restart every line's timer.
function Chat:_logFor(panel)
    local existing = self._logs[panel.id]
    if existing then return existing end

    local log = SuuUI.Pool:Acquire("chat.log", self._wrapper)
    log:SetFontSize(get("font_size") or "md")
    log:SetChrome(panel.chrome and true or false)
    if panel.fade and get("fade_channels") then
        log:SetFading(true, get("fade_after"))
    else
        log:SetFading(false)
    end
    self._logBox:Add(log, { inset = 0 })
    if panel.id ~= self._active then log:Hide() end
    self._logs[panel.id] = log
    return log
end

--- The rail's width, collapsed or expanded.
---
--- Stated rather than hugged: a container with no explicit `w` takes its PARENT's width rather than
--- its content's (hugging is height-only), so the rail would be as wide as the whole window and the
--- log would start off the right edge.
function Chat:_railWidth(expanded)
    local T = SuuUI.Theme
    local gap = T:GetToken("spaceXs") or 4
    -- The SAME number the rows are built with. Read from the setting rather than the token, or a
    -- disc larger than 18 is clipped by a rail still sized for the old constant.
    -- The scrollbar is reserved ALWAYS, not only while the rows overflow: a bar that appeared with
    -- the first whisper would shift the log sideways at the moment a whisper arrived, which is the
    -- worst possible moment to move the text someone is reading.
    local bar = T:GetToken("sizeScrollbar") or 8
    local w = SuuUI.Pixel.Line(2) + gap + bar
        + (get("rail_size") or T:GetToken("sizeControlSm") or 18)
    if not expanded then return w end

    -- The WIDEST name, so expanding does not resize the rail again per row and the log's left edge
    -- is stable while the cursor moves down the list.
    local font = SuuUI.Fonts:Path(T:GetToken("fontFamilyMain"))
    local size = T:GetFontSize("md")
    local widest = 0
    for _, panel in ipairs(self._panels) do
        local lw = SuuUI.TextMetrics.Box(panel.name or panel.id or "", font, size)
        if lw > widest then widest = lw end
    end
    return w + gap + widest
end

--- Expands the rail to names, or collapses it to discs.
---
--- The concept keeps the rail collapsed at rest and "widens to names on hover".
---
--- Expanding does NOT re-size the rail's layout cell, and that is the load-bearing part: the rail
--- and the log are flow siblings, so growing the rail pushes the column -- which means hovering to
--- read a name would re-wrap every line of chat and slide the resting chip sideways. Measured in
--- game at ~70 units of travel. The names OVERLAY the log's left edge instead, and stay legible
--- because the concept gives `.lbl` a text-shadow for exactly this reason.
--- Expands or collapses the rail, MOVING the log rather than covering it.
---
--- This used to overlay: the rail kept its collapsed width and each row's name overflowed across the
--- log, which was a deliberate choice to keep the log's left edge from jumping. Seeing it settled it
--- the other way -- the names landed ON TOP of the message text and both became unreadable, which is
--- worse than a moving edge. So the rail's width is restated and the log reflows beside it.
function Chat:SetRailExpanded(on)
    on = on and true or false
    if on == self._railExpanded then return end
    self._railExpanded = on
    for _, row in pairs(self._rows) do row:SetShowLabel(on) end

    -- ANIMATED, because snapping the log sideways reads as a glitch rather than as a reveal. `animFast`
    -- is the token every other panel reveal in the addon uses -- Dropdown's panel, Modal, Tooltip,
    -- Accordion -- so this is the same gesture at the same speed rather than a timing of its own.
    --
    -- Driven through the animator's `value` property rather than by animating the frame's width: the
    -- width is a LAYOUT PROP, so tweening the frame directly would fight the container, which restates
    -- it on its next pass. `apply` hands every step back through the layout engine, which is the same
    -- division StatusBar's fill transitions draw.
    --
    -- One animation per (target, property), so a hover-out mid-expand PRE-EMPTS the expand and
    -- continues from wherever the width actually got to -- no queue, and no snap back to the start.
    local from = (self._railScroll and self._railScroll:GetWidth()) or self:_railWidth(not on)
    local to   = self:_railWidth(on)
    local dur  = SuuUI.Theme:GetToken("animFast") or 0.12
    -- 0 disables it, exactly as animPopScale = 1 disables the button pop. Also the equal-width case,
    -- where a tween would be a frame of work to arrive where it started.
    if dur <= 0 or from == to then
        self:_setRailCell(to)
        return
    end
    SuuUI.Anim:New({
        target   = self,
        property = "value",
        apply    = function(v) self:_setRailCell(v) end,
        from     = from, to = to,
        duration = dur, easing = "easeOut",
    }):Play()
end

function Chat:IsRailExpanded() return self._railExpanded == true end

--------------------------------------------------------------------------------

--- Rebuilds the rail AND restates its width.
---
--- The disc size is baked into each Avatar at construction, so a size change cannot be repainted --
--- and rebuilding alone is not enough either, because the window sized the rail's cell from the old
--- diameter and would clip every new disc.
---
--- The width follows the CURRENT expansion state. Hardcoding the collapsed one shrank the rail out
--- from under its own labels whenever a conversation appeared while the cursor was on the rail.
function Chat:_rebuildRail()
    self:_buildRail()
    self:_setRailCell(self:_railWidth(self._railExpanded == true))
end

--- Builds or rebuilds the rail from the panel list.
function Chat:_buildRail()
    for _, row in pairs(self._rows) do
        self._rail:Remove(row)
        row:Destroy()
    end
    self._rows = {}
    if self._sep then
        self._rail:Remove(self._sep)
        self._sep:Destroy()
        self._sep = nil
    end

    local size = get("rail_size") or SuuUI.Theme:GetToken("sizeControlSm")
    local placedConversation = false
    for _, panel in ipairs(self._panels) do
        -- A hairline between the channels and the people, exactly once, before the first
        -- conversation row. The concept's `.sep`: one list, two kinds.
        if panel.conversation and not placedConversation then
            placedConversation = true
            self._sep = SuuUI.Components.Divider({ dir = "horizontal" }, self._wrapper)
            self._rail:Add(self._sep, { width = "fill" })
        end

        local av = SuuUI.Components.Avatar({
            initial = panel.initial or (panel.name or panel.id):sub(1, 1):upper(),
            color   = self:_panelColor(panel),
            label   = panel.name,
            size    = size,
            active  = panel.id == self._active,
            -- Collapsed at rest, per the concept. Hover widens the whole rail, not one row.
            showLabel = self._railExpanded == true,
        }, self._wrapper)
        local id = panel.id
        SuuUI.UISignals:Connect(av, SuuUI.UISignals.SIGNALS.CLICKED, function()
            self:SetActivePanel(id)
        end)
        -- Armed from a ROW's enter rather than the rail frame's, because a container's frame is not
        -- ours to attach scripts to -- and it collapses through HoverAway rather than OnLeave, which
        -- fires on the way INTO a child and would collapse the rail from under the cursor the moment
        -- it reached the name it was aiming for.
        SuuUI.UISignals:Connect(av, SuuUI.UISignals.SIGNALS.MOUSE_ENTER, function()
            self:SetRailExpanded(true)
            if self._railHover then self._railHover:Arm() end
        end)
        -- NATURAL width, not "fill". A filled child is clamped to the rail's cell, so an expanded
        -- row's name would be shown and then clipped at 24 units. Taking its own width is what lets
        -- the name overflow the rail and OVERLAY the log instead of pushing it.
        self._rail:Add(av)
        self._rows[panel.id] = av
        -- Seeded from the tracked count rather than left at 0: the rail is rebuilt whenever a
        -- conversation appears, and a rebuild that reset every badge would silently discard the
        -- unread messages the badge exists to advertise.
        av:SetCount(self._unread and self._unread[panel.id] or 0)
    end
end

--- Switches the visible panel.
---
--- The same-id early-out is an OPTIMISATION and nothing more -- mutation testing proved that
--- removing it changes no observable behaviour, because re-showing an already-shown log does not
--- touch its scroll position. It becomes load-bearing once per-panel scroll state is restored on
--- switch (Phase 8), and `63_chat_plugin_spec.lua` carries an xit naming that.
function Chat:SetActivePanel(id)
    if id == self._active then return end
    if not SuuUI.ChatPanels.Find(self._panels, id) then return end
    self._active = id
    for pid, log in pairs(self._logs) do
        if pid == id then log:Show() else log:Hide() end
    end
    for pid, row in pairs(self._rows) do
        row:SetActive(pid == id)
    end
    -- Reading a panel is what clears its badge. Cleared for the panel being OPENED only: every other
    -- panel's count is still unread, and zeroing them all here would make the badge mean "since you
    -- last switched tabs" rather than "waiting for you".
    self._unread = self._unread or {}
    self._unread[id] = 0
    local row = self._rows[id]
    if row then row:SetCount(0) end
    -- The new panel has its own scroll position, and the missed count belonged to the old one.
    self._missed = 0
    self:_refreshJump()
    self:_refreshChip()
end

function Chat:GetActivePanel() return self._active end

--- The visible panel's log, or nil before the first is built.
function Chat:ActiveLog() return self._logs and self._logs[self._active] or nil end

--- One panel's log, or nil when that panel has never received a message.
function Chat:LogFor(id) return self._logs and self._logs[id] or nil end

--- Creates a conversation panel the first time someone whispers, and gives it a rail row.
---
--- Done at RECEIPT rather than from stored settings because a conversation cannot be configured
--- before it exists. The panel is appended, so it lands after every channel panel and the rail's
--- separator falls in the right place without ordering logic.
function Chat:_ensureConversation(rec)
    if not rec.conversation then return nil end
    -- `whisper_mode` decides this, and it was NOT consulted: a panel was built on every first
    -- whisper regardless, so "General Only" produced a rail row for a conversation whose messages
    -- all went to General -- an empty panel advertising itself.
    --
    -- Gated here rather than through a SECOND setting, which is what "a config for whether new
    -- whispers open a window" would naively become: two settings both answering "do I get a whisper
    -- panel" can contradict each other, and `whisper_mode = panel` with panels switched off would
    -- route every whisper to a panel that does not exist. One setting, three honest states.
    if get("whisper_mode") == "general" then return nil end
    local id = "whisper:" .. rec.conversation
    local existing = SuuUI.ChatPanels.Find(self._panels, id)
    if existing then return existing end

    local panel = SuuUI.ChatPanels.Conversation(rec.conversation, rec.sender)
    tinsert(self._panels, panel)
    -- _rebuildRail rather than _buildRail: a new conversation can carry the LONGEST name in the
    -- list, and the expanded width is measured from the widest one. Rebuilding the rows alone left
    -- that width stale -- harmless while expansion overlays the log rather than reflowing it, which
    -- is exactly the kind of "harmless" that stops being harmless when the overlay changes.
    self:_rebuildRail()
    return panel
end

--------------------------------------------------------------------------------

local function buildWindow(p)
    local root = SuuUI.UIRoot:GetRootContainer():GetFrame()

    local self = setmetatable({}, { __index = Chat })

    -- A plain wrapper so the log and the chip stack; frameless, so it paints nothing itself.
    local wrapper = CreateFrame("Frame", "SuuUI_chat_wrapper", root)
    wrapper:SetSize(get("width") or 460, get("height") or 180)
    self._wrapper = wrapper

    -- The concept's window is [rail][column] -- but the INPUT ROW is a full-width sibling BELOW that
    -- row rather than a child of the column, which is what stops it moving when the rail expands.
    --
    -- The rail widens on hover and pushes whatever shares its row. With the input inside the column
    -- that meant the resting chip slid sideways every time the cursor crossed the rail; as a sibling
    -- it is outside that row entirely and cannot be pushed. It also gets the WHOLE window width to
    -- type in rather than being inset by the rail, which is the better field either way.
    local win = SuuUI.Layout:CreateContainer({
        host = wrapper, layout = "flow", dir = "vertical",
        gap = SuuUI.Theme:GetToken("spaceXs"),
    })
    self._win = win

    -- The row the rail actually lives in, and therefore the only thing its expansion resizes.
    --
    -- HOSTED ON A FRAME rather than being a bare container, and that is load-bearing: a container
    -- with no explicit `h` re-states its height from its CONTENT inside its own Layout(), which
    -- overwrites whatever the parent assigned -- so `height = "fill"` was silently losing to the hug
    -- and this row came out 88 units tall inside a 180-unit window. The input row then floated 66
    -- units above the bottom edge and the moveable frame looked far bigger than the chat.
    --
    -- A host container adopts the frame's size instead of computing one, so the fill sticks. Same
    -- shape as logHost below, for the same reason.
    local topHost = CreateFrame("Frame", nil, wrapper)
    local top = SuuUI.Layout:CreateContainer({
        host = topHost, layout = "flow", dir = "horizontal",
        gap = SuuUI.Theme:GetToken("spaceSm"),
    })
    win:Add(topHost, { width = "fill", height = "fill" })
    self._top = top

    -- The rail SCROLLS. It is a vertical flow of one row per channel plus one per conversation, so
    -- its content height grows without bound -- with a handful of whispers open it ran past the
    -- window's bottom edge, over the input row and off the frame, taking the rows out of reach.
    --
    -- Stretched on the cross axis rather than given `height = "fill"`: in a horizontal flow the
    -- height IS the cross axis, so stretch is the documented mechanism and it sidesteps the fill
    -- behaviour that under-sized the row above.
    local railScroll = SuuUI.Components.ScrollFrame({
        w = self:_railWidth(false), h = 1,
    }, wrapper)
    top:Add(railScroll, { width = self:_railWidth(false), align = "stretch" })
    self._railScroll = railScroll

    -- The rail. Channel rows, a hairline separator, then one row per conversation -- which is one
    -- list rather than two, so switching from Guild to a whisper is the same gesture.
    local rail = SuuUI.Layout:CreateContainer({
        parent = railScroll:GetContent(), layout = "flow", dir = "vertical",
        gap = SuuUI.Theme:GetToken("spaceXxs"),
    })
    self._rail = rail
    self._rows = {}
    self._railExpanded = false

    -- The scroll frame cannot know its content grew: the rail reports its own height and this hands
    -- that number on, which is what makes the bar appear exactly when the rows overflow.
    SuuUI.UISignals:Connect(rail, SuuUI.UISignals.SIGNALS.SIZE_CHANGED, function(_, h)
        SuuUI.UISignals:Emit(railScroll, SuuUI.UISignals.SIGNALS.CONTENT_RESIZED, h)
    end)

    -- Collapses when the cursor leaves the rail as a REGION. OnLeave cannot express this: the
    -- client moves focus to a child as soon as the cursor enters one, so a row's own OnLeave fires
    -- while the cursor is still inside the rail.
    self._railHover = SuuUI.Components.HoverAway({
        frame = railScroll:GetFrame(),
        onOutside = function() self:SetRailExpanded(false) end,
    })

    -- Every panel's log OVERLAYS in one stack rather than sitting in the flow, because only one is
    -- shown at a time and flow would collapse the hidden ones -- resizing the column on every tab
    -- switch. A stack also keeps each log at the full column size whether or not it is visible.
    --
    -- Added to `top`, beside the rail. The intermediate vertical column this used to sit in is gone:
    -- it existed only to stack the log above the input row, and the input row is a sibling of this
    -- whole row now.
    local logHost = CreateFrame("Frame", nil, wrapper)
    local logBox = SuuUI.Layout:CreateContainer({ host = logHost, layout = "stack" })
    top:Add(logHost, { width = "fill", height = "fill" })
    self._logHost, self._logBox = logHost, logBox

    -- Jump-to-bottom. A stack child of the log box, so it OVERLAYS the log's bottom-right corner
    -- rather than taking a row from it -- the log must not shrink when the button appears, or the
    -- text reflows every time you scroll up.
    local T = SuuUI.Theme
    local jump = SuuUI.Components.Button({
        label = "v",
        onClick = function()
            local log = self:ActiveLog()
            if log then log:ScrollToBottom() end
            -- Not cleared here: ScrollToBottom emits AT_BOTTOM_CHANGED, which refreshes and clears.
            -- Clearing here as well would be a second source of truth for the same fact.
        end,
    }, logHost)
    logBox:Add(jump, {
        align = "end", valign = "end",
        inset = { right = T:GetToken("spaceSm") or 8, bottom = T:GetToken("spaceSm") or 8 },
    })
    jump:Hide()
    self._jump = jump
    self._logs = {}

    -- The resting chip: the only permanently visible chrome in 4a, and the visible surface of
    -- sticky channel. Blizzard has sticky channel and shows it nowhere until the box is already
    -- open, which is the top cause of mistells.
    --
    -- OUTLINE, not filled. Say's ChatTypeInfo colour is pure WHITE, so a filled chip renders a
    -- light grey pill that reads as a button rather than a label -- measured from a screenshot,
    -- not predicted. An outline keeps the ring and the coloured text and drops the wash.
    self._realm = type(GetRealmName) == "function" and GetRealmName() or nil

    -- ONE row, ALWAYS SHOWN, holding the chip and the adopted edit box side by side. The concept
    -- puts `.rest` (the chip) and `.ib` (the open field) on the same line, so this is one surface
    -- whose PAINT changes rather than two that swap.
    --
    -- Always shown is not a style choice, it is the bug fix. The first build created this row hidden
    -- and adopted Blizzard's edit box INTO it, which broke typing outright in two ways at once:
    --   * a child of a hidden parent draws nothing and cannot take keyboard focus, so Enter opened
    --     a box that was not really there;
    --   * the box was added to a container HOSTED ON THE HIDDEN FRAME, which is the documented
    --     "show a container before anchoring a foreign child to it" failure -- the child never
    --     resolves a rect, and showing the frame afterwards does not dirty a child that is not its
    --     own. LAYOUT_SYSTEM.md calls this out, and an attach point is the only other place it bites.
    -- So the row is never hidden. Only its border and background are painted or cleared.
    local inputRow = CreateFrame("Frame", nil, wrapper, "BackdropTemplate")
    inputRow:SetHeight(SuuUI.Theme:GetControlHeight("sizeControlMd"))
    local inputRowBox = SuuUI.Layout:CreateContainer({
        host = inputRow, layout = "flow", dir = "horizontal",
        gap = SuuUI.Theme:GetToken("spaceXs"), align = "center",
        padding = { left = SuuUI.Theme:GetToken("spaceXs"),
                    right = SuuUI.Theme:GetToken("spaceXs") },
    })
    -- FULL WIDTH of the window, and a sibling of the rail's row rather than a child of it: the
    -- rail cannot push what is not beside it.
    win:Add(inputRow, { width = "fill" })
    self._inputRow, self._inputBox, self._inputBorder = inputRow, inputRowBox, inputRow

    local chip = SuuUI.Components.Chip({ text = "Say" }, inputRow)
    inputRowBox:Add(chip, { width = "auto" })
    self._chip = chip

    -- Blizzard's box, adopted rather than replaced -- see ChatInput.lua for the two walls that make
    -- a custom one permanently worse. Added to a container on a SHOWN frame, per the note above.
    -- Unpainted at rest: there is no panel and no field until Enter.
    SuuUI.Backdrop.Apply(inputRow, { bg = false, border = false })

    local eb = SuuUI._ChatInput.Adopt(inputRow)
    if eb then
        -- The ROW owns the height and the box fills it -- note the placer below pins the box to all
        -- FOUR edges, so its own template height is not a constraint on anything.
        --
        -- There used to be a ratchet here: `if boxH > rowH then inputRow:SetHeight(boxH) end`, from
        -- before that BOTTOM anchor existed. It was a one-way grow driven by a frame BLIZZARD owns,
        -- and it broke two things at once in game while the suite stayed green -- the harness's edit
        -- box stub is small, so the branch never fired. With a tall box the row ate the window,
        -- `_topHeight` clamped the log to its 1-unit floor, and the Height slider then appeared to do
        -- NOTHING, because every value it set was consumed by the row.
        --
        -- The rule this cost: never let a foreign frame's reported size become a floor for our own
        -- layout. Size ours from tokens and fit theirs into it.
        -- Placed EXPLICITLY rather than added to the flow container, and re-placed on every open.
        -- SetPoint on a Blizzard frame is the documented carve-out for exactly this.
        --
        -- ANCHORED ONLY TO THE ROW, never to the chip. Measured in game: the row resolved a real rect
        -- (left 56, bottom 176, 428 wide) while the box reported `GetLeft()` and `GetBottom()` as NIL
        -- with a stale width of 5 -- the signature of an anchor chain that does not resolve, not of a
        -- frame squeezed thin. Anchoring to the chip made the chip's own rect a prerequisite; the row
        -- is the one frame proven to have one, so the chain cannot fail.
        --
        -- The chip is cleared by a computed INSET rather than by an anchor, and the inset is clamped:
        -- a chip that ever measures absurdly wide must not leave a field too narrow to read.
        SuuUI._ChatInput.SetPlacer(function(box)
            local pad = SuuUI.Theme:GetToken("spaceXs") or 4
            if box:GetParent() ~= inputRow then box:SetParent(inputRow) end
            local rowW  = inputRow:GetWidth() or 0
            local chipW = chip:GetWidth() or 0
            -- The caret starts one gap past the chip, so the inset IS the chip's measured width.
            -- Clamped by leaving MIN_INPUT for typing rather than by snapping to a fraction of the
            -- row: the old `> 66% -> 33%` rule moved the text LEFT, i.e. underneath the very chip
            -- it was avoiding, so a long whisper target overlapped what was being typed.
            local inset = pad * 2 + chipW
            if rowW > 0 then
                local maxInset = rowW - pad - MIN_INPUT
                if maxInset < pad then maxInset = pad end
                if inset > maxInset then inset = maxInset end
            end
            box:ClearAllPoints()
            box:SetPoint("LEFT", inputRow, "LEFT", inset, 0)
            box:SetPoint("RIGHT", inputRow, "RIGHT", -pad, 0)
            box:SetPoint("TOP", inputRow, "TOP", 0, 0)
            box:SetPoint("BOTTOM", inputRow, "BOTTOM", 0, 0)
        end)

        SuuUI._ChatInput.Watch(function(open)
            self:_setInputOpen(open)
        end)

        -- Tab and `/1` change the channel without opening or closing the box, so the open/close
        -- watch above never fires for them and the chip would keep naming the previous channel.
        SuuUI._ChatInput.OnHeader(function()
            self:_refreshChip()
        end)
    end

    SuuUI.UIRoot:SetLayer(wrapper, "normal")

    SuuUI.MoveableFrame:Apply(wrapper, {
        pluginId = PLUGIN_ID, key = "position",
        displayName = "Chat",
        defaults = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 24, y = 120 },
    })

    -- Panels and the store are built BEFORE the event frame, because registration is derived from
    -- the panel list: a group no panel wants is not subscribed at all.
    self._panels = SuuUI.ChatPanels.Panels(p:GetProfile().panels)
    -- Built from the SavedVariable rather than empty, which is what makes history survive a logout
    -- and is the whole reason records carry a sequence. `Restore` tolerates nil and a hand-edited
    -- blob by yielding an empty store, so a fresh install and a returning player are ONE path.
    --
    -- The blob's own depth is deliberately discarded in favour of the SETTING: a player who lowered
    -- the slider between sessions expects the next login to trim, not to honour the depth that was
    -- in force when the history was written.
    self._store  = SuuUI.ChatStore.Restore(SuuUIChatHistory)
    self._store:SetDepth(get("history_depth"))
    self._active = self._panels[1] and self._panels[1].id or nil

    -- Pooled so a conversation the player closes returns its frame rather than leaking one per
    -- person they have ever spoken to.
    -- Registered once per session. Pool has no Has(), and re-registering would replace the
    -- factory on every /reload-free plugin re-enable for no gain.
    if not poolRegistered then
        poolRegistered = true
        SuuUI.Pool:Register("chat.log", function(parent)
            local log = SuuUI.Components.MessageLog({ maxLines = 512, chrome = false }, parent)
            local SIG = SuuUI.Components.MESSAGELOG_SIGNALS
            -- Wired in the FACTORY, not at acquire time: this runs once per physical log, so a
            -- pooled log cannot accumulate a second connection each time a panel re-acquires it.
            -- Nothing here captures the plugin, because the factory outlives it -- the client's own
            -- globals are the whole implementation.
            --
            -- `MessageLog` reports the gesture and this decides what it MEANS, the same division
            -- `ResizeGrip` draws. What it means is `SetItemRef`: that one call is what makes an item
            -- link open its tooltip frame, a player link open the whisper menu, and a quest or spell
            -- link open its own panel. None of it is protected, so no combat guard belongs here.
            S:Connect(log, SIG.HYPERLINK_CLICK, function(link, text, button)
                -- `url:` is OUR link type and the client knows nothing about it, so it is answered
                -- here rather than handed on: SetItemRef would silently do nothing. There is no way
                -- to open a browser from the client, so the honest answer is to hand the player the
                -- address in something they can select and copy.
                local url = type(link) == "string" and link:match("^url:(.+)$")
                if url then
                    SuuUI.Components.Modal({
                        title = "Link",
                        message = "Press Ctrl-C to copy.",
                        input = true,
                        inputValue = url,
                        dismissOnly = true,
                        autoDestroy = true,
                    }):Show()
                    return
                end
                -- Our own link type too, and answered the same way: the client has no `suucopy`
                -- handler, so forwarding it would be a silent no-op.
                local seq = type(link) == "string" and link:match("^suucopy:(%d+)$")
                if seq then
                    local w = SuuUI.Chat_GetWindow()
                    if w then w:CopyLine(tonumber(seq)) end
                    return
                end
                if type(SetItemRef) ~= "function" then return end
                -- The CLIENT's own dispatcher, not Blizzard's chat-frame script. Forwarding through
                -- `ChatFrame1:GetScript("OnHyperlinkClick")` was tried and REVERTED together with the
                -- hover forwarding: that frame is parked under a hidden holder by suppression, so
                -- handing it the gesture put the result somewhere with no rect. It is also the wrong
                -- shape of dependency -- this addon must stand alone.
                --
                -- The cost is honest and worth stating: a link type a THIRD-PARTY addon adds (Questie's
                -- `questie:`) is dead in our log, because those addons hook `ChatFrame1..10` BY NAME and
                -- our frame is not one of them. Every link type the CLIENT knows works.
                --
                -- pcall stays -- an error raised inside a click handler unwinds into the client -- but
                -- it must not be SILENT, or a dead link is indistinguishable from nothing being wired.
                local ok, err = pcall(SetItemRef, link, text, button, log:GetFrame())
                if not ok then
                    SuuUI.Debug("chat: SetItemRef failed for " .. tostring(link) .. ": " .. tostring(err))
                end
            end)
            -- Hovering a link shows the client's tooltip, which is what makes a linked item worth
            -- linking. `SetHyperlink` raises for a link that has no tooltip -- a player link is the
            -- common one -- so a failure hides the tooltip rather than leaving the previous item's
            -- on screen.
            S:Connect(log, SIG.HYPERLINK_ENTER, function(link)
                -- OUR OWN tooltip, deliberately. Forwarding to Blizzard's OnHyperlinkEnter was tried
                -- and REVERTED: its handler anchors the tooltip to ChatFrame1, which suppression has
                -- parked under a hidden holder -- and a hidden frame has no rect, so the tooltip drew
                -- nothing at all. It failed silently and cost every item mouseover in the log.
                local tt = GameTooltip
                if not tt then return end
                tt:SetOwner(log:GetFrame(), "ANCHOR_CURSOR")
                if pcall(tt.SetHyperlink, tt, link) then tt:Show() else tt:Hide() end
            end)
            S:Connect(log, SIG.HYPERLINK_LEAVE, function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            -- Reached through the accessor rather than a captured `self`: this factory is registered
            -- once per SESSION and outlives any one plugin instance, so a captured plugin would go
            -- stale on a disable/enable cycle while the closure kept it alive.
            S:Connect(log, SIG.AT_BOTTOM_CHANGED, function()
                local w = SuuUI.Chat_GetWindow()
                if w then w:_refreshJump() end
            end)
            return log
        end)
    end

    self:_buildRail()
    -- After _buildRail, because the width is measured from the panel list's widest name. On `top`,
    -- which is the row the rail is a child of -- setting it on the vertical window would size a child
    -- that container does not have, and silently do nothing.
    self:_setRailCell(self:_railWidth(false))
    -- The first panel's log exists from the start, so the window is not an empty box before the
    -- first message arrives.
    if self._panels[1] then self:_logFor(self._panels[1]) end

    -- Replayed AFTER the rail and the first log exist: a restored whisper adds a rail row through
    -- _ensureConversation, and _render resolves panel ids against a list that has to be built.
    self:_replayHistory()

    -- One event frame for every chat event ANY panel wants, exactly as the action bars use one
    -- shared frame rather than one per button.
    local ev = CreateFrame("Frame", nil, wrapper)
    ev:SetScript("OnEvent", function(_, event, ...)
        -- PLAYER_LOGOUT is the ONLY moment the history is written, per the addon's SavedVariables
        -- rule: serialising on every message would rewrite the whole table to append one line.
        if event == "PLAYER_LOGOUT" then self:_saveHistory() return end
        self:_onChatEvent(event, ...)
    end)
    pcall(ev.RegisterEvent, ev, "PLAYER_LOGOUT")
    for _, event in ipairs(SuuUI.ChatPanels.Events(self._panels, ChatTypeGroup)) do
        -- pcall: an event absent on this client generation must not take the plugin down.
        pcall(ev.RegisterEvent, ev, event)
    end
    self._events = ev

    self:_apply()
    self:_refreshChip()
    return self
end

plugin = SuuUI:CreatePlugin({
    id = PLUGIN_ID,
    name = "Chat",
    version = "0.1",

    onInit = function(p)
        SuuUI.Settings:Register(PLUGIN_ID, SCHEMA)
        -- No immediate = true on the plugin's own enabled watcher: Plugins:autoEnable already
        -- applies the stored value during the login pass, and an immediate callback would run
        -- onEnable from inside the init pass.
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, PLUGIN_ID)
    end,

    onEnable = function(p)
        -- GUARDED, and the guard is the point. `onEnable` is pcall'd into a debug-gated log, so a
        -- throw in buildWindow used to abort this function SILENTLY -- and everything below it,
        -- including the `hide_blizzard` watcher, never ran. The visible result was Blizzard's chat
        -- back on screen with no error and no clue, which is exactly how it presented.
        --
        -- SuuUI.Fault prints with debug off, which is the difference between a bug report saying
        -- "the chat is broken" and one naming the line.
        if not p._chat then
            -- xpcall with a traceback handler, not pcall: the message alone says WHAT failed and the
            -- stack says WHERE, and without the line number this cost several rounds of guessing.
            --
            -- The result is also parked in a global. UIErrorsFrame text FADES after a few seconds, so
            -- a fault the player blinked past is a fault nobody can read -- `SuuUI._ChatBuildError`
            -- survives until the next reload and can be printed on demand.
            local ok, res = xpcall(function() return buildWindow(p) end, function(e)
                local where = ""
                if type(debugstack) == "function" then
                    local okStack, s = pcall(debugstack, 2, 8, 0)
                    if okStack then where = tostring(s) end
                end
                return tostring(e) .. "\n" .. where
            end)
            if ok then
                p._chat = res
                SuuUI._ChatBuildError = nil
            else
                SuuUI._ChatBuildError = tostring(res)
                SuuUI.Fault("chat: the window failed to build: " .. tostring(res))
            end
        end
        if p._chat then p._chat._wrapper:Show() end

        -- Addon output has no chat event, so it can only be caught by hooking Blizzard's frame.
        -- Wired whether or not suppression is on: with their chat visible the line would otherwise
        -- appear only there, and ours would silently lack every DBM / Questie / Details message.
        local B = SuuUI._ChatBlizzard
        B.MirrorAddonOutput(function(text)
            if not p._chat then return end
            local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
            local r, g, b
            if type(info) == "table" then r, g, b = info.r, info.g, info.b end
            -- Addon output is not conversation, so it belongs in the Log panel under the same
            -- ruling that sends loot and XP there -- not in whichever tab happens to be open.
            local log = p._chat:_systemLog()
            if log then log:AddMessage(text, r, g, b) end
        end)

        SuuUI.Settings:Watch(PLUGIN_ID, "hide_blizzard", function(on)
            if on then B.Suppress() B.Verify() else B.Restore() end
        end, PLUGIN_ID .. ".shape", { immediate = true })

        for _, key in ipairs({ "show_timestamps", "timestamp_format", "show_tags",
                              "font_size", "width", "height", "fade_channels", "fade_after" }) do
            SuuUI.Settings:Watch(PLUGIN_ID, key, function()
                if not p._chat then return end
                -- REPORTED, not swallowed. `Settings:Watch` pcalls its callback into SuuUI.Debug,
                -- which prints nothing with debug off -- so a throw in `_apply` presents as "the
                -- height slider does nothing", with no error and nothing to search for. It also
                -- explains a stale layout at the same time, because `_apply` is the only place the
                -- top row's height is stated.
                local ok, err = pcall(p._chat._apply, p._chat)
                if not ok then
                    SuuUI.Fault("chat: applying '" .. key .. "' failed: " .. tostring(err))
                end
            end, PLUGIN_ID .. ".shape")
        end

        -- Its own watcher rather than a member of the list above, because depth is not a SHAPE
        -- setting: `_apply` repaints, and trimming the store has nothing to repaint. Without this
        -- the slider silently did nothing until the next login, since the only other reader is the
        -- SetDepth call at build time.
        SuuUI.Settings:Watch(PLUGIN_ID, "history_depth", function(depth)
            if p._chat and p._chat._store then p._chat._store:SetDepth(depth) end
        end, PLUGIN_ID .. ".shape")

        -- The disc size is baked into each Avatar at construction, so this REBUILDS the rail rather
        -- than repainting it -- and the rail's own width has to be restated with it, since the
        -- window sized that cell from the old number.
        SuuUI.Settings:Watch(PLUGIN_ID, "rail_size", function()
            if p._chat then p._chat:_rebuildRail() end
        end, PLUGIN_ID .. ".shape")
    end,

    onDisable = function(p)
        SuuUI.Settings:Unwatch(PLUGIN_ID .. ".shape")
        -- Blizzard's chat comes back FIRST, so the player is never left with neither. The mirror
        -- hook cannot be uninstalled, so it is disarmed by clearing its callback.
        SuuUI._ChatBlizzard.Restore()
        SuuUI._ChatBlizzard.MirrorAddonOutput(nil)
        -- The edit box goes back BEFORE our wrapper hides, or it is left parented to a hidden frame
        -- and the player has no visible input in EITHER chat -- the exact failure this file exists
        -- to fix, arrived at from the other direction.
        SuuUI._ChatInput.Watch(nil)
        SuuUI._ChatInput.Restore()
        if p._chat then p._chat._wrapper:Hide() end
    end,
})

--- The live chat window, or nil before the plugin is enabled.
---
--- Exists so an in-game probe reads the component's OWN state rather than a frame located by
--- guessing a global name -- a reading off a guessed frame is uninterpretable, which this project
--- has already paid for once.
function SuuUI.Chat_GetWindow()
    local p = SuuUI.Plugins and SuuUI.Plugins.Get and SuuUI.Plugins:Get(PLUGIN_ID)
    return p and p._chat or nil
end

SuuUI._Chat = { PLUGIN_ID = PLUGIN_ID, SCHEMA = SCHEMA, Chat = Chat }
