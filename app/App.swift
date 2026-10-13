// Dock Switcher (Mantra): ⌘Tab over everything on the Dock, running or not. ⌃` (or ⌃ tapped twice) opens a square of
// the Dock's own icons in the middle of every screen at once, and it stays open: ` or Tab moves the light (⇧ back), the
// arrows walk the grid, ⏎ or a click brings the lit app to the front or launches it, Q quits it, H hides it, ⎋ or a click
// outside closes the square; an icon dragged to another cell stays there. The order learns his habits. A clock, the
// date, today's weather and the next event of his calendar stand under it. The Swift app that replaces switcher.lua,
// grid.lua, weather.lua, calendar.lua and the star's apps/dock.lua (Marko, 13.10.2026: "no more Lua, only Swift"),
// with the same settings file, ~/.config/dock.json. Resolve launched from the square starts its companions in the star
// (13.9.2026), from ~/.config/star-launch.json.
import SwiftUI
import AppKit
import Carbon.HIToolbox

let VERSION = 1
let RELEASES = "https://github.com/markoboskoauroville/MACOS_TASK_SWITCHER/releases/latest"
let DEFAULT_HOTKEY = "ctrl+`"
let DOUBLE_DEFAULT = 0.4
let RESOLVE = "com.blackmagic-design.DaVinciResolve"
let LAUNCH_FILE = URL(fileURLWithPath: HOME + "/.config/star-launch.json")
let LAUNCH_DEFAULT: [String: [String]] = [RESOLVE: ["display", "pages", "importbutton"]]
let NAMES = [RESOLVE: "DaVinci Resolve"]

let GREEN = Color(red: 0x33/255, green: 0xD1/255, blue: 0x7A/255)
let GREY = Color(red: 0x7A/255, green: 0x80/255, blue: 0x87/255)
let AMBER = Color(red: 0xE8/255, green: 0xA3/255, blue: 0x3D/255)
let INK = Color(red: 0x0B/255, green: 0x0D/255, blue: 0x10/255)

// a short note in the middle of the screen, as hs.alert did
final class Toast {
    static let shared = Toast()
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    let label = NSTextField(labelWithString: "")
    var job: DispatchWorkItem?
    init() {
        panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear; panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = NSView(); v.wantsLayer = true; v.layer?.backgroundColor = NSColor(white: 0, alpha: 0.75).cgColor; v.layer?.cornerRadius = 14
        label.font = .systemFont(ofSize: 18); label.textColor = .white; v.addSubview(label); panel.contentView = v
    }
    func show(_ text: String, _ seconds: Double = 2) {
        label.stringValue = text; label.sizeToFit()
        let w = label.frame.width + 40, h = label.frame.height + 24
        let f = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!).frame
        panel.setFrame(NSRect(x: f.midX - w / 2, y: f.midY - h / 2 - 160, width: w, height: h), display: true)
        label.frame.origin = NSPoint(x: 20, y: 12)
        panel.orderFrontRegardless()
        job?.cancel(); let j = DispatchWorkItem { self.panel.orderOut(nil) }; job = j
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: j)
    }
}

final class Switcher: ObservableObject {
    let dock = DockList(), grid = Grid(), weather = Weather(), calendar = CalendarFeed(), keys = HotKeys(), ctrl = CtrlTap()
    var row: [DockApp]?
    var lit = 0, cols = 1
    var frontAtOpen: NSRunningApplication?
    var mouseMonitor: Any?
    @Published var said = ""
    @Published var hotkeyOK = false
    @Published var tapOK = false
    @Published var tick = 0

