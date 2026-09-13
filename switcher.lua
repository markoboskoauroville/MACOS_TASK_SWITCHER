-- switcher.lua — macOS Task Switcher, a Dock replacement for Hammerspoon
--
-- ⌘Tab over everything on the Dock, running or not: a launcher and a switcher
-- in one square. Marko's star menu loads it (MANTRA_STAR/apps/dock.lua is the
-- switch); anyone else: dofile this file from ~/.hammerspoon/init.lua and call
-- .start(). Nothing else is needed; grid.lua sits beside it.
-- Marko, 9.9.2026: "control ` ... a launcher and switcher at the same
-- time acting same as Command Tab, but can launch what is not launched. So it
-- lists all my apps in that menu. It's a square menu in the middle of both
-- screens ... when I pick the app it becomes first one ... it gets the icon
-- exactly the same images like on the dock."
--
-- Ticked:
--   ⌃`          the square opens on every screen and STAYS OPEN: every app on the Dock, last
--               used first, Finder among them, the light on the app used before this one.
--               Marko, 10.9.2026: "it should stay open until I press escape or click out of
--               it ... control + tick opens it, and then tick is selecting and enter is
--               activating the app. Or mouse is activating the app."
--   `           moves the light on, ⇧` back (⌃` and ⌃⇧` do the same); the arrow keys walk the grid
--   ⏎           brings the lit app to the front, launching it if it is not running
--   the mouse   hovering lights a cell, a click on it is the jump
--   ⎋           closes without a jump; so does a click anywhere outside the square
--   Q, H        quit or hide the lit app, as ⌘Q and ⌘H do inside ⌘Tab; the square stays
-- The list is the Dock's own (com.apple.dock.plist, persistent-apps), read
-- when the app starts and again whenever the Dock changes it. The icons are
-- the bundles' own, the ones the Dock shows. THE ORDER LEARNS HIS HABITS
-- (his words, later the same day): the first cell is the app in front, the
-- second the one used before it (so a tap is "back"), and the rest sit by how
-- often they were opened, the most used first; apps never opened come last in
-- the Dock's order. Every activation counts, from any road, through the
-- application watcher; ~/.config/dock.json keeps the counts and the order.

local M = { name = "Dock Switcher (⌃` opens the square of the Dock; ` selects, ⏎ or the mouse starts)", key = "dock" }
_G.TASK_SWITCHER = M                                   -- reachable from hs -c and from the star's switch

local HOME  = os.getenv("HOME")
local HERE  = (debug.getinfo(1, "S").source:match("^@(.*/)") or (HOME .. "/Developer/MACOS_TASK_SWITCHER/"))
local GRID  = HERE .. "grid.lua"
local PLIST = HOME .. "/Library/Preferences/com.apple.dock.plist"
local STATE = HOME .. "/.config/dock.json"
local DEFAULT_HOTKEY = "ctrl+`"
local FINDER = { id = "com.apple.finder", name = "Finder", path = "/System/Library/CoreServices/Finder.app" }

local on = false
local apps = {}                  -- { id, name, path, icon } in the Dock's order
local mru = {}                   -- bundle ids, most recently used first
local use = {}                   -- bundle id -> how many times it was brought forward
local hotkeys = {}
local watcher, plistWatcher
local holdTap, holdTimer, ctrlDown          -- HOLD ⌃: the square opens when ⌃ alone is held for a while
local HOLD_DEFAULT = 3                      -- seconds (Marko, 13.9.2026: "holding Ctrl for three seconds")

local function grid() return dofile(GRID) end

-- ---------------------------------------------------------------- the settings file
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

local function remember()
    local s = load(); s.mru = mru; s.use = use; save(s)
end

-- ---------------------------------------------------------------- the Dock
local function unquote(url)
    return (url:gsub("^file://", ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end):gsub("/$", ""))
end

