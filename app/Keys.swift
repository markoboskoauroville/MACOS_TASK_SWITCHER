// The shortcut (⌃` by default, a Carbon hot key: no permission) and its ⇧ twin that walks back; and the DOUBLE TAP
// on ⌃ (13.9.2026): ⌃ pressed and let go alone, twice within 0.4 s, opens the square, or closes it when it is open.
// The double tap must see every modifier change and every key, so it is an event tap that only listens (it never
// swallows anything); it needs Accessibility and is tried again every 2 s until it is given.
import AppKit
import Carbon.HIToolbox

let KEYCODES: [String: Int] = ["`": kVK_ANSI_Grave, "space": kVK_Space, "tab": kVK_Tab, "return": kVK_Return, "escape": kVK_Escape,
    "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, ";": kVK_ANSI_Semicolon,
    "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash,
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
    "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
    "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
    "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
    "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6,
    "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
    "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13,
    "f14": kVK_F14, "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20]

// "ctrl+`", "alt+space": Carbon modifiers (at least one) and a key code
func parseShortcut(_ text: String) -> (mods: UInt32, key: UInt32, shift: Bool)? {
    var mods: UInt32 = 0, key: UInt32?, shift = false
    for raw in text.split(whereSeparator: { $0 == "+" || $0 == " " }) {
        switch raw.lowercased() {
        case "ctrl", "control": mods |= UInt32(controlKey)
        case "alt", "option", "opt": mods |= UInt32(optionKey)
        case "cmd", "command": mods |= UInt32(cmdKey)
        case "shift": mods |= UInt32(shiftKey); shift = true
        default: if let k = KEYCODES[raw.lowercased()] { key = UInt32(k) }
        }
    }
    guard let k = key, mods != 0 else { return nil }
    return (mods, k, shift)
}

final class HotKeys {
    static var onStep: ((Int) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private static var installed = false
    var bound = ""

    // true when the shortcut is ours; false when another app holds it (the Lua switcher, while it runs)
    @discardableResult func bind(_ text: String) -> Bool {
        unbind()
        if !Self.installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, ev, _ in
                var hk = EventHotKeyID()
                GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                let dir = hk.id == 2 ? -1 : 1
                DispatchQueue.main.async { HotKeys.onStep?(dir) }
                return noErr
            }, 1, &spec, nil, nil)
            Self.installed = true
        }
        guard let s = parseShortcut(text) else { return false }
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(s.key, s.mods, EventHotKeyID(signature: 0x444F434B, id: 1), GetApplicationEventTarget(), 0, &ref) == noErr, let r = ref else { return false }
        refs.append(r)
        if !s.shift {                                          // with ⇧ it walks back
            var back: EventHotKeyRef?
            if RegisterEventHotKey(s.key, s.mods | UInt32(shiftKey), EventHotKeyID(signature: 0x444F434B, id: 2), GetApplicationEventTarget(), 0, &back) == noErr, let b = back { refs.append(b) }
        }
        bound = text
        return true
    }
    func unbind() { refs.forEach { UnregisterEventHotKey($0) }; refs = []; bound = "" }
}

final class CtrlTap {
    static var shared: CtrlTap!
    var onDouble: (() -> Void)?
    var seconds: () -> Double = { 0.4 }
    private(set) var tap: CFMachPort?
    private var ctrlDown = false, clean = false, lastTap: Double = 0

    init() { CtrlTap.shared = self }
    var running: Bool { tap != nil }

    @discardableResult func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let cb: CGEventTapCallBack = { _, type, ev, _ in CtrlTap.shared.handle(type, ev); return Unmanaged.passUnretained(ev) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                        eventsOfInterest: CGEventMask(mask), callback: cb, userInfo: nil) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
        return true
    }

    // a tap macOS switched off (at boot, after sleep) is switched on again every 2 s
    func wake() { if let t = tap, !CGEvent.tapIsEnabled(tap: t) { CGEvent.tapEnable(tap: t, enable: true) } }

    func handle(_ type: CGEventType, _ ev: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }; return }
        if type == .keyDown { clean = false; lastTap = 0; return }
        let f = ev.flags
        let others: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskSecondaryFn]
        let alone = f.contains(.maskControl) && f.intersection(others).isEmpty
        let none = !f.contains(.maskControl) && f.intersection(others).isEmpty
        if alone && !ctrlDown { ctrlDown = true; clean = true; return }
        if !alone {
            let wasTap = ctrlDown && clean && none                // ⌃ let go clean: nothing else touched
            ctrlDown = false; clean = false
            guard wasTap else { lastTap = 0; return }
            let now = Date().timeIntervalSince1970, gap = seconds()
            if gap > 0 && now - lastTap <= gap { lastTap = 0; DispatchQueue.main.async { self.onDouble?() } }
            else { lastTap = now }
        }
    }
}