    // ---------------------------------------------------------------- start
    func start() {
        dock.loadState()
        dock.readDock()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier { self?.dock.touch(id) }
        }
        HotKeys.onStep = { [weak self] dir in self?.step(dir) }
        ctrl.seconds = { [weak self] in self?.doubleSeconds() ?? DOUBLE_DEFAULT }
        ctrl.onDouble = { [weak self] in guard let self = self else { return }; if self.row != nil { self.cancel() } else { self.step(1) } }
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        hotkeyOK = keys.bind(hotkeyText())
        tapOK = ctrl.start()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.ctrl.running { self.tapOK = self.ctrl.start() }
            if self.keys.bound != self.hotkeyText() { self.hotkeyOK = self.keys.bind(self.hotkeyText()) }   // held by another app: try again
            self.dock.followDock()
            self.tick += 1
        }
        // for a test or a script, as `hs -c` reached the Lua one: open, walk, close the square from outside
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("community.auroville.dockswitcher.step"), object: nil, queue: .main) { [weak self] _ in self?.step(1) }
        dnc.addObserver(forName: Notification.Name("community.auroville.dockswitcher.close"), object: nil, queue: .main) { [weak self] _ in self?.cancel() }
        weather.refresh(force: false) { [weak self] _ in self?.tick += 1 }       // once a day
        calendar.refresh(force: false) { [weak self] _ in self?.tick += 1 }
    }

    // ---------------------------------------------------------------- the square
    func items() -> [GridItem] { (row ?? []).map { GridItem(name: $0.name, icon: $0.icon, running: dock.running($0)) } }
    func extraLines() -> [String] { weather.lines() + calendar.lines() }

    func step(_ dir: Int) {
        if row == nil {
            let r = dock.candidates()
            guard r.count >= 2 else { return }
            row = r
            lit = dock.order != nil ? ((dock.previousIndex(r) - dir) % r.count + r.count) % r.count : 0   // the step below lands on "back"
            cols = Int(Double(r.count).squareRoot().rounded(.up))
            frontAtOpen = NSWorkspace.shared.frontmostApplication
            weather.daily(); calendar.stale()
            grid.onPick = { [weak self] i in self?.pick(i) }
            grid.onHover = { [weak self] i in self?.hover(i) }
            grid.onDrop = { [weak self] a, b in self?.drop(a, b) }
            grid.onKey = { [weak self] e in self?.key(e) ?? false }
            grid.extra = { [weak self] in self?.extraLines() ?? [] }
            // a click outside the square closes it (a click inside is the grid's own)
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self = self, self.row != nil, !self.grid.inside(NSEvent.mouseLocation) else { return }
                self.cancel()
            }
        }
        move(dir)
    }
    func move(_ d: Int) {
        guard let r = row else { return }
        lit = ((lit + d) % r.count + r.count) % r.count
        grid.show(items(), lit: lit)
    }
    @discardableResult func close() -> DockApp? {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        grid.hide()
        let target = row.flatMap { lit < $0.count ? $0[lit] : nil }
        row = nil
        return target
    }
    func commit() { if let a = close() { open(a) } }
    func cancel() { close(); frontAtOpen?.activate() }          // the keys go back to the app that was in front
    func pick(_ i: Int) { guard let r = row, i < r.count else { return }; lit = i; commit() }
    func hover(_ i: Int) { guard let r = row, i < r.count, i != lit else { return }; lit = i; grid.show(items(), lit: lit) }
    func drop(_ from: Int, _ to: Int) {
        guard var r = row, from < r.count, to < r.count, from != to else { if row != nil { grid.show(items(), lit: lit) }; return }
        let a = r.remove(at: from); r.insert(a, at: to); row = r
        lit = to
        dock.order = r.map { $0.id }; dock.remember()
        grid.show(items(), lit: lit)
    }
    func forgetOrder() {
        dock.order = nil; dock.remember()
        if row != nil { row = dock.candidates(); lit = 0; grid.show(items(), lit: lit) }
        tick += 1
    }
    func quitLit() {
        guard let r = row, let app = NSRunningApplication.runningApplications(withBundleIdentifier: r[lit].id).first else { return }
        app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if self.row != nil { self.grid.show(self.items(), lit: self.lit) } }
    }
    func hideLit() { if let r = row { NSRunningApplication.runningApplications(withBundleIdentifier: r[lit].id).first?.hide() } }

    func key(_ e: NSEvent) -> Bool {
        let back = e.modifierFlags.contains(.shift)
        switch Int(e.keyCode) {
        case kVK_ANSI_Grave, kVK_Tab: move(back ? -1 : 1)
        case kVK_RightArrow: move(1)
        case kVK_LeftArrow: move(-1)
        case kVK_DownArrow: move(cols)
        case kVK_UpArrow: move(-cols)
        case kVK_Escape: cancel()
        case kVK_Return, kVK_ANSI_KeypadEnter: commit()
        case kVK_ANSI_Q: quitLit()
        case kVK_ANSI_H: hideLit()
        default: return false
        }
        return true
    }

    // ---------------------------------------------------------------- a jump: focus, or launch
    func open(_ a: DockApp) {
        dock.touch(a.id)
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: a.id).first {
            app.activate(options: [.activateAllWindows])               // every window of it, as ⌘Tab does
            companions(a, launched: false)
        } else {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: a.path), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            companions(a, launched: true)
        }
    }
    func previous() {
        let c = dock.candidates(); let i = dock.previousIndex(c)
        if i < c.count { open(c[i]) }
    }

    // ---------------------------------------------------------------- Resolve's companions in the star (13.9.2026)
    func launchTable() -> [String: [String]] {
        guard let d = try? Data(contentsOf: LAUNCH_FILE), let t = try? JSONSerialization.jsonObject(with: d) as? [String: [String]] else { return LAUNCH_DEFAULT }
        return t
    }
    func saveLaunch(_ t: [String: [String]]) {
        try? FileManager.default.createDirectory(at: LAUNCH_FILE.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: t, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: LAUNCH_FILE) }
    }
    func starRows() -> [[String: Any]] {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: HOME + "/.config/star-rows.json")),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return j["rows"] as? [[String: Any]] ?? []
    }
    func shortName(_ row: [String: Any]) -> String {
        let n = row["name"] as? String ?? row["key"] as? String ?? "?"
        return n.split(separator: "(").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? n
    }
    func companions(_ a: DockApp, launched: Bool) {
        guard launched, let wanted = launchTable()[a.id], !wanted.isEmpty else { return }
        let rows = starRows().filter { wanted.contains($0["key"] as? String ?? "") }
        DispatchQueue.global().async {
            var started: [String] = []
            for r in rows {
                let key = r["key"] as? String ?? ""
                if (r["kind"] as? String) == "app", let path = r["app"] as? String {
                    let on = NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == path }
                    if !on { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }; started.append(self.shortName(r)) }
                } else {                                          // still a Lua app of the star
                    let lua = "local a; for _, x in ipairs((STAR and STAR.apps) or {}) do if x.key == '\(key)' then a = x end end; " +
                              "if a and not a.running() then a.start(); if STAR.remember then STAR.remember() end; return 'started' end; return 'on'"
                    let p = Process(); p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/hs"); p.arguments = ["-t", "5", "-c", lua]
                    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
                    if (try? p.run()) != nil {
                        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); p.waitUntilExit()
                        if out.contains("started") { started.append(self.shortName(r)) }
                    }
                }
            }
            if !started.isEmpty { DispatchQueue.main.async { Toast.shared.show("\(NAMES[a.id] ?? a.name) starts: \(started.joined(separator: ", "))", 3) } }
        }
    }
    func toggleCompanion(_ id: String, _ key: String) {
        var t = launchTable(); var keep = t[id] ?? []
        if keep.contains(key) { keep.removeAll { $0 == key } } else { keep.append(key) }
        t[id] = keep; saveLaunch(t); tick += 1
    }

    // ---------------------------------------------------------------- settings
    func hotkeyText() -> String { let h = Store.load()["hotkey"] as? String ?? ""; return h.isEmpty ? DEFAULT_HOTKEY : h }
    func setHotkey(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty && parseShortcut(t) == nil { said = "the shortcut needs a modifier and a key I know, like ctrl+`"; return }
        Store.update { if t.isEmpty { $0.removeValue(forKey: "hotkey") } else { $0["hotkey"] = t } }
        hotkeyOK = keys.bind(hotkeyText())
        said = hotkeyOK ? "\(hotkeyText()) walks the Dock" : "\(hotkeyText()) is held by another app (the Lua switcher?); tried again every 2 s"
    }
    func doubleSeconds() -> Double { let v = Store.load()["double"]; return v == nil ? DOUBLE_DEFAULT : (num(v) ?? 0) }
    func toggleDouble() { let on = doubleSeconds() > 0; Store.update { $0["double"] = on ? 0 : DOUBLE_DEFAULT }; tick += 1 }
}

