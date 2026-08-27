-- The chat plugin, Phase 4a: one General log alongside Blizzard's chat, which is untouched.
local H = require("harness")

describe("chat plugin", function()
    before_each(function() H.setup() end)

    local function P() return H.SuuUI.Plugins:Get("chat") end

    local function enabled()
        local p = P()
        H.SuuUI.Settings:Set("chat", "enabled", true)
        return p
    end

    describe("registration", function()
        it("registers as a plugin", function()
            expect(P()).notNil()
            expect(P().name).eq("Chat")
        end)

        it("declares the settings schema", function()
            local schema = H.SuuUI.Settings:GetSchema("chat")
            expect(schema).notNil()
            local keys = {}
            for _, e in ipairs(schema) do keys[e.key] = e end
            expect(keys["show_timestamps"]).notNil()
            expect(keys["show_timestamps"].default)
                .as("the column was asked for, so it is there without hunting").eq(true)
            expect(keys["whisper_mode"]).notNil()
            expect(#keys["whisper_mode"].options)
                .as("three-way: General only, own panel only, or both").eq(3)
        end)

        it("gates the timestamp format on the toggle", function()
            local schema = H.SuuUI.Settings:GetSchema("chat")
            for _, e in ipairs(schema) do
                if e.key == "timestamp_format" then
                    expect(e.enabledIf).eq("show_timestamps")
                end
            end
        end)

        it("is enabled by default", function()
            expect(H.SuuUI.Settings:Get("chat", "enabled")).eq(true)
        end)
    end)

    describe("the window", function()
        it("builds a frameless log and a resting chip", function()
            local p = enabled()
            expect(p._chat).notNil()
            expect(p._chat:ActiveLog()).notNil()
            expect(p._chat:ActiveLog():HasChrome())
                .as("the log floats over the world with no surface of its own").eq(false)
            expect(p._chat._chip).notNil()
        end)

        it("gives the log a real height, not a zero-height strip", function()
            -- The bug this catches has shipped in this project before: a host container SIZES
            -- NOTHING, so a child asking for height = "fill" can end up 0 tall while every other
            -- assertion passes. An empty frameless log with no height is indistinguishable in game
            -- from one that is simply quiet.
            local p = enabled()
            expect(H.box(p._chat:ActiveLog()).height).gt(20)
            expect(H.box(p._chat:ActiveLog()).width).gt(100)
        end)

        it("leaves room for the chip below the log", function()
            local p = enabled()
            local log, chip = H.box(p._chat:ActiveLog()), H.box(p._chat._chip)
            expect(chip.top).as("the chip sits BELOW the log (larger .top)").gt(log.top)
            expect(chip.height).gt(0)
        end)

        it("sizes from the width and height settings", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "width", 520)
            H.SuuUI.Settings:Set("chat", "height", 240)
            H.expectSize(p._chat._wrapper, 520, 240)
        end)

        it("fades, because General is a channel tab", function()
            local p = enabled()
            expect(p._chat:ActiveLog():IsFading())
                .as("channels fade, conversations persist").eq(true)
        end)

        it("stops fading when the setting is off", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "fade_channels", false)
            expect(p._chat:ActiveLog():IsFading()).eq(false)
        end)

        it("takes its font step from the setting", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "font_size", "lg")
            expect(p._chat:ActiveLog():GetFontSize()).eq("lg")
        end)

        it("registers as a moveable frame so edit mode can place it", function()
            local p = enabled()
            local found = false
            for _, f in ipairs(H.SuuUI.ToggleUI:GetAll()) do
                if f == p._chat._wrapper then found = true end
            end
            expect(found).eq(true)
        end)

        it("does not touch Blizzard's chat in 4a", function()
            enabled()
            expect(H.env.ChatFrame1 == nil or H.env.ChatFrame1:IsShown() ~= false)
                .as("suppression is 4b, deliberately separate -- a wrong call here must cost a "
                    .. "misplaced window, not an unreadable chat").truthy()
        end)
    end)

    describe("message routing", function()
        it("shows a guild message", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "kara tonight?", sender = "Thalvyn" })
            expect(p._chat:LogFor("guild"):GetNumMessages()).eq(1)
            expect((p._chat:LogFor("guild"):GetMessageInfo(1))).contains("kara tonight?")
        end)

        it("shows a say message", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hello", sender = "Grimtusk" })
            expect(p._chat:ActiveLog():GetNumMessages()).eq(1)
        end)

        it("IGNORES an event no tab claims", function()
            local p = enabled()
            -- PING is declared by this client and routed nowhere. It never reaches the handler
            -- because REGISTRATION derives from the same map -- which is why there is no guard
            -- inside the handler; mutation testing proved one unreachable.
            H.chat("CHAT_MSG_PING", { text = "should not show" })
            expect(p._chat:ActiveLog():GetNumMessages())
                .as("registration is the gate, not a runtime check").eq(0)
        end)

        it("puts loot and XP in the LOG panel, not in General", function()
            local p = enabled()
            H.chat("CHAT_MSG_LOOT", { text = "You receive loot." })
            H.chat("CHAT_MSG_COMBAT_XP_GAIN", { text = "You gain 500 experience." })
            expect(p._chat:LogFor("log"):GetNumMessages())
                .as("non-conversation traffic has its own panel under the routing ruling").eq(2)
            expect(p._chat:LogFor("general"):GetNumMessages())
                .as("General is CONVERSATION only, so loot never reaches it").eq(0)
        end)

        it("keeps each panel's traffic to itself", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY",   { text = "hello",  sender = "A" })
            H.chat("CHAT_MSG_GUILD", { text = "kara?",  sender = "B" })
            H.chat("CHAT_MSG_LOOT",  { text = "loot" })
            expect(p._chat:LogFor("general"):GetNumMessages()).eq(1)
            expect(p._chat:LogFor("guild"):GetNumMessages()).eq(1)
            expect(p._chat:LogFor("log"):GetNumMessages()).eq(1)
        end)

        it("routes a record to EVERY panel that accepts it, not the first", function()
            local p = enabled()
            H.chat("CHAT_MSG_LOOT", { text = "You receive loot." })
            local recs = p._chat._store:Records()
            expect(#recs).eq(1)
            expect(recs[1].panels)
                .as("routing hands back a LIST, which is what lets one message be in two panels")
                .neq(nil)
            expect(recs[1].panels[1]).eq("log")
        end)

        it("stores the structured record, not only the rendered line", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "kara?", sender = "Thalvyn-TestRealm" })
            local rec = p._chat._store:Records()[1]
            expect(rec.kind).eq("GUILD")
            expect(rec.message).eq("kara?")
            expect(rec.sender).as("the display name is realm-stripped").eq("Thalvyn")
            expect(rec.senderFull)
                .as("the full name survives, because a whisper resolves against it")
                .eq("Thalvyn-TestRealm")
            expect(rec.stream).eq("type:guild")
        end)

        it("keeps a whisper's conversation on its own stream", function()
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sulisande-Goldensands" })
            local rec = p._chat._store:Records()[1]
            expect(rec.stream)
                .as("per-conversation retention is what makes whisper history storable")
                .eq("whisper:sulisande-goldensands")
        end)

        it("routes a whisper by whisper_mode, NOT by any panel's group list", function()
            -- The assertion a survivor exposed as missing: no shipped panel lists WHISPER, so
            -- routing a whisper through the group filter returns NO panels and the line silently
            -- never renders. Asserting the stream alone could not tell the two apart.
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sulisande-Goldensands" })
            local rec = p._chat._store:Records()[1]
            expect(#rec.panels).as("a whisper must reach at least one panel").gt(0)
            expect(p._chat:ActiveLog():GetNumMessages())
                .as("and it must actually be rendered -- a lost whisper is the worst outcome")
                .eq(1)
            local ids = {}
            for _, id in ipairs(rec.panels) do ids[id] = true end
            expect(ids["general"]).as("whisper_mode defaults to both").truthy()
            expect(ids["whisper:sulisande-goldensands"]).truthy()
        end)

        it("registers only the events some panel actually wants", function()
            local p = enabled()
            local events = H.SuuUI.ChatPanels.Events(p._chat._panels, H.env.ChatTypeGroup)
            local set = {}
            for _, e in ipairs(events) do set[e] = true end
            expect(set["CHAT_MSG_LOOT"]).as("the Log panel wants loot").truthy()
            expect(set["CHAT_MSG_GUILD"]).truthy()
            expect(set["CHAT_MSG_WHISPER"])
                .as("whisper groups register regardless of the panels, because a conversation "
                    .. "panel does not exist until someone whispers you").truthy()
        end)

        it("does NOT print the player's own language", function()
            -- The bug this pins was visible in game: every line read
            -- `08:31 SAY Sulisande-Thunderstrike says: [Common] test`. The client sends a language
            -- on every chat event, so printing it unconditionally labels all of them.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "test", sender = "Thalvyn", language = "Common" })
            expect((p._chat:ActiveLog():GetMessageInfo(1)):find("[Common]", 1, true))
                .as("Blizzard gates this on the language being DIFFERENT").eq(nil)
        end)

        it("DOES print a language the player does not speak", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "lok'tar", sender = "Grimtusk", language = "Orcish" })
            expect((p._chat:ActiveLog():GetMessageInfo(1))).contains("Orcish")
        end)

        it("strips the player's own realm from the displayed name", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Sulisande-TestRealm", lineID = 5 })
            -- The raw line necessarily CONTAINS the full name, because the link target keeps it.
            -- What matters is the DISPLAY segment between |h and |h.
            expect((p._chat:ActiveLog():GetMessageInfo(1)))
                .as("the realm is noise on every line for a same-realm player")
                .contains("|hSulisande|h")
        end)

        it("keeps the FULL name in the link, which is what a whisper needs", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Sulisande-TestRealm", lineID = 5 })
            expect((p._chat:ActiveLog():GetMessageInfo(1)))
                .as("only the displayed text is shortened")
                .contains("|Hplayer:Sulisande-TestRealm:5|h")
        end)

        it("does not print the channel verb beside the tag", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "test", sender = "Thalvyn" })
            local text = p._chat:ActiveLog():GetMessageInfo(1)
            expect(text).contains("SAY")
            expect(text:find("says", 1, true))
                .as("`SAY Thalvyn says: test` says it twice").eq(nil)
        end)

        it("colours a line from ChatTypeInfo, not from a token", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "hi", sender = "Thalvyn" })
            local _, r, g, b = p._chat:LogFor("guild"):GetMessageInfo(1)
            local info = H.env.ChatTypeInfo.GUILD
            expect(g).as("a channel's colour is a game fact").near(info.g, 0.01)
            expect(r).near(info.r, 0.01)
            expect(b).near(info.b, 0.01)
        end)

        it("carries the lineID through, so a name stays right-clickable", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "hi", sender = "Thalvyn", lineID = 77 })
            local _, _, _, _, id = p._chat:LogFor("guild"):GetMessageInfo(1)
            expect(id).eq(77)
        end)

        it("builds a player link containing the lineID", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "hi", sender = "Thalvyn", lineID = 91 })
            expect((p._chat:LogFor("guild"):GetMessageInfo(1)))
                .as("SetItemRef needs it; dropping it degrades right-click silently")
                .contains("|Hplayer:Thalvyn:91|h")
        end)
    end)

    describe("the rail", function()
        it("is COLLAPSED at rest, so the log keeps its width", function()
            local p = enabled()
            expect(p._chat:IsRailExpanded()).falsy()
            expect(p._chat._rows["general"]:IsShowingLabel())
                .as("the concept's resting rail is discs only").falsy()
        end)

        it("widens the ROWS when the cursor enters one, not the rail's cell", function()
            local p = enabled()
            local rowBefore = H.box(p._chat._rows["general"]).width
            H.hover(p._chat._rows["guild"])
            expect(p._chat:IsRailExpanded()).truthy()
            expect(p._chat._rows["general"]:IsShowingLabel())
                .as("EVERY row's name appears, not just the hovered one").truthy()
            expect(H.box(p._chat._rows["general"]).width)
                .as("the row grows to hold the name").gt(rowBefore)
        end)

        it("does NOT move the log or the chip when it expands", function()
            -- The defect this pins was measured in game at ~70 units of travel: the rail and the
            -- column are flow siblings, so growing the rail's cell pushed the column -- which means
            -- hovering to read a name re-wraps every line of chat and slides the resting chip
            -- sideways. The names overlay the log instead.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hello there", sender = "Grimtusk" })
            local chipBefore = H.box(p._chat._chip).left
            local logBefore  = H.box(p._chat:LogFor("general")).left
            H.hover(p._chat._rows["guild"])
            expect(p._chat:IsRailExpanded()).as("it did expand").truthy()
            expect(H.box(p._chat._chip).left)
                .as("the resting chip must not slide sideways on a hover").eq(chipBefore)
            expect(H.box(p._chat:LogFor("general")).left)
                .as("and the log must not re-wrap").eq(logBefore)
        end)

        it("sizes the expanded rail to the WIDEST name, not the first", function()
            -- Otherwise the log's left edge shifts as the cursor moves down the list. The SHIPPED
            -- names hide this -- "General" is both first and longest -- so a mutation taking the
            -- first name survived. Staged so the widest is LAST.
            local p = enabled()
            p._chat._panels = {
                { id = "a", name = "Ab",                 groups = { "SAY" } },
                { id = "b", name = "A much longer name", groups = { "GUILD" } },
            }
            local font = H.SuuUI.Fonts:Path(H.token("fontFamilyMain"))
            local size = H.SuuUI.Theme:GetFontSize("md")
            local short = H.SuuUI.TextMetrics.Box("Ab", font, size)
            local long  = H.SuuUI.TextMetrics.Box("A much longer name", font, size)
            expect(p._chat:_railWidth(true) - p._chat:_railWidth(false) - H.token("spaceXs"))
                .as("the widest name decides the width").near(long, 1)
            expect(long).gt(short)
        end)

        it("reserves the MARKER column in the collapsed width", function()
            -- An absolute assertion, because comparing collapsed against expanded cannot see a
            -- column missing from both.
            local p = enabled()
            expect(p._chat:_railWidth(false))
                .as("2px marker + gap + disc")
                .near(H.SuuUI.Pixel.Line(2) + H.token("spaceXs") + H.token("sizeControlSm"), 0.5)
        end)

        it("collapses again when the cursor leaves the rail as a region", function()
            local p = enabled()
            H.hover(p._chat._rows["guild"])
            expect(p._chat:IsRailExpanded()).truthy()
            p._chat:SetRailExpanded(false)
            expect(p._chat._rows["general"]:IsShowingLabel()).falsy()
        end)

        it("keeps the marker column reserved, so rows do not shift on switch", function()
            local p = enabled()
            local before = H.box(p._chat._rows["guild"]).left
            p._chat:SetActivePanel("guild")
            expect(H.box(p._chat._rows["guild"]).left).eq(before)
        end)

        it("has one row per panel, channels first", function()
            local p = enabled()
            expect(p._chat._rows["general"]).notNil()
            expect(p._chat._rows["guild"]).notNil()
            expect(p._chat._rows["log"]).notNil()
        end)

        it("marks the active panel and dims the rest", function()
            local p = enabled()
            expect(p._chat:GetActivePanel()).as("the first panel opens").eq("general")
            expect(p._chat._rows["general"]:IsActive()).truthy()
            expect(p._chat._rows["guild"]:IsActive()).falsy()
        end)

        it("dims an inactive avatar's disc, which the concept states outright", function()
            local p = enabled()
            local _, _, _, activeA = p._chat._rows["general"]._disc._tex:GetVertexColor()
            local _, _, _, idleA   = p._chat._rows["guild"]._disc._tex:GetVertexColor()
            expect(activeA).near(1, 0.01)
            expect(idleA).as("`.rw.dim .av { opacity:.5 }`").near(H.token("opacityRailIdle"), 0.01)
        end)

        it("gives General a NEUTRAL disc, since it is not one channel", function()
            local p = enabled()
            local r, g, b = p._chat._rows["general"]._disc._tex:GetVertexColor()
            local grey = H.token("colorGray600")
            expect(r).near(grey[1], 0.02)
            expect(g).near(grey[2], 0.02)
            expect(b).near(grey[3], 0.02)
        end)

        it("gives Guild the CHANNEL's own colour, which is a game fact", function()
            local p = enabled()
            local _, g = p._chat._rows["guild"]._disc._tex:GetVertexColor()
            expect(g).near(H.env.ChatTypeInfo.GUILD.g, 0.02)
        end)

        it("switches the visible log when a row is clicked", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "kara?", sender = "Thalvyn" })
            expect(p._chat:LogFor("guild"):IsShown()).as("not the active panel yet").falsy()
            H.click(p._chat._rows["guild"])
            expect(p._chat:GetActivePanel()).eq("guild")
            expect(p._chat:LogFor("guild"):IsShown()).truthy()
            expect(p._chat:LogFor("general"):IsShown()).falsy()
        end)

        it("ignores a switch to a panel that does not exist", function()
            local p = enabled()
            p._chat:SetActivePanel("whisper:nobody")
            expect(p._chat:GetActivePanel()).eq("general")
        end)

        it("is silent on a switch to the panel already open", function()
            -- Re-showing a log the player has scrolled up in would jump them to the bottom.
            local p = enabled()
            local log = p._chat:LogFor("general")
            log:ScrollUp()
            local at = log:AtBottom()
            p._chat:SetActivePanel("general")
            expect(log:AtBottom()).eq(at)
        end)
    end)

    describe("per-panel log shape", function()
        it("fades a CHANNEL panel and not the Log", function()
            local p = enabled()
            H.chat("CHAT_MSG_LOOT", { text = "loot" })
            expect(p._chat:LogFor("general"):IsFading())
                .as("channel traffic fades out of a frameless log").truthy()
            expect(p._chat:LogFor("log"):IsFading())
                .as("the Log exists to be searched afterwards; a faded line cannot be").falsy()
        end)

        it("gives a CONVERSATION chrome and no fading, per the concept", function()
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sylvaine-TestRealm" })
            local log = p._chat:LogFor("whisper:sylvaine-testrealm")
            expect(log).as("a conversation panel is created on the first whisper").notNil()
            expect(log:HasChrome())
                .as("a conversation is history you read, so it earns a panel").truthy()
            expect(log:IsFading()).falsy()
        end)

        it("omits the tag in a conversation, where the chip already names the person", function()
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sylvaine-TestRealm" })
            expect((p._chat:LogFor("whisper:sylvaine-testrealm"):GetMessageInfo(1)):find("WHIS", 1, true))
                .eq(nil)
        end)

        it("adds a rail row for a new conversation, below the channels", function()
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sylvaine-TestRealm" })
            local row = p._chat._rows["whisper:sylvaine-testrealm"]
            expect(row).notNil()
            expect(row:GetLabel()).eq("Sylvaine")
            expect(H.box(row).top)
                .as("a conversation sits BELOW the channels, i.e. a larger .top")
                .gt(H.box(p._chat._rows["log"]).top)
        end)

        it("omits the tag in a SINGLE-group panel, where it would be constant", function()
            -- The shipped panels all carry several groups, so `> 1` was true for every one of them
            -- and a mutation forcing the tag on survived. A per-channel panel is the real case and
            -- exactly what an editable panel list is for; the rule is asserted directly because
            -- staging one through the plugin's lifecycle tests the lifecycle, not the rule.
            local p = enabled()
            expect(p._chat:_wantsTag({ id = "trade", groups = { "CHANNEL" } }))
                .as("one group means the tag is the same word on every line").falsy()
            expect(p._chat:_wantsTag({ id = "guild", groups = { "GUILD", "OFFICER" } }))
                .as("two groups means the tag distinguishes guild from officer").truthy()
            expect(p._chat:_wantsTag({ id = "whisper:x", streams = { "whisper:x" } }))
                .as("a conversation carries no groups at all, so the same rule covers it").falsy()
        end)

        it("re-resolves fading per panel when a setting changes AFTER the logs exist", function()
            -- _logFor sets fading at creation, so a mutation to _apply's per-panel branch was
            -- invisible until a setting change drove it over logs that already existed.
            local p = enabled()
            H.chat("CHAT_MSG_SAY",  { text = "hi", sender = "A" })
            H.chat("CHAT_MSG_LOOT", { text = "loot" })
            H.SuuUI.Settings:Set("chat", "fade_after", 12)
            expect(p._chat:LogFor("general"):IsFading()).as("a channel still fades").truthy()
            expect(p._chat:LogFor("log"):IsFading())
                .as("and the Log still does not, after _apply re-ran").falsy()
        end)

        it("repaints the rail's active markers on a switch", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "kara?", sender = "Thalvyn" })
            p._chat:SetActivePanel("guild")
            expect(p._chat._rows["guild"]:IsActive()).as("the new row lights up").truthy()
            expect(p._chat._rows["general"]:IsActive()).as("and the old one goes dark").falsy()
        end)

        it("re-selecting the open panel leaves everything as it was", function()
            -- Pins what is actually observable today. The same-id early-out is an OPTIMISATION:
            -- removing it changes nothing here, because re-showing an already-shown log does not
            -- touch its scroll position. See the xit below for what would make it load-bearing.
            local p = enabled()
            for i = 1, 40 do H.chat("CHAT_MSG_SAY", { text = "m" .. i, sender = "A" }) end
            local log = p._chat:LogFor("general")
            log:PageUp()
            local at = log:AtBottom()
            p._chat:SetActivePanel("general")
            expect(p._chat:GetActivePanel()).eq("general")
            expect(log:IsShown()).truthy()
            expect(log:AtBottom()).eq(at)
        end)

        xit("restores each panel's own scroll position on switch", function()
            -- Not implemented. Once a switch RESTORES scroll rather than merely showing the log,
            -- re-selecting the open panel would re-apply a stale saved offset and jerk a reader who
            -- had scrolled since -- which is the point at which SetActivePanel's same-id early-out
            -- stops being an optimisation and becomes correctness. Phase 8, with jump-to-bottom.
        end)

        it("creates the conversation panel BEFORE routing, so 'panel' mode reaches it", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "whisper_mode", "panel")
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sylvaine-TestRealm" })
            local rec = p._chat._store:Records()[1]
            expect(rec.panels[1])
                .as("routed to its own panel, not to the fallback")
                .eq("whisper:sylvaine-testrealm")
            expect(p._chat:LogFor("whisper:sylvaine-testrealm"):GetNumMessages()).eq(1)
            expect(p._chat:LogFor("general"):GetNumMessages())
                .as("'panel' mode means General does NOT get a copy").eq(0)
        end)

        it("reuses one conversation panel across many whispers", function()
            local p = enabled()
            for i = 1, 3 do
                H.chat("CHAT_MSG_WHISPER", { text = "m" .. i, sender = "Sylvaine-TestRealm" })
            end
            expect(p._chat:LogFor("whisper:sylvaine-testrealm"):GetNumMessages()).eq(3)
            -- The PANEL LIST is what a duplicate grows: _rows and _logs are keyed by panel id, so
            -- a second panel with the same id is invisible in both.
            expect(#p._chat._panels).as("three channels plus ONE conversation").eq(4)
        end)

        it("never drops a message with nowhere to go", function()
            -- whisper_mode "panel" names a conversation panel. If creating it ever failed, the
            -- line must still land somewhere -- a silently lost whisper is the worst outcome here.
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "whisper_mode", "panel")
            p._chat._ensureConversation = function() return nil end
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Ghost-TestRealm" })
            local total = 0
            for _, log in pairs(p._chat._logs) do total = total + log:GetNumMessages() end
            expect(total).as("delivered to the fallback panel rather than dropped").eq(1)
        end)
    end)


    describe("the adopted input", function()
        it("adopts Blizzard's edit box into our window at login", function()
            -- Without this the box stays a child of the suppressed ChatFrame1, so pressing Enter
            -- opens an input the player cannot see.
            local p = enabled()
            expect(H.env.ChatFrame1.editBox:GetParent())
                .as("ours, not Blizzard's hidden holder").eq(p._chat._inputRow)
        end)

        it("NEVER hides the box's parent, which is what broke typing", function()
            -- The defect this pins made chat unusable: the row was created hidden and the box
            -- adopted into it, so (a) a child of a hidden parent draws nothing and cannot take
            -- keyboard focus, and (b) the box was added to a container hosted on that hidden frame,
            -- which is the documented "show a container before anchoring a foreign child" failure --
            -- the child never resolves a rect. Enter opened a box that was not really there.
            local p = enabled()
            local box = H.env.ChatFrame1.editBox
            expect(box:GetParent()).eq(p._chat._inputRow)
            expect(p._chat._inputRow:IsShown())
                .as("the box's parent is shown at rest and always").truthy()
            H.SuuUI._ChatInput.Open()
            expect(p._chat._inputRow:IsShown()).truthy()
            H.SuuUI._ChatInput.Close()
            expect(p._chat._inputRow:IsShown())
                .as("and STILL shown when closed -- only its paint changes").truthy()
        end)

        it("paints the row only while the box is open", function()
            -- There is no panel and no field at rest, so the row carries its box and its place while
            -- drawing nothing.
            local p = enabled()
            local function borderAlpha()
                local _, _, _, a = p._chat._inputRow:GetBackdropBorderColor()
                return a or 0
            end
            local function bgAlpha()
                local _, _, _, a = p._chat._inputRow:GetBackdropColor()
                return a or 0
            end
            expect(borderAlpha()).as("nothing painted at rest").near(0, 0.01)
            expect(bgAlpha()).as("no surface at rest either").near(0, 0.01)
            H.SuuUI._ChatInput.Open()
            expect(borderAlpha()).as("the open field wears a border").gt(0)
            -- The BACKGROUND too, and asserting it is what makes the open branch load-bearing: the
            -- border alone is repainted by the chip refresh from the channel colour, so a mutation
            -- deleting the paint left a bordered field with no surface and went unnoticed.
            expect(bgAlpha()).as("and a surface to read the text against").gt(0)
            H.SuuUI._ChatInput.Close()
            expect(borderAlpha()).near(0, 0.01)
            expect(bgAlpha()).near(0, 0.01)
        end)

        it("keeps the chip on the row, so it labels the field when it opens", function()
            -- The concept puts the resting chip and the open field on the SAME line, so the chip is
            -- reused rather than duplicated -- one widget, so the two states cannot disagree about
            -- where a message is going.
            local p = enabled()
            expect(p._chat._chip:GetFrame():GetParent()).eq(p._chat._inputRow)
        end)

        it("reads the chip from the BOX, so it names the real channel", function()
            -- Phase 4a printed a literal "Say" because ChatTypeInfo.sticky is the wrong source.
            -- Driven through OPENING the box rather than calling the refresh by hand, so the wiring
            -- is under test and not just the read.
            local p = enabled()
            H.env.ChatFrame1.editBox.chatType = "GUILD"
            H.SuuUI._ChatInput.Open()
            expect(p._chat._chip:GetText())
                .as("the chip follows the box without anyone refreshing it").eq("Guild")
        end)

        it("follows the channel changing while the box STAYS open, as Tab does", function()
            local p = enabled()
            H.SuuUI._ChatInput.Open()
            local box = H.env.ChatFrame1.editBox
            box.chatType = "PARTY"
            -- Tab cycles the channel in place; a text change is the only script that fires then.
            box:SetText("x")
            expect(p._chat._chip:GetText()).eq("Party")
        end)

        it("names the PERSON for a whisper, not the word Whisper", function()
            local p = enabled()
            local box = H.env.ChatFrame1.editBox
            box.chatType, box.tellTarget = "WHISPER", "Sylvaine-TestRealm"
            p._chat:_refreshChip()
            expect(p._chat._chip:GetText())
                .as("the chip answers WHERE this is going, and a name is that answer")
                .contains("Sylvaine")
            expect(p._chat._chip:GetText():find("TestRealm", 1, true))
                .as("own realm stripped, as everywhere else").eq(nil)
        end)

        it("colours the chip and the field's border from the channel", function()
            local p = enabled()
            H.env.ChatFrame1.editBox.chatType = "GUILD"
            p._chat:_refreshChip()
            local _, g = p._chat._chip._label:GetTextColor()
            expect(g).near(H.env.ChatTypeInfo.GUILD.g, 0.02)
        end)

        it("hands the box back on disable, before our window hides", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "enabled", false)
            expect(H.env.ChatFrame1.editBox:GetParent())
                .as("or the player has no visible input in EITHER chat")
                .eq(H.env.ChatFrame1)
        end)
    end)

    describe("the timestamp and tag settings reach the line", function()
        it("prefixes a timestamp when on", function()
            local p = enabled()
            H.setClock({ year = 2026, month = 8, day = 27, hour = 19, min = 41, sec = 0 })
            H.chat("CHAT_MSG_GUILD", { text = "hi", sender = "Thalvyn" })
            expect((p._chat:LogFor("guild"):GetMessageInfo(1))).contains("19:41")
        end)

        it("follows the timestamp FORMAT setting", function()
            -- Asserting the 24h reading cannot discriminate: dropping the setting falls back to
            -- the same 24h default, so the mutation survives. The 12-hour form is the only
            -- reading where present and absent differ.
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "timestamp_format", "12h")
            H.setClock({ year = 2026, month = 8, day = 27, hour = 19, min = 41, sec = 0 })
            H.chat("CHAT_MSG_GUILD", { text = "hi", sender = "Thalvyn" })
            expect((p._chat:LogFor("guild"):GetMessageInfo(1))).contains("7:41 PM")
        end)

        it("omits it when off", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "show_timestamps", false)
            H.setClock({ year = 2026, month = 8, day = 27, hour = 19, min = 41, sec = 0 })
            H.chat("CHAT_MSG_GUILD", { text = "hi", sender = "Thalvyn" })
            expect((p._chat:LogFor("guild"):GetMessageInfo(1)):find("19:41", 1, true)).eq(nil)
        end)

        it("prefixes the channel tag when on", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "hi", sender = "Thalvyn" })
            expect((p._chat:LogFor("guild"):GetMessageInfo(1))).contains("GLD")
        end)

        it("omits the tag when off, and the bracket stays stripped", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "show_tags", false)
            H.chat("CHAT_MSG_GUILD", { text = "hi", sender = "Thalvyn" })
            local text = p._chat:LogFor("guild"):GetMessageInfo(1)
            expect(text:find("GLD", 1, true)).eq(nil)
            expect(text:find("[Guild]", 1, true))
                .as("the globalstring's own bracket goes either way").eq(nil)
        end)
    end)

    describe("the resting chip", function()
        it("names the channel Enter would open", function()
            local p = enabled()
            expect(p._chat._chip:GetText()).notNil()
            expect(#p._chat._chip:GetText()).gt(0)
        end)

        it("does NOT read the sticky flags, which cannot answer the question", function()
            -- say, party, raid, guild, officer and whisper ALL carry sticky = 1 in the client's
            -- defaults, so the flag means "may be remembered", not "was last used". Reading it
            -- returns whichever type is checked first, which is arbitrary dressed as
            -- authoritative. Real tracking lives on the edit box, adopted in Phase 5.
            H.env.ChatTypeInfo.GUILD.sticky = 1
            local p = enabled()
            expect(p._chat._chip:GetText())
                .as("4a states the honest default rather than guessing").eq("Say")
        end)

        it("takes its colour from ChatTypeInfo", function()
            local p = enabled()
            local say = H.env.ChatTypeInfo.SAY
            local r = p._chat._chip._label:GetTextColor()
            expect(r).as("a channel's colour is a game fact, not a token").near(say.r, 0.02)
        end)
    end)

    describe("lifecycle", function()
        it("hides the window when disabled", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "enabled", false)
            expect(p._chat._wrapper:IsShown()).eq(false)
        end)

        it("shows it again when re-enabled, reusing the same window", function()
            local p = enabled()
            local first = p._chat
            H.SuuUI.Settings:Set("chat", "enabled", false)
            H.SuuUI.Settings:Set("chat", "enabled", true)
            expect(p._chat).as("re-enabling must not build a second window").eq(first)
            expect(p._chat._wrapper:IsShown()).eq(true)
        end)

        it("drops its shape watchers on disable", function()
            local p = enabled()
            local before = H.SuuUI.Settings:GetWatcherCount()
            H.SuuUI.Settings:Set("chat", "enabled", false)
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("a watcher outlives the frame it drives unless something drops it")
                .lt(before)
        end)

        it("does not accumulate watchers across an enable cycle", function()
            local p = enabled()
            local baseline = H.SuuUI.Settings:GetWatcherCount()
            for _ = 1, 3 do
                H.SuuUI.Settings:Set("chat", "enabled", false)
                H.SuuUI.Settings:Set("chat", "enabled", true)
            end
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("a subscription leak is invisible until it fires into freed state")
                .lte(baseline)
        end)
    end)
end)
