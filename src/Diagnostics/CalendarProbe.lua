-- Diagnostics/CalendarProbe.lua
-- "/suu probe calendar": what Forever's calendar tells an addon about
-- holidays, for showing holiday quests on the map only while their holiday
-- is on. Saved in SuuUIProbe.calendar on /reload.
--   * which C_Calendar and C_DateAndTime functions exist
--   * today's date as the calendar has it
--   * every event this month and next (the calendar loads them after
--     OpenCalendar; the probe waits for CALENDAR_UPDATE_EVENT_LIST, at most
--     5 s): title, type, eventID, start and end, and a holiday's own info
--   * today's events on their own

local _, ns = ...

local CP = {}
ns.CalendarProbe = CP

local isSecret = issecretvalue or function() return false end

local function show(v, depth)
    depth = depth or 0
    if isSecret(v) then return "<secret>" end
    if type(v) ~= "table" then return tostring(v) end
    if depth > 1 then return "{…}" end
    local parts = {}
    for k, x in pairs(v) do
        if type(x) ~= "function" then
            parts[#parts + 1] = tostring(k) .. "=" .. (isSecret(x) and "<secret>" or (type(x) == "table" and show(x, depth + 1) or tostring(x)))
        end
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function call(t, name, ...)
    if not (t and type(t[name]) == "function") then return "missing" end
    local ok, a, b, c = pcall(t[name], ...)
    if not ok then return "error: " .. tostring(a) end
    return a, b, c
end

function CP.Snapshot(waited)
    SuuUIProbe = SuuUIProbe or {}
    local s = { at = date("%Y-%m-%d %H:%M:%S"), waited = waited }
    SuuUIProbe.calendar = s
    local cal = C_Calendar
    s.exists = cal ~= nil
    s.functions = {}
    for k, v in pairs(cal or {}) do
        if type(v) == "function" then s.functions[#s.functions + 1] = k end
    end
    table.sort(s.functions)
    local now = C_DateAndTime and call(C_DateAndTime, "GetCurrentCalendarTime")
    s.now = show(now)
    if not (cal and type(now) == "table") then
        ns.Print("Calendar probe: no calendar (" .. tostring(cal ~= nil) .. "); /reload.")
        return
    end
    -- this month (offset 0) and next (1), as the calendar's month view has them
    s.months = {}
    local holidays = 0
    for offset = 0, 1 do
        local info = call(cal, "GetMonthInfo", offset)
        local m = { info = show(info), events = {} }
        s.months[#s.months + 1] = m
        local days = type(info) == "table" and info.numDays or 31
        for day = 1, days do
            local n = call(cal, "GetNumDayEvents", offset, day)
            for i = 1, (type(n) == "number" and n or 0) do
                local e = call(cal, "GetDayEvent", offset, day, i)
                local entry = { day = day, event = show(e) }
                if type(e) == "table" and e.calendarType == "HOLIDAY" then
                    holidays = holidays + 1
                    entry.holiday = show((call(cal, "GetHolidayInfo", offset, day, i)))
                end
                -- one line per event a day, not one per day it lasts
                if #m.events < 120 then m.events[#m.events + 1] = entry end
            end
        end
    end
    -- today's
    s.today = {}
    local n = call(cal, "GetNumDayEvents", 0, now.monthDay)
    for i = 1, (type(n) == "number" and n or 0) do
        s.today[#s.today + 1] = show((call(cal, "GetDayEvent", 0, now.monthDay, i)))
    end
    ns.Print(("Calendar probe: %d events today, %d holiday days in two months%s; /reload."):format(
        #s.today, holidays, waited and "" or " (the calendar didn't answer in 5 s)"))
end

function CP.Command()
    if not C_Calendar then
        CP.Snapshot(false)
        return
    end
    -- the calendar loads its events after OpenCalendar
    local f = CreateFrame("Frame")
    local done = false
    local function finish(waited)
        if done then return end
        done = true
        f:UnregisterAllEvents()
        CP.Snapshot(waited)
    end
    f:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
    f:SetScript("OnEvent", function() finish(true) end)
    local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if now and C_Calendar.SetAbsMonth then pcall(C_Calendar.SetAbsMonth, now.month, now.year) end
    if C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
    ns.Print("Calendar probe: reading the calendar…")
    C_Timer.After(5, function() finish(false) end)
end