struct Word: View {
    let text: String; let on: Bool; let action: () -> Void
    var body: some View {
        Text(text).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(on ? GREEN : GREY)
            .padding(.horizontal, 6).padding(.vertical, 4).contentShape(Rectangle()).onTapGesture(perform: action)
    }
}
struct Head: View {
    let name: String; let value: String
    var body: some View {
        HStack {
            Text(name).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY)
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(AMBER).lineLimit(1).truncationMode(.tail)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var s: Switcher
    @State var keyText = ""
    @State var placeText = ""
    @State var address = ""
    var body: some View {
        let _ = s.tick
        VStack(alignment: .leading, spacing: 14) {
            Head(name: "THE SQUARE", value: "\(s.hotkeyText().uppercased()) · \(s.dock.apps.count) APPS")
            HStack(spacing: 0) {
                Word(text: "PREVIOUS APP NOW", on: false) { s.previous() }
                Word(text: "READ THE DOCK AGAIN", on: false) { s.said = "\(s.dock.readDock()) apps on the Dock"; s.tick += 1 }
            }
            HStack {
                Text("SHORTCUT").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY)
                TextField(DEFAULT_HOTKEY, text: $keyText).textFieldStyle(.roundedBorder).frame(width: 150).onSubmit { s.setHotkey(keyText) }
                Word(text: "SET", on: false) { s.setHotkey(keyText) }
                Text(s.hotkeyOK ? "ours" : "held by another app").font(.system(size: 11, design: .monospaced)).foregroundColor(s.hotkeyOK ? GREEN : AMBER)
            }
            HStack {
                Text("⌃ TAPPED TWICE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY)
                Word(text: "OPENS THE SQUARE", on: s.doubleSeconds() > 0) { if s.doubleSeconds() == 0 { s.toggleDouble() } }
                Word(text: "OFF", on: s.doubleSeconds() == 0) { if s.doubleSeconds() > 0 { s.toggleDouble() } }
            }
            HStack {
                Text("THE ORDER").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY)
                if s.dock.order != nil {
                    Text("YOURS (DRAGGED)").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(AMBER)
                    Word(text: "LEARN FROM MY HABITS AGAIN", on: false) { s.forgetOrder() }
                } else {
                    Text("LEARNS YOUR HABITS · DRAG AN ICON FOR YOUR OWN").font(.system(size: 11, design: .monospaced)).foregroundColor(GREY)
                }
            }
            Divider().background(GREY)
            Head(name: "WEATHER TODAY", value: s.weather.text().isEmpty ? "NOT FETCHED YET" : s.weather.text())
            HStack {
                Text("\(s.weather.place().name)\((s.weather.state()["model"] as? String).map { ", " + $0 } ?? "")\((s.weather.state()["at"] as? String).map { ", fetched " + $0 } ?? "")")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(GREY)
                Spacer()
                Word(text: "FETCH AGAIN", on: false) { s.weather.refresh(force: true) { ok in s.said = ok ? "weather: \(s.weather.text())" : "the weather service did not answer"; s.tick += 1 } }
            }
            HStack {
                Text("PLACE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY)
                TextField("a town", text: $placeText).textFieldStyle(.roundedBorder).frame(width: 200).onSubmit { setPlace() }
                Word(text: "SET", on: false) { setPlace() }
            }
            Divider().background(GREY)
            Head(name: "NEXT EVENT", value: s.calendar.hasAddress ? (s.calendar.lines().first ?? "NOTHING FETCHED YET") : "NO CALENDAR YET")
            if s.calendar.hasAddress {
                HStack {
                    Text("\(s.calendar.state()["name"] as? String ?? "the calendar")\((s.calendar.state()["at"] as? String).map { ", fetched " + $0 } ?? "")")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(GREY)
                    Spacer()
                    Word(text: "FETCH AGAIN", on: false) { s.calendar.refresh(force: true) { ok in s.said = ok ? "next event: \(s.calendar.lines().first ?? "none")" : "the calendar did not answer"; s.tick += 1 } }
                    Word(text: "FORGET", on: false) { s.calendar.forget(); s.tick += 1 }
                }
            }
            HStack {
                Text("SECRET iCAL ADDRESS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY)
                SecureField(s.calendar.hasAddress ? "one is set; paste another to replace it" : "Google Calendar › Integrate calendar", text: $address)
                    .textFieldStyle(.roundedBorder).onSubmit { setAddress() }
                Word(text: "SET", on: false) { setAddress() }
            }
            Divider().background(GREY)
            ForEach(companionIDs(), id: \.self) { id in
                VStack(alignment: .leading, spacing: 2) {
                    Text("STARTS WITH \((NAMES[id] ?? id).uppercased()), LAUNCHED FROM THE SQUARE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(GREY)
                    HStack(spacing: 0) {
                        ForEach(companionRows(id), id: \.self) { key in
                            Word(text: rowName(key).uppercased(), on: (s.launchTable()[id] ?? []).contains(key)) { s.toggleCompanion(id, key) }
                        }
                    }
                }
            }
            if !s.tapOK {
                Text("Accessibility: not allowed yet, so ⌃ tapped twice cannot be heard. System Settings → Privacy & Security → Accessibility → Dock Switcher (Mantra) on.")
                    .font(.system(size: 11)).foregroundColor(AMBER).fixedSize(horizontal: false, vertical: true)
            }
            if !s.said.isEmpty { Text(s.said).font(.system(size: 11, design: .monospaced)).foregroundColor(GREY).fixedSize(horizontal: false, vertical: true) }
            HStack { Spacer(); Text("v\(VERSION)").font(.system(size: 11, design: .monospaced)).foregroundColor(GREY).onTapGesture { NSWorkspace.shared.open(URL(string: RELEASES)!) } }
        }
        .padding(24).frame(width: 560).background(INK).preferredColorScheme(.dark)
        .onAppear { keyText = s.hotkeyText(); placeText = s.weather.place().name }
    }
    func setPlace() { s.weather.setPlace(placeText) { msg in s.said = msg; s.tick += 1 } }
    func setAddress() { let a = address; address = ""; s.calendar.setAddress(a) { msg in s.said = msg; s.tick += 1 } }
    func companionIDs() -> [String] { Array(Set(LAUNCH_DEFAULT.keys).union(s.launchTable().keys)).sorted() }
    func companionRows(_ id: String) -> [String] {
        let offered = Set(LAUNCH_DEFAULT[id] ?? []).union(s.launchTable()[id] ?? [])
        return s.starRows().compactMap { $0["key"] as? String }.filter { offered.contains($0) }
    }
    func rowName(_ key: String) -> String { s.starRows().first { ($0["key"] as? String) == key }.map { s.shortName($0) } ?? key }
}

// the engine is made after launch (UHD_HD_DISPLAY LESSONS 1: AppKit objects before launch crash); the window is its
// settings, and closing it leaves the switcher working
let SWITCHER = Switcher()

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        SWITCHER.start()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Dock Switcher (Mantra)"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(s: SWITCHER))
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        show()
    }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool { show(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}

@main struct Main {
    static func main() {
        let app = NSApplication.shared
        let d = AppDelegate(); app.delegate = d
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
