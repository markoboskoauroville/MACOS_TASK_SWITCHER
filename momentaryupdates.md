# macOS Task Switcher: momentary updates

## 13.10.2026: from Lua to Swift
> "go through my start menu. If any app is not a Swift app, you need to convert it to a Swift app. We are quitting the Lua, no more Lua, only Swift. And everything will be in the application folder, name of the app in parentheses. Mantra"

Marko 13.10.2026: convert to Swift (no more Lua). switcher.lua, grid.lua, weather.lua, calendar.lua and the star's
apps/dock.lua (the Resolve companions) become "Dock Switcher (Mantra).app" (app/ beside the Lua; the Lua stays until
Marko confirms). **Status:** built v1 13.10.2026, "Dock Switcher (Mantra).app": the settings window and the square (15 apps,
icons, names, dots, the lit cell; the clock, date and weather plate) verified by screenshot, opened and closed from outside;
the front app stayed in front. Marko to try with the Lua dock off in the star (both answer ⌃` while both run).

## 19.10.2026: the double tap of ⌃ does nothing after a restart

> Please let me know why. The dock  switcher is not starting with double tap on control. This should work. This is part of the setup.When you again set up the switcher then go to our local transcription engine and notice that there is a huge gap between minimize button and the last icon. width of the UI should be without big gaps and please this send button on the UI is not necessary because F1 does the thing and that's it and between F1 and the pipe there is also big gap so there are places to improve spaces between elements of the user interface to guide the eye between every element you should put pipe and also reduce the space. Thank you.

**Status:** v3 19.10.2026: found the cause (Dock list read too early at boot, only Finder, the square needs two apps); the Dock is read again when the list is short, an empty CFPreferences answer falls back to the plist, a switched-off tap is switched on. Proven: ⌃⌃ opens and ⌃⌃ closes (synthetic taps); the boot itself is proven at his next restart.

## 19.10.2026: ON / OFF at the top of the window

> "When I select any of the apps, the user interface opens up. In the top of every user interface, there will now be an on/off switch ... If I say on, I close it's on ... When I just switch the check mark, and that's how I activate it. This is gone." (Marko, 19.10.2026; MANTRA_MANIFEST modules/swift-apps.md, "ON / OFF at the top of every window")

The first row of the window is ON / OFF: running is ON, OFF stops the app and quits it. Closing the window leaves it ON; the star's open brings the window back.

**Status:** saved before any code.
