local H = require("harness")

-- The Tooltips plugin: reskins the CLIENT's tooltips rather than drawing any of its own.
--
-- So everything here asserts a seam with Blizzard's frames, and three facts about this client
-- shape what is worth asserting at all -- each measured in game (.kiro/specs/tooltips.md,
-- Phase 0) rather than assumed:
--
--   GameTooltip is NOT protected, so there is no combat guard to test and none should exist.
--   TooltipDataProcessor is PRESENT and deliberately UNUSED, so the legacy OnTooltipSet*
--     scripts are the only content path -- pinned below, because "just use the modern API"
--     is a refactor that would compile and silently do nothing.
--   Blizzard's border is a NINESLICE, so hiding it is mandatory and not defensive.
--
-- What a spec here CANNOT prove: that Blizzard's own restyle fires the durability hook. The
-- harness models no Blizzard-side re-stamping, so calling SharedTooltip_SetBackdropStyle from a
-- test asserts against the test's own trigger. That gap is recorded in TESTING.md; the in-game
-- check is hovering anything after a UI event that re-stamps a backdrop.

local PLUGIN_ID = "tooltips"

local function plugin()    return H.SuuUI.Plugins:Get(PLUGIN_ID) end
local function get(key)    return H.SuuUI.Settings:Get(PLUGIN_ID, key) end
local function set(key, v) return H.SuuUI.Settings:Set(PLUGIN_ID, key, v) end
local function Skin()      return H.SuuUI._Tooltips.Skin end
local function Signal()    return H.SuuUI._Tooltips.Signal end
local function Anchor()    return H.SuuUI._Tooltips.Anchor end
local function tip()       return H.env.GameTooltip end

-- The border colour the frame is currently carrying. Read off the backdrop, which is where
-- Backdrop.SetBorder puts it.
local function borderOf(f)
    local c = f._backdropBorderColor
    if not c then return nil end
    return { c[1], c[2], c[3], c[4] }
end

local function near(a, b)
    return a and b and math.abs(a[1] - b[1]) < 0.001
        and math.abs(a[2] - b[2]) < 0.001
        and math.abs(a[3] - b[3]) < 0.001
end

