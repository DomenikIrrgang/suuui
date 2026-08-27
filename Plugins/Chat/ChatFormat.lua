-- Turns a CHAT_MSG_* payload into a finished display line. PURE: no frames, no components, no
-- settings reads -- every input arrives as an argument, which is what makes ~28 event types
-- specifiable without a frame in sight.
--
-- Built on the client's own GlobalStrings rather than hand-written formats, so locale support is
-- free and the output matches what players already read. The composition shape was recovered from
-- ElvUI's Chat.lua rather than from memory; see .kiro/specs/chat-plugin.md 5b.
local format, gsub, strsub = string.format, string.gsub, string.sub
local tonumber, type = tonumber, type

local M = {}

-- Chat types whose GlobalString carries its own formatting, so the MESSAGE goes inside the format
-- string instead of being appended. Not a defensive list -- these genuinely differ.
local SPECIAL = {
    MONSTER_BOSS_EMOTE   = true,
    MONSTER_BOSS_WHISPER = true,
    PET_BATTLE_INFO      = true,
    PET_BATTLE_COMBAT_LOG = true,
}

-- The short tag each chat type shows in a mixing tab. THREE letters or fewer so the column is
-- narrow, and uppercase because the caller passes the literal string (WoW has no text-transform).
--
-- A numbered channel is deliberately absent: its tag is its NUMBER, because that is what a player
-- types (`/2`), and replacing it with letters would hide the one part of a channel's identity
-- that is actionable.
local TAGS = {
    SAY             = "SAY",
    YELL            = "YELL",
    EMOTE           = "EMO",
    TEXT_EMOTE      = "EMO",
    WHISPER         = "WSP",
    WHISPER_INFORM  = "WSP",
    PARTY           = "PTY",
    PARTY_LEADER    = "PTY",
    RAID            = "RAID",
    RAID_LEADER     = "RAID",
    RAID_WARNING    = "RW",
    GUILD           = "GLD",
    OFFICER         = "OFF",
    MONSTER_SAY     = "NPC",
    MONSTER_YELL    = "NPC",
    MONSTER_EMOTE   = "NPC",
    MONSTER_WHISPER = "NPC",
    SYSTEM          = "SYS",
    LOOT            = "LOOT",
    MONEY           = "COIN",
    SKILL           = "SKILL",
}

--- The tag for a chat type, or the channel NUMBER for a numbered channel.
-- @param chatType string
-- @param channelIndex number|nil
-- @return string|nil
function M.Tag(chatType, channelIndex)
    if chatType == "CHANNEL" then
        local n = tonumber(channelIndex)
        return n and tostring(n) or "CH"
    end
    return TAGS[chatType]
end

--- Strips the `|Hchannel:target|h[Label]|h ` prefix the group GlobalStrings carry, KEEPING the
--- link target so a channel name stays clickable.
---
--- This is a substitution rather than a deletion: a tab that renders a tag chip and the raw
--- globalstring prints the channel twice on every line. Same pattern ElvUI's ShortChannel
--- matches, which is the precedent for it being safe.
-- @param body string
-- @return string body, string|nil linkTarget, string|nil label
function M.StripChannelPrefix(body)
    if type(body) ~= "string" then return body end
    -- ONE anchored pattern, not two. This was a match plus a separate anchored gsub, and mutation
    -- testing showed the gsub's own anchor could never matter -- the match already gates it -- so
    -- the second copy was pure duplication waiting to drift out of step with the first.
    local _, stop, target, label = body:find("^|Hchannel:(.-)|h%[(.-)%]|h ")
    if not stop then return body end
    return body:sub(stop + 1), target, label
end

--- Builds the clickable player link the client's own SetItemRef resolves.
---
--- The lineID is NOT optional decoration: SetItemRef needs it to open a player's context menu,
--- and dropping it is the usual reason right-click on a name silently degrades. `name` is passed
--- through unchanged when there is no lineID to attach, so a system line still reads correctly.
-- @param name string
-- @param lineID number|nil
-- @param display string|nil  what the link shows, defaults to name
-- @return string
function M.PlayerLink(name, lineID, display)
    if type(name) ~= "string" or name == "" then return display or "" end
    if not lineID then return display or name end
    return format("|Hplayer:%s:%d|h%s|h", name, lineID, display or name)
end

--- Strips a realm suffix from a display name when it matches the player's own.
---
--- `Sulisande-Thunderstrike` is what the client hands over even for someone standing next to you,
--- and printing it is noise on every line. A DIFFERENT realm is kept, because there the suffix is
--- the information.
-- @param name string
-- @param ownRealm string|nil  the player's realm; nil strips nothing
-- @return string
function M.ShortName(name, ownRealm)
    if type(name) ~= "string" then return name end
    if type(ownRealm) ~= "string" or ownRealm == "" then return name end
    local bare, realm = name:match("^(.+)%-(.+)$")
    if not bare then return name end
    -- Realm names arrive with spaces stripped in a link but not always in the raw name, so compare
    -- both forms rather than trusting one.
    local a = realm:gsub("%s+", ""):lower()
    local b = ownRealm:gsub("%s+", ""):lower()
    if a == b then return bare end
    return name
end

