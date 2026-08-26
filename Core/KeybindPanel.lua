-- KeybindPanel: the small palette that appears while keybind mode is open.
--
-- Visual reference: artifact `suuui-keybind-mode-concept`, section 3. The hint copy, the counters,
-- the per-character toggle and the Save / Discard pair all come from it.
--
-- Shaped after Core/EditPanel.lua, which is the same thing for edit mode: a draggable
-- Layout:CreateWindow, built LAZILY the first time the mode opens (so login never constructs
-- components that fire animations for a panel nobody sees), and whose close box exits the mode.
--
-- WHY THE PANEL EXISTS AT ALL. Commit model C: edits apply LIVE and are persisted on Save. Without
-- a panel there is nowhere to put Save, Discard, or the fact that seven bindings are pending.
local M = {}

local C = SuuUI.Components
local S = SuuUI.UISignals
local T = SuuUI.Theme

-- 320 rather than 280 because the rows carry BLIZZARD'S binding command names, and
-- MULTIACTIONBAR5BUTTON1 is 22 characters before the keys are even appended.
local PANEL_W = 320
-- Wide enough for the longest reading either counter produces ("999 / 999"), because a Text
-- measures itself from the string it was CONSTRUCTED with and the client truncates the overflow to
-- an ellipsis rather than growing the field.
local VALUE_W = 72
-- The change rows' width. Explicit for the same reason VALUE_W is: a row built from "" measures ~0
-- and the client ellipsised every entry to "MULTIACTIONBAR5BUTTON1  unb...". Leaves room for the
-- scrollbar, which sits inside the scroll frame's own width.
local ROW_W = PANEL_W - 2 * 12 - 10

local win, built, buildingDone
local changedText, boundText, perCharToggle, saveBtn
local changeList, listContent, listBox
-- Row Texts, reused across repaints. Pooled rather than recreated because Refresh runs on every
-- binding change and leaking a FontString per keystroke would be a slow leak nobody notices.
local rows = {}
-- Tall enough for four rows, which is where a list stops being glanceable anyway; beyond that the
-- scrollbar does the work instead of the window growing off the screen.
local LIST_H = 68

-- The honest wording for what Discard can do. An unsaved SetBinding survives a reload on its own
-- (measured), so Discard reverts to the last SAVED state rather than undoing everything -- and
-- saying "undo" here would promise something the client does not honour.
local HINT = "Hover any action button and press a key. Mouse buttons and the wheel work too.\n"
    .. "Press ESC on a button to clear all its keys."

local function counts()
    local mode = SuuUI.KeybindMode
    if not mode then return 0, 0, 0 end
    local buttons = mode:GetButtons()
    local bound = 0
    for _, b in ipairs(buttons) do
        local cmd = b.GetBinding and b:GetBinding() or nil
        if cmd and type(GetBindingKey) == "function" and GetBindingKey(cmd) then
            bound = bound + 1
        end
    end
    return mode:ChangedCount(), bound, #buttons
end

--- Re-reads the counters and the toggle. Cheap, so it runs on every binding change.
function M:Refresh()
    if not win then return end
    local mode = SuuUI.KeybindMode
    local changed, bound, total = counts()

    if changedText then changedText:SetText(tostring(changed)) end
    if boundText then boundText:SetText(bound .. " / " .. total) end

    -- The primary action is only primary when there is something to do. A Save button that looks
    -- live with nothing pending invites a click that does nothing.
    if saveBtn and saveBtn.SetEnabled then saveBtn:SetEnabled(changed > 0) end

    if listBox and mode then
        local list = mode:Changes()
        for i, row in ipairs(list) do
            local t = rows[i]
            if not t then
                -- EXPLICIT WIDTH AND WRAP ON. Built from "" a Text measures ~0 wide, so every entry
                -- came back ellipsised -- "MULTIACTIONBAR5BUTTON1  unb...". Width alone is not
                -- enough either: these rows carry Blizzard's own command names, and
                -- MULTIACTIONBAR5BUTTON1 plus two key strings genuinely exceeds one line. Wrapping
                -- costs a second line on the longest entries and is the only option that never
                -- hides part of what the player is about to save.
                t = C.Text({ text = "", size = "sm", color = "text", w = ROW_W,
                    wrap = true, justify = "LEFT" }, listContent)
                rows[i] = t
                listBox:Add(t, { width = ROW_W })
            end
            t:SetText(mode:FormatChange(row))
            -- Cleared reads as a removal, so it takes the danger ink rather than plain text. A
            -- rebind is not a loss and stays neutral.
            t:SetColor(row.cleared and "danger" or "text")
            t:Show()
        end
        -- Surplus rows are HIDDEN, not destroyed: the pool is what keeps a long session from
        -- leaking a FontString per keystroke.
        for i = #list + 1, #rows do rows[i]:Hide() end

        if #list == 0 then
            local t = rows[1]
            if not t then
                t = C.Text({ text = "", size = "sm", color = "textMuted", w = ROW_W,
                    wrap = true, justify = "LEFT" }, listContent)
                rows[1] = t
                listBox:Add(t, { width = ROW_W })
            end
            t:SetText("No changes yet.")
            t:SetColor("muted")
            t:Show()
        end
    end

    if perCharToggle and perCharToggle.SetValue and mode then
        perCharToggle:SetValue(mode:BindingSet() == 2)
    end

    -- Re-fit after the values change: a counter going from "0" to "12 / 96" can re-wrap nothing
    -- today, but the hint is wrapped text and a locale or font change moves it by a line.
    if M._fit then M._fit() end
