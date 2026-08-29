-- ChatStore and ChatPanels: the pure data model behind the chat. A record is the unit, a stream
-- is the retention unit, and a panel is a view -- so these specs involve no frames at all.
local H = require("harness")

describe("ChatStore", function()
    before_each(function() H.setup() end)

    local function S() return H.SuuUI.ChatStore end
    local function rec(kind, msg, extra)
        local f = { kind = kind, message = msg }
        for k, v in pairs(extra or {}) do f[k] = v end
        return S().Record(f)
    end

    describe("Record", function()
        it("keeps the structured facts and NO presentation", function()
            local r = rec("SAY", "test", { sender = "Sulisande", senderFull = "Sulisande-Realm" })
            expect(r.kind).eq("SAY")
            expect(r.message).eq("test")
            expect(r.sender).eq("Sulisande")
            expect(r.senderFull).eq("Sulisande-Realm")
            -- A record must carry nothing render-time: a stored line would freeze the player's
            -- timestamp format and the client's locale into the history.
            expect(r.text).as("no assembled line").eq(nil)
            expect(r.timestamp).as("no formatted timestamp").eq(nil)
        end)

        it("stores the GUID, which is the only route to a class colour", function()
            -- Nothing reads it yet. It is stored because it is not recoverable later: the event is
            -- the one place the client offers it.
            expect(rec("SAY", "x", { guid = "Player-1-ABC" }).guid).eq("Player-1-ABC")
        end)

        it("defaults senderFull to sender when only one is known", function()
            expect(rec("SAY", "x", { sender = "Thalvyn" }).senderFull).eq("Thalvyn")
        end)
    end)

    describe("StreamKey", function()
        it("keys a conversation by its participant", function()
            expect(S().StreamKey({ kind = "WHISPER", conversation = "sulisande-realm" }))
                .eq("whisper:sulisande-realm")
        end)

        it("keys a numbered channel by its NUMBER, not its name", function()
            -- A player renames nothing but joins and leaves, and the name is localized while the
            -- number is not.
            expect(S().StreamKey({ kind = "CHANNEL", channel = "Trade", channelIndex = 2 }))
                .eq("channel:2")
        end)

        it("falls back to the type", function()
            expect(S().StreamKey({ kind = "GUILD" })).eq("type:guild")
        end)

        it("prefers the conversation over the channel index", function()
            -- A whisper carries a channel index of 0, but a defensive caller may pass anything;
            -- the conversation is the stronger identity either way.
            expect(S().StreamKey({ kind = "WHISPER", conversation = "a-b", channelIndex = 7 }))
                .eq("whisper:a-b")
        end)
    end)

    describe("retention", function()
        it("caps PER STREAM, so a busy channel cannot evict a whisper", function()
            local store = S().NewStore({ depth = 3 })
            for i = 1, 10 do
                store:Add(rec("CHANNEL", "trade " .. i, { channelIndex = 2 }))
            end
            store:Add(rec("WHISPER", "hey", { conversation = "sul-realm" }))
            expect(store:Count("channel:2")).as("trimmed to the cap").eq(3)
            expect(store:Count("whisper:sul-realm"))
                .as("a quiet conversation is untouched by traffic it has nothing to do with")
                .eq(1)
        end)

        it("EVICTS records older than the age cap", function()
            -- The second, orthogonal cap. Depth alone cannot bound the store, because it caps records
            -- per stream while nothing caps the number of streams.
            local now = 1000000
            local store = S().NewStore({ maxAge = 86400 })
            store:Add(rec("WHISPER", "old", { conversation = "a", at = now - 90000 }))
            store:Add(rec("WHISPER", "new", { conversation = "a", at = now - 100 }))
            store:Evict(now)
            local left = store:Stream("whisper:a")
            expect(#left).as("only the record inside the window survives").eq(1)
            expect(left[1].message).eq("new")
        end)

        it("DROPS a stream the eviction emptied, not just its records", function()
            -- The half that actually solves the problem. Evicting only records shrinks the bytes while
            -- `_order` keeps every conversation key for ever, so the login replay still walks all of
            -- them and the file still grows without bound.
            local now = 1000000
            local store = S().NewStore({ maxAge = 86400 })
            store:Add(rec("WHISPER", "old", { conversation = "gone", at = now - 90000 }))
            store:Add(rec("WHISPER", "recent", { conversation = "kept", at = now - 100 }))
            expect(store:StreamCount()).eq(2)
            expect(store:Evict(now)).as("reports what it dropped").eq(1)
            expect(store:StreamCount()).as("the emptied stream is gone").eq(1)
            local keys = store:Keys()
            for i = 1, #keys do
                expect(keys[i] == "whisper:gone").as("and gone from the ORDERED key list too").eq(false)
            end
        end)

        it("KEEPS a record with no timestamp", function()
            -- `at` is stamped as `type(time) == "function" and time() or nil`, so it can legitimately
            -- be absent. Deleting on missing data is the destructive direction.
            local now = 1000000
            local store = S().NewStore({ maxAge = 86400 })
            store:Add(rec("WHISPER", "unstamped", { conversation = "a" }))
            store:Evict(now)
            expect(store:Count("whisper:a")).as("kept rather than silently deleted").eq(1)
        end)

        it("evicts NOTHING when the cap is 0", function()
            local now = 1000000
            local store = S().NewStore({ maxAge = 0 })
            store:Add(rec("WHISPER", "ancient", { conversation = "a", at = now - 99999999 }))
            expect(store:Evict(now)).eq(0)
            expect(store:Count("whisper:a")).as("0 means keep forever").eq(1)
        end)

        it("SetMaxAge evicts immediately rather than at the next message", function()
            -- Same reasoning as SetDepth: the streams holding the oldest records are the quiet ones
            -- nobody is going to talk in, so waiting for a message would never free them.
            local store = S().NewStore()
            local now = (H.env.time and H.env.time()) or 1000000
            store:Add(rec("WHISPER", "old", { conversation = "a", at = now - 90000 }))
            store:SetMaxAge(86400)
            expect(store:GetMaxAge()).eq(86400)
            expect(store:StreamCount()).as("evicted on the spot").eq(0)
        end)

        it("survives a SAVE and RESTORE carrying the age cap, evicting on the way in", function()
            -- Restore must evict before the plugin replays: the whole point is that a conversation the
            -- player stopped using costs neither a rebuilt panel nor a walk over its records.
            local now = (H.env.time and H.env.time()) or 1000000
            local store = S().NewStore({ maxAge = 86400 })
            store:Add(rec("WHISPER", "old", { conversation = "a", at = now - 90000 }))
            store:Add(rec("WHISPER", "new", { conversation = "b", at = now - 60 }))
            local blob = store:Serialise()
            expect(blob.maxAge).as("the cap is persisted").eq(86400)
            local back = S().Restore(blob)
            expect(back:GetMaxAge()).eq(86400)
            expect(back:StreamCount()).as("the stale conversation never reaches the replay").eq(1)
            expect(back:Count("whisper:b")).eq(1)
        end)

        it("keeps the NEWEST records when it trims", function()
            local store = S().NewStore({ depth = 2 })
            for i = 1, 5 do store:Add(rec("SAY", "m" .. i)) end
            local s = store:Stream("type:say")
            expect(s[1].message).eq("m4")
            expect(s[2].message).eq("m5")
        end)

        it("defaults to 50 per stream", function()
            expect(S().NewStore():GetDepth())
                .as("modest on purpose: it is per stream, and there are many streams").eq(50)
        end)

        it("trims IMMEDIATELY when the depth is lowered", function()
            -- A stream that only shrank on its next message would never shrink in the quiet ones,
            -- which are exactly the streams holding the oldest records.
            local store = S().NewStore({ depth = 10 })
            for i = 1, 10 do store:Add(rec("SAY", "m" .. i)) end
            store:SetDepth(3)
            expect(store:Count("type:say")).eq(3)
        end)

        it("refuses a nonsense depth at CONSTRUCTION, which is a route to the hang", function()
            -- NewStore had no validation at all, so NewStore({ depth = -1 }) reached the trim loop
            -- with a negative cap. `while #s > -1` never terminates: #s bottoms out at 0 and
            -- 0 > -1 stays true. That spun a mutation run for 67 minutes with no output.
            for _, bad in ipairs({ -1, 0, "lots" }) do
                local store = S().NewStore({ depth = bad })
                expect(store:GetDepth()).as("falls back to the default").eq(50)
                store:Add(rec("SAY", "still works"))
                expect(store:Count("type:say")).as("and does not hang or discard").eq(1)
            end
        end)

        it("refuses a nonsense depth rather than emptying every stream", function()
            local store = S().NewStore({ depth = 5 })
            store:Add(rec("SAY", "x"))
            store:SetDepth(0)
            store:SetDepth(-1)
            store:SetDepth("lots")
            expect(store:GetDepth()).eq(5)
            expect(store:Count("type:say")).eq(1)
        end)
    end)

    describe("ordering", function()
        it("interleaves streams by ARRIVAL, not by stream", function()
            local store = S().NewStore()
            store:Add(rec("SAY", "first"))
            store:Add(rec("GUILD", "second"))
            store:Add(rec("SAY", "third"))
            local all = store:Records()
            expect(#all).eq(3)
            expect(all[1].message).eq("first")
            expect(all[2].message)
                .as("concatenating streams would put both SAY lines together").eq("second")
            expect(all[3].message).eq("third")
        end)

        it("stamps a monotonic sequence, because time() cannot order within a second", function()
            local store = S().NewStore()
            local a = store:Add(rec("SAY", "a"))
            local b = store:Add(rec("SAY", "b"))
            expect(b.seq).gt(a.seq)
        end)

        it("lists stream keys in first-write order, never hash order", function()
            local store = S().NewStore()
            store:Add(rec("GUILD", "g"))
            store:Add(rec("SAY", "s"))
            local keys = store:Keys()
            expect(keys[1]).eq("type:guild")
            expect(keys[2]).eq("type:say")
        end)
    end)

    describe("reading", function()
        it("scopes to a set of streams, which is what a panel does", function()
            local store = S().NewStore()
            store:Add(rec("SAY", "s"))
            store:Add(rec("GUILD", "g"))
            local only = store:Records({ streams = { ["type:guild"] = true } })
            expect(#only).eq(1)
            expect(only[1].message).eq("g")
        end)

        it("limits from the END, because a panel shows the most recent N", function()
            local store = S().NewStore()
            for i = 1, 6 do store:Add(rec("SAY", "m" .. i)) end
            local last = store:Records({ limit = 2 })
            expect(#last).eq(2)
            expect(last[1].message).eq("m5")
            expect(last[2].message).eq("m6")
        end)

        it("hands out a COPY of a stream", function()
            local store = S().NewStore()
            store:Add(rec("SAY", "x"))
            local a = store:Stream("type:say")
            table.remove(a, 1)
            expect(store:Count("type:say"))
                .as("the internal table is what the next Add trims").eq(1)
        end)

        it("answers an unknown stream with an empty list, not nil", function()
            expect(#S().NewStore():Stream("type:nothing")).eq(0)
        end)
    end)

    describe("persistence", function()
        it("round-trips records through Serialise and Restore", function()
            local store = S().NewStore({ depth = 7 })
            store:Add(rec("GUILD", "kara?", { sender = "Thalvyn" }))
            store:Add(rec("WHISPER", "hey", { conversation = "sul-realm" }))

            local back = S().Restore(store:Serialise())
            expect(back:GetDepth()).eq(7)
            expect(back:Count("type:guild")).eq(1)
            expect(back:Count("whisper:sul-realm")).eq(1)
            expect(back:Stream("type:guild")[1].message).eq("kara?")
            expect(back:Stream("type:guild")[1].sender).eq("Thalvyn")
        end)

        it("marks restored records so a renderer can dim them", function()
            local store = S().NewStore()
            store:Add(rec("SAY", "old"))
            local back = S().Restore(store:Serialise())
            expect(back:Stream("type:say")[1].restored)
                .as("history from a previous login must not read as live conversation").eq(true)
        end)

        it("keeps restored records INTERLEAVED across streams", function()
            -- The defect a survivor exposed. Restore walks stream by stream, so re-stamping the
            -- sequence from 1 returned a history as all-of-guild-then-all-of-say -- losing the
            -- order the messages actually arrived in. Carrying the counter over looked like dead
            -- code precisely because the records it sorts after had been renumbered underneath it.
            local store = S().NewStore()
            store:Add(rec("SAY", "say-1"))
            store:Add(rec("GUILD", "guild-1"))
            store:Add(rec("SAY", "say-2"))
            store:Add(rec("GUILD", "guild-2"))

            local back = S().Restore(store:Serialise())
            local msgs = {}
            for i, r in ipairs(back:Records()) do msgs[i] = r.message end
            expect(table.concat(msgs, ","))
                .as("restored history must read in arrival order, not stream by stream")
                .eq("say-1,guild-1,say-2,guild-2")
        end)

        it("a live message sorts AFTER restored ones", function()
            -- The stored counter is carried over. Restarting at 1 would interleave this session's
            -- messages underneath the last one's.
            local store = S().NewStore()
            for i = 1, 3 do store:Add(rec("SAY", "old" .. i)) end
            local back = S().Restore(store:Serialise())
            back:Add(rec("SAY", "new"))
            local all = back:Records()
            expect(all[#all].message).eq("new")
        end)

        it("a live message outranks a TRIMMED history's consumed numbers", function()
            -- The case where the saved counter genuinely exceeds the records present: 6 messages
            -- arrived, the cap kept 2, so the counter is 6 while the highest surviving seq is 6
            -- only if it was carried. Without it a new message could tie a restored one.
            local store = S().NewStore({ depth = 2 })
            for i = 1, 6 do store:Add(rec("SAY", "m" .. i)) end
            local blob = store:Serialise()
            expect(blob.seq).as("six messages consumed six numbers").eq(6)
            local back = S().Restore(blob)
            local fresh = back:Add(rec("SAY", "new"))
            for _, r in ipairs(back:Records()) do
                if r.message ~= "new" then
                    expect(fresh.seq).as("a live message must outrank every restored one").gt(r.seq)
                end
            end
        end)

        it("gives a sequence-less record one at the END, not the front", function()
            -- A blob written before sequences existed, or hand-edited.
            local back = S().Restore({ depth = 5, seq = 0, order = { "type:say" },
                streams = { ["type:say"] = { { kind = "SAY", message = "legacy" } } } })
            expect(back:Records()[1].seq).as("a nil seq would sort before everything").gt(0)
        end)

        it("resumes past a record whose sequence EXCEEDS the saved counter", function()
            -- A well-formed blob's counter always equals its highest record, so the resume looked
            -- redundant -- a mutation removing it survived. It is load-bearing only for a blob
            -- whose two halves disagree, which is exactly what this file claims to tolerate: a
            -- hand-edited SavedVariable, or a partial write. Without it a live message would tie
            -- or sort BEFORE restored history.
            local back = S().Restore({ depth = 50, seq = 1, order = { "type:say" },
                streams = { ["type:say"] = {
                    { kind = "SAY", message = "old", seq = 10 },
                } } })
            local fresh = back:Add(rec("SAY", "new"))
            expect(fresh.seq).as("a live message must outrank a record numbered past the counter")
                .gt(10)
            local all = back:Records()
            expect(all[#all].message).eq("new")
        end)

        it("survives a truncated blob whose order list is missing keys", function()
            local blob = { depth = 5, seq = 2, order = {}, streams = { ["type:say"] = {
                { kind = "SAY", message = "kept" },
            } } }
            local back = S().Restore(blob)
            expect(back:Count("type:say"))
                .as("dropping them would turn a partial save into a lost history").eq(1)
        end)

        it("yields an empty store for a hand-edited or absent blob", function()
            expect(S().Restore(nil):StreamCount()).eq(0)
            expect(S().Restore("nonsense"):StreamCount()).eq(0)
            expect(S().Restore({ streams = "no" }):StreamCount()).eq(0)
        end)
    end)

    describe("Clear", function()
        it("drops one stream and forgets its key", function()
            local store = S().NewStore()
            store:Add(rec("SAY", "s"))
            store:Add(rec("GUILD", "g"))
            store:Clear("type:say")
            expect(store:StreamCount()).eq(1)
            expect(store:Keys()[1]).eq("type:guild")
        end)

        it("drops everything with no key", function()
            local store = S().NewStore()
            store:Add(rec("SAY", "s"))
            store:Clear()
            expect(store:StreamCount()).eq(0)
        end)
    end)
end)

describe("ChatPanels", function()
    before_each(function() H.setup() end)

    local function P() return H.SuuUI.ChatPanels end
    local function rec(kind, extra)
        local f = { kind = kind }
        for k, v in pairs(extra or {}) do f[k] = v end
        return H.SuuUI.ChatStore.Record(f)
    end

    describe("Panels", function()
        it("ships General, Global, Guild and Log as DEFAULTS", function()
            local panels = P().Panels(nil)
            expect(#panels).eq(4)
            -- ORDER matters twice over: the rail renders in it, and `_render`'s
            -- never-land-nowhere fallback is `panels[1]`, so General has to stay first.
            expect(panels[1].id).eq("general")
            expect(panels[2].id).eq("global")
            expect(panels[3].id).eq("guild")
            expect(panels[4].id).eq("log")
        end)

        it("gives every shipped panel a DISTINCT rail initial", function()
            -- The disc's letter is the only thing identifying a panel at rest -- the name appears on
            -- hover -- so two panels sharing one is two panels the player cannot tell apart. `#`
            -- moved to Global (a player types `/1`, `/2`) and General took `@`.
            local seen = {}
            for _, p in ipairs(P().Panels(nil)) do
                expect(seen[p.initial]).as("duplicate initial " .. tostring(p.initial)).falsy()
                seen[p.initial] = true
            end
            expect(P().Find(P().Panels(nil), "global").initial).eq("#")
            expect(P().Find(P().Panels(nil), "general").initial).eq("@")
        end)

        it("prefers a stored list, so the set is the player's", function()
            local panels = P().Panels({ { id = "mine", name = "Mine", groups = { "SAY" } } })
            expect(#panels).eq(1)
            expect(panels[1].id).eq("mine")
        end)

        it("hands out COPIES, so one profile cannot edit another's", function()
            local a = P().Panels(nil)
            table.insert(a[1].groups, "GUILD")
            local b = P().Panels(nil)
            for _, g in ipairs(b[1].groups) do
                expect(g).as("the defaults are shared module state").neq("GUILD")
            end
        end)

        it("falls back rather than leaving the player with no panels", function()
            -- An empty chat window is indistinguishable from a broken addon.
            expect(#P().Panels({})).eq(4)
            expect(#P().Panels({ { name = "no id" } })).eq(4)
        end)

        it("General is CONVERSATION only", function()
            local general = P().Find(P().Panels(nil), "general")
            local set = {}
            for _, g in ipairs(general.groups) do set[g] = true end
            expect(set["SAY"]).truthy()
            expect(set["PARTY"]).truthy()
            expect(set["LOOT"]).as("loot belongs in the Log, not among people talking").falsy()
            expect(set["COMBAT_XP_GAIN"]).falsy()
            expect(set["GUILD"]).as("Guild is its own panel").falsy()
            expect(set["CHANNEL"]).as("channels moved to Global, and are not copied").falsy()
        end)

        it("Global is CHANNELS only", function()
            -- The client makes no distinction between a city channel and a joined one -- General,
            -- Trade, LocalDefense, LookingForGroup and every custom channel are all
            -- `CHAT_MSG_CHANNEL` told apart by their index -- so "all the global channels plus the
            -- custom ones" is exactly this one group.
            local global = P().Find(P().Panels(nil), "global")
            local set = {}
            for _, g in ipairs(global.groups) do set[g] = true end
            expect(set["CHANNEL"]).truthy()
            expect(set["SAY"]).as("not conversation").falsy()
            expect(set["GUILD"]).falsy()
            expect(set["LOOT"]).falsy()
            expect(set["CHANNEL_NOTICE"])
                .as("a join notice is bookkeeping, so it stays in the Log").falsy()
        end)

        it("makes Global a firehose that fades, like the channel traffic it took over", function()
            local global = P().Find(P().Panels(nil), "global")
            expect(global.fade).as("a channel is glanced at, not read").truthy()
            expect(global.chrome).as("chrome is for conversations").falsy()
        end)
    end)

    describe("Accept", function()
        it("matches on the group", function()
            local guild = P().Find(P().Panels(nil), "guild")
            expect(P().Accept(guild, rec("GUILD"))).truthy()
            expect(P().Accept(guild, rec("SAY"))).falsy()
        end)

        it("treats an ABSENT group list as no filter at all", function()
            -- A panel that never declared a group clause is a deliberate catch-all.
            expect(P().Accept({ id = "all" }, rec("LOOT"))).truthy()
            expect(P().Accept({ id = "all" }, rec("SAY"))).truthy()
        end)

        it("treats an EMPTY group list as a filter nothing satisfies", function()
            -- ABSENT and EMPTY are opposites here, and the difference became user-reachable the
            -- moment the player could switch every one of a panel's categories off. Collapsing them
            -- made that panel accept EVERY message in the game -- the loudest possible reading of
            -- "show me none of this", and how a Global panel with nothing ticked filled with loot.
            expect(P().Accept({ id = "none", groups = {} }, rec("LOOT"))).falsy()
            expect(P().Accept({ id = "none", groups = {} }, rec("CHANNEL"))).falsy()
        end)

        it("keeps that distinction through the COPY Panels hands out", function()
            -- copyPanel flattened nil to {}, so the distinction existed in Accept and was destroyed
            -- one call earlier by the thing every caller actually goes through.
            local copied = P().Panels({ { id = "all", name = "All" } })
            expect(copied[1].groups).as("nil survives the copy").eq(nil)
            expect(P().Accept(copied[1], rec("LOOT"))).truthy()
            local emptied = P().Panels({ { id = "none", name = "None", groups = {} } })
            expect(emptied[1].groups).notNil()
            expect(P().Accept(emptied[1], rec("LOOT"))).falsy()
        end)

        it("an explicit stream list wins over groups", function()
            -- How a conversation panel is expressed: it shows one stream whatever group the
            -- whispers in it belong to.
            local panel = { id = "c", streams = { "whisper:sul-realm" }, groups = { "GUILD" } }
            expect(P().Accept(panel, rec("AFK", { conversation = "sul-realm" }))).truthy()
            expect(P().Accept(panel, rec("GUILD")))
                .as("the stream list is the filter, not an addition to the groups").falsy()
        end)

        it("filters by sender, the first dimension past the group", function()
            local panel = { id = "s", groups = { "SAY" }, senders = { "Thalvyn" } }
            expect(P().Accept(panel, rec("SAY", { sender = "Thalvyn" }))).truthy()
            expect(P().Accept(panel, rec("SAY", { sender = "Someone" }))).falsy()
        end)

        it("matches a sender case-insensitively", function()
            local panel = { id = "s", senders = { "thalvyn" } }
            expect(P().Accept(panel, rec("SAY", { sender = "Thalvyn" }))).truthy()
        end)

        it("an ABSENT clause matches everything, which is what keeps filters cheap to add", function()
            -- Every existing stored panel is unaffected by a new dimension because it does not
            -- carry the field.
            local panel = { id = "any" }
            expect(P().Accept(panel, rec("LOOT"))).truthy()
        end)

        it("refuses nonsense rather than raising inside an event handler", function()
            expect(P().Accept(nil, rec("SAY"))).falsy()
            expect(P().Accept({ id = "x" }, nil)).falsy()
        end)
    end)

    describe("Route", function()
        it("returns EVERY accepting panel, not the first", function()
            -- This is what replaces first-tab-wins. One record in two panels is the ordinary case.
            local panels = {
                { id = "a", groups = { "SAY" } },
                { id = "b", groups = { "SAY", "GUILD" } },
                { id = "c", groups = { "GUILD" } },
            }
            local ids = P().Route(panels, rec("SAY"))
            expect(#ids).eq(2)
            expect(ids[1]).eq("a")
            expect(ids[2]).eq("b")
        end)

        it("DE-DUPLICATES a panel id appearing twice in the list", function()
            -- The de-dup is keyed by panel ID, so a single panel listing one group twice was never
            -- the case it guards -- that panel is visited once whatever its groups say, which is
            -- why the mutation removing `seen` survived. A malformed stored list is the real case.
            local panels = {
                { id = "dup", groups = { "SAY" } },
                { id = "dup", groups = { "SAY" } },
            }
            expect(#P().Route(panels, rec("SAY")))
                .as("one panel must not be rendered into twice").eq(1)
        end)

        it("accepts a record once for a panel listing one group twice", function()
            -- CHAT_MSG_AFK sits in two ChatTypeGroups, so a panel can legitimately name both.
            local panels = { { id = "a", groups = { "AFK", "AFK" } } }
            expect(#P().Route(panels, rec("AFK"))).eq(1)
        end)

        it("returns empty for a record no panel wants", function()
            expect(#P().Route({ { id = "a", groups = { "GUILD" } } }, rec("SAY"))).eq(0)
        end)

        it("hands back ids, so a definition cannot be mutated through the result", function()
            local ids = P().Route({ { id = "a", groups = { "SAY" } } }, rec("SAY"))
            expect(type(ids[1])).eq("string")
        end)
    end)

    describe("WhisperPanels", function()
        it("general puts a whisper in General only", function()
            local t = P().WhisperPanels("general", "whisper:a-b")
            expect(#t).eq(1)
            expect(t[1]).eq("general")
        end)

        it("panel puts it in its conversation only", function()
            local t = P().WhisperPanels("panel", "whisper:a-b")
            expect(#t).eq(1)
            expect(t[1]).eq("whisper:a-b")
        end)

        it("both is a REAL answer, not a fallback", function()
            local t = P().WhisperPanels("both", "whisper:a-b")
            expect(#t).eq(2)
            expect(t[1]).eq("general")
            expect(t[2]).eq("whisper:a-b")
        end)

        it("never returns empty, because a lost whisper is the worst outcome", function()
            for _, mode in ipairs({ "nonsense", "", "panel", "both" }) do
                expect(#P().WhisperPanels(mode, nil))
                    .as("an unrecognised mode, or no conversation, still reaches General").gt(0)
            end
        end)
    end)

    describe("Events", function()
        it("is the UNION of every panel's groups", function()
            local _, set = P().Events(P().Panels(nil), H.env.ChatTypeGroup)
            expect(set["CHAT_MSG_SAY"]).truthy()
            expect(set["CHAT_MSG_GUILD"]).truthy()
            expect(set["CHAT_MSG_LOOT"]).truthy()
        end)

        it("includes whisper groups whatever the panels say", function()
            -- A conversation panel does not exist until someone whispers you, so a union over
            -- panels alone would never register the event that creates it.
            local _, set = P().Events({ { id = "g", groups = { "GUILD" } } }, H.env.ChatTypeGroup)
            expect(set["CHAT_MSG_WHISPER"]).truthy()
        end)

        it("does NOT register a group no panel wants", function()
            local _, set = P().Events({ { id = "g", groups = { "GUILD" } } }, H.env.ChatTypeGroup)
            expect(set["CHAT_MSG_LOOT"]).falsy()
        end)

        it("deduplicates an event two panels both want", function()
            local events = P().Events({
                { id = "a", groups = { "GUILD" } },
                { id = "b", groups = { "GUILD" } },
            }, H.env.ChatTypeGroup)
            local n = 0
            for _, e in ipairs(events) do if e == "CHAT_MSG_GUILD" then n = n + 1 end end
            expect(n).eq(1)
        end)

        it("tolerates a group this client has no events for", function()
            -- The group list is shared across client generations; a dead group is not a bug in the
            -- panel that names it.
            local ok = pcall(P().Events, { { id = "x", groups = { "PET_BATTLE_INFO" } } },
                             H.env.ChatTypeGroup)
            expect(ok).truthy()
        end)
    end)
end)

describe("ChatCategories", function()
    before_each(function() H.setup() end)

    local function C() return H.SuuUI.ChatCategories end
    local function P() return H.SuuUI.ChatPanels end

    local function has(list, want)
        for _, v in ipairs(list or {}) do if v == want then return true end end
        return false
    end

    describe("the vocabulary itself", function()
        it("gives every category a unique id", function()
            local seen = {}
            for _, c in ipairs(C().CATEGORIES) do
                expect(seen[c.id]).as("duplicate category id " .. tostring(c.id)).falsy()
                seen[c.id] = true
            end
        end)

        it("gives every category a unique label", function()
            -- Two rows reading the same thing on a settings page is a page the player cannot use:
            -- the label IS the only thing distinguishing one toggle from the next.
            local seen = {}
            for _, c in ipairs(C().CATEGORIES) do
                expect(seen[c.label]).as("duplicate label " .. tostring(c.label)).falsy()
                seen[c.label] = true
            end
        end)

        it("never puts one group in two categories", function()
            -- The load-bearing invariant. GroupsFor de-duplicates, so a group named by two
            -- categories would survive switching EITHER of them off -- a toggle that visibly does
            -- nothing, for the half of its groups the other one also claims.
            local owner = {}
            for _, c in ipairs(C().CATEGORIES) do
                for _, g in ipairs(c.groups) do
                    expect(owner[g])
                        .as(g .. " is claimed by both " .. tostring(owner[g]) .. " and " .. c.id)
                        .falsy()
                    owner[g] = c.id
                end
            end
        end)

        it("gives every category at least one group", function()
            -- A category with no groups is a control that cannot change anything -- the settings
            -- equivalent of a theme token nothing reads.
            for _, c in ipairs(C().CATEGORIES) do
                expect(#c.groups).as(c.id .. " has no groups").gt(0)
            end
        end)
    end)

    describe("Key", function()
        it("builds one key per panel and category", function()
            expect(C().Key("general", "system")).eq("general_show_system")
            expect(C().Key("log", "loot")).eq("log_show_loot")
        end)

        it("returns nil rather than a malformed key for a bad argument", function()
            expect(C().Key(nil, "system")).eq(nil)
            expect(C().Key("general", nil)).eq(nil)
        end)
    end)

    describe("Default", function()
        it("puts SYSTEM messages in General as well as the Log", function()
            -- The ruling this feature was asked for: General is the main window, and a system line
            -- is what a player expects to read there because that is where Blizzard puts it.
            expect(C().Default("general", "system")).as("General shows system").truthy()
            expect(C().Default("log", "system")).as("the Log keeps them too").truthy()
        end)

        it("keeps conversation categories out of the Log and Log categories out of General", function()
            expect(C().Default("general", "say")).truthy()
            -- eq(false), not falsy(): the whole reason this coerces is that a nil default renders an
            -- unchecked box while Get answers nil, which is a second spelling of off that no watcher
            -- fires for. `.falsy()` cannot tell the two apart, so it proved nothing here.
            expect(C().Default("log", "say")).as("a real false, never nil").eq(false)
            expect(C().Default("log", "loot")).truthy()
            expect(C().Default("general", "loot")).as("a real false, never nil").eq(false)
        end)

        it("keeps Guild out of both, because Guild has a panel of its own", function()
            -- Not an oversight: General showing it too would put every guild line on screen twice.
            expect(C().Default("general", "guild")).eq(false)
            expect(C().Default("log", "guild")).eq(false)
        end)

        it("answers FALSE, not nil, for an unknown category", function()
            -- It is read as a schema `default`, and a nil default renders unchecked while Get
            -- answers nil -- two spellings of off, only one of which a watcher fires for.
            expect(C().Default("general", "nope")).eq(false)
        end)

        it("answers FALSE for a category row that OMITS a panel's field", function()
            -- Every shipped row writes both fields, so the coercion is unreachable through the
            -- table as it stands -- which is exactly why it is pinned here rather than deleted. A
            -- row added later as `{ id, label, general = true, groups }` with no `log` is the
            -- shape it defends against, and the failure it prevents is silent: `Schema` would put
            -- a nil default on that toggle, `PageBuilder` would draw it unchecked, and no watcher
            -- would fire for the value the player never changed.
            local cats = C().CATEGORIES
            cats[#cats + 1] = { id = "_probe", label = "_probe", general = true,
                                groups = { "PROBE" } }
            expect(C().Default("log", "_probe")).as("an absent field is a real false").eq(false)
            expect(C().Default("general", "_probe")).eq(true)
            -- And the derived schema carries that false rather than a nil.
            local seen
            for _, e in ipairs(C().Schema("log")) do
                if e.key == "log_show__probe" then seen = e end
            end
            expect(seen.default).eq(false)
            cats[#cats] = nil
        end)

        it("answers a boolean for every declared category on every panel", function()
            for _, panelId in ipairs(C().PANELS) do
                for _, c in ipairs(C().CATEGORIES) do
                    expect(type(C().Default(panelId, c.id)))
                        .as(panelId .. "/" .. c.id .. " must be a boolean").eq("boolean")
                end
            end
        end)
    end)

    describe("Schema", function()
        it("emits one toggle per category, in vocabulary order", function()
            local schema = C().Schema("general")
            expect(#schema).eq(#C().CATEGORIES)
            for i, entry in ipairs(schema) do
                expect(entry.type).eq("toggle")
                expect(entry.key).eq(C().Key("general", C().CATEGORIES[i].id))
                expect(entry.label).eq(C().CATEGORIES[i].label)
            end
        end)

        it("takes each entry's default from Default, so the page and the filter agree", function()
            -- The whole reason the schema is generated: a hand-written default that disagreed with
            -- GroupsFor would render a ticked box for a group the panel does not carry.
            for _, entry in ipairs(C().Schema("log")) do
                local catId = entry.key:match("^log_show_(.+)$")
                expect(entry.default).eq(C().Default("log", catId))
            end
        end)

        it("differs between the two panels", function()
            local g, l = C().Schema("general"), C().Schema("log")
            local gLoot, lLoot
            for _, e in ipairs(g) do if e.key == "general_show_loot" then gLoot = e.default end end
            for _, e in ipairs(l) do if e.key == "log_show_loot" then lLoot = e.default end end
            expect(gLoot).falsy()
            expect(lLoot).truthy()
        end)
    end)

    describe("GroupsFor", function()
        it("expands the shipped defaults when given no predicate", function()
            local groups = C().GroupsFor("general")
            expect(has(groups, "SAY")).truthy()
            expect(has(groups, "SYSTEM")).as("General now carries SYSTEM").truthy()
            expect(has(groups, "CHANNEL")).as("channels MOVED to Global, not copied").falsy()
            expect(has(groups, "LOOT")).as("loot is the Log's").falsy()
        end)

        it("gives Global the channel group and nothing else", function()
            local groups = C().GroupsFor("global")
            expect(#groups).as("one group covers every channel, city and custom alike").eq(1)
            expect(groups[1]).eq("CHANNEL")
        end)

        it("honours a predicate over the defaults", function()
            local only = C().GroupsFor("general", function(id) return id == "loot" end)
            expect(has(only, "LOOT")).truthy()
            expect(has(only, "MONEY")).as("the whole category, not just its first group").truthy()
            expect(has(only, "SAY")).as("a default-on category the predicate refused").falsy()
        end)

        it("returns an empty list when every category is off", function()
            expect(#C().GroupsFor("general", function() return false end)).eq(0)
        end)

        it("de-duplicates and keeps vocabulary order", function()
            local groups = C().GroupsFor("general", function() return true end)
            local seen = {}
            for _, g in ipairs(groups) do
                expect(seen[g]).as("duplicate group " .. g).falsy()
                seen[g] = true
            end
            -- Order is total, so the event registration set built from it is the same on every
            -- login -- the determinism ChatPanels' ordered arrays exist for.
            local iSay, iLoot
            for i, g in ipairs(groups) do
                if g == "SAY" then iSay = i end
                if g == "LOOT" then iLoot = i end
            end
            expect(iSay).lt(iLoot)
        end)

        it("claims CHANNEL_JOIN and CHANNEL_LEAVE, which no panel used to", function()
            -- The CHANNEL group registers both events, and until this table existed no panel named
            -- either KIND -- so every join and leave notice fell through routing into _render's
            -- never-land-nowhere fallback, which is General. They belong with the bookkeeping.
            local log = C().GroupsFor("log")
            expect(has(log, "CHANNEL_JOIN")).truthy()
            expect(has(log, "CHANNEL_LEAVE")).truthy()
            expect(has(C().GroupsFor("general"), "CHANNEL_JOIN")).falsy()
        end)
    end)

    describe("Keys", function()
        it("names every configurable panel", function()
            -- Declared explicitly rather than counted, because `Keys` is what the plugin wires its
            -- watchers from AND what tells `_applyCategories` which panels to re-derive: a panel
            -- missing from here renders its toggles (the schema is generated per panel) and then
            -- ignores every one of them, which reads as the checkboxes being broken.
            local set = {}
            for _, id in ipairs(C().PANELS) do set[id] = true end
            expect(set["general"]).truthy()
            expect(set["global"]).as("Global's toggles need watchers like anyone else's").truthy()
            expect(set["log"]).truthy()
            expect(set["guild"]).as("one group, so there is nothing to configure").falsy()
        end)

        it("covers every configurable panel crossed with every category", function()
            expect(#C().Keys()).eq(#C().PANELS * #C().CATEGORIES)
        end)

        it("is what a caller wires watchers from, so it contains no nils", function()
            for _, key in ipairs(C().Keys()) do expect(type(key)).eq("string") end
        end)
    end)

    describe("the panel defaults are DERIVED from it", function()
        it("gives General exactly GroupsFor('general')", function()
            -- No second copy: two lists of the same fact would let the shipped defaults and the
            -- switchable categories disagree, and the page would offer a control for a group the
            -- panel does not carry.
            local panel = P().Find(P().Panels(nil), "general")
            local want = C().GroupsFor("general")
            expect(#panel.groups).eq(#want)
            for i, g in ipairs(want) do expect(panel.groups[i]).eq(g) end
        end)

        it("gives the Log exactly GroupsFor('log')", function()
            local panel = P().Find(P().Panels(nil), "log")
            local want = C().GroupsFor("log")
            expect(#panel.groups).eq(#want)
            for i, g in ipairs(want) do expect(panel.groups[i]).eq(g) end
        end)

        it("gives Global exactly GroupsFor('global')", function()
            local panel = P().Find(P().Panels(nil), "global")
            local want = C().GroupsFor("global")
            expect(#panel.groups).eq(#want)
            for i, g in ipairs(want) do expect(panel.groups[i]).eq(g) end
        end)

        it("leaves Guild alone, and claims GUILD_MOTD there", function()
            -- Guild is not in PANELS: one group means a category page for it would be a single
            -- checkbox that empties the panel. GUILD_MOTD is named because the GUILD group
            -- registers that event and its record's kind is GUILD_MOTD, not GUILD -- unclaimed, the
            -- message of the day fell through into General.
            local panel = P().Find(P().Panels(nil), "guild")
            expect(has(panel.groups, "GUILD")).truthy()
            expect(has(panel.groups, "GUILD_MOTD")).truthy()
        end)
    end)
end)
