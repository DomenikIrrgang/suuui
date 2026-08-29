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

    describe("history persistence", function()
        -- The store's own Serialise/Restore round-trip is covered in 65_chatstore_panels_spec.
        -- What is tested HERE is the wiring that was missing entirely: the store had both methods
        -- and nothing called either, so history did not survive a logout.

        it("writes the store into the per-character SavedVariable at logout", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "kara?", sender = "Thalvyn" })
            expect(H.env.SuuUIChatHistory).as("nothing written before logout").eq(nil)
            H.fireEvent("PLAYER_LOGOUT")
            local blob = H.env.SuuUIChatHistory
            expect(blob).as("PLAYER_LOGOUT is the only moment it is written").notNil()
            expect(type(blob.streams)).eq("table")
            local found = false
            for _, recs in pairs(blob.streams) do
                for _, r in ipairs(recs) do
                    if r.message == "kara?" then found = true end
                end
            end
            expect(found).as("the message itself, not just the shape").eq(true)
        end)

        it("comes back from the SavedVariable on the next session", function()
            -- Driven through the REAL writer rather than a hand-built blob: a staged table would
            -- assert the staging, and this project has already shipped a bug where every spec staged
            -- a state the production writer cannot produce.
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "remember me", sender = "Thalvyn" })
            H.fireEvent("PLAYER_LOGOUT")
            local blob = H.env.SuuUIChatHistory

            -- A fresh session: new client, new plugin, with that blob already on disk.
            H.setup({ savedVars = { SuuUIChatHistory = blob } })
            local p2 = enabled()
            expect(p2._chat._store:StreamCount())
                .as("the store is built FROM the SavedVariable, not empty").gt(0)
            local recs = p2._chat._store:Records()
            local found = false
            for _, r in ipairs(recs) do if r.message == "remember me" then found = true end end
            expect(found).as("the line survived the relog").eq(true)

            -- And that it was RENDERED. Asserting the store alone proved only that `Restore` ran:
            -- deleting the `_replayHistory()` call left this test green, because a restored store with
            -- nothing on screen satisfies every assertion above. A mutation found that.
            --
            -- Searched across EVERY panel's log rather than the active one: a guild line correctly
            -- lands on the Guild panel while General stays active, so asserting on `ActiveLog()` here
            -- reads 0 for a completely correct render.
            local shown = false
            for _, log in pairs(p2._chat._logs) do
                for i = 1, log:GetNumMessages() do
                    if tostring(log:GetMessageInfo(i)):find("remember me", 1, true) then
                        shown = true
                    end
                end
            end
            expect(shown).as("replayed into a log, not just into the store").eq(true)
        end)

        it("takes the depth from the SETTING, not from the stored blob", function()
            -- A player who lowered the slider between sessions expects the next login to trim, not to
            -- honour whatever depth was in force when the history was written.
            local p = enabled()
            H.fireEvent("PLAYER_LOGOUT")
            local blob = H.env.SuuUIChatHistory
            blob.depth = 500

            -- Asserted at BUILD time against the setting's own default, with NO Set() call: writing
            -- the setting afterwards made this pass through the `history_depth` watcher instead of
            -- through the build, so deleting the build-time SetDepth left it green. A mutation found
            -- that, and it is the difference between testing the line and testing its neighbour.
            H.setup({ savedVars = { SuuUIChatHistory = blob } })
            local p2 = enabled()
            local want = H.SuuUI.Settings:Get("chat", "history_depth")
            expect(want).as("the default, so the blob's 500 cannot coincide with it").lt(500)
            expect(p2._chat._store:GetDepth())
                .as("the setting wins over the blob's stored depth").eq(want)
        end)

        it("survives an absent SavedVariable, which is every fresh install", function()
            H.env.SuuUIChatHistory = nil
            local p = enabled()
            expect(p._chat._store).as("Restore(nil) yields an empty store, so there is ONE path").notNil()
            expect(p._chat._store:StreamCount()).eq(0)
        end)

        it("replays without re-adding, so the store does not double", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "one", sender = "Thalvyn" })
            H.fireEvent("PLAYER_LOGOUT")
            local blob = H.env.SuuUIChatHistory

            H.setup({ savedVars = { SuuUIChatHistory = blob } })
            local p2 = enabled()
            -- Replay ran during the build. Re-adding through Add would renumber every sequence and
            -- destroy the interleaving that restoring by sequence exists to preserve.
            expect(#p2._chat._store:Records())
                .as("one stored line stays one line after replay").eq(1)
        end)

        it("does not count replayed history as unread", function()
            -- Otherwise every badge reads the full depth on login, which is exactly the noise the
            -- badge exists to make meaningful.
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sylvaine-TestRealm" })
            H.fireEvent("PLAYER_LOGOUT")
            local blob = H.env.SuuUIChatHistory

            H.setup({ savedVars = { SuuUIChatHistory = blob } })
            local p2 = enabled()
            for id, row in pairs(p2._chat._rows) do
                expect(row:GetCount())
                    .as("restored history is what you already read: " .. tostring(id)).eq(nil)
            end
        end)

        it("leaves replayed history FULLY FADED when fading is on", function()
            -- A line's fade clock starts when it is ADDED, so replayed history would otherwise be as
            -- prominent as a message that just arrived and then fade out all together.
            --
            -- `_replayHistory` is driven DIRECTLY rather than through a login, because the setting is
            -- read while the window builds and the window builds inside `H.setup()` -- reaching the
            -- login ordering would mean staging a whole fake `SuuUIProfiles`, and a hand-built
            -- profile is exactly the shape production may not produce. The branch is the same one
            -- either way; what is untested is only that a stored preference arrives before the build.
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "old news", sender = "Thalvyn" })
            H.SuuUI.Settings:Set("chat", "fade_channels", true)
            p._chat:_replayHistory()
            expect(p._chat:ActiveLog():IsFaded())
                .as("present but not shouting; hover reveals it").eq(true)
        end)

        it("shows replayed history immediately when fading is OFF, which is the default", function()
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "old news", sender = "Thalvyn" })
            H.fireEvent("PLAYER_LOGOUT")
            local blob = H.env.SuuUIChatHistory

            H.setup({ savedVars = { SuuUIChatHistory = blob } })
            local p2 = enabled()
            expect(p2._chat:ActiveLog():IsFaded())
                .as("a player who turned fading off wants to see it").eq(false)
        end)
    end)

    describe("unread counts", function()
        -- `Avatar` drew this badge from the start and NOTHING ever set it -- the same unwired
        -- component as the hyperlink click and the ActionButton tooltip before it.

        it("counts a line that lands on a panel you are not reading", function()
            local p = enabled()
            expect(p._chat:GetActivePanel()).as("General is active at rest").eq("general")
            H.chat("CHAT_MSG_GUILD", { text = "kara?", sender = "Thalvyn" })
            expect(p._chat._rows["guild"]:GetCount()).eq(1)
        end)

        it("never counts the panel you ARE reading", function()
            -- A badge over the tab you are looking at can only say "you have read this".
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Thalvyn" })
            expect(p._chat._rows["general"]:GetCount())
                .as("the active panel's messages are already on screen").eq(nil)
        end)

        it("clears only the panel being opened, so the badge means WAITING", function()
            -- Zeroing every count on a switch would make the badge mean "since you last changed
            -- tabs", which is a different and much less useful statement.
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "one", sender = "Thalvyn" })
            H.chat("CHAT_MSG_LOOT",  { text = "loot" })
            expect(p._chat._rows["guild"]:GetCount()).eq(1)
            expect(p._chat._rows["log"]:GetCount()).eq(1)
            p._chat:SetActivePanel("guild")
            expect(p._chat._rows["guild"]:GetCount()).as("read, so cleared").eq(nil)
            expect(p._chat._rows["log"]:GetCount()).as("still waiting for you").eq(1)
            -- The CONSEQUENCE, and the assertion that actually discriminates: the Log's count must
            -- CONTINUE rather than restart. Reading the badge alone could not see the table being
            -- cleared behind it -- a mutation that zeroed every entry left the stale badge in place
            -- and this test green, because only the opened panel's row is ever re-set.
            H.chat("CHAT_MSG_LOOT", { text = "more loot" })
            expect(p._chat._rows["log"]:GetCount())
                .as("continues from 1 rather than restarting").eq(2)
        end)

        it("keeps the count when the rail is REBUILT", function()
            -- The rail is rebuilt whenever a conversation appears, so a rebuild that reset every
            -- badge would silently discard exactly what the badge exists to advertise.
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "one", sender = "Thalvyn" })
            expect(p._chat._rows["guild"]:GetCount()).eq(1)
            -- A whisper creates a conversation panel, which rebuilds the rail.
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sylvaine-TestRealm" })
            expect(p._chat._rows["guild"]:GetCount())
                .as("survived the rebuild the whisper triggered").eq(1)
        end)

        it("counts a whisper against its own new conversation panel", function()
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sylvaine-TestRealm" })
            local row = p._chat._rows["whisper:sylvaine-testrealm"]
            expect(row).as("the conversation got a rail row").notNil()
            expect(row:GetCount()).as("and its first whisper is unread").eq(1)
        end)
    end)

    describe("the rail's size is a setting", function()
        it("WIDENS when expanded, so the log moves instead of being covered", function()
            -- It used to overlay: the rail kept its collapsed width and each row's name overflowed
            -- across the log. In game the names landed on top of the message text and both became
            -- unreadable, which is worse than the moving left edge the overlay was protecting.
            --
            -- Asserted on the LOG's resolved left edge, not on the rail's layout props: "the log
            -- moves" is the requirement, and a props assertion would pass on a width nothing applied.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Thalvyn" })
            local before = H.box(p._chat:ActiveLog()).left
            p._chat:SetRailExpanded(true)
            -- The width is TWEENED over animFast now, so the settled state is what to assert; reading
            -- it immediately measures the first frame of the animation.
            H.runAnimations()
            local after = H.box(p._chat:ActiveLog()).left
            expect(after).as("the log is pushed right by the widened rail").gt(before)
        end)

        it("ANIMATES the width rather than snapping it", function()
            -- Snapping the log sideways read as a glitch in game. Asserted as "in between", which is
            -- the only thing that distinguishes a tween from an instant jump -- a settled-state
            -- assertion passes for both.
            local p = enabled()
            local collapsed = p._chat:_railWidth(false)
            local expanded  = p._chat:_railWidth(true)
            expect(expanded).as("there is room to animate across").gt(collapsed)
            p._chat:SetRailExpanded(true)
            H.tick(0.03)
            local mid = p._chat._railScroll:GetWidth()
            expect(mid).as("part way there, not arrived").lt(expanded)
            expect(mid).as("and moving").gt(collapsed - 0.5)
            H.runAnimations()
            expect(p._chat._railScroll:GetWidth()).as("settles exactly on the target").near(expanded, 0.5)
        end)

        it("pre-empts a reversal instead of queueing it", function()
            -- One animation per (target, property), so hovering out mid-expand continues from wherever
            -- the width actually got to. A queued second tween would first finish opening.
            local p = enabled()
            local collapsed = p._chat:_railWidth(false)
            p._chat:SetRailExpanded(true)
            H.tick(0.03)
            p._chat:SetRailExpanded(false)
            H.runAnimations()
            expect(p._chat._railScroll:GetWidth())
                .as("ends collapsed, not wherever the interrupted expand was going").near(collapsed, 0.5)
        end)


        it("returns to the collapsed width when the cursor leaves", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Thalvyn" })
            local collapsed = H.box(p._chat:ActiveLog()).left
            p._chat:SetRailExpanded(true)
            H.runAnimations()
            p._chat:SetRailExpanded(false)
            -- Settled BOTH ways. Without this the test passed vacuously: neither tween had run, so
            -- the log had never moved and "came back" was true of a log that never left.
            H.runAnimations()
            expect(H.box(p._chat:ActiveLog()).left)
                .as("and comes back to where it started").near(collapsed, 0.5)
            expect(p._chat:IsRailExpanded()).eq(false)
        end)
        it("sizes the disc from rail_size, not from a control token", function()
            -- It shipped pinned to `sizeControlSm` (18) with an 11px glyph, which made the channel
            -- unidentifiable at a glance. A widget's own dimension is a plugin setting here, never a
            -- theme token.
            local p = enabled()
            local want = H.SuuUI.Settings:Get("chat", "rail_size")
            expect(want).notNil()
            expect(p._chat._rows["general"]._size).eq(want)
        end)

        it("rebuilds the rail when the size changes, and restates the rail's WIDTH", function()
            -- The size is baked into each Avatar at construction, so it cannot be repainted -- and
            -- rebuilding alone is not enough, because the window sized the rail's cell from the old
            -- diameter and would clip every new disc.
            local p = enabled()
            local before = p._chat:_railWidth(false)
            H.SuuUI.Settings:Set("chat", "rail_size", 40)
            expect(p._chat._rows["general"]._size).as("the row was rebuilt at the new size").eq(40)
            expect(p._chat:_railWidth(false)).as("and the rail grew with it").gt(before)
        end)
    end)

    describe("reopening WITHOUT whispering the person again", function()
        local function closedOne(name)
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "night", sender = name })
            local id = "whisper:" .. H.SuuUI.ChatRouting.ConversationKey(name)
            p._chat:CloseConversation(id)
            return p, id
        end

        it("lists a closed conversation so it can be found again", function()
            -- Messaging someone to summon their panel back is not an acceptable way to read your own
            -- logs, so the closed set has to be discoverable from the store alone.
            local p, id = closedOne("Thalvyn")
            local closed = p._chat:ClosedConversations()
            expect(#closed).eq(1)
            expect(closed[1].id).eq(id)
            expect(closed[1].name).as("the display name, not the lower-cased key").eq("Thalvyn")
        end)

        it("reopens on demand and replays the stored history", function()
            local p, id = closedOne("Thalvyn")
            expect(p._chat:ReopenConversation(id)).eq(true)
            local log = p._chat:LogFor(id)
            expect(log).notNil()
            local found = false
            for i = 1, log:GetNumMessages() do
                if tostring(log:GetMessageInfo(i)):find("night", 1, true) then found = true end
            end
            expect(found).as("history is replayed, not lost").eq(true)
        end)

        it("does NOT duplicate the replayed lines into General", function()
            -- Those records were already shown in General when they arrived, so a routed replay would
            -- print every line there a second time.
            local p, id = closedOne("Thalvyn")
            local general = p._chat:LogFor("general")
            local before = general and general:GetNumMessages() or 0
            p._chat:ReopenConversation(id)
            expect((general and general:GetNumMessages() or 0))
                .as("General is untouched by the replay").eq(before)
        end)

        it("drops out of the closed list once reopened", function()
            local p, id = closedOne("Thalvyn")
            p._chat:ReopenConversation(id)
            expect(#p._chat:ClosedConversations()).eq(0)
        end)

        it("offers a rail row only while something is closed", function()
            local p = enabled()
            expect(p._chat._reopenRow).as("nothing closed, no control").eq(nil)
            H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = "Thalvyn" })
            p._chat:CloseConversation("whisper:" .. H.SuuUI.ChatRouting.ConversationKey("Thalvyn"))
            expect(p._chat._reopenRow).as("appears when there is").notNil()
        end)

        it("HIDES its label when the rail is collapsed, like every other row", function()
            -- It lives outside `_rows`, so each per-row pass has to name it. Missed in the label
            -- toggle, its text stayed on screen with the rail collapsed to discs.
            local p, _ = closedOne("Thalvyn")
            p._chat:SetRailExpanded(false)
            expect(p._chat._reopenRow:IsShowingLabel()).eq(false)
            p._chat:SetRailExpanded(true)
            expect(p._chat._reopenRow:IsShowingLabel()).eq(true)
        end)

        it("leaves room for its own label at the expanded width", function()
            -- Asserted as an INVARIANT rather than as a before/after comparison, deliberately: the
            -- label is "Closed" and "General" is always present at seven characters, so this row can
            -- never BE the widest and a comparison would pass whether or not the width measured it.
            -- What must hold is that the expanded rail is wide enough to draw this label -- which is
            -- exactly what broke when the label read "Closed conversations" and was not measured.
            local p, _ = closedOne("Thalvyn")
            local font = H.SuuUI.Fonts:Path(H.SuuUI.Theme:GetToken("fontFamilyMain"))
            local size = H.SuuUI.Theme:GetFontSize("md")
            local need = H.SuuUI.TextMetrics.Box(p._chat._reopenRow:GetLabel(), font, size)
            expect(p._chat:_railWidth(true) - p._chat:_railWidth(false))
                .as("the expanded rail can draw this row's label").gte(need)
        end)

        it("CAPS the roster, because a player whispers hundreds of people", function()
            -- FlyoutPanel wraps a long roster into COLUMNS, so an uncapped list does not scroll badly
            -- -- it renders every row across a dozen columns spanning the screen.
            local p = enabled()
            for i = 1, 30 do
                local name = "Person" .. i
                H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = name })
                p._chat:CloseConversation("whisper:" .. H.SuuUI.ChatRouting.ConversationKey(name))
            end
            expect(#p._chat:ClosedConversations()).as("all are remembered").eq(30)
            p._chat:_openReopenFlyout(p._chat._reopenRow)
            expect(p._chat._reopenFlyout:GetRowCount()).as("but only eight are shown").eq(8)
        end)

        it("shows the NEWEST conversations, since those are the ones being looked for", function()
            local p = enabled()
            for i = 1, 12 do
                local name = "P" .. i
                H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = name })
                p._chat:CloseConversation("whisper:" .. H.SuuUI.ChatRouting.ConversationKey(name))
            end
            local closed = p._chat:ClosedConversations()
            expect(closed[1].name).as("most recent first").eq("P12")
        end)

        it("labels each row with a COMPACT age", function()
            -- "14 minutes ago" is wider than the name it belongs to and would push the roster past the
            -- panel, which is why Readout.AgeShort exists alongside Age.
            local p, _ = closedOne("Thalvyn")
            p._chat:_openReopenFlyout(p._chat._reopenRow)
            local label = p._chat._reopenFlyout._entries[1].label
            expect(label:find("Thalvyn", 1, true)).notNil()
            -- Asserted against the EXACT string AgeShort would produce, because looser forms do not
            -- discriminate: `find("now")` also matches Age's "just now", and asserting only that "ago"
            -- is absent passes even when no age is shown at all. Both weaker versions let a mutation
            -- swapping AgeShort for Age survive.
            local at = p._chat:ClosedConversations()[1].at
            expect(at).as("the record carries an arrival time").notNil()
            local want = H.SuuUI.Readout.AgeShort(at)
            expect(#want > 0).as("and it renders to something").eq(true)
            -- The age is its OWN entry field now, not part of the label: the concept draws meta as a
            -- separate dim column, and a joined string also drew it at the name's size and colour.
            expect(label).as("the label is the name alone").eq("Thalvyn")
            expect(p._chat._reopenFlyout._entries[1].meta).eq(want)
        end)

        it("finds a conversation buried past the cap by TYPING its name", function()
            -- The point of the search field: with 30 closed conversations the roster draws 8, and the
            -- 20th is unreachable without it. Capping in the plugin instead of the panel would have put
            -- that entry outside what the field can even see.
            local p = enabled()
            for i = 1, 30 do
                local name = "Person" .. i
                H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = name })
                p._chat:CloseConversation("whisper:" .. H.SuuUI.ChatRouting.ConversationKey(name))
            end
            p._chat:_openReopenFlyout(p._chat._reopenRow)
            local fly = p._chat._reopenFlyout
            expect(fly:GetRowCount()).as("drawn without a query").eq(8)
            H.typeText(fly._search, "Person20")
            expect(fly:GetRowCount()).as("the buried one is found").eq(1)
            expect(fly._entries[1].label:find("Person20", 1, true)).notNil()
        end)

        it("reopens the conversation the search found", function()
            local p = enabled()
            for i = 1, 12 do
                local name = "Q" .. i
                H.chat("CHAT_MSG_WHISPER", { text = "hi " .. i, sender = name })
                p._chat:CloseConversation("whisper:" .. H.SuuUI.ChatRouting.ConversationKey(name))
            end
            p._chat:_openReopenFlyout(p._chat._reopenRow)
            local fly = p._chat._reopenFlyout
            H.typeText(fly._search, "Q3")
            expect(fly:GetRowCount()).eq(1)
            fly._entries[1].onClick(fly._entries[1], "LeftButton")
            local id = "whisper:" .. H.SuuUI.ChatRouting.ConversationKey("Q3")
            expect(H.SuuUI.ChatPanels.Find(p._chat._panels, id)).as("it reopened").notNil()
            expect(p._chat._active).eq(id)
        end)

        it("draws a class-coloured disc on every row, as the concept does", function()
            -- Without it the roster read as a bare list of names: the concept gives each row the same
            -- disc the rail carries, which is what makes a row recognisable at a glance.
            local p, _ = closedOne("Thalvyn")
            p._chat:_openReopenFlyout(p._chat._reopenRow)
            expect(#p._chat._reopenAvatars).as("one disc per row").eq(1)
            expect(p._chat._reopenFlyout._entries[1].frame)
                .as("and it is handed to the row").eq(p._chat._reopenAvatars[1]:GetFrame())
        end)

        it("destroys the PREVIOUS discs when the roster is rebuilt", function()
            -- The panel adopts an icon frame and does not own it, so reopening the flyout ten times
            -- would otherwise leave ten sets of avatars parented to the wrapper.
            local p, _ = closedOne("Thalvyn")
            p._chat:_openReopenFlyout(p._chat._reopenRow)
            local first = p._chat._reopenAvatars[1]
            p._chat:_openReopenFlyout(p._chat._reopenRow)
            expect(#p._chat._reopenAvatars).eq(1)
            expect(p._chat._reopenAvatars[1] == first).as("a fresh set replaced it").eq(false)
            -- Asserted through a CONSEQUENCE of the destroy, not through the replacement: a fresh set
            -- is created whether or not the old one was freed, so the first version of this spec let a
            -- mutation deleting the teardown survive. Destroy hides the frame.
            expect(first:GetFrame():IsShown()).as("the previous disc was destroyed").eq(false)
        end)

        it("renders a CONVERSATION panel's own lines without the whisper verb", function()
            -- The wiring, not the mechanism: ChatFormat can drop the verb for a labelled row, but only
            -- if the plugin tells it the panel is one. Without this spec, passing `labelled = false`
            -- from _render survived mutation while the format specs all stayed green.
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = "Tangodin" })
            local id = "whisper:" .. H.SuuUI.ChatRouting.ConversationKey("Tangodin")
            local log = p._chat:LogFor(id)
            expect(log).as("the conversation panel has a log").notNil()
            local line = log:GetMessageInfo(log:GetNumMessages())
            expect(line:find("whispers", 1, true))
                .as("the panel IS the label, so the verb is redundant").eq(nil)
            -- Asserted at the END rather than as a contiguous "Tangodin: hi": the sender is a
            -- hyperlink, so the link's `|h` closer sits between the name and the colon.
            expect(line:sub(-4)).as("one row shape: name, colon, message").eq(": hi")
            expect(line:find("Tangodin", 1, true)).as("and the name is still there").notNil()
        end)

        it("still says WHO in General, where the panel labels nothing", function()
            -- The other half: General carries many groups, so its rows keep the tag that tells them
            -- apart. Dropping the verb everywhere would make a whisper unreadable among say and party.
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "whisper_mode", "general")
            H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = "Tangodin" })
            local log = p._chat:LogFor("general")
            expect(log).as("General has a log").notNil()
            local line = log:GetMessageInfo(log:GetNumMessages())
            expect(line:find("Tangodin", 1, true)).as("the sender is named").notNil()
        end)

        it("applies the history_days SETTING to the store", function()
            -- Without a watcher the slider silently does nothing until the next login, which is the
            -- gap history_depth already had its own watcher for.
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "history_days", 3)
            expect(p._chat._store:GetMaxAge()).as("days become seconds").eq(3 * 86400)
            H.SuuUI.Settings:Set("chat", "history_days", 0)
            expect(p._chat._store:GetMaxAge()).as("0 means keep forever").eq(0)
        end)

        it("drops an EVICTED conversation from the reopen roster", function()
            -- An evicted stream must stop being offered: `ClosedConversations` reads the store, so a
            -- conversation whose history is gone would otherwise still be listed with nothing behind it.
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = "Tangodin" })
            local id = "whisper:" .. H.SuuUI.ChatRouting.ConversationKey("Tangodin")
            p._chat:CloseConversation(id)
            expect(#p._chat:ClosedConversations()).as("listed while its history exists").eq(1)

            -- Age the one record past the window rather than waiting.
            local recs = p._chat._store:Stream(id)
            local now = (H.env.time and H.env.time()) or 1000000
            p._chat._store:Clear(id)
            recs[1].at = now - 40 * 86400
            p._chat._store:_insert(recs[1])
            -- 7 rather than 14: `Set` DROPS a write that does not change the effective value, and 14
            -- is the shipped default -- so setting it to 14 fires no watcher and evicts nothing.
            H.SuuUI.Settings:Set("chat", "history_days", 7)

            expect(p._chat._store:Count(id)).as("evicted").eq(0)
            expect(#p._chat:ClosedConversations()).as("and no longer offered for reopen").eq(0)
        end)

        it("ACTIVATES the panel before replaying, so lines land in a shown log", function()
            -- The root of "reopened lines do not start at the bottom". `_logFor` hides a log it builds
            -- for a panel that is not active, so replaying first added every restored line to a HIDDEN
            -- ScrollingMessageFrame -- which has no rect in the client, so there was no height to lay
            -- the lines out against. Asserting the ORDER is what discriminates: the outcome alone
            -- passes either way here, because the harness gives a hidden frame a rect.
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "one", sender = "Tangodin" })
            H.chat("CHAT_MSG_WHISPER", { text = "two", sender = "Tangodin" })
            local id = "whisper:" .. H.SuuUI.ChatRouting.ConversationKey("Tangodin")
            p._chat:CloseConversation(id)

            local activeAtFirstRender
            local real = p._chat._render
            p._chat._render = function(self, rec, only)
                if activeAtFirstRender == nil then activeAtFirstRender = self._active or false end
                return real(self, rec, only)
            end
            p._chat:ReopenConversation(id)
            p._chat._render = real

            expect(activeAtFirstRender).as("the panel is active before the first line is replayed").eq(id)
            expect(p._chat:LogFor(id):IsShown()).as("so the log is shown while it fills").eq(true)
        end)

        it("leaves a REOPENED conversation scrolled to the bottom", function()
            -- Pins the outcome the player sees. NOT discriminable in the harness on its own: its
            -- ScrollingMessageFrame:Clear() zeroes the scroll offset, so a pooled log cannot come back
            -- carrying a stale one here the way it does in game. Kept because it is the invariant, and
            -- it fails if a future change replays without settling.
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "one", sender = "Tangodin" })
            local id = "whisper:" .. H.SuuUI.ChatRouting.ConversationKey("Tangodin")
            p._chat:CloseConversation(id)
            p._chat:ReopenConversation(id)
            expect(p._chat:LogFor(id):AtBottom()).as("newest line is what you land on").eq(true)
        end)

        it("settles the log at the bottom when a LIVE whisper reopens it", function()
            -- The automatic path is deliberately NOT activated -- a whisper must not yank the player
            -- away from what they are reading -- so its log stays hidden and only the offset can be
            -- settled. That offset is what survives to the moment the player clicks the row.
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "one", sender = "Tangodin" })
            local id = "whisper:" .. H.SuuUI.ChatRouting.ConversationKey("Tangodin")
            p._chat:CloseConversation(id)
            H.chat("CHAT_MSG_WHISPER", { text = "back", sender = "Tangodin" })
            local log = p._chat:LogFor(id)
            expect(log).as("the live whisper reopened it").notNil()
            expect(log:AtBottom()).as("and it is settled at the bottom").eq(true)
            expect(p._chat:GetActivePanel() == id).as("without stealing the active panel").eq(false)
        end)

        it("can be opened AGAIN after a reopen", function()
            -- Shipped broken: `_buildRail` destroys and recreates the reopen row whenever the closed
            -- list changes, and a reopen always changes it -- so the panel was left anchored to the
            -- destroyed first row. It opened in the wrong place and closed instantly, because a frame
            -- with no rect can never read as "inside" for the hover watcher.
            local p = enabled()
            for _, name in ipairs({ "Alpha", "Beta" }) do
                H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = name })
                p._chat:CloseConversation("whisper:" .. H.SuuUI.ChatRouting.ConversationKey(name))
            end
            p._chat:_openReopenFlyout(p._chat._reopenRow)
            local fly = p._chat._reopenFlyout
            fly._entries[1].onClick(fly._entries[1], "LeftButton")

            -- The row that exists NOW, after the rebuild.
            local row = p._chat._reopenRow
            expect(row).as("still something closed, so the row is back").notNil()
            p._chat:_openReopenFlyout(row)
            expect(fly._anchorTo).as("anchored to the CURRENT row").eq(row:GetFrame())
            expect(fly:IsOpen()).as("and it stays open").eq(true)
            H.expectInside(fly, H.UIParent)
        end)

        it("drops the DESTROYED row from the hover guards", function()
            -- AddGuard only appends, so without a replace the dead frame stays in the list and the set
            -- grows on every rebuild -- and a dead guard is exactly what closed the panel instantly.
            local p = enabled()
            for _, name in ipairs({ "Alpha", "Beta" }) do
                H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = name })
                p._chat:CloseConversation("whisper:" .. H.SuuUI.ChatRouting.ConversationKey(name))
            end
            p._chat:_openReopenFlyout(p._chat._reopenRow)
            local fly = p._chat._reopenFlyout
            local dead = p._chat._reopenRow:GetFrame()
            fly._entries[1].onClick(fly._entries[1], "LeftButton")
            p._chat:_openReopenFlyout(p._chat._reopenRow)
            local guards = fly._hoverAway._guards
            for i = 1, #guards do
                expect(guards[i] == dead).as("the destroyed row is not a guard").eq(false)
            end
        end)

        it("stays CLOSED across a reload", function()
            -- Shipped reopening itself on every reload: closing removes the PANEL while deliberately
            -- keeping the STREAM, and the login replay walks every stored record, so it recreated a
            -- panel for every conversation and undid the close.
            local p, id = closedOne("Thalvyn")
            H.fireEvent("PLAYER_LOGOUT")
            local blob = H.env.SuuUIChatHistory
            expect(blob.closed and blob.closed[id]).as("the close is persisted").truthy()

            -- Relog with that blob staged, exactly as the client restores it.
            H.setup({ savedVars = { SuuUIChatHistory = blob } })
            H.SuuUI.Settings:Set("chat", "enabled", true)
            local p2 = H.SuuUI.Plugins:Get("chat")
            expect(H.SuuUI.ChatPanels.Find(p2._chat._panels, id))
                .as("no panel after the reload").eq(nil)
            expect(#p2._chat:ClosedConversations())
                .as("but it is still reachable from the roster").eq(1)
        end)

        it("REOPENS on a live whisper after a reload, not on the replay", function()
            -- The gate is the replay specifically: a new whisper from that person is exactly the event
            -- that should bring the panel back.
            local p, id = closedOne("Thalvyn")
            H.fireEvent("PLAYER_LOGOUT")
            H.setup({ savedVars = { SuuUIChatHistory = H.env.SuuUIChatHistory } })
            H.SuuUI.Settings:Set("chat", "enabled", true)
            local p2 = H.SuuUI.Plugins:Get("chat")
            expect(H.SuuUI.ChatPanels.Find(p2._chat._panels, id)).eq(nil)
            H.chat("CHAT_MSG_WHISPER", { text = "still there?", sender = "Thalvyn" })
            expect(H.SuuUI.ChatPanels.Find(p2._chat._panels, id))
                .as("a live whisper reopens it").notNil()
        end)

        it("does not re-close a conversation the whisper just reopened", function()
            -- If the flag were not cleared on the live path the panel would reopen and the store would
            -- still call it closed, so the NEXT reload would close it again behind the player.
            local p, id = closedOne("Thalvyn")
            H.chat("CHAT_MSG_WHISPER", { text = "back", sender = "Thalvyn" })
            H.fireEvent("PLAYER_LOGOUT")
            local blob = H.env.SuuUIChatHistory
            expect(blob.closed and blob.closed[id]).as("no longer recorded as closed").falsy()
        end)

        it("forgets a closed id that has no stream left", function()
            -- Otherwise the set grows forever as old conversations are trimmed out from under it.
            -- Asserted directly rather than by trimming: SetDepth(0) does not empty a stream, so a
            -- depth-driven version of this test passed for the wrong reason.
            local p, id = closedOne("Thalvyn")
            p._chat._closed["whisper:nobody-"] = true
            H.fireEvent("PLAYER_LOGOUT")
            local closed = H.env.SuuUIChatHistory.closed or {}
            expect(closed[id]).as("a live stream keeps its flag").truthy()
            expect(closed["whisper:nobody-"]).as("a streamless id is dropped").falsy()
        end)

        it("survives a logout, because the streams do", function()
            -- A conversation closed in a previous session is listed exactly like one closed a minute
            -- ago: the stream keys ARE the panel ids and they persist in SavedVariables.
            local p, id = closedOne("Thalvyn")
            H.fireEvent("PLAYER_LOGOUT")
            local blob = H.env.SuuUIChatHistory
            expect(blob).notNil()
            expect(blob.streams[id]).as("the closed conversation is still stored").notNil()
        end)

        it("never shows one person's whisper in ANOTHER person's panel", function()
            -- Measured before the fix: closing Alpha's conversation released its log to the pool with
            -- every line still in the buffer, and Beta's new panel acquired it and rendered Alpha's
            -- private message. The pool's reset is generic and knows nothing about a message buffer.
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "SECRET-A", sender = "Alpha" })
            p._chat:CloseConversation("whisper:" .. H.SuuUI.ChatRouting.ConversationKey("Alpha"))
            H.chat("CHAT_MSG_WHISPER", { text = "hello-b", sender = "Beta" })
            local log = p._chat:LogFor("whisper:" .. H.SuuUI.ChatRouting.ConversationKey("Beta"))
            expect(log).notNil()
            local leaked = false
            for i = 1, log:GetNumMessages() do
                if tostring(log:GetMessageInfo(i)):find("SECRET-A", 1, true) then leaked = true end
            end
            expect(leaked).as("no cross-conversation leak").eq(false)
        end)
    end)

    describe("closing and reopening a conversation", function()
        local function whispered()
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Thalvyn" })
            -- DERIVED, never hardcoded: the key is lower-cased and realm-suffixed
            -- ("thalvyn-"), so a literal "whisper:Thalvyn" addresses a panel that does not exist.
            return p, "whisper:" .. H.SuuUI.ChatRouting.ConversationKey("Thalvyn")
        end

        it("closes a conversation panel on right-click", function()
            local p, id = whispered()
            expect(H.SuuUI.ChatPanels.Find(p._chat._panels, id)).as("panel opened").notNil()
            expect(H.click(p._chat._rows[id], "RightButton")).eq(true)
            expect(H.SuuUI.ChatPanels.Find(p._chat._panels, id)).as("and closed").eq(nil)
        end)

        it("LEFT-click still selects rather than closing", function()
            local p, id = whispered()
            expect(H.click(p._chat._rows[id], "LeftButton")).eq(true)
            expect(H.SuuUI.ChatPanels.Find(p._chat._panels, id)).as("still open").notNil()
            expect(p._chat._active).eq(id)
        end)

        it("REFUSES to close General, which is the window's fixed spine", function()
            -- A gesture that could remove General would leave the player with no way back short of a
            -- reload, so the refusal lives in the model rather than in the row's handler.
            local p = enabled()
            expect(H.SuuUI.ChatPanels.Remove(p._chat._panels, "general")).eq(false)
            expect(H.SuuUI.ChatPanels.Find(p._chat._panels, "general")).notNil()
        end)

        it("falls back to General when the CLOSED panel was the active one", function()
            local p, id = whispered()
            p._chat:SetActivePanel(id)
            p._chat:CloseConversation(id)
            expect(p._chat._active).as("not left pointing at a panel that no longer exists").eq("general")
        end)

        it("RELEASES the log to the pool instead of destroying it", function()
            -- _logFor acquires from the `chat.log` pool, so destroying the handle would hand the pool a
            -- dead one to reissue on the next conversation.
            local p, id = whispered()
            p._chat:CloseConversation(id)
            expect(p._chat._logs[id]).as("the log is dropped").eq(nil)
            H.chat("CHAT_MSG_WHISPER", { text = "back", sender = "Thalvyn" })
            local log = p._chat:LogFor(id)
            expect(log).as("a reissued log is usable").notNil()
            expect(log:GetNumMessages()).gt(0)
        end)

        it("reopens with the conversation's HISTORY, because the store is untouched", function()
            -- Closing a window is not a request to delete what was said.
            local p, id = whispered()
            p._chat:CloseConversation(id)
            H.chat("CHAT_MSG_WHISPER", { text = "still there?", sender = "Thalvyn" })
            local log = p._chat:LogFor(id)
            expect(log).notNil()
            local found = false
            for i = 1, log:GetNumMessages() do
                if tostring(log:GetMessageInfo(i)):find("hey", 1, true) then found = true end
            end
            expect(found).as("the earlier whisper is replayed, not lost").eq(true)
        end)

        it("clears unread state so a reopened panel shows no stale badge", function()
            local p, id = whispered()
            p._chat:SetActivePanel("general")
            H.chat("CHAT_MSG_WHISPER", { text = "two", sender = "Thalvyn" })
            expect((p._chat._unread or {})[id]).as("unread accrued").gt(0)
            p._chat:CloseConversation(id)
            expect((p._chat._unread or {})[id]).eq(nil)
        end)
    end)

    describe("class-coloured sender names", function()
        local GUID = "Player-1-ABCDEF"

        local function say(class)
            H.setup()
            if class then H.setPlayerGUID(GUID, { class = class, localizedClass = "Localized" }) end
            H.SuuUI.Settings:Set("chat", "enabled", true)
            local p = H.SuuUI.Plugins:Get("chat")
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Thalvyn", guid = GUID })
            local log = p._chat:ActiveLog()
            return log:GetMessageInfo(log:GetNumMessages()), p
        end

        it("tints the sender with the class colour", function()
            local line = say("MAGE")
            local want = H.SuuUI.Game:ClassColorCode("MAGE")
            expect(want).as("the class resolves to an escape").notNil()
            expect(line:find(want, 1, true)).as("the name carries the class colour").notNil()
        end)

        it("puts the colour INSIDE the player link, around the name only", function()
            -- Outside the link the escape would also tint the separator between timestamp and name.
            local line = say("MAGE")
            local code = H.SuuUI.Game:ClassColorCode("MAGE")
            expect(line:find("|Hplayer:.-|h" .. code:gsub("|", "%%|"))).notNil()
        end)

        it("reads englishClass, NOT the localized first return", function()
            -- GetPlayerInfoByGUID answers localizedClass first. Reading that gives "Localized", which
            -- resolves to no colour -- and fails silently, which is the whole reason this is pinned.
            local line = say("MAGE")
            expect(line:find("Localized", 1, true)).as("the localized name is not used as a key").eq(nil)
        end)

        it("leaves a name uncoloured when the client knows nothing about the GUID", function()
            -- A creature has no class and the client answers nothing, which is correct: the name takes
            -- the line's own colour rather than an invented one.
            local line = say(nil)
            local at = line:find("Thalvyn", 1, true)
            expect(at).notNil()
            -- Narrowed to the NAME. A line-wide `|cff` search used to work and now finds the
            -- TIMESTAMP's own muted escape, which is a legitimate one -- so the assertion asks the
            -- question it always meant: is there an escape immediately before the name.
            expect(line:sub(1, at - 1):find("|cff[0-9a-fA-F]+$"))
                .as("no colour escape is invented for the name").eq(nil)
        end)

        it("caches the lookup on the record, including its absence", function()
            local _, p = say(nil)
            local recs = p._chat._store:Records()
            expect(recs[#recs]._classResolved).as("absence is memoised too").eq(true)
        end)
    end)

    describe("a bad history record must not cost the window", function()
        -- The real failure, reproduced. A record whose `message` was a NUMBER -- from a SavedVariable
        -- written by an older version -- raised inside the renderer, unwound out of `_replayHistory`
        -- and out of `buildWindow`, and left the plugin with NO window: Blizzard's chat came back and
        -- every setting silently did nothing. One line of stored history cost the whole feature.
        local function withHistory(message)
            H.setup({ savedVars = { SuuUIChatHistory = {
                depth = 50, seq = 2, order = { "general" },
                streams = { general = { {
                    kind = "SAY", message = message, sender = "Thalvyn",
                    senderFull = "Thalvyn", seq = 1, stream = "general",
                } } },
            } } })
            H.SuuUI.Settings:Set("chat", "enabled", true)
            return H.SuuUI.Plugins:Get("chat")
        end

        it("still builds the window with a NUMBER in a stored message", function()
            local p = withHistory(42)
            expect(p._chat).as("the window survives the bad record").notNil()
            expect(H.SuuUI._ChatBuildError).as("the build did not fail").eq(nil)
        end)

        it("still builds the window with a TABLE in a stored message", function()
            -- A number is what shipped; a table is the same class of fault and must not raise either.
            local p = withHistory({ nonsense = true })
            expect(p._chat).notNil()
        end)

        it("normalises a numeric message on restore rather than trusting it", function()
            -- ChatStore.Restore's own comment promises a malformed blob yields an empty store rather
            -- than raising, but it only ever validated the blob's SHAPE, never a record's fields.
            local p = withHistory(42)
            local recs = p._chat._store:Records()
            expect(#recs).gt(0)
            expect(type(recs[1].message)).as("coerced, not dropped").eq("string")
            expect(recs[1].message).eq("42")
        end)
    end)

    describe("a tall adopted edit box must not drive our layout", function()
        -- Blizzard owns that box's height. A ratchet here once let it become a FLOOR for our input
        -- row, which ate the window, clamped the log to its 1-unit floor, and made the Height slider
        -- look inert. The suite stayed green through all of it because the harness's stub box is
        -- small -- so these specs stage the tall box the client actually has.
        local function tallBox(h)
            H.setup()
            local eb = H.env.ChatFrame1EditBox
            if eb then eb:SetHeight(h) end
            H.SuuUI.Settings:Set("chat", "enabled", true)
            return H.SuuUI.Plugins:Get("chat")._chat
        end

        it("keeps the input row at its token height", function()
            local c = tallBox(160)
            local want = H.SuuUI.Theme:GetControlHeight("sizeControlMd")
            expect(H.box(c._inputRow).height)
                .as("the row states its own height, not the box's").eq(want)
        end)

        it("leaves the log filling the window, not clamped to its floor", function()
            local c = tallBox(160)
            local win = H.box(c._win)
            local top = H.box(c._top)
            expect(top.height).as("the log row is not collapsed").gt(1)
            -- The whole window is accounted for: log row + input row + one gap.
            expect(top.height + H.box(c._inputRow).height + H.token("spaceXs")).eq(win.height)
        end)

        it("still honours the height setting with a tall box present", function()
            -- The symptom was "the height slider does nothing", so assert the slider's EFFECT rather
            -- than the stored value.
            local c = tallBox(160)
            local before = H.box(c._top).height
            H.SuuUI.Settings:Set("chat", "height", 400)
            expect(H.box(c._top).height).as("raising the window raises the log").gt(before)
            expect(H.box(c._win).height).eq(400)
        end)
    end)

    describe("clicking a link, and the fade reveal", function()
        it("does NOT forward the click to Blizzard's chat frame, which suppression has parked", function()
            -- Forwarding was tried, shipped, and reverted the same session. It looks like good interop
            -- -- addons that add link types hook `OnHyperlinkClick` on `ChatFrame1..10` by name -- but
            -- that frame is PARKED under a hidden holder by suppression, and a hidden frame has no
            -- rect, so the hover half put the tooltip nowhere and cost every item mouseover in the log.
            -- It is also the wrong dependency shape: this addon stands alone.
            --
            -- Asserted rather than merely commented so the next reader cannot re-add it without a
            -- failing test explaining why.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "look", sender = "Thalvyn" })
            local log = p._chat:ActiveLog()
            local forwarded = false
            H.env.ChatFrame1:SetScript("OnHyperlinkClick", function() forwarded = true end)
            H.resetItemRef()
            expect(H.clickHyperlink(log._log, "item:19019", "[T]", "LeftButton")).eq(true)
            expect(forwarded).as("Blizzard's parked frame is not handed the gesture").eq(false)
            expect(H.getItemRef()).as("the client's own dispatcher is used").notNil()
            expect(H.getItemRef().link).eq("item:19019")
        end)

        it("hands a link click to the client's own SetItemRef", function()
            -- The component emitted HYPERLINK_CLICK from the start and NOTHING consumed it, so links
            -- rendered perfectly and did nothing. `SetItemRef` is what makes an item link open its
            -- tooltip frame and a player link open the whisper menu.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "look", sender = "Thalvyn" })
            local log = p._chat:ActiveLog()
            H.resetItemRef()
            expect(H.clickHyperlink(log._log, "item:19019", "[Thunderfury]", "LeftButton")).eq(true)
            local ref = H.getItemRef()
            expect(ref).as("the click reached the client, not just our signal").notNil()
            expect(ref.link).eq("item:19019")
            expect(ref.text).eq("[Thunderfury]")
            expect(ref.button).eq("LeftButton")
        end)

        it("passes the button through, so a right click can open a player menu", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "look", sender = "Thalvyn" })
            local log = p._chat:ActiveLog()
            H.resetItemRef()
            H.clickHyperlink(log._log, "player:Thalvyn", "[Thalvyn]", "RightButton")
            expect(H.getItemRef().button)
                .as("a swallowed button turns a context menu into a whisper").eq("RightButton")
        end)

        it("answers a url: link ITSELF rather than handing it to the client", function()
            -- `url:` is our own link type and the client knows nothing about it, so passing it to
            -- SetItemRef would silently do nothing -- the exact failure shape of a dead link click.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "see https://wow.gg", sender = "Thalvyn" })
            local log = p._chat:ActiveLog()
            H.resetItemRef()
            expect(H.clickHyperlink(log._log, "url:https://wow.gg", "[https://wow.gg]", "LeftButton"))
                .eq(true)
            expect(H.getItemRef())
                .as("never forwarded: the client has no url: handler").eq(nil)
        end)

        it("linkifies a URL in a message that reaches the log", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "see https://wow.gg for it", sender = "Thalvyn" })
            local log = p._chat:ActiveLog()
            local linked = false
            for i = 1, log:GetNumMessages() do
                if tostring(log:GetMessageInfo(i)):find("|Hurl:https://wow.gg|h", 1, true) then
                    linked = true
                end
            end
            expect(linked).as("a URL in chat is clickable, end to end").eq(true)
        end)

        it("reveals a faded buffer on hover AND restarts the fade clocks", function()
            -- Alpha alone is not enough: every restored line's own fade time expired long ago, so a
            -- reveal that forgets ResetAllFadeTimes shows the text for one frame and loses it again.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "old", sender = "Thalvyn" })
            local log = p._chat:ActiveLog()
            log:SetFaded(true)
            expect(log._log:GetAlpha()).as("fully faded means invisible, not dim").eq(0)
            local before = log._log:GetFadeResetCount()
            H.hover(log._log)
            expect(log:IsFaded()).as("hovering reveals it").eq(false)
            expect(log._log:GetAlpha()).eq(1)
            expect(log._log:GetFadeResetCount())
                .as("and restarts the clocks, or it vanishes again next frame").gt(before)
        end)

        it("does NOT re-fade when the cursor leaves", function()
            -- Per-line fading expires the lines again on its own clock. Re-hiding them the instant
            -- the cursor left would lose the text before you finished reading it.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "old", sender = "Thalvyn" })
            local log = p._chat:ActiveLog()
            log:SetFaded(true)
            H.hover(log._log)
            H.hover(p._chat._wrapper)
            expect(log:IsFaded()).as("a deliberate hover must survive the cursor moving on").eq(false)
        end)
    end)

    describe("numbered channel traffic", function()
        it("registers CHAT_MSG_CHANNEL at all", function()
            -- THE bug this block exists for, and it was a message-LOSS bug rather than a misrouting
            -- one: the event list is built from the panels' groups, so a group no panel claims is
            -- never subscribed -- and with Blizzard's chat suppressed the player never sees `/1` or
            -- `/2 Trade` again. Asserted on the event list rather than only on where a line lands,
            -- because an unregistered event cannot even be staged into the failure.
            local p = enabled()
            local events = H.SuuUI.ChatPanels.Events(p._chat._panels, H.env.ChatTypeGroup)
            local has = false
            for _, e in ipairs(events) do if e == "CHAT_MSG_CHANNEL" then has = true end end
            expect(has).as("a group no panel claims is a group the player loses").eq(true)
        end)

        it("shows a channel line in General", function()
            local p = enabled()
            H.chat("CHAT_MSG_CHANNEL", { text = "wts stuff", sender = "Thalvyn",
                                         channelIndex = 2, channel = "Trade" })
            local log = p._chat:LogFor("general")
            expect(log).as("General took it").notNil()
            local shown = false
            for i = 1, log:GetNumMessages() do
                if tostring(log:GetMessageInfo(i)):find("wts stuff", 1, true) then shown = true end
            end
            expect(shown).as("a channel is people talking, so it is not Log traffic").eq(true)
        end)

        it("tags the line with the channel NUMBER, which is what /2 means", function()
            local p = enabled()
            H.chat("CHAT_MSG_CHANNEL", { text = "wts stuff", sender = "Thalvyn",
                                         channelIndex = 2, channel = "Trade" })
            local log = p._chat:LogFor("general")
            local tagged = false
            for i = 1, log:GetNumMessages() do
                if tostring(log:GetMessageInfo(i)):find("2", 1, true) then tagged = true end
            end
            expect(tagged).as("the tag column carries the channel index").eq(true)
        end)

        xit("gives a joined channel its OWN panel", function()
            -- RESOLVED by Domenik 2026-08-27: whispers are DELIBERATELY the exception -- they may
            -- open their own window, and `whisper_mode` is the config for whether they do. Channels
            -- are not: they stay in General unless the player configures a panel for one. So the two
            -- mechanisms are not inconsistent after all, and this stays skipped rather than becoming
            -- a feature. Kept as the record of the decision.
        end)
    end)

    describe("whisper_mode governs whether a whisper opens its own panel", function()
        -- Domenik's ruling: "whispers are extra, there can be a config that new whispers open or
        -- dont open a new whisper window". That config already existed as the three-way
        -- `whisper_mode`; it simply was not consulted when the panel was created.

        it("opens a panel on Both, which is the default", function()
            local p = enabled()
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sylvaine-TestRealm" })
            expect(p._chat._rows["whisper:sylvaine-testrealm"]).notNil()
        end)

        it("opens a panel on Their Own Panel Only", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "whisper_mode", "panel")
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sylvaine-TestRealm" })
            expect(p._chat._rows["whisper:sylvaine-testrealm"]).notNil()
        end)

        it("opens NO panel on General Only", function()
            -- The bug this pins: a panel was built regardless of the mode, so General Only produced
            -- a rail row for a conversation whose every message went to General -- an empty panel
            -- advertising itself.
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "whisper_mode", "general")
            H.chat("CHAT_MSG_WHISPER", { text = "hey", sender = "Sylvaine-TestRealm" })
            expect(p._chat._rows["whisper:sylvaine-testrealm"])
                .as("no rail row for a panel the player asked not to have").eq(nil)
        end)

        it("still shows the whisper in General when no panel is opened", function()
            -- The message must never be lost as a side effect of not wanting a panel for it.
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "whisper_mode", "general")
            H.chat("CHAT_MSG_WHISPER", { text = "secret", sender = "Sylvaine-TestRealm" })
            local log = p._chat:LogFor("general")
            local shown = false
            for i = 1, log:GetNumMessages() do
                if tostring(log:GetMessageInfo(i)):find("secret", 1, true) then shown = true end
            end
            expect(shown).as("General Only means General, not nowhere").eq(true)
        end)
    end)

    describe("copying ONE line", function()
        it("puts a clickable copy icon at the start of every line", function()
            -- A ScrollingMessageFrame renders text and offers no per-line frame, so the affordance
            -- has to BE part of the string: an inline texture wrapped in a hyperlink.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Thalvyn" })
            local log = p._chat:ActiveLog()
            local line = log:GetMessageInfo(1)
            expect(line:find("|Hsuucopy:", 1, true))
                .as("the icon leads the line, before the timestamp").eq(1)
            expect(line:find("|T", 1, true)).as("and it is a texture, not a letter").notNil()
        end)

        it("copies THAT line, stripped of markup and of the icon itself", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "first",  sender = "Thalvyn" })
            H.chat("CHAT_MSG_SAY", { text = "second", sender = "Aldara" })
            local log = p._chat:ActiveLog()
            -- Take the seq off the SECOND line's own link, the way a click does.
            local seq = log:GetMessageInfo(2):match("|Hsuucopy:(%d+)|h")
            expect(seq).notNil()
            local m = p._chat:CopyLine(tonumber(seq))
            expect(m).as("a dialog opened").notNil()
            local text = m._input:GetValue()
            expect(text:find("second", 1, true)).as("the line that was clicked").notNil()
            expect(text:find("first", 1, true)).as("and only that line").eq(nil)
            expect(text:find("|T", 1, true)).as("the copy icon is not part of the text").eq(nil)
            expect(text:find("|H", 1, true)).as("nor any link wrapper").eq(nil)
            expect(text:find("|c", 1, true)).as("nor any colour escape").eq(nil)
            expect(text:sub(1, 1) == " ")
                .as("no leading space where the icon used to be").eq(false)
        end)

        it("refuses a sequence that is not on screen", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Thalvyn" })
            expect(p._chat:CopyLine(9999)).eq(false)
            expect(p._chat:CopyLine(nil)).eq(false)
        end)

        it("answers the copy link ITSELF rather than handing it to the client", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Thalvyn" })
            local log = p._chat:ActiveLog()
            local seq = log:GetMessageInfo(1):match("|Hsuucopy:(%d+)|h")
            H.resetItemRef()
            expect(H.clickHyperlink(log._log, "suucopy:" .. seq, "icon", "LeftButton")).eq(true)
            expect(H.getItemRef())
                .as("the client has no suucopy handler; forwarding would be a no-op").eq(nil)
        end)
    end)

    describe("the window fills its own height", function()
        it("puts the input row flush against the bottom edge", function()
            -- The defect: the rail+log row came out at its CONTENT height (88 units inside a 180-unit
            -- window), so the input row floated 66 units above the bottom and the edit-mode overlay
            -- looked far larger than the chat. Asserted as edges meeting, because that is the thing
            -- the player sees -- a height assertion alone would pass with the row in the wrong place.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Thalvyn" })
            local w = H.box(p._chat._wrapper)
            local i = H.box(p._chat._inputRow)
            expect(i.top + i.height)
                .as("the input row's bottom IS the window's bottom").near(w.top + w.height, 1)
        end)

        it("gives the rail and log row everything the input row does not use", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hi", sender = "Thalvyn" })
            local w = H.box(p._chat._wrapper)
            local t = H.box(p._chat._top)
            local i = H.box(p._chat._inputRow)
            local gap = H.token("spaceXs")
            expect(t.height).as("no dead space between them").near(w.height - i.height - gap, 1)
            expect(t.top).as("and the row starts at the top").near(w.top, 1)
        end)

        it("restates the row's height when the window is resized", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "height", 320)
            local w = H.box(p._chat._wrapper)
            local i = H.box(p._chat._inputRow)
            expect(w.height).eq(320)
            expect(i.top + i.height)
                .as("a taller window still ends where the input row ends").near(w.top + w.height, 1)
        end)

        xit("uses height = fill for the rail+log row instead of stating the number", function()
            -- OPEN: `height = "fill"` on that row produced its content height (88 of 180) and a
            -- forced re-layout did not change it, so it is not staleness. The cause is unproven --
            -- instrumenting FlowLayout was invisible because `print` inside the addon sandbox is
            -- captured by the harness's chat mirror rather than reaching stdout -- so rather than
            -- guess at the strategy, the plugin states the height it can compute. Worth returning to
            -- with `io.write`, because if vertical fill is wrong for a container child it is wrong
            -- everywhere, not only here.
        end)
    end)

    describe("the rail scrolls when there are many conversations", function()
        it("stays inside the window however many rows there are", function()
            -- The defect: the rail is a vertical flow that hugs its content, so a handful of open
            -- whispers ran it past the window's bottom edge, over the input row and off the frame --
            -- taking the rows out of reach entirely.
            local p = enabled()
            for _, n in ipairs({ "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }) do
                H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = n .. "-TestRealm" })
            end
            local w  = H.box(p._chat._wrapper)
            local sc = H.box(p._chat._railScroll)
            expect(sc.top + sc.height)
                .as("the rail's viewport ends inside the window").lte(w.top + w.height + 0.5)
        end)

        it("overflows INSIDE the viewport, which is what makes it scrollable", function()
            -- The rows must still exist at full height -- clipping them away would lose them rather
            -- than let the player reach them. The content being taller than the viewport IS the
            -- scrollable state.
            local p = enabled()
            for _, n in ipairs({ "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }) do
                H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = n .. "-TestRealm" })
            end
            expect(H.box(p._chat._rail).height)
                .as("the rows are all there, taller than the viewport")
                .gt(H.box(p._chat._railScroll).height)
            -- And the scroll frame KNOWS: comparing the two heights alone passed with the rail's
            -- SIZE_CHANGED connection deleted, because the content is taller either way. What the
            -- connection causes is the viewport learning its range, and a bar is the observable.
            expect(p._chat._railScroll:_needsBar())
                .as("the scroll frame was told its content grew").truthy()
        end)

        it("takes the row's full height, not its own content height", function()
            -- `SetChildProps` REPLACES props, so a call passing only `width` dropped the stretch and
            -- the viewport came out at content height. Every site goes through _setRailCell now.
            local p = enabled()
            expect(p._chat._railScroll:GetHeight())
                .near(p._chat._top:GetFrame():GetHeight(), 1)
        end)

        it("keeps the same width whether or not the bar is showing", function()
            -- The scrollbar is reserved always: a bar appearing with the first whisper would shift the
            -- log sideways at the exact moment a whisper arrived.
            local p = enabled()
            local before = H.box(p._chat:LogFor("general")).left
            for _, n in ipairs({ "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }) do
                H.chat("CHAT_MSG_WHISPER", { text = "hi", sender = n .. "-TestRealm" })
            end
            expect(H.box(p._chat:LogFor("general")).left)
                .as("the log did not move when the rail overflowed").near(before, 0.5)
        end)
    end)

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
            -- Staged ON explicitly: `fade_channels` now DEFAULTS TO FALSE, so relying on the default
            -- here would assert the opposite of what this test is named for.
            H.SuuUI.Settings:Set("chat", "fade_channels", true)
            expect(p._chat:ActiveLog():IsFading())
                .as("channels fade, conversations persist").eq(true)
        end)

        it("stops fading when the setting is off", function()
            local p = enabled()
            -- Turned ON and then OFF, so the TRANSITION is what is asserted. With the default now
            -- false, setting it false alone would pass without the code doing anything at all.
            H.SuuUI.Settings:Set("chat", "fade_channels", true)
            expect(p._chat:ActiveLog():IsFading()).as("on first, or the next line proves nothing").eq(true)
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

        it("draws NO channel tag out of the box", function()
            -- The default, asserted with nothing written: the concept's row has no text tag at all, and
            -- with Blizzard's line colours kept the channel is already on the line.
            local p = enabled()
            H.chat("CHAT_MSG_GUILD", { text = "hi", sender = "Thalvyn" })
            local text = p._chat:LogFor("guild"):GetMessageInfo(1)
            expect(text:find("GLD", 1, true)).as("no tag column by default").eq(nil)
        end)

        it("keeps ONE row shape with the tag OFF, which is the default", function()
            -- The concept's rule is "time, name, colon, message -- in General and in a whisper alike",
            -- and it is not conditional. This used to ride on the tag being drawn, so switching the tag
            -- column off brought `says:` and `whispers:` back everywhere.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "test", sender = "Thalvyn" })
            local text = p._chat:ActiveLog():GetMessageInfo(1)
            expect(text:find("says", 1, true)).as("no verb, tag or no tag").eq(nil)
            expect(text:sub(-6)).as("name, colon, message").eq(": test")
        end)

        it("does not print the channel verb beside the tag", function()
            local p = enabled()
            -- Asked for explicitly: the tag now defaults OFF, because the concept draws none and the
            -- line's own colour already carries the channel.
            H.SuuUI.Settings:Set("chat", "show_tags", true)
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

        it("MOVES the log right when it expands, and leaves the input row alone", function()
            -- REVERSED TWICE, and the second shape is Domenik's: the overlay put channel names on top
            -- of the message text, and reflowing the whole column then slid the resting chip sideways
            -- on every hover. The fix is STRUCTURAL rather than a choice between those two -- the input
            -- row is a full-width sibling of the [rail][log] row instead of a child of it, so the rail
            -- can push the log without the chip being beside it to push.
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hello there", sender = "Grimtusk" })
            local chipBefore = H.box(p._chat._chip).left
            local logBefore  = H.box(p._chat:LogFor("general")).left

            -- The HOVER wiring, asserted without advancing the clock: HoverAway polls the cursor's
            -- position rather than tracking enter/leave, so any tick long enough to settle the tween
            -- also decides the cursor has left and collapses the rail again.
            H.hover(p._chat._rows["guild"])
            expect(p._chat:IsRailExpanded()).as("hovering a row expands the rail").truthy()

            -- The GEOMETRY, driven directly so the tween can finish without the poll undoing it.
            p._chat:SetRailExpanded(false)
            H.runAnimations()
            p._chat:SetRailExpanded(true)
            H.runAnimations()
            expect(H.box(p._chat:LogFor("general")).left)
                .as("the log is pushed clear of the names").gt(logBefore)
            expect(H.box(p._chat._chip).left)
                .as("and the chip does NOT move, being outside the rail's row").near(chipBefore, 0.5)
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
            -- Derived from the SETTING, not from `sizeControlSm`. The disc size became a plugin
            -- setting (`rail_size`) because it is one widget's own dimension rather than design
            -- language, so a token-derived expectation here now asserts the wrong number and would
            -- go on asserting it if the setting moved again.
            --
            -- The SCROLLBAR is part of the width too, and reserved whether or not the rows currently
            -- overflow -- otherwise the log would shift sideways the moment a whisper arrived.
            expect(p._chat:_railWidth(false))
                .as("2px marker + gap + scrollbar + disc")
                .near(H.SuuUI.Pixel.Line(2) + H.token("spaceXs") + H.token("sizeScrollbar")
                      + H.SuuUI.Settings:Get("chat", "rail_size"), 0.5)
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
            -- `fade_channels` defaults to FALSE now, so the per-panel RULE under test -- channels
            -- fade, the Log does not -- only exists once fading is switched on.
            H.SuuUI.Settings:Set("chat", "fade_channels", true)
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
            -- Fading staged on, or `_apply`'s per-panel branch resolves to "no fading" for every
            -- panel and the assertion below cannot tell a channel from the Log.
            H.SuuUI.Settings:Set("chat", "fade_channels", true)
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
            H.env.ChatFrame1.editBox:SetAttribute("chatType", "GUILD")
            H.SuuUI._ChatInput.Open()
            expect(p._chat._chip:GetText())
                .as("the chip follows the box without anyone refreshing it").eq("Guild")
        end)

        it("follows the channel changing while the box STAYS open, as Tab does", function()
            local p = enabled()
            H.SuuUI._ChatInput.Open()
            local box = H.env.ChatFrame1.editBox
            box:SetAttribute("chatType", "PARTY")
            -- Tab cycles the channel in place; a text change is the only script that fires then.
            box:SetText("x")
            expect(p._chat._chip:GetText()).eq("Party")
        end)

        it("names the PERSON for a whisper, not the word Whisper", function()
            local p = enabled()
            local box = H.env.ChatFrame1.editBox
            box:SetAttribute("chatType", "WHISPER")
            box:SetAttribute("tellTarget", "Sylvaine-TestRealm")
            p._chat:_refreshChip()
            expect(p._chat._chip:GetText())
                .as("the chip answers WHERE this is going, and a name is that answer")
                .contains("Sylvaine")
            expect(p._chat._chip:GetText():find("TestRealm", 1, true))
                .as("own realm stripped, as everywhere else").eq(nil)
        end)

        it("names a numbered channel, not its NUMBER", function()
            -- The bug this pins shipped and took three rounds to find: the edit box carries the
            -- channel NUMBER in `channelTarget`, and the chip rendered `tostring(target)` -- so it
            -- read a bare `1`, which answers nothing. `GetChannelName` returns the index FIRST and
            -- the name second, and reading the wrong slot hands the number straight back.
            local p = enabled()
            H.setChannel(1, "General")
            local box = H.env.ChatFrame1.editBox
            box:SetAttribute("chatType", "CHANNEL")
            box:SetAttribute("channelTarget", 1)
            p._chat:_refreshChip()
            expect(p._chat._chip:GetText())
                .as("the chip answers WHICH channel, and a number does not").eq("General")
        end)

        it("drops a zone channel's qualifier", function()
            local p = enabled()
            H.setChannel(2, "General - Elwynn Forest")
            local box = H.env.ChatFrame1.editBox
            box:SetAttribute("chatType", "CHANNEL")
            box:SetAttribute("channelTarget", 2)
            p._chat:_refreshChip()
            expect(p._chat._chip:GetText())
                .as("you are standing in the zone; naming it back is noise").eq("General")
        end)

        it("colours a numbered channel from CHANNEL<index>, not the generic CHANNEL row", function()
            -- `ChatTypeInfo.CHANNEL` is a DIFFERENT colour from `ChatTypeInfo.CHANNEL1`, so reading
            -- the plain type paints every channel identically and the chip stops carrying identity.
            local p = enabled()
            H.setChannel(1, "General")
            local box = H.env.ChatFrame1.editBox
            box:SetAttribute("chatType", "CHANNEL")
            box:SetAttribute("channelTarget", 1)
            p._chat:_refreshChip()
            local r, g = p._chat._chip._label:GetTextColor()
            expect(g).near(H.env.ChatTypeInfo.CHANNEL1.g, 0.02)
            expect(r).as("and not the generic row").near(H.env.ChatTypeInfo.CHANNEL1.r, 0.02)
        end)

        it("leaves the NUMBER standing for a channel the player has not joined", function()
            -- GetChannelName answers 0 with no name. A blank chip would be worse than the number,
            -- so the number is the fallback rather than an empty label.
            local p = enabled()
            H.clearChannels()
            local box = H.env.ChatFrame1.editBox
            box:SetAttribute("chatType", "CHANNEL")
            box:SetAttribute("channelTarget", 7)
            p._chat:_refreshChip()
            expect(p._chat._chip:GetText()).eq("7")
        end)

        it("colours the chip and the field's border from the channel", function()
            local p = enabled()
            H.env.ChatFrame1.editBox:SetAttribute("chatType", "GUILD")
            p._chat:_refreshChip()
            -- RED as well as green, because SAY and GUILD both carry g = 1: asserting green alone
            -- could not tell the staged channel from the SAY default, so this passed while the chip
            -- was reading the wrong source entirely. Red is 0.25 for GUILD against 1 for SAY.
            local r, g = p._chat._chip._label:GetTextColor()
            expect(g).near(H.env.ChatTypeInfo.GUILD.g, 0.02)
            expect(r).as("red separates GUILD from the SAY default").near(H.env.ChatTypeInfo.GUILD.r, 0.02)
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
            H.SuuUI.Settings:Set("chat", "show_tags", true)
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
