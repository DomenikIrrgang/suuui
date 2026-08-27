local ipairs, pairs, type, tostring = ipairs, pairs, type, tostring
local tinsert, tremove, tconcat = table.insert, table.remove, table.concat

local M = {}

--[[ ===========================================================================================
     The chat DATA MODEL. Pure: no frames, no client calls, no formatting.

     A chat event becomes a RECORD -- the structured facts the client gave us -- which is appended
     to a STREAM. A panel is a VIEW over streams and formats records at RENDER time.

     The first build did none of this: it formatted an event into a string and pushed it straight
     into one ScrollingMessageFrame, which is the cheapest thing that shows a line and is a dead
     end for everything asked of it since.

     Four things a string cannot do, each of which is a requirement rather than a nice-to-have:

       * BE IN TWO PANELS AT ONCE. A whisper belongs in its conversation AND (optionally) in
         General; a channel line belongs in its own panel and in an "everything" panel if the
         player makes one. With one formatted string owned by one frame, that means formatting
         and storing the same message N times and hoping the copies agree.
       * SURVIVE A PANEL BEING RE-POINTED. Change what a panel shows and its existing lines have
         to be re-derived. A frame full of strings has nothing left to re-derive FROM -- the
         sender, the channel and the type were consumed at format time.
       * BE FILTERED. A filter needs fields. `"09:24 SAY Sulisande: test"` has none: matching a
         sender means parsing back out of presentation, which breaks the moment the timestamp
         format or the tag setting changes.
       * PERSIST. A formatted string bakes in the player's timestamp format, tag visibility and
         the client's locale, so a stored one is wrong the moment any of those change. Records are
         plain tables of primitives -- serialisable as they are, and re-rendered under whatever
         settings are live at the time.

     So: RECORD is the unit, STREAM is the retention unit, PANEL is a view. Formatting is a pure
     function of (record, panel options) applied on the way to the screen and never stored.
     =========================================================================================== ]]

--- A stream is the retention unit: one channel, or one conversation with one player.
---
--- Keyed rather than indexed, and the key is derived from the message rather than assigned, so
--- the same conversation lands in the same stream across sessions -- which is what makes
--- "history per channel / whisper" storable at all. This is the generalisation of
--- ChatRouting.ConversationKey, which solved exactly this for whispers.
-- @param rec table
-- @return string
function M.StreamKey(rec)
    rec = rec or {}
    local kind = rec.kind or "unknown"
    if rec.conversation and rec.conversation ~= "" then
        return "whisper:" .. rec.conversation
    end
    -- A numbered channel's identity is its NUMBER, not its name: a player renames nothing but
    -- joins and leaves, and the name is localized while the number is not.
    if rec.channelIndex and rec.channelIndex ~= 0 then
        return "channel:" .. tostring(rec.channelIndex)
    end
    return "type:" .. kind:lower()
end

--- Normalises a chat event's facts into a record. PURE: every client-dependent value is passed
--- in, so the shape of a record has one definition and that definition is testable without a
--- client at all.
---
--- Note what is NOT here: no timestamp format, no tag, no colour, no assembled line. A record is
--- what the client SAID; how it reads is a render-time decision, which is what lets one record
--- appear in two panels with different settings and survive the player changing either.
-- @param f table  { kind, message, sender, senderFull, language, channel, channelIndex,
--                   lineID, guid, conversation, at }
-- @return table
function M.Record(f)
    f = f or {}
    local rec = {
        kind         = f.kind or "UNKNOWN",
        message      = f.message or "",
        -- Both names are kept. The display name has the player's own realm stripped; the full one
        -- is what a whisper, an invite and a context menu resolve against, so discarding it would
        -- make a stored cross-realm conversation unreplyable after a reload.
        sender       = f.sender or "",
        senderFull   = f.senderFull or f.sender or "",
        -- Already gated to a language the player does NOT speak by the caller: storing the raw
        -- one would put "[Common]" back on every line the moment a panel re-rendered.
        language     = f.language,
        channel      = f.channel,
        channelIndex = f.channelIndex,
        lineID       = f.lineID,
        -- The sender's GUID, which is the only route to their class -- and therefore to a
        -- class-coloured name. Stored now even though nothing reads it yet, because it is not
        -- recoverable later: the event is the one place the client offers it.
        guid         = f.guid,
        conversation = f.conversation,
        at           = f.at,
    }
    rec.stream = M.StreamKey(rec)
    return rec
end

local StoreMeta = {}
StoreMeta.__index = StoreMeta

