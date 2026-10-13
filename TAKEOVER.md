# TAKEOVER: macOS Task Switcher

Two generations side by side until Marko confirms the second:

- **Lua** (switcher.lua, grid.lua, weather.lua, calendar.lua), loaded by MANTRA_STAR `apps/dock.lua` in Hammerspoon.
- **Swift**, `Dock Switcher (Mantra).app`, from `app/`:
  - `Store.swift`: `~/.config/dock.json`, read fresh and written whole, unknown keys kept (`enabled` is the Lua one's and is not touched).
  - `Dock.swift`: the Dock's persistent-apps through CFPreferences (the plist file as fallback), Finder first, icons from NSWorkspace; mru / use / order; the learned order and "back".
  - `Grid.swift`: one non-activating NSPanel per screen at the popUpMenu level (the square: drawing, hover, click, drag across screens), and the clock panels. The square's panel on the mouse's screen becomes key, so it takes the keys without activating the app; the front app stays in front.
  - `Keys.swift`: the Carbon hot key (⌃` and its ⇧ twin) and the listen-only event tap for ⌃ tapped twice (needs Accessibility; retried every 2 s).
  - `Weather.swift`, `CalendarFeed.swift`: ports of weather.lua and calendar.lua, the same keys in dock.json.
  - `App.swift`: the Switcher (step, move, commit, cancel, Q, H, drop, open, Resolve's companions), the settings window, the Toast, VERSION.
- Build: `./build.sh`. Version: `VERSION` in `app/App.swift`, a whole number, drawn under the icon and shown in the window.
- Test without a hand: post `community.auroville.dockswitcher.step` (opens or walks) and `.close` (a DistributedNotificationCenter
  notification), then `screencapture` the screens.
