local C = SuuUI.Components

local ModalMeta = {}
ModalMeta.__index = ModalMeta

function ModalMeta:Show()
    self._overlay:Show()
    self._window:Show()
    SuuUI.Anim.Presets.FadeIn(self._overlay, SuuUI.Theme:GetToken("animFast"))
    SuuUI.Anim.Presets.FadeIn(self._window, SuuUI.Theme:GetToken("animFast"))
    if self._input then
        self._input:SetFocus()
    end
end

function ModalMeta:Hide()
    local T = SuuUI.Theme
    SuuUI.Anim.Presets.FadeOut(self._overlay, T:GetToken("animFast"))
    SuuUI.Anim:New({
        target   = self._window,
        property = "alpha",
        from     = self._window:GetAlpha(), to = 0,
        duration = T:GetToken("animFast") or 0.12,
        easing   = "easeIn",
        onDone   = function()
            self._window:Hide()
            if self._input then self._input:SetValue("") end
        end,
    }):Play()
end

function ModalMeta:IsShown()
    return self._window:IsShown()
end

function ModalMeta:Destroy()
    self._overlay:Hide()
    self._window:Hide()
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
end

function ModalMeta:GetFrame()
    return self._window
end

function ModalMeta:ApplyTheme()
    local T  = SuuUI.Theme
    local bg = T:GetToken("colorBg")
    local bd = T:GetToken("colorBorder")
    local bw = T:GetToken("borderWidth") or 1
    self._window:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = bw,
        insets   = {left=bw, right=bw, top=bw, bottom=bw},
    })
    if bg then self._window:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
    if bd then self._window:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4]) end
end

--- Creates a modal dialog with optional input field.
-- @param props table  { title, message, input, onConfirm, onCancel, confirmText, cancelText }
-- @param parent frame  Optional parent (defaults to UIParent)
-- @return table  Modal handle
function SuuUI.Components.Modal(props, parent)
    parent = parent or UIParent

    local w = props.w or 360
    
    -- Calculate height based on content
    local contentHeight = 16  -- Top padding
    if props.title then contentHeight = contentHeight + 24 end
    if props.message then contentHeight = contentHeight + 24 end
    if props.input then contentHeight = contentHeight + 8 + 32 end  -- gap + input + spacing
    contentHeight = contentHeight + 8 + 28 + 16  -- gap + buttons + bottom padding
    
    local h = props.h or contentHeight

    -- Semi-transparent overlay to block clicks
    local overlay = CreateFrame("Frame", nil, parent)
    overlay:SetAllPoints(parent)
    overlay:SetFrameStrata("DIALOG")
    overlay:EnableMouse(true)
    overlay:SetScript("OnMouseDown", function() end)
    local overlayTex = overlay:CreateTexture(nil, "BACKGROUND")
    overlayTex:SetAllPoints(overlay)
    overlayTex:SetColorTexture(0, 0, 0, 0.7)
    overlay:Hide()

    -- Modal window
    local window = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    window:SetSize(w, h)
    window:SetPoint("CENTER", parent, "CENTER", 0, 0)
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window:Hide()

    local id = "modal_" .. tostring(window)
    local handle = setmetatable({
        _window  = window,
        _overlay = overlay,
        _eid     = id,
    }, ModalMeta)

    local yOffset = -16

    -- Title
    if props.title then
        local title = C.Text({ text=props.title, size="lg", color="text" }, window)
        title:SetPoint("TOP", window, "TOP", 0, yOffset)
        yOffset = yOffset - 24
    end

    -- Message
    if props.message then
        local msg = C.Text({ text=props.message, size="md", color="muted" }, window)
        msg:SetPoint("TOP", window, "TOP", 0, yOffset)
        yOffset = yOffset - 24
    end

    -- Input field (optional)
    local input
    if props.input then
        yOffset = yOffset - 8
        input = C.Input({
            value = "",
            w     = w - 32,
            h     = 24,
            onEnter = function(text)
                if props.onConfirm then
                    props.onConfirm(text)
                end
                handle:Hide()
            end,
        }, window)
        input:SetPoint("TOP", window, "TOP", 0, yOffset)
        handle._input = input
        yOffset = yOffset - 32
    end

    -- Button row
    yOffset = yOffset - 8
    local btnW = 100
    local btnGap = 12
    local totalBtnW = btnW * 2 + btnGap
    local btnStartX = -(totalBtnW / 2) + (btnW / 2)

    local confirmBtn = C.Button({
        label   = props.confirmText or "Confirm",
        w       = btnW,
        h       = 28,
        onClick = function()
            if props.onConfirm then
                local val = input and input:GetValue() or nil
                props.onConfirm(val)
            end
            handle:Hide()
        end,
    }, window)
    confirmBtn:SetPoint("TOP", window, "TOP", btnStartX, yOffset)

    local cancelBtn = C.Button({
        label   = props.cancelText or "Cancel",
        w       = btnW,
        h       = 28,
        onClick = function()
            if props.onCancel then props.onCancel() end
            handle:Hide()
        end,
    }, window)
    cancelBtn:SetPoint("LEFT", confirmBtn:GetFrame(), "RIGHT", btnGap, 0)

    -- ESC to close
    window:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            if props.onCancel then props.onCancel() end
            handle:Hide()
        end
    end)
    window:EnableKeyboard(true)
    window:SetPropagateKeyboardInput(false)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)

    return handle
end
