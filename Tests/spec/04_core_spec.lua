local H = require("harness")

describe("UISignals", function()
    before_each(function() H.setup() end)

    it("calls a connected callback with the emitted payload", function()
        local obj, seen = {}, nil
        H.S:Connect(obj, H.S.SIGNALS.VALUE_CHANGED, function(a, b) seen = { a, b } end)
        H.S:Emit(obj, H.S.SIGNALS.VALUE_CHANGED, 5, 3)
        expect(seen).deepEq({ 5, 3 })
    end)

    it("calls every callback for a signal", function()
        local obj, count = {}, 0
        for _ = 1, 3 do
            H.S:Connect(obj, H.S.SIGNALS.CLICKED, function() count = count + 1 end)
        end
        H.S:Emit(obj, H.S.SIGNALS.CLICKED)
        expect(count).eq(3)
    end)

    it("returns a unique id per connection", function()
        local obj = {}
        local a = H.S:Connect(obj, H.S.SIGNALS.CLICKED, function() end)
        local b = H.S:Connect(obj, H.S.SIGNALS.CLICKED, function() end)
        expect(a).neq(b)
    end)

    it("disconnects one callback and leaves the rest", function()
        local obj, kept, dropped = {}, 0, 0
        local id = H.S:Connect(obj, H.S.SIGNALS.CLICKED, function() dropped = dropped + 1 end)
        H.S:Connect(obj, H.S.SIGNALS.CLICKED, function() kept = kept + 1 end)
        H.S:Disconnect(obj, H.S.SIGNALS.CLICKED, id)
        H.S:Emit(obj, H.S.SIGNALS.CLICKED)
        expect(dropped).eq(0)
        expect(kept).eq(1)
    end)

    it("disconnects one whole signal", function()
        local obj, clicks, sizes = {}, 0, 0
        H.S:Connect(obj, H.S.SIGNALS.CLICKED, function() clicks = clicks + 1 end)
        H.S:Connect(obj, H.S.SIGNALS.SIZE_CHANGED, function() sizes = sizes + 1 end)
        H.S:DisconnectAll(obj, H.S.SIGNALS.CLICKED)
        H.S:Emit(obj, H.S.SIGNALS.CLICKED)
        H.S:Emit(obj, H.S.SIGNALS.SIZE_CHANGED)
        expect(clicks).eq(0)
        expect(sizes).eq(1)
    end)

    it("disconnects the whole object", function()
        local obj, count = {}, 0
        H.S:Connect(obj, H.S.SIGNALS.CLICKED, function() count = count + 1 end)
        H.S:Connect(obj, H.S.SIGNALS.SIZE_CHANGED, function() count = count + 1 end)
        H.S:DisconnectAll(obj)
        H.S:Emit(obj, H.S.SIGNALS.CLICKED)
        H.S:Emit(obj, H.S.SIGNALS.SIZE_CHANGED)
        expect(count).eq(0)
    end)

    it("reports whether a signal has listeners", function()
        local obj = {}
        expect(H.S:HasConnections(obj, H.S.SIGNALS.CLICKED)).falsy()
        local id = H.S:Connect(obj, H.S.SIGNALS.CLICKED, function() end)
        expect(H.S:HasConnections(obj, H.S.SIGNALS.CLICKED)).truthy()
        H.S:Disconnect(obj, H.S.SIGNALS.CLICKED, id)
        expect(H.S:HasConnections(obj, H.S.SIGNALS.CLICKED)).falsy()
    end)

    it("ignores emitting a signal nobody listens to", function()
        expect(function() H.S:Emit({}, H.S.SIGNALS.CLICKED, 1) end).notThrows()
    end)

    it("survives a throwing callback and still calls the others", function()
        local obj, other = {}, 0
        H.S:Connect(obj, H.S.SIGNALS.CLICKED, function() error("boom") end)
        H.S:Connect(obj, H.S.SIGNALS.CLICKED, function() other = other + 1 end)
        expect(function() H.S:Emit(obj, H.S.SIGNALS.CLICKED) end).notThrows()
        expect(other).eq(1)
    end)

    it("rejects a missing object, signal or callback", function()
        expect(function() H.S:Connect(nil, "x", function() end) end).throws("obj required")
        expect(function() H.S:Connect({}, nil, function() end) end).throws("signal must be string")
        expect(function() H.S:Connect({}, "x", nil) end).throws("callback must be function")
    end)

    it("keeps signals separate per object", function()
        local a, b, hits = {}, {}, 0
        H.S:Connect(a, H.S.SIGNALS.CLICKED, function() hits = hits + 1 end)
        H.S:Emit(b, H.S.SIGNALS.CLICKED)
        expect(hits).eq(0)
    end)
end)

