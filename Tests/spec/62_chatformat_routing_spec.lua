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

    describe("a non-string message must not raise", function()
        local function F() return H.SuuUI.ChatFormat end

        it("renders a NUMBER message instead of raising", function()
            -- A number reaches Body during history replay, off a SavedVariable written by an older
            -- version. `message:find(...)` raised on it -- a Lua number has no metatable reaching
            -- `string` -- and the throw unwound out of buildWindow and cost the ENTIRE chat window.
            local ok, out = pcall(F().Body, "SAY", 42, "Thalvyn", { plain = true })
            expect(ok).as("a number is rendered, not raised on").eq(true)
            expect(tostring(out):find("42", 1, true)).notNil()
        end)

        it("renders a NUMBER sender", function()
            local ok = pcall(F().Body, "SAY", "hi", 7, { plain = true })
            expect(ok).eq(true)
        end)

        it("survives a number on the MONSTER path, where the crash actually was", function()
            local ok = pcall(F().Body, "MONSTER_EMOTE", 42, "Onyxia", { plain = true })
            expect(ok).eq(true)
        end)
    end)

    describe("monster and boss placeholders", function()
        local function F() return H.SuuUI.ChatFormat end

        it("substitutes the source's name into a MONSTER_EMOTE's own %s", function()
            -- Shipped as a literal "%s" on screen. The message carries the placeholder, not the
            -- globalstring, and the client is what fills it in.
            local out = F().Body("MONSTER_EMOTE", "%s prepares to cast Shadow Bolt.", "Felguard")
            expect(out:find("%%s")).as("no placeholder survives").eq(nil)
            expect(out:find("Felguard", 1, true)).as("the source is named").notNil()
        end)

        it("substitutes in the PLAIN branch too, which is where it actually broke", function()
            -- MONSTER_EMOTE lands in a panel that draws a tag column, so it takes the plain early
            -- return and never reaches the globalstring path. Fixing only the latter would have
            -- looked correct in a unit test and stayed broken in game.
            local out = F().Body("MONSTER_EMOTE", "%s roars!", "Onyxia", { plain = true })
            expect(out:find("%%s")).eq(nil)
            expect(out:find("Onyxia", 1, true)).notNil()
        end)

        it("leaves a line with no placeholder untouched", function()
            local out = F().Body("MONSTER_SAY", "You are not prepared.", "Illidan", { plain = true })
            expect(out:find("You are not prepared.", 1, true)).notNil()
        end)

        it("does not touch a PLAYER line that happens to contain %s", function()
            -- A player typing "%s" is not a placeholder, and the prefix test is what keeps them apart.
            local out = F().Body("SAY", "printf(\"%s\")", "Thalvyn", { plain = true })
            expect(out:find("%%s")).as("a player's own text is left alone").notNil()
        end)

        it("survives a source name containing a percent sign", function()
            -- gsub treats `%` in the REPLACEMENT as a capture reference, so an unescaped name would
            -- raise from inside an event handler.
            local out = F().Body("MONSTER_EMOTE", "%s attacks!", "50%Health", { plain = true })
            -- ONE percent in the expected text: `%%` in a Lua string literal is already two percent
            -- characters, so asserting "50%%Health" looks for a doubling that must not survive.
            expect(out:find("50%Health", 1, true)).notNil()
        end)
    end)

    describe("Plain", function()
        local function F() return H.SuuUI.ChatFormat end

        it("keeps a link's LABEL and drops its target", function()
            expect(F().Plain("got |Hitem:19019|h[Thunderfury]|h today"))
                .as("the bracketed name is the readable part; the item id is not")
                .eq("got [Thunderfury] today")
        end)

        it("removes colour codes", function()
            expect(F().Plain("|cff00ff00green|r text")).eq("green text")
        end)

        it("removes an inline texture, which has no textual form", function()
            expect(F().Plain("a |TInterface\\Icons\\foo:12|t b")).eq("a  b")
        end)

        it("unwraps a COLOURED link, which is the ordering trap", function()
            -- A link's display text usually carries its own colour, so stripping colour first would
            -- leave the |h fragments with nothing to anchor on.
            expect(F().Plain("|cffa335ee|Hitem:19019|h[Thunderfury]|h|r"))
                .eq("[Thunderfury]")
        end)

        it("leaves an escaped pipe as a single pipe", function()
            expect(F().Plain("a || b")).eq("a | b")
        end)

        it("strips a real composed line end to end", function()
            -- Driven through the REAL composer rather than a hand-written string, so the test cannot
            -- pass against markup production never emits.
            local line = F().Line({
                chatType = "GUILD",
                message  = "got |Hitem:19019|h[Thunderfury]|h",
                sender   = F().PlayerLink("Thalvyn", 7, "Thalvyn"),
            }, { timestamps = false, tag = true })
            local plain = F().Plain(line)
            expect(plain:find("|c", 1, true)).as("no colour escapes survive").eq(nil)
            expect(plain:find("|H", 1, true)).as("no link wrappers survive").eq(nil)
            expect(plain:find("Thalvyn", 1, true)).as("the sender is still readable").notNil()
            expect(plain:find("[Thunderfury]", 1, true)).as("and so is the item").notNil()
        end)

        it("returns nil and empty unchanged", function()
            expect(F().Plain(nil)).eq(nil)
            expect(F().Plain("")).eq("")
        end)
    end)

    describe("LinkifyURLs", function()
        local function F() return H.SuuUI.ChatFormat end

        it("wraps an http URL in a url: hyperlink", function()
            local out = F().LinkifyURLs("see https://wowhead.com/item=19019 for it")
            expect(out:find("|Hurl:https://wowhead.com/item=19019|h", 1, true)).notNil()
            expect(out:find("see ", 1, true)).as("surrounding text is preserved").eq(1)
            expect(out:find(" for it", 1, true)).notNil()
        end)

        it("wraps a bare www. address, which has no scheme to match on", function()
            expect(F().LinkifyURLs("go to www.wowhead.com now")
                :find("|Hurl:www.wowhead.com|h", 1, true)).notNil()
        end)

        it("leaves trailing punctuation OUTSIDE the link", function()
            -- "see https://wow.gg." otherwise carries the full stop into the address and the player
            -- copies a broken URL.
            local out = F().LinkifyURLs("see https://wow.gg.")
            expect(out:find("|Hurl:https://wow.gg|h", 1, true)).as("no trailing dot in the link").notNil()
            expect(out:sub(-1)).as("the sentence keeps its full stop").eq(".")
        end)

        it("handles a scheme URL and a www address in the SAME message", function()
            -- The case a gsub-per-pattern version gets wrong: the www pass also matches the `www.`
            -- inside the already-wrapped https link and nests the two.
            local out = F().LinkifyURLs("try https://www.a.com or www.b.com")
            local _, n = out:gsub("|Hurl:", "")
            expect(n).as("exactly two links, not a nested one").eq(2)
            expect(out:find("|Hurl:https://www.a.com|h", 1, true)).notNil()
            expect(out:find("|Hurl:www.b.com|h", 1, true)).notNil()
        end)

        it("does not linkify ordinary prose that merely looks domain-shaped", function()
            -- A false positive is worse than a miss: it makes plain text look clickable. So a bare
            -- `foo.bar` is deliberately NOT matched -- only a scheme or a www. prefix.
            for _, s in ipairs({ "e.g. that thing", "meet at 5p.m. sharp", "hp.mp ratio" }) do
                expect(F().LinkifyURLs(s)).as(s).eq(s)
            end
        end)

        it("is idempotent, so a second pass cannot nest links", function()
            local once = F().LinkifyURLs("see https://wow.gg here")
            expect(F().LinkifyURLs(once)).eq(once)
        end)

        it("returns nil and empty unchanged", function()
            expect(F().LinkifyURLs(nil)).eq(nil)
            expect(F().LinkifyURLs("")).eq("")
        end)

        it("colours the link from the accent TOKEN, not a hardcoded hex", function()
            local code = H.SuuUI.Theme:GetColorCode("colorAccent")
            expect(code).notNil()
            expect(F().LinkifyURLs("https://wow.gg"):find(code, 1, true))
                .as("a retint must move chat's links with everything else").notNil()
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
