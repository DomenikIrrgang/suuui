-- One button on the shapeshift bar: a warrior stance, a druid form, a rogue's stealth, a priest's
-- shadowform, a paladin's aura. "Stance" follows Blizzard's and ElvUI's naming, not the scope.
--
-- WHY THIS INHERITS A BLIZZARD TEMPLATE WHEN EVERY OTHER SuuUI BUTTON DOES NOT.
--
-- `ActionButton` builds on `SecureActionButtonTemplate` and states `type="action"` plus the slot,
-- because that is a documented, addressable mechanism. A stance button has no equivalent, and this
-- was measured rather than assumed:
--
--   * `StanceButton1:GetAttribute("type")` is EMPTY on this client. There is no attribute to state.
--   * `CastShapeshiftForm` is BLOCKED for tainted code. Probed bracketed -- read form 7, cast form
--     3, read form 7 again. No error, no message, no change. A SILENT no-op, which is why it had to
--     be verified by reading the value back rather than by watching for a complaint.
--
-- So an addon cannot cast a form from its own handler, and `StanceButtonTemplate` is not a shortcut
-- here -- it is the only path. `SetID(i)` IS the wiring: the template's own OnClick reads GetID()
-- and nothing else.
--
-- WHAT WE STILL OWN, WHICH IS EVERYTHING VISIBLE. The template arrives with its own icon, cooldown,
-- hotkey and border art, and all of it is hidden here in favour of SuuUI's `Icon`, `Cooldown` and
-- `Text` -- the same components bars 1-8 use, so a stance button is pixel-identical to an action
-- button instead of merely similar.
--
-- That is safe for one specific reason: **Blizzard's own updater cannot see these buttons.**
-- `StanceBar_Update` walks `StanceButton1..N` BY NAME, and ours are named by our own prefix. So
-- nothing re-textures or re-shows the regions we hide behind our back. A button created with
-- Blizzard's naming would be fought over every event.
--
-- NEVER SetScript("OnClick") ON THIS FRAME. The template's handler is the entire casting mechanism;
-- replacing it produces a button that looks right, tooltips right, and does nothing -- which is
-- exactly the failure `ActionButton` already shipped once with press-versus-release.
--
-- RegisterForClicks is likewise NOT called here. The template owns that decision, `ElvUI` does not
-- touch it either, and which phase it acts on is UNMEASURED (GetRegisteredClicks was not readable in
-- game). Leaving it alone means the answer does not matter to us.
local CreateFrame, type, tonumber = CreateFrame, type, tonumber
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local GetShapeshiftFormCooldown = GetShapeshiftFormCooldown
local GetBindingKey = GetBindingKey

local S = SuuUI.UISignals
local T = SuuUI.Theme

local StanceButtonMeta = {}
StanceButtonMeta.__index = StanceButtonMeta

-- Every live button, so one event frame serves all of them rather than one frame each.
local live = {}
local eventFrame

-- The events the shapeshift bar actually moves on, measured from ElvUI's registrations.
--
-- Note the two spellings are DIFFERENT EVENTS and both are needed: the PLURAL means the set of
-- forms changed (a druid learning a form), the SINGULAR means which one is active changed (every
-- stance dance). A button that listens to only one is broken in a different way each time.
local EVENTS = {
    "UPDATE_SHAPESHIFT_FORMS",
    "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_SHAPESHIFT_USABLE",
    "UPDATE_SHAPESHIFT_COOLDOWN",
    "UPDATE_BINDINGS",
    "PLAYER_ENTERING_WORLD",
}

-- Every event does a FULL repaint, rather than routing each to the one painter it affects.
--
-- ActionButton routes, because it has nine events across up to 96 buttons. A stance bar has at most
-- ten, so the saving is noise -- and mutation testing showed the routing was indistinguishable from
-- a full refresh, i.e. untestable. One path that cannot drift out of step beats an optimisation
-- whose correctness nothing can assert.
local function onEvent()
    for handle in pairs(live) do
        handle:Refresh()
    end
end

local function syncEventFrame()
    if next(live) then
        if not eventFrame then
            eventFrame = CreateFrame("Frame")
            eventFrame:SetScript("OnEvent", onEvent)
        end
        for _, e in ipairs(EVENTS) do
            -- pcall'd for the same reason ActionButton does it: an event this client does not
            -- know must not take the whole bar down at construction.
            pcall(eventFrame.RegisterEvent, eventFrame, e)
        end
    elseif eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end

-- Hides one of the template's own regions without caring what kind it is. Guarded per method
-- because a region the template stops shipping must not error, and because the harness models a
-- narrower surface than the client.
local function silence(region)
    if not region then return end
    if type(region.SetTexture) == "function" then region:SetTexture(nil) end
    if type(region.SetText) == "function" then region:SetText("") end
    if type(region.Hide) == "function" then region:Hide() end
