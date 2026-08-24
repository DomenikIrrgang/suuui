-- Tooltips: reskins the client's own tooltips to match SuuUI, and supplies the information
-- colour the client withholds.
--
-- Plan and the recorded in-game probe results: .kiro/specs/tooltips.md
--
-- Three facts shape the whole plugin, all measured on this client rather than assumed:
--
--   GameTooltip is NOT PROTECTED, so nothing here needs a combat guard. ElvUI restyles
--   tooltips unconditionally with no taint comment anywhere in its tooltip path.
--
--   TooltipDataProcessor.AddTooltipPostCall EXISTS HERE AND MUST NOT BE USED. ElvUI
--   explicitly excludes TBC from it and falls back to the legacy OnTooltipSet* scripts; a
--   design built on the modern API compiles and silently does nothing.
--
--   Blizzard's border is a NINESLICE, so SetBackdrop alone leaves it drawing underneath.
local type, next = type, next

local PLUGIN_ID = "tooltips"
local OWNER     = "tooltips"

local Skin      = SuuUI._Tooltips.Skin
local Signal    = SuuUI._Tooltips.Signal
local Anchor    = SuuUI._Tooltips.Anchor
local HealthBar = SuuUI._Tooltips.HealthBar
local Content   = SuuUI._Tooltips.Content

-- hooksecurefunc and HookScript CANNOT BE UNDONE, so every hook is installed at most once and
-- asks a flag on each call instead of assuming it should act. Same shape as the Blizzard
-- suppression pattern and for the same reason: onDisable has to be able to hand the tooltip
-- back, and a hook that always restyled would make that impossible.
local hooked = false

local function installHooks()
    if hooked then return end
    hooked = true

    -- THE durability mechanism, and it is one line. Blizzard re-stamps a tooltip's backdrop at
    -- moments unrelated to anything the player did, so a one-shot pass in onEnable is silently
    -- reverted. This also covers tooltips that are in no list of ours.
    if type(_G.SharedTooltip_SetBackdropStyle) == "function" then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt, style, isEmbedded)
            if not SuuUI.Settings:Get(PLUGIN_ID, "enabled") then return end
            Skin.Style(tt, style, isEmbedded)
        end)
    else
        SuuUI.Fault("tooltips: SharedTooltip_SetBackdropStyle is absent -- the tooltip skin "
            .. "will be reverted whenever the client re-stamps a backdrop")
    end

    -- Placement. Blizzard's function is hooked, never replaced.
    if type(_G.GameTooltip_SetDefaultAnchor) == "function" then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tt, parent)
            Anchor.Place(tt, parent)
        end)
    end

    -- Content. The LEGACY scripts, deliberately -- see the header.
    local tt = _G.GameTooltip
    if tt and type(tt.HookScript) == "function" then
        tt:HookScript("OnTooltipSetItem", function(self)
            Signal.OnItem(self)
            Content.OnItem(self)
        end)
        tt:HookScript("OnTooltipSetSpell", function(self)
            Signal.OnSpell(self)
            Content.OnSpell(self)
        end)
        tt:HookScript("OnTooltipCleared",  Signal.OnCleared)

        -- The unit script drives three things, and the ORDER matters: content lines are APPENDED,
        -- so they must land before the health bar reserves space against the tooltip's settled
        -- edges -- otherwise the bar is placed against a box that is about to grow.
        tt:HookScript("OnTooltipSetUnit", function(self)
            Signal.OnUnit(self)
            Content.OnUnit(self)
            local _, unit = self:GetUnit()
            if unit then HealthBar.Apply(self, unit) end
        end)

        tt:HookScript("OnTooltipCleared", HealthBar.OnCleared)

        -- An AURA tooltip does not fire OnTooltipSetSpell -- the client builds it through the
        -- SetUnitBuff / SetUnitDebuff / SetUnitAura setters instead, so those are hooked
        -- directly. Missing this is why a buff tooltip showed no id while a spellbook one did.
        for _, name in next, { "SetUnitBuff", "SetUnitDebuff", "SetUnitAura" } do
            if type(tt[name]) == "function" and type(_G.hooksecurefunc) == "function" then
                local filter = name == "SetUnitDebuff" and "HARMFUL" or "HELPFUL"
                pcall(_G.hooksecurefunc, tt, name, function(self, unit, index, given)
                    Content.OnAura(self, unit, index, given or filter)
                end)
            end
        end

        -- An ACTION BUTTON opens its tooltip with SetAction(slot), which is neither
        -- OnTooltipSetSpell nor a route GetSpell can answer -- so it needs its own hook, reading
        -- the id off the slot. This is why an action bar's tooltips showed no id.
        if type(tt.SetAction) == "function" and type(_G.hooksecurefunc) == "function" then
            pcall(_G.hooksecurefunc, tt, "SetAction", function(self, slot)
                Content.OnAction(self, slot)
            end)
        end
    end

    -- Without this, a modifier-gated line only appears on the NEXT mouseover: the player holds
    -- shift over a unit and nothing happens, which reads as the setting being broken.
    --
    -- It re-drives whatever the tooltip is SHOWING, not just a unit. Only a unit tooltip can be
    -- rebuilt from the tooltip itself (through GetUnit); a spell or an aura cannot, because the
    -- tooltip does not remember what it was pointed at. Content records that, so this covers all
    -- of them -- the earlier version handled units alone, which meant `show_ids = SHIFT` silently
    -- never worked for spells or buffs.
    local mod = CreateFrame("Frame")
    mod:RegisterEvent("MODIFIER_STATE_CHANGED")
    mod:SetScript("OnEvent", function()
        if not SuuUI.Settings:Get(PLUGIN_ID, "enabled") then return end
        if SuuUI.Settings:Get(PLUGIN_ID, "show_ids") == "HIDE" then return end
        local g = _G.GameTooltip
        if not g or not g:IsShown() then return end
        Content.Redraw(g)
    end)

    HealthBar.Install()