describe("EventBus", function()
    before_each(function() H.setup() end)

    it("delivers an event with its payload", function()
        local seen
        H.SuuUI.Events:On("TEST_EVENT", function(a, b) seen = { a, b } end, "spec")
        H.SuuUI.Events:Emit("TEST_EVENT", "x", 2)
        expect(seen).deepEq({ "x", 2 })
    end)

    it("unsubscribes every callback for an owner", function()
        local count = 0
        H.SuuUI.Events:On("TEST_EVENT", function() count = count + 1 end, "spec")
        H.SuuUI.Events:On("TEST_EVENT", function() count = count + 1 end, "spec")
        H.SuuUI.Events:On("TEST_EVENT", function() count = count + 1 end, "other")
        H.SuuUI.Events:Off("TEST_EVENT", "spec")
        H.SuuUI.Events:Emit("TEST_EVENT")
        expect(count).eq(1)
    end)

    it("removes a Once listener after the first fire", function()
        local count = 0
        H.SuuUI.Events:Once("TEST_EVENT", function() count = count + 1 end, "spec")
        H.SuuUI.Events:Emit("TEST_EVENT")
        H.SuuUI.Events:Emit("TEST_EVENT")
        expect(count).eq(1)
    end)

    it("unsubscribes an owner from every event", function()
        local count = 0
        H.SuuUI.Events:On("A", function() count = count + 1 end, "spec")
        H.SuuUI.Events:On("B", function() count = count + 1 end, "spec")
        H.SuuUI.Events:OffAll("spec")
        H.SuuUI.Events:Emit("A")
        H.SuuUI.Events:Emit("B")
        expect(count).eq(0)
    end)

    it("survives a throwing listener", function()
        local other = 0
        H.SuuUI.Events:On("TEST_EVENT", function() error("boom") end, "spec")
        H.SuuUI.Events:On("TEST_EVENT", function() other = other + 1 end, "spec")
        expect(function() H.SuuUI.Events:Emit("TEST_EVENT") end).notThrows()
        expect(other).eq(1)
    end)

    it("ignores an event nobody listens to", function()
        expect(function() H.SuuUI.Events:Emit("NOBODY_HOME") end).notThrows()
    end)
end)

