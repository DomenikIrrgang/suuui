-- Keybind mode's panel: Save, Discard, the binding-set switch and the counters.
local H = require("harness")

describe("keybind panel", function()
    before_each(function()
        H.setup()
        H.SuuUI.KeybindMode:Disable()
    end)

    local function KB()    return H.SuuUI.KeybindMode end
    local function panel() return H.SuuUI.KeybindPanel end
    local function ctl()   return panel():_controls() end

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
    end)

    describe("Save", function()
        it("persists the live bindings and clears the pending count", function()
            KB():Enable()
            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON1")
            KB():NoteChange(1)

            expect(KB():Save()).eq(true)
            expect(H.getSavedBindings(1).ACTIONBUTTON1[1]).eq("SHIFT-J")
            expect(KB():ChangedCount()).eq(0)
            expect(KB():IsDirty()).falsy()
        end)

        it("is offered only when there is something to save", function()
            KB():Enable()
            expect(ctl().save._enabled)
                .as("a Save button that looks live with nothing pending invites a click that does "
                    .. "nothing").eq(false)

            KB():NoteChange(1)
            panel():Refresh()
            expect(ctl().save._enabled).eq(true)
        end)
    end)

    describe("Discard", function()
        it("reverts to the last saved state", function()
            KB():Enable()
            H.env.SetBinding("1", "ACTIONBUTTON1")
            KB():Save()

            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON1")
            KB():NoteChange(1)
            expect(select("#", H.env.GetBindingKey("ACTIONBUTTON1"))).eq(2)

            expect(KB():Discard()).eq(true)
            local a, b = H.env.GetBindingKey("ACTIONBUTTON1")
            expect(a).eq("1")
            expect(b).as("the saved set IS the snapshot -- no snapshot table of our own").isNil()
            expect(KB():ChangedCount()).eq(0)
        end)

        it("reverts to the last SAVED state, not to nothing", function()
            KB():Enable()
            H.env.SetBinding("1", "ACTIONBUTTON1")
            KB():Save()
            H.env.SetBinding("SHIFT-J", "ACTIONBUTTON2")
            KB():NoteChange(1)

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
            KB():NoteChange(1)

            expect(KB():SetPerCharacter(true))
                .as("switching LOADS the target set over the live one, so unsaved edits would "
                    .. "vanish without being mentioned").eq(false)
            expect(KB():BindingSet()).as("and the set did not move").eq(1)
        end)

        it("allows the switch once the work is saved", function()
            KB():Enable()
            KB():NoteChange(1)
            expect(KB():SetPerCharacter(true)).eq(false)
            KB():Save()
            expect(KB():SetPerCharacter(true)).as("saving clears the block").eq(true)
        end)

        it("allows the switch once the work is discarded", function()
            KB():Enable()
            KB():NoteChange(1)
            KB():Discard()
            expect(KB():SetPerCharacter(true))
                .as("discarding is just as valid a resolution as saving").eq(true)
        end)
    end)

    describe("the counters", function()
        it("reports how many bindings are pending", function()
            KB():Enable()
            expect(ctl().changed:GetText()).eq("0")
            KB():NoteChange(3)
            panel():Refresh()
            expect(ctl().changed:GetText()).eq("3")
        end)

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
            local after = boundNow()
            expect(after).as("a newly bound button moves the count").eq(before + 1)
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
