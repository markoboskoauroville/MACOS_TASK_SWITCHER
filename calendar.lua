-- calendar.lua — the next event of a Google Calendar on the Dock Switcher's clock stack (owned by switcher.lua)
--
-- Marko, 14.9.2026: "can I connect this app with my Google Calendar ... you also
-- display the title of my next event in my calendar kukljica.ekooaza@gmail.com".
--
-- THE ROAD. Hammerspoon has no Google account; Google Calendar offers every
-- calendar a SECRET ADDRESS IN iCAL FORMAT (Settings → the calendar → Integrate
-- calendar), a URL with a key in it that answers with the whole calendar as an
-- .ics file. That address is the connection: it lives in ~/.config/dock.json
-- under "calendar" (never in this repository, never shown again once set), the
-- file is fetched when the switcher starts and again when the square opens more
-- than a quarter of an hour after the last fetch, and the events of the coming
-- ninety days are kept there. The line under the weather is the first event
-- still to begin:  12:00   12. NEWS  today,  Tue 15:00   15. NEWS  this week,
-- 24 Sep 12:00   12. NEWS  beyond.
--
-- THE FILE. VEVENTs with DTSTART (local, UTC with Z, or a DATE for all day),
-- DTEND, SUMMARY, STATUS, RRULE (DAILY, WEEKLY with BYDAY, MONTHLY, YEARLY, with
-- INTERVAL, COUNT and UNTIL), EXDATE, and RECURRENCE-ID for a changed or removed
-- instance of a series. A TZID that is not the Mac's own is read as the Mac's
-- (Google writes Europe/Belgrade for Zagreb: the same clock).
--
--     .lines()            { "12:00   12. NEWS" } or {} (no address, nothing coming, nothing fetched)
--     .refresh(force)     fetch if the last fetch is old (or force); asynchronous
--     .setAddress(url)    remember the secret address, fetch at once
--     .rows()             the submenu rows: the next event (a click fetches again), the address

local C = _G.DOCKCALENDAR or {}
_G.DOCKCALENDAR = C

local HOME  = os.getenv("HOME")
local STATE = HOME .. "/.config/dock.json"
local STALE = 15 * 60                              -- seconds after which the square's opening fetches again
local RETRY = 5 * 60                               -- seconds before a failed fetch is tried again
local HORIZON = 90 * 24 * 3600                     -- how far ahead the events are kept
local KEEP = 120                                   -- how many events are kept
local TITLE_MAX = 56                               -- characters of the title on the line

-- ---------------------------------------------------------------- the settings file (shared with the switcher)
local function load()
    local f = io.open(STATE)
    if not f then return {} end
    local ok, j = pcall(hs.json.decode, f:read("a")); f:close()
    return (ok and type(j) == "table") and j or {}
end

local function save(t)
    hs.fs.mkdir(HOME .. "/.config")
    local f = io.open(STATE, "w")
    if f then f:write(hs.json.encode(t)); f:close() end
end

local function state()
    local c = load().calendar
    return type(c) == "table" and c or {}
end

local function remember(c)
    local s = load(); s.calendar = c; save(s)
end

-- ---------------------------------------------------------------- times
local function utcToEpoch(F)                        -- the fields are UTC: the epoch they name
    local L = os.time(F)
    local g = os.date("!*t", L); g.isdst = os.date("*t", L).isdst
    return L + (L - os.time(g))
end

-- "20260914T170000", "20260914T150000Z" or "20260914" -> epoch, allday
local function when(value, params)
    local y, mo, d, h, mi, s, z = value:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)(Z?)")
    if y then
        local F = { year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) }
        if z == "Z" then return utcToEpoch(F), false end
        return os.time(F), false
    end
    y, mo, d = value:match("^(%d%d%d%d)(%d%d)(%d%d)$")
    if y then return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 0 }), true end
    return nil
end

local function shift(t, days)                       -- the same wall-clock time, `days` later (DST kept right by mktime)
    local d = os.date("*t", t)
    return os.time({ year = d.year, month = d.month, day = d.day + days, hour = d.hour, min = d.min, sec = d.sec })
end

local function shiftMonths(t, months)
    local d = os.date("*t", t)
    return os.time({ year = d.year, month = d.month + months, day = d.day, hour = d.hour, min = d.min, sec = d.sec })
end

-- ---------------------------------------------------------------- the file
local function unescape(s)
    return (s:gsub("\\n", " "):gsub("\\N", " "):gsub("\\,", ","):gsub("\\;", ";"):gsub("\\\\", "\\"))
end