function M.readDock()
    local list = { { id = FINDER.id, name = FINDER.name, path = FINDER.path } }
    local ok, p = pcall(hs.plist.read, PLIST)
    for _, tile in ipairs((ok and type(p) == "table" and p["persistent-apps"]) or {}) do
        local td = tile["tile-data"] or {}
        local url = td["file-data"] and td["file-data"]["_CFURLString"]
        if url then
            local path = unquote(url)
            local info = hs.application.infoForBundlePath(path) or {}
            list[#list + 1] = {
                path = path,
                id = td["bundle-identifier"] or info.CFBundleIdentifier or path,
                name = td["file-label"] or info.CFBundleDisplayName or info.CFBundleName
                       or path:match("([^/]+)%.app$") or path,
            }
        end
    end
    for _, a in ipairs(list) do
        local icon = hs.image.iconForFile(a.path)
        if icon then a.icon = icon:setSize({ w = 128, h = 128 }) end
    end
    apps = list
    return #apps
end

local function byId(id)
    for _, a in ipairs(apps) do if a.id == id then return a end end
end

local function running(a)
    return #hs.application.applicationsForBundleID(a.id) > 0      -- exact; get() can answer with a dead app
end

local function touch(id)
    if not byId(id) then return end
    for i = #mru, 1, -1 do if mru[i] == id then table.remove(mru, i) end end
    table.insert(mru, 1, id)
    while #mru > 64 do table.remove(mru) end
    use[id] = (use[id] or 0) + 1
    remember()
end

-- the grid's order: the front app, the one used before it, then the most used
-- first (a tie goes to the more recent), then the never-used in the Dock's order
local function candidates()
    local list, seen = {}, {}
    local function take(a) if a and not seen[a.id] then list[#list + 1] = a; seen[a.id] = true end end
    local front = hs.application.frontmostApplication()
    local fid = front and front:bundleID()
    take(fid and byId(fid))
    for _, id in ipairs(mru) do if not seen[id] then take(byId(id)); break end end
    local recency = {}
    for i, id in ipairs(mru) do recency[id] = i end
    local rest = {}
    for _, a in ipairs(apps) do if not seen[a.id] and (use[a.id] or 0) > 0 then rest[#rest + 1] = a end end
    table.sort(rest, function(a, b)
        local ua, ub = use[a.id] or 0, use[b.id] or 0
        if ua ~= ub then return ua > ub end
        return (recency[a.id] or 1e9) < (recency[b.id] or 1e9)
    end)
    for _, a in ipairs(rest) do take(a) end
    for _, a in ipairs(apps) do take(a) end
    return list
end

-- ---------------------------------------------------------------- a jump: focus, or launch
function M.open(a)
    if not a then return end
    touch(a.id)
    local app = hs.application.applicationsForBundleID(a.id)[1]
    if app then
        app:activate(true)                                   -- every window of it, as ⌘Tab does
    elseif not hs.application.launchOrFocusByBundleID(a.id) then
        hs.application.open(a.path)                          -- an app whose id the Dock got wrong
    end
end

function M.previous()
    local c = candidates()
    if c[2] then M.open(c[2]) end
end

-- ---------------------------------------------------------------- ⌘Tab
local row, lit, cols, keyTap, mouseTap

local function items()
    local t = {}
    for i, a in ipairs(row) do t[i] = { name = a.name, icon = a.icon, running = running(a) } end
    return t
end

local function close()
    if keyTap then keyTap:stop(); keyTap = nil end
    if mouseTap then mouseTap:stop(); mouseTap = nil end
    grid().hide()
    local target = row and row[lit]
    row = nil
    return target
end

local function commit() M.open(close()) end
local function cancel() close() end

local function move(d)
    lit = ((lit - 1 + d) % #row) + 1
    grid().show(items(), lit)
end

local function pick(i)
    if row and row[i] then lit = i; commit() end
end

local function hover(i)
    if row and row[i] and i ~= lit then lit = i; grid().show(items(), lit) end
end

-- Q and H while the square is up: the lit app is quit (asked politely, as ⌘Q does)
-- or hidden; the square stays, its dot goes out a moment later
local function quitLit()
    local a = row and row[lit]
    local app = a and hs.application.applicationsForBundleID(a.id)[1]
    if app then app:kill() end
    hs.timer.doAfter(0.6, function() if row then grid().show(items(), lit) end end)
end

local function hideLit()
    local a = row and row[lit]
    local app = a and hs.application.applicationsForBundleID(a.id)[1]
    if app then app:hide() end
end

function M.quit(id)                                    -- the same from outside, for a test or a script
    local app = hs.application.applicationsForBundleID(id)[1]
    if app then app:kill(); return true end
    return false
end

-- THE SQUARE STAYS OPEN (Marko, 10.9.2026). ⌃` opens it with the light on the app used before
-- this one, so ⏎ at once is "back". While it is up, ` moves the light on and ⇧` back (the
-- shortcut itself does the same), the arrows walk the grid, ⏎ or a click on a cell is the jump,
-- ⎋ or a click outside closes it. Nothing happens when a modifier is let go.
local function step(dir)
    if not row then
        row = candidates()
        if #row < 2 then row = nil; return end
        lit = 1
        cols = math.ceil(math.sqrt(#row))
        local g = grid(); g.onPick = pick; g.onHover = hover
        keyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
            local k = hs.keycodes.map[e:getKeyCode()]
            local shift = e:getFlags().shift and true or false
            if k == "`" then move(shift and -1 or 1) return true
            elseif k == "tab" then move(shift and -1 or 1) return true
            elseif k == "right" then move(1) return true
            elseif k == "left" then move(-1) return true
            elseif k == "down" then move(cols) return true
            elseif k == "up" then move(-cols) return true
            elseif k == "escape" then cancel() return true
            elseif k == "return" then commit() return true
            elseif k == "q" then quitLit() return true
            elseif k == "h" then hideLit() return true
            end
            return false
        end)
        keyTap:start()
        -- a click outside the square closes it; a click inside is the grid's own (a cell is the jump)
        mouseTap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown }, function(e)
            if row and not grid().inside(e:location()) then cancel() end
            return false
        end)
        mouseTap:start()
    end
    move(dir)
