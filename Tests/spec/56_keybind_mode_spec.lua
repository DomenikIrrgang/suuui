-- Keybind mode: the mode's STATE only. Overlays, capture and the panel are later phases.
local H = require("harness")

describe("keybind mode", function()
    before_each(function() H.setup() end)

    local function KB() return H.SuuUI.KeybindMode end
    local function editMode() return H.SuuUI.ToggleUI end

    describe("state", function()
        it("starts inactive", function()
            expect(KB():IsActive()).eq(false)
        end)

        it("reads through the setting rather than a shadow variable", function()
            H.SuuUI.Settings:Set("_layout", "keybind_mode", true)
            expect(KB():IsActive())
                .as("the slash command, the settings toggle and the panel all write this one key, "
                    .. "so a local copy is the thing that lets them disagree").eq(true)
        end)

        it("Enable and Disable move the setting", function()
            expect(KB():Enable()).eq(true)
            expect(H.SuuUI.Settings:Get("_layout", "keybind_mode")).eq(true)
            KB():Disable()
            expect(H.SuuUI.Settings:Get("_layout", "keybind_mode")).eq(false)
        end)

        it("Toggle reports the state it arrived at", function()
            expect(KB():Toggle()).as("opened").eq(true)
            expect(KB():Toggle()).as("closed").eq(false)
        end)

        it("is transient, so it is never written to the profile", function()
            KB():Enable()
            local schema = H.SuuUI.Settings:GetSchema("_layout")
            local found
            for _, entry in ipairs(schema) do
                if entry.key == "keybind_mode" then found = entry end
            end
            expect(found).as("the key is declared beside edit_mode").truthy()
            expect(found.transient)
                .as("a mode the player is CURRENTLY IN, not a preference -- persisting it would "
                    .. "log them back in hovering a live binder").truthy()
        end)
    end)

    describe("combat", function()
        it("refuses to open", function()
            H.setCombat(true)
            expect(KB():Enable())
                .as("SetBinding returns false in combat AND the client prints an interface-action "
                    .. "error, so a mode that opened anyway would look live and bind nothing")
                .eq(false)
            expect(KB():IsActive()).eq(false)
        end)

        it("refuses through Toggle too, not just Enable", function()
            H.setCombat(true)
            expect(KB():Toggle()).eq(false)
            expect(KB():IsActive())
                .as("the slash command goes through Toggle, so a gate only on Enable would leave "
                    .. "the command itself unguarded").eq(false)
        end)

        it("still closes in combat", function()
            KB():Enable()
            H.setCombat(true)
            KB():Disable()
            expect(KB():IsActive())
                .as("leaving is always allowed -- it writes no binding").eq(false)
        end)

        it("opens again once combat ends", function()
            H.setCombat(true)
            KB():Enable()
            H.setCombat(false)
            expect(KB():Enable()).eq(true)
        end)
    end)

    describe("mutual exclusion with edit mode", function()
        -- ASSERTED AS A PAIR ON PURPOSE. Narrowing the exclusion to one direction is the mutation
        -- that matters: MoveableFrame's overlays sit at host+5 with mouse enabled, so whichever
        -- mode was left open would stack its overlay on the same frames as the other.
        it("closes edit mode when keybind mode opens", function()
            editMode():Enable()
            expect(editMode():IsEditMode()).eq(true)
            KB():Enable()
            expect(editMode():IsEditMode()).as("edit mode gave way").eq(false)
            expect(KB():IsActive()).eq(true)
        end)

        it("closes keybind mode when edit mode opens", function()
            KB():Enable()
            expect(KB():IsActive()).eq(true)
            editMode():Enable()
            expect(KB():IsActive()).as("keybind mode gave way").eq(false)
            expect(editMode():IsEditMode()).eq(true)
        end)

        it("never leaves both active, whichever order they are opened in", function()
            editMode():Enable()
            KB():Enable()
            expect(editMode():IsEditMode() and KB():IsActive()).eq(false)

            KB():Disable()
            editMode():Disable()
            KB():Enable()
            editMode():Enable()
            expect(editMode():IsEditMode() and KB():IsActive()).eq(false)
        end)

        it("does not disturb edit mode when keybind mode merely closes", function()
            editMode():Enable()
            KB():Disable()
            expect(editMode():IsEditMode())
                .as("only OPENING excludes; a close must not reach across").eq(true)
        end)
    end)

    describe("the provider registry", function()
        -- The real bars register a provider named "action_bars" at load, so these assertions drop
        -- it first and measure the registry's OWN mechanics. The spec below pins that it is there.
        before_each(function() KB():UnregisterProvider("action_bars") end)

        it("has the action bars registered as a provider out of the box", function()
            H.setup()
            local found = false
            KB():RegisterProvider("probe", function()
                found = true
                return {}
            end)
            expect(#KB():GetButtons() > 0)
                .as("ActionBars wires itself in at load, so the mode reaches real buttons without "
                    .. "anything else having to introduce them").eq(true)
            expect(found).as("and every provider is consulted, not just the first").eq(true)
        end)

        it("collects buttons from every provider", function()
            KB():RegisterProvider("a", function() return { "b1", "b2" } end)
            KB():RegisterProvider("b", function() return { "b3" } end)
            expect(#KB():GetButtons()).eq(3)
        end)

        it("replaces a provider registered under the same id", function()
            KB():RegisterProvider("a", function() return { "b1", "b2" } end)
            KB():RegisterProvider("a", function() return { "only" } end)
            local list = KB():GetButtons()
            expect(#list).as("re-registering must not duplicate").eq(1)
            expect(list[1]).eq("only")
        end)

        it("drops a provider on unregister", function()
            KB():RegisterProvider("a", function() return { "b1" } end)
            KB():UnregisterProvider("a")
            expect(#KB():GetButtons()).eq(0)
        end)

        it("tolerates a provider with nothing to offer", function()
            KB():RegisterProvider("empty", function() return {} end)
            KB():RegisterProvider("nothing", function() return nil end)
            KB():RegisterProvider("real", function() return { "b1" } end)
            expect(#KB():GetButtons())
                .as("SuuUIBarstanceButton1 was measured NIL on the reference character -- a class "
                    .. "with no stance bar is a normal state, not a fault").eq(1)
        end)

        it("refuses a registration it cannot use", function()
            expect(pcall(function() KB():RegisterProvider("", function() end) end)).eq(false)
            expect(pcall(function() KB():RegisterProvider("x", nil) end)).eq(false)
        end)
    end)
end)