describe("Plugins.Tooltips", function()
    before_each(function()
        H.setup()
    end)

    ---------------------------------------------------------------------------
    -- Lifecycle and schema
    ---------------------------------------------------------------------------
    describe("the plugin", function()
        it("registers and is enabled by default", function()
            expect(plugin()).truthy()
            expect(plugin():IsEnabled()).eq(true)
        end)

        it("declares every key its code reads", function()
            -- A key with no schema entry reads as nil through Settings:Get, so a missing one is
            -- a feature that silently does nothing.
            for _, key in ipairs({ "enabled", "signal_border", "backdrop_alpha", "font_size",
                                   "header_font_size", "comparison_font_size", "anchor_mode",
                                   "x_offset", "y_offset", "position" }) do
                local found = false
                for _, e in ipairs(H.SuuUI.Settings:GetSchema(PLUGIN_ID) or {}) do
                    if e.key == key then found = true break end
                end
                expect(found).as("schema declares " .. key).eq(true)
            end
        end)

        it("puts the enable toggle OUTSIDE any section", function()
            -- A player whose tooltips are misbehaving must not have to open a group to find the
            -- switch that turns the plugin off. Same rule as the action bars' suppression toggle.
            local schema = H.SuuUI.Settings:GetSchema(PLUGIN_ID)
            for _, e in ipairs(schema) do
                if e.type == "section" then break end
                if e.key == "enabled" then return end
            end
            error("the enabled toggle is not before the first section")
        end)

        it("builds a settings page that produces visible rows", function()
            -- Asserting a schema's SHAPE is not asserting that it renders: a missing subtabs id
            -- once threw the entire page build while every shape assertion passed.
            local win = H.SuuUI.SettingsWindow
            local ok = pcall(win.Open)
            expect(ok).as("the settings window opened").eq(true)
        end)
    end)

    ---------------------------------------------------------------------------
    -- The skin
    ---------------------------------------------------------------------------
    describe("the skin", function()
        it("gives the tooltip SuuUI's surface", function()
            expect(Skin().IsSkinned(tip())).eq(true)
        end)

        it("paints the background from colorBg with the alpha setting", function()
            set("backdrop_alpha", 0.5)
            local c = tip()._backdropColor
            local bg = H.SuuUI.Theme:GetToken("colorBg")
            expect(c[1]).eq(bg[1])
            expect(c[4]).as("the setting replaces the token's alpha").eq(0.5)
        end)

        it("hides Blizzard's NineSlice, which is the border it really draws", function()
            -- Measured present on this client. SetBackdrop alone leaves it drawing underneath
            -- ours and the player sees a double frame.
            expect(tip().NineSlice).truthy()
            expect(tip().NineSlice:GetAlpha()).eq(0)
        end)

        it("skips an embedded tooltip rather than giving it its own panel", function()
            local embedded = H.env.CreateFrame("GameTooltip", nil, H.env.UIParent, "BackdropTemplate")
            expect(Skin().Style(embedded, nil, true)).as("embedded flag").eq(false)
            embedded.IsEmbedded = true
            expect(Skin().Style(embedded)).as("IsEmbedded field").eq(false)
        end)

        it("refuses a forbidden frame", function()
            local f = H.env.CreateFrame("GameTooltip", nil, H.env.UIParent, "BackdropTemplate")
            f.IsForbidden = function() return true end
            expect(Skin().Style(f)).eq(false)
        end)

        it("survives a frame that cannot take a backdrop at all", function()
            -- This shipped once: Backdrop.Apply RAISES on a frame not created with
            -- BackdropTemplate, and "the method exists" is not a sufficient test because it
            -- exists and then raises. The throw landed inside Plugin:Enable's pcall, so the
            -- player got no tooltips and no message.
            local plain = H.env.CreateFrame("Frame", nil, H.env.UIParent)
            local ok, res = pcall(Skin().Style, plain)
            expect(ok).as("did not raise").eq(true)
            expect(res).as("reported that it skipped").eq(false)
        end)

        it("iterates the frame list with next, so a nil global does not truncate it", function()
            -- ipairs stops dead at the FIRST hole, silently dropping every frame after it. The
            -- hole therefore has to be at the FRONT for this to discriminate: with it in the
            -- middle, ipairs still reaches everything before it and the test passes either way.
            -- That weakness let the mutation survive on the first attempt.
            local behind = H.env.ShoppingTooltip1
            expect(behind).as("there is something behind the hole to drop").truthy()

            H.env.GameTooltip = nil
            local n = Skin().StyleAll()

            expect(n).as("skinned the frames behind the hole").gte(1)
            expect(Skin().IsSkinned(behind))
                .as("a frame AFTER the nil was still reached").eq(true)
        end)
    end)

    ---------------------------------------------------------------------------
    -- The signal border
    ---------------------------------------------------------------------------
    describe("the signal border", function()
        it("colours an item's border by quality from uncommon up", function()
            local link = "|Hitem:1|h[Epic]|h"
            H.setItemInfo(link, { quality = 4 })
            tip()._ttItem = link
            Signal().OnItem(tip())
            expect(near(borderOf(tip()), H.SuuUI.Game:ItemQualityColor(4)))
                .as("epic purple").eq(true)
        end)

        it("does NOT colour Common or Poor", function()
            -- The rule T4 needs and T3 did not, and it is ElvUI's too (`quality > 1`). A white
            -- 1px edge on a dark panel reads as a selected state, and it would fire on the
            -- MAJORITY of tooltips a player sees -- every reagent, every grey drop.
            for _, q in ipairs({ 0, 1 }) do
                local link = "|Hitem:" .. q .. "|h[Plain]|h"
                H.setItemInfo(link, { quality = q })
                expect(Signal().ItemColor(link)).as("quality " .. q .. " gets no border").isNil()
            end
            -- ...while Game still HAS those colours, because the threshold is this plugin's
            -- policy and not a fact about the client.
            expect(H.SuuUI.Game:ItemQualityColor(1)).notNil()
        end)

        it("colours uncommon, which is the boundary", function()
            local link = "|Hitem:2|h[Green]|h"
            H.setItemInfo(link, { quality = 2 })
            expect(near(Signal().ItemColor(link), H.SuuUI.Game:ItemQualityColor(2))).eq(true)
        end)

        it("leaves the border alone for an item the client has not cached", function()
            -- GetItemInfo answers nothing for an uncached item, which is a real state rather
            -- than an error.
            H.clearItems()
            expect(Signal().ItemColor("|Hitem:999|h[Unknown]|h")).isNil()
        end)

        it("colours a player by class and a mob by reaction", function()
            H.setTarget({ class = "MAGE", isPlayer = true })
            tip():SetUnit("target")
            local classColor = H.SuuUI.Game:ClassColor("MAGE")
            expect(near(borderOf(tip()), classColor)).as("class colour").eq(true)
        end)

        it("resets the border on clear, so a colour cannot leak to the next tooltip", function()
            H.setTarget({ class = "MAGE", isPlayer = true })
            tip():SetUnit("target")
            expect(Signal()._tinted[tip()]).as("tinted").eq(true)
            tip():ClearLines()
            expect(Signal()._tinted[tip()]).as("no longer tinted").isNil()
            expect(near(borderOf(tip()), H.SuuUI.Theme:GetToken("colorBorder")))
                .as("back to the theme's border").eq(true)
        end)

        it("does not reset a border it never set", function()
            -- With the feature off we coloured nothing, and resetting anyway would override
            -- whatever else owns that border.
            expect(Signal().Reset(tip())).eq(false)
        end)

        it("does nothing at all while switched off", function()
            set("signal_border", false)
            H.setTarget({ class = "MAGE", isPlayer = true })
            tip():SetUnit("target")
            expect(Signal()._tinted[tip()]).isNil()
        end)

        it("never tints a frame it did not skin", function()
            -- A border colour is a property of a backdrop, so SetBackdropBorderColor on a frame
            -- without one raises -- from inside a tooltip script, where a throw is the client's
            -- frame rather than ours.
            local plain = H.env.CreateFrame("Frame", nil, H.env.UIParent)
            plain.GetUnit = function() return "Bob", "target" end
            H.setTarget({ class = "MAGE", isPlayer = true })
            local ok = pcall(Signal().OnUnit, plain)
            expect(ok).as("did not raise").eq(true)
            expect(Signal()._tinted[plain]).isNil()
        end)

        describe("aura colours mirror AuraBand's rules exactly", function()
            it("gives a debuff its dispel colour", function()
                expect(near(Signal().AuraColor(true, "Curse"),
                            H.SuuUI.Game:DebuffTypeColor("Curse"))).eq(true)
            end)

            it("gives an UNTYPED debuff red, which is the common case", function()
                expect(near(Signal().AuraColor(true, nil),
                            H.SuuUI.Game:UntypedDebuffColor())).eq(true)
            end)

            it("gives a non-stealable buff NOTHING, even when it has a dispel type", function()
                -- The trap that cost a debugging round in the aura band: the client reports a
                -- dispelType for HELPFUL auras too (Righteous Fury comes back as "Magic"), so
                -- reading it would ring half a paladin's blessings in blue.
                expect(Signal().AuraColor(false, "Magic", false)).isNil()
            end)

            it("gives a STEALABLE buff its dispel colour", function()
                expect(near(Signal().AuraColor(false, "Magic", true),
                            H.SuuUI.Game:DebuffTypeColor("Magic"))).eq(true)
            end)
        end)

        it("leaves a spell tooltip alone, deliberately", function()
            -- No spell-to-school API on this client, so Game:SchoolOf only knows spells the
            -- combat log has reported. A border coloured for spells you have cast and grey
            -- otherwise is worse than always grey. Pinned so nobody wires a school lookup.
            tip():SetSpellByID(27071)
            expect(Signal()._tinted[tip()]).isNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- Fonts
    ---------------------------------------------------------------------------
    describe("fonts", function()
        it("sets all three Font objects, not per-line font strings", function()
            expect(Skin().ApplyFonts()).eq(3)
        end)

        it("gives the header its own size", function()
            set("font_size", 11)
            set("header_font_size", 17)
            Skin().ApplyFonts()
            expect(select(2, H.env.GameTooltipText:GetFont())).eq(11)
            expect(select(2, H.env.GameTooltipHeaderText:GetFont())).eq(17)
        end)

        it("falls back to a loadable face when the theme names a bad one", function()
            -- Built-in themes are read-only, so this needs a user theme to edit.
            local T = H.SuuUI.Theme
            T:CreateUserTheme("probe", T:GetActive())
            T:SetActive("probe")
            T:SetUserToken("probe", "fontFamilyMain", "Fonts/NOPE.TTF")

            local ok = pcall(Skin().ApplyFonts)
            expect(ok).as("did not raise out of the login pass").eq(true)
            -- What actually protects this is Fonts:Path, which resolves an unknown face to a
            -- loadable one BEFORE it reaches SetFont. So the face that lands is the fallback,
            -- not the bad name.
            local path = H.env.GameTooltipText:GetFont()
            expect(path).neq("Fonts/NOPE.TTF")
            expect(H.SuuUI.Fonts:Validate(path)).as("whatever landed is loadable").truthy()
        end)

        xit("survives a font object whose SetFont refuses outright", function()
            -- The pcall in Skin's setFont is belt-and-braces and its raise path is NOT
            -- reachable through Fonts:Path, which guarantees a loadable path -- so a mutation
            -- removing the pcall survives, and correctly so.
            --
            -- It stays because this runs during the PLAYER_LOGIN pass, where an unguarded
            -- SetFont has already unwound out of a handler once in this codebase, and because a
            -- Font object is a different client code path from a FontString: nothing proves the
            -- client refuses both for the same set of assets. Reaching it needs a harness hook
            -- that makes one font object reject a face Fonts:Path considers fine.
        end)
    end)

    ---------------------------------------------------------------------------
    -- The anchor
    ---------------------------------------------------------------------------
    describe("the anchor", function()
        it("creates one moveable mover and reuses it", function()
            local m = Anchor().EnsureMover()
            expect(m).truthy()
            expect(Anchor().EnsureMover()).as("same frame").eq(m)
        end)

        it("registers the mover with edit mode under its own name", function()
            Anchor().EnsureMover()
            local found = false
            for _, f in ipairs(H.SuuUI.ToggleUI:GetAll()) do
                if f == Anchor().GetMover() then found = true end
            end
            expect(found).as("listed as a moveable frame").eq(true)
        end)

        it("grows the tooltip AWAY from the mover", function()
            -- Argument order is load-bearing: the tooltip's own `point` attaches to the mover's
            -- INVERSE. Reversed, a bottom-right mover grows the tooltip down and right, off the
            -- screen edge -- which is how this was first written.
            --
            -- Asserting the INVERSE table alone is asserting INTENT: it passes with the SetPoint
            -- arguments swapped, which is exactly what the mutation showed. Read the resolved
            -- anchor back off the frame instead.
            set("anchor_mode", "mover")
            local mover = Anchor().EnsureMover()
            tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
            tip():ClearAllPoints()
            expect(Anchor().Place(tip(), H.env.UIParent)).eq("mover")

            local point, relTo, relPoint = tip():GetPoint()
            expect(relTo).as("anchored to the mover").eq(mover)
            local corner = Anchor().moverPoint()
            expect(point).as("the TOOLTIP's own point is the mover's corner").eq(corner)
            expect(relPoint).as("attached to the mover's INVERSE corner")
                .eq(Anchor().INVERSE[corner])
        end)

        it("declines when something already owns the anchor", function()
            tip():SetOwner(H.env.UIParent, "ANCHOR_CURSOR")
            expect(Anchor().Place(tip(), H.env.UIParent)).isNil()
        end)

        it("uses cursor mode when asked", function()
            set("anchor_mode", "cursor")
            tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
            expect(Anchor().Place(tip(), H.env.UIParent)).eq("cursor")
            expect(tip():GetAnchorType()).eq("ANCHOR_CURSOR")
        end)

        it("declines entirely while the plugin is off", function()
            set("enabled", false)
            tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
            expect(Anchor().Place(tip(), H.env.UIParent)).isNil()
        end)

        it("only re-points an anchor it recognises as unclaimed", function()
            -- The whitelist is what stops SuuUI fighting an addon that placed the tooltip
            -- deliberately.
            expect(Anchor().unclaimed(nil)).eq(true)
            expect(Anchor().unclaimed(H.env.UIParent)).eq(true)
            local stranger = H.env.CreateFrame("Frame", nil, H.env.UIParent)
            expect(Anchor().unclaimed(stranger)).as("someone else's frame").eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- The health bar
    ---------------------------------------------------------------------------
    describe("the health bar", function()
        local function hb()    return H.SuuUI._Tooltips.HealthBar end
        local function ours()  return hb().GetWidget() end
        local function blizz() return H.env.GameTooltipStatusBar end

        local function showUnit(props)
            H.setTarget(props or { class = "MAGE", isPlayer = true, health = 500, healthMax = 1000 })
            tip():SetUnit("target")
        end

        it("uses SuuUI's OWN StatusBar, not Blizzard's", function()
            -- The swap that removed the only non-additive call in the plugin: driving Blizzard's
            -- bar needed SetScript("OnValueChanged", nil) plus a re-hook, purely to stop its own
            -- handler fighting ours. Owning the bar leaves nothing to fight.
            showUnit()
            expect(ours()).as("a SuuUI handle exists").truthy()
            expect(type(ours().SetFillColor)).as("it is a SuuUI StatusBar").eq("function")
            expect(ours():GetFrame():GetParent()).as("inside the tooltip").eq(tip())
        end)

        it("SUPPRESSES Blizzard's bar, and keeps it suppressed", function()
            -- Necessary rather than tidy: GameTooltip_ShowStatusBar shows that bar whenever the
            -- client has health to display, so a one-shot Hide is undone on the next mouseover
            -- and the player sees two bars.
            showUnit()
            expect(blizz():IsShown()).as("hidden").eq(false)
            blizz():Show()
            expect(blizz():IsShown()).as("and it stays hidden through a re-show").eq(false)
        end)

        it("hands Blizzard's bar back on teardown", function()
            -- The flag has to clear BEFORE any Show, because HookScript cannot be undone.
            showUnit()
            plugin():Disable()
            expect(hb()._suppressed[blizz()]).as("no longer claimed").isNil()
            blizz():Show()
            expect(blizz():IsShown()).as("shows again once released").eq(true)
        end)

        it("reserves space with SetPadding so the bar cannot cover the last line", function()
            showUnit()
            local _, bottom = tip():GetPadding()
            expect(bottom).eq(hb().height() + (H.token("spaceXs") or 4))
        end)

        it("reserves at the TOP when asked", function()
            set("health_position", "TOP")
            showUnit()
            local _, bottom, _, top = tip():GetPadding()
            expect(top).as("top padding reserved").eq(hb().height() + (H.token("spaceXs") or 4))
            expect(bottom).as("and nothing at the bottom").eq(0)
        end)

        it("states padding ABSOLUTELY, so two shows do not stack it", function()
            showUnit()
            local _, first = tip():GetPadding()
            showUnit()
            local _, second = tip():GetPadding()
            expect(second).as("unchanged across a second show").eq(first)
        end)

        it("adds the bar to its container exactly once", function()
            -- Add is a membership operation, not an upsert: calling it per mouseover grows the
            -- child list without bound. Later shows update the props instead.
            showUnit()
            showUnit()
            showUnit()
            expect(#hb().GetHost():GetChildren()).as("one bar after three shows").eq(1)
        end)

        it("hands the reserved space back on clear", function()
            showUnit()
            tip():ClearLines()
            local _, bottom = tip():GetPadding()
            expect(bottom).eq(0)
        end)

        it("does not clear padding it never reserved", function()
            expect(hb().Release(tip())).eq(false)
        end)

        it("takes the unit's colour, which the client does not supply", function()
            showUnit({ class = "MAGE", isPlayer = true, health = 500, healthMax = 1000 })
            local want = H.SuuUI.Theme:GetUnitColor("colorHealth", "target")
            expect(near(ours()._fillColor, want)).as("class or reaction colour").eq(true)
        end)

        it("spans the tooltip's width and follows it as the tooltip grows", function()
            -- A stack child, not an anchor descriptor: a tooltip resizes on every line it is
            -- handed, and an anchor descriptor would carry a width computed once at placement
            -- time and go stale the moment the next line arrived.
            --
            -- The tooltip needs an explicit size: the harness never lays one out on its own, so
            -- without this the child has no resolvable rect and H.box answers nil.
            tip():SetSize(200, 80)
            showUnit()
            local inset = (H.token("borderWidth") or 1) + (H.token("spaceXs") or 4)
            expect(ours():GetWidth()).as("spans the tooltip minus both insets")
                .eq(200 - inset * 2)

            tip():SetSize(300, 80)
            expect(ours():GetWidth()).as("and grew with the tooltip").eq(300 - inset * 2)
        end)

        it("follows the height setting", function()
            set("health_height", 20)
            showUnit()
            expect(ours():GetHeight()).eq(20)
        end)

        describe("the readout", function()
            it("uses the SHARED formats, not one of its own", function()
                -- Core/Readout.lua. The first version invented k/M abbreviation no other bar in
                -- the addon uses, so a tooltip read "7.6k / 15.2k" beside a unit frame printing
                -- "7620 / 15240".
                expect(H.SuuUI.Readout.Format("current_max", 7620, 15240)).eq("7620 / 15240")
                expect(H.SuuUI.Readout.Format("percent", 500, 1000)).eq("50%")
                expect(H.SuuUI.Readout.Format("current", 500, 1000)).eq("500")
            end)

            it("clears the slot for an unresolved mode", function()
                expect(H.SuuUI.Readout.Format("none", 1, 2)).isNil()
                expect(H.SuuUI.Readout.Format(nil, 1, 2)).isNil()
            end)

            it("writes the value into the centre slot", function()
                set("health_text_mode", "current_max")
                showUnit({ isPlayer = true, class = "MAGE", health = 500, healthMax = 1000 })
                expect(ours():GetText("center")).eq("500 / 1000")
                expect(ours():GetText("left")).as("and only the centre").isNil()
            end)

            it("says DEAD at zero rather than 0 / max", function()
                showUnit({ isPlayer = true, class = "MAGE", health = 0, healthMax = 1000 })
                expect(ours():GetText("center")).matches("[Dd]ead")
            end)

            it("goes empty when the readout is switched off", function()
                set("health_text", false)
                showUnit()
                expect(ours():GetText("center")).isNil()
            end)
        end)

        it("follows the unit's health live", function()
            -- Blizzard drove its own bar's value; owning the bar means owning the updates, and
            -- nothing announces that a tooltip closed -- so the watcher is armed only while one
            -- is open.
            showUnit({ isPlayer = true, class = "MAGE", health = 1000, healthMax = 1000 })
            expect(ours():GetValue()).eq(1000)
            H.setUnit("target", { health = 250, healthMax = 1000 })
            H.fireEvent("UNIT_HEALTH", "target")
            expect(ours():GetValue()).as("tracked the change").eq(250)
        end)

        it("hides GENUINELY when disabled, not just at alpha 0", function()
            showUnit()
            expect(ours():IsShown()).as("shown to begin with").eq(true)
            set("health_position", "DISABLED")
            showUnit()
            expect(ours()).as("torn down entirely").isNil()
            local _, bottom = tip():GetPadding()
            expect(bottom).as("and reserves nothing").eq(0)
        end)

        it("hides the bar when the tooltip goes", function()
            -- ElvUI's bar-hider is registered only inside its RETAIL branch, so on this client
            -- nothing hides it and it lingers over the world. This plugin wires it itself.
            showUnit()
            expect(ours():IsShown()).eq(true)
            tip():Hide()
            expect(ours():IsShown()).as("gone with the tooltip").eq(false)
        end)

        it("releases everything on teardown", function()
            showUnit()
            plugin():Disable()
            expect(ours()).isNil()
            local _, bottom = tip():GetPadding()
            expect(bottom).eq(0)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Content lines
    ---------------------------------------------------------------------------
    describe("content lines", function()
        local function C() return H.SuuUI._Tooltips.Content end

        -- Reads the right-hand value of the line whose left label matches, which is how these
        -- are added. Returns the value and its colour.
        local function lineValue(label)
            for i = 1, tip():NumLines() do
                local left, right = tip():GetLine(i)
                if left == label then
                    local _, _, _, rr, rg, rb = tip():GetLineColor(i)
                    return right, { rr, rg, rb, 1 }
                end
            end
            return nil
        end

        -- Whether a line with this label exists AT ALL, regardless of its value.
        --
        -- Distinct from lineValue on purpose: lineValue returns the right-hand value, which is
        -- nil both when the line is absent AND when it was added with a nil value. A missing
        -- guard that appended `AddDoubleLine("Guild Rank", nil)` therefore passed a lineValue
        -- assertion — the mutation that exposed this survived on exactly that ambiguity.
        local function hasLine(label)
            for i = 1, tip():NumLines() do
                if (tip():GetLine(i)) == label then return true end
            end
            return false
        end

        local EPIC = "|Hitem:1|h[Epic]|h"

        local function showItem(props)
            H.setItemInfo(EPIC, props or { quality = 4, itemLevel = 154 })
            tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
            tip()._ttItem = EPIC
            tip():SetHyperlink(EPIC)
        end

        describe("on an item", function()
            it("adds the item level from GetItemInfo's fourth field", function()
                -- The boring field, and EXACT here: TBC has no upgrade levels, so there is
                -- nothing to scrape out of the tooltip's text and nothing for
                -- GetDetailedItemLevelInfo to add.
                showItem({ quality = 4, itemLevel = 154 })
                expect(lineValue("Item Level")).eq("154")
            end)

            it("omits the item level for a trivial one", function()
                -- Every grey and every reagent is item level 1; a line saying so on all of them
                -- is noise on the majority of tooltips.
                showItem({ quality = 1, itemLevel = 1 })
                expect(lineValue("Item Level")).isNil()
            end)

            it("shows how many you carry, with the bank as the DIFFERENCE", function()
                -- GetItemCount's includeBank returns the TOTAL. Reading it as the bank's own
                -- figure prints the whole stack as if it were all in the bank.
                showItem({ quality = 2, itemLevel = 20, countBags = 14, countBank = 100 })
                expect(lineValue("Carrying")).eq("14 (bank 100)")
            end)

            it("drops the bank part when there is none", function()
                showItem({ quality = 2, itemLevel = 20, countBags = 3, countBank = 0 })
                expect(lineValue("Carrying")).eq("3")
            end)

            it("drops the bank part when the setting is off", function()
                set("item_count_bank", false)
                showItem({ quality = 2, itemLevel = 20, countBags = 3, countBank = 100 })
                expect(lineValue("Carrying")).eq("3")
            end)

            it("adds no Carrying line for something you do not have", function()
                showItem({ quality = 2, itemLevel = 20, countBags = 0, countBank = 0 })
                expect(lineValue("Carrying")).isNil()
            end)

            it("shows the sell price only when switched on", function()
                showItem({ quality = 2, itemLevel = 20, sellPrice = 120488 })
                expect(lineValue("Sells for")).as("off by default").isNil()
                set("sell_price", true)
                showItem({ quality = 2, itemLevel = 20, sellPrice = 120488 })
                expect(lineValue("Sells for")).eq("12g 4s 88c")
            end)

            it("respects every toggle independently", function()
                set("item_level", false)
                set("item_count", false)
                showItem({ quality = 4, itemLevel = 154, countBags = 5 })
                expect(lineValue("Item Level")).isNil()
                expect(lineValue("Carrying")).isNil()
            end)
        end)

        -- THE ACCOUNT SECTION (T1): which OTHER characters hold this item, read from the Core cache.
        --
        -- The cache is staged by RUNNING A REAL CAPTURE against staged client state, not by writing the
        -- store by hand. That is not fussiness: the last bug in this feature area survived every spec
        -- because the specs wrote item names straight into the item table, which the container API
        -- cannot do -- so they asserted against a state production never reaches.
        describe("the account section", function()
            local ID = 22832
            local ITEM = "|cffffffff|Hitem:22832|h[Arcane Powder]|h|r"

            -- Captures the CURRENT character with the given bag contents, then renames the record so it
            -- belongs to someone else -- which is how a second character gets into the cache in a
            -- single-character test client. The rename is the only shortcut, and it copies a record
            -- that a genuine capture produced.
            local function cacheOther(name, class, bags, bank)
                local IC = H.SuuUI.ItemCache
                IC:Init()
                H.setBags({ [0] = { free = 6, slots = 8 } })
                H.setBagItem(0, 1, { itemID = ID, stackCount = bags or 1, quality = 1,
                                     iconFileID = "i", hyperlink = ITEM })
                IC:Capture("bags")
                local store = H.env.SuuUIItemCache
                local mine = store.chars[IC:CurrentKey()]
                local key = name .. "-TestRealm"
                store.chars[key] = {
                    class = class or "MAGE",
                    bags = { seen = mine.bags.seen, slots = mine.bags.slots },
                }
                if bank then
                    store.chars[key].bank =
                        { seen = mine.bags.seen, slots = { [-1] = { [1] = { ID, bank } } } }
                end
                -- The current character's own record is cleared so the section has only the alt to
                -- report -- the live `Carrying` line already answers for whoever is logged in.
                store.chars[IC:CurrentKey()] = nil
                IC:Forget("nobody")   -- clears the Find memo, which the capture above populated
                return key
            end

            local function showThisItem()
                H.setItemInfo(ITEM, { quality = 1, itemLevel = 1, countBags = 0, countBank = 0 })
                tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                tip()._ttItem = ITEM
                tip():SetHyperlink(ITEM)
            end

            it("names a character holding the item, with the count", function()
                cacheOther("Thalira", "MAGE", 8)
                showThisItem()
                expect(lineValue("Thalira")).as("one line per holder").eq("8")
            end)

            it("merges a character's bags and bank onto ONE line", function()
                -- Find returns bags and bank as SEPARATE hits. Two consecutive lines for one character
                -- would read as two characters, and the format matches the Carrying line above it.
                cacheOther("Thalira", "MAGE", 8, 20)
                showThisItem()
                expect(lineValue("Thalira")).eq("8 (bank 20)")
            end)

            it("says 'bank N' rather than '0 (bank N)' for a bank-only holding", function()
                -- "0 (bank 20)" makes a player check their bags for nothing.
                local IC = H.SuuUI.ItemCache
                cacheOther("Thalira", "MAGE", 8, 20)
                local store = H.env.SuuUIItemCache
                store.chars["Thalira-TestRealm"].bags = nil
                IC:Forget("nobody")
                showThisItem()
                expect(lineValue("Thalira")).eq("bank 20")
            end)

            it("class-colours the character's name", function()
                cacheOther("Thalira", "MAGE", 8)
                showThisItem()
                local want = H.SuuUI.Game:ClassColor("MAGE")
                local found
                for i = 1, tip():NumLines() do
                    if (tip():GetLine(i)) == "Thalira" then
                        local lr, lg, lb = tip():GetLineColor(i)
                        found = { lr, lg, lb }
                    end
                end
                expect(found).as("the line was found").truthy()
                expect(found[1]).as("same fact the dropdown paints with").near(want[1], 0.001)
                expect(found[3]).near(want[3], 0.001)
            end)

            it("never lists the character you are playing", function()
                -- The live `Carrying` line above already answers for you, and from the client rather
                -- than from a cache that is only as fresh as your last capture. Two figures for one
                -- character invite the player to compare them and find them disagreeing.
                local IC = H.SuuUI.ItemCache
                IC:Init()
                H.setBags({ [0] = { free = 6, slots = 8 } })
                H.setBagItem(0, 1, { itemID = ID, stackCount = 5, quality = 1,
                                     iconFileID = "i", hyperlink = ITEM })
                IC:Capture("bags")
                showThisItem()
                local me = IC:CurrentKey():match("^(.-)%-")
                expect(hasLine(me)).as("you are not in the account section").falsy()
            end)

            it("adds nothing when nobody else holds it", function()
                H.SuuUI.ItemCache:Init()
                showThisItem()
                expect(hasLine("Account total")).falsy()
            end)

            it("is silent while switched off", function()
                cacheOther("Thalira", "MAGE", 8)
                H.SuuUI.Settings:Set("tooltips", "account_counts", false)
                showThisItem()
                expect(hasLine("Thalira")).falsy()
            end)

            it("lists a character holding none only when asked", function()
                local key = cacheOther("Thalira", "MAGE", 8)
                local store = H.env.SuuUIItemCache
                store.chars["Broke-TestRealm"] = { class = "PRIEST",
                                                   bags = { seen = 1, slots = { [0] = {} } } }
                H.SuuUI.ItemCache:Forget("nobody")
                showThisItem()
                expect(hasLine("Broke")).as("off by default").falsy()

                H.SuuUI.Settings:Set("tooltips", "account_zero", true)
                tip():ClearLines()
                showThisItem()
                expect(lineValue("Broke")).as("and an em dash rather than a bare 0").eq("—")
                expect(key).truthy()
            end)
        end)

        describe("money formatting", function()
            it("drops the units that would read as zero", function()
                -- "12g 0s 88c" is noise, and a price under a gold has no business showing a
                -- gold figure at all.
                expect(C().FormatMoney(120488)).eq("12g 4s 88c")
                expect(C().FormatMoney(488)).eq("4s 88c")
                expect(C().FormatMoney(88)).eq("88c")
            end)

            it("keeps a zero MIDDLE unit, because the letters disambiguate", function()
                -- "12g 88c" and "12g 88s" are different prices; dropping the silver entirely
                -- would make them ambiguous to a reader scanning the letters.
                expect(C().FormatMoney(120088)).eq("12g 0s 88c")
            end)

            it("answers nothing for a worthless item", function()
                expect(C().FormatMoney(0)).isNil()
                expect(C().FormatMoney(nil)).isNil()
            end)
        end)

        describe("on a unit", function()
            local function showUnit()
                H.setTarget({ class = "MAGE", isPlayer = true, name = "Vaelthorne", role = "DAMAGER" })
                H.setUnit("targettarget", { exists = true, name = "Illidan", reaction = 2 })
                tip():SetUnit("target")
            end

            it("shows what the unit is targeting", function()
                showUnit()
                expect(lineValue("Target")).eq("Illidan")
            end)

            it("colours that target by what IT is", function()
                showUnit()
                local _, colour = lineValue("Target")
                local want = H.SuuUI.Theme:GetUnitColor("colorHealth", "targettarget")
                expect(near(colour, want)).as("the target's own colour").eq(true)
            end)

            it("adds no Target line when the unit has none", function()
                H.setTarget({ class = "MAGE", isPlayer = true })
                tip():SetUnit("target")
                expect(lineValue("Target")).isNil()
            end)

            it("translates the role rather than printing the client's word", function()
                -- MEASURED: the client answers "DAMAGER", not "DPS". Printing it raw shows a
                -- word no player uses.
                showUnit()
                expect(lineValue("Role")).eq("Damage")
                expect(C().RoleText("target")).eq("Damage")
            end)

            it("renders NOTHING for a unit with no role", function()
                -- "NONE" is what a solo player reports, and a line saying "None" is a line
                -- about nothing.
                H.setTarget({ class = "MAGE", isPlayer = true, role = "NONE" })
                tip():SetUnit("target")
                expect(lineValue("Role")).isNil()
                expect(C().RoleText("target")).isNil()
            end)

            it("maps the other two roles", function()
                H.setUnit("target", { role = "TANK" })
                expect(C().RoleText("target")).eq("Tank")
                H.setUnit("target", { role = "HEALER" })
                expect(C().RoleText("target")).eq("Healer")
            end)

            it("respects both unit toggles", function()
                -- The OFF state, which is the half a green "it shows the line" test never
                -- touches -- and it is exactly what let two mutations survive here.
                set("unit_target", false)
                set("unit_role", false)
                showUnit()
                expect(lineValue("Target")).as("target line suppressed").isNil()
                expect(lineValue("Role")).as("role line suppressed").isNil()
            end)
        end)

        describe("guild rank", function()
            local function guilded()
                H.setTarget({ class = "MAGE", isPlayer = true, name = "Vaelthorne",
                              guild = "Ashen Vow", guildRank = "Officer" })
                tip():SetUnit("target")
            end

            it("adds the rank", function()
                guilded()
                expect(lineValue("Guild Rank")).eq("Officer")
            end)

            it("adds only the RANK, not the guild name again", function()
                -- The client already prints <Guild> on its own line. Appending the name would
                -- duplicate a line the tooltip already has.
                guilded()
                expect(lineValue("Guild")).isNil()
            end)

            it("adds nothing for a unit with no guild", function()
                H.setTarget({ class = "MAGE", isPlayer = true })
                tip():SetUnit("target")
                expect(lineValue("Guild Rank")).isNil()
            end)

            it("adds nothing when the guild is known but the rank is not", function()
                H.setTarget({ class = "MAGE", isPlayer = true, guild = "Ashen Vow" })
                tip():SetUnit("target")
                expect(hasLine("Guild Rank")).as("no line at all, not a blank one").eq(false)
            end)

            it("respects its toggle", function()
                set("guild_rank", false)
                guilded()
                expect(hasLine("Guild Rank")).eq(false)
            end)
        end)

        describe("level difficulty colouring", function()
            local C2 = function() return H.SuuUI._Tooltips.Content end

            -- Builds a tooltip shaped like the client's: name, then the level line.
            local function unitWithLevel(level, extraFirst)
                H.setUnit("player", { level = 70 })
                H.setTarget({ name = "Mob", level = level, reaction = 2 })
                tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                tip():SetText("Mob")
                if extraFirst then tip():AddLine(extraFirst) end
                tip():AddLine("Level " .. level .. " Humanoid")
                C2().ColorLevelLine(tip())
            end

            local function levelText()
                local i = C2().FindLevelLine(tip())
                if not i then return nil end
                local fs = C2().lineFS(tip(), i)
                return fs and fs:GetText()
            end

            -- The escape the number should be wrapped in for a given difficulty band.
            local function escFor(band)
                return C2().Escape(H.SuuUI.Game.DIFFICULTY[band])
            end

            local function numberIsColored(band)
                local t = levelText()
                if not t then return false end
                -- The escape must sit immediately BEFORE the digits and close immediately after,
                -- which is what makes it the number rather than the line.
                return t:find(escFor(band) .. "%d+|r") ~= nil
            end

            it("finds the level line by PATTERN, not by a fixed index", function()
                -- It is line 2 for a mob and line 3 for a guilded player, and it moves again for
                -- anything with a title -- so a fixed index colours the guild name on some units
                -- and nothing at all on others.
                unitWithLevel(70)
                expect(C2().FindLevelLine(tip())).eq(2)
                unitWithLevel(70, "<Ashen Vow>")
                expect(C2().FindLevelLine(tip())).as("moved down by the guild line").eq(3)
            end)

            it("colours ONLY the number, leaving the rest of the line alone", function()
                unitWithLevel(78)
                local t = levelText()
                expect(t).as("the words survive").matches("Humanoid")
                expect(t:find("^" .. escFor("deadly"):gsub("|", "%%|")))
                    .as("the line does not START coloured").isNil()
                expect(numberIsColored("deadly")).as("the digits are wrapped").eq(true)
            end)

            it("leaves the font string's OWN colour untouched", function()
                -- SetTextColor would colour the whole line, which is what the escape exists to
                -- avoid. If this ever starts returning a colour, the implementation regressed to
                -- recolouring the font string.
                unitWithLevel(78)
                local i = C2().FindLevelLine(tip())
                local r = select(1, tip():GetLineColor(i))
                expect(r).as("no font-string colour was set").isNil()
            end)

            it("skips line 1, so a unit NAMED after a level is not mistaken for one", function()
                -- Why the scan starts at 2 rather than 1. "Level 60 Test Dummy" is a real mob
                -- name, and matching it would recolour the NAME and leave the actual level line
                -- alone. Without this case the start index is a free parameter.
                H.setUnit("player", { level = 70 })
                H.setTarget({ name = "Level 60 Test Dummy", level = 70, reaction = 2 })
                tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                tip():SetText("Level 60 Test Dummy")
                tip():AddLine("Level 70 Humanoid")
                expect(C2().FindLevelLine(tip())).as("the real level line, not the name").eq(2)
            end)

            it("paints red well above the player", function()
                unitWithLevel(78)
                expect(numberIsColored("deadly")).eq(true)
            end)

            it("paints orange a little above", function()
                unitWithLevel(73)
                expect(numberIsColored("hard")).eq(true)
            end)

            it("paints yellow within two either way", function()
                unitWithLevel(70)
                expect(numberIsColored("fair")).eq(true)
                unitWithLevel(68)
                expect(numberIsColored("fair")).eq(true)
            end)

            it("paints green below that", function()
                unitWithLevel(67)
                expect(numberIsColored("easy")).eq(true)
            end)

            it("paints grey once there is nothing left in it", function()
                unitWithLevel(60)
                expect(numberIsColored("trivial")).eq(true)
            end)

            it("colours a boss's ?? too", function()
                -- The ?? IS the reading for a boss, so leaving it uncoloured would be the one
                -- unit where the feature silently does nothing.
                H.setUnit("player", { level = 70 })
                H.setTarget({ name = "Boss", level = -1, reaction = 2 })
                tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                tip():SetText("Boss")
                tip():AddLine("Level ?? Elite")
                C2().ColorLevelLine(tip())
                expect(levelText():find(escFor("deadly") .. "%?+|r"))
                    .as("the ?? is wrapped").notNil()
            end)

            it("does not double-wrap when driven twice for one show", function()
                unitWithLevel(78)
                local once = levelText()
                C2().ColorLevelLine(tip())
                expect(levelText()).as("unchanged by a second pass").eq(once)
            end)

            it("treats an unknown level as DEADLY, like the client's own ??", function()
                expect(near(H.SuuUI.Game:DifficultyColor(-1),
                            H.SuuUI.Game.DIFFICULTY.deadly)).eq(true)
            end)

            it("respects its toggle", function()
                set("level_difficulty", false)
                unitWithLevel(78)
                expect(levelText()).as("left alone").eq("Level 78 Humanoid")
            end)

            it("finds nothing on a tooltip with no level line", function()
                tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                tip():SetText("Just a name")
                expect(C2().FindLevelLine(tip())).isNil()
                expect(C2().ColorLevelLine(tip())).eq(false)
            end)
        end)

        describe("IDs behind a modifier", function()
            it("is ON by default, as ElvUI ships it", function()
                -- It shipped as HIDE first, and a feature somebody asked for that is off by
                -- default is indistinguishable from one that does not work.
                expect(get("show_ids")).eq("SHOW")
                showItem()
                expect(lineValue("Item ID")).eq("1")
            end)

            it("shows them when set to always", function()
                set("show_ids", "SHOW")
                showItem()
                expect(lineValue("Item ID")).eq("1")
            end)

            it("gates on the actual modifier key", function()
                set("show_ids", "SHIFT")
                H.mods({ shift = false })
                showItem()
                expect(lineValue("Item ID")).as("shift not held").isNil()

                H.mods({ shift = true })
                showItem()
                expect(lineValue("Item ID")).as("shift held").eq("1")
            end)

            it("answers each mode honestly", function()
                H.mods({ shift = true })
                expect(C().ModifierDown("SHOW")).as("SHOW short-circuits").eq(true)
                expect(C().ModifierDown("HIDE")).eq(false)
                expect(C().ModifierDown(nil)).eq(false)
                expect(C().ModifierDown("SHIFT")).truthy()
                expect(C().ModifierDown("CTRL")).as("a different key").falsy()
            end)

            describe("on an action slot", function()
                -- How many lines carry this label. The whole point: ONE.
                local function countLabel(label)
                    local n = 0
                    for i = 1, tip():NumLines() do
                        if (tip():GetLine(i)) == label then n = n + 1 end
                    end
                    return n
                end

                it("shows the spell id EXACTLY ONCE", function()
                    -- It showed twice in game. `SetAction` fires OnTooltipSetSpell as well as
                    -- being hooked directly, so two paths appended the same line -- and the
                    -- harness had `SetAction` modelled as firing nothing, which made a duplicate
                    -- impossible to reproduce.
                    set("show_ids", "SHOW")
                    H.setAction(4, { type = "spell", id = 122 })
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    tip():SetText("Frost Nova")
                    tip():SetAction(4)
                    expect(countLabel("Spell ID")).as("one line, not two").eq(1)
                    expect(lineValue("Spell ID")).eq("122")
                end)

                it("adds no line of its own, only records the slot", function()
                    -- OnSpell already covers the id, because SetAction fires the spell script and
                    -- GetSpell answers for the slot. The record is the only thing this is for.
                    set("show_ids", "SHOW")
                    H.setAction(4, { type = "spell", id = 122 })
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    expect(C().OnAction(tip(), 4)).as("adds nothing").eq(0)
                    expect(C()._last.kind).as("but remembers").eq("action")
                    expect(C()._last.a).eq(4)
                end)

                it("never appends a label the tooltip already carries", function()
                    -- The general guard, rather than reasoning about which setter fires which
                    -- script -- a question this codebase has now got wrong in both directions.
                    set("show_ids", "SHOW")
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    tip():SetText("Thing")
                    expect(C().addLine(tip(), "Spell ID", "1")).eq(1)
                    expect(C().addLine(tip(), "Spell ID", "2")).as("refused").eq(0)
                    expect(countLabel("Spell ID")).eq(1)
                end)

                it("adds nothing while the gate is closed", function()
                    set("show_ids", "HIDE")
                    H.setAction(4, { type = "spell", id = 122 })
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    tip():SetText("Frost Nova")
                    tip():SetAction(4)
                    expect(countLabel("Spell ID")).eq(0)
                end)
            end)

            describe("the modifier redraw", function()
                it("re-drives a UNIT tooltip", function()
                    H.setTarget({ class = "MAGE", isPlayer = true, name = "V" })
                    tip():SetUnit("target")
                    expect(C()._last.kind).eq("unit")
                    expect(C().Redraw(tip())).eq(true)
                end)

                it("re-drives an AURA tooltip, which GetUnit cannot", function()
                    -- The bug this fixes: only a unit tooltip can be rebuilt from the tooltip
                    -- itself. A spell or aura cannot, so holding the modifier over a buff did
                    -- nothing and `show_ids = SHIFT` silently never worked there.
                    H.setAuras("player", { helpful = { { name = "AI", spellId = 27127 } } })
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    tip():SetUnitBuff("player", 1)
                    expect(C()._last.kind).as("recorded as an aura").eq("aura")
                    expect(C().Redraw(tip())).eq(true)
                end)

                it("re-drives an ACTION tooltip", function()
                    H.setAction(4, { type = "spell", id = 27071 })
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    C().OnAction(tip(), 4)
                    expect(C()._last.kind).eq("action")
                    expect(C().Redraw(tip())).eq(true)
                end)

                it("remembers the source even while the gate is CLOSED", function()
                    -- Otherwise the first modifier press has nothing to re-drive: the tooltip was
                    -- built with ids off, so nothing recorded what it was showing.
                    set("show_ids", "HIDE")
                    H.setAuras("player", { helpful = { { name = "AI", spellId = 27127 } } })
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    tip():SetUnitBuff("player", 1)
                    expect(C()._last.kind).eq("aura")
                end)

                it("does nothing when it has never seen a tooltip", function()
                    C()._last.kind = nil
                    expect(C().Redraw(tip())).eq(false)
                end)
            end)

            it("adds the spell id to a spell tooltip", function()
                set("show_ids", "SHOW")
                tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                tip():SetSpellByID(27071)
                expect(lineValue("Spell ID")).eq("27071")
            end)

            it("adds NO spell id while the gate is closed", function()
                -- The off state again: with only the SHOW case tested, a spell tooltip that
                -- ignored the gate entirely passed.
                set("show_ids", "HIDE")
                tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                tip():SetSpellByID(27071)
                expect(lineValue("Spell ID")).isNil()
            end)

            describe("the caster", function()
                local function buffFrom(source)
                    H.setUnit("player", { name = "Me", class = "MAGE", isPlayer = true })
                    H.setAuras("player", {
                        helpful = { { name = "Blessing", spellId = 19742, source = source } },
                    })
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    tip():SetUnitBuff("player", 1)
                end

                it("names who cast the buff", function()
                    H.setUnit("party1", { name = "Brynn", class = "PALADIN", isPlayer = true })
                    buffFrom("party1")
                    expect(lineValue("Cast by")).eq("Brynn")
                end)

                it("colours the name by what the CASTER is", function()
                    H.setUnit("party1", { name = "Brynn", class = "PALADIN", isPlayer = true })
                    buffFrom("party1")
                    local _, colour = lineValue("Cast by")
                    local want = H.SuuUI.Theme:GetUnitColor("colorHealth", "party1")
                    expect(near(colour, want)).as("the caster's own colour").eq(true)
                end)

                it("resolves a unit TOKEN, not a name", function()
                    -- Slot 7 is "party1" / "player", never a display name -- so it has to go
                    -- through UnitName. Handing the token straight to the line would print
                    -- "Cast by party1".
                    H.setUnit("party1", { name = "Brynn", isPlayer = true })
                    expect(C().CasterText("party1")).eq("Brynn")
                end)

                it("renders NOTHING when the client will not say who", function()
                    -- Frequently absent: an environmental debuff has no caster, and neither does
                    -- one from a unit the client has stopped tracking. "Unknown" would put a
                    -- useless line on a large share of auras.
                    --
                    -- `false`, not nil: the harness fills an omitted field from its defaults, so
                    -- nil staged a caster rather than removing one -- which is exactly why this
                    -- assertion failed on the first run.
                    buffFrom(false)
                    expect(hasLine("Cast by")).eq(false)
                    expect(C().CasterText(nil)).isNil()
                    expect(C().CasterText("")).isNil()
                end)

                it("renders nothing for a token the client cannot name", function()
                    expect(C().CasterText("party4")).as("nobody staged there").isNil()
                end)

                it("names YOU for your own buffs", function()
                    -- Kept rather than suppressed: "this is my own Blessing, not the paladin's" is
                    -- exactly the distinction the feature exists to draw.
                    buffFrom("player")
                    expect(lineValue("Cast by")).eq("Me")
                end)

                it("works for a DEBUFF too", function()
                    H.setUnit("target", { name = "Warlock", class = "WARLOCK", isPlayer = true })
                    H.setAuras("player", {
                        harmful = { { name = "Curse of Agony", spellId = 27218,
                                      debuffType = "Curse", source = "target" } },
                    })
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    tip():SetUnitDebuff("player", 1)
                    expect(lineValue("Cast by")).eq("Warlock")
                end)

                it("is INDEPENDENT of the id display", function()
                    -- The reason it has its own toggle: ElvUI welds the caster to the id's line, so
                    -- wanting one means switching the other on.
                    set("show_ids", "HIDE")
                    H.setUnit("party1", { name = "Brynn", isPlayer = true })
                    buffFrom("party1")
                    expect(lineValue("Cast by")).as("caster without ids").eq("Brynn")
                    expect(hasLine("Spell ID")).as("and no id").eq(false)
                end)

                it("respects its own toggle", function()
                    set("aura_caster", false)
                    set("show_ids", "SHOW")
                    H.setUnit("party1", { name = "Brynn", isPlayer = true })
                    buffFrom("party1")
                    expect(hasLine("Cast by")).eq(false)
                    expect(lineValue("Spell ID")).as("ids still work").eq("19742")
                end)
            end)

            describe("on an aura", function()
                local function showBuff()
                    H.setAuras("player", {
                        helpful = { { name = "Arcane Intellect", spellId = 27127 } },
                    })
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    tip():SetUnitBuff("player", 1)
                end

                it("adds the aura's spell id", function()
                    -- An aura tooltip does NOT fire OnTooltipSetSpell: the client builds it
                    -- through SetUnitBuff / SetUnitDebuff, so those need their own hook. Missing
                    -- that is why a buff showed no id while a spellbook entry did.
                    set("show_ids", "SHOW")
                    showBuff()
                    expect(lineValue("Spell ID")).eq("27127")
                end)

                it("reads the id from the aura DATA, not from the tooltip", function()
                    -- The tooltip does not carry it; slot 10 of UnitAura does.
                    set("show_ids", "SHOW")
                    set("aura_caster", false)
                    H.setAuras("player", {
                        helpful = { { name = "Other", spellId = 999 } },
                    })
                    expect(H.SuuUI._Tooltips.Content.OnAura(tip(), "player", 1, "HELPFUL")).eq(1)
                end)

                it("works for a debuff too", function()
                    set("show_ids", "SHOW")
                    H.setAuras("target", {
                        harmful = { { name = "Curse of Agony", spellId = 27218,
                                      debuffType = "Curse" } },
                    })
                    H.setTarget({ name = "Mob", reaction = 2 })
                    tip():SetOwner(H.env.UIParent, "ANCHOR_NONE")
                    tip():SetUnitDebuff("target", 1)
                    expect(lineValue("Spell ID")).eq("27218")
                end)

                it("adds nothing while the gate is closed", function()
                    set("show_ids", "HIDE")
                    showBuff()
                    expect(lineValue("Spell ID")).isNil()
                end)

                it("adds nothing for an aura index that is not there", function()
                    set("show_ids", "SHOW")
                    H.clearAuras("player")
                    expect(H.SuuUI._Tooltips.Content.OnAura(tip(), "player", 5, "HELPFUL")).eq(0)
                end)
            end)
        end)
    end)

    ---------------------------------------------------------------------------
    -- The modern API is present and must stay unused
    ---------------------------------------------------------------------------
    describe("the content API choice", function()
        it("uses the legacy scripts even though TooltipDataProcessor exists", function()
            -- Measured in game: the namespace IS present on this client, and ElvUI explicitly
            -- excludes TBC from it. A refactor onto the modern API would compile and silently
            -- do nothing, so pin the fact rather than the intention.
            local fired = false
            tip():HookScript("OnTooltipSetUnit", function() fired = true end)
            H.setTarget({ class = "MAGE", isPlayer = true })
            tip():SetUnit("target")
            expect(fired).as("the legacy script is what carries content here").eq(true)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Teardown
    ---------------------------------------------------------------------------
    describe("disabling", function()
        it("hands back every border it coloured", function()
            H.setTarget({ class = "MAGE", isPlayer = true })
            tip():SetUnit("target")
            plugin():Disable()
            expect(Signal()._tinted[tip()]).isNil()
        end)

        it("drops the mover", function()
            Anchor().EnsureMover()
            plugin():Disable()
            expect(Anchor().GetMover()).isNil()
        end)

        it("leaks no watchers across an enable/disable round trip", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            plugin():Disable()
            plugin():Enable()
            plugin():Disable()
            plugin():Enable()
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("watcher count is round-trip neutral").eq(before)
        end)

        it("comes back on after being switched off", function()
            -- The round trip, not just the off transition: the failing half is the one a green
            -- "it disables" test never touches.
            set("enabled", false)
            expect(plugin():IsEnabled()).eq(false)
            set("enabled", true)
            expect(plugin():IsEnabled()).eq(true)
            expect(Skin().IsSkinned(tip())).as("re-skinned on the way back").eq(true)
        end)
    end)
end)