end

local plugin = SuuUI:CreatePlugin({
    id      = "tooltips",
    name    = "Tooltips",
    version = "0.1",

    onInit = function(p)
        local T = SuuUI.Theme
        SuuUI.Settings:Register(PLUGIN_ID, {
            { key = "enabled", label = "Enable Tooltip Skin", type = "toggle", default = true },

            { key = "", label = "Appearance", type = "section" },
            { key = "signal_border", label = "Colour The Border By Quality", type = "toggle",
              default = true },
            { key = "backdrop_alpha", label = "Background Opacity", type = "slider",
              default = T:GetToken("opacityPanel") or 0.97, min = 0, max = 1, step = 0.01 },
            { key = "font_size", label = "Text Size", type = "slider",
              default = T:GetFontSize("sm") or 11, min = 8, max = 20, step = 1 },
            { key = "header_font_size", label = "Title Size", type = "slider",
              default = T:GetFontSize("md") or 13, min = 8, max = 24, step = 1 },
            { key = "comparison_font_size", label = "Comparison Text Size", type = "slider",
              default = T:GetFontSize("sm") or 11, min = 8, max = 20, step = 1 },

            { key = "", label = "Health Bar", type = "section" },
            { key = "health_position", label = "Position", type = "dropdown", default = "BOTTOM",
              options = {
                  { value = "BOTTOM",   label = "Bottom of the tooltip" },
                  { value = "TOP",      label = "Top of the tooltip" },
                  { value = "DISABLED", label = "Hidden" },
              } },
            { key = "health_height", label = "Height", type = "slider",
              default = 12, min = 4, max = 32, step = 1,
              enabledIf = { key = "health_position", notEquals = "DISABLED" } },
            { key = "health_text", label = "Show Health Value", type = "toggle", default = true,
              enabledIf = { key = "health_position", notEquals = "DISABLED" } },
            { key = "health_text_mode", label = "Health Value Format", type = "dropdown",
              default = "current_max", options = SuuUI.Readout.Options(),
              enabledIf = "health_text" },

            { key = "", label = "Content", type = "section" },
            { key = "item_level", label = "Show Item Level", type = "toggle", default = true },
            { key = "item_count", label = "Show How Many You Carry", type = "toggle",
              default = true },
            { key = "item_count_bank", label = "Include The Bank", type = "toggle",
              default = true, enabledIf = "item_count" },
            { key = "sell_price", label = "Show Sell Price", type = "toggle", default = false },
            { key = "unit_target", label = "Show What A Unit Is Targeting", type = "toggle",
              default = true },
            { key = "unit_role", label = "Show Group Role", type = "toggle", default = true },
            { key = "guild_rank", label = "Show Guild Rank", type = "toggle", default = true },
            -- Its OWN toggle, independent of Show IDs. ElvUI puts the caster on the id's line as
            -- its right-hand value, which is tidier but means a player who only wants to know who
            -- buffed them has to switch the noisier ids on as well.
            { key = "aura_caster", label = "Show Who Cast A Buff Or Debuff", type = "toggle",
              default = true },
            { key = "level_difficulty", label = "Colour Level By Difficulty", type = "toggle",
              default = true },
            -- Default SHOW, matching ElvUI's own `modifierID = 'SHOW'`. It shipped as HIDE first
            -- and that was wrong: a feature somebody asked for, switched off by default, is
            -- indistinguishable from a feature that does not work -- which is exactly how it was
            -- reported. A player who does not want ids can turn them off; one who does should not
            -- have to discover a dropdown to see the thing they asked for.
            { key = "show_ids", label = "Show IDs", type = "dropdown", default = "SHOW",
              options = {
                  { value = "HIDE",  label = "Never" },
                  { value = "SHOW",  label = "Always" },
                  { value = "SHIFT", label = "While Shift is held" },
                  { value = "CTRL",  label = "While Ctrl is held" },
                  { value = "ALT",   label = "While Alt is held" },
              } },

            { key = "", label = "Placement", type = "section" },
            { key = "anchor_mode", label = "Anchor", type = "dropdown", default = "mover",
              options = {
                  { value = "mover",  label = "Fixed position" },
                  { value = "cursor", label = "Follow the cursor" },
              } },
            { key = "x_offset", label = "X Offset", type = "slider",
              default = 0, min = -200, max = 200, step = 1 },
            { key = "y_offset", label = "Y Offset", type = "slider",
              default = 0, min = -200, max = 200, step = 1 },
            -- Written by MoveableFrame, so it needs a home in the profile and no control.
            { key = "position", type = "position", default = false },
        })

        -- No `immediate` on the plugin's own enabled watcher: Plugins:autoEnable already
        -- applies the stored value during the login pass, and an immediate callback would run
        -- onEnable from inside the init pass.
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, OWNER .. ".enabled")

        -- Every appearance key needs a watcher or it is read only at construction and appears
        -- to do nothing until a reload -- a gap already reported twice in this project.
        for _, key in next, { "backdrop_alpha", "signal_border" } do
            SuuUI.Settings:Watch(PLUGIN_ID, key, function()
                if p:IsEnabled() then Skin.StyleAll() end
            end, OWNER .. "." .. key)
        end

        for _, spec in next, Skin.FONT_OBJECTS do
            SuuUI.Settings:Watch(PLUGIN_ID, spec.sizeKey, function()
                if p:IsEnabled() then Skin.ApplyFonts() end
            end, OWNER .. "." .. spec.sizeKey)
        end

        for _, key in next, { "anchor_mode", "x_offset", "y_offset" } do
            SuuUI.Settings:Watch(PLUGIN_ID, key, function()
                -- Nothing to re-place: the next tooltip to open reads the new value. Only the
                -- mover has to exist, and only in fixed mode.
                if p:IsEnabled() then Anchor.EnsureMover() end
            end, OWNER .. "." .. key)
        end

        -- The health bar's own keys. Nothing is re-placed here either: the bar is positioned on
        -- every unit tooltip, so the next mouseover reads the new height and position. What DOES
        -- have to happen now is releasing reserved padding when the bar is switched off, or the
        -- gap it reserved outlives it.
        for _, key in next, { "health_position", "health_height", "health_text",
                              "health_text_mode" } do
            SuuUI.Settings:Watch(PLUGIN_ID, key, function()
                if not p:IsEnabled() then return end
                if HealthBar.position() == "DISABLED" then
                    HealthBar.Teardown()
                else
                    HealthBar.UpdateText()
                end
            end, OWNER .. "." .. key)
        end

        -- A theme change moves the surface colour, the border and the resolved font face.
        SuuUI.Events:On("SUUUI_THEME_CHANGED", function()
            if not p:IsEnabled() then return end
            Skin.StyleAll()
            Skin.ApplyFonts()
            HealthBar.ApplyTheme()
        end, OWNER)
    end,

    onEnable = function()
        installHooks()
        Anchor.EnsureMover()
        Skin.StyleAll()
        Skin.ApplyFonts()
    end,

    onDisable = function()
        -- The hooks stay installed -- they cannot be removed -- but every one of them asks the
        -- `enabled` setting or a per-frame flag before acting, so with the plugin off they are
        -- inert. What CAN be handed back is handed back.
        Signal.ResetAll()
        Skin.Forget()
        HealthBar.Teardown()
        Anchor.Release()
    end,
})

SuuUI._Tooltips.plugin = plugin