local function properties(block)                    -- the lines of one VEVENT as { name, params, value }
    local props = {}
    for line in (block .. "\n"):gmatch("([^\n]*)\n") do
        local head, value = line:match("^([^:]+):(.*)$")
        if head then
            local name, params = head:match("^([^;]+)(.*)$")
            props[#props + 1] = { name = name:upper(), params = params:upper(), value = value }
        end
    end
    return props
end

local DAYS = { SU = 1, MO = 2, TU = 3, WE = 4, TH = 5, FR = 6, SA = 7 }

local function rule(text)                           -- RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=...;COUNT=...
    local r = { interval = 1 }
    for k, v in text:gmatch("([^;=]+)=([^;]+)") do
        k = k:upper()
        if k == "FREQ" then r.freq = v:upper()
        elseif k == "INTERVAL" then r.interval = tonumber(v) or 1
        elseif k == "COUNT" then r.count = tonumber(v)
        elseif k == "UNTIL" then r.until_ = when(v)
        elseif k == "BYDAY" then
            r.byday = {}
            for dname in v:upper():gmatch("[A-Z][A-Z]") do if DAYS[dname] then r.byday[DAYS[dname]] = true end end
        elseif k == "BYMONTHDAY" then r.bymonthday = tonumber(v:match("-?%d+"))
        end
    end
    return r.freq and r or nil
end

-- the instances of a series between `from` and `to`, DTSTART counted as the first
local function occurrences(start, r, from, to)
    local out, n = {}, 0
    local last = to
    if r.until_ and r.until_ < last then last = r.until_ end
    if r.freq == "DAILY" or r.freq == "WEEKLY" then
        local step = r.freq == "DAILY" and r.interval or 1
        local i = 0
        local sd = os.date("*t", start)
        local weekStart = start - ((sd.wday - 2) % 7) * 86400          -- the Monday of DTSTART's week
        while true do
            local t = shift(start, i)
            if t > last then break end
            if r.count and n >= r.count then break end
            local hit
            if r.freq == "DAILY" then hit = true
            else
                local d = os.date("*t", t)
                local inDay = r.byday and r.byday[d.wday] or (not r.byday and d.wday == sd.wday)
                local weeks = math.floor((t - weekStart) / (7 * 86400) + 0.01)
                hit = inDay and weeks % r.interval == 0
            end
            if hit then
                n = n + 1
                if t >= from then out[#out + 1] = t end
            end
            i = i + step
            if i > 366 * 30 then break end
        end
    elseif r.freq == "MONTHLY" or r.freq == "YEARLY" then
        local i = 0
        while true do
            local t = r.freq == "MONTHLY" and shiftMonths(start, i * r.interval) or shiftMonths(start, i * 12 * r.interval)
            if t > last then break end
            if r.count and n >= r.count then break end
            local d0, d = os.date("*t", start), os.date("*t", t)
            if d.day == (r.bymonthday or d0.day) then                -- a 31st in a short month rolls over: not an instance
                n = n + 1
                if t >= from then out[#out + 1] = t end
            end
            i = i + 1
            if i > 12 * 30 then break end
        end
    end
    return out
end

-- every event of the file between now and the horizon: { t=, ends=, title=, allday= }, sorted
function C.parse(ics, now)
    now = now or os.time()
    ics = ics:gsub("\r\n", "\n"):gsub("\n[ \t]", "")                  -- unfold
    local from, to = now - 86400, now + HORIZON
    local masters, overrides, skip = {}, {}, {}                        -- by UID; skip[uid][epoch] = true (changed or removed instances)
    for block in ics:gmatch("BEGIN:VEVENT\n(.-)\nEND:VEVENT") do
        local e = { exdates = {} }
        for _, p in ipairs(properties(block)) do
            if p.name == "UID" then e.uid = p.value
            elseif p.name == "SUMMARY" then e.title = unescape(p.value)
            elseif p.name == "STATUS" then e.status = p.value:upper()
            elseif p.name == "DTSTART" then e.t, e.allday = when(p.value, p.params)
            elseif p.name == "DTEND" then e.ends = when(p.value, p.params)
            elseif p.name == "RRULE" then e.rule = rule(p.value)
            elseif p.name == "RECURRENCE-ID" then e.recurrence = when(p.value, p.params)
            elseif p.name == "EXDATE" then
                for v in p.value:gmatch("[^,]+") do local x = when(v, p.params); if x then e.exdates[x] = true end end
            end
        end
        if e.t then
            e.uid = e.uid or tostring(e.t) .. (e.title or "")
            if e.recurrence then
                skip[e.uid] = skip[e.uid] or {}
                skip[e.uid][e.recurrence] = true
                overrides[#overrides + 1] = e
            else
                masters[#masters + 1] = e
            end
        end
    end
    local events = {}
    local function add(t, e)
        if e.status == "CANCELLED" then return end
        local length = (e.ends and e.t and e.ends - e.t) or (e.allday and 86400 or 3600)
        if t + length < from or t > to then return end
        events[#events + 1] = { t = t, ends = t + length, title = e.title or "(no title)", allday = e.allday or false }
    end
    for _, e in ipairs(masters) do
        if e.rule then
            for _, t in ipairs(occurrences(e.t, e.rule, from, to)) do
                if not e.exdates[t] and not (skip[e.uid] and skip[e.uid][t]) then add(t, e) end
            end
        else
            add(e.t, e)
        end
    end
    for _, e in ipairs(overrides) do add(e.t, e) end
    table.sort(events, function(a, b) return a.t < b.t end)
    while #events > KEEP do table.remove(events) end
    return events
end

-- ---------------------------------------------------------------- the line
local function short(title)
    if utf8.len(title) and utf8.len(title) > TITLE_MAX then
        return title:sub(1, utf8.offset(title, TITLE_MAX) - 1) .. "…"
    end
    return title
end

local function label(ev, now)
    local d, n = os.date("*t", ev.t), os.date("*t", now)
    local sameDay = d.year == n.year and d.yday == n.yday
    local clock = ev.allday and "" or os.date("%H:%M", ev.t)
    local day
    if sameDay then day = ev.allday and "today" or ""
    elseif ev.t - now < 6 * 86400 then
        local tomorrow = os.date("*t", now + 86400)
        day = (d.year == tomorrow.year and d.yday == tomorrow.yday) and "tomorrow" or os.date("%a", ev.t)
    else day = tostring(d.day) .. os.date(" %b", ev.t) end
    local parts = {}
    if day ~= "" then parts[#parts + 1] = day end
    if clock ~= "" then parts[#parts + 1] = clock end
    return table.concat(parts, " ")
end

function C.nextEvent(now)
    now = now or os.time()
    for _, ev in ipairs(state().events or {}) do
        if type(ev.t) == "number" and ev.t > now then return ev end
    end
end

function C.lines()
    local c = state()
    if not c.ics then return {} end
    local ev = C.nextEvent()
    if not ev then return c.at and { "no event coming" } or {} end
    local l = label(ev, os.time())
    return { (l ~= "" and (l .. "   ") or "") .. short(ev.title) }
end

-- ---------------------------------------------------------------- the fetch
function C.refresh(force, done)
    local c = state()
    if not c.ics then if done then done(false) end return "no address" end
    local now = os.time()
    if not force then
        if c.fetched and now - c.fetched < STALE then return "fresh" end
        if C.tried and now - C.tried < RETRY then return "tried a moment ago" end
    end
    if C.fetching then return "fetching" end
    C.fetching, C.tried = true, now
    hs.http.asyncGet(c.ics, nil, function(code, body)
        C.fetching = false
        if code ~= 200 or type(body) ~= "string" or not body:find("BEGIN:VCALENDAR") then
            print("Dock Switcher: the calendar did not answer (" .. tostring(code) .. ")")
            if done then done(false) end
            return
        end
        local ok, events = pcall(C.parse, body, now)
        if not ok then print("Dock Switcher: the calendar could not be read: " .. tostring(events)); if done then done(false) end return end
        local s = state()
        s.events, s.fetched, s.at = events, now, os.date("%H:%M")
        s.name = s.name or body:match("X%-WR%-CALNAME:([^\n\r]+)")
        remember(s)
        if done then done(true) end
    end)
    return "fetching"
end

function C.stale()                                   -- the square opened: fetch if the last one is old
    local c = state()
    if c.ics and (not c.fetched or os.time() - c.fetched >= STALE) then C.refresh(false) end
end

function C.setAddress(url, done)
    url = (url or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if url == "" then return end
    if not url:match("^https?://") then hs.alert.show("Dock Switcher: that is not an address", 3); return end
    local s = state()
    s.ics, s.events, s.fetched, s.at, s.name = url, nil, nil, nil, nil
    remember(s)
    C.refresh(true, function(ok)
        hs.alert.show(ok and ("Dock Switcher: the calendar is connected" .. (C.lines()[1] and (": " .. C.lines()[1]) or ""))
                         or "Dock Switcher: that address did not answer with a calendar", 4)
        if done then done(ok) end
    end)
end

function C.forget()
    local s = load(); s.calendar = nil; save(s)
end

local function askAddress()
    local button, text = hs.dialog.textPrompt("Dock Switcher",
        "The calendar's secret address in iCal format (Google Calendar → Settings → the calendar → Integrate calendar → "
        .. "Secret address in iCal format). It is kept in ~/.config/dock.json and never shown again."
        .. (state().ics and "\n\nOne is set; paste another to replace it." or ""),
        "", "Set", "Cancel")
    if button ~= "Set" then return end
    C.setAddress(text)
end

function C.rows()
    local c = state()
    local rows = {}
    if c.ics then
        local l = C.lines()[1]
        rows[#rows + 1] = { title = "Next event:  " .. (l or "nothing fetched yet") .. "   (" .. (c.name or "the calendar")
                              .. (c.at and (", fetched " .. c.at) or "") .. ")  ·  fetch again",
            fn = function() C.refresh(true, function(ok)
                hs.alert.show(ok and ("Next event: " .. (C.lines()[1] or "none")) or "Dock Switcher: the calendar did not answer", 3) end) end }
        rows[#rows + 1] = { title = "Set the calendar's secret address…  (one is set)", fn = askAddress }
        rows[#rows + 1] = { title = "Forget the calendar", fn = C.forget }
    else
        rows[#rows + 1] = { title = "Set the calendar's secret address…  (no calendar yet)", fn = askAddress }
    end
    return rows
end

return C
