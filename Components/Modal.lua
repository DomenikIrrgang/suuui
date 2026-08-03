local C = SuuUI.Components
local S = SuuUI.UISignals

-- Modal-specific signals
C.MODAL_SIGNALS = {
    CONFIRMED = "modal.confirmed",  -- Args: inputValue (or nil)
    CANCELLED = "modal.cancelled",  -- Args: none
}

local CONFIRMED = C.MODAL_SIGNALS.CONFIRMED
local CANCELLED = C.MODAL_SIGNALS.CANCELLED

local ModalMeta = {}
ModalMeta.__index = ModalMeta

function ModalMeta:Show()
    self._overlay:Show()
    self._window:Show()
    SuuUI.Anim.Presets.FadeIn(self._overlay, SuuUI.Theme:GetToken("animFast"))
    SuuUI.Anim.Presets.FadeIn(self._window, SuuUI.Theme:GetToken("animFast"))
    if self._input then self._input:SetFocus() end
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
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
            -- One-shot modals (notices) free themselves once the fade finishes, rather
            -- than leaving a hidden frame behind on every message.
            if self._autoDestroy then self:Destroy() end
        end,
    }):Play()
    S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
end

function ModalMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._shellBox:Destroy()
    self._overlay:Hide()
    self._window:Hide()
    self._shell:Hide()
end

function ModalMeta:ApplyTheme()
    SuuUI.Backdrop.Apply(self._window, { bg = "colorBg", border = "colorBorder" })
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize. Show and Hide are defined
-- above and survive: they drive the overlay, the fade, and optional autoDestroy.
SuuUI.Components.InstallBase(ModalMeta, "_window")

--- Creates a modal dialog with optional input field.
-- Emits CONFIRMED (value), CANCELLED, VISIBILITY_CHANGED.
-- @param props table  { title, message, input, onConfirm, onCancel, confirmText,
--   cancelText, confirmVariant, dismissOnly, autoDestroy, w }
--   confirmVariant: nil | "danger" | "success" | "warning" — tints the confirm button
--   dismissOnly: true drops the cancel button, for notices with nothing to cancel
--   autoDestroy: true frees the modal once it finishes hiding (one-shot dialogs)
-- @param parent frame  Optional parent (defaults to UIParent)
-- @return table  Modal handle
function SuuUI.Components.Modal(props, parent)
    parent = parent or UIParent
    local T   = SuuUI.Theme
    local gap = T:GetToken("spaceSm") or 8
    local pad = T:GetToken("spaceLg") or 16
    local w   = props.w or 360

    -- The shell container covers the parent. Sized explicitly rather than with fill:
    -- modals are transient, and fill would hook the parent's resize every time.
    local shellBox = SuuUI.Layout:CreateContainer({
        parent = parent,
        layout = "stack",
        w      = parent:GetWidth(),
        h      = parent:GetHeight(),
    })
    local shell = shellBox:GetFrame()
    shell:SetFrameStrata("DIALOG")

    local overlay = CreateFrame("Frame", nil, shell)
    overlay:EnableMouse(true)
    overlay:SetScript("OnMouseDown", function() end)
    overlay:Hide()
    shellBox:Add(overlay)

    local overlayBox = SuuUI.Layout:CreateContainer({ host = overlay, layout = "stack" })
    local overlayTex = overlay:CreateTexture(nil, "BACKGROUND")
    overlayTex:SetColorTexture(0, 0, 0, T:GetToken("opacityOverlay") or 0.7)
    overlayBox:Add(overlayTex)

    local window = CreateFrame("Frame", nil, shell, "BackdropTemplate")
    window:EnableMouse(true)
    window:Hide()
    shellBox:Add(window, { align = "center", valign = "center", width = w, height = 1 })

    local id = "modal_" .. tostring(window)
    local handle = setmetatable({
        _window      = window,
        _overlay     = overlay,
        _shell       = shell,
        _shellBox    = shellBox,
        _eid         = id,
        _autoDestroy = props.autoDestroy or false,
    }, ModalMeta)

    local root = SuuUI.Layout:CreateContainer({
        host    = window,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        align   = "center",
        padding = { top=pad, right=pad, bottom=pad, left=pad },
    })

    -- Heights omitted throughout: text re-measures itself when a font token changes and
    -- the input derives its height from the size tokens, so the modal re-flows instead
    -- of clipping.
    if props.title then
        local title = C.Text({ text=props.title, size="lg", color="text", justify="CENTER" }, root:GetFrame())
        root:Add(title, { width = "fill" })
    end

    if props.message then
        local msg = C.Text({ text=props.message, size="md", color="muted", justify="CENTER" }, root:GetFrame())
        root:Add(msg, { width = "fill" })
    end

    local input
    if props.input then
        input = C.Input({ value = "", w = w - pad * 2 }, root:GetFrame())
        root:Add(input, { width = "fill" })
        handle._input = input
    end

    local function confirm()
        local val = input and input:GetValue() or nil
        if props.onConfirm then props.onConfirm(val) end
        S:Emit(handle, CONFIRMED, val)
        handle:Hide()
    end

    local function cancel()
        if props.onCancel then props.onCancel() end
        S:Emit(handle, CANCELLED)
        handle:Hide()
    end

    if input then
        S:Connect(input, C.INPUT_SIGNALS.SUBMITTED, confirm)
    end

    local btnRow = SuuUI.Layout:CreateContainer({
        parent = root:GetFrame(),
        layout = "flow",
        dir    = "horizontal",
        gap    = gap + 4,
        align  = "center",
    })

    -- Buttons hug their labels, so the row is sized from its content to stay centred.
    -- The intent colour lives on the confirm button, where the action is actually taken,
    -- rather than on the button that merely opens this dialog.
    local confirmBtn = C.Button({
        label   = props.confirmText or "Confirm",
        minW    = 100,
        variant = props.confirmVariant,
    }, btnRow:GetFrame())
    btnRow:Add(confirmBtn)
    S:Connect(confirmBtn, S.SIGNALS.CLICKED, confirm)

    -- A notice has nothing to cancel: one button that just dismisses it
    if not props.dismissOnly then
        local cancelBtn = C.Button({ label = props.cancelText or "Cancel", minW = 100 },
            btnRow:GetFrame())
        btnRow:Add(cancelBtn)
        S:Connect(cancelBtn, S.SIGNALS.CLICKED, cancel)
    end

    local rowW = btnRow:GetContentSize()
    root:Add(btnRow, { width = rowW })

    -- Size the window to the composed content through the stack container
    local function fitWindow(h)
        shellBox:SetChildProps(window, {
            align = "center", valign = "center", width = w, height = h,
        })
    end
    S:Connect(root, S.SIGNALS.SIZE_CHANGED, function(_, h) fitWindow(h) end)
    local _, contentH = root:GetContentSize()
    fitWindow(props.h or contentH)

    window:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then cancel() end
    end)
    window:EnableKeyboard(true)
    window:SetPropagateKeyboardInput(false)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
