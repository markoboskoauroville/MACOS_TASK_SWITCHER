# macOS Task Switcher — a Dock replacement for Hammerspoon

**⌘Tab over everything on your Dock, running or not. Hold ⌃, tap `, and a square of your Dock's
own icons opens in the middle of every screen at once. Let go on the one you want and it comes to
the front, or launches. Q quits it, H hides it, the mouse works, and the order learns your habits.**

Two Lua files, no server, no daemon, nothing running until you start it. Written for Marko Boško's
Mac on 9.9.2026, from his words: "a launcher and switcher at the same time acting same as Command
Tab, but can launch what is not launched ... a square menu in the middle of both screens ... when I
pick the app it becomes first one ... it gets the icon exactly the same images like on the dock."

## What it does

| Key | While the square is up |
|-----|------------------------|
| ⌃` (tap) | back to the app you used before this one; tap again and you are back |
| ⌃` (hold), ` | the square opens; each ` moves the light on, ⇧` moves it back |
| ← → ↑ ↓ | walk the grid |
| ⏎ or let go of ⌃ | bring the lit app to the front, launching it if it is not running |
| Q | quit the lit app, politely, as ⌘Q does inside ⌘Tab; the square stays, its dot goes out |
| H | hide the lit app |
| ⎋ | close the square, jump nowhere |
| the mouse | hovering lights a cell (its icon grows a little), a click is the jump |

- **The list is your Dock's.** Read from `~/Library/Preferences/com.apple.dock.plist`, `persistent-apps`,
  again whenever the Dock changes; Finder is added by hand because the Dock does not list it. The icons
  are the bundles' own, the very images the Dock draws.
- **The same square on every screen.** One canvas per screen with the same elements, above every
  window, on every space. Unplug a screen and its square goes.
- **The order learns your habits.** The first cell is the app in front, the second the one you used
  before it (so a tap is "back"), then the most opened first, and the never opened last in Dock order.
  Every activation counts, from any road, through an application watcher; the counts and the order live
  in `~/.config/dock.json`.
- **Letting go is the jump.** An event tap hears the modifier release, and a tenth-of-a-second clock
  checks it too, because a tap alone misses a very quick press.

## Install

Hammerspoon with Accessibility permission. Then:

    git clone https://github.com/markoboskoauroville/MACOS_TASK_SWITCHER ~/Developer/MACOS_TASK_SWITCHER

and in `~/.hammerspoon/init.lua`:

    TASK_SWITCHER = dofile(os.getenv("HOME") .. "/Developer/MACOS_TASK_SWITCHER/switcher.lua")
    TASK_SWITCHER.start()

Reload Hammerspoon. ⌃` is the default; `TASK_SWITCHER.menu()` returns the settings rows (change the
shortcut, re-read the Dock) for any menu you want to put them in. On Marko's Mac the star menu
(MANTRA_STAR, `apps/dock.lua`) is that menu: a tick starts it, a second tick stops it.

The shortcut is words joined by plus in `~/.config/dock.json` (`"hotkey": "ctrl+\`"`, or `alt+space`);
the first modifier is the one you hold.

## Files

    switcher.lua     the whole switcher: the Dock list, the order, the keys, the mouse, the jump
    grid.lua         the square: one canvas per screen, icons, names, dots, the lit cell
    ~/.config/dock.json   your order, your counts, your shortcut (never in the repository)

MIT licence. Built with Claude Code.
