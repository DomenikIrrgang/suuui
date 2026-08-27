-- Blizzard's edit box, adopted rather than replaced. The seam this pins is the one that cannot be
-- changed later without losing /cast and shift-click-to-link, so it is asserted structurally.
local H = require("harness")

describe("ChatInput", function()
    before_each(function() H.setup() end)

    local function I() return H.SuuUI._ChatInput end
    local function eb() return H.env.ChatFrame1.editBox end

    -- The plugin ADOPTS at login, so a spec about adoption has to start from the unadopted state.
    -- Disabling hands the box back, which is also the escape hatch a player has.
    local function unadopted()
        H.SuuUI.Settings:Set("chat", "enabled", false)
        return eb()
    end

    describe("the seam", function()
        it("creates NO EditBox of its own", function()
            -- The load-bearing assertion of the whole file. `hash_SecureCmdList` is file-local with
            -- no global handle, so a custom box permanently loses /cast, /target, /click, /use,
            -- /castsequence, /focus, /equip and /startattack -- and shift-click inserts a link only
            -- into ACTIVE_CHAT_EDIT_BOX, which only Blizzard's ActivateChat sets.
            local f = io.open("Plugins/Chat/ChatInput.lua", "r")
            expect(f).notNil()
            local src = f:read("*a")
            f:close()
            expect(src:find('CreateFrame%s*%(%s*"EditBox"'))
                .as("this module must never create an edit box").eq(nil)
        end)

        it("resolves the box the CHAT FRAME owns, not a global name", function()
            -- The two are the same object in practice, so the preference only means something when
            -- they DIFFER -- which is what makes this assertion able to fail.
            local mine = eb()
            local decoy = H.parent(10, 10)
            H.env.ChatFrame1EditBox = decoy
            expect(I().Resolve())
                .as("the field is what Blizzard's own code reads").eq(mine)
            expect(I().Resolve()).neq(decoy)
        end)

        it("falls back to the global when the frame has no field", function()
            H.env.ChatFrame1.editBox = nil
            expect(I().Resolve()).eq(H.env.ChatFrame1EditBox)
        end)

        it("answers nil when there is no box at all, rather than raising", function()
            H.env.ChatFrame1.editBox = nil
            H.env.ChatFrame1EditBox = nil
            expect(I().Resolve()).eq(nil)
        end)
    end)

    describe("the box is a CHILD of the chat frame", function()
        it("is parented to ChatFrame1 when not adopted", function()
            unadopted()
            -- This is why adoption is necessary rather than cosmetic: suppression parks ChatFrame1
            -- on a permanently hidden holder, and a child of a hidden parent renders nothing
            -- whatever its own shown flag says. Unadopted, pressing Enter opens an input the player
            -- cannot see -- they can type and send, they just cannot read what they typed.
            expect(eb():GetParent()).eq(H.env.ChatFrame1)
        end)

        it("is invisible once the chat frame is suppressed, unadopted", function()
            local box = unadopted()
            H.SuuUI._ChatBlizzard.Restore()
            box:Show()
            expect(box:IsVisible()).as("visible while its parent is").truthy()
            H.SuuUI._ChatBlizzard.Suppress()
            expect(box:IsShown()).as("its own flag is untouched").truthy()
            expect(box:IsVisible())
                .as("but a child of a hidden parent draws nothing").falsy()
        end)
    end)

    describe("Adopt", function()
        it("reparents the box and clears its anchors", function()
            local host = H.parent(300, 30)
            local got = I().Adopt(host)
            expect(got).eq(eb())
            expect(eb():GetParent()).eq(host)
            expect(eb():GetNumPoints()).as("the container places it now").eq(0)
        end)

        it("records the ORIGINAL parent only once", function()
            -- Re-recording on a second adopt would capture our own frame and make the box
            -- unrestorable -- the same trap BlizzardChat.park documents.
            unadopted()
            local a, b = H.parent(300, 30), H.parent(300, 30)
            I().Adopt(a)
            I().Adopt(b)
            I().Restore()
            expect(eb():GetParent())
                .as("back to the chat frame, not to the first host").eq(H.env.ChatFrame1)
        end)

        it("refuses gracefully with no parent", function()
            expect(I().Adopt(nil)).eq(nil)
        end)
    end)

    describe("Restore", function()
        it("hands the box back to its parent and anchor", function()
            -- The anchor restored is the one recorded at the FIRST adopt, which happens at login --
            -- not whatever the box carried most recently. That is the point of recording once.
            local box = unadopted()
            expect(box:GetParent()).eq(H.env.ChatFrame1)
            local pt, _, relP, x, y = box:GetPoint(1)
            expect(pt).as("its own anchor is back").eq("TOPLEFT")
            expect(relP).eq("BOTTOMLEFT")
            expect(x).eq(0)
            expect(y).eq(-6)
        end)

        it("is a no-op when nothing is adopted", function()
            unadopted()
            expect(I().Restore()).as("already handed back").falsy()
        end)
    end)

    describe("Skin", function()
        it("clears the template's art, which is sized for its old home", function()
            -- Enumerated through GetRegions rather than by name: a hand-written name list is what
            -- drew a stray blue lattice over the inventory grid, because the names differ across
            -- client generations and a missing one is silent.
            local box = unadopted()
            local tex = box:CreateTexture(nil, "BACKGROUND")
            tex:SetTexture("Interface\\ChatFrame\\UI-ChatInputBorder-Left")
            tex:Show()
            I().Adopt(H.parent(300, 30))
            expect(tex:IsShown()).as("the caps would read as a second, wrong-sized frame").falsy()
        end)

        it("gives the box OUR font, so the field matches the log", function()
            unadopted()
            I().Adopt(H.parent(300, 30))
            local path, size = eb():GetFont()
            expect(path).eq(H.SuuUI.Fonts:Path(H.token("fontFamilyMain")))
            expect(size).eq(H.SuuUI.Theme:GetFontSize("md"))
        end)

        it("tightens the text insets, which are sized for a taller field", function()
            unadopted()
            I().Adopt(H.parent(300, 30))
            local l = eb():GetTextInsets()
            expect(l).as("a large left inset pushes a short string out of a short row")
                .eq(H.token("spaceXs"))
        end)

        it("raises the box above its parent's backdrop", function()
            -- Text drawing UNDER the surface it sits on is indistinguishable from no text at all.
            unadopted()
            local host = H.parent(300, 30)
            I().Adopt(host)
            expect(eb():GetFrameLevel()).gt(host:GetFrameLevel())
        end)

        it("survives a client that refuses any of it, rather than raising at login", function()
            -- This runs against a frame we do not own, and SetFont RAISES on an unloadable asset.
            local box = unadopted()
            box.SetTextInsets = function() error("refused") end
            box.SetFont = function() error("refused") end
            expect(pcall(I().Adopt, H.parent(300, 30))).truthy()
        end)
    end)

    describe("ChatType", function()
        it("reads the channel off the BOX, not off ChatTypeInfo.sticky", function()
            -- `sticky = 1` means "this type MAY be remembered", not "you last spoke here", and six
            -- types carry it -- so scanning for it returned whichever came first in an arbitrary
            -- iteration order. Phase 4a shipped exactly that and always read "Say".
            -- Staged as an ATTRIBUTE, which is where the client keeps it -- ElvUI reads
            -- `editbox:GetAttribute('chatType')` in two places. Setting the plain FIELD instead is
            -- what this spec did originally, and it passed against a production version that read
            -- the field: the harness now defaults the attribute to "SAY", so a field-only staging
            -- correctly fails. That failure is the point, not a regression.
            eb():SetAttribute("chatType", "GUILD")
            expect((I().ChatType())).eq("GUILD")
        end)

        it("defaults to SAY when the box says nothing", function()
            -- BOTH cleared. With only the field cleared this passed for the wrong reason: the
            -- harness defaults the attribute to "SAY", so the assertion was reading that default
            -- rather than the guard under test.
            eb():SetAttribute("chatType", nil)
            eb().chatType = nil
            expect((I().ChatType())).eq("SAY")
            eb():SetAttribute("chatType", "")
            eb().chatType = ""
            expect((I().ChatType())).eq("SAY")
        end)

        it("carries the whisper TARGET, which is what the chip needs", function()
            eb():SetAttribute("chatType", "WHISPER")
            eb():SetAttribute("tellTarget", "Sylvaine")
            local t, target = I().ChatType()
            expect(t).eq("WHISPER")
            expect(target).eq("Sylvaine")
        end)

        it("carries a numbered channel's target", function()
            eb():SetAttribute("chatType", "CHANNEL")
            eb():SetAttribute("channelTarget", 2)
            local t, target = I().ChatType()
            expect(t).eq("CHANNEL")
            expect(target).eq(2)
        end)

        it("falls back to the plain FIELD when the attribute is absent", function()
            -- The fallback is deliberate rather than leftover: it costs one `or` and a client
            -- generation that exposes the field instead then needs no change here. Pinned so the
            -- attribute-first fix above cannot quietly delete it.
            eb():SetAttribute("chatType", nil)
            eb():SetAttribute("tellTarget", nil)
            eb().chatType = "WHISPER"
            eb().tellTarget = "Aldara"
            local t, target = I().ChatType()
            expect(t).as("field read when no attribute is set").eq("WHISPER")
            expect(target).as("target read from the field too").eq("Aldara")
        end)

        it("answers SAY with no box at all", function()
            H.env.ChatFrame1.editBox = nil
            H.env.ChatFrame1EditBox = nil
            expect((I().ChatType())).eq("SAY")
        end)
    end)

    describe("Open and Close", function()
        it("opens through the CLIENT's activation, so links can be shift-clicked in", function()
            -- ACTIVE_CHAT_EDIT_BOX is set by Blizzard's ActivateChat and by nothing else, and it is
            -- what shift-click-to-insert-a-link writes into.
            I().Adopt(H.parent(300, 30))
            expect(I().Open()).truthy()
            expect(H.env.ACTIVE_CHAT_EDIT_BOX).eq(eb())
            expect(I().IsOpen()).truthy()
        end)

        it("prefers the MODERN ChatFrameUtil name over the deprecation shim", function()
            -- This client runs the refactored Blizzard_ChatFrameBase; the bare ChatEdit_* globals
            -- are shims. Removing the modern table must still work, which is what proves the
            -- fallback is real rather than decorative.
            local seen = false
            H.env.ChatFrameUtil = { ActivateChat = function() seen = true end }
            I().Open()
            expect(seen).truthy()
        end)

        it("falls back to the bare global when ChatFrameUtil is absent", function()
            H.env.ChatFrameUtil = nil
            local seen = false
            H.env.ChatEdit_ActivateChat = function() seen = true end
            expect(I().Open()).truthy()
            expect(seen).truthy()
        end)

        it("reports failure when the client offers neither", function()
            H.env.ChatFrameUtil = nil
            H.env.ChatEdit_ActivateChat = nil
            expect(I().Open()).falsy()
        end)

        it("closes through the client too", function()
            I().Open()
            expect(I().Close()).truthy()
            expect(I().IsOpen()).falsy()
        end)
    end)

    describe("Watch", function()
        it("reports the box opening and closing", function()
            local states = {}
            I().Adopt(H.parent(300, 30))
            I().Watch(function(open) states[#states + 1] = open end)
            I().Open()
            I().Close()
            expect(#states).gte(2)
            expect(states[1]).truthy()
            expect(states[#states]).falsy()
        end)

        it("uses HookScript and never SetScript on the box", function()
            -- Asserted STRUCTURALLY, because it cannot be isolated behaviourally: the hooks are
            -- installed once at login, before any spec can arrange the state, and the OnTextChanged
            -- hook reports on the same callback as OnShow -- so a SetScript mutation on OnShow is
            -- masked. Same shape as 00_harness_spec's check that no shipped file calls a
            -- harness-only name.
            --
            -- The invariant is real: the box's own OnShow/OnHide drive Blizzard's history and
            -- sticky-channel bookkeeping, and replacing either breaks them with no error.
            local f = io.open("Plugins/Chat/ChatInput.lua", "r")
            expect(f).notNil()
            local src = f:read("*a")
            f:close()
            -- The CALL form, not the bare word -- the prose above the hook says "never SetScript".
            expect(src:find("[%w_]+:SetScript%s*%("))
                .as("the box's own scripts are Blizzard's; only HookScript is allowed").eq(nil)
            expect(src:find("[%w_]+:HookScript%s*%(")).as("and it does hook").notNil()
        end)

        it("HOOKS, so a later SetScript cannot silence the watcher", function()
            -- The box's OnShow/OnHide drive Blizzard's history and sticky-channel bookkeeping, so
            -- SetScript would break both silently. Asserted from the OTHER direction, because the
            -- hook is installed once at login and cannot be reinstalled: something else setting a
            -- script must not stop our callback, which only holds if we hooked rather than set.
            local box = unadopted()
            local theirs = false
            box:SetScript("OnShow", function() theirs = true end)
            local ours = false
            I().Watch(function() ours = true end)
            I().Open()
            expect(theirs).as("their handler runs").truthy()
            expect(ours).as("and ours still does, because it is a hook").truthy()
        end)

        it("disarms on nil, since a hook cannot be uninstalled", function()
            local n = 0
            I().Watch(function() n = n + 1 end)
            I().Open()
            local after = n
            I().Watch(nil)
            I().Close()
            I().Open()
            expect(n).as("the callback is consulted on every fire").eq(after)
        end)
    end)
end)
