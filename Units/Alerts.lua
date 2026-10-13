-- Units/Alerts.lua
-- Alerts (step 1.11): one short-lived alert at a time, centred on the screen
-- 320px down from its top, and only in combat. Other modules raise them
-- through the public API (written against it, like a plugin would):
--
--   SuuUI.ShowAlert(key, tone, title, detail, ...)  -- detail: text, or a
--       format whose arguments may be secret; tone "danger" | "warning" | "info"
--   SuuUI.HideAlert(key)
--   SuuUI.ShowLevelUp(key, def)   -- the level-up card (UI.LevelUp) in the
--       alert's place, tone info: { title, detail, spells, more, cost }
--
-- An alert stays while its condition holds: its owner hides it (HideAlert),
-- and the same key again updates it in place. Out of combat none show, and
-- combat ending clears them. A new alert takes the place of the one showing
-- unless that one is more urgent (danger > warning > info); the one it
-- replaced comes back when it goes, unless its owner hid it meanwhile (a
-- level-up over the campfire alert). Danger alerts can play a sound. The
-- level-up card stays while the mouse is over it: hidden once it leaves.

local UI = SuuUI.UI

local M = SuuUI.RegisterModule({
    id = "alerts",
    name = "Alerts",
    description = "Short alerts in the middle of the screen when something needs you now: aggro, a pull.",
    api = "0.10",
    defaults = {
        position = { point = "TOP", x = 0, y = -320 },
        sound = true,
    },
})

local URGENCY = { info = 1, warning = 2, danger = 3 }
local TEST_TIME = 4

-- May this key's alert show now, over the one showing?
function M:Allowed(key, tone)
    if not self.frame then return false end
    local inCombat = InCombatLockdown() or UI.Flag(UnitAffectingCombat("player"))
    if not inCombat and not self.testing and not (self.anytime and self.anytime[key]) then return false end
    local current = self.current
    if current and current ~= key and (URGENCY[self.tone] or 0) > (URGENCY[tone] or 0) then return false end
    -- the one it replaces, to come back
    if current and current ~= key and self.last then self.under = self.last end
    return true
end

function M:Present(key, tone, shown, hidden, args)
    self:StopHolding()
    local fresh = self.current ~= key or self.tone ~= tone
    self.current, self.tone = key, tone
    self.last = args
    if self.under and self.under.key == key then self.under = nil end
    hidden:Hide()
    shown:Show()
    if self:Get("position").hidden then return end
    self.frame:Show()
    if fresh then
        SuuUI.Motion.Enter(shown)
        if tone == "danger" and self:Get("sound") then UI.TrackerSound("warning") end
    end
end

function M:Show(key, tone, title, detail, ...)
    if not self:Allowed(key, tone) then return end
    self.alert:SetAlert(tone, title, detail, ...)
    self:Present(key, tone, self.alert, self.card,
        { key = key, kind = "alert", n = select("#", ...) + 3, tone, title, detail, ... })
end

-- The level-up card in the alert's place (tone info).
function M:ShowLevelUp(key, def)
    if not self:Allowed(key, "info") then return end
    self.card:SetLevelUp(def)
    self:Present(key, "info", self.card, self.alert, { key = key, kind = "card", def = def })
end

-- A key whose alerts may show out of combat too (a pull countdown).
function M:AllowOutOfCombat(key)
    self.anytime = self.anytime or {}
    self.anytime[key] = true
end

function M:StopHolding()
    if self.holding then self.holding:Cancel(); self.holding = nil end
end

function M:Hide(key)
    -- the card under the mouse: it goes a moment after the mouse leaves
    if key and key == self.current and self.card:IsShown() and self.card:IsHovered() then
        if not self.holding then
            local away = 0
            self.holding = C_Timer.NewTicker(0.2, function()
                if self.current ~= key then return self:StopHolding() end
                away = self.card:IsHovered() and 0 or away + 0.2
                if away >= 1 then
                    self:StopHolding()
                    self:Hide(key)
                end
            end)
        end
        return
    end
    self:StopHolding()
    if key and key ~= self.current then
        -- its owner is done with it: it won't come back either
        if self.under and self.under.key == key then self.under = nil end
        return
    end
    self.current, self.tone, self.last = nil, nil, nil
    if self.frame then self.frame:Hide() end
    -- the alert this one replaced, if it still holds
    local under = self.under
    self.under = nil
    if key and under then
        if under.kind == "card" then self:ShowLevelUp(under.key, under.def)
        else self:Show(under.key, unpack(under, 1, under.n)) end
    end
end

-- An alert of each tone in turn, out of combat too (the settings' button).
function M:Test()
    local samples = {
        { "danger", "You have drawn aggro", "Lava Surger · Feign Death ready" },
        { "warning", "You're about to pull", "Lava Surger · over Brannoc's threat" },
        { "info", "Pull in 5", "4 of 5 ready" },
    }
    self.testing = true
    for i, s in ipairs(samples) do
        C_Timer.After((i - 1) * TEST_TIME, function()
            if not self:IsEnabled() then return end
            self.testing = true
            self.current = nil
            self:Show("test", s[1], s[2], s[3])
        end)
    end
    C_Timer.After(#samples * TEST_TIME, function()
        self.testing = nil
        self:Hide("test")
    end)
end

-- The settings' preview: the three tones at their real size.
function M:PreviewView(parent)
    if not self.previewView then
        local view = CreateFrame("Frame", nil, parent)
        local list = {
            { "danger", "You have drawn aggro", "Lava Surger · Vanish ready" },
            { "warning", "You're about to pull", "over Brannoc's threat" },
            { "info", "Pull in 5", "4 of 5 ready" },
        }
        local y, w = 0, 0
        for _, s in ipairs(list) do
            local a = UI.Alert(view)
            a:SetAlert(s[1], s[2], s[3])
            a:SetPoint("TOP", 0, -y)
            y = y + a:GetHeight() + SuuUI.Tokens.space["space-4"] * 2
            w = math.max(w, a:GetWidth())
        end
        view:SetSize(w + 10, y)
        self.previewView = view
    end
    self.previewView:SetParent(parent)
    return self.previewView
end

local SECTION = {
    id = "alerts", label = "Alerts", category = "Insights", order = 10,
    preview = function(parent) return M:PreviewView(parent) end,
    previewNote = "In combat only, one at a time, 320px down from the top of the screen.",
    groups = {
        { title = "Alerts", description = "One line in the middle of the screen when something needs you now. Only in combat; the alert goes when the reason does.", rows = {
            { key = "sound", label = "Sound on danger", control = "toggle",
              description = "A raid warning sound when an alert in ember appears (you have aggro)." },
            { label = "Try it", control = "button", text = "Show test alerts",
              description = "The three kinds in turn, four seconds each, out of combat too.",
              onClick = function() M:Test() end },
        } },
    },
}

function M:OnEnable()
    if not self.frame then
        local f = CreateFrame("Frame", "SuuUIAlerts", SuuUI.Root)
        f:SetSize(400, 64)
        f:SetFrameStrata("HIGH")
        self.alert = UI.Alert(f)
        self.alert:SetPoint("TOP")
        self.card = UI.LevelUp(f)
        self.card:SetPoint("TOP")
        self.card:Hide()
        f:Hide()
        self.frame = f
    end
    self.frame.suuManagedShow = true
    self:RegisterMover(self.frame, { key = "position", label = "Alerts" })
    self:RegisterSettings(SECTION)
    -- combat over: nothing stays
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if not self.testing then self:Hide() end
    end)
end

function M:OnDisable()
    self:Hide()
end