end

-- ---------------------------------------------------------------- the shortcut
local function parse(text)
    local mods, key = {}, nil
    for part in (text or ""):gmatch("[^%+%s]+") do
        local p = part:lower()
        if p == "ctrl" or p == "control" then mods[#mods + 1] = "ctrl"
        elseif p == "alt" or p == "option" or p == "opt" then mods[#mods + 1] = "alt"
        elseif p == "cmd" or p == "command" then mods[#mods + 1] = "cmd"
        elseif p == "shift" then mods[#mods + 1] = "shift"
        else key = part end
    end
    return mods, key
end

local function hotkeyText()
    local s = load()
    return (s.hotkey and s.hotkey ~= "") and s.hotkey or DEFAULT_HOTKEY
end

local function bind()
    for _, hk in ipairs(hotkeys) do hk:delete() end
    hotkeys = {}
    local text = hotkeyText()
    local mods, key = parse(text)
    if not key or #mods == 0 then hs.alert.show("Dock Switcher: the shortcut needs a modifier, like ctrl+`", 3); return end
    local ok, hk = pcall(hs.hotkey.bind, mods, key, function() step(1) end, nil, function() step(1) end)
    if not ok then hs.alert.show("Dock Switcher: cannot bind " .. text, 3); return end
    hotkeys[1] = hk
    local back, hasShift = {}, false
    for _, m in ipairs(mods) do back[#back + 1] = m; if m == "shift" then hasShift = true end end
    if not hasShift then
        back[#back + 1] = "shift"
        local ok2, hk2 = pcall(hs.hotkey.bind, back, key, function() step(-1) end, nil, function() step(-1) end)
        if ok2 then hotkeys[2] = hk2 end
    end
end

-- HOLD ⌃ FOR THREE SECONDS (Marko, 13.9.2026: "a second shortcut to open the Dock Switcher by holding
-- Ctrl for three seconds"). A tap on the modifier keys: ⌃ pressed alone starts a clock; any other key or
-- modifier in the meantime, or ⌃ let go, stops it; when the clock runs out with ⌃ still down and the
-- square not open, the square opens as ⌃` would. ⌃` itself, or ⌃C, ⌃A and the rest, stop the clock
-- by their key, so nothing opens while ⌃ is used for something else.
local function holdSeconds()
    local v = load().hold
    if v == nil then return HOLD_DEFAULT end
    return tonumber(v) or 0
end

local function holdStop()
    if holdTimer then holdTimer:stop(); holdTimer = nil end
end

local function holdBind()
    if holdTap then holdTap:stop(); holdTap = nil end
    holdStop()
    ctrlDown = false
    holdTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown }, function(e)
        if e:getType() == hs.eventtap.event.types.keyDown then holdStop(); return false end
        local f = e:getFlags()
        local alone = f.ctrl and not (f.cmd or f.alt or f.shift or f.fn)
        if alone and not ctrlDown then
            ctrlDown = true
            local secs = holdSeconds()
            if secs > 0 and not row then
                holdStop()
                holdTimer = hs.timer.doAfter(secs, function()
                    holdTimer = nil
                    if ctrlDown and not row then step(1) end
                end)
            end
        elseif not alone then
            ctrlDown = false
            holdStop()
        end
        return false
    end)
    holdTap:start()
end

local function askShortcut()
    local button, text = hs.dialog.textPrompt("Dock Switcher",
        "The shortcut that opens the square (with shift it walks backwards).\nWords joined by plus, for example  ctrl+`  or  alt+space.",
        hotkeyText(), "Set", "Cancel")
    if button ~= "Set" then return end
    local s = load()
    s.hotkey = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s.hotkey == "" then s.hotkey = nil end
    save(s)
    bind()
    hs.alert.show("Dock Switcher: " .. hotkeyText() .. " walks the Dock", 2)
end

-- ---------------------------------------------------------------- following the Mac
local function watch()
    if watcher then return end
    watcher = hs.application.watcher.new(function(_, ev, app)
        if ev == hs.application.watcher.activated and app then
            local id = app:bundleID()
            if id then touch(id) end
        end
    end)
    watcher:start()
    plistWatcher = hs.pathwatcher.new(HOME .. "/Library/Preferences", function(paths)
        for _, p in ipairs(paths) do
            if p:match("com%.apple%.dock%.plist$") then M.readDock(); return end
        end
    end)
    plistWatcher:start()
end

function M.running() return on end

function M.start()
    local s = load(); s.enabled = true; save(s)
    mru = type(s.mru) == "table" and s.mru or {}
    use = type(s.use) == "table" and s.use or {}
    local n = M.readDock()
    on = true
    watch()
    bind()
    holdBind()
    return true, "Dock Switcher on: " .. hotkeyText() .. " walks " .. n .. " apps; ⌃ held " .. holdSeconds() .. " s opens the square"
end

function M.stop()
    local s = load(); s.enabled = false; save(s)
    on = false
    close()
    for _, hk in ipairs(hotkeys) do hk:delete() end
    hotkeys = {}
    if holdTap then holdTap:stop(); holdTap = nil end
    holdStop()
    if watcher then watcher:stop(); watcher = nil end
    if plistWatcher then plistWatcher:stop(); plistWatcher = nil end
    return true, "Dock Switcher off"
end

-- ticked before: on again after a reload of Hammerspoon, without a hand on the star
if load().enabled then hs.timer.doAfter(1, function() M.start() end) end

function M.menu()
    if not on then return nil end
    return {
        { title = "Previous app now  (" .. hotkeyText() .. ")", fn = M.previous },
        { title = "Set the keyboard shortcut…  (" .. hotkeyText() .. ")", fn = askShortcut },
        { title = "Holding ⌃ alone for " .. HOLD_DEFAULT .. " seconds opens the square", checked = holdSeconds() > 0,
          fn = function() local s = load(); s.hold = holdSeconds() > 0 and 0 or HOLD_DEFAULT; save(s) end },
        { title = "Read the Dock again  (" .. #apps .. " apps)", fn = function()
            hs.alert.show("Dock Switcher: " .. M.readDock() .. " apps", 2) end },
    }
end

return M
