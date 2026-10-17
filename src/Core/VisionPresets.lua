-- Core/VisionPresets.lua
-- The colour vision presets' values (design system: SuuUI.cvdPresets, board
-- "Colour-blind presets", approved 2026-10-17): for each preset the signal
-- tokens it replaces. Checked in OKLab under Machado et al. (2009)
-- simulation: the pairs that must stay apart differ by at least 0.10, and
-- on-signal keeps at least 6.1:1 on every signal fill. Vision.lua applies
-- them; the glows follow their tokens there. Copied from the design system
-- (its bundle's cvdPresets); Normal is Tokens.lua itself.

local _, ns = ...

local T = ns.Tokens

T.vision = {
    redgreen = {
        ["ember"] = { 0.9255, 0.4196, 0, hex = "ec6b00" },
        ["ember-text"] = { 0.9569, 0.651, 0.4, hex = "f4a666" },
        ["ember-soft"] = { 0.1608, 0.102, 0.07843, hex = "291a14" },
        ["unit-fill-low"] = { 0.7451, 0, 0.7216, hex = "be00b8" },
        ["unit-fill-low-deep"] = { 0.3725, 0, 0.3608, hex = "5f005c" },
        ["fel"] = { 0.3725, 0.6157, 1, hex = "5f9dff" },
        ["fel-incoming"] = { 0.3725, 0.6157, 1, 0.4, hex = "5f9dff" },
        ["amber"] = { 0.9961, 0.949, 0.5647, hex = "fef290" },
        ["arcane"] = { 0.1333, 0.7882, 0.7882, hex = "22c9c9" },
        ["arcane-soft"] = { 0.06667, 0.1255, 0.1333, hex = "112022" },
        ["arcane-glow"] = { 0.1333, 0.7882, 0.7882, 0.4, hex = "22c9c9" },
        ["ward"] = { 0.9961, 0.9373, 0.7255, hex = "feefb9" },
        ["ward-absorb"] = { 0.9961, 0.9373, 0.7255, 0.45, hex = "feefb9" },
        ["dispel-magic"] = { 0.4392, 0.7176, 0.9765, hex = "70b7f9" },
        ["dispel-curse"] = { 0.9961, 0.3216, 0.6706, hex = "fe52ab" },
        ["dispel-poison"] = { 0.2471, 1, 0.8706, hex = "3fffde" },
        ["dispel-disease"] = { 1, 0.7294, 0, hex = "ffba00" },
        ["reaction-hostile"] = { 0.8471, 0.3294, 0.03137, hex = "d85408" },
        ["reaction-neutral"] = { 0.9255, 0.9529, 0.3804, hex = "ecf361" },
        ["reaction-friendly"] = { 0.3333, 0.549, 0.9608, hex = "558cf5" },
    },
    blueyellow = {
        ["ember"] = { 1, 0.3333, 0.3255, hex = "ff5553" },
        ["ember-text"] = { 1, 0.6, 0.5961, hex = "ff9998" },
        ["ember-soft"] = { 0.1686, 0.09412, 0.1098, hex = "2b181c" },
        ["unit-fill-low"] = { 0.8314, 0, 0.2784, hex = "d40047" },
        ["unit-fill-low-deep"] = { 0.4157, 0, 0.1412, hex = "6a0024" },
        ["fel"] = { 0, 1, 0.1059, hex = "00ff1b" },
        ["fel-incoming"] = { 0, 1, 0.1059, 0.4, hex = "00ff1b" },
        ["amber"] = { 1, 0.8667, 0.4941, hex = "ffdd7e" },
        ["arcane"] = { 0.302, 0.702, 1, hex = "4db3ff" },
        ["arcane-soft"] = { 0.08235, 0.1176, 0.1529, hex = "151e27" },
        ["arcane-glow"] = { 0.302, 0.702, 1, 0.4, hex = "4db3ff" },
        ["ward"] = { 0.9961, 0.9373, 0.7255, hex = "feefb9" },
        ["ward-absorb"] = { 0.9961, 0.9373, 0.7255, 0.45, hex = "feefb9" },
        ["dispel-magic"] = { 0.3804, 0.5686, 0.8941, hex = "6191e4" },
        ["dispel-curse"] = { 1, 0.01569, 0.9882, hex = "ff04fc" },
        ["dispel-poison"] = { 0.702, 0.9451, 0.7098, hex = "b3f1b5" },
        ["dispel-disease"] = { 0.9294, 0.5608, 0.07059, hex = "ed8f12" },
        ["reaction-hostile"] = { 0.9059, 0.2157, 0.1216, hex = "e7371f" },
        ["reaction-neutral"] = { 1, 1, 0.498, hex = "ffff7f" },
        ["reaction-friendly"] = { 0, 0.9294, 0, hex = "00ed00" },
    },
}
