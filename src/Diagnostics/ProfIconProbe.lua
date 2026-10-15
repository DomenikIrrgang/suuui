-- Diagnostics/ProfIconProbe.lua
-- "/suu probe proficons": the game's own icons of the professions, large,
-- to redraw the map's trainer glyphs after (screenshot the panel). Each is
-- the icon of the profession's apprentice spell as this client has it; their
-- file IDs are saved in SuuUIProbe.proficons on /reload. Click the panel to
-- close it.

local _, ns = ...

local PIP = {}
ns.ProfIconProbe = PIP

local UI = SuuUI.UI

-- the apprentice spell of each profession (the original game's IDs)
local PROFESSIONS = {
    { "Alchemy", 2259 }, { "Blacksmithing", 2018 }, { "Enchanting", 7411 }, { "Engineering", 4036 },
    { "Herbalism", 2366 }, { "Leatherworking", 2108 }, { "Mining", 2575 }, { "Skinning", 8613 },
    { "Tailoring", 3908 }, { "Cooking", 2550 }, { "First Aid", 3273 }, { "Fishing", 7620 },
}
local SIZE, GAP, PER_ROW = 96, 24, 6

function PIP.Command()
    SuuUIProbe = SuuUIProbe or {}
    local saved = {}
    SuuUIProbe.proficons = saved
    local f = PIP.frame
    if not f then
        f = CreateFrame("Button", nil, UIParent)
        f:SetFrameStrata("DIALOG")
        UI.Fill(f, "surface"):SetAllPoints()
        UI.Border(f, "gilt-line")
        f:SetScript("OnClick", function(self) self:Hide() end)
        f.cells = {}
        PIP.frame = f
    end
    local rows = math.ceil(#PROFESSIONS / PER_ROW)
    f:SetSize(PER_ROW * (SIZE + GAP) + GAP, rows * (SIZE + GAP + 18) + GAP)
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    for i, p in ipairs(PROFESSIONS) do
        local c = f.cells[i]
        if not c then
            c = { icon = f:CreateTexture(nil, "ARTWORK"), label = UI.Text(f, "label", "ink") }
            c.icon:SetSize(SIZE, SIZE)
            f.cells[i] = c
        end
        local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
        c.icon:ClearAllPoints()
        c.icon:SetPoint("TOPLEFT", GAP + col * (SIZE + GAP), -(GAP + row * (SIZE + GAP + 18)))
        local ok, file = pcall(C_Spell.GetSpellTexture, p[2])
        file = ok and file or nil
        c.icon:SetTexture(file or 134400) -- the question mark when the spell has none
        c.label:ClearAllPoints()
        c.label:SetPoint("TOP", c.icon, "BOTTOM", 0, -4)
        c.label:SetValue(p[1])
        saved[p[1]] = { spell = p[2], icon = file and tostring(file) or "none" }
    end
    f:Show()
    ns.Print("Profession icons: screenshot the panel, click it to close; /reload saves their file IDs.")
end
