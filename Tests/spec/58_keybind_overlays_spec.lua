-- Keybind mode's overlays and the binding write. The mode's STATE is 56_keybind_mode_spec.lua.
local H = require("harness")

describe("keybind overlays", function()
    local PLUGIN = "action_bars"

    before_each(function()
        H.setup()
        H.SuuUI.KeybindMode:Disable()
    end)

    local function KB()  return H.SuuUI.ActionBarKeybind end
    local function grid(id) return H.SuuUI.Plugins:Get(PLUGIN)._bars[id or 1] end
    local function button(i, id) return grid(id):GetButtons()[i or 1] end

    local function openOn(i)
        H.SuuUI.KeybindMode:Enable()
        return button(i)
    end

    describe("the mode gate", function()
        it("draws nothing until the mode opens", function()
            expect(KB().OverlayFor(button(1)))
                .as("registration is cheap and must cost nothing while the mode is shut").isNil()
        end)

        it("builds an overlay per button when it opens", function()
            local b = openOn(1)
            expect(KB().OverlayFor(b)).notNil()
        end)

        it("tears every overlay down when it closes", function()
            local b = openOn(1)
            H.SuuUI.KeybindMode:Disable()
            expect(KB().OverlayFor(b)).isNil()
        end)
    end)

    describe("the key chip", function()
        it("abbreviates at rest so it fits a 32-unit button", function()
            H.setBinding("ACTIONBUTTON1", "SHIFT-1")
            local b = openOn(1)
            expect(KB().OverlayFor(b).chipText:GetText())
                .as("the full string smeared across neighbours in game -- five chips reading "
                    .. "ALT-RLT-ALT-ZLT-ALT-GLT-V on one bar").eq("S1")
        end)

        it("shows the FULL key once hovered, which is the point of the mode", function()
            H.setBinding("ACTIONBUTTON1", "SHIFT-1")
            local b = openOn(1)
            KB().Arm(b)
            expect(KB().OverlayFor(b).chipText:GetText())
                .as("confirming exactly what bound is why the chip exists at all").eq("SHIFT-1")
        end)

        it("shows nothing at all on an unbound button at rest", function()
            local b = openOn(1)
            local rec = KB().OverlayFor(b)
            expect(rec.chipText:GetText()).eq("")
            expect(rec.chip:IsShown())
                .as("\"unbound\" was the longest string of the lot and it was on every empty "
                    .. "button at once").falsy()
        end)

        it("says unbound only when hovered, where the player is actually asking", function()
            local b = openOn(1)
            KB().Arm(b)
            expect(KB().OverlayFor(b).chipText:GetText()).eq("unbound")
        end)

        it("marks a button holding more than one key", function()
            H.setBinding("ACTIONBUTTON1", "1")
            local b = openOn(1)
            expect(KB().OverlayFor(b).dot:IsShown()).as("one key, no dot").falsy()

            H.addBinding("ACTIONBUTTON1", "CTRL-F9")
            H.fireEvent("UPDATE_BINDINGS")
            expect(KB().OverlayFor(b).dot:IsShown())
                .as("the chip can only show one key, so more-than-one needs its own channel")
                .truthy()
        end)
    end)

    describe("keyboard capture", function()
        it("is released until the button is hovered", function()
            local b = openOn(1)
            expect(KB().OverlayFor(b).f:IsKeyboardEnabled())
                .as("exclusive capture swallows EVERYTHING, so a mode-wide listener would eat chat "
                    .. "and movement for as long as the mode is open").falsy()
        end)

        it("is taken on hover and handed back on leave", function()
            local b = openOn(1)
            KB().Arm(b)
            expect(KB().OverlayFor(b).f:IsKeyboardEnabled()).truthy()
            KB().Disarm(b)
            expect(KB().OverlayFor(b).f:IsKeyboardEnabled()).falsy()
        end)

        it("captures exclusively, which is the only mode that works on this client", function()
            local b = openOn(1)
            expect(KB().OverlayFor(b).f._propagateKeyboard)
                .as("a frame with SetPropagateKeyboardInput(true) received NO OnKeyUp at all -- "
                    .. "measured, the probe printed nothing for any key").eq(false)
        end)

        -- THE INVARIANT THE WRITE PATH RESTS ON. If two overlays are listening, one keypress can be
        -- answered by a button the pointer is nowhere near -- which is exactly the symptom reported
        -- in game as "sometimes it binds it to a different button".
        it("leaves exactly one overlay listening, whatever the hover history", function()
            H.SuuUI.KeybindMode:Enable()
            local bs = grid(1):GetButtons()

            local function listeners()
                local n, names = 0, {}
                for _, b in ipairs(H.SuuUI.KeybindMode:GetButtons()) do
                    local r = KB().OverlayFor(b)
                    if r and r.f:IsKeyboardEnabled() then
                        n = n + 1
                        names[#names + 1] = tostring(b:GetBinding())
                    end
                end
                return n, table.concat(names, ",")
            end

            expect(listeners()).as("nothing hovered, nothing listening").eq(0)

            KB().Arm(bs[1])
            local n = listeners()
            expect(n).eq(1)

            -- Hop across several buttons without a matching Disarm between them, which is what a
            -- fast mouse sweep produces.
            KB().Arm(bs[2])
            KB().Arm(bs[3])
            KB().Arm(bs[4])
            local n2, who = listeners()
            expect(n2).as("listeners: " .. who).eq(1)

            KB().Disarm(bs[4])
            expect(listeners()).as("leaving hands the keyboard back").eq(0)
        end)

        it("does not leave a destroyed overlay listening", function()
            H.SuuUI.KeybindMode:Enable()
            local b = grid(1):GetButtons()[1]
            KB().Arm(b)
            local f = KB().OverlayFor(b).f
            expect(f:IsKeyboardEnabled()).truthy()

            H.SuuUI.KeybindMode:Disable()
            expect(f:IsKeyboardEnabled())
                .as("hiding and reparenting a frame does NOT undo EnableKeyboard, so the release "
                    .. "has to be explicit").falsy()
            expect(KB().GetArmed()).as("and armed must not outlive its overlay").isNil()
        end)
    end)

    describe("the combo builder", function()
        local function combo(key) return KB()._comboFor(key) end

        it("uses a bare key when no modifier is held", function()
            expect(combo("Q")).eq("Q")
        end)

        it("orders modifiers ALT-CTRL-SHIFT-META-", function()
            H.mods({ alt = true, ctrl = true, shift = true, meta = true })
            expect(combo("Q"))
                .as("copied from ElvUI, which ships a working keybind mode on this client. The "
                    .. "client stores ONE canonical order and a different order is a different "
                    .. "binding -- an in-game check by construction").eq("ALT-CTRL-SHIFT-META-Q")
        end)

        it("includes Cmd as META-, the prefix this client really uses", function()
            H.mods({ meta = true })
            expect(combo("Q"))
                .as("confirmed from one of the player's own bindings rendering as META-Q")
                .eq("META-Q")
        end)
    end)

    describe("the ignore list", function()
        local function ignored(k) return KB()._ignored(k) end

        it("drops bare modifiers", function()
            for _, k in ipairs({ "LSHIFT", "RSHIFT", "LCTRL", "RCTRL", "LALT", "RALT" }) do
                expect(ignored(k)).as(k .. " alone is reaching for a combination, not choosing one")
                    .eq(true)
            end
        end)

        it("drops UNKNOWN and nothing", function()
            expect(ignored("UNKNOWN")).eq(true)
            expect(ignored("")).eq(true)
            expect(ignored(nil)).eq(true)
        end)

        it("drops a bare Cmd by PATTERN, whichever name this client gives it", function()
            expect(ignored("META")).eq(true)
            expect(ignored("LMETA")).eq(true)
            expect(ignored("RMETA")).eq(true)
            expect(ignored("COMMAND"))
                .as("the probe meant to capture the exact token never fired, so the rule matches "
                    .. "the family. ElvUI's list has this hole and a bare Cmd can bind there")
                .eq(true)
        end)

        it("keeps a real key", function()
            expect(ignored("Q")).eq(false)
            expect(ignored("BUTTON4")).eq(false)
            expect(ignored("MOUSEWHEELUP")).eq(false)
        end)
    end)

    describe("mouse normalisation", function()
        it("maps the middle button to BUTTON3", function()
            expect(KB()._normalizeMouse("MiddleButton")).eq("BUTTON3")
        end)

        it("upper-cases the numbered buttons", function()
            expect(KB()._normalizeMouse("Button4")).eq("BUTTON4")
            expect(KB()._normalizeMouse("Button5")).eq("BUTTON5")
        end)

        it("passes left and right through, since they carry no digit", function()
            expect(KB()._normalizeMouse("LeftButton")).eq("LeftButton")
            expect(KB()._normalizeMouse("RightButton")).eq("RightButton")
        end)
    end)

    describe("writing a binding", function()
        it("writes the combination onto the hovered button's command", function()
            local b = openOn(1)
            KB().Arm(b)
            expect(KB().Capture(b, "Q")).eq(true)
            expect(H.env.GetBindingKey(b:GetBinding())).eq("Q")
        end)

        it("writes the MODIFIED combination, not the bare key", function()
            local b = openOn(1)
            KB().Arm(b)
            H.mods({ shift = true })
            KB().Capture(b, "Q")
            expect(H.env.GetBindingKey(b:GetBinding())).eq("SHIFT-Q")
        end)

        it("counts the change, so the panel can tell pending work from none", function()
            local b = openOn(1)
            H.SuuUI.KeybindMode:Discard()
            KB().Capture(b, "Q")
            expect(H.SuuUI.KeybindMode:ChangedCount())
                .as("the counter is MODE state, not bar state -- a second provider must add to the "
                    .. "same total rather than keep its own").eq(1)
            expect(H.SuuUI.KeybindMode:IsDirty()).truthy()
        end)

        it("writes straight away when the key is free", function()
            local b = openOn(1)
            expect(KB().Capture(b, "Q")).eq(true)
            expect(KB().PendingConflict())
                .as("an unowned key is not a conflict and must not ask").isNil()
        end)

        it("refuses in combat rather than attempting and checking", function()
            local b = openOn(1)
            H.setCombat(true)
            H.resetBlockedActions()

            expect(KB().Capture(b, "Q")).eq(false)
            expect(H.env.GetBindingKey(b:GetBinding())).isNil()

            -- THE LOAD-BEARING ASSERTION, and the one a "returns false" check cannot make. The
            -- client's SetBinding ALSO returns false in combat, so a version with no gate at all
            -- produces the identical return value -- FOUND BY MUTATION, which survived until this
            -- line existed. What separates them is whether the call HAPPENED: an attempt makes the
            -- client print "Interface action failed because of an AddOn" at the player, so the gate
            -- has to stop us reaching SetBinding, not merely handle its refusal.
            local blocked = H.getBlockedActions()
            local attempts = 0
            for _, rec in ipairs(blocked) do
                if rec.action == "SetBinding" then attempts = attempts + 1 end
            end
            expect(attempts).as("gated, not attempted").eq(0)
        end)

        it("ignores a bare modifier without touching the binding", function()
            H.setBinding("ACTIONBUTTON1", "1")
            local b = openOn(1)
            expect(KB().Capture(b, "LSHIFT")).eq(false)
            expect(H.env.GetBindingKey(b:GetBinding())).eq("1")
        end)
    end)

    describe("stealing a key someone else owns", function()
        it("asks instead of taking it", function()
            H.setBinding("ACTIONBUTTON1", "Q")
            local b1 = openOn(1)
            local b2 = button(2)

            expect(KB().Capture(b2, "Q"))
                .as("ElvUI takes it silently and its own gap analysis calls that its worst hole")
                .eq(false)
            expect(H.env.GetBindingKey(b1:GetBinding()))
                .as("the current owner keeps it until confirmed").eq("Q")
            expect(KB().PendingConflict().owner).eq("ACTIONBUTTON1")
        end)

        it("shows the pending state on the button being bound", function()
            H.setBinding("ACTIONBUTTON1", "Q")
            openOn(1)
            local b2 = button(2)
            KB().Capture(b2, "Q")
            expect(KB().OverlayFor(b2).state)
                .as("gold, the concept's colour for a write that has not landed").eq("pending")
        end)

        it("takes the key when the same combination is pressed again", function()
            H.setBinding("ACTIONBUTTON1", "Q")
            local b1 = openOn(1)
            local b2 = button(2)

            KB().Capture(b2, "Q")
            expect(KB().Capture(b2, "Q")).as("the second press IS the confirmation").eq(true)
            expect(H.env.GetBindingKey(b2:GetBinding())).eq("Q")
            expect(H.env.GetBindingKey(b1:GetBinding()))
                .as("a key belongs to exactly one command").isNil()
            expect(KB().OverlayFor(b1).chipText:GetText())
                .as("the button that LOST the key must stop advertising it -- repainting only the "
                    .. "hovered one leaves the same key visibly claimed twice").eq("")
            expect(KB().PendingConflict()).isNil()
        end)

        it("re-asks when a DIFFERENT contested key is pressed while one is pending", function()
            H.setBinding("ACTIONBUTTON1", "Q")
            H.setBinding("ACTIONBUTTON3", "R")
            openOn(1)
            local b2 = button(2)

            KB().Capture(b2, "Q")
            expect(KB().Capture(b2, "R"))
                .as("a second contested key is a new question, not a confirmation of the first")
                .eq(false)
            expect(KB().PendingConflict().combo).eq("R")
            expect(H.env.GetBindingKey("ACTIONBUTTON1")).as("Q was never taken").eq("Q")
        end)

        it("cancels when the pointer leaves the button", function()
            H.setBinding("ACTIONBUTTON1", "Q")
            openOn(1)
            local b2 = button(2)
            KB().Arm(b2)
            KB().Capture(b2, "Q")
            expect(KB().PendingConflict()).notNil()

            KB().Disarm(b2)
            expect(KB().PendingConflict())
                .as("ESC already means clear-all, so leaving is the cancel gesture").isNil()
            expect(H.env.GetBindingKey("ACTIONBUTTON1")).eq("Q")
        end)

        it("does not ask when the key is already on THIS button", function()
            H.setBinding("ACTIONBUTTON1", "Q")
            local b1 = openOn(1)
            expect(KB().Capture(b1, "Q"))
                .as("re-pressing a button's own key is not a steal from anyone").eq(true)
            expect(KB().PendingConflict()).isNil()
        end)

        it("names the owner the way the player sees it in the bindings UI", function()
            _G.BINDING_NAME_TOGGLEWORLDMAP = "World Map"
            expect(KB()._readableCommand("TOGGLEWORLDMAP"))
                .as("\"that key is in use\" without saying by WHAT leaves the player unable to "
                    .. "decide").eq("World Map")
            _G.BINDING_NAME_TOGGLEWORLDMAP = nil
            expect(KB()._readableCommand("SOMETHING_UNKNOWN"))
                .as("and an unresolvable name still beats saying nothing").eq("SOMETHING_UNKNOWN")
        end)

        it("treats both nil and the empty string as unowned", function()
            expect(KB()._ownerOf("Q"))
                .as("the client's documented answer is \"\", but that is the one thing here never "
                    .. "measured in game -- so the guard covers both rather than betting").isNil()
        end)
    end)

    describe("ESC clears the button", function()
        it("clears EVERY key, not just the first", function()
            H.setBinding("ACTIONBUTTON1", "1")
            H.addBinding("ACTIONBUTTON1", "CTRL-F9")
            H.addBinding("ACTIONBUTTON1", "BUTTON4")
            local b = openOn(1)

            expect(KB().Capture(b, "ESCAPE")).eq(true)
            expect(H.env.GetBindingKey(b:GetBinding()))
                .as("GetBindingKey is varargs and a command can hold several keys -- clearing only "
                    .. "the first leaves the button bound while reporting success").isNil()
        end)

        it("reports nothing to do on an already-unbound button", function()
            local b = openOn(1)
            expect(KB().Capture(b, "ESCAPE")).eq(false)
        end)

        it("is not swallowed by the ignore list", function()
            H.setBinding("ACTIONBUTTON1", "1")
            local b = openOn(1)
            KB().Capture(b, "ESCAPE")
            expect(H.env.GetBindingKey(b:GetBinding()))
                .as("ESCAPE is the clear GESTURE, checked before the ignore list").isNil()
        end)

        it("refuses in combat", function()
            H.setBinding("ACTIONBUTTON1", "1")
            local b = openOn(1)
            H.setCombat(true)
            H.resetBlockedActions()

            expect(KB().Capture(b, "ESCAPE")).eq(false)
            expect(H.env.GetBindingKey(b:GetBinding())).eq("1")

            -- Same reasoning as the write path: the gate must stop us CALLING SetBinding, because
            -- the attempt itself is what the player sees as an error.
            local attempts = 0
            for _, rec in ipairs(H.getBlockedActions()) do
                if rec.action == "SetBinding" then attempts = attempts + 1 end
            end
            expect(attempts).as("gated, not attempted").eq(0)
        end)
    end)

    describe("the corner hotkey", function()
        it("is hidden while the mode is open and given back on exit", function()
            local b = openOn(1)
            expect(b:IsShowingHotkey())
                .as("the chip replaces it -- the abbreviated key and the full one side by side is "
                    .. "two readings of one fact").falsy()
            H.SuuUI.KeybindMode:Disable()
            expect(b:IsShowingHotkey()).as("the mode borrowed it, it does not own it").truthy()
        end)
    end)
end)
