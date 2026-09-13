# macOS Task Switcher — a Dock replacement for Hammerspoon

**⌘Tab over everything on your Dock, running or not. ⌃` (or a double tap on ⌃) opens a square of your Dock's own icons in
the middle of every screen at once, and it stays open: ` moves the light, ⏎ or a click brings the lit
app to the front, or launches it; ⎋ or a click outside closes it. Q quits, H hides, and the order
learns your habits.**

Two Lua files, no server, no daemon, nothing running until you start it. Written for Marko Boško's
Mac on 9.9.2026, from his words: "a launcher and switcher at the same time acting same as Command
Tab, but can launch what is not launched ... a square menu in the middle of both screens ... when I
pick the app it becomes first one ... it gets the icon exactly the same images like on the dock."

## What it does

| Key | What it does |
|-----|--------------|
| ⌃` | opens the square, the light on the app you used before this one; ⌃` again moves the light on, ⌃⇧` back |
| ⌃ tapped twice | two taps on ⌃ alone within 0.4 s open the square the same way, and close it again while it is open (13.9.2026); a key or another modifier between the taps means nothing |
| dragging an icon | picks it up and drops it on another cell: it moves there, the others slide, and from then on the order is yours (13.9.2026, "I can grab the icon and move it to another location"); a row in the settings hands the order back to your habits |
| ` or Tab | moves the light on; with ⇧ back |
| ← → ↑ ↓ | walk the grid |
| ⏎ | bring the lit app to the front, launching it if it is not running |
| Q | quit the lit app, politely, as ⌘Q does inside ⌘Tab; the square stays, its dot goes out |
| H | hide the lit app |
| ⎋ | close the square, jump nowhere; a click anywhere outside the square does the same, and so does a double tap on ⌃ |
| the mouse | hovering lights a cell (its icon grows a little), a click on it is the jump |

The square stays open until you choose or close it (Marko, 10.9.2026: "it should stay open until I
press escape or click out of it ... control + tick opens it, and then tick is selecting and enter is
activating the app. Or mouse is activating the app"). Letting go of ⌃ means nothing.

- **A clock at the bottom centre of every screen** while the square is open (13.9.2026): the time with its seconds, the day, and the date as day month year, white letters outlined in black on nothing, so a glance at the switcher is a glance at the clock.

- **The list is your Dock's.** Read from `~/Library/Preferences/com.apple.dock.plist`, `persistent-apps`,
  again whenever the Dock changes; Finder is added by hand because the Dock does not list it. The icons
  are the bundles' own, the very images the Dock draws.
- **The same square on every screen.** One canvas per screen with the same elements, above every
  window, on every space. Unplug a screen and its square goes.
- **The order learns your habits.** The first cell is the app in front, the second the one you used
  before it (so a tap is "back"), then the most opened first, and the never opened last in Dock order.
  Every activation counts, from any road, through an application watcher; the counts and the order live
  in `~/.config/dock.json`.
- **Or the order is yours.** Drag an icon to another cell while the square is open and it stays there:
  the cells keep your order, an app new to the Dock joins at the end, and the square opens with the
  light on the app you used before this one, so ⏎ is still "back". "Learn the order from my habits
  again" in the settings forgets it (13.9.2026).

## Install

Hammerspoon with Accessibility permission. Then:

    git clone https://github.com/markoboskoauroville/MACOS_TASK_SWITCHER ~/Developer/MACOS_TASK_SWITCHER

and in `~/.hammerspoon/init.lua`:

    TASK_SWITCHER = dofile(os.getenv("HOME") .. "/Developer/MACOS_TASK_SWITCHER/switcher.lua")
    TASK_SWITCHER.start()

Reload Hammerspoon. ⌃` is the default; `TASK_SWITCHER.menu()` returns the settings rows (change the
shortcut, the double tap on and off, forget the dragged order, re-read the Dock). `TASK_SWITCHER.onOpen`
may be set to a function `(app, launched)`: it is called after every jump made through the square, with
the app (`id`, `name`, `path`) and whether the jump launched it or only brought it forward, so something
else can follow (on Marko's Mac the star menu starts Resolve's companions when Resolve is launched here) for any menu you want to put them in. On Marko's Mac the star menu
(MANTRA_STAR, `apps/dock.lua`) is that menu: a tick starts it, a second tick stops it.

The shortcut is words joined by plus in `~/.config/dock.json` (`"hotkey": "ctrl+\`"`, or `alt+space`);
any modifier will do. `"double"` is the longest gap between two taps on ⌃ (0.4; 0 turns it off);
`"order"` is the list of bundle ids as you dragged them, absent while the order learns your habits.

## Files

    switcher.lua     the whole switcher: the Dock list, the order, the keys, the mouse, the jump
    grid.lua         the square: one canvas per screen, icons, names, dots, the lit cell
    ~/.config/dock.json   your counts, your dragged order, your shortcut (never in the repository)

MIT licence. Built with Claude Code.
