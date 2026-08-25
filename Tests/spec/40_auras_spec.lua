-- Aura bands on the unit frames: the behaviours that fail silently if they regress.
--
-- Geometry first, because the whole feature is placement: how many icons, on how many rows,
-- which side of the frame, and -- the one that has bitten this frame twice already -- whether
-- the frame's own bars stay where the player put them while a band grows around them.
local PLUGIN_ID = "unit_frames"

local function set(key, value)
    H.SuuUI.Settings:Set(PLUGIN_ID, key, value)
end

local function setting(key)
    return H.SuuUI.Settings:Get(PLUGIN_ID, key)
end

local function plugin()
    return H.SuuUI.Plugins:Get(PLUGIN_ID)
end

local function pf() return plugin()._playerFrame end
local function tf() return plugin()._targetFrame end
local function band(widget, kind) return widget._bands[kind] end

-- Builds n distinct buffs. Distinct icons so a spec can tell one slot from another, and a
-- duration only where the test is about timing.
local function buffs(n, opts)
    local out = {}
    for i = 1, n do
        out[i] = {
            name    = "Buff " .. i,
            icon    = "Interface\\Icons\\Spell_" .. i,
            count   = (opts and opts.count) or 0,
            spellId = 1000 + i,
            duration = opts and opts.duration or 0,
            expirationTime = opts and opts.expiration or 0,
        }
    end
    return out
end

-- The same, with a live timer expiring `left` seconds from the sandbox clock. Read from the
-- harness rather than calling GetTime, which is a sandbox global and not a spec-scope one.
local function timedBuffs(n, left)
    local now = require("harness.wow.state").clock
    return buffs(n, { duration = left, expiration = now + left })
end

-- Stages a mob as the target, with the announcement the client always sends alongside it.
-- Only the fields the frame needs to draw something; none of them is asserted.
local function targetMob(props)
    local p = { name = "Vale Moth", level = 20, reaction = 4,
                health = 50, healthMax = 100, power = 0, powerMax = 0 }
    for k, v in pairs(props or {}) do p[k] = v end
    return H.setTarget(p)
end

-- How many frames the client would call OnUpdate on this frame.
--
-- The band ticker is a bare, unnamed, unparented frame the band creates lazily, so nothing
-- in the spec can reach it by handle -- and the whole point of the design is that it is
-- absent, not merely idle. Counting the scripts the client would actually call is the same
-- evidence the client acts on, and it is what makes "one ticker for two bands" assertable.
-- Nothing else in a unit-frame spec registers one, so a delta of exactly 1 is the ticker.
local function tickerCount()
    local st = require("harness.wow.state")
    local n = 0
    for i = 1, #st.frames do
        local f = st.frames[i]
        if f.GetScript and f:GetScript("OnUpdate") then n = n + 1 end
    end
    return n
end

-- The seconds a readout is showing, parsed off the front of its text. Parsed rather than
-- string-compared so the assertion is about the number counting down and not about the
-- component's format string, which changes tier at 10s and at 60s.
local function readoutSeconds(icon)
    local text = icon._durationText:GetFrame():GetText() or ""
    return tonumber(text:match("^([%d%.]+)") or "")
end

local function durationColor(icon)
    local r, g, b, a = icon._durationText:GetFrame():GetTextColor()
    return { r, g, b, a }
end

-- Compares the RGB of two colours. Used to say "this is the warning colour" and "this is
-- not" without the spec having to name what the calm colour resolves to.
local function sameColor(a, b)
    for i = 1, 3 do
        if math.abs((a[i] or 0) - (b[i] or 0)) > 0.001 then return false end
    end
    return true
end

