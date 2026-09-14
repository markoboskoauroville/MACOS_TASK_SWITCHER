-- grid.lua — the square of the macOS Task Switcher (drawn by switcher.lua)
--
-- THE SQUARE OF THE DOCK'S APPS, drawn on every screen at once. Marko,
-- 9.9.2026: "It's a square menu in the middle of the both screens, not only
-- one if I have multiple. Every screen displays the same thing wherever I
-- look ... it gets the icon exactly the same images like on the dock."
--
--     .show(items, lit)   items = { {name=, icon=, running=} ... } in the order
--                         they were last used; lit = the index that is chosen
--     .hide()
--     .onHover(i)         set by the owner: the mouse is over cell i (the light follows)
--     .onPick(i)          set by the owner: cell i was clicked (the jump, at once). Marko,
--                         later the same day: "when I'm holding Control ... I can also
--                         click with the mouse and start app."
--     .onDrop(from, to)   set by the owner: the icon of cell `from` was dragged and let go on
--                         cell `to` (13.9.2026: "I can grab the icon and move it to another
--                         location"). A press that moves less than a few points is a click.
--
-- One hs.canvas per screen, the same picture on each: a dark rounded square,
-- the icons in a grid as square as the count allows, the name under each, a
-- small dot under the ones that run (as the Dock does), the chosen one lit.
-- switcher.lua owns it.
--
-- THE CLOCK. Marko, 13.9.2026: "with white font fully transparent, you need to
-- have a real time clock then day then date without running seconds, and the
-- date will be in the format of day month year", then "align it to the center",
-- then "move the line with date time to center bottom of the screen". Then,
-- 14.9.2026: "one on top of the other in the center view. So first I have a
-- clock, which is the biggest font. Then I have date, which is the smallest font.
-- And then in the same small font, you give me weather three lines centered". So
-- while the square is open, a stack stands at the bottom centre of every screen,
-- above the Dock, every line centred, white outlined in black on nothing:
--
--                          08:01:12                 the clock, big, the seconds moving
--                  Monday, 14 September 2026        the date, small
--                         19° – 23°                 the weather, three small lines
--                            rain
--                            87%
--
-- It is its own small canvas per screen, shown and hidden with the square.
--
--     .extra()            set by the owner: the small lines under the date, a list of strings,
--                         or nothing (14.9.2026: today's weather, { "19° – 23°", "rain", "87%" })

local G = _G.DOCKGRID or {}
_G.DOCKGRID = G

local CELL, ICON, PAD = 132, 76, 20
local CLOCK_W, CLOCK_BOTTOM = 760, 48            -- the clock's stack: width, how far its last line stands above the screen's bottom
local BIG, SMALL = 48, 18                        -- the clock's size and the small lines' (13.9.2026: at 14 points on the 2560-wide BenQ a line was lost against Live's bottom bar)
local BIG_H, SMALL_H, GAP = 58, 24, 4            -- line heights and the breath between the date and the weather

-- 13.9.2026, once he saw it: "non-bold font, it's supposed to show seconds, and the font should be outlined"
local function clockText() return os.date("%H:%M:%S") end
local function dateText() return os.date("%A, ") .. tostring(tonumber(os.date("%d"))) .. os.date(" %B %Y") end

local function extraLines()
    local ok, more = pcall(function() return G.extra and G.extra() end)
    if not ok then return {} end
    if type(more) == "string" then return more ~= "" and { more } or {} end
    return type(more) == "table" and more or {}
end

local function styled(text, size)
    return hs.styledtext.new(text, {
        font = { name = "Menlo", size = size },
        color = { white = 1, alpha = 0.97 },
        strokeColor = { black = 1, alpha = 0.95 }, strokeWidth = size > SMALL and -3.5 or -2.5,    -- negative: the letters are filled AND outlined; the big clock a little thicker
        paragraphStyle = { alignment = "center" },
    })
end

-- the stack's elements: the clock, the date, the small lines; and its height
local function clockElements()
    local els = {
        { type = "text", text = styled(clockText(), BIG), frame = { x = 0, y = 0, w = CLOCK_W, h = BIG_H } },
        { type = "text", text = styled(dateText(), SMALL), frame = { x = 0, y = BIG_H, w = CLOCK_W, h = SMALL_H } },
    }
    local y = BIG_H + SMALL_H + GAP
    for _, line in ipairs(extraLines()) do
        els[#els + 1] = { type = "text", text = styled(line, SMALL), frame = { x = 0, y = y, w = CLOCK_W, h = SMALL_H } }
        y = y + SMALL_H
    end
    return els, y
end

local DRAG_START = 6                               -- points the mouse must travel before a press is a drag

local function elements(items, lit, cols, rows, lifted)
    local w, h = cols * CELL + PAD * 2, rows * CELL + PAD * 2
    local els = {
        { type = "rectangle", action = "fill", fillColor = { white = 0.08, alpha = 0.9 },
          roundedRectRadii = { xRadius = 22, yRadius = 22 }, frame = { x = 0, y = 0, w = w, h = h } },
    }
    for i, it in ipairs(items) do
        local r, c = math.floor((i - 1) / cols), (i - 1) % cols
        local x, y = PAD + c * CELL, PAD + r * CELL
        if i == lit then
            els[#els + 1] = { type = "rectangle", action = "fill", fillColor = { white = 1, alpha = 0.22 },
                              roundedRectRadii = { xRadius = 16, yRadius = 16 },
                              frame = { x = x + 4, y = y + 4, w = CELL - 8, h = CELL - 8 } }
        end
        if it.icon then
            -- the lit icon grows a little: under the mouse it says "ready to be clicked" (his request);
            -- the one being dragged stays as a shadow in its cell while its picture follows the mouse
            local size = i == lit and ICON * 1.22 or ICON
            els[#els + 1] = { type = "image", image = it.icon, imageScaling = "scaleProportionally",
                              imageAlpha = i == lifted and 0.25 or (i == lit and 1 or 0.85),
                              frame = { x = x + (CELL - size) / 2, y = y + 12 - (size - ICON) / 2, w = size, h = size } }
        end
        els[#els + 1] = { type = "text", text = it.name, textSize = 11, textLineBreak = "truncateTail",
                          textColor = { white = 1, alpha = i == lit and 1 or 0.65 }, textAlignment = "center",
                          frame = { x = x + 4, y = y + ICON + 16, w = CELL - 8, h = 16 } }
        if it.running then
            els[#els + 1] = { type = "circle", action = "fill", radius = 2.2,
                              fillColor = { white = 1, alpha = 0.8 },
                              center = { x = x + CELL / 2, y = y + CELL - 6 } }
        end
        -- an invisible plate over the cell, so the mouse can light it, pick it and pick it up
        els[#els + 1] = { type = "rectangle", action = "fill", fillColor = { alpha = 0 }, id = "cell" .. i,
                          trackMouseEnterExit = true, trackMouseDown = true,
                          frame = { x = x, y = y, w = CELL, h = CELL } }
    end
    return els, w, h
end

-- the cell under a point of the screen, if it is over one of the squares
local function cellAt(p)
    for _, c in pairs(G.canvases or {}) do
        local f = c:frame()
        if f and p.x >= f.x and p.x <= f.x + f.w and p.y >= f.y and p.y <= f.y + f.h then
            local lx, ly = p.x - f.x - PAD, p.y - f.y - PAD
            if lx < 0 or ly < 0 then return nil, c end
            local col, r = math.floor(lx / CELL), math.floor(ly / CELL)
            if col >= G.cols then return nil, c end
            local i = r * G.cols + col + 1
            if G.items and G.items[i] then return i, c end
            return nil, c
        end
    end
end

-- THE DRAG. A press on a cell (the canvas says which) starts a watch on the mouse: when it has
-- moved a few points the icon is lifted, its picture follows the mouse on the square under it,
-- and the cell under the mouse lights as the place it will land; letting go there hands
-- (from, to) to the owner. Letting go without having moved is the click of before, the jump.
local function dragStop()
    if G.dragTap then G.dragTap:stop(); G.dragTap = nil end
    G.drag = nil
end

local function dragDraw(p)
    local d = G.drag
    local over, c = cellAt(p)
    if over ~= d.over then                                       -- the landing cell changed: redraw the squares
        d.over = over
        local els = elements(G.items, over or d.from, G.cols, G.rows, d.from)
        for _, cv in pairs(G.canvases or {}) do cv:replaceElements(els) end
        d.canvas = nil
    end
    local it = G.items[d.from]
    if not (it and it.icon) then return end
    if d.canvas ~= c then                                        -- the mouse crossed to another screen's square
        for _, cv in pairs(G.canvases or {}) do
            while cv:elementCount() > G.count do cv:removeElement(cv:elementCount()) end
        end
        d.canvas = c
        if c then c:appendElements({ type = "image", image = it.icon, imageScaling = "scaleProportionally",
                                     frame = { x = 0, y = 0, w = ICON, h = ICON } }) end
    end
    if c then
        local f = c:frame()
        c:elementAttribute(c:elementCount(), "frame", { x = p.x - f.x - ICON / 2, y = p.y - f.y - ICON / 2, w = ICON, h = ICON })
    end
end

local function dragStart(i, p)
    dragStop()
    G.drag = { from = i, x = p.x, y = p.y, moved = false }
    G.dragTap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDragged, hs.eventtap.event.types.leftMouseUp }, function(e)
        local d = G.drag
        if not d then dragStop(); return false end
        local q = e:location()
        if e:getType() == hs.eventtap.event.types.leftMouseDragged then
            if not d.moved and math.abs(q.x - d.x) + math.abs(q.y - d.y) >= DRAG_START then d.moved = true end
            if d.moved then dragDraw(q) end
            return false
        end
        local from, moved, over = d.from, d.moved, cellAt(q)
        dragStop()
        if not moved then
            if G.onPick then G.onPick(from) end                  -- a plain click: the jump
        elseif G.onDrop then
            G.onDrop(from, over or from)                         -- let go off every cell: back where it was
        end
        return false
    end)
    G.dragTap:start()
end

function G.show(items, lit)
    local n = #items
    if n == 0 then return G.hide() end
    local cols = math.ceil(math.sqrt(n))
    local rows = math.ceil(n / cols)
    local els, w, h = elements(items, lit, cols, rows)
    G.items, G.lit, G.cols, G.rows, G.count = items, lit, cols, rows, #els
    G.canvases = G.canvases or {}
    local seen = {}
    for _, screen in ipairs(hs.screen.allScreens()) do
        local id = screen:id()
        seen[id] = true
        local f = screen:frame()
        local frame = { x = f.x + (f.w - w) / 2, y = f.y + (f.h - h) / 2, w = w, h = h }
        local c = G.canvases[id]
        if not c then
            c = hs.canvas.new(frame)
            c:level(hs.canvas.windowLevels.popUpMenu)       -- above every window, like ⌘Tab
            c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
            c:canvasMouseEvents(true, false, true, false)   -- down, enter/exit; the up is the drag's
            c:mouseCallback(function(_, ev, elId, x, y)
                local i = tonumber((tostring(elId):match("^cell(%d+)$")))
                if not i then return end
                if ev == "mouseEnter" and G.onHover and not G.drag then G.onHover(i)
                elseif ev == "mouseDown" then dragStart(i, hs.mouse.absolutePosition()) end
            end)
            G.canvases[id] = c
        else
            c:frame(frame)
        end
        c:replaceElements(els)
        c:show()
    end
    for id, c in pairs(G.canvases) do                          -- a screen that was unplugged
        if not seen[id] then c:delete(); G.canvases[id] = nil end
    end
    G.showClock()
    return "grid " .. n .. " on " .. #hs.screen.allScreens() .. " screens"
end

-- the clock's stack at the bottom centre of every screen, white on nothing, while the square is open
function G.showClock()
    G.clocks = G.clocks or {}
    local seen = {}
    local els, h = clockElements()
    for _, screen in ipairs(hs.screen.allScreens()) do
        local id = screen:id()
        seen[id] = true
        local f = screen:frame()
        local frame = { x = f.x + (f.w - CLOCK_W) / 2, y = f.y + f.h - CLOCK_BOTTOM - h, w = CLOCK_W, h = h }
        local c = G.clocks[id]
        if not c then
            c = hs.canvas.new(frame)
            c:level(hs.canvas.windowLevels.popUpMenu)
            c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
            G.clocks[id] = c
        else
            c:frame(frame)
        end
        c:replaceElements(els)
        c:show()
    end
    for id, c in pairs(G.clocks) do
        if not seen[id] then c:delete(); G.clocks[id] = nil end
    end
    if not G.clockTimer then                                    -- the seconds move while the square is open
        G.clockTimer = hs.timer.doEvery(1, function()
            local t = styled(clockText(), BIG)
            for _, c in pairs(G.clocks or {}) do c[1].text = t end
            if G.extraCount ~= #extraLines() then G.showClock() end   -- the weather arrived: the stack grows
        end)
    end
    G.extraCount = #extraLines()
end

-- is a point (the mouse, in screen coordinates) inside any of the squares
function G.inside(p)
    for _, c in pairs(G.canvases or {}) do
        local f = c:frame()
        if f and p.x >= f.x and p.x <= f.x + f.w and p.y >= f.y and p.y <= f.y + f.h then return true end
    end
    return false
end

function G.hide()
    dragStop()
    for id, c in pairs(G.canvases or {}) do c:delete(); G.canvases[id] = nil end
    for id, c in pairs(G.clocks or {}) do c:delete(); G.clocks[id] = nil end
    if G.clockTimer then G.clockTimer:stop(); G.clockTimer = nil end
    return "grid hidden"
end

return G
