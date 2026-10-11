-- Diagnostics/Diagnostics.lua
-- The diagnostics module: /suu probe and /suu tokens. The first built-in
-- module, written against the public API like any plugin.

local _, ns = ...

SuuUI.RegisterModule({
    id = "diagnostics",
    name = "Diagnostics",
    description = "Developer tools: the client API probe and the design token sheet.",
    api = "0.1",
    OnEnable = function(self)
        self:RegisterCommand("probe", "Check which client APIs SuuUI depends on exist here; \"/suu probe show\" reopens the last report.", ns.Probe.Command)
        self:RegisterCommand("tokens", "Show every design token colour and text style.", ns.TokenSheet.Toggle)
    end,
    OnDisable = function()
        ns.Probe.Hide()
        ns.TokenSheet.Hide()
    end,
})
