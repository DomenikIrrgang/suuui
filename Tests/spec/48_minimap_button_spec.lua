local H = require("harness")

-- Every test here goes through this rather than H.setup directly.
--
-- The addon-button tray collects every LibDBIcon button off the minimap ring, and SuuUI's own
-- launcher is one of them -- deliberately, because that is what the tray is FOR. With the tray
-- enabled this button has no ring position left to assert, so these tests would be measuring
-- which plugin reached it first instead of measuring the launcher. Turned off here; the
-- interaction itself is asserted in 50_addon_buttons_spec.lua, where it belongs.
local function setup(opts)
    H.setup(opts)
    pcall(function() H.SuuUI.Settings:Set("addon_buttons", "enabled", false) end)
end

-- The MinimapButton plugin: SuuUI's launcher, owned by LibDBIcon-1.0 rather than
-- hand-rolled. So this file asserts the SEAM between the plugin and two third-party
-- libraries, which is where all of its behaviour lives — the plugin itself creates no
-- frames at all.
--
-- 05_window_uiroot_spec already covers the surface facts: that a button is registered
-- under "SuuUI", that it is a square child of Minimap sitting on the ring, and that a left
-- click opens the settings window while a right click enters edit mode. This file covers
-- the parts a working button does not prove: the schema, the enable/disable cycle across a
-- library with no unregister, the lock, the tooltip's content and its colours, where a
-- dragged position is persisted, watcher hygiene, and what happens on a client that has no
-- LibDBIcon at all.
--
-- Two reaches into internals are deliberate and marked at their helper: the harness records
-- what a tooltip was HANDED rather than rendering it (so a colour has to be read off the
-- record, since GetLine answers text only), and it models no drag input path (so the client's
-- own drag scripts are fired directly). Both are noted where they happen rather than hidden.

local PLUGIN_ID = "minimap_button"

local function plugin()    return H.SuuUI.Plugins:Get(PLUGIN_ID) end
local function name()      return H.SuuUI._MinimapButton.ICON_NAME end
local function button()    return H.SuuUI._MinimapButton.GetButton() end
local function lib()       return H.env.LibStub("LibDBIcon-1.0") end
local function ldb()       return H.env.LibStub("LibDataBroker-1.1") end
local function obj()       return ldb():GetDataObjectByName(name()) end
local function get(key)    return H.SuuUI.Settings:Get(PLUGIN_ID, key) end
local function set(key, v) return H.SuuUI.Settings:Set(PLUGIN_ID, key, v) end

--- The LibDBIcon position store: the plugin's own profile sub-table, which the library
--- mutates in place during a drag.
local function iconStore() return plugin():GetProfile().icon end

-- Lines recorded on LibDBIcon's OWN tooltip (LibDBIconTooltip, not the shared GameTooltip).
-- The harness records what a tooltip was handed and renders nothing, and GetLine answers the
-- text alone, so the per-line colour has to be read off the record — the same shape of reach
-- the aura specs make through H.getTooltipState.
local function lines() return lib().tooltip._lines or {} end

local CHANNELS = { "r", "g", "b" }

-- Asserts one tooltip line's colour resolves to a theme token rather than a literal. Only
-- three channels: AddLine takes r, g, b and no alpha, so H.expectTokenColor (which compares
-- all four) would be comparing a missing alpha against the token's.
local function expectLineColor(i, tokenKey)
    local rec  = lines()[i]
    local want = H.token(tokenKey)
    expect(rec).as("tooltip line " .. i .. " was recorded").notNil()
    for c = 1, 3 do
        expect(rec[CHANNELS[c]])
            .as("line " .. i .. " channel " .. CHANNELS[c] .. " comes from " .. tokenKey)
            .near(want[c], 0.001)
    end
end

local function hoverButton()
    H.hover(button())
    return lib().tooltip
end

-- A drag, as the client delivers one: OnDragStart, then a sample of the cursor on every
-- frame while the button is held, then OnDragStop. The harness models no drag input path
-- (H.dragResize drives a sizing grip and nothing else), so the scripts are fired the way the
-- client fires them. Stated once here rather than at each call site.
local function drag(toX, toY)
    local btn = button()
    H.cursor(toX, toY, H.Minimap)
    btn:_fire("OnDragStart", "LeftButton")
    H.tick()
    btn:_fire("OnDragStop", "LeftButton")
end

