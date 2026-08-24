-- Plugins/WatchBars/WatchBars.lua
--
-- Experience and the watched faction's reputation. One widget shape, two instances.
--
-- The assertions that matter are the HIDE CONDITIONS and the reputation BAND MATHS. Both bars are
-- silent most of the time -- a max-level character has no experience bar and most characters watch no
-- faction -- so "shows when it should" and "is gone when it should" is the bulk of the behaviour.

local H = require("harness")

describe("Plugins.WatchBars", function()
    local PLUGIN = "watch_bars"
    local p, S

    before_each(function()
        H.setup()
        p = H.SuuUI.Plugins:Get(PLUGIN)
        S = H.SuuUI.Settings
    end)

    local function xp() return p._bars.xp end
    local function rep() return p._bars.rep end

    -- Read back what was actually PAINTED, not the props the bar was handed. The colour bugs here were
    -- all cases of a prop being accepted and ignored, so asserting against stored props would have
    -- confirmed the very thing that was wrong.
    local function fillColor(bar) return { bar._bar:GetColorTexture() } end
    local function secondaryColor(bar) return { bar._secTex:GetColorTexture() } end

    describe("the experience bar", function()
        it("shows the level's progress", function()
            H.setXP({ current = 400, max = 1000 })
            expect(xp():IsShown()).truthy()
            expect(xp():GetValue()).eq(400)
            expect(xp():GetPercent()).eq(0.4)
        end)

        it("HIDES at max level, which the client reports as a max of zero", function()
            H.setXP({ current = 0, max = 0 })
            expect(xp():IsShown()).falsy()
        end)

        it("HIDES when experience is switched off, which is a DIFFERENT reason", function()
            -- A trial account, or /xpoff. A bar that only checked the level would still show here --
            -- the character has a perfectly good max, they just are not earning.
            H.setXP({ current = 400, max = 1000, disabled = true })
            expect(xp():IsShown()).falsy()
        end)

        it("comes back when experience resumes", function()
            H.setXP({ current = 400, max = 1000, disabled = true })
            expect(xp():IsShown()).falsy()
            H.setXP({ disabled = false })
            expect(xp():IsShown()).truthy()
        end)

        describe("the rested ghost", function()
            it("reaches from current progress, not from zero", function()
                -- Rested experience extends from where you ARE. Drawn from zero it would claim the
                -- player has banked progress they have not earned.
                H.setXP({ current = 400, max = 1000, rested = 250 })
                expect(xp():GetSecondary()).eq(0.65)
            end)

            it("is ABSENT rather than empty when there is no bonus", function()
                -- nil and 0 are different readings from the client, and the difference is visible: a
                -- ghost of zero width still occupies the bar's first pixel.
                H.setXP({ current = 400, max = 1000, rested = 250 })
                H.setXP({ rested = false })
                expect(xp():GetSecondary()).eq(0)
                expect(xp()._secFrame:IsShown()).falsy()
            end)

            it("follows progress as it is earned", function()
                H.setXP({ current = 400, max = 1000, rested = 250 })
                local before = xp():GetSecondary()
                H.setXP({ current = 600 })
                expect(xp():GetSecondary() > before).as("the ghost moved with progress").truthy()
            end)
        end)
    end)

    describe("the reputation bar", function()
        it("HIDES when nothing is watched", function()
            expect(rep():IsShown()).falsy()
        end)

        it("shows the watched faction", function()
            H.setWatchedFaction({ name = "Argent Dawn", standing = 5, min = 0, max = 6000, value = 3000 })
            expect(rep():IsShown()).truthy()
            expect(rep():GetPercent()).eq(0.5)
        end)

        it("measures progress WITHIN the standing's band, not against its top", function()
            -- The client reports the band's own min and max. Using value against max directly would
            -- make every standing above Neutral look nearly full -- 4500 of 6000 is 75%, but inside
            -- the 3000-6000 band it is halfway.
            H.setWatchedFaction({ name = "Argent Dawn", standing = 6, min = 3000, max = 6000,
                value = 4500 })
            expect(rep():GetValue()).eq(1500)
            expect(rep():GetPercent()).eq(0.5)
        end)

        it("hides again when the faction is unwatched", function()
            H.setWatchedFaction({ name = "Argent Dawn", standing = 5, min = 0, max = 6000, value = 100 })
            expect(rep():IsShown()).truthy()
            H.setWatchedFaction(nil)
            expect(rep():IsShown()).falsy()
        end)

        it("takes the CLIENT's standing colour, not a theme token", function()
            -- The reputation bands are a game fact a player already knows by sight. Inventing our own
            -- palette for them would be worse than matching, and Core/Game.lua already maps standing
            -- onto the client's own table.
            H.setWatchedFaction({ name = "Argent Dawn", standing = 7, min = 0, max = 1000, value = 500 })
            local want = H.SuuUI.Game:ReactionColor(7)
            expect(want).as("the client has a colour for Exalted").notNil()
            local r, g, b = rep()._bar:GetColorTexture()
            expect({ r, g, b }).deepEq({ want[1], want[2], want[3] })
        end)

        it("recolours when the standing changes", function()
            H.setWatchedFaction({ name = "F", standing = 4, min = 0, max = 1000, value = 1 })
            local neutral = { rep()._bar:GetColorTexture() }
            H.setWatchedFaction({ name = "F", standing = 7, min = 0, max = 1000, value = 1 })
            local exalted = { rep()._bar:GetColorTexture() }
            expect(neutral[1] == exalted[1] and neutral[2] == exalted[2])
                .as("a different band reads as a different colour").falsy()
        end)

        it("draws a zero-span band FULL instead of hiding it", function()
            -- THIS TEST USED TO ASSERT THE OPPOSITE, and that is the lesson worth keeping: it demanded
            -- the bar hide when the band had no span, so it did not merely miss the defect -- it locked
            -- it in. A zero span happens at max standing, where the client reports the same number for
            -- the band's floor and its ceiling, and hiding there made an Exalted faction look identical
            -- to no faction at all.
            H.setWatchedFaction({ name = "F", standing = 8, min = 5000, max = 5000, value = 5000 })
            expect(rep():IsShown()).as("still on screen").truthy()
            expect(rep():GetPercent()).as("and full").eq(1)
        end)
    end)

    describe("the fill colour", function()
        it("is the XP token, not the component's white default", function()
            -- THE FIRST BUG THIS SHIPPED WITH. `fillColor` takes a literal {r,g,b,a}; the plugin passed
            -- a token KEY under the wrong prop name, so the bar silently stayed white.
            --
            -- The original spec compared the ghost against the main fill and passed -- because BOTH were
            -- white. Comparing two things that are wrong the same way proves nothing; this asserts the
            -- absolute value against the token.
            H.setXP({ current = 400, max = 1000 })
            H.expectTokenColor(fillColor(xp()), "colorXp")
        end)

        it("is NOT the accent, because blue means rested in WoW", function()
            -- THE SECOND BUG. Fixing the white default by reaching for colorAccent produced a BLUE
            -- experience bar, which any player reads as "you are rested" -- so the bar asserted a bonus
            -- the character did not have. Progress is purple; blue is spoken for.
            --
            -- Asserted as a real inequality against the accent rather than just "equals colorXp", so
            -- that pointing colorXp back at the accent in a theme cannot pass silently.
            H.setXP({ current = 400, max = 1000, rested = 0 })
            local acc = H.token("colorAccent")
            local f = fillColor(xp())
            expect(f[1] == acc[1] and f[2] == acc[2] and f[3] == acc[3])
                .as("progress must not be the accent blue").falsy()
        end)

        it("gives the rested region its own blue rather than a paler copy of the fill", function()
            -- A ghost derived from the fill is a paler PURPLE here, which reads as "more progress"
            -- rather than as rested. Rested is the one thing on this bar entitled to be blue.
            H.setXP({ current = 400, max = 1000, rested = 200 })
            H.expectTokenColor(secondaryColor(xp()), "colorXpRested")
            local f, s = fillColor(xp()), secondaryColor(xp())
            expect(f[3] == s[3]).as("rested is a different hue, not the same one faded").falsy()
        end)

        it("re-resolves both colours on a theme change", function()
            -- SWITCHES TO A THEME WITH DIFFERENT VALUES, rather than re-emitting the event on the same
            -- theme. Re-emitting proves nothing: the old literal and the new token value are identical,
            -- so a bar that never re-resolved would pass. `StatusBar` stores colours as LITERALS
            -- captured when they were set, so following a theme change is the plugin's job.
            H.setXP({ current = 400, max = 1000, rested = 200 })
            H.T:CreateUserTheme("GreenXp", "Modern")
            H.T:SetUserToken("GreenXp", "colorXp", { 0, 1, 0, 1 })
            H.T:SetUserToken("GreenXp", "colorXpRested", { 1, 0, 0, 1 })
            H.T:SetActive("GreenXp")
            local f, s = fillColor(xp()), secondaryColor(xp())
            expect({ f[1], f[2], f[3] }).as("fill followed").deepEq({ 0, 1, 0 })
            expect({ s[1], s[2], s[3] }).as("rested followed").deepEq({ 1, 0, 0 })
        end)

        it("draws no border by default", function()
            -- A hairline box around a 10px bar reads as a panel rather than a progress track.
            H.setXP({ current = 400, max = 1000 })
            expect(xp()._showBorder).falsy()
        end)
    end)

    describe("the reputation API shapes", function()
        -- THE BUG THAT MADE THE BAR INVISIBLE IN GAME. Every test here was absent, and the harness only
        -- ever modelled the legacy positional API, so 4051 passing tests could not see any of it.
        local WATCHED = { name = "Sporeggar", standing = 5, min = 3000, max = 6000, value = 4500 }

        it("reads the LEGACY positional API", function()
            H.setRepApi("legacy")
            H.setWatchedFaction(WATCHED)
            expect(rep():GetFrame():IsShown()).as("bar visible").truthy()
            expect(rep():GetMax()).eq(3000)
            expect(rep():GetValue()).as("offset into the band").eq(1500)
        end)

        it("reads the MODERN table API when that is what the client has", function()
            -- C_Reputation.GetWatchedFactionData returns a TABLE. The old code read positionally, so
            -- `name` came back as the table itself (truthy) with min/max/value all nil -- collapsing to
            -- a zero span and hiding the bar. This is the shape a modern backend actually presents, and
            -- ElvUI ships a shim for it on this very client.
            H.setRepApi("modern")
            H.setWatchedFaction(WATCHED)
            expect(rep():GetFrame():IsShown()).as("bar visible on the modern API too").truthy()
            expect(rep():GetMax()).eq(3000)
            expect(rep():GetValue()).eq(1500)
        end)

        it("hides quietly when nothing is watched, on either API", function()
            for _, mode in ipairs({ "legacy", "modern" }) do
                H.setRepApi(mode)
                H.setWatchedFaction(nil)
                expect(rep():GetFrame():IsShown()).as(mode .. ": nothing watched hides").falsy()
            end
        end)

        it("SURFACES A FAULT when neither API exists, instead of hiding silently", function()
            -- "No API" and "no faction watched" produce the same empty screen but are completely
            -- different problems, and only one of them is normal. Hiding silently on a missing API is
            -- what let this sit unnoticed, so a missing API now prints even with debug off.
            H.setRepApi("none")
            H.setWatchedFaction(WATCHED)
            local found = false
            for _, line in ipairs(H.debugLog()) do
                if line:find("reputation API", 1, true) then found = true end
            end
            expect(found).as("a fault was surfaced").truthy()
            expect(rep():GetFrame():IsShown()).as("and the bar is still hidden").falsy()
        end)

        it("draws FULL at max standing rather than vanishing", function()
            -- At the top standing the client reports the same number for the band's floor and ceiling,
            -- so the span is zero. The old guard returned nil on that and hid the bar, which made an
            -- Exalted faction look exactly like no faction at all. ElvUI forces the floor to 0 for the
            -- same reason.
            H.setRepApi("legacy")
            H.setWatchedFaction({ name = "Sporeggar", standing = 7, min = 42000, max = 42000, value = 42000 })
            expect(rep():GetFrame():IsShown()).as("Exalted still shows").truthy()
            expect(rep():GetPercent()).as("and reads full").eq(1)
        end)

        it("says the standing rather than a meaningless ratio when capped", function()
            H.setRepApi("legacy")
            H.setWatchedFaction({ name = "Sporeggar", standing = 7, min = 42000, max = 42000, value = 42000 })
            local W = H.SuuUI._WatchBars
            local r = W.readRep()
            expect(r.capped).truthy()
            expect(W.READOUTS.current_max(r)).as("no '1 / 1'").eq("")
            expect(W.READOUTS.remaining(r)).as("nothing left to earn").eq("")
        end)

        it("treats a reaction of 0 as the first standing, not as a nil lookup", function()
            H.setRepApi("legacy")
            H.setWatchedFaction({ name = "Odd", standing = 0, min = 0, max = 100, value = 50 })
            expect(H.SuuUI._WatchBars.readRep().standing).eq(1)
        end)
    end)

    describe("live geometry settings", function()
        -- REPORTED FROM THE GAME: the width and height sliders "don't do anything and only take effect
        -- after a reload". They had no watcher at all -- the values were read once in buildBar, so the
        -- only thing that applied them was rebuilding the bar. A setting that appears to be ignored is
        -- worse than a missing one, because the player concludes the feature is broken.
        local function setXpAnd(k, v)
            H.setXP({ current = 230, max = 1000 })
            H.SuuUI.Settings:Set("watch_bars", "xp_" .. k, v)
        end

        it("applies a width change immediately", function()
            setXpAnd("width", 700)
            expect(xp():GetWidth()).eq(700)
        end)

        it("applies a height change immediately", function()
            setXpAnd("height", 24)
            expect(xp():GetHeight()).eq(24)
        end)

        it("toggles the border immediately", function()
            setXpAnd("border", true)
            expect(xp()._showBorder).as("on").truthy()
            H.SuuUI.Settings:Set("watch_bars", "xp_border", false)
            expect(xp()._showBorder).as("and off again").falsy()
        end)

        it("REPAINTS the fill to the new width, not just the frame", function()
            -- Kept as an integration guard even though the plugin does not do the repainting: the fill
            -- is quantised to whole pixels against the bar's width, and StatusBar's OWN OnSizeChanged
            -- clears the pixel caches and re-asserts the fraction. This asserts the two halves stay
            -- wired together -- a plugin that resized some other way, or a component that stopped
            -- re-asserting, would both leave the fill at its old pixel width.
            setXpAnd("width", 700)
            local pct = xp():GetPercent()
            expect(pct > 0).as("there is something to draw").truthy()
            local want = math.floor(700 * pct + 0.5)
            expect(math.abs(xp()._bar:GetWidth() - want) <= 1)
                .as("fill followed the resize (got " .. tostring(xp()._bar:GetWidth())
                    .. ", wanted ~" .. tostring(want) .. ")")
                .truthy()
        end)

        it("resizes IN PLACE rather than rebuilding the bar", function()
            -- A rebuild would drop the bar's moveable registration and reset its stored position, so a
            -- resize would move the bar as a side effect. Identity is the cheapest proof that did not
            -- happen.
            setXpAnd("width", 600)
            local before = xp()
            H.SuuUI.Settings:Set("watch_bars", "xp_width", 800)
            expect(xp()).as("same handle").eq(before)
            expect(xp():GetWidth()).eq(800)
        end)
    end)

    describe("docking", function()
        -- The watch bars use the SAME Core/Dock service the action bars do. The dock needed no change
        -- to accept them: it only ever asks a participant for GetFrame, GetWidth/GetHeight and a
        -- SIZE_CHANGED signal, all of which a StatusBar handle already had.
        -- A FUNCTION, not a captured value: a describe body runs when the file is declared, before
        -- H.setup() has built the addon, so H.SuuUI is still nil at that point.
        local function D() return H.SuuUI.Dock end
        local function ab(id) return H.SuuUI.Plugins:Get("action_bars")._bars[id] end
        local function enableBar(id)
            H.SuuUI.Settings:Set("action_bars", "bar" .. id .. "_enabled", true)
        end

        it("lists the options in a stable, natural order", function()
            -- table.sort is NOT stable in Lua, and the action bars carry no explicit order -- so all
            -- eight tied and the dropdown came out "Bar 4, Bar 6, Bar 5, Bar 2...". Registration order
            -- is the final tiebreaker now. Asserted as an exact sequence because "looks about right"
            -- is what let the jumble ship.
            local labels = {}
            for _, o in ipairs(D().OptionsFor("watch:xp")) do labels[#labels + 1] = o.label end
            expect(labels).deepEq({
                "Free", "Bar 1", "Bar 2", "Bar 3", "Bar 4", "Bar 5", "Bar 6", "Bar 7", "Bar 8",
                "Pet", "Stance", "Reputation",
            })
        end)

        it("labels the options WITHOUT a group prefix, and keeps them unique", function()
            -- REPORTED FROM THE GAME: prefixing the group produced eight rows of "Action Bars: Ba..."
            -- in a 140px dropdown -- every entry truncated to the same string. The prefix was meant to
            -- disambiguate and instead made every option identical.
            --
            -- Uniqueness is what makes the prefix unnecessary, so it is asserted here rather than
            -- trusted: a new participant whose label collides fails THIS test and gets a better name,
            -- instead of every label carrying a prefix to cover a collision that does not exist.
            local opts = D().OptionsFor("watch:xp")
            local seen = {}
            for _, o in ipairs(opts) do
                expect(o.label:find(":", 1, true)).as(o.label .. " carries no group prefix").isNil()
                expect(seen[o.label]).as("label '" .. o.label .. "' is not a duplicate").isNil()
                seen[o.label] = true
                -- Long enough to truncate at the control's width is a rendering bug waiting to happen.
                expect(#o.label <= 16).as("'" .. o.label .. "' fits the dropdown").truthy()
            end
            expect(seen["Free"]).as("Free is offered").truthy()
            expect(seen["Experience"]).as("its own label is excluded").isNil()
        end)

        it("registers both bars as participants under their own group", function()
            local byId = {}
            for _, e in ipairs(D().Participants()) do byId[e.id] = e.spec end
            expect(byId["watch:xp"]).as("xp registered").notNil()
            expect(byId["watch:rep"]).as("rep registered").notNil()
            expect(byId["watch:xp"].group).eq("Watch Bars")
            -- NAMESPACED, unlike the action bars' plain ids. Those were already in player profiles
            -- before a second group existed, so they keep what they had.
            expect(byId["1"]).as("action bar ids stay plain").notNil()
        end)

        it("attaches the XP bar to an action bar", function()
            H.setXP({ current = 230, max = 1000 })
            enableBar(1)
            H.SuuUI.Settings:Set("watch_bars", "xp_attach_edge", "below")
            H.SuuUI.Settings:Set("watch_bars", "xp_attach", "1")
            expect(D().ParentOf(xp())).eq(ab(1))
            expect(D().EdgeOf(xp())).eq("below")
        end)

        it("takes the drag handle away while docked and gives it back on release", function()
            -- Two things writing one anchor is the failure to avoid: while docked the dock owns the
            -- frame's point, so a moveable left switched on would fight it and the winner would depend
            -- on which wrote last.
            H.setXP({ current = 230, max = 1000 })
            enableBar(1)
            H.SuuUI.Settings:Set("watch_bars", "xp_attach", "1")
            expect(xp():GetFrame()._suuui_moveable).as("not draggable while docked").isNil()
            H.SuuUI.Settings:Set("watch_bars", "xp_attach", "detached")
            expect(xp():GetFrame()._suuui_moveable).as("draggable again once free").notNil()
            expect(D().ParentOf(xp())).as("and off the dock").isNil()
        end)

        it("lets an ACTION BAR attach to a watch bar -- the reverse direction", function()
            -- This failed at first, and the reason is worth keeping: ActionBars built the target's
            -- attach point name from its OWN prefix, so a watch-bar target became
            -- "actionbar.dock.watch:xp" -- a point that never existed. Request's "not published yet"
            -- path looks exactly like that, so it failed silently. Both plugins resolve the name
            -- through Dock.PointFor now.
            H.setXP({ current = 230, max = 1000 })
            enableBar(2)
            H.SuuUI.Settings:Set("action_bars", "bar2_attach_edge", "above")
            H.SuuUI.Settings:Set("action_bars", "bar2_attach", "watch:xp")
            expect(D().ParentOf(ab(2))).as("docked to the XP bar").eq(xp())
            expect(D().EdgeOf(ab(2))).eq("above")
        end)

        it("REFUSES a cycle that runs through two plugins", function()
            -- Neither plugin can see this alone: bar 2 is attached to the XP bar in ActionBars'
            -- settings, and the XP bar would be attached to bar 2 in WatchBars'. Each holds one half.
            H.setXP({ current = 230, max = 1000 })
            enableBar(2)
            H.SuuUI.Settings:Set("action_bars", "bar2_attach", "watch:xp")
            H.SuuUI.Settings:Set("watch_bars", "xp_attach", "2")
            expect(H.SuuUI.Settings:Get("watch_bars", "xp_attach"))
                .as("the cycle never reached the profile").eq("detached")
            expect(D().WouldCycleIds("watch:xp", "2")).truthy()
        end)

        it("allows a legal chain across plugins", function()
            H.setXP({ current = 230, max = 1000 })
            H.setWatchedFaction({ name = "F", standing = 5, min = 3000, max = 6000, value = 4500 })
            enableBar(1)
            H.SuuUI.Settings:Set("watch_bars", "rep_attach", "watch:xp")
            H.SuuUI.Settings:Set("watch_bars", "xp_attach", "1")
            expect(D().ParentOf(rep())).as("rep on xp").eq(xp())
            expect(D().ParentOf(xp())).as("xp on bar 1").eq(ab(1))
        end)

        it("defers the whole transition in combat and catches up on leaving it", function()
            -- An anchor is the same dependency as parentage: if this bar is a dock for an action bar,
            -- moving it would move protected buttons and the client refuses that mid-fight. Rather
            -- than reason about which direction is safe, the transition waits.
            H.setXP({ current = 230, max = 1000 })
            enableBar(1)
            H.setCombat(true)
            H.SuuUI.Settings:Set("watch_bars", "xp_attach", "1")
            expect(D().ParentOf(xp())).as("nothing moved in combat").isNil()
            H.setCombat(false)
            H.fireEvent("PLAYER_REGEN_ENABLED")
            expect(D().ParentOf(xp())).as("applied on leaving combat").eq(ab(1))
        end)

        it("gives up its dock membership when the bar is switched off", function()
            H.setXP({ current = 230, max = 1000 })
            enableBar(1)
            H.SuuUI.Settings:Set("watch_bars", "xp_attach", "1")
            local held = xp()
            H.SuuUI.Settings:Set("watch_bars", "xp_enabled", false)
            expect(D().ParentOf(held)).as("no longer anchored to anything").isNil()
        end)
    end)

    describe("readout slots", function()
        it("defaults to a percent in the centre and nothing either side", function()
            H.setXP({ current = 250, max = 1000 })
            expect(xp():GetText("center")).eq("25%")
            expect(xp():GetText("left") or "").eq("")
            expect(xp():GetText("right") or "").eq("")
        end)

        it("offers current-max, remaining and the rested bonus on the XP bar", function()
            H.setXP({ current = 400, max = 1000, rested = 250 })
            S:Set(PLUGIN, "xp_slot_left", "current_max")
            expect(xp():GetText("left")).eq("400 / 1000")
            S:Set(PLUGIN, "xp_slot_left", "remaining")
            expect(xp():GetText("left")).eq("600")
            S:Set(PLUGIN, "xp_slot_left", "rested")
            expect(xp():GetText("left")).eq("+250")
        end)

        it("leaves the rested readout BLANK rather than showing a zero", function()
            -- "0" would read as "you have no rested experience left", which is a different statement
            -- from "resting is not a factor right now".
            H.setXP({ current = 400, max = 1000 })
            S:Set(PLUGIN, "xp_slot_left", "rested")
            expect(xp():GetText("left") or "").as("no bonus at all").eq("")

            -- And a bonus of exactly ZERO, which is a different reading from nil and takes a
            -- different branch. Without this the `<= 0` half of the guard is untested and a mutant
            -- rendering "+0" passes.
            H.setXP({ current = 400, max = 1000, rested = 0 })
            expect(xp():GetText("left") or "").as("a bonus of zero is still nothing").eq("")
        end)

        it("offers the faction name and standing on the REP bar", function()
            H.setWatchedFaction({ name = "Argent Dawn", standing = 6, min = 0, max = 1000, value = 1 })
            S:Set(PLUGIN, "rep_slot_left", "faction")
            S:Set(PLUGIN, "rep_slot_right", "standing")
            expect(rep():GetText("left")).eq("Argent Dawn")
            expect(rep():GetText("right")).eq("Revered")
        end)

        it("does NOT offer experience-only readouts on the reputation tab", function()
            -- A slot that reads as broken half the time is worse than one fewer option: `rested` has
            -- no meaning for a faction, and `faction` has none for a level.
            local function optionsFor(barId, slot)
                for _, e in ipairs(S:GetSchema(PLUGIN)) do
                    if e.type == "subtabs" then
                        for _, tab in ipairs(e.tabs) do
                            if tab.id == barId then
                                for _, entry in ipairs(tab.schema) do
                                    if entry.key == barId .. "_slot_" .. slot then
                                        local set = {}
                                        for _, o in ipairs(entry.options) do set[o.value] = true end
                                        return set
                                    end
                                end
                            end
                        end
                    end
                end
            end
            local repOpts, xpOpts = optionsFor("rep", "left"), optionsFor("xp", "left")
            expect(repOpts).notNil()
            expect(repOpts.rested).as("no rested bonus on a faction").falsy()
            expect(repOpts.faction).as("but a faction name").truthy()
            expect(xpOpts.faction).as("and no faction on the XP bar").falsy()
            expect(xpOpts.rested).truthy()
        end)

        it("repaints without rebuilding when a slot changes", function()
            H.setXP({ current = 400, max = 1000 })
            local before = xp()
            S:Set(PLUGIN, "xp_slot_right", "percent")
            expect(p._bars.xp).as("same bar, new text").eq(before)
            expect(xp():GetText("right")).eq("40%")
        end)
    end)

    describe("as bars", function()
        it("gives each one its own moveable frame", function()
            H.setXP({ current = 1, max = 100 })
            expect(xp():GetFrame()._suuui_moveable).notNil()
        end)

        it("tears both down when the plugin is switched off", function()
            H.setXP({ current = 1, max = 100 })
            expect(p._bars.xp).notNil()
            S:Set(PLUGIN, "enabled", false)
            expect(p._bars.xp).isNil()
            expect(p._bars.rep).isNil()
        end)

        it("can switch off ONE bar and keep the other", function()
            H.setXP({ current = 1, max = 100 })
            S:Set(PLUGIN, "rep_enabled", false)
            expect(p._bars.rep).isNil()
            expect(p._bars.xp).as("the other is untouched").notNil()
        end)
    end)
end)
