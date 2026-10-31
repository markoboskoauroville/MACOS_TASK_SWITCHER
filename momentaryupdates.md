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

> "please unify the position of the close button on every application. It's far upper right corner. There is X to close the dialog in every dialog, same." (Marko, 19.10.2026)

And a ✕ at the window's top-right corner, on the ON / OFF row: it closes the window only, the app stays ON.

**Status:** built v4 19.10.2026: the first row is DOCK SWITCHER ON / OFF, v4 and ✕ at the far right (checked by screenshot, ⌃` still "ours"). OFF closes the square, unbinds ⌃` and quits (NSApp.terminate). ✕ closes the window (performClose), the switcher stays ON; closing already left it working and the reopen already brought the window back (v2). Restarted: pid 5049 → 23643 (window shown for the screenshot) → 23763, started again with --login as it was found, no window. Marko to try ✕ and OFF.

## 22.10.2026: the double Control is not heard until ⌃` has been used

> "Another fix in the start menu for my dock switcher. It doesn't start up normally. It doesn't register my double control pressing. There is a bug. It registers double control pressing after I press control-t to switch applications, and then it's somehow started and then it recognizes double control. But before that, it doesn't. Please fix that bug." (Marko, 22.10.2026)

After the Dock Switcher starts, a double tap on Control does nothing; once ⌃` has opened the switcher, the double tap works. It must work from the start.

**Status:** v5 22.10.2026. The cause: the star starts the app hidden (`open -j … --login`); the event tap heard every ⌃⌃ and the square was built, but a hidden app's panels are never seen (they appeared at once when the app was unhidden). v5 unhides without activating at a --login start and before every square. Reproduced on v4 and proven on v5 with synthetic Control taps: restarted hidden (pid 10621 → 10923), the first ⌃⌃ showed the square, the second closed it. Marko to try with his hand after the next login.

**26.10.2026 (through Mantra Remote, the phone):**
> And for the dock, we need a local dock, emulating the real one. Basically, you need to build a remote controller for my dock, so I'm not waiting for the dock and trying to find it on screen.
> It should fill up my screen real estate on my phone with the same functions. Then I pick switching or starting, and that's it. It acts the same, but you need to make a special sister app for my dock, which runs from this user interface, please.

**26.10.2026 (through Mantra Remote):**
> now I need another feature which is going to open my menu bar if it's hidden. With arrows, I can navigate through the menu bar openings one by one, and then I can go down.

**Status, 26.10.2026:** done in v6 (Remote.swift: the phone's dock, the key count) and v7 (/menu, /menuclose by Accessibility); tested from Mantra Remote v9 on the phone.

> "Yes, build that." (Marko, 26.10.2026: the Mac unlocks a phone on its USB cable for Computer Remote)

- v8: POST /unlock (name, PIN in the body): the phone of that model on the cable is woken, its PIN pad brought up, the PIN typed, then adb on TCP 5555 armed again; one try per 15 s, five failures pause 10 min; the PIN never kept or logged. Tested without a PIN: "no PIN"; an unknown phone: "not on this Mac's USB cable", also with the body in a second packet over Tailscale. Not yet with the real PIN (Marko types it in Computer Remote). — **Status:** built, running (pid restarted).

## 27.10.2026: onto the Mac's port registry (MANTRA_PORTS v2)

> please do rebuild and restart

**Status:** v9: the door for Mantra Remote (TCP 8861, dialled by the phone) writes Dock Switcher into
~/.config/mantra-ports.json as its owner once it listens. Rebuilt; not restarted, it was not running.

## 30.10.2026: PERMISSIONS at the top right

> please make this in every application that needs some permission. If permissions are not set, it needs to have text in the top right: "Permissions." Then I click on it, and it opens me directly to my settings page where I need to set permissions.

**Status:** done in v10 (30.10.2026): PERMISSIONS (amber) on the ON / OFF row, between the spacer and v10/✕, while Accessibility (the only permission it uses: AX menus for the phone's dock, the listen-only ⌃⌃ tap) is off; a click asks once and opens Privacy_Accessibility. Re-read every 2 s, set only on change; at --login nothing is asked any more (the start used to ask always). Built and installed; not restarted, it was not running.

## 31.10.2026: ON, OFF and TOP in every application

> Please go to all the interface of my applications. Each needs to have the same user interface elements. On, off and top. Please build it in every application.

The first row as MANTRA_MANIFEST swift-apps.md "The first row of every app: ON OFF … TOP ✕": ON, OFF at the left, TOP
(green: the window above every other, UserDefaults `onTop`, applied at launch) beside ✕ at the right; each an
Accessibility button (`off`, `top`, `close`).
**Status:** pending