end

--- The form index this button casts. Read from the frame's id, which is where the template keeps it.
-- @return number
function StanceButtonMeta:GetForm()
    return self._f:GetID()
end

function StanceButtonMeta:_info()
    local form = self:GetForm()
    if not form or form < 1 then return nil end
    -- No upper bound checked against GetNumShapeshiftForms, deliberately: the client answers nil
    -- for a form past the count, so a bound here is a second source of truth for the same fact.
    -- An earlier draft had one and mutation testing could not make it matter.
    return GetShapeshiftFormInfo(form)
end

function StanceButtonMeta:_paintIcon()
    local form = self:GetForm()
    local texture, _, _, spellID = self:_info()
    -- ElvUI derives the icon from the spell rather than trusting the form's own texture, and
    -- prefers it where both exist. Followed here: the form texture is the fallback, not the
    -- first choice.
    local icon = texture
    if spellID and type(GetSpellTexture) == "function" then
        icon = GetSpellTexture(spellID) or texture
    end
    -- Cleared rather than hidden, for the same reason as ActionButton: hiding a region inside a
    -- button the client considers protected is refused in combat.
    self._iconComp:SetIcon(form and icon or nil)
end

function StanceButtonMeta:_paintCooldown()
    local form = self:GetForm()
    if not form or form < 1 then
        self._cooldown:SetCooldown(0, 0)
        return
    end
    local start, duration, active = GetShapeshiftFormCooldown(form)
    -- `active` is a NUMBER on this client and 0 means inactive -- ElvUI tests `active ~= 0`
    -- explicitly. Testing truthiness would treat 0 as a running cooldown and paint a permanent
    -- sweep over every form.
    if active and active ~= 0 and duration and duration > 0 then
        self._cooldown:SetCooldown(start, duration)
    else
        self._cooldown:SetCooldown(0, 0)
    end
end

function StanceButtonMeta:_paintHotkey()
    if not self._hotkeyText then return end
    local key = self._binding and GetBindingKey(self._binding) or nil
    local short = SuuUI._ActionButtonInternals
        and SuuUI._ActionButtonInternals.abbreviateKey(key) or key
    if self._showHotkey and short then
        self._hotkeyText:SetText(short)
        self._hotkeyText:Show()
    else
        self._hotkeyText:Hide()
    end
end

--- Whether this form is the one currently assumed.
-- @return bool
function StanceButtonMeta:IsActive()
    local _, isActive = self:_info()
    return isActive == true
end

--- Whether the client says this form can be cast right now.
-- @return bool
function StanceButtonMeta:IsCastable()
    local _, _, isCastable = self:_info()
    return isCastable ~= false
end

function StanceButtonMeta:_paintState()
    local _, isActive, isCastable = self:_info()
    -- The CheckButton's own state, not a field of ours: it is what the template and any other
    -- reader consult, so keeping our own flag instead would make the two disagree.
    if type(self._f.SetChecked) == "function" then
        self._f:SetChecked(isActive == true)
    end

    -- THE ACTIVE RING, and it is not decoration -- which stance you are in is the single most
    -- important thing this bar tells you.
    --
    -- SetChecked alone draws NOTHING here, because the construction hides every one of the
    -- template's textures including its checked art. That was the whole visual for the active form,
    -- so removing it without replacing it left all the buttons looking identical -- which is exactly
    -- how this shipped and was reported.
    --
    -- A hairline accent border rather than a brighter icon: dimming is already spoken for by the
    -- uncastable state, and two states expressed through the same channel cannot be told apart.
    if self._overlay then
        SuuUI.Backdrop.SetBorder(self._overlay, isActive and "colorAccent" or false)
    end

    local icon = self._iconComp
    if not icon then return end
    if isCastable == false then
        icon:SetArtDesaturated(true)
        icon:SetArtTint(nil, T:GetToken("opacityDisabled") or 0.4)
    else
        icon:SetArtDesaturated(false)
        icon:SetArtTint(nil)
    end
end

-- NO TOOLTIP CODE HERE, deliberately, and this is the opposite of ActionButton.
--
-- ActionButton owns its tooltip because nothing else was going to provide one. StanceButtonTemplate
-- ALREADY shows a tooltip from its own OnEnter, so a second setter does not add anything -- it
-- fights. Shipping both made the tooltip flick between the button and the screen corner on every
-- hover, because two owners were anchoring the same frame.
--
-- The template also knows the content better than we could: it has the form's real name and cost,
-- where we would be guessing at a setter this project has never read off the live client.

--- Re-reads the form and repaints everything.
function StanceButtonMeta:Refresh()
    self:_paintIcon()
    self:_paintCooldown()
    self:_paintHotkey()
    self:_paintState()
end

