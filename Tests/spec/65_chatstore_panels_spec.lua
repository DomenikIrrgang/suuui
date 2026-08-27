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
        it("ships General, Guild and Log as DEFAULTS", function()
            local panels = P().Panels(nil)
            expect(#panels).eq(3)
            expect(panels[1].id).eq("general")
            expect(panels[2].id).eq("guild")
            expect(panels[3].id).eq("log")
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
            expect(#P().Panels({})).eq(3)
            expect(#P().Panels({ { name = "no id" } })).eq(3)
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
        end)
    end)

    describe("Accept", function()
        it("matches on the group", function()
            local guild = P().Find(P().Panels(nil), "guild")
            expect(P().Accept(guild, rec("GUILD"))).truthy()
            expect(P().Accept(guild, rec("SAY"))).falsy()
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
