-- Plugins/DataBar/MicroMenuWidget.lua
--
-- The micro menu moved into the data bar: one field per entry in the `left` section, each a glyph
-- from Media/micro-icons.tga with an optional label.
--
-- The assertions that carry weight are about RESOLUTION and DEFAULTS, not appearance. This client is
-- a hybrid -- `MICRO_BUTTONS` is nil and `LFDMicroButton` is absent while `LFGMicroButton` exists --
-- so an entry that resolves nothing must be skipped rather than rendered as a glyph that does
-- nothing when clicked.

local H = require("harness")

describe("Plugins.DataBar: the micro menu", function()
    local PLUGIN = "data_bar"
    local M, S, DB

    before_each(function()
        H.setup()
        M = H.SuuUI._DataBar.MicroMenu
        S = H.SuuUI.Settings
        DB = H.SuuUI.DataBar
    end)

    local function shown()
        local out = {}
        for i, id in ipairs(M.Registered()) do out[i] = id:gsub("^micro_", "") end
        return out
    end

    local function entryFor(glyph)
        for _, e in ipairs(M.ENTRIES) do
            if e.glyph == glyph then return e end
        end
    end

    describe("what shows by default", function()
        it("shows exactly the five asked for, in order", function()
            -- Character, spellbook, quests, options, help. Fourteen glyphs is more menu than most
            -- players use, so the rest ship off rather than absent.
            expect(shown()).deepEq({ "char", "spells", "quests", "menu", "help" })
        end)

        it("keeps GUILD off, because a dedicated guild widget is coming", function()
            -- Two things opening the same panel from the same bar would be one too many. The toggle
            -- stays for anyone who prefers the glyph.
            expect(entryFor("guild").default).falsy()
            expect(DB:GetWidget("micro_guild")).isNil()
        end)

        it("has NO collections entry at all, since TBC has no collections", function()
            -- Not merely off: a toggle for a button that is never coming reads as a broken setting.
            expect(entryFor("collections")).isNil()
        end)

        it("keeps the collections GLYPH in the atlas, because the order is a contract", function()
            -- Renumbering the sheet would silently re-point every coord after it -- bags and keys sit
            -- past collections. The unused cell costs nothing.
            expect(M.COORDS.collections).notNil()
        end)
    end)

    describe("per-entry toggles", function()
        it("adds an entry when its toggle goes on", function()
            S:Set(PLUGIN, "micro_show_guild", true)
            expect(shown()).contains("guild")
            expect(DB:GetWidget("micro_guild")).notNil()
        end)

        it("removes an entry when its toggle goes off", function()
            S:Set(PLUGIN, "micro_show_char", false)
            local ids = shown()
            local found = false
            for _, g in ipairs(ids) do if g == "char" then found = true end end
            expect(found).falsy()
            expect(DB:GetWidget("micro_char")).isNil()
        end)

        it("gives a re-enabled entry back its OWN position, not the end of the strip", function()
            -- Order is a property of the entry, not of the order it happened to be switched on. A
            -- player toggling quests off and on again must not have it jump to the end.
            local before = M.ENTRIES
            local wantOrder
            for _, e in ipairs(before) do
                if e.glyph == "quests" then wantOrder = true end
            end
            expect(wantOrder).truthy()

            local original = DB:GetWidget("micro_quests").order
            S:Set(PLUGIN, "micro_show_quests", false)
            S:Set(PLUGIN, "micro_show_quests", true)
            expect(DB:GetWidget("micro_quests").order).eq(original)

            -- And every shown entry has a DISTINCT, increasing order. Without this, an
            -- implementation that gave them all the same number would satisfy the check above --
            -- which is what mutation testing found.
            local last = -1
            for _, id in ipairs(M.Registered()) do
                local o = DB:GetWidget(id).order
                expect(o > last).as(id .. " order " .. tostring(o) .. " follows " .. tostring(last))
                    .truthy()
                last = o
            end
        end)

        it("puts every field in the LEFT section, which nothing else occupies", function()
            for _, id in ipairs(M.Registered()) do
                expect(DB:GetWidget(id).section).eq("left")
            end
        end)
    end)

    describe("labels", function()
        it("shows them by default, as the entry's name", function()
            expect(S:Get(PLUGIN, "micro_show_labels")).truthy()
            expect(DB:GetWidget("micro_char").GetText()).eq("Character")
        end)

        it("collapses to the glyph alone when switched off", function()
            S:Set(PLUGIN, "micro_show_labels", false)
            expect(DB:GetWidget("micro_char").GetText()).eq("")
        end)

        it("comes back when switched on again", function()
            S:Set(PLUGIN, "micro_show_labels", false)
            S:Set(PLUGIN, "micro_show_labels", true)
            expect(DB:GetWidget("micro_char").GetText()).eq("Character")
        end)

        it("RE-REGISTERS the fields, because the change alters their width", function()
            -- Not just their text. An icon-only field hugs to icon plus spaceMd either side; with a
            -- label it hugs to icon, gap, text. The field has to be rebuilt and the section reflowed,
            -- so a labels change replaces each widget rather than only re-reading GetText.
            -- Observed by counting registrations rather than by comparing the def object: the same
            -- def table is re-registered, so the object is identical either way. What matters is that
            -- the registry was told again, which is what makes the bar rebuild the field.
            local reRegistered = 0
            local realRegister = DB.RegisterWidget
            DB.RegisterWidget = function(self, def)
                if def.id == "micro_char" then reRegistered = reRegistered + 1 end
                return realRegister(self, def)
            end
            S:Set(PLUGIN, "micro_show_labels", false)
            DB.RegisterWidget = realRegister
            expect(reRegistered).as("the field was rebuilt, not just re-texted").eq(1)
        end)

        it("suppresses the tooltip while the label is visible", function()
            -- A tooltip repeating a label the player can already read is noise, and it covers the bar
            -- to do it. Observed by counting Tooltip CONSTRUCTIONS -- asserting OnEnter merely does
            -- not throw proves nothing, which mutation testing pointed out.
            local made = 0
            local real = H.C.Tooltip
            H.C.Tooltip = function(props, parent) made = made + 1 return real(props, parent) end
            local fakeField = { GetFrame = function() return H.env.UIParent end }

            DB:GetWidget("micro_char").OnEnter(fakeField)
            expect(made).as("labels on -- no tooltip").eq(0)

            S:Set(PLUGIN, "micro_show_labels", false)
            DB:GetWidget("micro_char").OnEnter(fakeField)
            H.C.Tooltip = real
            expect(made).as("labels off -- the name has to come from somewhere").eq(1)
        end)
    end)

    describe("resolution against a hybrid client", function()
        it("prefers LFGMicroButton, which is the one that exists here", function()
            -- LFD and LFG differ by one letter and only one of them exists on this client -- exactly
            -- the case a literal frame name would get wrong.
            expect(H.env.LFGMicroButton).notNil()
            expect(H.env.LFDMicroButton).as("absent on this build").isNil()
            S:Set(PLUGIN, "micro_show_lfg", true)
            expect(DB:GetWidget("micro_lfg")).notNil()
        end)

        it("falls through to a LATER candidate when the first is missing", function()
            -- The point of a candidate LIST rather than a pair of names. With only the first tried,
            -- a client that ships LFD instead of LFG loses the entry -- and every existing entry here
            -- happens to resolve on its first name, so nothing else would catch it.
            H.env.LFGMicroButton = nil
            H.env.LFDMicroButton = H.env.CreateFrame("Button", "LFDMicroButton", H.env.UIParent)
            M.Disable()
            M.Enable()
            S:Set(PLUGIN, "micro_show_lfg", true)
            expect(DB:GetWidget("micro_lfg")).as("resolved on the second candidate").notNil()
        end)

        it("SKIPS an entry whose panel ACTION does not exist", function()
            -- Keys resolves a button but this client has no ToggleKeyRing, so the entry must not
            -- render. Two separate conditions: the frame says the feature exists, the function says
            -- we can trigger it -- and a field that cannot act looks like a working control.
            expect(H.env.KeyRingButton).as("the button is there").notNil()
            expect(H.env.ToggleKeyRing).as("but the action is not").isNil()
            local found = false
            for _, g in ipairs(shown()) do if g == "keys" then found = true end end
            expect(found).falsy()
            S:Set(PLUGIN, "micro_show_keys", true)
            expect(DB:GetWidget("micro_keys")).as("not even when switched on").isNil()
        end)

        it("SKIPS an entry whose candidates all fail to resolve", function()
            -- A glyph the player can click that does nothing is worse than no glyph.
            -- The widget is the unit here, so it is cycled directly rather than through the plugin.
            H.env.QuestLogMicroButton = nil
            M.Disable()
            M.Enable()
            local found = false
            for _, g in ipairs(shown()) do if g == "quests" then found = true end end
            expect(found).as("no button, no field").falsy()
        end)

        it("offers a toggle ONLY for entries that resolve", function()
            -- A switch for something this client does not have is a promise the UI cannot keep.
            local keys = {}
            for _, e in ipairs(M.Schema()) do keys[e.key] = true end
            expect(keys["micro_show_char"]).truthy()

            -- An entry that IS in the table but whose button is gone must lose its toggle too.
            -- Asserting only that a NON-EXISTENT entry has no key proves nothing, because it has no
            -- key either way.
            H.env.HelpMicroButton = nil
            local after = {}
            for _, e in ipairs(M.Schema()) do after[e.key] = true end
            expect(after["micro_show_help"]).as("no button, no switch").falsy()
            expect(after["micro_show_char"]).as("the others are untouched").truthy()
        end)
    end)

    describe("clicking", function()
        -- Reaches the rendered FIELD rather than calling def.OnClick directly. Calling the hook by
        -- hand skips the field, the CLICKED signal and the bar's wiring -- so it can pass while a
        -- player clicking the glyph gets nothing, which is exactly what happened.
        local function clickField(id)
            local bar = H.SuuUI.Plugins:Get(PLUGIN)._bar
            local recs
            for _, n in ipairs({ "_records", "_fields", "_widgets" }) do
                if bar[n] then recs = bar[n] end
            end
            for _, rec in pairs(recs or {}) do
                if rec.def and rec.def.id == id and rec.field then
                    rec.field:GetFrame():_fire("OnMouseUp", "LeftButton")
                    return true
                end
            end
            return false
        end

        it("opens the panel from a real click on the FIELD", function()
            expect(clickField("micro_char")).as("the field was found and clicked").truthy()
            local t = H.getPanelToggles()
            expect(#t).eq(1)
            expect(t[1].name).eq("ToggleCharacter")
            expect(t[1].arg).as("the pane it should land on").eq("PaperDollFrame")
        end)

        it("does NOT try to click Blizzard's button, which has no OnClick on this client", function()
            -- Measured: CharacterMicroButton:GetScript("OnClick") is nil, so Click() is a silent
            -- no-op. This is pinned so a future "just forward the click" simplification fails here
            -- rather than in game.
            clickField("micro_char")
            expect(H.getMicroClicks()).as("no forwarding attempted").len(0)
        end)

        it("takes the mouse, or a click never arrives", function()
            local bar = H.SuuUI.Plugins:Get(PLUGIN)._bar
            local recs
            for _, n in ipairs({ "_records", "_fields", "_widgets" }) do
                if bar[n] then recs = bar[n] end
            end
            for _, rec in pairs(recs or {}) do
                if rec.def and rec.def.id == "micro_char" and rec.field then
                    local f = rec.field:GetFrame()
                    expect(f._mouseEnabled).as("mouse enabled").truthy()
                    expect(f:GetScript("OnMouseUp")).as("wired to a click handler").notNil()
                end
            end
        end)

        it("calls each entry's OWN panel action", function()
            DB:GetWidget("micro_help").OnClick()
            expect(H.getPanelToggles()[1].name).eq("ToggleHelpFrame")
        end)

        it("stays silent if the action disappears after registration", function()
            -- Guarded at call time as well as at registration: a Lua error popup on click is worse
            -- than a button that does nothing, and a client can drop a global between login and the
            -- click.
            H.env.ToggleHelpFrame = nil
            expect(function() DB:GetWidget("micro_help").OnClick() end).notThrows()
        end)
    end)

    it("draws every field from the atlas, one cell each", function()
        for _, id in ipairs(M.Registered()) do
            local def = DB:GetWidget(id)
            expect(def.icon).eq(M.ATLAS)
            expect(def.iconCoords).as(id .. " has a coord tuple").notNil()
            expect(#def.iconCoords).eq(4)
        end
    end)
end)