describe("Settings", function()
    before_each(function()
        H.setup()
        H.SuuUI.Settings:Register("spec_plugin", {
            { key = "enabled", label = "Enabled", type = "toggle", default = true },
            { key = "size",    label = "Size",    type = "slider", default = 12, min = 8, max = 32 },
            { key = "",        label = "Group",   type = "section" },
            { key = "checked", label = "Checked", type = "toggle", default = false,
              validate = function(v) if v == "bad" then return false, "nope" end return true end },
        })
    end)

    it("returns schema defaults before anything is written", function()
        expect(H.SuuUI.Settings:Get("spec_plugin", "enabled")).truthy()
        expect(H.SuuUI.Settings:Get("spec_plugin", "size")).eq(12)
    end)

    it("returns nil for an unknown key", function()
        expect(H.SuuUI.Settings:Get("spec_plugin", "nope")).isNil()
    end)

    it("returns nil for an unregistered plugin", function()
        expect(H.SuuUI.Settings:Get("no_such_plugin", "x")).isNil()
    end)

    it("writes a value and fires SUUUI_SETTING_CHANGED with old and new", function()
        local spy = H.eventSpy("SUUUI_SETTING_CHANGED")
        H.SuuUI.Settings:Set("spec_plugin", "size", 20)
        expect(H.SuuUI.Settings:Get("spec_plugin", "size")).eq(20)
        expect(spy:arg(1)).eq("spec_plugin")
        expect(spy:arg(2)).eq("size")
        expect(spy:arg(3)).eq(20)
        -- The EFFECTIVE old value, not the raw stored nil. A listener that reverts a
        -- change (ReloadGuard) writes this value back, so handing it nil would clear
        -- the key and leave every bound widget showing nil for a setting that reads
        -- as its default.
        expect(spy:arg(4)).as("the value a reader saw before the write").eq(12)
    end)

    it("drops a write that does not change the effective value", function()
        local spy = H.eventSpy("SUUUI_SETTING_CHANGED")
        -- Never written, so it reads as its default of 12. Writing 12 changes nothing.
        H.SuuUI.Settings:Set("spec_plugin", "size", 12)
        expect(spy.count).as("no event for a no-op write").eq(0)
    end)

    it("stores false, distinct from unset", function()
        H.SuuUI.Settings:Set("spec_plugin", "enabled", false)
        expect(H.SuuUI.Settings:Get("spec_plugin", "enabled")).falsy()
    end)

    it("rejects a value its validator refuses", function()
        H.SuuUI.Settings:Set("spec_plugin", "checked", "bad")
        expect(H.SuuUI.Settings:Get("spec_plugin", "checked")).falsy()
    end)

    it("resets one key to its default", function()
        H.SuuUI.Settings:Set("spec_plugin", "size", 30)
        H.SuuUI.Settings:Reset("spec_plugin", "size")
        expect(H.SuuUI.Settings:Get("spec_plugin", "size")).eq(12)
    end)

    it("resets every key, skipping section entries", function()
        H.SuuUI.Settings:Set("spec_plugin", "size", 30)
        H.SuuUI.Settings:Set("spec_plugin", "enabled", false)
        H.SuuUI.Settings:ResetAll("spec_plugin")
        expect(H.SuuUI.Settings:Get("spec_plugin", "size")).eq(12)
        expect(H.SuuUI.Settings:Get("spec_plugin", "enabled")).truthy()
    end)

    it("refuses to register the same plugin twice", function()
        expect(function()
            H.SuuUI.Settings:Register("spec_plugin", {})
        end).throws("already registered")
    end)

    it("requires a string plugin id", function()
        expect(function() H.SuuUI.Settings:Register(42, {}) end).throws("must be string")
    end)

    it("reads and writes through the active profile", function()
        H.SuuUI.Settings:Set("spec_plugin", "size", 20)
        H.SuuUI.Profiles:Create("Other")
        H.SuuUI.Profiles:SetActive("Other")
        expect(H.SuuUI.Settings:Get("spec_plugin", "size"))
            .as("Create copies Default, so the value comes along").eq(20)

        H.SuuUI.Settings:Set("spec_plugin", "size", 30)
        H.SuuUI.Profiles:SetActive("Default")
        expect(H.SuuUI.Settings:Get("spec_plugin", "size"))
            .as("the profiles diverge from then on").eq(20)
    end)
end)