--- A numbered channel's name as the chip spells it: the zone qualifier dropped.
---
--- The client names a zone channel `General - Elwynn Forest`, and the qualifier is the one part a
--- player never needs read back to them -- they are standing in it. Split on Blizzard's own
--- ` - ` separator rather than on any hyphen, because a custom channel may legitimately contain one.
-- @param name string|nil
-- @return string|nil
function M.ChannelLabel(name)
    if type(name) ~= "string" or name == "" then return name end
    local bare = name:match("^(.-)%s+%-%s+")
    if bare and bare ~= "" then return bare end
    return name
end

--- Composes the message body: the GlobalString applied to the sender, with the message.
-- @param chatType string   without the CHAT_MSG_ prefix, e.g. "GUILD"
-- @param message string
-- @param sender string     already linked and coloured by the caller
-- @param opts table|nil    { language, globals, plain }
-- @return string
function M.Body(chatType, message, sender, opts)
    opts = opts or {}
    -- Injectable for specs; falls through to the client's real globals in game.
    local globals = opts.globals or _G
    message = message or ""
    sender  = sender or ""

    -- BEFORE the globalstring lookup, deliberately: TEXT_EMOTE's message ALREADY contains the
    -- sender's name ("Thalvyn waves."), so prefixing would print it twice -- and it needs no
    -- globalstring at all, so resolving one first sends it down the unknown-type fallback and
    -- produces exactly the double name this branch exists to avoid.
    if chatType == "TEXT_EMOTE" then
        return message
    end

    -- `plain` means the ROW already carries the channel identity in its tag column, so the
    -- globalstring's own words are redundant. That is not only the `[Guild]` bracket -- it is the
    -- VERB too: `CHAT_SAY_GET` is "%s says: ", which renders as "SAY Name says: hi" beside a tag.
    -- The concept's row is `TAG Name: message`, so when a tag is drawn the body is exactly that.
    --
    -- The globalstring path survives for every type with NO tag, where its phrasing IS the
    -- content -- a boss emote, a system line, a channel notice.
    if opts.plain then
        if sender == "" then return message end
        -- A DIFFERENT language still has to appear, in the same place Blizzard puts it: right
        -- before the message. Dropping it here was a real bug -- the plain branch returned early
        -- and never reached the language path below.
        if opts.language and opts.language ~= "" then
            return sender .. ": [" .. opts.language .. "] " .. message
        end
        return sender .. ": " .. message
    end

    local header = globals["CHAT_" .. tostring(chatType) .. "_GET"]

    -- An unknown chat type has no globalstring. Returning sender plus message is the right
    -- degradation: the player still reads what was said, which beats an empty line or a raise
    -- from inside an event handler.
    if type(header) ~= "string" then
        return (sender ~= "" and (sender .. ": " .. message)) or message
    end

    if opts.language and opts.language ~= "" then
        return format(header .. "[%s] %s", sender, opts.language, message)
    end

    -- A special globalstring carries its own formatting, so the message joins the FORMAT rather
    -- than the arguments. Guarded with pcall because the message is player-supplied and a stray
    -- `%` in it would raise from inside an event handler.
    if SPECIAL[chatType] then
        local ok, out = pcall(format, header .. message, sender)
        if ok then return out end
        return message
    end

    local ok, out = pcall(format, header .. "%s", sender, message)
    if ok then return out end
    return message
end

--- The `HH:MM` (or `HH:MM:SS`, or 12-hour) stamp for a line.
---
--- A LEADING ZERO IS STRIPPED FROM THE 12-HOUR FORM: `%I` gives "02:32 PM", and the zero is
--- noise in a column that is already right-aligned.
-- @param mode string|nil  "24h" (default) | "12h" | "24hs"
-- @param when number|nil  epoch seconds; defaults to now
-- @return string
function M.Timestamp(mode, when)
    local fmt = "%H:%M"
    if mode == "24hs" then
        fmt = "%H:%M:%S"
    elseif mode == "12h" then
        fmt = "%I:%M %p"
    end
    local out = date(fmt, when)
    if mode == "12h" then out = (gsub(out, "^0", "", 1)) end
    return out
end

--- Assembles the whole line: timestamp column, tag, then the body.
---
--- Returns the tag SEPARATELY as well as inside the text, because a tab that renders the tag as
--- its own column needs the width, and one that does not needs it absent from the string. The
--- caller decides; this never guesses.
-- @param def table  { chatType, message, sender, lineID, channelIndex, language, globals }
-- @param opts table|nil { timestamps, timeFormat, tag, now }
-- @return string text, string|nil tag
function M.Line(def, opts)
    def, opts = def or {}, opts or {}
    local tag = M.Tag(def.chatType, def.channelIndex)
    local showTag = (opts.tag and tag ~= nil) or false
    local body = M.Body(def.chatType, def.message, def.sender, {
        language = def.language, globals = def.globals,
        -- When the tag column carries the channel, the globalstring's own label AND verb are both
        -- redundant. See Body.
        plain = showTag,
    })
    body = M.StripChannelPrefix(body)

    local out = body
    if showTag then out = tag .. " " .. out end
    if opts.timestamps then
        out = M.Timestamp(opts.timeFormat, opts.now) .. " " .. out
    end
    return out, tag
end

SuuUI.ChatFormat = M