end

function M:_build()
    win = SuuUI.Layout:CreateWindow({
        id        = "keybind_panel",
        title     = "Keybinds",
        w         = PANEL_W,
        h         = 260,
        resizable = false,
        centered  = true,
    })

    -- Closing the panel LEAVES the mode, matching edit mode's Properties window. buildingDone
    -- guards the initial Hide() below from being read as the player closing it.
    S:Connect(win, S.SIGNALS.VISIBILITY_CHANGED, function(isVisible)
        if not buildingDone then return end
        if not isVisible and SuuUI.KeybindMode and SuuUI.KeybindMode:IsActive() then
            SuuUI.KeybindMode:Disable()
        end
    end)

    local content = win:GetContentFrame()
    -- spaceSm rather than spaceXs between rows, and spaceMd of padding. Reported in game as "pretty
    -- cramped": at 4 units the hint ran into the divider and the two counter rows read as one block.
    local box = SuuUI.Layout:CreateContainer({
        host = content, layout = "flow", dir = "vertical",
        gap = T:GetToken("spaceSm"),
        padding = {
            top = T:GetToken("spaceMd"), right = T:GetToken("spaceMd"),
            bottom = T:GetToken("spaceMd"), left = T:GetToken("spaceMd"),
        },
    })

    local hint = C.Text({ text = HINT, size = "sm", color = "textMuted", wrap = true }, content)
    box:Add(hint, { width = "fill" })
    box:Add(C.Divider({}, content), { width = "fill" })

    local changedRow = SuuUI.Layout:CreateContainer({
        parent = content, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })
    changedRow:Add(C.Text({ text = "Changes", size = "sm", color = "textMuted" }, content),
        { width = "fill" })
    -- EXPLICIT WIDTH, and both the prop and the Add opt. A Text measures itself from the string it
    -- was CONSTRUCTED with -- "0" is a few units wide -- so a later SetText("63 / 96") overflowed
    -- its allocation and the client truncated it to an ellipsis. Reported in game as "the number of
    -- changed and bound keybinds gets shortened to dots". Sized for the widest plausible reading.
    changedText = C.Text({ text = "0", size = "sm", color = "text", w = VALUE_W, justify = "RIGHT" },
        content)
    changedRow:Add(changedText, { width = VALUE_W })
    box:Add(changedRow, { width = "fill" })

    -- THE CHANGE LIST. A count answers "is there work pending"; the list answers "what did I
    -- actually do", which is the question a player about to press Save is asking. Capped and
    -- scrollable so a long editing session cannot grow the window off the screen.
    changeList = C.ScrollFrame({ w = PANEL_W - 2 * (T:GetToken("spaceMd") or 12), h = LIST_H },
        content)
    box:Add(changeList, { width = "fill", height = LIST_H })    listContent = changeList:GetContent()
    listBox = SuuUI.Layout:CreateContainer({
        parent = listContent, layout = "flow", dir = "vertical",
        gap = T:GetToken("spaceXxs"),
    })

    local boundRow = SuuUI.Layout:CreateContainer({
        parent = content, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })
    boundRow:Add(C.Text({ text = "Bound", size = "sm", color = "textMuted" }, content),
        { width = "fill" })
    boundText = C.Text({ text = "0 / 0", size = "sm", color = "text", w = VALUE_W,
        justify = "RIGHT" }, content)
    boundRow:Add(boundText, { width = VALUE_W })
    box:Add(boundRow, { width = "fill" })

    box:Add(C.Divider({}, content), { width = "fill" })

    local perCharRow = SuuUI.Layout:CreateContainer({
        parent = content, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })
    perCharRow:Add(C.Text({ text = "Character-specific", size = "sm", color = "textMuted" },
        content), { width = "fill" })
    perCharToggle = C.Toggle({
        value = false,
        onChange = function(value)
            -- REFUSED while dirty, by the mode. Switching sets LOADS the target over the live one,
            -- so unsaved edits would vanish without being mentioned. Put the toggle back and say why.
            local mode = SuuUI.KeybindMode
            if not (mode and mode:SetPerCharacter(value)) then
                M:Refresh()
                C.Notice({
                    title = "Keybinds",
                    message = "Save or discard your changes before switching between "
                        .. "account-wide and character-specific keybinds.",
                    tone = "warning",
                })
                return
            end
            M:Refresh()
        end,
    }, content)
    perCharRow:Add(perCharToggle)
    box:Add(perCharRow, { width = "fill" })

    local btnRow = SuuUI.Layout:CreateContainer({
        parent = content, layout = "flow", dir = "horizontal",
        gap = T:GetToken("spaceXs"), align = "center",
    })
    saveBtn = C.Button({
        label = "Save",
        onClick = function()
            if SuuUI.KeybindMode then SuuUI.KeybindMode:Save() end
            M:Refresh()
        end,
    }, content)
    local discardBtn = C.Button({
        label = "Discard",
        -- NOT styled danger. Discard reverts to the last saved state; it is a retreat, not a
        -- destructive act, and dressing it in red would make the safe option look like the scary one.
        onClick = function()
            if SuuUI.KeybindMode then SuuUI.KeybindMode:Discard() end
            M:Refresh()
        end,
    }, content)
    btnRow:Add(saveBtn, { width = "fill" })
    btnRow:Add(discardBtn, { width = "fill" })
    box:Add(btnRow, { width = "fill" })

    -- THE WINDOW HUGS ITS CONTENT. A vertical flow packs from the top, so a fixed height left dead
    -- space under the buttons -- reported twice in game as "the buttons are not aligned to the bottom
    -- of the window".
    --
    -- MEASURED WITH GetContentSize, NOT with the SIZE_CHANGED signal, and that distinction is the
    -- whole bug in the first attempt. For a `host` container `self._frame` IS the window's content
    -- frame, so the signal reports the height the WINDOW gave it -- feeding that back into SetSize
    -- measures the window against itself and tells you nothing about the children. GetContentSize
    -- returns the bounding box of the children, which is the number actually wanted.
    local titleH = T:GetToken("sizeTitleBar") or 26
    local function fit()
        local _, contentH = box:GetContentSize()
        if not (contentH and contentH > 0) then return end
        local want = contentH + titleH
        local have = win:GetHeight()
        if have and math.abs(have - want) < 1 then return end
        win:SetSize(PANEL_W, want)
    end
    M._fit = fit
    fit()

    win:Hide()
    buildingDone = true
end

--- Shows or hides the panel with the mode.
function M:Init()
    SuuUI.Settings:Watch("_layout", "keybind_mode", function(isActive)
        if isActive and not built then
            built = true
            M:_build()
        end
        if not win then return end
        if isActive then
            M:Refresh()
            win:Show()
        else
            win:Hide()
        end
    end, "_keybindpanel_mode", { immediate = true })

    -- The counters follow the bindings, so they track a write made on any button without the
    -- overlays having to know the panel exists.
    local evt = CreateFrame("Frame")
    evt:RegisterEvent("UPDATE_BINDINGS")
    evt:SetScript("OnEvent", function() M:Refresh() end)
    M._evt = evt
end

--- The window handle, for specs.
function M:GetWindow() return win end

--- The panel's controls, for specs. Not part of the public surface.
function M:_controls()
    return {
        save = saveBtn, perChar = perCharToggle,
        changed = changedText, bound = boundText,
        rows = rows, list = changeList,
    }
end

SuuUI.KeybindPanel = M
