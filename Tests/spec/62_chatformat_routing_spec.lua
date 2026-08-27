-- ChatFormat and ChatRouting: the pure modules that turn a CHAT_MSG_* payload into a line and
-- decide which tab it belongs to. No frames involved, so these are the cheapest specs in the
-- chat feature and the most exhaustive.
local H = require("harness")

describe("ChatFormat", function()
    before_each(function() H.setup() end)

    local function F() return H.SuuUI.ChatFormat end

    describe("Body", function()
        it("applies the GlobalString to the sender and appends the message", function()
            local out = F().Body("SAY", "hello there", "Thalvyn", { globals = H.env })
            expect(out).eq("Thalvyn says: hello there")
        end)

        it("uses the client's own string, not a hand-written format", function()
            -- Change the globalstring and the output must follow it.
            H.env.CHAT_SAY_GET = "%s mutters: "
            expect(F().Body("SAY", "hi", "Thalvyn", { globals = H.env }))
                .as("locale support comes free precisely because nothing is hardcoded")
                .eq("Thalvyn mutters: hi")
        end)

        it("keeps the bracketed channel name the group strings carry", function()
            local out = F().Body("GUILD", "kara tonight?", "Thalvyn", { globals = H.env })
            expect(out).contains("[Guild]")
            expect(out).contains("kara tonight?")
        end)

        it("puts the message INSIDE the format for a special type", function()
            -- The fixture needs a message containing `%%`, because that is the ONLY thing that
            -- distinguishes the two branches: special appends the message to the FORMAT string
            -- (so `%%` collapses to `%`), while normal passes it as an ARGUMENT (so `%%` stays
            -- literal). A message with no specifier in it produces identical output either way,
            -- and a mutation swapping the branches survives.
            H.env.CHAT_MONSTER_BOSS_EMOTE_GET = "<<%s>> "
            local out = F().Body("MONSTER_BOSS_EMOTE", "is at 50%% power", "Nefarian",
                { globals = H.env })
            expect(out)
                .as("these globalstrings carry their own formatting, so the message joins the "
                    .. "FORMAT rather than the arguments").eq("<<Nefarian>> is at 50% power")
        end)

        it("returns TEXT_EMOTE's message untouched, because it already names the sender", function()
            local out = F().Body("TEXT_EMOTE", "Thalvyn waves.", "Thalvyn", { globals = H.env })
            expect(out).as("prefixing would print the name twice").eq("Thalvyn waves.")
        end)

        it("inserts the language when one is given", function()
            local out = F().Body("SAY", "lok'tar", "Grimtusk",
                { globals = H.env, language = "Orcish" })
            expect(out).contains("[Orcish]")
            expect(out).contains("lok'tar")
        end)

        it("degrades an unknown chat type to sender plus message", function()
            local out = F().Body("NOT_A_REAL_TYPE", "still readable", "Thalvyn",
                { globals = H.env })
            expect(out)
                .as("the player still reads what was said, which beats an empty line")
                .eq("Thalvyn: still readable")
        end)

        it("survives a percent sign in a player's message", function()
            -- Player-supplied text reaches string.format, so a stray specifier must not raise
            -- from inside an event handler.
            local out
            expect(function()
                out = F().Body("SAY", "mana at 50%s and dropping", "Thalvyn", { globals = H.env })
            end).notThrows()
            expect(out).notNil()
        end)

        it("tolerates a nil message", function()
            expect(function() F().Body("SAY", nil, "Thalvyn", { globals = H.env }) end)
                .notThrows()
        end)
    end)

    describe("StripChannelPrefix", function()
        it("removes the bracket the group strings carry", function()
            local body, target, label =
                F().StripChannelPrefix("|Hchannel:Guild|h[Guild]|h Thalvyn: hi")
            expect(body)
                .as("a tab rendering a tag chip AND the raw string prints the channel twice")
                .eq("Thalvyn: hi")
            expect(target).as("the link target is KEPT: a channel name stays clickable").eq("Guild")
            expect(label).eq("Guild")
        end)

        it("leaves a string with no prefix alone", function()
            expect((F().StripChannelPrefix("Thalvyn says: hi"))).eq("Thalvyn says: hi")
        end)

        it("reports nil target for an unprefixed string", function()
            local _, target = F().StripChannelPrefix("plain")
            expect(target).eq(nil)
        end)

        it("strips only the leading prefix, not a link later in the message", function()
            local body = F().StripChannelPrefix(
                "|Hchannel:Guild|h[Guild]|h Thalvyn: see |Hchannel:Trade|h[Trade]|h")
            expect(body).contains("|Hchannel:Trade|h[Trade]|h")
        end)

        it("leaves an EMBEDDED channel link alone when there is no leading prefix", function()
            -- The discriminating fixture for the `^` anchor. With a leading prefix present, an
            -- unanchored gsub still replaces that one first, so the earlier test cannot tell the
            -- two apart -- and a player pasting a channel link mid-message is the real case.
            local input = "Thalvyn: see |Hchannel:Trade|h[Trade]|h for prices"
            expect((F().StripChannelPrefix(input)))
                .as("only a LEADING prefix is the globalstring's own; anything later is the "
                    .. "player's text").eq(input)
        end)

        it("tolerates a non-string", function()
            expect(function() F().StripChannelPrefix(nil) end).notThrows()
        end)
    end)

    describe("PlayerLink", function()
        it("builds a link carrying the lineID", function()
            expect(F().PlayerLink("Sylvaine", 4242))
                .eq("|Hplayer:Sylvaine:4242|hSylvaine|h")
        end)

        it("takes a separate display string, for a class-coloured name", function()
            expect(F().PlayerLink("Sylvaine", 7, "|cffF58CBASylvaine|r"))
                .contains("|cffF58CBASylvaine|r")
        end)

        it("returns the bare name with no lineID rather than a broken link", function()
            expect(F().PlayerLink("Sylvaine", nil))
                .as("SetItemRef needs the lineID; a link without one degrades right-click")
                .eq("Sylvaine")
        end)

        it("tolerates an empty name", function()
            expect(F().PlayerLink("", 1)).eq("")
        end)
    end)

    describe("Timestamp", function()
        it("defaults to 24-hour", function()
            H.setClock({ year = 2026, month = 8, day = 27, hour = 14, min = 32, sec = 7 })
            expect(F().Timestamp()).eq("14:32")
        end)

        it("adds seconds on request", function()
            H.setClock({ year = 2026, month = 8, day = 27, hour = 14, min = 32, sec = 7 })
            expect(F().Timestamp("24hs")).eq("14:32:07")
        end)

        it("strips the leading zero from the 12-hour form", function()
            H.setClock({ year = 2026, month = 8, day = 27, hour = 14, min = 32, sec = 7 })
            expect(F().Timestamp("12h"))
                .as("%I gives 02:32 PM and the zero is noise in a right-aligned column")
                .eq("2:32 PM")
        end)

        it("keeps a two-digit 12-hour reading intact", function()
            H.setClock({ year = 2026, month = 8, day = 27, hour = 23, min = 5, sec = 0 })
            expect(F().Timestamp("12h")).eq("11:05 PM")
        end)
    end)

    describe("Tag", function()
        it("gives a short uppercase tag per chat type", function()
            expect(F().Tag("GUILD")).eq("GLD")
            expect(F().Tag("PARTY")).eq("PTY")
            expect(F().Tag("WHISPER")).eq("WSP")
        end)

        it("collapses a leader variant onto its base tag", function()
            expect(F().Tag("RAID_LEADER"))
                .as("a mixing tab does not need to spend a column on leader-ness")
                .eq(F().Tag("RAID"))
        end)

        it("uses the NUMBER for a numbered channel", function()
            expect(F().Tag("CHANNEL", 2))
                .as("the number is what a player types (/2), so letters would hide the "
                    .. "actionable part").eq("2")
        end)

        it("falls back for a channel with no index", function()
            expect(F().Tag("CHANNEL", nil)).eq("CH")
        end)

        it("returns nil for a type with no tag", function()
            expect(F().Tag("SOMETHING_ELSE")).eq(nil)
        end)
    end)

    describe("ShortName", function()
        it("strips the player's OWN realm", function()
            expect(F().ShortName("Sulisande-Thunderstrike", "Thunderstrike"))
                .as("the client hands the realm over even for someone standing beside you")
                .eq("Sulisande")
        end)

        it("keeps a DIFFERENT realm, where the suffix is the information", function()
            expect(F().ShortName("Sulisande-Goldensands", "Thunderstrike"))
                .eq("Sulisande-Goldensands")
        end)

        it("matches a realm whose spaces the client stripped", function()
            expect(F().ShortName("Sulisande-GoldenSands", "Golden Sands")).eq("Sulisande")
        end)

        it("leaves a bare name alone", function()
            expect(F().ShortName("Sulisande", "Thunderstrike")).eq("Sulisande")
        end)

        it("strips nothing without a realm to compare against", function()
            expect(F().ShortName("Sulisande-Thunderstrike", nil))
                .eq("Sulisande-Thunderstrike")
        end)
    end)

    describe("Line", function()
        it("assembles timestamp, tag and body in that order", function()
            H.setClock({ year = 2026, month = 8, day = 27, hour = 19, min = 41, sec = 0 })
            local text = F().Line(
                { chatType = "GUILD", message = "kara?", sender = "Thalvyn", globals = H.env },
                { timestamps = true, tag = true })
            expect(text).eq("19:41 GLD Thalvyn: kara?")
        end)

        it("omits the timestamp when the setting is off", function()
            local text = F().Line(
                { chatType = "GUILD", message = "kara?", sender = "Thalvyn", globals = H.env },
                { tag = true })
            expect(text).eq("GLD Thalvyn: kara?")
        end)

        it("omits the tag in a single-channel tab", function()
            local text = F().Line(
                { chatType = "GUILD", message = "kara?", sender = "Thalvyn", globals = H.env },
                { timestamps = false, tag = false })
            expect(text)
                .as("a Guild tab would print GLD on every line").eq("Thalvyn: kara?")
        end)

        it("drops the globalstring's VERB when a tag is drawn", function()
            -- The bug this pins shipped and was found by looking at the game:
            -- `08:31 SAY Sulisande says: test` -- the tag and "says:" are the same information.
            -- CHAT_SAY_GET carries no bracket to strip, so only the plain-body path fixes it.
            local text = F().Line(
                { chatType = "SAY", message = "test", sender = "Thalvyn", globals = H.env },
                { tag = true })
            expect(text).eq("SAY Thalvyn: test")
            expect(text:find("says", 1, true))
                .as("the tag column already says which channel it is").eq(nil)
        end)

        it("KEEPS the globalstring when no tag carries the channel", function()
            local text = F().Line(
                { chatType = "SAY", message = "test", sender = "Thalvyn", globals = H.env },
                { tag = false })
            expect(text)
                .as("with no tag the verb IS the channel identity, so it must stay")
                .eq("Thalvyn says: test")
        end)

        it("keeps a tagless type's globalstring phrasing even with tags on", function()
            H.env.CHAT_MONSTER_BOSS_EMOTE_GET = "<<%s>> "
            local text = F().Line(
                { chatType = "MONSTER_BOSS_EMOTE", message = "roars!", sender = "Nefarian",
                  globals = H.env }, { tag = true })
            expect(text)
                .as("a boss emote has no tag, so its own phrasing is the content")
                .eq("<<Nefarian>> roars!")
        end)

        it("strips the channel bracket even when no tag is rendered", function()
            local text = F().Line(
                { chatType = "GUILD", message = "kara?", sender = "Thalvyn", globals = H.env },
                { tag = false })
            expect(text:find("[Guild]", 1, true))
                .as("the bracket goes whether or not a tag replaces it -- the rail carries "
                    .. "channel identity in a single-channel tab").eq(nil)
        end)

        it("returns the tag separately so a column can be sized from it", function()
            local _, tag = F().Line(
                { chatType = "CHANNEL", message = "WTS", sender = "Morgaine",
                  channelIndex = 2, globals = H.env }, { tag = true })
            expect(tag).eq("2")
        end)

        it("still returns the tag when the caller is not rendering one", function()
            local _, tag = F().Line(
                { chatType = "GUILD", message = "x", sender = "T", globals = H.env },
                { tag = false })
            expect(tag).as("the caller decides; this never guesses").eq("GLD")
        end)
    end)
end)

