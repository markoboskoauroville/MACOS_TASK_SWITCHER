# LESSONS

1. (13.10.2026, Swift) A Carbon hot key is not exclusive between processes: the Swift app registered ⌃` while the Lua
   switcher held it, and both answer. Run one switcher at a time.
2. (13.10.2026, Swift) A non-activating NSPanel can be made key and take the keys while another app stays active: no event
   tap and no Accessibility are needed for the keys inside the square (only for ⌃ tapped twice). When the square closes
   without a jump, the app that was in front is activated again so its window has the keys back.
3. (13.10.2026, Swift) AppKit objects (panels, status items) are made after applicationDidFinishLaunching (UHD_HD_DISPLAY
   LESSONS 1).
4. (19.10.2026, v3) Started by the star right after boot (06:00, --login), the switcher read the Dock's list before macOS
   had it and kept only Finder; the square needs two apps, so every ⌃⌃ ended in silence for the whole day (the tap and
   Accessibility were fine). CFPreferences can answer with an empty list rather than nil: an empty answer falls back to
   the plist file, and a list shorter than two is read again (every 2 s and at the press). A restart of the app hid it.
4. (22.10.2026) A hidden app's windows and panels are never seen, `orderFrontRegardless` included. Started by `open -j`, an
   LSUIElement app is hidden: the double-tap tap worked and the square was built out of sight. Unhide with
   `NSApp.unhideWithoutActivation()` (the app in front keeps the keys) before showing anything.
- **(26.10.2026) A listener in a signed app on macOS 15 gets no connections from the home Wi-Fi** until Local Network
  is allowed for it (TCP connects, nothing arrives); 127.0.0.1 and the Tailscale address (utun) work. Ask through
  Tailscale, or have Marko allow it in System Settings → Privacy & Security → Local Network.
- **pkill -f with "(Mantra)" in the pattern misses**: the parentheses are a regex group. Kill by `pgrep -f MacOS/DockSwitcher`.