--- Points this button at a different form. Safe because the id is not a secure attribute -- unlike
--- an action button's slot, which only a secure snippet may move.
-- @param form number
function StanceButtonMeta:SetForm(form)
    self._f:SetID(form)
    self:Refresh()
end

--- @param command string|nil  binding command, e.g. "SHAPESHIFTBUTTON1"
function StanceButtonMeta:SetBinding(command)
    self._binding = command
    self:_paintHotkey()
end

--- The binding command this button owns, or nil.
---
--- Mirrors ActionButtonMeta:GetBinding deliberately, so keybind mode can walk a stance bar and an
--- action bar through the same accessor rather than branching on the button kind.
-- @return string|nil
function StanceButtonMeta:GetBinding()
    return self._binding
end

--- Whether the corner hotkey readout is currently showing.
--- Mirrors ActionButtonMeta:IsShowingHotkey, so keybind mode can borrow and restore the readout on
--- either button kind through one call.
-- @return bool
function StanceButtonMeta:IsShowingHotkey()
    return self._showHotkey ~= false
end

--- @param show bool
function StanceButtonMeta:SetShowHotkey(show)
    self._showHotkey = show and true or false
    self:_paintHotkey()
end

-- The rest of ActionBarGrid's BUTTON INTERFACE. The grid calls all of these on a re-apply, so a
-- factory-supplied button that lacks one dies the second time a setting changes rather than the
-- first -- which is why they are here as a group with the contract named, not added one crash at a
-- time.
--
--   GetSlot / SetSize / SetBinding / SetShowHotkey / SetShowMacroText / SetShowCount /
--   SetShowCooldownText / Destroy

--- The grid's identity accessor. For a stance button the grid's "slot" IS the form index -- the
--- grid compares it to decide whether a cell must be rebuilt, and form 2 in cell 2 is exactly that
--- identity.
-- @return number
function StanceButtonMeta:GetSlot()
    return self:GetForm()
end

-- Accepted and ignored, and the distinction is real rather than a stub: a form has no charge count
-- and no macro name to draw. Answering the call keeps the grid generic; drawing something would
-- invent a readout the client has no data for.
function StanceButtonMeta:SetShowMacroText() end
function StanceButtonMeta:SetShowCount() end

-- Accepted and ignored for a different reason from the two above: a form DOES have a cooldown, so
-- there is data to draw -- the countdown was simply scoped to the action and pet bars. Answering the
-- call is what keeps the grid's fan-out generic; drawing nothing here is a decision, not a gap, and
-- adding it later is confined to this file.
function StanceButtonMeta:SetShowCooldownText() end

--- @param w number
--- @param h number|nil  defaults to w
function StanceButtonMeta:SetSize(w, h)
    self._f:SetSize(w, h or w)
    self._box:Layout()
end

function StanceButtonMeta:ApplyTheme()
    if self._iconComp and self._iconComp.ApplyTheme then self._iconComp:ApplyTheme() end
    if self._hotkeyText and self._hotkeyText.ApplyTheme then self._hotkeyText:ApplyTheme() end
    -- Re-runs the ring too, so a theme change re-resolves colorAccent rather than leaving the
    -- previous theme's blue on the active form.
    self:_paintState()
end

function StanceButtonMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    live[self] = nil
    -- Drops to nothing once the last button goes, rather than leaving six events registered
    -- for no one.
    syncEventFrame()
    if self._hotkeyText then self._hotkeyText:Destroy() end
    if self._iconComp then self._iconComp:Destroy() end
    if self._overlayBox then self._overlayBox:Destroy() end
    if self._box then self._box:Destroy() end
    -- Hidden, NOT reparented to nil. SetParent(nil) on a frame built from a Blizzard template is
    -- the one teardown step Suppress.lua also forbids: it is unnecessary, and on a frame the
    -- client considers protected it is refused in combat.
    self._f:Hide()
end

SuuUI.Components.InstallBase(StanceButtonMeta, "_f")

