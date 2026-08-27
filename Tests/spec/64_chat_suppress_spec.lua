-- Phase 4b: suppressing Blizzard's chat, and mirroring the addon output that would otherwise be
-- lost with it.
local H = require("harness")

describe("chat suppression", function()
    before_each(function() H.setup() end)

    local function B() return H.SuuUI._ChatBlizzard end
    local function P() return H.SuuUI.Plugins:Get("chat") end

    local function enabled()
        local p = P()
        H.SuuUI.Settings:Set("chat", "enabled", true)
        return p
    end

    describe("frame resolution", function()
        it("finds every chat log the client has, not a hardcoded count", function()
            local frames = B().Frames()
            local names = {}
            for _, f in ipairs(frames) do names[f:GetName() or "?"] = true end
            expect(names["ChatFrame1"]).eq(true)
            expect(names["ChatFrame" .. H.env.NUM_CHAT_WINDOWS])
                .as("resolved from NUM_CHAT_WINDOWS, so a client with more is covered").eq(true)
        end)

        it("includes each log's TAB, which is a separate frame", function()
            local names = {}
            for _, f in ipairs(B().Frames()) do names[f:GetName() or "?"] = true end
            expect(names["ChatFrame1Tab"])
                .as("hiding the log and leaving its tab on screen is a real bug shape").eq(true)
        end)

        it("includes the dock and the menu button", function()
            local names = {}
            for _, f in ipairs(B().Frames()) do names[f:GetName() or "?"] = true end
            expect(names["GeneralDockManager"]).eq(true)
            expect(names["ChatFrameMenuButton"]).eq(true)
        end)

        it("skips a candidate this client does not have", function()
            H.env.ChatFrameMenuButton = nil
            local names = {}
            for _, f in ipairs(B().Frames()) do names[f:GetName() or "?"] = true end
            expect(names["ChatFrameMenuButton"])
                .as("an absent global is skipped, not raised on").eq(nil)
            expect(names["ChatFrame1"]).as("and the rest still resolve").eq(true)
        end)
    end)

    describe("suppress and restore", function()
        it("parks every frame under a hidden parent", function()
            B().Suppress()
            expect(B().SuppressedCount()).gt(10)
            expect(H.env.ChatFrame1:IsVisible())
                .as("a child of a hidden parent renders nothing whatever its own flag says")
                .eq(false)
        end)

        it("leaves the frame's own shown flag alone, so nothing is fighting a Hide", function()
            B().Suppress()
            expect(H.env.ChatFrame1:IsShown())
                .as("IsShown and IsVisible disagree on purpose -- there is no Hide for Blizzard "
                    .. "to undo").eq(true)
        end)

        it("is idempotent", function()
            B().Suppress()
            local n = B().SuppressedCount()
            B().Suppress()
            expect(B().SuppressedCount()).eq(n)
        end)

        it("hands every frame back to the parent it came from", function()
            -- The plugin suppresses AT BOOT, because hide_blizzard defaults on -- so a `before`
            -- captured now would read the POST-suppression parent. Restore to a known clean state
            -- first, which is what makes the assertion mean anything.
            B().Restore()
            -- A NON-UIParent home, because UIParent is also the fallback when no original was
            -- recorded: with the harness's default parent the recorded and guessed answers are
            -- identical and a mutation dropping the record survives.
            local home = H.parent(200, 100)
            H.env.ChatFrame1:SetParent(home)
            B().Suppress()
            B().Restore()
            expect(H.env.ChatFrame1:GetParent())
                .as("restored to its ORIGINAL parent, not blanket-reparented to UIParent")
                .eq(home)
            expect(B().SuppressedCount()).eq(0)
        end)

        it("re-parks a frame another addon dragged out, and can still restore it", function()
            B().Restore()
            local home = H.parent(200, 100)
            H.env.ChatFrame1:SetParent(home)
            B().Suppress()
            -- Something steals it, then we re-park. A re-park must NOT record the hidden holder as
            -- the original -- that would make Restore park it under a hidden frame permanently,
            -- which is an unrecoverable chat.
            H.env.ChatFrame1:SetParent(H.UIParent)
            B().Suppress()
            expect(H.env.ChatFrame1:IsVisible())
                .as("Suppress is self-healing rather than trusting its own flag").eq(false)
            B().Restore()
            expect(H.env.ChatFrame1:GetParent())
                .as("the re-park must not have overwritten the real home with the holder")
                .eq(home)
            expect(H.env.ChatFrame1:IsVisible()).eq(true)
        end)

        it("leaves a frame alone that it never suppressed", function()
            B().Restore()
            -- Another addon takes it. SuuUI must not drag it back on the next Restore, which is
            -- the "never show a frame someone else hid" rule.
            local theirs = H.parent(200, 100)
            H.env.ChatFrame1:SetParent(theirs)
            B().Restore()
            expect(H.env.ChatFrame1:GetParent()).eq(theirs)
        end)

        it("survives a suppress/restore cycle repeatedly", function()
            B().Restore()
            local before = H.env.ChatFrame1:GetParent()
            for _ = 1, 3 do B().Suppress() B().Restore() end
            expect(H.env.ChatFrame1:GetParent()).eq(before)
            expect(H.env.ChatFrame1:IsVisible()).eq(true)
        end)
    end)

    describe("Verify", function()
        it("passes when everything is parked", function()
            B().Suppress()
            local ok = B().Verify()
            expect(ok).eq(true)
        end)

        it("reports rather than raises when a frame is still visible", function()
            -- SuuUI.Debug is gated behind the debug flag, so the log line only exists with it on.
            -- Asserting the RETURN as well, since that is the contract a caller acts on.
            H.SuuUI._debug = true
            B().Suppress()
            -- Drag one back out, as another addon reparenting it would.
            H.env.ChatFrame1:SetParent(H.UIParent)
            local ok, bad = B().Verify()
            expect(ok).eq(false)
            expect(#bad).eq(1)
            local found = false
            for _, line in ipairs(H.debugLog()) do
                if line:find("still visible", 1, true) then found = true end
            end
            expect(found)
                .as("a stray visible chat frame is cosmetic, not a reason to take the plugin down")
                .eq(true)
        end)
    end)

    describe("the addon-output mirror", function()
        it("mirrors a print(), which arrives by no chat event", function()
            local got = {}
            B().MirrorAddonOutput(function(text) got[#got + 1] = text end)
            H.env.print("DBM: pull in 10")
            expect(#got).eq(1)
            expect(got[1]).contains("DBM: pull in 10")
        end)

        it("IGNORES a line carrying a chat-type id", function()
            local got = {}
            B().MirrorAddonOutput(function(text) got[#got + 1] = text end)
            -- Blizzard's own handler passes info.id as the fifth argument. Mirroring it would
            -- double every chat line, since our CHAT_MSG registration already formatted it.
            H.env.DEFAULT_CHAT_FRAME:AddMessage("Thalvyn says: hi", 1, 1, 1, 42)
            expect(#got)
                .as("the chat-type id is the discriminator between chat and addon output").eq(0)
        end)

        it("mirrors a bare AddMessage with no id", function()
            local got = {}
            B().MirrorAddonOutput(function(text) got[#got + 1] = text end)
            H.env.DEFAULT_CHAT_FRAME:AddMessage("Questie: quest complete")
            expect(#got).eq(1)
        end)

        it("HOOKS rather than replaces, so Blizzard's frame still receives", function()
            B().MirrorAddonOutput(function() end)
            local before = H.env.DEFAULT_CHAT_FRAME:GetNumMessages()
            H.env.print("still lands")
            expect(H.env.DEFAULT_CHAT_FRAME:GetNumMessages())
                .as("replacing AddMessage taints 10/10 and is what retired LS: Glass")
                .eq(before + 1)
        end)

        it("is disarmed by a nil callback, since the hook cannot be uninstalled", function()
            local got = {}
            B().MirrorAddonOutput(function(text) got[#got + 1] = text end)
            B().MirrorAddonOutput(nil)
            H.env.print("after disarm")
            expect(#got).eq(0)
        end)

        it("ignores an empty line", function()
            local got = {}
            B().MirrorAddonOutput(function(text) got[#got + 1] = text end)
            H.env.DEFAULT_CHAT_FRAME:AddMessage("")
            expect(#got).eq(0)
        end)

        it("does not double-hook when armed twice", function()
            local got = {}
            B().MirrorAddonOutput(function(text) got[#got + 1] = text end)
            B().MirrorAddonOutput(function(text) got[#got + 1] = text end)
            H.env.print("once")
            expect(#got).as("a second hook would mirror every line twice").eq(1)
        end)
    end)

    describe("plugin wiring", function()
        it("suppresses on enable, because the setting defaults on", function()
            enabled()
            expect(H.env.ChatFrame1:IsVisible()).eq(false)
        end)

        it("has its own TOP-LEVEL toggle, outside every section", function()
            local schema = H.SuuUI.Settings:GetSchema("chat")
            local seenSection = false
            for _, e in ipairs(schema) do
                if e.type == "section" then seenSection = true end
                if e.key == "hide_blizzard" then
                    expect(seenSection)
                        .as("a player whose chat misbehaves must reach it without opening a group")
                        .eq(false)
                end
            end
        end)

        it("hands Blizzard's chat back when the toggle goes off", function()
            enabled()
            H.SuuUI.Settings:Set("chat", "hide_blizzard", false)
            expect(H.env.ChatFrame1:IsVisible())
                .as("the escape hatch is one toggle, no reload").eq(true)
        end)

        it("re-suppresses when it goes back on", function()
            enabled()
            H.SuuUI.Settings:Set("chat", "hide_blizzard", false)
            H.SuuUI.Settings:Set("chat", "hide_blizzard", true)
            expect(H.env.ChatFrame1:IsVisible()).eq(false)
        end)

        it("routes an addon print into OUR log", function()
            -- Into the LOG panel: addon output is not conversation, so it goes where loot and XP
            -- go rather than into whichever tab the player happens to have open.
            local p = enabled()
            H.env.print("Details: 4.2k dps")
            local log = p._chat:LogFor("log")
            expect(log)
                .as("without this every other addon's output vanishes with Blizzard's chat")
                .notNil()
            expect(log:GetNumMessages()).eq(1)
            expect((log:GetMessageInfo(1))).contains("Details: 4.2k dps")
        end)

        it("does NOT double a real chat message", function()
            local p = enabled()
            H.chat("CHAT_MSG_SAY", { text = "hello", sender = "Grimtusk" })
            expect(p._chat:LogFor("general"):GetNumMessages())
                .as("our own CHAT_MSG registration already formatted it").eq(1)
        end)

        it("restores Blizzard's chat on disable, before hiding ours", function()
            enabled()
            H.SuuUI.Settings:Set("chat", "enabled", false)
            expect(H.env.ChatFrame1:IsVisible())
                .as("the player must never be left with neither chat").eq(true)
        end)

        it("disarms the mirror on disable", function()
            local p = enabled()
            H.SuuUI.Settings:Set("chat", "enabled", false)
            local log = p._chat:LogFor("log") or p._chat:LogFor("general")
            local before = log:GetNumMessages()
            H.env.print("after disable")
            expect(log:GetNumMessages())
                .as("a live mirror would keep writing into a hidden log for the whole session")
                .eq(before)
        end)
    end)
end)