--- Trims a stream to a cap, oldest first.
---
--- The floor of 0 is not decoration. `while #s > depth` with a NEGATIVE depth NEVER TERMINATES:
--- `#s` bottoms out at 0, `tremove` on an empty table is a no-op, and `0 > -1` stays true forever.
--- Both callers now reject a non-positive depth, so this is a second barrier rather than the only
--- one -- kept because it is a single comparison and the alternative hung a mutation run for 67
--- minutes with no output.
local function trim(s, depth)
    local cap = (type(depth) == "number" and depth > 0) and depth or 0
    while #s > cap do tremove(s, 1) end
end

--- Creates a message store.
---
--- `depth` is the per-stream cap, NOT a global one, and that distinction is the point: a busy
--- Trade channel must not be able to evict a whisper. Blizzard keeps one buffer per frame and a
--- quiet conversation ages out behind traffic it has nothing to do with.
-- @param opts table|nil  { depth }
-- @return table  store handle
function M.NewStore(opts)
    opts = opts or {}
    -- Validated like SetDepth's, because the constructor is a reachable route to the same hazard:
    -- NewStore({ depth = -1 }) reached trim with a negative cap, and before trim grew its floor
    -- that spun forever. Two barriers on purpose -- the floor stays even though this makes it
    -- unreachable, because it is one comparison and the alternative cost 67 minutes once.
    local depth = opts.depth
    if type(depth) ~= "number" or depth < 1 then depth = 50 end
    return setmetatable({
        _streams = {},
        _order   = {},
        -- 50 per stream is the shipped default. Deliberately modest: it is per stream and there
        -- are many streams, so the total is the interesting number, and a player who wants deep
        -- scrollback raises it rather than paying for it in every conversation by default.
        _depth   = math.floor(depth),
        _seq     = 0,
    }, StoreMeta)
end

--- The per-stream retention cap.
function StoreMeta:GetDepth() return self._depth end

--- Sets the per-stream cap, trimming every stream that is now over it.
---
--- Lowering it trims IMMEDIATELY rather than waiting for the next message: a player who drops the
--- depth to free memory has asked for the memory back now, and a stream that only shrinks when
--- someone talks in it would never shrink at all in the quiet ones -- which are exactly the
--- streams holding the oldest records.
-- @param depth number
function StoreMeta:SetDepth(depth)
    if type(depth) ~= "number" or depth < 1 then return end
    self._depth = math.floor(depth)
    for _, s in pairs(self._streams) do trim(s, self._depth) end
end

--- Appends a record, returning it plus its stream key.
---
--- The record is STAMPED with a monotonic sequence number, which is what gives a total order
--- across streams. A timestamp cannot: two messages inside one second are common, `time()` has
--- one-second resolution, and a panel merging several streams has to interleave them in the order
--- they actually arrived or a conversation reads out of sequence.
-- @param rec table
-- @return table, string
function StoreMeta:Add(rec)
    rec = rec or {}
    self._seq = self._seq + 1
    rec.seq = self._seq
    return self:_insert(rec)
end

--- Inserts a record into its stream WITHOUT stamping a sequence number.
---
--- Split out from Add because a RESTORED record must KEEP the sequence it was saved with. Restore
--- walks stream by stream, so re-adding through Add renumbered from 1 and a restored history came
--- back as all-of-one-stream-then-the-next, losing the order the messages actually arrived in.
function StoreMeta:_insert(rec)
    local key = rec.stream or M.StreamKey(rec)
    rec.stream = key

    local s = self._streams[key]
    if not s then
        s = {}
        self._streams[key] = s
        -- Insertion order is kept separately: `pairs` order is hash order, so a panel built by
        -- walking the streams table would list its sources differently between logins. The same
        -- reason ChatRouting's tab groups are an ordered array and never a hash.
        tinsert(self._order, key)
    end
    tinsert(s, rec)
    trim(s, self._depth)
    return rec, key
end

--- One stream's records, oldest first. Returns a COPY.
---
--- A copy because the internal table is what the next Add trims: a caller holding the live one
--- would see records vanish from under it mid-render, and could reorder the stream with no
--- retention behind it. Same contract as Container:GetPadding and ItemCache:Find.
-- @param key string
-- @return table
function StoreMeta:Stream(key)
    local s = self._streams[key]
    if not s then return {} end
    local out = {}
    for i = 1, #s do out[i] = s[i] end
    return out
end

--- Every stream key, in the order the streams were first written to.
-- @return table
function StoreMeta:Keys()
    local out = {}
    for i = 1, #self._order do out[i] = self._order[i] end
    return out
end

function StoreMeta:StreamCount() return #self._order end