describe("Theme", function()
    before_each(function() H.setup() end)

    it("resolves a literal token", function()
        expect(H.token("spaceSm")).eq(8)
    end)

    it("resolves an alias chain to its primitive", function()
        expect(H.token("colorText")).deepEq(H.token("colorGray100"))
    end)

    it("resolves a derived colour, taking rgb from the ref and alpha from the token", function()
        local bg = H.token("colorBg")
        local base = H.token("colorGray900")
        expect({ bg[1], bg[2], bg[3] }).deepEq({ base[1], base[2], base[3] })
        expect(bg[4]).eq(H.token("opacityPanel"))
    end)

    it("returns nil for an unknown token", function()
        expect(H.token("colorNotAThing")).isNil()
    end)

    it("floors a control height against the font metrics", function()
        expect(H.controlHeight("sizeControlMd")).eq(math.max(22, 13 + 4 * 2))
    end)

    it("grows a control height once the font outgrows the size token", function()
        H.T:CreateUserTheme("Big", "Modern")
        H.T:SetUserToken("Big", "fontSizeMd", 40)
        H.T:SetActive("Big")
        expect(H.controlHeight("sizeControlMd")).eq(40 + H.token("spaceXs") * 2)
    end)

    it("formats a colour token as a chat escape prefix", function()
        expect(H.T:GetColorCode("colorText")).matches("^|cff%x%x%x%x%x%x$")
    end)

    it("lists built-in themes", function()
        local names = {}
        for _, n in ipairs(H.T:List()) do names[n] = true end
        expect(names["Modern"]).truthy()
        expect(names["Default"]).truthy()
    end)

    it("refuses to delete or edit a built-in theme", function()
        expect(function() H.T:DeleteUserTheme("Modern") end).throws("cannot delete built-in")
        expect(function() H.T:SetUserToken("Modern", "spaceSm", 2) end).throws("cannot edit built-in")
    end)

    it("refuses to create a theme that already exists", function()
        H.T:CreateUserTheme("Mine", "Modern")
        expect(function() H.T:CreateUserTheme("Mine", "Modern") end).throws("already exists")
    end)

    it("requires a built-in as the base for a user theme", function()
        expect(function() H.T:CreateUserTheme("Mine", "NotATheme") end)
            .throws("base must be a built-in")
    end)

    it("fires SUUUI_THEME_CHANGED on activation and on a token edit", function()
        H.T:CreateUserTheme("Mine", "Modern")
        local spy = H.eventSpy("SUUUI_THEME_CHANGED")
        H.T:SetActive("Mine")
        expect(spy.count).eq(1)
        H.T:SetUserToken("Mine", "spaceSm", 20)
        expect(spy.count).eq(2)
    end)

    it("cascades a primitive edit through every semantic that references it", function()
        H.T:CreateUserTheme("Mine", "Modern")
        H.T:SetActive("Mine")
        H.T:SetUserToken("Mine", "colorBlue400", { 1, 0, 1, 1 })
        expect(H.token("colorAccent")).deepEq({ 1, 0, 1, 1 })
        expect(H.token("colorBorderFocus")).deepEq({ 1, 0, 1, 1 })
    end)

    it("clears overrides on reset", function()
        H.T:CreateUserTheme("Mine", "Modern")
        H.T:SetActive("Mine")
        H.T:SetUserToken("Mine", "spaceSm", 40)
        H.T:ResetUserTheme("Mine")
        expect(H.token("spaceSm")).eq(8)
    end)

    it("falls back to Modern when the active user theme is deleted", function()
        H.T:CreateUserTheme("Mine", "Modern")
        H.T:SetActive("Mine")
        H.T:DeleteUserTheme("Mine")
        expect(H.T:GetActive()).eq("Modern")
    end)

    it("rejects activating an unknown theme", function()
        expect(function() H.T:SetActive("Nope") end).throws("unknown theme")
    end)

    it("migrates legacy token keys on unversioned user themes", function()
        local profile = H.SuuUI.Profiles:GetActive()
        profile.themes = profile.themes or {}
        profile.themes["Legacy"] = { _base = "Modern", spaceSm = 99 }  -- no _tokenVersion
        H.T:SetActive("Legacy")
        expect(H.token("spaceXs")).as("old spaceSm meant today's spaceXs").eq(99)
    end)

    it("keeps every size token wired to a consumer", function()
        for _, key in ipairs({ "sizeControlSm", "sizeControlMd", "sizeControlLg", "sizeRow",
                               "sizeNavRow", "sizeTitleBar", "sizeToggleW", "sizeIcon",
                               "sizeScrollbar", "borderWidth" }) do
            expect(H.token(key)).as(key .. " must exist").notNil()
        end
    end)
end)

describe("Profiles", function()
    before_each(function() H.setup() end)

    it("starts on the Default profile", function()
        expect(H.SuuUI.Profiles:GetActiveName()).eq("Default")
    end)

    it("creates a profile and lists it", function()
        H.SuuUI.Profiles:Create("Raid")
        local names = {}
        for _, n in ipairs(H.SuuUI.Profiles:List()) do names[n] = true end
        expect(names["Raid"]).truthy()
    end)

    it("switches the active profile and fires SUUUI_PROFILE_LOADED", function()
        H.SuuUI.Profiles:Create("Raid")
        local spy = H.eventSpy("SUUUI_PROFILE_LOADED")
        H.SuuUI.Profiles:SetActive("Raid")
        expect(H.SuuUI.Profiles:GetActiveName()).eq("Raid")
        expect(spy:arg(1)).eq("Raid")
    end)

    it("refuses to delete the Default profile", function()
        expect(function() H.SuuUI.Profiles:Delete("Default") end).throws()
    end)

    it("seeds a new profile from Default", function()
        H.SuuUI.Settings:Register("ns_test", { { key = "v", type = "slider", default = 1 } })
        H.SuuUI.Settings:Set("ns_test", "v", 5)
        H.SuuUI.Profiles:Create("Raid")
        H.SuuUI.Profiles:SetActive("Raid")
        expect(H.SuuUI.Settings:Get("ns_test", "v")).eq(5)
    end)

    it("does not share plugin tables between profiles", function()
        H.SuuUI.Settings:Register("ns_test", { { key = "v", type = "slider", default = 1 } })
        H.SuuUI.Settings:Set("ns_test", "v", 5)
        H.SuuUI.Profiles:Create("Raid")
        H.SuuUI.Profiles:SetActive("Raid")
        H.SuuUI.Settings:Set("ns_test", "v", 9)
        H.SuuUI.Profiles:SetActive("Default")
        expect(H.SuuUI.Settings:Get("ns_test", "v")).as("deep copy, not a shared reference").eq(5)
    end)
end)