describe("ChatRouting", function()
    before_each(function() H.setup() end)

    local function R() return H.SuuUI.ChatRouting end

    describe("EventsFor", function()
        it("expands a group from the client's own table", function()
            local events = R().EventsFor("SAY", H.env.ChatTypeGroup)
            expect(#events).eq(1)
            expect(events[1]).eq("CHAT_MSG_SAY")
        end)

        it("returns a copy, not the client's table", function()
            local events = R().EventsFor("SAY", H.env.ChatTypeGroup)
            events[1] = "TAMPERED"
            expect(H.env.ChatTypeGroup.SAY[1]).eq("CHAT_MSG_SAY")
        end)

        it("returns empty for a group this client does not declare", function()
            expect(#R().EventsFor("PET_BATTLE_INFO", H.env.ChatTypeGroup))
                .as("a declared-but-never-fired group must cost nothing, not raise").eq(0)
        end)

        it("tolerates a missing group table", function()
            expect(#R().EventsFor("SAY", nil)).gte(0)
        end)
    end)

    describe("EventsForTab", function()
        it("collects every event General needs", function()
            local events, seen = R().EventsForTab("general", H.env.ChatTypeGroup)
            expect(#events).gt(5)
            expect(seen["CHAT_MSG_SAY"]).eq(true)
            expect(seen["CHAT_MSG_PARTY"]).eq(true)
            expect(seen["CHAT_MSG_RAID_WARNING"]).eq(true)
        end)

        it("keeps General conversational -- no loot, no XP", function()
            local _, seen = R().EventsForTab("general", H.env.ChatTypeGroup)
            expect(seen["CHAT_MSG_LOOT"])
                .as("General is party/raid/say/yell/whispers, not the everything tab").eq(nil)
            expect(seen["CHAT_MSG_COMBAT_XP_GAIN"]).eq(nil)
        end)

        it("routes the non-conversational traffic to the Log tab", function()
            local _, seen = R().EventsForTab("log", H.env.ChatTypeGroup)
            expect(seen["CHAT_MSG_LOOT"]).eq(true)
            expect(seen["CHAT_MSG_COMBAT_XP_GAIN"])
                .as("window 2's groups land here, so XP is not lost when it is neutered")
                .eq(true)
            expect(seen["CHAT_MSG_SYSTEM"]).eq(true)
        end)

        it("gives guild its own tab, with officer", function()
            local _, seen = R().EventsForTab("guild", H.env.ChatTypeGroup)
            expect(seen["CHAT_MSG_GUILD"]).eq(true)
            expect(seen["CHAT_MSG_OFFICER"]).eq(true)
        end)

        it("deduplicates an event two groups share", function()
            local events = R().EventsForTab("log", H.env.ChatTypeGroup)
            local count = 0
            for _, e in ipairs(events) do
                if e == "CHAT_MSG_SYSTEM" then count = count + 1 end
            end
            expect(count)
                .as("SYSTEM and ERRORS both carry CHAT_MSG_SYSTEM; registering twice would "
                    .. "double every system line").eq(1)
        end)

        it("returns empty for an unknown tab", function()
            expect(#R().EventsForTab("nope", H.env.ChatTypeGroup)).eq(0)
        end)
    end)

    describe("BuildEventMap", function()
        it("maps each event to exactly one tab", function()
            local map = R().BuildEventMap(H.env.ChatTypeGroup)
            expect(map["CHAT_MSG_SAY"]).eq("general")
            expect(map["CHAT_MSG_GUILD"]).eq("guild")
            expect(map["CHAT_MSG_LOOT"]).eq("log")
        end)

        it("resolves a shared event the SAME way every build", function()
            -- CHAT_MSG_SYSTEM is in both SYSTEM and ERRORS; the client's own inverted map is
            -- built with pairs() and is non-deterministic. Ours must not be.
            local first = R().BuildEventMap(H.env.ChatTypeGroup)["CHAT_MSG_SYSTEM"]
            for _ = 1, 5 do
                expect(R().BuildEventMap(H.env.ChatTypeGroup)["CHAT_MSG_SYSTEM"]).eq(first)
            end
        end)

        it("the EARLIER tab keeps an event two tabs would both claim", function()
            -- Determinism alone cannot prove first-wins: always-overwrite is deterministic too,
            -- it just picks the last tab. So the overlap has to be staged. Injected through the
            -- group table because TAB_GROUPS is shipped data -- putting CHAT_MSG_SAY into the
            -- GUILD group makes SAY reachable from both "general" and "guild".
            H.env.ChatTypeGroup.GUILD = { "CHAT_MSG_GUILD", "CHAT_MSG_SAY" }
            local map = R().BuildEventMap(H.env.ChatTypeGroup)
            expect(map["CHAT_MSG_SAY"])
                .as("TABS is ordered and general comes first, so a later tab must not steal a "
                    .. "claimed event -- otherwise editing one tab's groups silently re-routes "
                    .. "another's").eq("general")
        end)

        it("does not claim whisper events, which the setting routes", function()
            local map = R().BuildEventMap(H.env.ChatTypeGroup)
            expect(map["CHAT_MSG_WHISPER"])
                .as("a whisper's destination is the one thing the player configures").eq(nil)
        end)
    end)

    describe("WhisperTargets", function()
        it("general-only sends it to General alone", function()
            expect(R().WhisperTargets("general", "sylvaine-goldensands"))
                .deepEq({ "general" })
        end)

        it("panel-only sends it to the conversation alone", function()
            expect(R().WhisperTargets("panel", "sylvaine-goldensands"))
                .deepEq({ "sylvaine-goldensands" })
        end)

        it("both sends it to two places", function()
            expect(R().WhisperTargets("both", "sylvaine-goldensands"))
                .deepEq({ "general", "sylvaine-goldensands" })
        end)

        it("falls back to General when panel-only has no conversation", function()
            expect(R().WhisperTargets("panel", nil))
                .as("a lost whisper is the worst outcome this module can produce")
                .deepEq({ "general" })
        end)

        it("an unrecognised stored mode still delivers", function()
            expect(R().WhisperTargets("garbage", "sylvaine-goldensands"))
                .as("a hand-edited profile must not lose whispers")
                .deepEq({ "general", "sylvaine-goldensands" })
        end)
    end)

    describe("ConversationKey", function()
        it("lowercases name and realm", function()
            expect(R().ConversationKey("Sylvaine", "Golden Sands"))
                .eq("sylvaine-golden sands")
        end)

        it("collapses the duplicate Name / Name-Realm pair onto one key", function()
            local a = R().ConversationKey("Sylvaine", "Goldensands")
            local b = R().ConversationKey("Sylvaine-Goldensands", nil)
            expect(b).as("this is the fix for Blizzard opening two tabs for one person").eq(a)
        end)

        it("does not double the realm when the name already carries it", function()
            expect(R().ConversationKey("Sylvaine-Goldensands", "Goldensands"))
                .eq("sylvaine-goldensands")
        end)

        it("returns nil for an empty name", function()
            expect(R().ConversationKey("")).eq(nil)
            expect(R().ConversationKey(nil)).eq(nil)
        end)
    end)
end)
