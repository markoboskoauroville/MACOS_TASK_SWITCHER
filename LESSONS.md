# LESSONS

1. (13.10.2026, Swift) A Carbon hot key is not exclusive between processes: the Swift app registered ⌃` while the Lua
   switcher held it, and both answer. Run one switcher at a time.
2. (13.10.2026, Swift) A non-activating NSPanel can be made key and take the keys while another app stays active: no event
   tap and no Accessibility are needed for the keys inside the square (only for ⌃ tapped twice). When the square closes
   without a jump, the app that was in front is activated again so its window has the keys back.
3. (13.10.2026, Swift) AppKit objects (panels, status items) are made after applicationDidFinishLaunching (UHD_HD_DISPLAY
   LESSONS 1).