--- Creates one shapeshift-bar button.
-- @param props table  { form, size, binding, showHotkey, name }
--   No tooltip props: the template provides the tooltip, and a second owner fights it.
--   form:     form index, 1-based. Required -- it is the button's entire wiring.
--   size:     side of the square button. Required.
--   binding:  binding command for the hotkey readout, e.g. "SHAPESHIFTBUTTON1"
-- @param parent frame
-- @return table  StanceButton handle
function SuuUI.Components.StanceButton(props, parent)
    props = props or {}
    assert(type(props.form) == "number", "SuuUI: StanceButton needs a form index")
    assert(type(props.size) == "number", "SuuUI: StanceButton needs a size")

    -- CheckButton, not Button: the template is one, and the checked state is how an active form
    -- reads. Creating the wrong type loses SetChecked and the template's own art states.
    local f = CreateFrame("CheckButton", props.name, parent, "StanceButtonTemplate")
    f:SetSize(props.size, props.size)
    f:EnableMouse(true)
    -- The id IS the wiring. Set before anything paints, or the first Refresh reads form 0.
    f:SetID(props.form)

    -- Everything the template draws, silenced. Ours goes on top and Blizzard's updater cannot
    -- find these buttons by name to put any of it back.
    silence(f.icon)
    silence(f.HotKey)
    if f.cooldown and type(f.cooldown.Hide) == "function" then f.cooldown:Hide() end
    -- HIDE THE TEXTURE OBJECTS -- do NOT pass nil to the setters.
    --
    -- `SetNormalTexture(nil)` is REFUSED on this client: "bad argument #2 to '?' (Usage:
    -- self:SetNormalTexture(asset))". It wants an asset, and there is no documented "clear it"
    -- argument. The getters hand back the Texture, and a Texture can be emptied and hidden.
    --
    -- This threw during construction, which meant the bar was never built at all -- and because the
    -- whole thing runs inside a Settings watcher whose errors are pcall'd into a DEBUG-ONLY log, the
    -- player saw no bar and no message. Two rounds of the wrong diagnosis went into that silence.
    for _, getter in ipairs({
        "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture",
        "GetDisabledTexture", "GetCheckedTexture",
    }) do
        if type(f[getter]) == "function" then
            local tex = f[getter](f)
            if type(tex) == "table" then
                if type(tex.SetTexture) == "function" then tex:SetTexture(nil) end
                if type(tex.Hide) == "function" then tex:Hide() end
            end
        end
    end

    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- Same construction as ActionButton, deliberately: no border because the grid's plate owns
    -- the surface, and trim crops the bevel Blizzard bakes into its icon files.
    local iconComp = SuuUI.Components.Icon({ icon = nil, border = false, trim = true }, f)
    iconComp._fade = false
    box:Add(iconComp, { align = "stretch", valign = "stretch" })

    local iconFrame = iconComp:GetFrame()
    local cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    cooldown:SetHideCountdownNumbers(true)
    box:Add(cooldown, { inset = 0 })

    -- A FontString on the root frame would draw BEHIND the cooldown, because a child frame draws
    -- above its parent's layers. RaiseAbove is the only sanctioned z-order mechanism outside
    -- Core/UIRoot.lua.
    -- BackdropTemplate, because this frame carries the ACTIVE RING -- see _paintState. The border
    -- lives on the overlay rather than on a frame of its own so it draws above the icon for free;
    -- a sibling would need its own RaiseAbove and its own resize.
    local overlay = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:Add(overlay, { align = "stretch", valign = "stretch" })
    SuuUI.UIRoot:RaiseAbove(overlay, iconFrame, 2)
    -- Set up once with no border; _paintState turns it on for the active form. inset 0 because this
    -- surface must not paint over the icon -- it is a ring, not a plate.
    SuuUI.Backdrop.Apply(overlay, { bg = false, border = false, inset = 0 })
    local overlayBox = SuuUI.Layout:CreateContainer({ host = overlay, layout = "stack" })

    local padXs = T:GetToken("spaceXxs") or 2
    local hotkeyText = SuuUI.Components.Text({
        text = "", size = "sm", color = "textMuted", justify = "RIGHT", wrap = false,
    }, overlay)
    hotkeyText._fade = false
    overlayBox:Add(hotkeyText, {
        align = "end", valign = "start", inset = { right = padXs, top = padXs },
    })
    hotkeyText:Hide()

    local id = "stancebutton_" .. tostring(f)
    handle = setmetatable({
        _f             = f,
        _box           = box,
        _iconComp      = iconComp,
        _cooldown      = cooldown,
        _overlay       = overlay,
        _overlayBox    = overlayBox,
        _hotkeyText    = hotkeyText,
        _eid           = id,
        _binding       = props.binding,
        _showHotkey    = props.showHotkey ~= false,
    }, StanceButtonMeta)

    -- HookScript throughout, never SetScript: the template's own handlers ARE the mechanism, and
    -- OnEnter is also where its tooltip comes from.
    f:HookScript("PostClick", function()
        S:Emit(handle, S.SIGNALS.CLICKED, "LeftButton")
    end)
    -- Signals only. The template's own OnEnter draws the tooltip, and HookScript leaves it intact.
    f:HookScript("OnEnter", function()
        S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
    end)
    f:HookScript("OnLeave", function()
        S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
    end)

    live[handle] = true
    syncEventFrame()

    handle:Refresh()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end

-- Test seam, matching ActionButton's.
SuuUI._StanceButtonInternals = {
    liveCount = function()
        local n = 0
        for _ in pairs(live) do n = n + 1 end
        return n
    end,
    eventFrame = function() return eventFrame end,
}