function StoreMeta:Count(key)
    local s = self._streams[key]
    return s and #s or 0
end

--- Every record any stream holds, in arrival order across all of them.
---
--- This is what a panel reads: it accepts a set of streams and needs them interleaved, so the
--- merge happens here once rather than in every panel. Bounded by `limit` from the END, because a
--- panel shows the most recent N and walking the whole store to throw the front away is the cost
--- this argument exists to avoid.
-- @param opts table|nil  { streams = { key = true }, limit }
-- @return table
function StoreMeta:Records(opts)
    opts = opts or {}
    local want = opts.streams
    local merged = {}
    for i = 1, #self._order do
        local key = self._order[i]
        if not want or want[key] then
            local s = self._streams[key]
            for j = 1, #s do tinsert(merged, s[j]) end
        end
    end
    -- Sorted by the sequence stamp rather than by insertion, because the streams were walked one
    -- after another: concatenating them leaves each stream internally ordered and the whole thing
    -- globally wrong.
    table.sort(merged, function(a, b) return (a.seq or 0) < (b.seq or 0) end)

    local limit = opts.limit
    if type(limit) == "number" and limit > 0 and #merged > limit then
        local out = {}
        for i = #merged - limit + 1, #merged do tinsert(out, merged[i]) end
        return out
    end
    return merged
end

--- Drops one stream, or everything when no key is given.
-- @param key string|nil
function StoreMeta:Clear(key)
    if key == nil then
        self._streams, self._order = {}, {}
        return
    end
    if self._streams[key] == nil then return end
    self._streams[key] = nil
    for i = #self._order, 1, -1 do
        if self._order[i] == key then tremove(self._order, i) end
    end
end

--- Serialises the store to a plain table for SavedVariables.
---
--- Records only -- never a formatted line, for the reason in this file's header: a stored string
--- is wrong as soon as the timestamp format, the tag setting or the locale changes, while a
--- record re-renders correctly under whatever is live at load time.
---
--- The sequence counter goes with it so a rehydrated store keeps ordering rather than restarting
--- at 1 and interleaving this session's messages underneath the last one's.
-- @return table
function StoreMeta:Serialise()
    local out = { depth = self._depth, seq = self._seq, order = self:Keys(), streams = {} }
    for _, key in ipairs(self._order) do
        out.streams[key] = self:Stream(key)
    end
    return out
end

--- Rebuilds a store from Serialise's output. A malformed or absent blob yields an empty store
--- rather than raising -- this runs at login, off a SavedVariable a player may have hand-edited.
-- @param blob table|nil
-- @return table  store handle
function M.Restore(blob)
    local store = M.NewStore({ depth = type(blob) == "table" and blob.depth or nil })
    if type(blob) ~= "table" or type(blob.streams) ~= "table" then return store end

    local highest = 0
    local order = type(blob.order) == "table" and blob.order or {}
    local seen = {}
    for _, key in ipairs(order) do seen[key] = true end
    -- A key present in `streams` but missing from `order` is still restored: the two disagreeing
    -- means a truncated write, and dropping the records would turn a partial save into a lost
    -- history. Order for those is unspecified, which is why the records carry their own seq.
    for key in pairs(blob.streams) do
        if not seen[key] then tinsert(order, key) end
    end

    for _, key in ipairs(order) do
        local recs = blob.streams[key]
        if type(recs) == "table" then
            for _, rec in ipairs(recs) do
                if type(rec) == "table" then
                    -- Marked so a renderer can dim rehydrated lines and draw a session divider:
                    -- history from a previous login must not read as live conversation.
                    rec.restored = true
                    rec.stream = rec.stream or key
                    -- _insert, NOT Add: a restored record keeps its saved sequence, so records
                    -- from different streams stay interleaved as they arrived.
                    if type(rec.seq) ~= "number" then
                        -- A blob predating sequences, or hand-edited. Put it past everything
                        -- stored so far rather than at the front.
                        highest = highest + 1
                        rec.seq = highest
                    elseif rec.seq > highest then
                        highest = rec.seq
                    end
                    store:_insert(rec)
                end
            end
        end
    end
    -- Restored AFTER the adds, which have been re-stamping seq from 1. Keeping the stored counter
    -- means the next live message sorts after the restored ones rather than among them.
    -- The next live message must outrank every restored one, so the counter resumes at the
    -- highest sequence actually present -- or at the saved counter when that is higher, which it
    -- is whenever trimming discarded records that had already consumed numbers.
    store._seq = highest
    if type(blob.seq) == "number" and blob.seq > store._seq then store._seq = blob.seq end
    return store
end

SuuUI.ChatStore = M