describe("Pool", function()
    before_each(function() H.setup() end)

    local function registerRow()
        H.SuuUI.Pool:Register("spec.row", function(parent)
            local f = H.env.CreateFrame("Frame", nil, parent)
            f:SetSize(100, 20)
            f._created = (f._created or 0) + 1
            return f
        end)
    end

    it("requires a string id and a function factory", function()
        expect(function() H.SuuUI.Pool:Register(1, function() end) end).throws("must be string")
        expect(function() H.SuuUI.Pool:Register("x", 1) end).throws("must be function")
    end)

    it("refuses to acquire an unregistered type", function()
        expect(function() H.SuuUI.Pool:Acquire("spec.unknown", H.UIParent) end)
            .throws("unregistered typeId")
    end)

    it("creates a frame when the pool is empty", function()
        registerRow()
        local host = H.parent(200, 200)
        local f = H.SuuUI.Pool:Acquire("spec.row", host)
        expect(f).notNil()
        expect(f:IsShown()).truthy()
        expect(f:GetParent()).eq(host)
    end)

    it("recycles a released frame instead of creating a new one", function()
        registerRow()
        local host = H.parent(200, 200)
        local first = H.SuuUI.Pool:Acquire("spec.row", host)
        H.SuuUI.Pool:Release("spec.row", first)
        expect(H.SuuUI.Pool:Acquire("spec.row", host)).eq(first)
    end)

    it("hides and unanchors a released frame", function()
        registerRow()
        local host = H.parent(200, 200)
        local f = H.SuuUI.Pool:Acquire("spec.row", host)
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 5, -5)
        H.SuuUI.Pool:Release("spec.row", f)
        expect(f:IsShown()).falsy()
        expect(f:GetNumPoints()).eq(0)
    end)

    it("re-parents a recycled frame", function()
        registerRow()
        local a, b = H.parent(100, 100), H.parent(100, 100)
        local f = H.SuuUI.Pool:Acquire("spec.row", a)
        H.SuuUI.Pool:Release("spec.row", f)
        expect(H.SuuUI.Pool:Acquire("spec.row", b):GetParent()).eq(b)
    end)

    it("releases every active frame at once", function()
        registerRow()
        local host = H.parent(200, 200)
        local frames = {}
        for i = 1, 4 do frames[i] = H.SuuUI.Pool:Acquire("spec.row", host) end
        H.SuuUI.Pool:ReleaseAll("spec.row")
        for _, f in ipairs(frames) do expect(f:IsShown()).falsy() end
        local reused = H.SuuUI.Pool:Acquire("spec.row", host)
        local wasOurs = false
        for _, f in ipairs(frames) do if f == reused then wasOurs = true end end
        expect(wasOurs).as("released frames go back into the pool").truthy()
    end)

    it("ignores releasing a frame it never handed out", function()
        registerRow()
        local stranger = H.parent(10, 10)
        expect(function() H.SuuUI.Pool:Release("spec.row", stranger) end).notThrows()
    end)

    it("ignores releasing into an unknown type", function()
        expect(function() H.SuuUI.Pool:Release("spec.nope", H.parent(1, 1)) end).notThrows()
    end)
end)

