-- weather.lua — today's weather on the Dock Switcher's clock line (owned by switcher.lua)
--
-- Marko, 14.9.2026: "once a day, first time when it is started a call to some
-- weather service ... What we like is weather in Netherlands service for Croatia.
-- I need weather forecast for today, so I need minimum temperature / maximum
-- temperature and one word: sunny, cloudy, rain, 18%, 20%".
--
-- THE SERVICE. KNMI, the Dutch national weather service, runs the Harmonie-AROME
-- model over Europe every hour, and Open-Meteo serves it as `knmi_seamless`, no
-- key, no account. Croatia lies inside its domain (checked 14.9.2026: Zagreb
-- answered with KNMI's own numbers). Should KNMI have nothing for a place, the
-- second call asks Open-Meteo for its best model there.
--
-- ONCE A DAY. The forecast for today is fetched when the switcher starts, and
-- again only when the day has changed (the square opened on a new morning
-- without a restart). The answer lives in ~/.config/dock.json under "weather":
-- the place, its coordinates, the day it was fetched for, the two temperatures,
-- the word and the chance of rain. A failed call is tried again ten minutes later
-- at the earliest, and until then the line shows nothing of the weather.
--
--     .text()             "18° – 23°   rain   87%" for today, or "" (nothing yet, or not today's)
--     .lines()            the same as three lines for the clock's stack, { "18° – 23°", "rain", "87%" }, or {}
--     .refresh(force)     fetch now if today's is missing (or force); asynchronous
--     .place()            the place's name
--     .setPlace(name)     find the place (Open-Meteo's geocoder), remember it, fetch
--     .rows()             the submenu rows: the forecast (a click fetches again), the place
--
-- The place. Nothing on this Mac names his town; the clock runs in Europe/Zagreb,
-- so Zagreb is the default until he sets another from the submenu.

local W = _G.DOCKWEATHER or {}
_G.DOCKWEATHER = W

local HOME  = os.getenv("HOME")
local STATE = HOME .. "/.config/dock.json"
local DEFAULT_PLACE = { name = "Zagreb", lat = 45.8144, lon = 15.978, country = "Croatia" }
local RETRY = 600                                   -- seconds before a failed call is tried again
local FORECAST = "https://api.open-meteo.com/v1/forecast"
local GEOCODE  = "https://geocoding-api.open-meteo.com/v1/search"

-- WMO weather code -> his one word
local function word(code)
    code = tonumber(code) or -1
    if code == 0 or code == 1 then return "sunny" end
    if code == 2 or code == 3 then return "cloudy" end
    if code == 45 or code == 48 then return "fog" end
    if code >= 51 and code <= 57 then return "drizzle" end
    if code >= 61 and code <= 67 then return "rain" end
    if code >= 71 and code <= 77 then return "snow" end
    if code >= 80 and code <= 82 then return "showers" end
    if code == 85 or code == 86 then return "snow" end
    if code >= 95 then return "storm" end
    return "cloudy"
end

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
    local w = load().weather
    return type(w) == "table" and w or {}
end

local function remember(w)
    local s = load(); s.weather = w; save(s)
end

local function today() return os.date("%Y-%m-%d") end

local function placeOf(w)
    if type(w.lat) == "number" and type(w.lon) == "number" and w.place then
        return { name = w.place, lat = w.lat, lon = w.lon, country = w.country }
    end
    return DEFAULT_PLACE
end

function W.place() return placeOf(state()).name end

-- ---------------------------------------------------------------- the line
local function degrees(v) return tostring(math.floor(tonumber(v) + 0.5)) .. "°" end

function W.lines()
    local w = state()
    if w.day ~= today() or type(w.min) ~= "number" or type(w.max) ~= "number" then return {} end
    local t = { degrees(w.min) .. " – " .. degrees(w.max), w.word or "cloudy" }
    if type(w.chance) == "number" then t[3] = tostring(math.floor(w.chance + 0.5)) .. "%" end
    return t
end

function W.text() return table.concat(W.lines(), "   ") end

-- ---------------------------------------------------------------- the call
local function parse(body)
    local ok, j = pcall(hs.json.decode, body or "")
    if not ok or type(j) ~= "table" or type(j.daily) ~= "table" then return nil end
    local d = j.daily
    local min, max = (d.temperature_2m_min or {})[1], (d.temperature_2m_max or {})[1]
    if type(min) ~= "number" or type(max) ~= "number" then return nil end
    return {
        day = (d.time or {})[1] or today(),
        min = min, max = max,
        word = word((d.weather_code or {})[1]),
        chance = (d.precipitation_probability_max or {})[1],
    }
end

local function url(p, model)
    return FORECAST .. "?latitude=" .. p.lat .. "&longitude=" .. p.lon
        .. "&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max"
        .. "&timezone=auto&forecast_days=1" .. (model and ("&models=" .. model) or "")
end

-- KNMI first; if it has nothing for the place, Open-Meteo's best model there
function W.refresh(force, done)
    local w = state()
    local now = hs.timer.secondsSinceEpoch()
    if not force then
        if w.day == today() and type(w.min) == "number" then if done then done(true) end return "today's is here" end
        if W.tried and now - W.tried < RETRY then return "tried a moment ago" end
    end
    if W.fetching then return "fetching" end
    W.fetching = true
    W.tried = now
    local p = placeOf(w)
    local function keep(got, model)
        W.fetching = false
        local s = state()
        s.place, s.lat, s.lon, s.country = p.name, p.lat, p.lon, p.country
        s.day, s.min, s.max, s.word, s.chance = got.day, got.min, got.max, got.word, got.chance
        s.model, s.at = model, os.date("%H:%M")
        remember(s)
        if done then done(true) end
    end
    hs.http.asyncGet(url(p, "knmi_seamless"), nil, function(code, body)
        local got = code == 200 and parse(body)
        if got then return keep(got, "KNMI") end
        hs.http.asyncGet(url(p), nil, function(code2, body2)
            local got2 = code2 == 200 and parse(body2)
            if got2 then return keep(got2, "Open-Meteo") end
            W.fetching = false
            print("Dock Switcher: no weather for " .. p.name .. " (" .. tostring(code) .. ", " .. tostring(code2) .. ")")
            if done then done(false) end
        end)
    end)
    return "fetching " .. p.name
end

-- the day has turned: fetch today's (called when the square opens)
function W.daily()
    if state().day ~= today() then W.refresh(false) end
end

-- ---------------------------------------------------------------- the place
function W.setPlace(name, done)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    hs.http.asyncGet(GEOCODE .. "?name=" .. hs.http.encodeForQuery(name) .. "&count=1&language=en", nil, function(code, body)
        local ok, j = pcall(hs.json.decode, body or "")
        local r = code == 200 and ok and type(j) == "table" and type(j.results) == "table" and j.results[1]
        if not r then
            hs.alert.show("Dock Switcher: no place called " .. name, 3)
            if done then done(false) end
            return
        end
        local s = state()
        s.place, s.lat, s.lon, s.country = r.name, r.latitude, r.longitude, r.country
        s.day = nil                                          -- the old place's forecast is not this one's
        remember(s)
        hs.alert.show("Dock Switcher: the weather is " .. r.name .. (r.country and (", " .. r.country) or ""), 2)
        W.refresh(true, done)
    end)
end

local function askPlace()
    local button, text = hs.dialog.textPrompt("Dock Switcher",
        "The place whose weather stands beside the clock (a town, with the country if the name is common).",
        W.place(), "Set", "Cancel")
    if button ~= "Set" then return end
    W.setPlace(text)
end

function W.rows()
    local w = state()
    local line = W.text()
    local title
    if line ~= "" then
        title = "Weather today:  " .. line .. "   (" .. (w.place or W.place()) .. ", " .. (w.model or "KNMI")
              .. (w.at and (", fetched " .. w.at) or "") .. ")  ·  fetch again"
    else
        title = "Weather today: not fetched yet  (" .. W.place() .. ")  ·  fetch now"
    end
    return {
        { title = title, fn = function() W.refresh(true, function(ok)
            hs.alert.show(ok and ("Weather: " .. W.text()) or "Dock Switcher: the weather service did not answer", 3) end) end },
        { title = "Set the place for the weather…  (" .. W.place() .. ")", fn = askPlace },
    }
end

return W
