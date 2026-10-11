-- HelloPlugin.lua
-- A minimal SuuUI plugin: one module with a setting, a chat command, a game
-- event and a message. Copy this folder to Interface/AddOns to try it.
--
--   /suu                     its section is under Plugins in the settings window
--   /suu modules             lists it next to SuuUI's own modules
--   /suu hello               says the greeting
--   /suu set hello.greeting Well met
--   /suu disable hello       removes it at once, command and all
--   /suu set hello.failOnEnable on, then /suu disable hello and /suu enable hello
--                            shows how a failing plugin is contained

SuuUI.RegisterModule({
    id = "hello",
    name = "Hello",
    description = "An example plugin that says hello.",
    api = "0.3",
    defaults = {
        greeting = "Hello from a SuuUI plugin",
        failOnEnable = false,
    },

    OnInitialize = function(self)
        self.targets = 0
    end,

    OnEnable = function(self)
        if self:Get("failOnEnable") then
            error("failing on purpose (hello.failOnEnable is on)")
        end

        self:RegisterCommand("hello", "Say the Hello plugin's greeting.", function()
            self:Print(self:Get("greeting"), ("(you changed target %d times)"):format(self.targets))
        end)

        self:Watch("greeting", function(greeting)
            self:Print("New greeting:", greeting)
        end)

        self:OnGameEvent("PLAYER_TARGET_CHANGED", function()
            self.targets = self.targets + 1
        end)

        self:On("SUUUI_MODULE_ENABLED", function(_, id)
            if id ~= self.id then self:Print("Another module turned on:", id) end
        end)

        -- A section in SuuUI's settings window, beside the built-in ones.
        self:RegisterSettings({
            id = "hello", label = "Hello",
            groups = {
                { title = "Greeting", description = "An example plugin's own settings.", rows = {
                    { key = "greeting", label = "Greeting", control = "text", width = 240,
                      description = "What /suu hello says." },
                    { key = "failOnEnable", label = "Fail on enable", control = "toggle",
                      description = "Makes the plugin fail the next time it turns on, to show how SuuUI contains a broken plugin." },
                } },
            },
        })

        self:Print(self:Get("greeting"))
    end,

    OnDisable = function(self)
        self:Print("Goodbye.")
    end,
})
