-- UI/KeybindMode.lua
-- Keybind mode: hover any SuuUI action, stance or pet button and press a key
-- (with Shift, Ctrl or Alt as you like), a mouse button (middle, 4, 5) or turn
-- the wheel to bind it. Delete clears the hovered button's keys; Esc or Done
-- closes. "/suu keybind" toggles it.
--
-- Bindings go to the game's own commands (ACTIONBUTTON3, MULTIACTIONBAR1BUTTON5,
-- SHAPESHIFTBUTTON2, BONUSACTIONBUTTON4), so they show in the game's Key
-- Bindings window too, and SuuUI's bars pick them up from there. Binding a key
-- that did something else says what it replaced. Bindings can't change in
-- combat, so the mode closes when combat starts.

local _, ns = ...

local UI, T, Events, Layout = ns.UI, ns.Tokens, ns.Events, ns.Layout
local S = T.space

local KM = {}
ns.KeybindMode = KM

local active, target
local panel, status, highlight, catcher
local hooked = {}

local IGNORED = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
                  LMETA = true, RMETA = true, UNKNOWN = true }
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

-- The key with its modifiers, as the binding API spells it ("SHIFT-1").
local function withModifiers(key)
    if not key or IGNORED[key] then return nil end
    local mods = ""
    if IsAltKeyDown() then mods = mods .. "ALT-" end
    if IsControlKeyDown() then mods = mods .. "CTRL-" end
    if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
    if IsMetaKeyDown and IsMetaKeyDown() then mods = mods .. "META-" end
    return mods .. key
end

local function commandName(cmd)
    return _G["BINDING_NAME_" .. cmd] or cmd
end

local function keyText(key)
    return GetBindingText and GetBindingText(key) or key
end

local function setStatus(text)
    if status then status:SetValue(text or "") end
end

local function showTip()
    if not target then return end
    GameTooltip:SetOwner(highlight, "ANCHOR_TOP")
    GameTooltip:AddLine(target.bindLabel or target.bindCommand, 1, 1, 1)
    local keys = { GetBindingKey(target.bindCommand) }
    if #keys == 0 then
        GameTooltip:AddLine("Not bound", UI.RGBA("ink-muted"))
    else
        for _, key in ipairs(keys) do GameTooltip:AddLine(keyText(key), UI.RGBA("ink")) end
    end
    GameTooltip:AddLine("Press a key to bind it. Delete clears.", UI.RGBA("ink-muted"))
    GameTooltip:Show()
end

local function save()
    SaveBindings(GetCurrentBindingSet())
end

local function bind(key)
    if not (target and key) or InCombatLockdown() then return end
    local cmd = target.bindCommand
    local was = GetBindingAction(key)
    if was == cmd then return end
    if not SetBinding(key, cmd) then
        setStatus(("%s can't be bound."):format(keyText(key)))
        return
    end
    save()
    local line = ("%s → %s"):format(keyText(key), target.bindLabel or cmd)
    if was and was ~= "" then line = line .. (" (was %s)"):format(commandName(was)) end
    setStatus(line)
    showTip()
end

local function clear()
    if not target or InCombatLockdown() then return end
    local keys = { GetBindingKey(target.bindCommand) }
    if #keys == 0 then return end
    for _, key in ipairs(keys) do SetBinding(key) end
    save()
    setStatus(("%s: no keys."):format(target.bindLabel or target.bindCommand))
    showTip()
end

--------------------------------------------------------------------------------
-- The hovered button
--------------------------------------------------------------------------------

local function setTarget(b)
    target = b
    if not b then
        highlight:Hide()
        if GameTooltip:GetOwner() == highlight then GameTooltip:Hide() end
        return
    end
    highlight:ClearAllPoints()
    highlight:SetAllPoints(b)
    highlight:Show()
    showTip()
end

