-- Diagnostics/Diagnostics.lua
-- The diagnostics module: /suu probe, /suu tokens and /suu gallery. The first built-in
-- module, written against the public API like any plugin.

local _, ns = ...

SuuUI.RegisterModule({
    id = "diagnostics",
    name = "Diagnostics",
    description = "Developer tools: the client API probe, the design token sheet and the component gallery.",
    api = "0.2",
    OnEnable = function(self)
        self:RegisterCommand("probe", "Check which client APIs SuuUI depends on exist here; \"/suu probe show\" reopens the last report; \"/suu probe track\" tests the tracker.", ns.Probe.Command, ns.Probe.TOPICS)
        self:RegisterCommand("tokens", "Show every design token colour and text style.", ns.TokenSheet.Toggle)
        self:RegisterCommand("gallery", "Show every SuuUI component built so far.", ns.Gallery.Toggle)
    end,
    OnDisable = function()
        ns.Probe.Hide()
        ns.TokenSheet.Hide()
        ns.Gallery.Hide()
    end,
})
