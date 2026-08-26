-- Keybind mode's panel and its change ledger: Save, Discard, the binding-set switch, the list.
local H = require("harness")

describe("keybind panel", function()
    before_each(function()
        H.setup()
        H.SuuUI.KeybindMode:Disable()
    end)

    local function KB()    return H.SuuUI.KeybindMode end
    local function panel() return H.SuuUI.KeybindPanel end
    local function ctl()   return panel():_controls() end

    -- The baseline is taken when the mode OPENS, so anything staged before this is "what the player
    -- walked in with" and anything after it is a change.
    local function openWith(staged)
        for cmd, key in pairs(staged or {}) do H.setBinding(cmd, key) end
        KB():Enable()
    end

    describe("lifecycle", function()
        it("is not built until the mode opens", function()
            expect(panel():GetWindow())
                .as("built lazily, so login never constructs components for a panel nobody sees")
                .isNil()
        end)

        it("appears with the mode and hides with it", function()
            KB():Enable()
            local w = panel():GetWindow()
            expect(w).notNil()

            -- ASSERTED ON THE SIGNAL, not on IsShown. WinMeta:Show and Hide run a fade, so the
            -- frame's shown flag lags the intent by an animation -- the signal is emitted
            -- synchronously and is the actual contract.
            local spy = H.signalSpy(w, H.S.SIGNALS.VISIBILITY_CHANGED)
            KB():Disable()
            expect(#spy.calls > 0).as("the panel was told to go").truthy()
            expect(spy.calls[#spy.calls][1]).eq(false)
        end)

        it("leaves the mode when the panel is closed", function()
            KB():Enable()
            panel():GetWindow():Hide()
            expect(KB():IsActive())
                .as("the close box is an exit, matching edit mode's Properties window").eq(false)
        end)

        -- REGRESSED TWICE before this spec existed, both times reported as "the buttons are not
        -- aligned to the bottom of the window". The first fix read the SIZE_CHANGED signal, which for
        -- a `host` container reports the height the WINDOW gave the content frame -- measuring the
        -- window against itself. GetContentSize is the children's bounding box, which is the number
        -- the window should follow.
        it("sizes itself to its content, leaving no dead space under the buttons", function()
            KB():Enable()
            local h = panel():GetWindow():GetHeight()
            local titleH = H.SuuUI.Theme:GetToken("sizeTitleBar") or 26
            expect(h > titleH).as("the window has real content").truthy()
            expect(h < 400)
                .as("a fixed height with content ending well short is what produced the gap")
                .truthy()
        end)
    end)

    describe("opened through the settings toggle rather than Enable()", function()
        -- THE PATH THAT SHIPPED THE BUG. Every other spec in this file calls Enable(), which is why
        -- they all passed while the change list said "No changes yet" in game: the settings-panel
        -- toggle writes the key DIRECTLY through Settings:Set and never reaches Enable(). Anything
        -- that must happen when the mode opens has to hang off the WATCHER, and this asserts it does.
        local function openViaSetting()
            H.SuuUI.Settings:Set("_layout", "keybind_mode", true)
        end

        it("still takes a baseline, so changes are detectable", function()
            H.setBinding("ACTIONBUTTON1", "1")
            openViaSetting()
            expect(KB():IsActive()).eq(true)

            H.env.SetBinding("2", "ACTIONBUTTON1")
            expect(#KB():Changes())
                .as("with no baseline the diff has nothing to compare against and the list is "
                    .. "silently always empty").eq(1)
        end)

        it("still refuses in combat", function()
            H.setCombat(true)
            openViaSetting()
            expect(KB():IsActive())
                .as("Enable() gated combat but the toggle bypassed it, opening a mode that cannot "
                    .. "write a single binding").eq(false)
        end)
    end)

    describe("the change list", function()
        it("is empty when nothing has been touched", function()
            KB():Enable()
            expect(#KB():Changes()).eq(0)
            expect(KB():IsDirty()).falsy()
            expect(ctl().rows[1]:GetText()).eq("No changes yet.")
        end)

        it("reads command, old key and new key", function()
            openWith({ ACTIONBUTTON1 = "1" })
            H.env.SetBinding("2", "ACTIONBUTTON1")

            local list = KB():Changes()
            expect(#list).eq(1)
            -- APPENDS rather than replaces: a command can hold several keys, which is the client's
            -- own model (Blizzard's UI shows "Binding 1" and "Binding 2") and the reason the concept
            -- has a multi-bind dot at all. So the row shows the resulting SET, not a swap.
            expect(KB():FormatChange(list[1])).eq("ACTIONBUTTON1  1 -> 1, 2")
        end)

        it("says cleared when every key is gone", function()
            openWith({ ACTIONBUTTON2 = "3" })
            H.env.SetBinding("3")

            local list = KB():Changes()
            expect(#list).eq(1)
            expect(KB():FormatChange(list[1])).eq("ACTIONBUTTON2  cleared")
            expect(list[1].cleared).truthy()
        end)

        it("names a newly bound button as coming from unbound", function()
            KB():Enable()
            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON1")
            expect(KB():FormatChange(KB():Changes()[1])).eq("ACTIONBUTTON1  unbound -> SHIFT-J")
        end)

        it("keeps ONE entry per button however many times it is rebound", function()
            openWith({ ACTIONBUTTON1 = "1" })
            H.env.SetBinding("2", "ACTIONBUTTON1")
            H.env.SetBinding("3", "ACTIONBUTTON1")
            H.env.SetBinding("4", "ACTIONBUTTON1")

            local list = KB():Changes()
            expect(#list).as("unique per button, as asked").eq(1)
            expect(KB():FormatChange(list[1]))
                .as("from the ORIGINAL state, not the previous intermediate one -- the left side "
                    .. "stays \"1\" however many keys pile up on the right")
                .eq("ACTIONBUTTON1  1 -> 1, 2, 3, 4")
        end)

        it("keeps separate entries for separate buttons", function()
            openWith({ ACTIONBUTTON1 = "1", ACTIONBUTTON2 = "2" })
            H.env.SetBinding("8", "ACTIONBUTTON1")
            H.env.SetBinding("9", "ACTIONBUTTON2")
            expect(#KB():Changes()).eq(2)
        end)

        it("drops an entry that ends up back where it started", function()
            openWith({ ACTIONBUTTON1 = "1" })
            H.env.SetBinding("2", "ACTIONBUTTON1")
            expect(#KB():Changes()).eq(1)

            H.env.SetBinding("2")
            H.env.SetBinding("1", "ACTIONBUTTON1")
            expect(#KB():Changes())
                .as("there is nothing to save, so there is nothing to list").eq(0)
        end)

        it("lists BOTH sides of a steal", function()
            openWith({ ACTIONBUTTON1 = "Q" })
            -- Binding Q elsewhere takes it off ACTIONBUTTON1.
            H.env.SetBinding("Q", "ACTIONBUTTON2")

            local list = KB():Changes()
            expect(#list)
                .as("the button that LOST the key changed too -- a counter incremented at the write "
                    .. "site would never have noticed").eq(2)

            local seen = {}
            for _, row in ipairs(list) do seen[row.command] = KB():FormatChange(row) end
            expect(seen.ACTIONBUTTON1).eq("ACTIONBUTTON1  cleared")
            expect(seen.ACTIONBUTTON2).eq("ACTIONBUTTON2  unbound -> Q")
        end)

        it("stays in a stable order between repaints", function()
            openWith({ ACTIONBUTTON1 = "1", ACTIONBUTTON2 = "2", ACTIONBUTTON3 = "3" })
            H.env.SetBinding("7", "ACTIONBUTTON3")
            H.env.SetBinding("8", "ACTIONBUTTON1")
            H.env.SetBinding("9", "ACTIONBUTTON2")

            local first = KB():Changes()
            local second = KB():Changes()
            for i = 1, #first do
                expect(first[i].command)
                    .as("pairs() order is arbitrary and a list that reshuffles under the player is "
                        .. "unreadable").eq(second[i].command)
            end
            expect(first[1].command).eq("ACTIONBUTTON1")
        end)

        it("keeps the whole change string on the row", function()
            KB():Enable()
            local longest
            for _, b in ipairs(KB():GetButtons()) do
                local cmd = b:GetBinding()
                if cmd and (not longest or #cmd > #longest) then longest = cmd end
            end
            expect(longest).as("there is at least one bindable button").notNil()

            H.env.SetBinding("CTRL-ALT-SHIFT-F11", longest)
            H.env.SetBinding("CTRL-ALT-SHIFT-F12", longest)
            panel():Refresh()

            local row = ctl().rows[1]
            expect(row:GetText():find(longest, 1, true))
                .as("the command name survives into the row").notNil()
            expect(row:GetText():find("CTRL%-ALT%-SHIFT%-F12"))
                .as("and so does the last key -- the STRING is whole even where the pixels were not")
                .notNil()
        end)

        -- PINNED AT THE COMPONENT LEVEL instead of here, in 10_frame_text_spec.lua ("honours a width
        -- given without a height"). Four attempts to assert it on this row all passed on the broken
        -- code -- GetText() returns the string HANDED to the label rather than the pixels drawn,
        -- GetWidth() returns the width the CONTAINER assigned, and GetNumLines() and
        -- H.expectTextNotClipped were both defeated by the same thing. The cause was not in this
        -- panel at all: Components/Text.lua applied `w` only when `h` was given too, so a
        -- width-only caller got no width, and a FontString with no width cannot wrap. Asserted where
        -- the value is SET rather than where it is inferred.



        it("renders one row per change and hides the surplus", function()            openWith({ ACTIONBUTTON1 = "1", ACTIONBUTTON2 = "2" })
            H.env.SetBinding("8", "ACTIONBUTTON1")
            H.env.SetBinding("9", "ACTIONBUTTON2")
            panel():Refresh()
            expect(ctl().rows[1]:IsShown()).truthy()
            expect(ctl().rows[2]:IsShown()).truthy()

            KB():Save()
            panel():Refresh()
            expect(ctl().rows[2]:IsShown())
                .as("surplus rows are pooled and hidden, not leaked per keystroke").falsy()
        end)
    end)

    describe("Save", function()
        it("persists the live bindings and empties the list", function()
            openWith({})
            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON1")
            expect(KB():IsDirty()).truthy()

            expect(KB():Save()).eq(true)
            expect(H.getSavedBindings(1).ACTIONBUTTON1[1]).eq("SHIFT-J")
            expect(#KB():Changes())
                .as("the saved state IS the new baseline, so the list empties by definition").eq(0)
        end)

        it("is offered only when there is something to save", function()
            KB():Enable()
            panel():Refresh()
            expect(ctl().save._enabled)
                .as("a Save button that looks live with nothing pending invites a click that does "
                    .. "nothing").eq(false)

            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON1")
            panel():Refresh()
            expect(ctl().save._enabled).eq(true)
        end)
    end)

    describe("Discard", function()
        it("reverts to the last saved state", function()
            openWith({ ACTIONBUTTON1 = "1" })
            KB():Save()

            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON1")
            expect(select("#", H.env.GetBindingKey("ACTIONBUTTON1"))).eq(2)

            expect(KB():Discard()).eq(true)
            local a, b = H.env.GetBindingKey("ACTIONBUTTON1")
            expect(a).eq("1")
            expect(b).as("the saved set IS the snapshot -- no snapshot table of our own").isNil()
            expect(#KB():Changes()).eq(0)
        end)

        it("reverts to the last SAVED state, not to nothing", function()
            openWith({ ACTIONBUTTON1 = "1" })
            KB():Save()
            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON2")

            KB():Discard()
            expect(H.env.GetBindingKey("ACTIONBUTTON1"))
                .as("an unsaved SetBinding survives a reload on its own, so Discard is a SESSION "
                    .. "undo and the panel must not promise more").eq("1")
        end)
    end)

    describe("the account-wide / character switch", function()
        it("switches sets when there is nothing pending", function()
            KB():Enable()
            expect(KB():BindingSet()).as("account-wide by default, measured").eq(1)
            expect(KB():SetPerCharacter(true)).eq(true)
            expect(KB():BindingSet()).eq(2)
        end)

        it("REFUSES while there are unsaved changes", function()
            KB():Enable()
            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON1")

            expect(KB():SetPerCharacter(true))
                .as("switching LOADS the target set over the live one, so unsaved edits would "
                    .. "vanish without being mentioned").eq(false)
            expect(KB():BindingSet()).as("and the set did not move").eq(1)
        end)

        it("allows the switch once the work is saved", function()
            KB():Enable()
            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON1")
            expect(KB():SetPerCharacter(true)).eq(false)
            KB():Save()
            expect(KB():SetPerCharacter(true)).as("saving clears the block").eq(true)
        end)

        it("allows the switch once the work is discarded", function()
            openWith({ ACTIONBUTTON1 = "1" })
            KB():Save()
            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON1")
            KB():Discard()
            expect(KB():SetPerCharacter(true))
                .as("discarding is just as valid a resolution as saving").eq(true)
        end)
    end)

    describe("the bound counter", function()
        it("counts bound buttons against the total", function()
            KB():Enable()
            local function boundNow()
                local a, b = ctl().bound:GetText():match("^(%d+) / (%d+)$")
                return tonumber(a), tonumber(b)
            end
            local before, total = boundNow()
            expect(total).as("reads as bound / total").notNil()

            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON1")
            panel():Refresh()
            expect((boundNow())).as("a newly bound button moves the count").eq(before + 1)
        end)

        it("follows a binding change without the overlays telling it to", function()
            KB():Enable()
            local function boundNow()
                return tonumber(ctl().bound:GetText():match("^(%d+)"))
            end
            local before = boundNow()
            -- No explicit Refresh: the panel listens for UPDATE_BINDINGS itself, so a write made on
            -- any button reaches it without the overlay module knowing the panel exists.
            H.env.SetBinding("SHIFT-K", "ACTIONBUTTON2")
            expect(boundNow()).eq(before + 1)
        end)
    end)
end)
