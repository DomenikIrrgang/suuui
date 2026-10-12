-- Units/Alerts.lua
-- Alerts (step 1.11): one short-lived alert at a time, centred on the screen
-- 270px down from its top, and only in combat. Other modules raise them
-- through the public API (written against it, like a plugin would):
--
--   SuuUI.ShowAlert(key, tone, title, detail, ...)  -- detail: text, or a
--       format whose arguments may be secret; tone "danger" | "warning" | "info"
--   SuuUI.HideAlert(key)
--
-- An alert stays while its condition holds: its owner hides it (HideAlert),
-- and the same key again updates it in place. Out of combat none show, and
-- combat ending clears them. A new alert takes the place of the one showing
-- unless that one is more urgent (danger > warning > info); the owner raises
-- it again when it still matters. Danger alerts can play a sound.

local UI = SuuUI.UI

local M = SuuUI.RegisterModule({
    id = "alerts",
    name = "Alerts",
    description = "Short alerts in the middle of the screen when something needs you now: aggro, a pull.",
    api = "0.10",
    defaults = {
        position = { point = "TOP", x = 0, y = -270 },
        sound = true,
    },
})

local URGENCY = { info = 1, warning = 2, danger = 3 }
local TEST_TIME = 4

function M:Show(key, tone, title, detail, ...)
    if not self.frame then return end
    local inCombat = InCombatLockdown() or UI.Flag(UnitAffectingCombat("player"))
    if not inCombat and not self.testing then return end
    local current = self.current
    if current and current ~= key and (URGENCY[self.tone] or 0) > (URGENCY[tone] or 0) then return end
    local fresh = current ~= key or self.tone ~= tone
    self.current, self.tone = key, tone
    self.alert:SetAlert(tone, title, detail, ...)
    if self:Get("position").hidden then return end
    self.frame:Show()
    if fresh then
        SuuUI.Motion.Enter(self.alert)
        if tone == "danger" and self:Get("sound") then UI.TrackerSound("warning") end
    end
end

function M:Hide(key)
    if key and key ~= self.current then return end
    self.current, self.tone = nil, nil
    if self.frame then self.frame:Hide() end
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
    previewNote = "In combat only, one at a time, 270px down from the top of the screen.",
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