local function buildHighlight()
    -- Over the hovered button, so clicks bind instead of casting.
    local h = CreateFrame("Button", nil, UIParent)
    h:SetFrameStrata("FULLSCREEN_DIALOG")
    h:EnableMouse(true)
    h:EnableMouseWheel(true)
    h:RegisterForClicks("AnyDown")
    local fill = h:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    UI.PaintFill(fill, "arcane", 0.25)
    UI.Border(h, "arcane", { layer = "OVERLAY" })
    h:SetScript("OnMouseDown", function(_, button) bind(withModifiers(MOUSE[button])) end)
    h:SetScript("OnMouseWheel", function(_, delta) bind(withModifiers(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")) end)
    h:SetScript("OnLeave", function() setTarget(nil) end)
    h:Hide()
    return h
end

local function hookButtons()
    for _, b in ipairs(UI.actionButtons) do
        if b.bindCommand and not hooked[b] then
            hooked[b] = true
            b:HookScript("OnEnter", function(self)
                if active then
                    GameTooltip:Hide()
                    setTarget(self)
                end
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- The panel and the keyboard
--------------------------------------------------------------------------------

local function buildPanel()
    local p = UI.Panel(ns.Root, { title = "Keybind mode", width = 320 })
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetPoint("TOP", ns.Root, "TOP", 0, -160)
    p:EnableMouse(true)
    local stack = Layout.Stack(p.body, { gap = S["space-4"], autoSize = "height" })

    local hint = UI.Text(p.body, "body", "ink")
    hint:SetWordWrap(true)
    hint:SetJustifyH("LEFT")
    hint:SetFixedWidth(296)
    hint:SetValue("Hover a button and press a key, a mouse button or the wheel. Shift, Ctrl and Alt combine. Delete clears the button's keys.")
    stack:Add(hint)

    status = UI.Text(p.body, "caption", "ink-muted")
    status:SetWordWrap(true)
    status:SetJustifyH("LEFT")
    status:SetFixedWidth(296)
    status:SetValue(" ")
    stack:Add(status)

    local done = UI.Button(p.body, { text = "Done", variant = "primary", onClick = function() KM.Exit() end })
    stack:Add(done)
    return p
end

local function buildCatcher()
    local c = CreateFrame("Frame", nil, UIParent)
    c:SetFrameStrata("FULLSCREEN_DIALOG")
    c:EnableKeyboard(true)
    c:SetPropagateKeyboardInput(false)
    c:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then KM.Exit()
        elseif key == "PRINTSCREEN" then Screenshot()
        elseif key == "DELETE" then clear()
        else bind(withModifiers(key)) end
    end)
    c:Hide()
    return c
end

local function setGrid(on)
    for _, b in ipairs(UI.actionButtons) do
        if b.bindCommand and b.SetGrid then b:SetGrid(on) end
    end
end

function KM.IsActive()
    return active
end

function KM.Enter()
    if active then return true end
    if InCombatLockdown() then
        ns.Print("Keybind mode opens out of combat.")
        return false
    end
    if ns.EditMode and ns.EditMode.IsActive() then ns.EditMode.Exit() end
    if ns.SettingsWindow and ns.SettingsWindow.Close then ns.SettingsWindow.Close() end
    panel = panel or buildPanel()
    highlight = highlight or buildHighlight()
    catcher = catcher or buildCatcher()
    hookButtons()
    active = true
    setStatus(" ")
    panel:Show()
    catcher:Show()
    setGrid(true) -- empty slots can take keys too
    Events.Emit("SUUUI_KEYBINDMODE_CHANGED", true)
    return true
end

function KM.Exit()
    if not active then return end
    active = false
    setTarget(nil)
    panel:Hide()
    catcher:Hide()
    setGrid(false)
    Events.Emit("SUUUI_KEYBINDMODE_CHANGED", false)
end

function KM.Toggle()
    if active then KM.Exit() else KM.Enter() end
end

Events.OnGame("PLAYER_REGEN_DISABLED", function()
    if active then
        KM.Exit()
        ns.Print("Keybind mode closed: combat started.")
    end
end, "KeybindMode")

ns.RegisterCommand("keybind", "Bind keys to SuuUI's action bars: hover a button and press a key.", KM.Toggle)