-- The icons a band currently has on screen, in layout order.
local function shownIcons(b)
    local out = {}
    for i = 1, b:GetCount() do out[#out + 1] = b._icons[i] end
    return out
end

describe("Plugins.UnitFrames – aura bands", function()
    before_each(function()
        local state = require("harness.wow.state")
        state.unitHealth    = 100
        state.unitHealthMax = 100
        state.unitPower     = 80
        state.unitPowerMax  = 100
        state.unitPowerType = 0
        state.unitLevel     = 42
        state.maxPlayerLevel = 60
        H.setup()
    end)

    describe("defaults", function()
        it("puts buffs above the frame and debuffs below", function()
            expect(setting("player_buffs_position")).eq("above")
            expect(setting("player_debuffs_position")).eq("below")
        end)

        it("starts with both bands empty and hidden", function()
            expect(band(pf(), "buffs"):GetCount()).eq(0)
            expect(band(pf(), "buffs"):GetContainer():IsShown())
                .as("an empty band claims no gap").falsy()
            expect(band(pf(), "buffs"):GetHeight()).eq(0)
        end)
    end)

    describe("reading the unit's auras", function()
        it("shows one icon per aura and hides the band when they go", function()
            H.setAuras("player", { helpful = buffs(3) })
            local b = band(pf(), "buffs")
            expect(b:GetCount()).as("three buffs staged").eq(3)
            expect(b:GetContainer():IsShown()).truthy()

            H.clearAuras("player")
            expect(b:GetCount()).eq(0)
            expect(b:GetContainer():IsShown()).falsy()
        end)

        it("keeps the icons and only hides the surplus when the count drops", function()
            H.setAuras("player", { helpful = buffs(4) })
            local b = band(pf(), "buffs")
            local fourth = b._icons[4]
            H.setAuras("player", { helpful = buffs(2) })
            expect(b:GetCount()).eq(2)
            expect(b._icons[4]).as("the icon is reused, not destroyed").eq(fourth)
            expect(fourth:IsShown()).as("surplus drops out of the layout").falsy()
        end)

        it("routes UNIT_AURA rather than needing a manual refresh", function()
            -- setAuras fires the event the client always sends; nothing else is called here.
            H.setAuras("player", { helpful = buffs(1) })
            expect(band(pf(), "buffs"):GetCount()).eq(1)
        end)

        it("reads the harmful list into the debuff band, not the buff band", function()
            H.setAuras("player", { harmful = buffs(2) })
            expect(band(pf(), "debuffs"):GetCount()).eq(2)
            expect(band(pf(), "buffs"):GetCount()).eq(0)
        end)
    end)

    describe("rows", function()
        it("lays one row left to right at the icon size", function()
            set("player_buffs_size", 24)
            H.setAuras("player", { helpful = buffs(3) })
            local icons = shownIcons(band(pf(), "buffs"))
            local a, b2, c = H.box(icons[1]), H.box(icons[2]), H.box(icons[3])
            expect(a.width).eq(24)
            expect(a.height).eq(24)
            expect(b2.left).as("second icon sits one gap right of the first")
                .near(a.left + 24 + H.token("spaceXxs"), 0.5)
            expect(c.left).gt(b2.left)
            H.expectNoOverlap({ icons[1], icons[2] })
        end)

        it("wraps onto a second row when the row would overflow the frame", function()
            -- A width that fits four icons and no more, so the fifth has to wrap.
            local size, gap = 24, H.token("spaceXxs")
            set("player_width", size * 4 + gap * 3)
            set("player_buffs_size", size)
            H.setAuras("player", { helpful = buffs(5) })

            local icons = shownIcons(band(pf(), "buffs"))
            local first, fifth = H.box(icons[1]), H.box(icons[5])
            expect(fifth.left).as("the fifth icon starts a new row").near(first.left, 0.5)
            -- H.box measures downward from the screen top, so a row further from the frame
            -- has the SMALLER top. This band is above the frame, so row two is up there.
            expect(fifth.top).as("and on the row beyond it").lt(first.top)
        end)

        it("reports a taller band once it has wrapped", function()
            local size, gap = 24, H.token("spaceXxs")
            set("player_width", size * 4 + gap * 3)
            set("player_buffs_size", size)
            local b = band(pf(), "buffs")

            H.setAuras("player", { helpful = buffs(4) })
            local oneRow = b:GetHeight()
            H.setAuras("player", { helpful = buffs(5) })
            expect(oneRow).eq(size)
            expect(b:GetHeight()).as("two rows plus the line gap").eq(size * 2 + gap)
        end)

        it("stacks an above band's rows away from the frame", function()
            -- Row one stays against the frame: a new row must extend the band's TOP, not
            -- push the first row up. Reversed line order is what makes that true.
            local size, gap = 24, H.token("spaceXxs")
            set("player_width", size * 4 + gap * 3)
            set("player_buffs_size", size)
            H.setAuras("player", { helpful = buffs(4) })
            local b = band(pf(), "buffs")
            local firstRowTop = H.box(b._icons[1]).top

            H.setAuras("player", { helpful = buffs(5) })
            expect(H.box(b._icons[1]).top)
                .as("row one does not move when a row is added above it")
                .near(firstRowTop, 0.5)
        end)
    end)

    describe("the frame grows around the bands", function()
        it("adds the band and its gap to the frame's height", function()
            local before = pf():GetFrame():GetHeight()
            H.setAuras("player", { helpful = buffs(2) })
            expect(pf():GetFrame():GetHeight())
                .near(before + 24 + H.token("spaceXs"), 0.5)
        end)

        it("reports the band in the core inset on the side it sits", function()
            -- Measured as a delta, because the frame already carries a band on the far side:
            -- the cast bar plugin attaches below by default, so `below` starts non-zero and
            -- an absolute assertion here would be asserting the cast bar's height.
            local above0, below0 = pf():GetCoreInset()
            H.setAuras("player", { helpful = buffs(2) })
            local above1, below1 = pf():GetCoreInset()
            local want = 24 + H.token("spaceXs")
            expect(above1 - above0).as("buffs default above").near(want, 0.5)
            expect(below1 - below0).as("and add nothing below").near(0, 0.5)

            set("player_buffs_position", "below")
            local above2, below2 = pf():GetCoreInset()
            expect(above2 - above0).as("moving them clears the inset above").near(0, 0.5)
            expect(below2 - below0).as("and adds it below").near(want, 0.5)
        end)

        it("leaves the health bar where it was when a band appears", function()
            -- The regression this frame has already shipped twice: the stored position
            -- resolves against the BOUNDING BOX, so a band growing outside the content moves
            -- the content unless the core inset compensates for it.
            local barTop = H.box(pf()._healthBar).top
            H.setAuras("player", { helpful = buffs(3) })
            expect(H.box(pf()._healthBar).top)
                .as("bars stay put while buffs appear above them").near(barTop, 0.5)

            H.setAuras("player", { harmful = buffs(3) })
            expect(H.box(pf()._healthBar).top)
                .as("and while debuffs appear below them").near(barTop, 0.5)
        end)

        it("leaves the content still under EVERY anchor family", function()
            -- The compensation shifts the stored offset by the inset, and which edge it
            -- shifts depends on the anchor's vertical family: TOP* pins the top, BOTTOM* the
            -- bottom, and LEFT/RIGHT/CENTER split the difference. The default position only
            -- exercises one of those three, and the client rewrites the anchor to TOPLEFT on
            -- every drag -- so a player who has moved their frame is on a different branch
            -- than the one the defaults cover.
            for _, anchor in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "BOTTOMLEFT", "BOTTOM",
                                      "BOTTOMRIGHT", "CENTER", "LEFT", "RIGHT" }) do
                H.setup()
                set("player_buffs_position", "above")
                set("player_debuffs_position", "below")
                set("player_position",
                    { point = anchor, relPoint = anchor, x = 120, y = -120 })
                H.clearAuras("player")
                local barTop = H.box(pf()._healthBar).top

                H.setAuras("player", { helpful = buffs(2), harmful = buffs(2) })
                expect(H.box(pf()._healthBar).top)
                    .as(anchor .. ": content must not move when bands appear")
                    .near(barTop, 0.5)
            end
        end)

        it("grows the bounding box outward rather than moving the content", function()
            -- The box is expected to change -- that is what "extend" means. What must not
            -- change is where the bars sit, which is the pair of assertions above.
            set("player_buffs_position", "above")
            H.clearAuras("player")
            local wrapTop = H.box(pf():GetFrame()).top
            H.setAuras("player", { helpful = buffs(2) })
            expect(H.box(pf():GetFrame()).top)
                .as("the box reaches further up the screen").lt(wrapTop)
        end)
    end)

    describe("placement", function()
        it("orders the column with buffs nearer the frame than debuffs", function()
            set("player_debuffs_position", "above")
            H.setAuras("player", { helpful = buffs(1), harmful = buffs(1) })
            local buffTop  = H.box(band(pf(), "buffs")._icons[1]).top
            local debuffTop = H.box(band(pf(), "debuffs")._icons[1]).top
            -- H.box measures downward from the screen top, so the band further OUT from the
            -- frame is the one with the smaller top.
            expect(debuffTop).as("debuffs sit outside the buffs").lt(buffTop)
        end)

        it("drops a hidden band out of the column entirely", function()
            H.setAuras("player", { helpful = buffs(2) })
            local withBand = pf():GetFrame():GetHeight()
            set("player_buffs_position", "hidden")
            expect(band(pf(), "buffs"):GetCount()).eq(0)
            expect(band(pf(), "buffs"):GetHeight()).eq(0)
            expect(pf():GetFrame():GetHeight()).lt(withBand)
        end)

        it("repopulates a band switched back on", function()
            set("player_buffs_position", "hidden")
            H.setAuras("player", { helpful = buffs(2) })
            expect(band(pf(), "buffs"):GetCount()).as("hidden reads nothing").eq(0)
            set("player_buffs_position", "above")
            expect(band(pf(), "buffs"):GetCount())
                .as("switching it on reads what is already there").eq(2)
        end)
    end)

    describe("icon content", function()
        it("carries the client's icon and stack count", function()
            H.setAuras("player", { helpful = {
                { name = "Stacked", icon = "Interface\\Icons\\Stack", count = 4, spellId = 7 },
            } })
            local icon = band(pf(), "buffs")._icons[1]
            expect(icon:GetIcon()).eq("Interface\\Icons\\Stack")
            expect(icon._countText:GetFrame():GetText()).eq("4")
        end)

        it("hides the stack readout for a non-stacking aura", function()
            -- The live client reports count = 0 for an aura that does not stack, so the
            -- readout has to test > 1 rather than >= 1 or every buff would show a "0".
            H.setAuras("player", { helpful = buffs(1) })
            expect(band(pf(), "buffs")._icons[1]._countText:IsShown()).falsy()
        end)

        it("paints a duration readout as soon as the aura arrives", function()
            -- The clock the sandbox's GetTime reads. Taken from the harness rather than
            -- called directly: GetTime is a sandbox global, not a spec-scope one.
            local now = require("harness.wow.state").clock
            H.setAuras("player", { helpful = {
                { name = "Timed", icon = "i", duration = 30, expirationTime = now + 30 },
            } })
            local icon = band(pf(), "buffs")._icons[1]
            expect(icon._durationText:IsShown())
                .as("no waiting for the next tick").truthy()
            expect(icon._durationText:GetFrame():GetText()).eq("30s")
        end)

        it("leaves a permanent aura with no readout and no ticker", function()
            H.setAuras("player", { helpful = buffs(1) })
            expect(band(pf(), "buffs")._icons[1]._durationText:IsShown()).falsy()
        end)
    end)

    describe("dispel type colouring", function()
        it("rings a debuff in its dispel colour", function()
            H.setAuras("player", { harmful = {
                { name = "Curse of Agony", icon = "i", debuffType = "Curse" },
            } })
            local want = H.SuuUI.Game:DebuffTypeColor("Curse")
            expect(band(pf(), "debuffs")._icons[1]._typeColor).deepEq(want)
        end)

        it("rings an UNTYPED debuff red, which is most of them", function()
            -- Fireball's DoT reports no dispel type in this client, and neither does any
            -- physical debuff. Red is the client's own "none" row, so this agrees with the
            -- default UI rather than inventing a colour.
            H.setAuras("player", { harmful = {
                { name = "Fireball", icon = "i" },
            } })
            local want = H.SuuUI.Game:UntypedDebuffColor()
            expect(band(pf(), "debuffs")._icons[1]._typeColor).deepEq(want)
            expect(want[1]).as("red, not the neutral ring").gt(0.5)
        end)

        it("does NOT ring a buff by type, even though the client reports one", function()
            -- Righteous Fury comes back as "Magic" from UnitAura. Colouring buffs by dispel
            -- type would put a blue ring around half a paladin's bar while telling the
            -- player nothing they can act on.
            H.setAuras("player", { helpful = {
                { name = "Righteous Fury", icon = "i", debuffType = "Magic" },
            } })
            expect(band(pf(), "buffs")._icons[1]._typeColor).isNil()
        end)

        it("rings a STEALABLE buff in its dispel colour", function()
            -- isStealable is the client's own verdict on whether a purge or spellsteal
            -- would land, computed per class and per unit -- which is exactly the question
            -- a buff border should answer.
            H.setAuras("player", { helpful = {
                { name = "Ice Barrier", icon = "i", debuffType = "Magic",
                  isStealable = true },
            } })
            local want = H.SuuUI.Game:DebuffTypeColor("Magic")
            expect(band(pf(), "buffs")._icons[1]._typeColor).deepEq(want)
        end)

        it("leaves a stealable buff with no dispel type on the neutral ring", function()
            H.setAuras("player", { helpful = {
                { name = "Odd", icon = "i", isStealable = true },
            } })
            expect(band(pf(), "buffs")._icons[1]._typeColor)
                .as("no type means nothing to name, and a buff is never red").isNil()
        end)

        it("drops the tint when a slot is reused for an unstealable buff", function()
            -- Icons are pooled, so slot 1 carries whatever the last aura left on it unless
            -- every update re-states the border.
            H.setAuras("player", { helpful = {
                { name = "Ice Barrier", icon = "i", debuffType = "Magic",
                  isStealable = true },
            } })
            expect(band(pf(), "buffs")._icons[1]._typeColor).notNil()
            H.setAuras("player", { helpful = {
                { name = "Blessing", icon = "i", debuffType = "Magic" },
            } })
            expect(band(pf(), "buffs")._icons[1]._typeColor).isNil()
        end)
    end)

    describe("tooltip", function()
        it("points the game tooltip at the hovered aura", function()
            H.setAuras("player", { helpful = buffs(3) })
            local icon = band(pf(), "buffs")._icons[2]
            H.hover(icon)

            local tip = H.getTooltipState()
            expect(tip).notNil()
            expect(tip.owner).as("owned by the icon hovered").eq(icon:GetFrame())
            expect(tip.aura.unit).eq("player")
            expect(tip.aura.index).as("the second aura, not the second icon").eq(2)
        end)

        it("asks about a debuff through the debuff method", function()
            H.setAuras("player", { harmful = buffs(1) })
            H.hover(band(pf(), "debuffs")._icons[1])
            expect(H.getTooltipState().aura.filter).eq("HARMFUL")
        end)

        it("hides the tooltip on leave", function()
            H.setAuras("player", { helpful = buffs(1) })
            local icon = band(pf(), "buffs")._icons[1]
            H.hover(icon)
            H.unhover(icon)
            expect(H.GameTooltip:IsShown()).falsy()
        end)
    end)

    describe("right-click cancel", function()
        it("cancels the player's own buff by its aura index", function()
            H.setAuras("player", { helpful = buffs(3) })
            H.resetCancelBuff()
            H.click(band(pf(), "buffs")._icons[3], "RightButton")
            local rec = H.getCancelBuff()
            expect(rec).notNil()
            expect(rec.unit).eq("player")
            expect(rec.index).eq(3)
        end)

        it("ignores a left click", function()
            H.setAuras("player", { helpful = buffs(1) })
            H.resetCancelBuff()
            H.click(band(pf(), "buffs")._icons[1], "LeftButton")
            expect(H.getCancelBuff()).isNil()
        end)

        it("never cancels a debuff", function()
            H.setAuras("player", { harmful = buffs(1) })
            H.resetCancelBuff()
            H.click(band(pf(), "debuffs")._icons[1], "RightButton")
            expect(H.getCancelBuff()).as("a debuff is not yours to cancel").isNil()
        end)
    end)

    describe("the target's bands", function()
        it("reads the target's own aura lists", function()
            targetMob()
            H.setAuras("target", { helpful = buffs(2), harmful = buffs(3) })
            expect(band(tf(), "buffs"):GetCount()).eq(2)
            expect(band(tf(), "debuffs"):GetCount()).eq(3)
        end)

        it("never reads the player's auras, and the player never reads the target's", function()
            targetMob()
            H.setAuras("target", { helpful = buffs(2) })
            H.setAuras("player", { helpful = buffs(5) })
            expect(band(tf(), "buffs"):GetCount())
                .as("the target keeps its own two").eq(2)
            expect(band(pf(), "buffs"):GetCount())
                .as("and the player its own five").eq(5)
            -- The reverse direction as well: UNIT_AURA names the unit it is about, and a
            -- band that ignored the name would re-read on the other unit's event.
            H.clearAuras("player")
            expect(band(tf(), "buffs"):GetCount())
                .as("the player losing every buff leaves the target's alone").eq(2)
        end)

        it("takes its placement from the target's own setting", function()
            targetMob()
            H.setAuras("target", { helpful = buffs(1) })
            H.setAuras("player", { helpful = buffs(1) })
            set("target_buffs_position", "below")

            expect(setting("player_buffs_position"))
                .as("the player's setting is untouched").eq("above")
            expect(band(tf(), "buffs"):GetCount()).eq(1)
            expect(H.box(band(tf(), "buffs")._icons[1]).top)
                .as("the target's band moved below its own bars")
                .gt(H.box(tf()._healthBar).top)
            expect(H.box(band(pf(), "buffs")._icons[1]).top)
                .as("the player's stayed above its own")
                .lt(H.box(pf()._healthBar).top)
        end)

        it("takes its icon size from the target's own setting", function()
            targetMob()
            H.setAuras("target", { helpful = buffs(1) })
            H.setAuras("player", { helpful = buffs(1) })
            set("target_buffs_size", 32)
            expect(band(tf(), "buffs"):GetCount()).eq(1)
            expect(H.box(band(tf(), "buffs")._icons[1]).width).eq(32)
            expect(H.box(band(pf(), "buffs")._icons[1]).width)
                .as("the player's icons keep their own size")
                .eq(setting("player_buffs_size"))
        end)

        it("stays empty while nothing is targeted", function()
            -- No target staged, so the client answers nil for every index -- the state a
            -- target frame spends most of its life in.
            H.setAuras("target", { helpful = buffs(3), harmful = buffs(3) })
            expect(band(tf(), "buffs"):GetCount()).eq(0)
            expect(band(tf(), "debuffs"):GetCount()).eq(0)
            expect(band(tf(), "buffs"):GetContainer():IsShown()).falsy()
            expect(band(tf(), "buffs"):GetHeight()).eq(0)
        end)

        it("empties the bands when the target is lost", function()
            targetMob()
            H.setAuras("target", { helpful = buffs(2), harmful = buffs(1) })
            expect(band(tf(), "buffs"):GetCount()).eq(2)

            H.setTarget(nil)
            -- Nothing fires UNIT_AURA for a unit that stopped existing, so the target
            -- change is the only announcement -- and the frame's own repaint is skipped on
            -- that path precisely because the unit is now absent.
            expect(band(tf(), "buffs"):GetCount())
                .as("no icons left describing a unit that is gone").eq(0)
            expect(band(tf(), "debuffs"):GetCount()).eq(0)
            expect(band(tf(), "buffs"):GetHeight())
                .as("and no height claimed for them").eq(0)
        end)

        it("drops the lost target out of the shared ticker", function()
            local base = tickerCount()
            targetMob()
            H.setAuras("target", { helpful = timedBuffs(2, 30) })
            expect(tickerCount() - base).as("a timed aura registers the ticker").eq(1)

            H.setTarget(nil)
            expect(tickerCount())
                .as("a dropped target must not go on counting down forever").eq(base)
        end)

        it("repopulates on the next target with no manual refresh", function()
            targetMob()
            H.setAuras("target", { helpful = buffs(2) })
            H.setTarget(nil)
            expect(band(tf(), "buffs"):GetCount()).eq(0)

            -- PLAYER_TARGET_CHANGED is the only thing that fires here: the aura list for
            -- the token never moved, so a frame waiting for UNIT_AURA would stay empty.
            targetMob({ name = "Vale Moth II" })
            expect(band(tf(), "buffs"):GetCount()).eq(2)
            expect(band(tf(), "buffs"):GetContainer():IsShown()).truthy()
        end)
    end)

    describe("the duration ticker", function()
        it("counts the readout down", function()
            H.setAuras("player", { helpful = timedBuffs(1, 30) })
            local icon = band(pf(), "buffs")._icons[1]
            expect(readoutSeconds(icon)).as("painted on arrival").near(30, 0.2)

            H.tick(10)
            expect(readoutSeconds(icon)).near(20, 0.2)
            H.tick(10)
            expect(readoutSeconds(icon)).near(10, 0.2)
        end)

        it("crosses into colorWarning under five seconds", function()
            H.setAuras("player", { helpful = timedBuffs(1, 30) })
            local icon = band(pf(), "buffs")._icons[1]
            local warning = H.token("colorWarning")
            expect(sameColor(durationColor(icon), warning))
                .as("not warning while there is time left").falsy()

            H.tick(26)
            expect(readoutSeconds(icon)).near(4, 0.2)
            expect(sameColor(durationColor(icon), warning))
                .as("an expiring aura reads at a glance").truthy()
        end)

        it("clears the readout when the aura expires", function()
            H.setAuras("player", { helpful = timedBuffs(1, 5) })
            local icon = band(pf(), "buffs")._icons[1]
            expect(icon._durationText:IsShown()).truthy()

            H.tick(6)
            expect(icon._durationText:IsShown())
                .as("nothing left to count").falsy()
        end)

        it("registers ONE ticker for two bands with timers", function()
            local base = tickerCount()
            H.setAuras("player", { helpful = timedBuffs(2, 30), harmful = timedBuffs(1, 20) })
            expect(band(pf(), "buffs"):GetCount()).eq(2)
            expect(band(pf(), "debuffs"):GetCount()).eq(1)
            expect(tickerCount() - base)
                .as("one shared OnUpdate, not one per band").eq(1)
        end)

        it("keeps ticking while the other band still has a timer", function()
            local base = tickerCount()
            H.setAuras("player", { helpful = timedBuffs(1, 30), harmful = timedBuffs(1, 20) })
            H.setAuras("player", { helpful = buffs(1), harmful = timedBuffs(1, 20) })
            expect(tickerCount() - base)
                .as("one band leaving the ticker does not stop the other").eq(1)
        end)

        it("unregisters the ticker once only permanent auras are left", function()
            local base = tickerCount()
            H.setAuras("player", { helpful = timedBuffs(1, 30) })
            expect(tickerCount() - base).eq(1)

            -- A permanent aura reports duration 0. A bar of paladin blessings must cost no
            -- ticks at all -- a permanently registered OnUpdate is the cost this design
            -- exists to avoid.
            H.setAuras("player", { helpful = buffs(3) })
            expect(band(pf(), "buffs"):GetCount()).eq(3)
            expect(tickerCount()).as("nothing timed on screen, nothing ticking").eq(base)
        end)

        it("unregisters the ticker when the band empties", function()
            local base = tickerCount()
            H.setAuras("player", { helpful = timedBuffs(2, 30) })
            expect(tickerCount() - base).eq(1)
            H.clearAuras("player")
            expect(tickerCount()).eq(base)
        end)

        it("takes the ticker down with the frame", function()
            local base = tickerCount()
            H.setAuras("player", { helpful = timedBuffs(2, 30) })
            expect(tickerCount() - base).eq(1)
            pf():Destroy()
            expect(tickerCount())
                .as("a destroyed frame leaves nothing ticking").eq(base)
        end)
    end)

    describe("placement combinations", function()
        local POSITIONS = { "above", "below", "hidden" }

        -- Asserts one band is where the setting says, and reports its top so the caller can
        -- compare the two bands against each other. Nil for a hidden band, which has no top.
        local function checkSide(kind, pos, barTop)
            local b = band(pf(), kind)
            if pos == "hidden" then
                expect(b:GetCount()).as(kind .. " hidden reads nothing").eq(0)
                expect(b:GetContainer():IsShown())
                    .as(kind .. " hidden claims no row").falsy()
                expect(b:GetHeight()).as(kind .. " hidden claims no height").eq(0)
                return nil
            end
            expect(b:GetCount()).as(kind .. " on screen").eq(1)
            local top = H.box(b._icons[1]).top
            -- H.box measures DOWNWARD from the screen top, so above the bars is the smaller
            -- number and below them the larger one.
            if pos == "above" then
                expect(top).as(kind .. " above the bars").lt(barTop)
            else
                expect(top).as(kind .. " below the bars").gt(barTop)
            end
            return top
        end

        for _, buffPos in ipairs(POSITIONS) do
            for _, debuffPos in ipairs(POSITIONS) do
                it("buffs " .. buffPos .. ", debuffs " .. debuffPos, function()
                    set("player_buffs_position", buffPos)
                    set("player_debuffs_position", debuffPos)
                    H.setAuras("player", { helpful = buffs(1), harmful = buffs(1) })

                    local barTop = H.box(pf()._healthBar).top
                    local buffTop   = checkSide("buffs", buffPos, barTop)
                    local debuffTop = checkSide("debuffs", debuffPos, barTop)

                    -- Both on one side: buffs are the inner band, because that is where the
                    -- player asked for them.
                    if buffTop and debuffTop and buffPos == debuffPos then
                        if buffPos == "above" then
                            expect(debuffTop)
                                .as("debuffs sit outside the buffs above").lt(buffTop)
                        else
                            expect(debuffTop)
                                .as("debuffs sit outside the buffs below").gt(buffTop)
                        end
                    end

                    -- The cast bar plugin attaches below by default, and a cast bar is a
                    -- bar: it belongs against the frame's own bars, inside either aura band.
                    local slotTop = H.box(pf()._slotBelow).top
                    expect(pf()._slotBelow:IsShown())
                        .as("the attach band below is populated by default").truthy()
                    if buffPos == "below" then
                        expect(slotTop)
                            .as("the cast bar stays nearer the frame than the buffs")
                            .lt(buffTop)
                    end
                    if debuffPos == "below" then
                        expect(slotTop)
                            .as("the cast bar stays nearer the frame than the debuffs")
                            .lt(debuffTop)
                    end
                end)
            end
        end

        it("gives the frame back every band when both are hidden", function()
            local bare = pf():GetFrame():GetHeight()
            H.setAuras("player", { helpful = buffs(2), harmful = buffs(2) })
            expect(pf():GetFrame():GetHeight()).gt(bare)
            set("player_buffs_position", "hidden")
            set("player_debuffs_position", "hidden")
            expect(pf():GetFrame():GetHeight())
                .as("two hidden bands leave the frame exactly as it was")
                .near(bare, 0.5)
        end)
    end)

    describe("re-flow", function()
        it("moves icons onto more rows as the frame narrows, and back as it widens", function()
            local size, gap = 24, H.token("spaceXxs")
            set("player_buffs_size", size)
            set("player_width", size * 5 + gap * 4)
            H.setAuras("player", { helpful = buffs(5) })
            local b = band(pf(), "buffs")
            local wideBand, wideFrame = b:GetHeight(), pf():GetFrame():GetHeight()
            expect(wideBand).as("five icons fit one row at this width").eq(size)

            set("player_width", size * 3 + gap * 2)
            expect(b:GetHeight()).as("two rows once only three fit").eq(size * 2 + gap)
            expect(H.box(b._icons[4]).left)
                .as("row two starts back at the left edge")
                .near(H.box(b._icons[1]).left, 0.5)
            expect(pf():GetFrame():GetHeight())
                .as("the frame grows by exactly the row the band gained")
                .near(wideFrame + size + gap, 0.5)

            set("player_width", size * 5 + gap * 4)
            expect(b:GetHeight()).as("widening collapses them back").eq(wideBand)
            expect(pf():GetFrame():GetHeight())
                .as("and the frame gives the row back").near(wideFrame, 0.5)
        end)

        it("re-flows on the icon size setting too", function()
            local size, gap = 24, H.token("spaceXxs")
            set("player_buffs_size", size)
            set("player_width", size * 5 + gap * 4)
            H.setAuras("player", { helpful = buffs(5) })
            local b = band(pf(), "buffs")
            local oneRowFrame = pf():GetFrame():GetHeight()

            set("player_buffs_size", 40)
            expect(H.box(b._icons[1]).width).as("the icons follow the slider").eq(40)
            expect(b:GetHeight()).as("bigger icons need a second row").eq(40 * 2 + gap)
            expect(pf():GetFrame():GetHeight())
                .as("and the frame follows the band")
                .near(oneRowFrame - size + (40 * 2 + gap), 0.5)
        end)
    end)

    describe("a below band's rows", function()
        it("lays row one against the frame and grows away downward", function()
            local size, gap = 24, H.token("spaceXxs")
            set("player_width", size * 4 + gap * 3)
            set("player_debuffs_size", size)
            H.setAuras("player", { harmful = buffs(4) })
            local b = band(pf(), "debuffs")
            local rowOne = H.box(b._icons[1]).top

            H.setAuras("player", { harmful = buffs(5) })
            expect(H.box(b._icons[1]).top)
                .as("row one does not move when a row is added below it")
                .near(rowOne, 0.5)
            -- The mirror of the above band's reversed order: below the frame the row further
            -- OUT is the one with the LARGER top, so row two lands one pitch down.
            expect(H.box(b._icons[5]).top)
                .as("the new row sits one pitch further from the frame")
                .near(rowOne + size + gap, 0.5)
        end)

        it("mirrors the above band, which grows upward instead", function()
            local size, gap = 24, H.token("spaceXxs")
            set("player_width", size * 4 + gap * 3)
            set("player_buffs_size", size)
            H.setAuras("player", { helpful = buffs(4) })
            local b = band(pf(), "buffs")
            local rowOne = H.box(b._icons[1]).top

            H.setAuras("player", { helpful = buffs(5) })
            expect(H.box(b._icons[5]).top)
                .as("the above band's new row goes one pitch the other way")
                .near(rowOne - size - gap, 0.5)
        end)
    end)

    describe("watcher hygiene", function()
        it("a placement change registers no new watchers", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            set("player_buffs_position", "below")
            set("player_debuffs_position", "above")
            set("player_buffs_position", "hidden")
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("re-seating the column re-uses the watchers it already has").eq(before)
        end)

        it("a destroyed frame leaks none", function()
            local widget = pf()
            local owner = widget._themeId
            local before = H.SuuUI.Settings:GetWatcherCount()
            H.setAuras("player", { helpful = buffs(2), harmful = buffs(2) })
            widget:Destroy()

            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("the frame's watchers went with it").lt(before)
            -- Named rather than merely counted: Unwatch answers how many it removed, so zero
            -- for each band owner is the precise statement that none survived.
            for _, key in ipairs({ "buffs_position", "buffs_size",
                                   "debuffs_position", "debuffs_size" }) do
                expect(H.SuuUI.Settings:Unwatch(owner .. "_" .. key))
                    .as("no watcher left under " .. key).eq(0)
            end
            -- And the consequence a survivor would have: every band callback indexes
            -- self._bands, which Destroy nils, so a leaked watcher throws on the next write
            -- into a profile rather than failing quietly.
            expect(function()
                set("player_buffs_position", "below")
                set("player_buffs_size", 32)
            end).notThrows()
        end)
    end)

    describe("profile switch", function()
        it("re-places the bands from the new profile's values", function()
            -- Created BEFORE the edit, so it holds the schema defaults: a profile created
            -- afterwards starts as a copy of the edited one and would prove nothing.
            H.SuuUI.Profiles:Create("Raid")
            H.setAuras("player", { helpful = buffs(1) })
            set("player_buffs_position", "below")
            expect(H.box(band(pf(), "buffs")._icons[1]).top)
                .gt(H.box(pf()._healthBar).top)

            H.SuuUI.Profiles:SetActive("Raid")
            expect(setting("player_buffs_position"))
                .as("the new profile's own value").eq("above")
            expect(H.box(band(pf(), "buffs")._icons[1]).top)
                .as("and the band actually moved there, unasked")
                .lt(H.box(pf()._healthBar).top)

            H.SuuUI.Profiles:SetActive("Default")
            expect(H.box(band(pf(), "buffs")._icons[1]).top)
                .as("switching back restores the other profile's placement")
                .gt(H.box(pf()._healthBar).top)
        end)

        it("re-derives the icon size from the new profile", function()
            H.SuuUI.Profiles:Create("Raid")
            H.setAuras("player", { helpful = buffs(1) })
            set("player_buffs_size", 40)
            expect(H.box(band(pf(), "buffs")._icons[1]).width).eq(40)

            H.SuuUI.Profiles:SetActive("Raid")
            expect(setting("player_buffs_size")).as("the profile's own size").neq(40)
            expect(H.box(band(pf(), "buffs")._icons[1]).width)
                .as("the icons followed it").eq(setting("player_buffs_size"))
        end)
    end)

    describe("theme change", function()
        -- A user theme, because a built-in cannot be edited. Editing a token is what emits
        -- SUUUI_THEME_CHANGED, which is the band's only announcement that spacing moved.
        local function userTheme()
            H.T:CreateUserTheme("SpecTheme", H.T:GetActive())
            H.T:SetActive("SpecTheme")
        end

        it("re-derives the icon gap from spaceXxs", function()
            set("player_buffs_size", 24)
            H.setAuras("player", { helpful = buffs(2) })
            local b = band(pf(), "buffs")
            local function measuredGap()
                local one, two = H.box(b._icons[1]), H.box(b._icons[2])
                return two.left - (one.left + one.width)
            end
            expect(measuredGap()).as("the gap is the token, not a literal")
                .near(H.token("spaceXxs"), 0.5)

            userTheme()
            local was = H.token("spaceXxs")
            H.T:SetUserToken("SpecTheme", "spaceXxs", was + 7)
            expect(H.token("spaceXxs")).as("the token really moved").eq(was + 7)
            expect(measuredGap()).as("and the band re-spaced to whatever it now says")
                .near(H.token("spaceXxs"), 0.5)
        end)

        it("re-derives the row pitch from the same token", function()
            -- One token drives both axes: not passing lineGap leaves it tracking gap, so a
            -- wrapped band's rows move with its columns.
            local size = 24
            set("player_buffs_size", size)
            -- Wide enough for two icons at either gap and never for three, so the row COUNT
            -- is fixed and only the pitch is under test.
            set("player_width", size * 2 + 10)
            H.setAuras("player", { helpful = buffs(4) })
            local b = band(pf(), "buffs")
            expect(b:GetHeight()).eq(size * 2 + H.token("spaceXxs"))

            userTheme()
            H.T:SetUserToken("SpecTheme", "spaceXxs", 8)
            expect(b:GetCount()).as("still four icons on two rows").eq(4)
            expect(b:GetHeight()).as("two rows at the new pitch")
                .eq(size * 2 + H.token("spaceXxs"))
        end)
    end)

    describe("an empty band claims no gap", function()
        it("costs the frame exactly its own height plus one column gap", function()
            local size, gap = 24, H.token("spaceXxs")
            set("player_width", size * 4 + gap * 3)
            set("player_buffs_size", size)
            local b = band(pf(), "buffs")
            local bare = pf():GetFrame():GetHeight()

            -- Two rows deliberately: a one-row band would pass this even if the frame were
            -- adding a fixed band height rather than the band's measured one.
            H.setAuras("player", { helpful = buffs(5) })
            expect(b:GetHeight()).eq(size * 2 + gap)
            expect(pf():GetFrame():GetHeight() - bare)
                .as("the band's height plus one column gap, and nothing else")
                .near(b:GetHeight() + H.token("spaceXs"), 0.5)

            H.clearAuras("player")
            expect(b:GetHeight()).eq(0)
            expect(pf():GetFrame():GetHeight())
                .as("an emptied band gives the gap back too").near(bare, 0.5)
        end)
    end)

    describe("teardown", function()
        it("destroys both bands with the frame", function()
            H.setAuras("player", { helpful = buffs(2) })
            local widget = pf()
            local container = band(widget, "buffs"):GetContainer()
            widget:Destroy()
            expect(widget._bands).isNil()
            expect(container:GetFrame():IsShown()).falsy()
        end)
    end)
end)
