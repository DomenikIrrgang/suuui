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

-- The reopen row's label, in ONE place because the rail's expanded width is measured from it and a
-- second copy would drift from what is drawn. Deliberately short: the expanded rail is as wide as its
-- widest label, and "Closed conversations" would make every hover push the log much further than any
-- player name does. The tooltip carries the full explanation.
local REOPEN_LABEL = "Closed"

-- How many closed conversations the roster shows at once. Named rather than inline because it is the
-- whole reason the roster stays usable at three hundred conversations, and because the search field
-- that lands next has to cap its RESULTS to the same number.
local REOPEN_MAX_ROWS = 8

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
    -- OFF by default, because the concept's row has no text tag at all: it carries channel identity on
    -- a 2px coloured left border, which a ScrollingMessageFrame cannot draw. Keeping Blizzard's line
    -- colours means that identity is ALREADY on the line -- a Guild line is green, a whisper pink -- so
    -- `GLD` in front of it is the same information twice, and it is the widest thing between the
    -- timestamp and the name. The setting stays for anyone who wants the column back.
    { key = "show_tags", label = "Show Channel Tags", type = "toggle", default = false },
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
    -- The SECOND retention rule, and the one that actually bounds the SavedVariable. `history_depth`
    -- caps records per conversation while nothing caps how many conversations there are, so the total
    -- is depth x conversations and grows for as long as the player keeps meeting people. 0 means keep
    -- forever, which is why the minimum is 0 rather than 1.
    { key = "history_days", label = "Forget Conversations After (Days)", type = "slider", default = 14,
      min = 0, max = 90, step = 1 },
}

-- The per-panel message categories, APPENDED rather than written inline: every entry is generated
-- from `ChatCategories`, so adding a category is one row in that table and no edit here. Writing
-- twenty-eight toggles by hand is also how a key gets misspelled in exactly one of the two places
-- that have to agree about it.
--
-- Two SECTIONS rather than a `subtabs` entry. `PageBuilder` walks the schema linearly and a section
-- opens an accordion that swallows everything after it until the next one, so two sections give two
-- long toggle lists that are one click each to open and cannot both be open -- which is the right
-- shape for two lists the player compares against each other. A `subtabs` entry placed after the
-- existing sections would render as a control inside the last accordion's body instead.
local function appendCategories(label, panelId)
    tinsert(SCHEMA, { key = "", label = label, type = "section" })
    for _, entry in ipairs(SuuUI.ChatCategories.Schema(panelId)) do
        tinsert(SCHEMA, entry)
    end
end
appendCategories("General Panel: Messages", "general")
appendCategories("Global Panel: Messages", "global")
appendCategories("Log Panel: Messages", "log")

tinsert(SCHEMA, { key = "", label = "Internal", type = "internal" })
tinsert(SCHEMA, { key = "position", type = "position" })

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

--- Every log that addon output belongs in.
---
--- Resolved through the SAME question a real system line is routed by -- which panels accept a
--- `SYSTEM` record -- rather than being pinned to the Log. There is now a setting saying where
--- system messages go, and a `print()` from another addon is system output; answering it two
--- different ways would mean a player who put system lines in General still had to look in the Log
--- for half of them.
---
--- Falls back to `_systemLog` when routing resolves nothing, so addon output cannot be lost by a
--- player switching the `system` category off on both panels: they asked for the client's system
--- chatter to be quieter, not for another addon's error to vanish.
-- @return table  array of log handles, possibly empty
function Chat:_systemLogs()
    local out = {}
    for _, id in ipairs(SuuUI.ChatPanels.Route(self._panels, { kind = "SYSTEM" })) do
        local panel = SuuUI.ChatPanels.Find(self._panels, id)
        if panel then tinsert(out, self:_logFor(panel)) end
    end
    if #out == 0 then
        local log = self:_systemLog()
        if log then out[1] = log end
    end
    return out
end

--- Rewrites the configurable panels' group filters from the player's category settings.
---
--- The SETTINGS are the source of truth; the panel's `groups` array is a derived cache of them, so
--- this runs at build time and again on every category change. `ChatPanels.DEFAULTS` derives the
--- same list from the same table, which is what keeps a fresh profile and a configured one on one
--- code path.
---
--- Only `ChatCategories.PANELS` are touched. Guild is a single-group panel and a conversation is
--- filtered by stream, so neither has a category list to apply -- and rewriting their groups from an
--- empty answer would empty them.
function Chat:_applyCategories()
    local Cats = SuuUI.ChatCategories
    for _, panelId in ipairs(Cats.PANELS) do
        local panel = SuuUI.ChatPanels.Find(self._panels or {}, panelId)
        if panel then
            panel.groups = Cats.GroupsFor(panelId, function(catId)
                return get(Cats.Key(panelId, catId)) and true or false
            end)
        end
    end