-- The angle LibDBIcon derives from a cursor offset, computed the way the library does so the
-- expectation moves with it rather than being a number typed in.
local function angleOf(dx, dy)
    return math.deg((math.atan2 or math.atan)(dy, dx)) % 360
end

-- Debug lines the addon printed. SuuUI.Debug is a no-op unless the addon was loaded in debug
-- mode, so any test reading this re-boots with it on. Plain find: "LibDBIcon-1.0" contains a
-- pattern character.
local function logMatching(needle)
    local hits = 0
    for _, line in ipairs(H.debugLog()) do
        if line:lower():find(needle:lower(), 1, true) then hits = hits + 1 end
    end
    return hits
end

describe("Plugins.MinimapButton – the LibDBIcon launcher", function()
    before_each(function() setup() end)

    -----------------------------------------------------------------------------
    describe("the settings schema", function()
        it("declares exactly the two documented toggles", function()
            local schema = H.SuuUI.Settings:GetSchema(PLUGIN_ID)
            expect(schema).notNil()
            expect(#schema).as("two keys and nothing else").eq(2)
            expect(schema[1]).deepEq({
                key = "enabled", label = "Show Minimap Button", type = "toggle",
                default = true,
            })
            expect(schema[2]).deepEq({
                key = "locked", label = "Lock Position", type = "toggle",
                default = false,
            })
        end)

        it("answers each declared default through the registry", function()
            for _, entry in ipairs(H.SuuUI.Settings:GetSchema(PLUGIN_ID)) do
                expect(get(entry.key)).as(entry.key .. " reads its schema default")
                    .eq(entry.default)
            end
        end)

        it("registers the keys under the plugin id, not the launcher name", function()
            -- The launcher name is a player-facing string other addons show; it is not a
            -- settings namespace, and using it as one would silently store nothing.
            expect(H.SuuUI.Settings:GetSchema(name())).isNil()
            expect(H.SuuUI.Settings:Get(name(), "enabled")).isNil()
        end)
    end)

    -----------------------------------------------------------------------------
    describe("coming up after login", function()
        it("initialises and enables itself, with a visible button", function()
            expect(H.SuuUI.Plugins:IsInitialised(PLUGIN_ID)).eq(true)
            expect(plugin():IsEnabled()).eq(true)

            local btn = button()
            expect(btn).as("GetButton answers the live button").notNil()
            expect(btn).as("and it is the one LibDBIcon holds")
                .eq(lib():GetMinimapButton(name()))
            expect(btn:IsShown()).eq(true)
            expect(btn:IsVisible())
                .as("visible, not merely shown under a hidden parent").eq(true)
        end)

        it("is known by the addon's name rather than by the plugin id", function()
            -- Collectors and LDB displays show this string to the player, so it is the
            -- addon's name; the plugin id is an internal key and the two must not be
            -- conflated.
            expect(name()).neq(plugin().id)
            expect(ldb():GetNameByDataObject(obj()))
                .as("LDB files the data object under the same name").eq(name())
            expect(lib():GetButtonList())
                .as("one button, under that name").deepEq({ name() })
        end)

        it("publishes a launcher with a real icon, not a bare data source", function()
            local o = obj()
            expect(o).as("the data object exists").notNil()
            expect(o.type).as("a launcher, so LDB displays render it as a button")
                .eq("launcher")
            expect(type(o.icon)).eq("string")
            expect(#o.icon).as("with a non-empty texture path").gt(0)
            expect(button().icon:GetTexture())
                .as("and the minimap button paints that exact texture").eq(o.icon)
            expect(type(o.OnClick)).eq("function")
            expect(type(o.OnTooltipShow)).eq("function")
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the enabled toggle", function()
        it("hides the button when switched off, without unregistering it", function()
            local btn = button()
            set("enabled", false)
            expect(plugin():IsEnabled()).as("the watcher took the plugin down").eq(false)
            expect(btn:IsShown()).as("Hide IS the teardown here").eq(false)
            expect(lib():IsRegistered(name()))
                .as("LibDBIcon has no unregister, so it stays registered").eq(true)
            expect(lib():GetMinimapButton(name()))
                .as("and keeps the same button object").eq(btn)
        end)

        it("re-shows the SAME button when switched on again", function()
            local btn = button()
            set("enabled", false)
            set("enabled", true)
            expect(button()).as("the identical object, not a replacement").eq(btn)
            expect(btn:IsShown()).eq(true)
            expect(lib():GetButtonList()).as("still exactly one button").deepEq({ name() })
        end)

        it("survives three round trips without a second registration", function()
            -- A second lib:Register raises ("already registered"), and a second
            -- NewDataObject answers nil — both of which Plugin:Enable's pcall would
            -- swallow, leaving a button that silently stops coming back. The log is what
            -- makes either visible.
            setup({ debug = true })
            local btn, o = button(), obj()
            for _ = 1, 3 do
                set("enabled", false)
                set("enabled", true)
            end
            expect(button()).as("the same button throughout").eq(btn)
            expect(logMatching("Plugin onEnable error"))
                .as("no swallowed error on any of the three enables").eq(0)
            expect(logMatching("unavailable"))
                .as("and the library was found every time").eq(0)
            expect(btn:IsShown()).eq(true)
            expect(obj()).as("and the same data object, built once").eq(o)
        end)

        it("leaves the lock state and the store alone, so a re-enable resumes", function()
            -- Teardown is one Hide and nothing else. Anything it changed on the way down —
            -- the lock, the persisted angle, the store's identity — would come back as a
            -- setting the player never wrote.
            local mx, my = H.Minimap:GetCenter()
            drag(mx + 40, my + 40)
            local store, pos = iconStore(), iconStore().minimapPos

            set("enabled", false)
            expect(iconStore()).as("the store is not rebuilt by teardown").eq(store)
            expect(iconStore().minimapPos)
                .as("nor is the dragged angle discarded").near(pos, 0.001)
            expect(get("locked")).as("and the lock setting is untouched").eq(false)

            set("enabled", true)
            expect(button():GetScript("OnDragStart"))
                .as("so the button comes back draggable, as the setting says").notNil()
        end)

        it("seeds LibDBIcon's own hide mirror from the setting", function()
            -- LibDBIcon keeps its own `hide` flag and reads it whenever it refreshes and on
            -- the next login. Visibility has one source of truth — the `enabled` setting —
            -- so the enable path writes the mirror rather than persisting a second copy.
            -- Refresh is the library's own reader, which is what makes the write observable.
            expect(iconStore().hide).as("seeded false while the plugin is enabled").eq(false)
            lib():Refresh(name())
            expect(button():IsShown())
                .as("a refresh from the mirror leaves the button visible").eq(true)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("locking the position", function()
        it("comes up draggable, matching the stored default", function()
            expect(get("locked")).eq(false)
            expect(button():GetScript("OnDragStart"))
                .as("the drag handler is installed while unlocked").notNil()
            expect(button():GetScript("OnDragStop")).notNil()
        end)

        it("takes the drag handlers away when locked", function()
            set("locked", true)
            expect(button():GetScript("OnDragStart")).isNil()
            expect(button():GetScript("OnDragStop")).isNil()
            expect(button().db.lock)
                .as("and LibDBIcon records the lock in the store it was handed").eq(true)
        end)

        it("gives them back when unlocked", function()
            set("locked", true)
            set("locked", false)
            expect(button():GetScript("OnDragStart")).notNil()
            expect(button():GetScript("OnDragStop")).notNil()
            expect(button().db.lock).as("Unlock clears the flag").isNil()
        end)

        it("cannot be moved while locked", function()
            set("locked", true)
            local btn = button()
            local bx, by = btn:GetCenter()
            local mx, my = H.Minimap:GetCenter()
            drag(mx + 40, my + 40)
            expect(iconStore().minimapPos)
                .as("no drag handler ran, so no angle was persisted").isNil()
            expect(btn:GetCenter()).as("and the button did not move on x").near(bx, 0.001)
            expect(select(2, btn:GetCenter())).as("nor on y").near(by, 0.001)
        end)

        it("applies a stored lock through the store, not through the watcher", function()
            -- The enable path mirrors the setting into db.lock, which is the value
            -- LibDBIcon reads when it builds the button. That is what makes a lock stored in
            -- the profile survive a login, where the watcher cannot help: it fires during
            -- onInit, before any button exists.
            set("locked", true)
            set("enabled", false)
            set("enabled", true)
            expect(iconStore().lock)
                .as("the enable path seeded the library's lock flag from the setting")
                .eq(true)
            expect(button():GetScript("OnDragStart")).isNil()
        end)

        it("watches locked immediately and enabled deferred", function()
            -- The immediate flag cannot be read back after the fact, and the two watchers
            -- deliberately disagree about it, so the registration is observed as it happens.
            setup({ boot = false })
            local S = H.SuuUI.Settings
            local realWatch, seen = S.Watch, {}
            S.Watch = function(self, pid, key, cb, owner, opts)
                if pid == PLUGIN_ID then
                    seen[#seen + 1] = {
                        key       = key,
                        owner     = owner,
                        immediate = (opts and opts.immediate) == true,
                        enabled   = plugin():IsEnabled(),
                        hasButton = lib():IsRegistered(name()),
                    }
                end
                return realWatch(self, pid, key, cb, owner, opts)
            end
            H.fireEvent("ADDON_LOADED", "SuuUI")
            H.fireEvent("PLAYER_LOGIN")
            S.Watch = realWatch

            expect(#seen).as("two watchers, one per key").eq(2)
            expect(seen[1].key).eq("enabled")
            expect(seen[2].key).eq("locked")
            expect(seen[1].immediate)
                .as("an immediate enabled watcher would run onEnable inside the init pass")
                .eq(false)
            expect(seen[2].immediate).as("locked is applied immediately").eq(true)
            for i = 1, 2 do
                expect(seen[i].owner).as("watcher " .. i .. " owns its subscription")
                    .eq(PLUGIN_ID .. "." .. seen[i].key)
            end
            expect(plugin():IsEnabled())
                .as("and the plugin is up by the end of login regardless").eq(true)
        end)

        it("registers the lock watcher before any button exists, as written today", function()
            -- Pins the ordering the immediate flag actually meets: onInit runs before
            -- onEnable, so the immediate callback finds nothing registered and returns
            -- without locking anything. See the xit below.
            setup({ boot = false })
            local S = H.SuuUI.Settings
            local realWatch, atWatch = S.Watch, {}
            S.Watch = function(self, pid, key, cb, owner, opts)
                if pid == PLUGIN_ID and key == "locked" then
                    atWatch.hasButton = lib():IsRegistered(name())
                end
                return realWatch(self, pid, key, cb, owner, opts)
            end
            H.fireEvent("ADDON_LOADED", "SuuUI")
            H.fireEvent("PLAYER_LOGIN")
            S.Watch = realWatch
            expect(atWatch.hasButton)
                .as("no button is registered when the immediate callback runs").eq(false)
        end)

        xit("applies a stored lock through the immediate callback", function()
            -- The invariant the `immediate = true` flag reads as promising, and does not
            -- currently deliver: the callback fires from onInit, where lib:IsRegistered is
            -- false, so it returns having done nothing. Today the lock reaches the button
            -- only because onEnable mirrors it into db.lock (covered above), which means the
            -- flag buys nothing at login and its cost is one dead call per session.
            --
            -- Options, pending a decision: (a) drop `immediate` and rely on the db.lock
            -- seeding alone, which is what actually works; (b) keep it and move the lock
            -- application into onEnable explicitly, so one place owns it; (c) keep it as
            -- insurance for a late registration (a plugin re-enabled after login), and say so
            -- in the comment. Whichever is chosen, the two paths should not both claim to own
            -- the lock.
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the hover tooltip", function()
        it("puts a title and one line per click action on the library's tooltip", function()
            local tip = hoverButton()
            expect(tip:IsShown()).eq(true)
            expect(tip:GetOwner()).as("owned by the button it describes").eq(button())
            expect(tip:NumLines()).as("a title plus one line per click action").eq(3)
        end)

        it("titles it with the name collectors know the button by", function()
            local tip = hoverButton()
            expect(tip:GetLine(1)).eq(name())
            expectLineColor(1, "colorText")
        end)

        it("names both click actions, each in the muted colour", function()
            local tip = hoverButton()
            local left, right = (tip:GetLine(2) or ""):lower(), (tip:GetLine(3) or ""):lower()
            expect(left).as("line 2 is about the left click").contains("left")
            expect(left).as("and says it opens the settings").contains("settings")
            expect(right).as("line 3 is about the right click").contains("right")
            expect(right).as("and says it enters edit mode").contains("edit mode")
            expectLineColor(2, "colorTextMuted")
            expectLineColor(3, "colorTextMuted")
        end)

        it("re-tints with the theme instead of carrying colour literals", function()
            -- The assertion that tells a token from a literal that happens to match it:
            -- move the palette entry the semantic token resolves through, and the next
            -- hover has to come back with the new value.
            hoverButton()
            local beforeTitle, beforeHint = lines()[1].r, lines()[2].r

            H.T:CreateUserTheme("Retint", "Modern")
            H.T:SetUserToken("Retint", "colorGray100", { 0.1, 0.8, 0.3, 1 })
            H.T:SetUserToken("Retint", "colorGray400", { 0.9, 0.2, 0.4, 1 })
            H.T:SetActive("Retint")

            H.unhover(button())
            hoverButton()
            expectLineColor(1, "colorText")
            expectLineColor(2, "colorTextMuted")
            expectLineColor(3, "colorTextMuted")
            expect(lines()[1].r).as("the title channel actually moved").neq(beforeTitle)
            expect(lines()[2].r).as("and so did the hint channel").neq(beforeHint)
        end)

        it("does not accumulate lines across hovers", function()
            hoverButton()
            H.unhover(button())
            hoverButton()
            expect(lib().tooltip:NumLines()).as("three lines on the second hover, not six")
                .eq(3)
        end)

        it("ignores a tooltip that cannot take lines", function()
            -- An LDB display may hand over something that is not a GameTooltip at all. The
            -- hook is called directly by third-party code, so an unguarded index raises
            -- inside THEIR frame handler, not ours.
            expect(function() obj().OnTooltipShow(nil) end)
                .as("a nil tooltip is guarded").notThrows()
            expect(function() obj().OnTooltipShow({}) end)
                .as("and so is one with no AddLine").notThrows()
        end)
    end)

    -----------------------------------------------------------------------------
    describe("click routing", function()
        it("treats any button that is not the right one as a left click", function()
            -- RegisterForClicks("anyUp") means a middle click arrives too, and the handler
            -- tests for RightButton rather than for LeftButton, so everything else opens the
            -- window. Inverting that test would send a middle click into edit mode.
            expect(H.SuuUI.SettingsWindow.IsShown()).as("closed to begin with").falsy()
            expect(H.click(button(), "MiddleButton"))
                .as("the click was delivered at all").eq(true)
            expect(H.SuuUI.SettingsWindow.IsShown())
                .as("a middle click opens the settings").truthy()
            expect(H.SuuUI.ToggleUI:IsEditMode())
                .as("and does not enter edit mode").falsy()
        end)

        it("toggles the window rather than only opening it", function()
            H.click(button(), "LeftButton")
            expect(H.SuuUI.SettingsWindow.IsShown()).truthy()
            H.click(button(), "LeftButton")
            H.runAnimations()
            expect(H.SuuUI.SettingsWindow.IsShown())
                .as("a second click closes it again").falsy()
        end)

        it("still clicks when the position is locked", function()
            -- Lock takes the DRAG scripts away and must leave OnClick alone; a locked
            -- button the player cannot press is a button they cannot get rid of either,
            -- since the setting lives behind it.
            set("locked", true)
            expect(H.click(button(), "LeftButton")).eq(true)
            expect(H.SuuUI.SettingsWindow.IsShown()).truthy()
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the position store", function()
        it("hands LibDBIcon the plugin's own profile table, by identity", function()
            expect(button().db)
                .as("the table the library mutates is the profile sub-table itself")
                .eq(iconStore())
        end)

        it("persists a dragged angle into the profile", function()
            local mx, my = H.Minimap:GetCenter()
            local dx, dy = 40, 40
            expect(iconStore().minimapPos).as("nothing stored before a drag").isNil()
            drag(mx + dx, my + dy)
            expect(iconStore().minimapPos)
                .as("the angle the cursor was at, written straight into the profile")
                .near(angleOf(dx, dy), 0.001)
        end)

        it("moves the button to the dragged angle on the ring", function()
            local mx, my = H.Minimap:GetCenter()
            local dx, dy = 40, 40
            drag(mx + dx, my + dy)
            local angle = math.rad(angleOf(dx, dy))
            local ringW = H.Minimap:GetWidth() / 2 + lib().radius
            local ringH = H.Minimap:GetHeight() / 2 + lib().radius
            local bx, by = button():GetCenter()
            expect(bx - mx).as("moved right along the ring").near(math.cos(angle) * ringW, 0.5)
            expect(by - my).as("and up it").near(math.sin(angle) * ringH, 0.5)
        end)

        it("keeps a dragged position across an enable cycle", function()
            local mx, my = H.Minimap:GetCenter()
            drag(mx + 40, my + 40)
            local store, pos = iconStore(), iconStore().minimapPos
            set("enabled", false)
            set("enabled", true)
            expect(iconStore()).as("the same table, not a rebuilt one").eq(store)
            expect(iconStore().minimapPos).as("with the angle intact").near(pos, 0.001)
            expect(button().db).as("and the library still holding it").eq(store)
        end)

        it("cannot be written back through Settings, which is why it is not a setting",
            function()
                -- The reason the store lives in the profile rather than behind Settings:Get.
                -- LibDBIcon mutates the table in place on every tick of a drag, so a
                -- Settings:Set of that same table compares it against itself, finds no
                -- change, and drops the write — watchers and event included.
                local seen = 0
                H.SuuUI.Events:On("SUUUI_SETTING_CHANGED", function(id, key)
                    if id == PLUGIN_ID and key == "icon" then seen = seen + 1 end
                end, "spec_minimap_icon_probe")

                local store = iconStore()
                store.minimapPos = angleOf(1, 1)
                H.SuuUI.Settings:Set(PLUGIN_ID, "icon", store)
                expect(seen)
                    .as("an in-place mutation is invisible to Set, so no write happens")
                    .eq(0)
                expect(H.SuuUI.Settings:GetSchema(PLUGIN_ID)[3])
                    .as("and no icon key was ever declared").isNil()
            end)
    end)

    -----------------------------------------------------------------------------
    describe("watcher hygiene", function()
        it("registers exactly one watcher per key, under its own owner name", function()
            local S = H.SuuUI.Settings
            expect(S:Unwatch(PLUGIN_ID .. ".enabled")).as("one watcher on enabled").eq(1)
            expect(S:Unwatch(PLUGIN_ID .. ".locked")).as("one watcher on locked").eq(1)
        end)

        it("is watcher-neutral across an enable cycle", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            set("enabled", false)
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("onDisable retires nothing").eq(before)
            set("enabled", true)
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("and onEnable adds nothing").eq(before)
        end)

        it("does not stack watchers across repeated cycles", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            for _ = 1, 3 do
                plugin():Disable()
                plugin():Enable()
            end
            expect(H.SuuUI.Settings:GetWatcherCount()).eq(before)
        end)

        it("keeps the enabled watcher alive while disabled, or it could never come back",
            function()
                set("enabled", false)
                expect(plugin():IsEnabled()).eq(false)
                set("enabled", true)
                expect(plugin():IsEnabled())
                    .as("the watcher survived its own disable").eq(true)
                expect(button():IsShown()).eq(true)
            end)
    end)

    -----------------------------------------------------------------------------
    -- A client with no LibDBIcon is the ordinary case for a stripped install, and the
    -- plugin's guards are pcall-wrapped by Plugin:Enable and by Settings:Watch — so
    -- "it did not raise" proves nothing here. The DEBUG LOG is the observable: the plugin's
    -- own message means the guard fired, and a swallowed lifecycle error means it did not.
    describe("without LibDBIcon", function()
        it("logs and carries on when LibStub itself is gone", function()
            setup({ debug = true })
            H.env.LibStub = nil
            plugin():Disable()
            plugin():Enable()
            expect(plugin():IsEnabled()).as("the plugin still came up").eq(true)
            expect(H.SuuUI._MinimapButton.GetButton())
                .as("with no button to answer with").isNil()
            expect(logMatching("Plugin onEnable error"))
                .as("rather than raising into Plugin:Enable's pcall").eq(0)
            expect(logMatching("Plugin onDisable error"))
                .as("and the same on the way down").eq(0)
            expect(logMatching("LibDBIcon-1.0 unavailable"))
                .as("the plugin said so itself").gte(1)
        end)

        it("copes with a LibStub that raises", function()
            setup({ debug = true })
            H.env.LibStub = setmetatable({}, { __call = function() error("boom", 0) end })
            plugin():Disable()
            plugin():Enable()
            expect(logMatching("LibDBIcon-1.0 unavailable"))
                .as("the pcall around the lookup absorbed it").gte(1)
            expect(logMatching("Plugin onEnable error")).eq(0)
        end)

        it("copes with a LibStub that simply has no such library", function()
            setup({ debug = true })
            H.env.LibStub = setmetatable({}, { __call = function() return nil end })
            plugin():Disable()
            plugin():Enable()
            expect(logMatching("LibDBIcon-1.0 unavailable")).gte(1)
            expect(logMatching("Plugin onEnable error")).eq(0)
        end)

        it("guards the lock watcher, whose callback is pcall'd too", function()
            setup({ debug = true })
            H.env.LibStub = nil
            set("locked", true)
            expect(logMatching("Settings:Watch callback error"))
                .as("the watcher checked for the library before using it").eq(0)
            expect(get("locked")).as("and the setting still stored").eq(true)
        end)
    end)
end)