describe("Animator", function()
    before_each(function() H.setup() end)

    it("does not start until Play", function()
        local f = H.parent(10, 10)
        local a = H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 1, duration = 0.2 })
        expect(a:IsPlaying()).falsy()
        H.tick(0.5)
        expect(f:GetAlpha()).eq(1)
    end)

    it("drives alpha to the end value", function()
        local f = H.parent(10, 10)
        H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 1, duration = 0.2 }):Play()
        H.tick(1)
        expect(f:GetAlpha()).eq(1)
    end)

    it("interpolates part way through", function()
        local f = H.parent(10, 10)
        H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 1,
                           duration = 1, easing = "linear" }):Play()
        H.tick(0.25)
        expect(f:GetAlpha()).near(0.25, 0.001)
    end)

    it("animates width, height and scale", function()
        local f = H.parent(10, 10)
        H.SuuUI.Anim:New({ target = f, property = "width", from = 10, to = 50, duration = 0.1 }):Play()
        H.SuuUI.Anim:New({ target = f, property = "height", from = 10, to = 60, duration = 0.1 }):Play()
        H.SuuUI.Anim:New({ target = f, property = "scale", from = 1, to = 2, duration = 0.1 }):Play()
        H.tick(1)
        H.expectSize(f, 50, 60)
        expect(f:GetScale()).eq(2)
    end)

    it("calls onDone once at the end", function()
        local f, done = H.parent(10, 10), 0
        H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 1, duration = 0.1,
                           onDone = function() done = done + 1 end }):Play()
        H.tick(1)
        H.tick(1)
        expect(done).eq(1)
    end)

    it("stops without firing onDone", function()
        local f, done = H.parent(10, 10), false
        local a = H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 1,
                                     duration = 1, onDone = function() done = true end })
        a:Play()
        a:Stop()
        H.tick(2)
        expect(done).falsy()
        expect(a:IsPlaying()).falsy()
    end)

    it("swaps from and to on Reverse", function()
        local f = H.parent(10, 10)
        local a = H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 1, duration = 0.1 })
        a:Reverse()
        H.tick(1)
        expect(f:GetAlpha()).eq(0)
    end)

    it("runs a sequence in order", function()
        local f, order = H.parent(10, 10), {}
        H.SuuUI.Anim:Sequence({
            H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 0.5, duration = 0.1,
                               onDone = function() order[#order + 1] = "first" end }),
            H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0.5, to = 1, duration = 0.1,
                               onDone = function() order[#order + 1] = "second" end }),
        })
        H.runAnimations()
        expect(order).deepEq({ "first", "second" })
        expect(f:GetAlpha()).eq(1)
    end)

    it("runs parallel animations together", function()
        local f = H.parent(10, 10)
        H.SuuUI.Anim:Parallel({
            H.SuuUI.Anim:New({ target = f, property = "width", from = 10, to = 40, duration = 0.1 }),
            H.SuuUI.Anim:New({ target = f, property = "height", from = 10, to = 30, duration = 0.1 }),
        })
        H.tick(1)
        H.expectSize(f, 40, 30)
    end)

    it("drives x through the layout engine's anchor descriptor", function()
        local host = H.parent(200, 100)
        local box = H.Layout:CreateContainer({ host = host, layout = "anchor" })
        local child = H.env.CreateFrame("Frame", nil, host)
        local anchor = { point = "LEFT", relativePoint = "LEFT", x = 0, y = 0, width = 10, height = 10 }
        box:Add(child, { anchor = anchor })
        H.SuuUI.Anim:New({ container = box, target = child, anchor = anchor,
                           property = "x", from = 0, to = 100, duration = 0.1 }):Play()
        H.tick(1)
        H.expectOffset(child, host, 100, nil)
    end)

    it("refuses to animate x without a container, rather than falling back to SetPoint", function()
        H.setup({ debug = true })
        local host = H.parent(200, 100)
        local child = H.env.CreateFrame("Frame", nil, host)
        child:SetSize(10, 10)
        child:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        H.SuuUI.Anim:New({ target = child, property = "x", from = 0, to = 100, duration = 0.1 }):Play()
        H.tick(1)
        H.expectOffset(child, host, 0, 0)
        local logged = false
        for _, line in ipairs(H.debugLog()) do
            if line:find("requires a container") then logged = true end
        end
        expect(logged).as("the refusal is logged, not silent").truthy()
    end)

    it("survives a throwing onDone", function()
        local f = H.parent(10, 10)
        H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 1, duration = 0.1,
                           onDone = function() error("boom") end }):Play()
        expect(function() H.tick(1) end).notThrows()
    end)

    it("stops ticking once nothing is playing", function()
        local f = H.parent(10, 10)
        H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 1, duration = 0.1 }):Play()
        H.tick(1)
        local calls = 0
        f:SetScript("OnUpdate", function() calls = calls + 1 end)
        H.tick(1)
        expect(calls).as("only our own handler is left running").eq(1)
    end)

    it("ignores a duplicate Play while already running", function()
        local f, done = H.parent(10, 10), 0
        local a = H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 1,
                                     duration = 0.1, onDone = function() done = done + 1 end })
        a:Play()
        a:Play()
        H.tick(1)
        expect(done).eq(1)
    end)