end

--- Brings the event frame's registrations in line with what the panels now want.
---
--- A DIFF rather than a re-register, and both halves matter. Registering the new ones is what makes
--- switching a category on take effect at all -- the event set is a union over the panels' groups, so
--- a group nothing claimed was never subscribed and its messages never reached the plugin. And
--- unregistering the dropped ones is what makes switching one off actually stop the traffic rather
--- than merely filter it, which is the difference between a quiet panel and a store that keeps
--- growing with records nothing will ever show.
---
--- `PLAYER_LOGOUT` is registered separately and deliberately absent from `_registered`, so this can
--- never unregister the one event the history depends on.
function Chat:_syncEvents()
    local ev = self._events
    if not ev then return end
    local _, want = SuuUI.ChatPanels.Events(self._panels, ChatTypeGroup)
    local have = self._registered or {}
    for event in pairs(have) do
        if not want[event] then
            pcall(ev.UnregisterEvent, ev, event)
            have[event] = nil
        end
    end
    for event in pairs(want) do
        if not have[event] then
            -- pcall: an event absent on this client generation must not take the plugin down.
            pcall(ev.RegisterEvent, ev, event)
            have[event] = true
        end
    end
    self._registered = have
end

--- Repaints every panel from the store under the filters that are live now.
---
--- This is what makes a category toggle visible IMMEDIATELY instead of only affecting the next
--- message. It is affordable for exactly the reason the store holds records rather than strings: a
--- re-render is a re-route plus a re-format of what was already kept, so the player sees the loot
--- lines they already received move into the panel they just ticked.
---
--- The logs are CLEARED first. `_replayHistory` appends, so replaying onto a populated log would
--- print the entire history a second time -- and the bounded buffer would then evict the oldest half
--- of it, which looks like the toggle deleting messages.
---
--- Unread counts are deliberately NOT reset: `_bumpUnread` and `_bumpMissed` both stand down while
--- `_replaying`, so the badges survive untouched rather than being recounted from history.
function Chat:_rerender()
    if not (self._logs and self._store) then return end
    for _, log in pairs(self._logs) do log:Clear() end
    self:_replayHistory()
    self:_refreshJump()
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
    -- Evicted before serialising, because login is not the only moment history goes stale: a client
    -- left running for three weeks holds records older than the window with nothing having re-read the
    -- store since. One walk per logout, against a store already capped by depth.
    self._store:Evict()
    local blob = self._store:Serialise()
    -- The CLOSED SET rides along in the same SavedVariable, and it has to be persisted at all because
    -- closing removes the PANEL while deliberately keeping the STREAM -- so the login replay, which
    -- walks every stored record, recreated a panel for every conversation and every close was undone
    -- by a reload.
    --
    -- Here rather than in the profile because it shares the history's SCOPE and LIFETIME exactly: the
    -- streams are per-character and so are the conversations, and one write path cannot drift from
    -- itself. Only ids that still HAVE a stream are kept, or the set grows forever as old
    -- conversations are trimmed out from under it.
    local closed = {}
    for id in pairs(self._closed or {}) do
        if #self._store:Stream(id) > 0 then closed[id] = true end
    end
    blob.closed = closed
    SuuUIChatHistory = blob
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
function Chat:_render(rec, onlyPanelId)
    local targets = {}
    -- `onlyPanelId` narrows a render to a single panel, which is what REOPENING needs: the record has
    -- already been shown in General (that happened when it arrived), so replaying it through normal
    -- routing would print every line a second time there.
    if onlyPanelId then
        local only = SuuUI.ChatPanels.Find(self._panels, onlyPanelId)
        if not only then return end
        targets = { only }
    end
    for _, id in ipairs((not onlyPanelId) and (rec.panels or {}) or {}) do
        local panel = SuuUI.ChatPanels.Find(self._panels, id)
        if panel then tinsert(targets, panel) end
    end

    -- A message must never land NOWHERE. Every routed id can fail to resolve -- whisper_mode is
    -- "panel" and the conversation has not been created yet, or the player deleted the only panel
    -- that wanted this group -- and a silently dropped line is the worst outcome this module can
    -- produce, worse than one shown in the wrong place, which is at least visible and correctable.
    -- The fallback is for ROUTED records only. A narrowed replay has already resolved its one panel
    -- above, so falling back here would dump a reopened conversation's history into General.
    if #targets == 0 and not onlyPanelId then
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
            -- The RECORD'S OWN clock, never the render's. Formatting is deliberately deferred to
            -- render time so a settings change re-reads -- but that also means a replayed history
            -- line is formatted at LOGIN, and with `now` absent `date()` answers the current time:
            -- every restored line came back stamped with the moment the player logged in, the whole
            -- history reading as one instant. The plumbing existed on both sides and nothing joined
            -- it -- `Line` and `Timestamp` both document the parameter, and `at` was already stamped,
            -- persisted, and read by the age eviction.
            --
            -- `at` is epoch seconds from `time()`, never `GetTime()`, which is uptime and resets
            -- every login, so it survives the SavedVariable. It is nil only for a record written
            -- before it was stamped, and falling through to now is the honest answer there: the
            -- alternative is a blank column, and no stored clock is not the same as midnight.
            --
            -- Every other timestamp spec fires a LIVE message with the clock already staged, where
            -- this value and "now" are equal -- which is exactly why the omission rendered correctly
            -- in every test while being wrong for the only case that reads a stored line.
            now        = rec.at,
            -- A panel carrying ONE group needs no tag: the panel IS the label, so "GLD" on every
            -- line of a Guild panel is the same information twice. This is the property the
            -- per-panel render buys -- one record, two panels, two correct strings.
            tag        = self:_wantsTag(panel, rec),
            -- ALWAYS, because "time, name, colon, message -- in General and in a whisper alike" is the
            -- concept's stated rule and it is not conditional on anything. It used to ride on the tag
            -- being drawn, which coupled two unrelated things: turning the tag column off brought
            -- `says:` and `whispers:` back everywhere, which is the opposite of one row shape.
            --
            -- What tells a whisper from a say once the verb is gone is the LINE COLOUR, which is
            -- exactly how the concept does it -- colour and a coloured border, never words. Keeping
            -- Blizzard's colours is what makes that available. A line with no sender at all (a system
            -- message, a channel notice) still takes the globalstring path, where the phrasing IS the
            -- content; `Body` decides that on the sender being empty.
            labelled   = true,
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

