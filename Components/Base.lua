local pairs = pairs
local S = SuuUI.UISignals

-- The six accessors every component handle repeats verbatim, plus SetSize.
-- SetSize deliberately does not emit SIZE_CHANGED: that comes from the frame's own
-- OnSizeChanged hook so an explicit resize and a layout-driven one behave identically.
local builders = {
    GetWidth  = function(field) return function(self) return self[field]:GetWidth()  end end,
    GetHeight = function(field) return function(self) return self[field]:GetHeight() end end,
    IsShown   = function(field) return function(self) return self[field]:IsShown()   end end,
    GetFrame  = function(field) return function(self) return self[field]            end end,
    SetSize   = function(field) return function(self, w, h) self[field]:SetSize(w, h) end end,
    Show      = function(field)
        return function(self)
            self[field]:Show()
            S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
        end
    end,
    Hide      = function(field)
        return function(self)
            self[field]:Hide()
            S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
        end
    end,
}

--- Installs the standard handle accessors onto a component metatable.
-- Only fills in methods the metatable does not already define, so a component
-- keeping a custom SetSize/Show/Hide is untouched.
-- @param meta table   the component's metatable
-- @param field string the handle field holding the widget (default "_f")
-- @return table  the metatable, for chaining
function SuuUI.Components.InstallBase(meta, field)
    field = field or "_f"
    for name, build in pairs(builders) do
        if meta[name] == nil then meta[name] = build(field) end
    end
    return meta
end

-- Used only when a theme somehow carries no opacityDisabled, e.g. a hand-written theme
-- table predating the token. Matches the shipped themes' value.
local FALLBACK_DISABLED_ALPHA = 0.40

--- Installs the canonical enabled-state handling onto a component metatable.
--
-- Disabled is ONE root-frame fade, not per-part recolouring. A recolour can only dim the
-- parts a component remembers to dim: that is how a disabled toggle kept a fully
-- saturated accent track while only its knob greyed, and how a disabled slider stayed
-- pixel-identical to a live one. A fade is state-independent by construction — there is
-- no value, selection or variant it can fail to cover — which is the property the design
-- rule demands: disabled must never look like enabled in ANY state.
--
-- Mouse input drops in the same call, so a faded widget can never still react. The
-- pre-disable mouse state is remembered and restored rather than forced back on, because
-- enabling mouse on a passive container that never wanted it would make it start
-- swallowing clicks meant for whatever is underneath.
--
-- Frame alpha cascades to children, so only the OUTERMOST handle may fade. A composite
-- that delegates to a sub-component (KeyCapture -> Button) sets `_fade = false` on the
-- inner handle, otherwise the two fades multiply and the widget goes nearly black. Text
-- opts out for a different reason: it dims through colorTextDisabled, and fading a label
-- that is already disabled-grey leaves it unreadable.
--
-- Components layer extra behaviour on a `_onEnabledChanged(en)` hook — an inner hit
-- frame, an EditBox, a menu that has to close — instead of writing their own SetEnabled.
-- @param meta table   the component's metatable
-- @param field string the handle field holding the widget (default "_f")
-- @return table  the metatable, for chaining
function SuuUI.Components.InstallEnable(meta, field)
    field = field or "_f"

    -- Applies the current enabled state to the frame. Separate from SetEnabled because
    -- ApplyTheme calls it too: opacityDisabled is user-editable, so a live token edit has
    -- to reach a widget that is already sitting disabled.
    if meta._applyEnabled == nil then
        meta._applyEnabled = function(self)
            local f  = self[field]
            local en = self._enabled ~= false
            if self._fade ~= false then
                local a = SuuUI.Theme:GetToken("opacityDisabled") or FALLBACK_DISABLED_ALPHA
                f:SetAlpha(en and 1 or a)
            end
            if en then
                -- nil means it was never disabled, so there is nothing to restore.
                if self._mouseWas ~= nil then f:EnableMouse(self._mouseWas) end
            else
                if self._mouseWas == nil then self._mouseWas = f:IsMouseEnabled() end
                f:EnableMouse(false)
            end
        end
    end

    if meta.SetEnabled == nil then
        meta.SetEnabled = function(self, en)
            self._enabled = en ~= false
            self:_applyEnabled()
            if self._onEnabledChanged then self:_onEnabledChanged(self._enabled) end
            S:Emit(self, S.SIGNALS.ENABLED_CHANGED, self._enabled)
        end
    end

    if meta.IsEnabled == nil then
        meta.IsEnabled = function(self) return self._enabled ~= false end
    end

    return meta
end
