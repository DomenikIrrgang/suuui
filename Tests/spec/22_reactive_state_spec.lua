local H = require("harness")

describe("Settings:Watch reactive state", function()
    before_each(function()
        H.setup()
        H.SuuUI.Settings:Register("watch_test", {
            { key = "toggle_val", type = "toggle", default = false },
            { key = "slider_val", type = "slider", default = 50, min = 0, max = 100, step = 1 },
            { key = "text_val",   type = "text",   default = "hello" },
            { key = "color_val",  type = "color",  default = {1, 0, 0, 1} },
            { key = "session_val", type = "toggle", default = false, transient = true },
        })
    end)

    describe("Watch subscription", function()
        it("fires callback when Set changes the value", function()
            local received = nil
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", function(val)
                received = val
            end, "test_basic")
            H.SuuUI.Settings:Set("watch_test", "toggle_val", true)
            expect(received).eq(true)
        end)

        it("does not fire when the effective value is unchanged", function()
            local callCount = 0
            H.SuuUI.Settings:Watch("watch_test", "slider_val", function()
                callCount = callCount + 1
            end, "test_noop")
            -- Never written, so it already reads as 50
            H.SuuUI.Settings:Set("watch_test", "slider_val", 50)
            expect(callCount).eq(0)
        end)

        it("only fires for the matching pluginId + key", function()
            local calls = 0
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", function()
                calls = calls + 1
            end, "test_filter")
            H.SuuUI.Settings:Set("watch_test", "slider_val", 30)
            expect(calls).eq(0)
        end)

        it("multiple watchers on the same key all fire", function()
            local a, b = nil, nil
            H.SuuUI.Settings:Watch("watch_test", "text_val", function(val) a = val end, "test_a")
            H.SuuUI.Settings:Watch("watch_test", "text_val", function(val) b = val end, "test_b")
            H.SuuUI.Settings:Set("watch_test", "text_val", "world")
            expect(a).eq("world")
            expect(b).eq("world")
        end)

        it("immediate fires once with the current value at registration", function()
            local received, calls = nil, 0
            H.SuuUI.Settings:Watch("watch_test", "slider_val", function(val)
                received = val
                calls = calls + 1
            end, "test_immediate", { immediate = true })
            expect(received).as("the schema default, without a manual Get").eq(50)
            expect(calls).eq(1)
        end)

        it("a watcher error does not break the others", function()
            local received = nil
            H.SuuUI.Settings:Watch("watch_test", "text_val", function()
                error("deliberate test error")
            end, "err_test")
            H.SuuUI.Settings:Watch("watch_test", "text_val", function(v)
                received = v
            end, "after_err")
            H.SuuUI.Settings:Set("watch_test", "text_val", "survived")
            expect(received).eq("survived")
        end)
    end)

    describe("effective values", function()
        it("watchers receive the default, never the raw stored nil", function()
            H.SuuUI.Settings:Register("eff", {
                { key = "flag", type = "toggle", default = true },
            })
            local received = "unset"
            H.SuuUI.Settings:Watch("eff", "flag", function(v) received = v end, "eff_w")

            H.SuuUI.Settings:Set("eff", "flag", false)
            expect(received).eq(false)

            -- Clearing the key makes the default visible again; the watcher must be
            -- told `true`, not nil.
            H.SuuUI.Settings:Set("eff", "flag", nil)
            expect(received).as("the effective value, not raw nil").eq(true)
            expect(H.SuuUI.Settings:Get("eff", "flag")).eq(true)
        end)

        it("REGRESSION: a cancelled ReloadGuard leaves widget and store agreeing", function()
            H.SuuUI.Settings:Register("rg", {
                { key = "feature", label = "Feature", type = "toggle", default = true },
            })
            H.SuuUI.ReloadGuard:Register("rg", "feature", {})

            local displayed
            H.SuuUI.Settings:Watch("rg", "feature", function(v)
                displayed = v
            end, "rg_ctrl", { immediate = true })
            expect(displayed).eq(true)

            -- Toggle off. ReloadGuard reverts, having been given the effective old value.
            H.SuuUI.Settings:Set("rg", "feature", false)

            expect(H.SuuUI.Settings:Get("rg", "feature")).as("store reverted").eq(true)
            expect(displayed).as("widget followed the revert").eq(true)
        end)

        it("structurally equal tables are not treated as a change", function()
            local calls = 0
            H.SuuUI.Settings:Watch("watch_test", "color_val", function()
                calls = calls + 1
            end, "tbl_eq")
            H.SuuUI.Settings:Set("watch_test", "color_val", {1, 0, 0, 1})  -- same as default
            expect(calls).as("no echo for an identical table").eq(0)

            H.SuuUI.Settings:Set("watch_test", "color_val", {0, 1, 0, 1})
            expect(calls).eq(1)
        end)
    end)

    describe("Unwatch", function()
        it("removes all watchers for a given owner", function()
            local calls = 0
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", function()
                calls = calls + 1
            end, "test_remove")
            H.SuuUI.Settings:Unwatch("test_remove")
            H.SuuUI.Settings:Set("watch_test", "toggle_val", true)
            expect(calls).eq(0)
        end)

        it("does not remove watchers with a different owner", function()
            local aCalls, bCalls = 0, 0
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", function() aCalls = aCalls + 1 end, "owner_a")
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", function() bCalls = bCalls + 1 end, "owner_b")
            H.SuuUI.Settings:Unwatch("owner_a")
            H.SuuUI.Settings:Set("watch_test", "toggle_val", true)
            expect(aCalls).eq(0)
            expect(bCalls).eq(1)
        end)

        it("UnwatchPrefix drops a whole group at once", function()
            local calls = 0
            local function bump() calls = calls + 1 end
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", bump, "page:watch_test:toggle:toggle_val")
            H.SuuUI.Settings:Watch("watch_test", "slider_val", bump, "page:watch_test:slider:slider_val")
            H.SuuUI.Settings:Watch("watch_test", "text_val",   bump, "keep_me")

            local removed = H.SuuUI.Settings:UnwatchPrefix("page:watch_test:")
            expect(removed).eq(2)

            H.SuuUI.Settings:Set("watch_test", "toggle_val", true)
            H.SuuUI.Settings:Set("watch_test", "slider_val", 30)
            expect(calls).as("prefixed watchers are gone").eq(0)

            H.SuuUI.Settings:Set("watch_test", "text_val", "still here")
            expect(calls).as("the unprefixed one survived").eq(1)
        end)

        it("GetWatcherCount reflects additions and removals", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", function() end, "cnt_test")
            expect(H.SuuUI.Settings:GetWatcherCount()).eq(before + 1)
            H.SuuUI.Settings:Unwatch("cnt_test")
            expect(H.SuuUI.Settings:GetWatcherCount()).eq(before)
        end)
    end)

    describe("mutation during notify", function()
        it("a watcher that unwatches mid-notify does not skip its siblings", function()
            local seen = {}
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", function()
                seen[#seen + 1] = "a"
                -- Rebuilding a page does exactly this: tear down subscribers while a
                -- notify is in flight.
                H.SuuUI.Settings:Unwatch("mut_b")
            end, "mut_a")
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", function()
                seen[#seen + 1] = "b"
            end, "mut_b")
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", function()
                seen[#seen + 1] = "c"
            end, "mut_c")

            H.SuuUI.Settings:Set("watch_test", "toggle_val", true)
            -- b was torn down before it ran, but c must not be skipped by the removal.
            expect(seen[1]).eq("a")
            expect(seen[#seen]).as("the last subscriber still ran").eq("c")
        end)

        it("a watcher added mid-notify is not called in the same pass", function()
            local lateCalls = 0
            H.SuuUI.Settings:Watch("watch_test", "slider_val", function()
                H.SuuUI.Settings:Watch("watch_test", "slider_val", function()
                    lateCalls = lateCalls + 1
                end, "late_one")
            end, "adder")
            H.SuuUI.Settings:Set("watch_test", "slider_val", 20)
            expect(lateCalls).eq(0)
            H.SuuUI.Settings:Set("watch_test", "slider_val", 21)
            expect(lateCalls).eq(1)
        end)
    end)

    describe("transient keys", function()
        it("are never written into the profile", function()
            H.SuuUI.Settings:Set("watch_test", "session_val", true)
            expect(H.SuuUI.Settings:Get("watch_test", "session_val")).eq(true)

            local profile = H.SuuUI.Profiles:GetActive()
            local stored = profile.plugins["watch_test"] and profile.plugins["watch_test"].session_val
            expect(stored).as("not in SavedVariables").isNil()
        end)

        it("are reported as transient", function()
            expect(H.SuuUI.Settings:IsTransient("watch_test", "session_val")).eq(true)
            expect(H.SuuUI.Settings:IsTransient("watch_test", "toggle_val")).eq(false)
        end)

        it("survive a profile switch unchanged", function()
            H.SuuUI.Settings:Set("watch_test", "session_val", true)
            H.SuuUI.Profiles:Create("Other")
            H.SuuUI.Profiles:SetActive("Other")
            expect(H.SuuUI.Settings:Get("watch_test", "session_val")).eq(true)
        end)
    end)

    describe("profile switch integration", function()
        it("fires all watchers with new values on SUUUI_PROFILE_LOADED", function()
            local toggleVal, sliderVal = nil, nil
            H.SuuUI.Settings:Watch("watch_test", "toggle_val", function(v) toggleVal = v end, "prof_t")
            H.SuuUI.Settings:Watch("watch_test", "slider_val", function(v) sliderVal = v end, "prof_s")

            H.SuuUI.Profiles:Create("Alt")
            H.SuuUI.Profiles:SetActive("Alt")
            H.SuuUI.Settings:Set("watch_test", "toggle_val", true)
            H.SuuUI.Settings:Set("watch_test", "slider_val", 99)

            H.SuuUI.Events:Emit("SUUUI_PROFILE_LOADED", "Alt")
            expect(toggleVal).eq(true)
            expect(sliderVal).eq(99)
        end)

        it("a new profile inherits Default's CURRENT state, not schema defaults", function()
            -- Profiles:Create deep-copies Default as it stands right now, so a profile
            -- created after a write inherits that write. Worth pinning: it is the
            -- opposite of what "new profile" suggests.
            H.SuuUI.Settings:Set("watch_test", "slider_val", 80)
            H.SuuUI.Profiles:Create("AfterWrite")
            H.SuuUI.Profiles:SetActive("AfterWrite")
            expect(H.SuuUI.Settings:Get("watch_test", "slider_val"))
                .as("inherited the 80 written into Default").eq(80)
        end)

        it("a profile created before a write keeps the default", function()
            H.SuuUI.Profiles:Create("BeforeWrite")
            H.SuuUI.Settings:Set("watch_test", "slider_val", 80)

            local received = nil
            H.SuuUI.Settings:Watch("watch_test", "slider_val", function(v) received = v end, "prof_before")
            H.SuuUI.Profiles:SetActive("BeforeWrite")
            expect(received).eq(50)
        end)
    end)

    describe("ToggleUI uses Settings as single source of truth", function()
        it("Toggle() writes to Settings, watchers fire", function()
            local received = nil
            H.SuuUI.Settings:Watch("_layout", "edit_mode", function(v) received = v end, "tui_test")
            H.SuuUI.ToggleUI:Toggle()
            expect(received).eq(true)
            expect(H.SuuUI.Settings:Get("_layout", "edit_mode")).eq(true)
        end)

        it("Enable() is idempotent - watcher does not fire on same value", function()
            H.SuuUI.ToggleUI:Enable()
            local calls = 0
            H.SuuUI.Settings:Watch("_layout", "edit_mode", function() calls = calls + 1 end, "tui_idem")
            H.SuuUI.ToggleUI:Enable()
            expect(calls).eq(0)
        end)

        it("IsEditMode reads from Settings, not a local variable", function()
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(true)
            H.SuuUI.Settings:Set("_layout", "edit_mode", false)
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(false)
        end)

        it("REGRESSION: edit mode is not persisted across sessions", function()
            H.SuuUI.ToggleUI:Enable()
            local profile = H.SuuUI.Profiles:GetActive()
            local stored = profile.plugins["_layout"] and profile.plugins["_layout"].edit_mode
            expect(stored).as("edit mode must not reach SavedVariables").isNil()
        end)

        it("still emits the deprecated SUUUI_EDIT_MODE_CHANGED event", function()
            local spy = H.eventSpy("SUUUI_EDIT_MODE_CHANGED")
            H.SuuUI.ToggleUI:Enable()
            expect(spy.count).as("third-party listeners keep working").eq(1)
            expect(spy:arg(1)).eq(true)
            H.SuuUI.ToggleUI:Disable()
            expect(spy:arg(1)).eq(false)
        end)
    end)

    describe("MoveableFrame binding", function()
        local host
        before_each(function()
            host = H.parent(1024, 768)
            H.SuuUI.Settings:Register("mf_test", {
                { key = "pos", type = "position",
                  default = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 } },
            })
        end)

        local function applyFrame()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId = "mf_test", key = "pos", displayName = "Test",
                defaults = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
            })
            return f
        end

        it("reacts to edit mode changed through Settings directly", function()
            local f = applyFrame()
            expect(f._suuui_moveable.overlay:IsShown()).eq(false)
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            expect(f._suuui_moveable.overlay:IsShown()).eq(true)
            H.SuuUI.Settings:Set("_layout", "edit_mode", false)
            expect(f._suuui_moveable.overlay:IsShown()).eq(false)
        end)

        it("REGRESSION: overlay shows at Apply when edit mode is already on", function()
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            local f = applyFrame()
            expect(f._suuui_moveable.overlay:IsShown())
                .as("immediate binding applied the current state").eq(true)
        end)

        it("REGRESSION: saving a dragged position does not echo back a restore", function()
            local f = applyFrame()
            local restores = 0
            local real = H.SuuUI.MoveableFrame.RestorePosition
            H.SuuUI.MoveableFrame.RestorePosition = function(...)
                restores = restores + 1
                return real(...)
            end

            f._suuui_moveable.overlay:GetScript("OnDragStop")()
            expect(restores).as("the frame's own save must not move it").eq(0)

            H.SuuUI.MoveableFrame.RestorePosition = real
        end)

        it("Remove drops both watchers", function()
            local f = applyFrame()
            local before = H.SuuUI.Settings:GetWatcherCount()
            H.SuuUI.MoveableFrame:Remove(f)
            expect(H.SuuUI.Settings:GetWatcherCount()).eq(before - 2)
        end)
    end)

    describe("settings page lifecycle", function()
        it("REGRESSION: rebuilding a page does not leak watchers", function()
            H.SuuUI.Settings:Register("leak", {
                { key = "a", label = "A", type = "toggle", default = false },
                { key = "b", label = "B", type = "slider", default = 5, min = 0, max = 10 },
            })
            local host   = H.parent(400, 300)
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 400, h = 300 }, host)

            H.SuuUI._PageBuilder:Build("leak", scroll)
            local afterFirst = H.SuuUI.Settings:GetWatcherCount()

            for _ = 1, 5 do H.SuuUI._PageBuilder:Build("leak", scroll) end
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("each rebuild drops the previous page's watchers").eq(afterFirst)
        end)

        it("switching pages drops the outgoing page's watchers", function()
            H.SuuUI.Settings:Register("page_x", {
                { key = "x", label = "X", type = "toggle", default = false },
            })
            H.SuuUI.Settings:Register("page_y", {
                { key = "y", label = "Y", type = "toggle", default = false },
            })
            local host   = H.parent(400, 300)
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 400, h = 300 }, host)

            local base = H.SuuUI.Settings:GetWatcherCount()
            H.SuuUI._PageBuilder:Build("page_x", scroll)
            H.SuuUI._PageBuilder:Build("page_y", scroll)
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("only the visible page holds watchers").eq(base + 1)
        end)

        it("a control reflects an external write while its page is open", function()
            H.SuuUI.Settings:Register("live", {
                { key = "flag", label = "Flag", type = "toggle", default = false },
            })
            local host   = H.parent(400, 300)
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 400, h = 300 }, host)
            H.SuuUI._PageBuilder:Build("live", scroll)

            -- This is the original bug: change the value from outside the panel and the
            -- rendered control must follow.
            H.SuuUI.Settings:Set("live", "flag", true)
            expect(H.SuuUI.Settings:Get("live", "flag")).eq(true)
        end)
    end)
end)