end)

describe("Tween", function()
    before_each(function() H.setup() end)

    it("pins every easing to 0 at t=0 and 1 at t=1", function()
        for _, name in ipairs({ "linear", "easeIn", "easeOut", "easeInOut", "spring" }) do
            expect(H.SuuUI.Tween.Ease(0, name)).as(name .. " at 0").near(0, 0.0001)
            expect(H.SuuUI.Tween.Ease(1, name)).as(name .. " at 1").near(1, 0.0001)
        end
    end)

    it("overshoots past the target mid-curve for spring", function()
        -- That overshoot is the whole point of easeOutBack; without it the curve is
        -- indistinguishable from easeOut.
        local peak = 0
        for i = 0, 100 do
            peak = math.max(peak, H.SuuUI.Tween.Ease(i / 100, "spring"))
        end
        expect(peak).gt(1)
        expect(peak).as("but not wildly").lt(1.2)
    end)

    it("never dips below zero for spring", function()
        for i = 0, 100 do
            expect(H.SuuUI.Tween.Ease(i / 100, "spring")).gte(-0.0001)
        end
    end)

    it("drives an animation from its start value with spring easing", function()
        local f = H.parent(10, 10)
        H.SuuUI.Anim:New({ target = f, property = "alpha", from = 0, to = 1,
                           duration = 1, easing = "spring" }):Play()
        H.tick(0.001)
        expect(f:GetAlpha()).as("starts at from, not at double to").near(0, 0.02)
        H.tick(2)
        expect(f:GetAlpha()).eq(1)
    end)

    it("returns t unchanged for linear", function()
        expect(H.SuuUI.Tween.Ease(0.3, "linear")).near(0.3, 0.0001)
    end)

    it("starts slow for easeIn and fast for easeOut", function()
        expect(H.SuuUI.Tween.Ease(0.5, "easeIn")).lt(0.5)
        expect(H.SuuUI.Tween.Ease(0.5, "easeOut")).gt(0.5)
    end)

    it("falls back to linear for an unknown easing", function()
        expect(H.SuuUI.Tween.Ease(0.4, "nope")).near(0.4, 0.0001)
    end)

    it("stays monotonic across the range for the standard easings", function()
        for _, name in ipairs({ "linear", "easeIn", "easeOut", "easeInOut" }) do
            local prev = -math.huge
            for i = 0, 20 do
                local v = H.SuuUI.Tween.Ease(i / 20, name)
                expect(v).as(name .. " monotonic").gte(prev)
                prev = v
            end
        end
    end)
end)

describe("Utils", function()
    before_each(function() H.setup() end)

    it("deep-copies nested tables without sharing references", function()
        local src = { a = 1, nested = { b = 2, deep = { c = 3 } } }
        local copy = H.SuuUI.Utils.DeepCopy(src)
        copy.nested.deep.c = 99
        expect(src.nested.deep.c).eq(3)
        expect(copy.a).eq(1)
    end)

    it("shallow-merges a source into a target", function()
        local target = { a = 1, b = 2 }
        H.SuuUI.Utils.Merge(target, { b = 3, c = 4 })
        expect(target).deepEq({ a = 1, b = 3, c = 4 })
    end)

    it("finds the first matching value", function()
        local found = H.SuuUI.Utils.Find({ 1, 5, 9 }, function(v) return v > 4 end)
        expect(found).eq(5)
    end)

    it("returns nil when nothing matches", function()
        expect(H.SuuUI.Utils.Find({ 1, 2 }, function(v) return v > 10 end)).isNil()
    end)

    it("lists keys", function()
        local keys = {}
        for _, k in ipairs(H.SuuUI.Utils.Keys({ x = 1, y = 2 })) do keys[k] = true end
        expect(keys.x).truthy()
        expect(keys.y).truthy()
    end)
end)
