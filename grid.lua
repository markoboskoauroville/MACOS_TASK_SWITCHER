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
--
-- One hs.canvas per screen, the same picture on each: a dark rounded square,
-- the icons in a grid as square as the count allows, the name under each, a
-- small dot under the ones that run (as the Dock does), the chosen one lit.
-- switcher.lua owns it.
--
-- THE CLOCK. Marko, 13.9.2026: "in the upper right corner with white font fully
-- transparent, you need to have a real time clock then day then date without
-- running seconds, and the date will be in the format of day month year." So the
-- upper right corner of the square says  14:05   Saturday   13 September 2026,
-- white on nothing, and it moves with the minute while the square is open.

local G = _G.DOCKGRID or {}
_G.DOCKGRID = G

local CELL, ICON, PAD = 132, 76, 20
local TOP = 30                                    -- room above the first row for the clock

local function clockText()
    return os.date("%H:%M   %A   ") .. tostring(tonumber(os.date("%d"))) .. os.date(" %B %Y")
end

local function elements(items, lit, cols, rows)
    local w, h = cols * CELL + PAD * 2, rows * CELL + PAD + TOP
    local els = {
        { type = "rectangle", action = "fill", fillColor = { white = 0.08, alpha = 0.9 },
          roundedRectRadii = { xRadius = 22, yRadius = 22 }, frame = { x = 0, y = 0, w = w, h = h } },
        -- the clock: white letters and nothing behind them, in the upper right corner
        { type = "text", id = "clock", text = clockText(), textSize = 12.5, textFont = "Menlo",
          textColor = { white = 1, alpha = 0.92 }, textAlignment = "right",
          frame = { x = w - 420 - 16, y = 8, w = 420, h = 18 } },
    }
    for i, it in ipairs(items) do
        local r, c = math.floor((i - 1) / cols), (i - 1) % cols
        local x, y = PAD + c * CELL, TOP + r * CELL
        if i == lit then
            els[#els + 1] = { type = "rectangle", action = "fill", fillColor = { white = 1, alpha = 0.22 },
                              roundedRectRadii = { xRadius = 16, yRadius = 16 },
                              frame = { x = x + 4, y = y + 4, w = CELL - 8, h = CELL - 8 } }
        end
        if it.icon then
            -- the lit icon grows a little: under the mouse it says "ready to be clicked" (his request)
            local size = i == lit and ICON * 1.22 or ICON
            els[#els + 1] = { type = "image", image = it.icon, imageScaling = "scaleProportionally",
                              imageAlpha = i == lit and 1 or 0.85,
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
        -- an invisible plate over the cell, so the mouse can light it and pick it
        els[#els + 1] = { type = "rectangle", action = "fill", fillColor = { alpha = 0 }, id = "cell" .. i,
                          trackMouseEnterExit = true, trackMouseUp = true,
                          frame = { x = x, y = y, w = CELL, h = CELL } }
    end
    return els, w, h
end

function G.show(items, lit)
    local n = #items
    if n == 0 then return G.hide() end
    local cols = math.ceil(math.sqrt(n))
    local rows = math.ceil(n / cols)
    local els, w, h = elements(items, lit, cols, rows)
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
            c:canvasMouseEvents(false, true, true, false)   -- up, enter/exit
            c:mouseCallback(function(_, ev, elId)
                local i = tonumber((tostring(elId):match("^cell(%d+)$")))
                if not i then return end
                if ev == "mouseEnter" and G.onHover then G.onHover(i)
                elseif ev == "mouseUp" and G.onPick then G.onPick(i) end
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
    -- the minute moves while the square is open
    if not G.clockTimer then
        G.clockTimer = hs.timer.doEvery(5, function()
            local t = clockText()
            for _, c in pairs(G.canvases or {}) do
                if c[2] and c[2].text ~= t then c[2].text = t end     -- element 2 is the clock
            end
        end)
    end
    return "grid " .. n .. " on " .. #hs.screen.allScreens() .. " screens"
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
    for id, c in pairs(G.canvases or {}) do c:delete(); G.canvases[id] = nil end
    if G.clockTimer then G.clockTimer:stop(); G.clockTimer = nil end
    return "grid hidden"
end

return G