--- Whether a panel's rows should carry a channel tag, for one record.
---
--- Two rules, and the second is an exception to the first rather than a feature of its own.
---
--- The general rule: a tag is drawn only when the panel can hold MORE THAN ONE group, because
--- otherwise it is the same word on every line and the panel itself already says it. A conversation
--- is covered by that same rule rather than by a guard of its own -- it filters by STREAM and
--- carries no groups at all, so the count is 0. A separate `panel.conversation` check was here and
--- mutation testing proved it unreachable: both branches agreed on every input.
---
--- THE EXCEPTION: a numbered channel's tag is its NUMBER, which differs line to line. So it is not a
--- label repeating what the panel already says -- it is the only channel identity the row has, since
--- `_render` passes `labelled = true` and that strips the globalstring's own `[2. Trade]` bracket.
--- Without this the Global panel would render General, Trade, LookingForGroup and every custom
--- channel as one indistinguishable run of `Name: message`, told apart only by six similar
--- ChatTypeInfo colours -- and the number is the actionable half, because `/2` is what a player
--- types to reply. Neither gate applies to it: not the group count, and not `show_tags`, whose whole
--- argument for defaulting off is that a TYPE tag repeats what the line colour already says.
-- @param panel table
-- @param rec table|nil  the record being rendered; omitted asks about the panel alone
-- @return boolean
function Chat:_wantsTag(panel, rec)
    if rec and rec.kind == "CHANNEL" then return true end
    if not get("show_tags") then return false end
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
    -- The reopen row's label counts toward the widest, or the rail expands to fit the names and
    -- clips this one. Measured whenever the row COULD exist rather than only when it does: the width
    -- is stated before the rows are rebuilt, so asking `_reopenRow` here would read the old state.
    if self._store and #self:ClosedConversations() > 0 then
        local lw = SuuUI.TextMetrics.Box(REOPEN_LABEL, font, size)
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
    -- The reopen row lives OUTSIDE `_rows`, so every per-row pass has to name it explicitly. Missed
    -- here, its label stayed on screen with the rail collapsed to discs.
    if self._reopenRow then self._reopenRow:SetShowLabel(on) end

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
    -- Not in `_rows`, so it needs its own teardown -- the rail is rebuilt on every conversation
    -- change, and without this each rebuild would leave another avatar parented to the wrapper.
    if self._reopenRow then
        self._rail:Remove(self._reopenRow)
        self._reopenRow:Destroy()
        self._reopenRow = nil
    end
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
        local isConversation = panel.conversation and true or false
        local panelName = panel.name or panel.id
        SuuUI.UISignals:Connect(av, SuuUI.UISignals.SIGNALS.CLICKED, function(button)
            -- RIGHT-CLICK CLOSES a conversation, left-click selects. No × badge, and that is a
            -- deliberate trade rather than laziness: the rail is collapsed to a disc at rest, so a
            -- close button would either sit inside a 30-unit circle already carrying an initial and an
            -- unread badge, or appear only while expanded -- which is a control that exists only when
            -- hovered, on a row whose hover ALSO drives the expansion.
            --
            -- Right-click needs no pixels and matches what the client's own chat tabs do. It is
            -- advertised in the avatar's tooltip, because a gesture nobody documents is a gesture
            -- nobody finds.
            if button == "RightButton" then
                if isConversation then self:CloseConversation(id) end
                return
            end
            self:SetActivePanel(id)
        end)
        -- Armed from a ROW's enter rather than the rail frame's, because a container's frame is not
        -- ours to attach scripts to -- and it collapses through HoverAway rather than OnLeave, which
        -- fires on the way INTO a child and would collapse the rail from under the cursor the moment
        -- it reached the name it was aiming for.
        SuuUI.UISignals:Connect(av, SuuUI.UISignals.SIGNALS.MOUSE_ENTER, function()
            -- The tooltip earns its place at REST, where the row is a bare disc carrying one initial:
            -- it is the only thing that says who `T` is. It also carries the close hint, since
            -- right-click is otherwise undiscoverable.
            --
            -- GameTooltip rather than Components.Tooltip, matching this file's hyperlink path: rail
            -- rows are destroyed and rebuilt on every conversation change, and a per-row component
            -- handle would be one more thing to free on each rebuild for a transient hint.
            local tt = GameTooltip
            if tt then
                tt:SetOwner(av:GetFrame(), "ANCHOR_RIGHT")
                tt:ClearLines()
                tt:AddLine(panelName)
                if isConversation then tt:AddLine("Right-click to close", 0.6, 0.6, 0.6) end
                tt:Show()
            end
            self:SetRailExpanded(true)
            if self._railHover then self._railHover:Arm() end
        end)
        -- The TOOLTIP hides on leave, and only the tooltip. The rail's own collapse stays with
        -- HoverAway for the reason given above -- OnLeave fires on the way INTO a child, so
        -- collapsing here would take the rail away as the cursor reached the name. A tooltip has the
        -- opposite requirement: it must go the moment the cursor leaves, and re-entering re-shows it.
        SuuUI.UISignals:Connect(av, SuuUI.UISignals.SIGNALS.MOUSE_LEAVE, function()
            if GameTooltip then GameTooltip:Hide() end
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
    -- LAST in the rail, below the conversations it reopens. Built here rather than in _rebuildRail so
    -- every path that rebuilds rows gets it -- closing a conversation is exactly the moment it has to
    -- appear, and that path goes through here.
    self:_buildReopenRow(size)
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
--- The rail's "reopen a closed conversation" row, and the flyout it opens.
---
--- SELF-HIDING: it exists only while there is something closed to reopen, so the rail carries no
--- permanent control that does nothing on a fresh login. That also makes it its own affordance -- a
--- row appearing when you close a conversation is what tells the player the history is still there.
function Chat:_buildReopenRow(size)
    if not self._store then return end
    if #self:ClosedConversations() == 0 then return end

    local av = SuuUI.Components.Avatar({
        initial   = "+",
        color     = SuuUI.Theme:GetToken("colorTextMuted"),
        label     = REOPEN_LABEL,
        size      = size,
        active    = false,
        showLabel = self._railExpanded == true,
    }, self._wrapper)

    SuuUI.UISignals:Connect(av, SuuUI.UISignals.SIGNALS.CLICKED, function()
        self:_openReopenFlyout(av)
    end)
    SuuUI.UISignals:Connect(av, SuuUI.UISignals.SIGNALS.MOUSE_ENTER, function()
        local tt = GameTooltip
        if tt then
            tt:SetOwner(av:GetFrame(), "ANCHOR_RIGHT")
            tt:ClearLines()
            tt:AddLine("Closed conversations")
            tt:AddLine("Click to reopen one and read its history", 0.6, 0.6, 0.6)
            tt:Show()
        end
        self:SetRailExpanded(true)
        if self._railHover then self._railHover:Arm() end
    end)
    SuuUI.UISignals:Connect(av, SuuUI.UISignals.SIGNALS.MOUSE_LEAVE, function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    self._rail:Add(av)
    self._reopenRow = av
end

--- Opens the closed-conversation roster next to the rail.
---
--- Rows are LABEL-ONLY: FlyoutPanel's icon slot adopts a foreign frame and does not own it, so
--- handing it an Avatar per row would make this function responsible for destroying those avatars on
--- every rebuild. A name is the whole information a player needs to pick a conversation.
function Chat:_openReopenFlyout(anchor)
    local closed = self:ClosedConversations()
    if #closed == 0 then return end

    if not self._reopenFlyout then
        self._reopenFlyout = SuuUI.Components.FlyoutPanel({
            anchorTo = anchor:GetFrame(),
            -- QUADRANT placement. The chat window is moveable and STARTS in the bottom-left corner,
            -- where a panel that always opened downward ran off the bottom of the screen. `auto` grows
            -- it toward the middle instead, so a bottom-left rail opens up and to the right.
            align    = "auto",
            -- The panel does the narrowing now, so EVERY closed conversation is handed over and the
            -- cap applies to what is DRAWN. Capping here instead would put the older ones out of
            -- reach of the search field entirely, which is the whole reason it exists.
            filter   = true,
            filterPlaceholder = "Search conversations…",
            maxRows  = REOPEN_MAX_ROWS,
            -- The disc size the concept draws, which is the RAIL's resting size rather than the
            -- rail_size setting: this roster is a list of names, not the rail itself, and a 30-unit
            -- disc per row would make eight rows taller than the log they sit over.
            iconSize = SuuUI.Theme:GetToken("sizeControlSm") or 18,
        }, self._wrapper)
    end
    -- RE-POINTED on every open, because `_buildRail` destroys and recreates the reopen row whenever the
    -- closed list changes -- which a reopen always does. The panel was constructed against the FIRST
    -- row, so after one reopen it hung off a DESTROYED frame: it opened somewhere else entirely, and
    -- closed the instant it appeared, since a frame with no rect can never read as "inside" for the
    -- hover watcher. One cause, both symptoms.
    self._reopenFlyout:SetAnchorTo(anchor:GetFrame())
    local rows = {}
    -- The flyout ADOPTS an icon frame and does not own it, so this owns them: the previous set is
    -- destroyed only AFTER SetRows has swapped the new frames in, or the destroy would tear out frames
    -- the panel is still holding.
    local fresh = {}
    for i = 1, #closed do
        -- NOT capped here: the panel caps what it DRAWS while keeping the full set searchable. The
        -- list is newest-first, so an unfiltered roster shows the conversations most likely to be
        -- wanted and typing reaches the rest.
        local c = closed[i]
        local id = c.id
        -- The age is META, in its own dim right-aligned column. It used to be glued into the label
        -- with a separator, which drew it at the NAME's size and colour -- the concept renders meta as
        -- a separate small muted column, and joining the two also made the label's measured width
        -- include text nobody is scanning for.
        -- A CLASS-COLOURED DISC per row, as the concept draws it -- the roster read as a bare list of
        -- names without one, and the disc is what makes a row recognisable at a glance the same way
        -- the rail's is.
        --
        -- Coloured through the same `_panelColor` the rail uses, given a panel definition built from
        -- the stored key, so a closed conversation cannot disagree with its own rail row about colour.
        local av = SuuUI.Components.Avatar({
            initial   = (c.name or "?"):sub(1, 1):upper(),
            color     = self:_panelColor(SuuUI.ChatPanels.Conversation(id:sub(9), c.name)),
            size      = SuuUI.Theme:GetToken("sizeControlSm") or 18,
            active    = false,
            showLabel = false,
        }, self._wrapper)
        tinsert(fresh, av)
        tinsert(rows, {
            key   = id,
            label = c.name,
            meta  = SuuUI.Readout.AgeShort(c.at),
            frame = av:GetFrame(),
            onClick = function()
                if self._reopenFlyout then self._reopenFlyout:Close() end
                self:ReopenConversation(id)
            end,
        })
    end
    self._reopenFlyout:SetRows(rows)
    for _, old in ipairs(self._reopenAvatars or {}) do old:Destroy() end
    self._reopenAvatars = fresh
    self._reopenFlyout:Open()
end

--- Every conversation the STORE remembers that has no panel open. Newest first.
---
--- Exists because closing a conversation must not be the same thing as losing it: the player closes a
--- window to clear the rail, then wants to read what someone said last night WITHOUT whispering them
--- to summon the panel back -- messaging a person to check your own logs is not an acceptable price.
---
--- Read from the STREAM KEYS rather than from a separate "recently closed" list, which is the reason
--- there is nothing extra to persist: a stream key IS the panel id (both are `whisper:<key>`), the
--- streams already survive logout in SavedVariables, and so a conversation from a previous session is
--- listed exactly like one closed a minute ago.
-- @return table  { { id, name, count } }
function Chat:ClosedConversations()
    local out = {}
    if not self._store then return out end
    for _, key in ipairs(self._store:Keys()) do
        if key:sub(1, 8) == "whisper:" and not SuuUI.ChatPanels.Find(self._panels, key) then
            local recs = self._store:Stream(key)
            local n = #recs
            if n > 0 then
                -- The name off the LAST record: it is the display name the client most recently gave
                -- for that person, and the key itself is lower-cased and realm-suffixed, so showing
                -- the key would read "thalvyn-" in the list.
                local last = recs[n]
                tinsert(out, { id = key, name = last.sender or key:sub(9), count = n,
                               seq = last.seq or 0, at = last.at })
            end
        end
    end
    -- Newest conversation first, which is the order a player scans for "who was I just talking to".
    -- `id` breaks the tie so the list cannot reorder between openings on equal sequences.
    table.sort(out, function(x, y)
        if x.seq ~= y.seq then return x.seq > y.seq end
        return x.id < y.id
    end)
    return out
end

--- Reopens a closed conversation and replays its stored history into it.
---
--- Distinct from the automatic path in `_ensureConversation`, which needs an incoming record to work
--- from. This one is driven by the PLAYER choosing a name, so it has to rebuild the panel from the
--- stream alone and then fill the log itself -- a reopened panel that came back empty would tell the
--- player their history was gone.
-- @param id string  the `whisper:<key>` id from ClosedConversations
-- @return boolean
function Chat:ReopenConversation(id)
    if type(id) ~= "string" or not self._store then return false end
    if SuuUI.ChatPanels.Find(self._panels, id) then return true end
    local recs = self._store:Stream(id)
    if #recs == 0 then return false end

    local key = id:sub(9)
    local panel = SuuUI.ChatPanels.Conversation(key, recs[#recs].sender or key)
    tinsert(self._panels, panel)
    -- No longer closed, or the next reload would close it again behind the player's back.
    if self._closed then self._closed[id] = nil end
    self:_rebuildRail()

    -- ACTIVATED BEFORE THE REPLAY, which is load-bearing rather than cosmetic ordering. `_logFor`
    -- hides a log it builds for any panel that is not the active one, so replaying first meant every
    -- restored line was added to a HIDDEN ScrollingMessageFrame -- and a hidden frame has no rect in
    -- the client, so the frame had no height to lay its lines out against and they did not settle at
    -- the bottom the way a live conversation's do. Activating first costs one frame of an empty panel
    -- and gives the replay a laid-out frame to write into. `_refreshJump` tolerates the log not
    -- existing yet, which is what makes this order safe.
    self:SetActivePanel(id)

    -- `_replaying` suppresses the same things a login replay suppresses -- no unread bump, no store
    -- write, no jump-to-bottom nudge -- because none of this is new traffic.
    self._replaying = true
    for i = 1, #recs do
        -- NARROWED to this panel: these records were already shown wherever routing sent them when
        -- they arrived, so a routed replay would print each line into General a second time.
        local ok = pcall(self._render, self, recs[i], id)
        if not ok then SuuUI.Fault("chat: a stored record in " .. id .. " could not be replayed") end
    end
    self._replaying = false

    -- The newest line is what the player must be looking at, so the replay ends AT THE BOTTOM. Needed
    -- on top of the ordering above because the log comes from the pool: `Clear` empties the buffer, and
    -- a scroll offset that outlived its messages would place the restored lines against a history that
    -- no longer exists. A login replay never showed this -- the pool is empty at login, so it gets a
    -- fresh frame at offset 0 -- which is exactly why this only went wrong on a mid-session reopen.
    local log = self:LogFor(id)
    if log and log.ScrollToBottom then log:ScrollToBottom() end
    return true
end

--- Closes one conversation panel. Returns whether anything closed.
---
--- Reopening is not a separate feature and deliberately has no button: the next whisper from that
--- person runs `_ensureConversation` again, which recreates the panel -- and because the STORE is
--- untouched, the recreated panel replays that conversation's history instead of opening blank. So
--- "close" means "put this away", not "forget this person".
---
--- Only a conversation can close; ChatPanels.Remove refuses General, Guild and Log, which are the
--- window's fixed spine. A gesture that could remove one of those would leave the player with no way
--- back short of a reload.
function Chat:CloseConversation(id)
    if not SuuUI.ChatPanels.Remove(self._panels, id) then return false end
    -- Recorded so the login replay does not recreate the panel. The STREAM is untouched, which is what
    -- keeps the history readable through the reopen roster.
    self._closed = self._closed or {}
    self._closed[id] = true

    -- The LOG goes with the panel, or its frame leaks: `_logFor` builds one per panel id and nothing
    -- else would ever free it, so closing and reopening a conversation ten times would leave ten
    -- message frames parented to the log box.
    --
    -- RELEASED to the pool, not destroyed: `_logFor` acquires it from `chat.log`, so destroying it
    -- would hand the pool a dead handle to reissue on the next conversation.
    local log = self._logs and self._logs[id]
    if log then
        self._logBox:Remove(log)
        -- CLEARED BEFORE RELEASE, and this is a privacy fix rather than tidiness. The pool's reset is
        -- generic -- hide, unanchor, drop scripts -- and knows nothing about a message buffer, so a
        -- released log kept every line it held. Measured: close Alpha's conversation, then have Beta
        -- whisper, and Beta's panel opened showing Alpha's message. One person's private conversation
        -- rendered in another's window.
        if log.Clear then log:Clear() end
        SuuUI.Pool:Release("chat.log", log)
        self._logs[id] = nil
    end
    -- Unread state goes too. Left behind, a reopened panel would inherit a count from before it was
    -- closed and show a badge for messages the player has already dealt with.
    --
    -- `_missed` is deliberately NOT touched: it is one counter for the jump-to-bottom badge on the
    -- ACTIVE log, not a per-panel table, so clearing it here would reset a badge about a different
    -- panel entirely.
    if self._unread then self._unread[id] = nil end

    -- Falling back to General rather than to whatever is adjacent: the active panel just ceased to
    -- exist, and "the tab next to the one you closed" is a different answer every time depending on
    -- how many conversations happen to be open.
    if self._active == id then
        local first = SuuUI.ChatPanels.Find(self._panels, "general") or self._panels[1]
        if first then self:SetActivePanel(first.id) end
    end
    self:_rebuildRail()
    return true
end

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

    -- A conversation the player CLOSED stays closed across a reload, and the gate is `_replaying`
    -- rather than unconditional: the login replay must not undo a close, while a LIVE whisper from
    -- that person is exactly the event that should bring the panel back. So the flag is cleared here
    -- on the live path -- otherwise the panel would reopen and the store would still call it closed,
    -- and the next reload would close it again.
    if self._closed and self._closed[id] then
        if self._replaying then return nil end
        self._closed[id] = nil
    end

    local panel = SuuUI.ChatPanels.Conversation(rec.conversation, rec.sender)
    tinsert(self._panels, panel)
    -- REPLAY what the store already holds for this conversation, so a panel the player closed and
    -- that a new whisper reopens comes back with its context rather than one orphaned line. Skipped
    -- during the login replay, where `_replayHistory` is already walking every record and this would
    -- render each one twice.
    --
    -- Before the incoming record is rendered, so history sits ABOVE the message that reopened it.
    if not self._replaying and self._store then
        local prior = self._store:Stream(id)
        if #prior > 0 then
            self._replaying = true
            for i = 1, #prior do
                -- STRICTLY OLDER than the record being ingested. By the time this runs the incoming
                -- record is ALREADY in the stream, so replaying the whole stream rendered it here and
                -- the caller rendered it again -- one whisper, printed twice.
                local old = prior[i]
                if not (rec.seq and old.seq and old.seq >= rec.seq) then
                    pcall(self._render, self, old, id)
                end
            end
            self._replaying = false
            -- SETTLED AT THE BOTTOM, exactly as `ReopenConversation` does. This panel is deliberately
            -- NOT activated -- a new whisper must not yank the player away from what they are reading
            -- -- so unlike that path the log stays hidden and cannot be laid out here. The offset is
            -- the part that survives to the moment it IS shown, and 0 is what makes the newest line
            -- the one they land on. Not done from `SetActivePanel`, which must preserve a scroll
            -- position the player chose by hand.
            local log = self:LogFor(id)
            if log and log.ScrollToBottom then log:ScrollToBottom() end
        end
    end
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
    -- Applied BEFORE the store and the replay. The panels' filters decide what the replay routes, so
    -- deriving them afterwards would repaint the whole history under the shipped defaults and only
    -- honour the player's categories from the next live message onward.
    self:_applyCategories()
    -- Built from the SavedVariable rather than empty, which is what makes history survive a logout
    -- and is the whole reason records carry a sequence. `Restore` tolerates nil and a hand-edited
    -- blob by yielding an empty store, so a fresh install and a returning player are ONE path.
    --
    -- The blob's own depth is deliberately discarded in favour of the SETTING: a player who lowered
    -- the slider between sessions expects the next login to trim, not to honour the depth that was
    -- in force when the history was written.
    self._store  = SuuUI.ChatStore.Restore(SuuUIChatHistory)
    self._store:SetDepth(get("history_depth"))
    -- Applied for the same reason as the depth above: the SETTING wins over whatever window the blob
    -- was written under, so lowering the slider between sessions evicts on the next login. Restore has
    -- already evicted using the blob's own value, so this only ever tightens or relaxes that result.
    self._store:SetMaxAge((tonumber(get("history_days")) or 0) * 86400)
    -- Read BEFORE the replay, since the replay is what would otherwise recreate every closed panel.
    -- Copied rather than aliased: the blob is replaced wholesale on the next save, and aliasing it
    -- would leave this table pointing at a discarded one.
    self._closed = {}
    if type(SuuUIChatHistory) == "table" and type(SuuUIChatHistory.closed) == "table" then
        for id in pairs(SuuUIChatHistory.closed) do
            if type(id) == "string" then self._closed[id] = true end
        end
    end
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
    self._events = ev
    -- Through `_syncEvents` rather than a loop of its own, so the first registration and every later
    -- category change walk ONE code path. A second loop here would be the copy that stops agreeing
    -- with the diff the moment either is touched.
    self._registered = {}
    self:_syncEvents()

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
            -- Addon output is system output, so it goes wherever the player put system messages --
            -- resolved through the same routing a real SYSTEM line takes rather than pinned to the
            -- Log, so the two cannot give different answers to one question.
            for _, log in ipairs(p._chat:_systemLogs()) do
                log:AddMessage(text, r, g, b)
            end
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

        -- Same reasoning as the depth watcher: nothing to repaint, and without this the slider would
        -- silently do nothing until the next login. The rail is rebuilt afterwards because eviction can
        -- drop a whole conversation, and a closed one that is gone must stop being offered for reopen.
        SuuUI.Settings:Watch(PLUGIN_ID, "history_days", function(days)
            local c = p._chat
            if not (c and c._store) then return end
            c._store:SetMaxAge((tonumber(days) or 0) * 86400)
            c:_rebuildRail()
        end, PLUGIN_ID .. ".shape")

        -- The disc size is baked into each Avatar at construction, so this REBUILDS the rail rather
        -- than repainting it -- and the rail's own width has to be restated with it, since the
        -- window sized that cell from the old number.
        SuuUI.Settings:Watch(PLUGIN_ID, "rail_size", function()
            if p._chat then p._chat:_rebuildRail() end
        end, PLUGIN_ID .. ".shape")

        -- One watcher per category key, DERIVED from ChatCategories rather than listed: a category
        -- added to that table is watched without anyone remembering to come back here, and the
        -- failure that avoids is a toggle that stores a value nothing reacts to -- which reads as
        -- the setting being broken rather than as a missing subscription.
        --
        -- Three things happen, in this order, and none is optional. The filter is re-derived, or the
        -- panel keeps showing what it showed. The event registrations are diffed, or a newly-ticked
        -- category's messages never reach the plugin at all -- the event set is a union over the
        -- panels' groups, so nothing was subscribed to it. And the panels are repainted, or the
        -- change appears to do nothing until the next message happens to arrive.
        for _, key in ipairs(SuuUI.ChatCategories.Keys()) do
            SuuUI.Settings:Watch(PLUGIN_ID, key, function()
                local c = p._chat
                if not c then return end
                -- REPORTED, not swallowed: `Settings:Watch` pcalls into SuuUI.Debug, which prints
                -- nothing with debug off, so a throw here would present as one checkbox silently
                -- doing nothing while the rest worked.
                local ok, err = pcall(function()
                    c:_applyCategories()
                    c:_syncEvents()
                    c:_rerender()
                end)
                if not ok then
                    SuuUI.Fault("chat: applying '" .. key .. "' failed: " .. tostring(err))
                end
            end, PLUGIN_ID .. ".shape")
        end
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
