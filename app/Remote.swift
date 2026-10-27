// Remote.swift: the square's sister on the phone. Mantra Remote's DOCK draws the Dock's apps on the whole phone screen
// and picks one here (Marko, 26.10.2026: "build a remote controller for my dock, so I'm not waiting for the dock and
// trying to find it on screen"). A small HTTP listener on :8861 that answers only the home network and Tailscale.
// macOS's Local Network privacy holds back connections from the home Wi-Fi unless the app is allowed there (System
// Settings → Privacy & Security → Local Network); through Tailscale (100.79.251.19) they always arrive, so the phone asks there first:
//   GET /apps           the square's apps in the square's order: {"apps":[{"id","name","running","front"}]}
//   GET /icon?id=<id>   the app's icon, PNG 192 px
//   GET /open?id=<id>   switch to it, or start it: the square's own open(), companions included
//   GET /menu           opens the menu bar of the app in front at its own menu (shown even when the bar hides itself);
//                       the phone's arrows then walk it (Marko, 26.10.2026: "open my menu bar if it's hidden. With
//                       arrows, I can navigate through the menu bar openings one by one, and then I can go down")
//   GET /menuclose      closes every open menu of the app in front (AXCancel; a second press would not)
//   GET /keys?after=N   the number of keys the Mac has seen (key downs and modifier changes, the ⌃⌃ tap's own events);
//                       held up to 3 s until it passes N, so the phone knows the moment its key landed (Marko, 26.10.2026:
//                       "it says not landed yet, but if you take a screenshot, it has landed")
//   POST /unlock        body "name=PIXEL 7&pin=…": the phone of that model on this Mac's USB cable is woken, its PIN pad
//                       brought up and the PIN typed, then its adb on TCP 5555 armed again, so the phone is reachable
//                       through Tailscale (Marko, 26.10.2026: "Yes, build that": after a restart a phone is off
//                       Tailscale until its first unlock, and only the cable reaches it). The PIN only in the body, never
//                       kept or logged; one try per 15 s, five failures stop it for 10 minutes.
import AppKit
import Network

let REMOTE_PORT: UInt16 = 8861

final class Remote {
    private var listener: NWListener?
    private let s: Switcher
    private var icons: [String: Data] = [:]
    private(set) var keys = 0
    private var waiting: [(c: NWConnection, after: Int)] = []

    /** Every key event the ⌃⌃ tap sees, the phone's included: the waiting questions are answered at once. */
    func keySeen() {
        keys += 1
        let ready = waiting.filter { keys > $0.after }
        waiting.removeAll { keys > $0.after }
        ready.forEach { reply($0.c, "200 OK", "application/json", Data("{\"keys\":\(keys)}".utf8)) }
    }
    init(_ s: Switcher) { self.s = s }

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: REMOTE_PORT),
              let l = try? NWListener(using: .tcp, on: port) else { return }
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        l.stateUpdateHandler = { [weak self] st in
            if case .failed = st { self?.listener = nil }                // tried again by the 2 s timer
            // the phone dials 8861 by number, so it never moves: this app is written down as its one owner in the
            // Mac's port registry (MANTRA_PORTS v2, 27.10.2026), and `mantra-ports check` names a stranger on it
            if case .ready = st { Ports.record("remote", REMOTE_PORT, udp: false, health: "/apps") }
        }
        l.start(queue: .main)
        listener = l
    }

    // the phone comes from the home Wi-Fi (192.168/10/172.16) or Tailscale (100.64/10); nobody else
    private func allowed(_ c: NWConnection) -> Bool {
        guard case let .hostPort(host, _) = c.endpoint else { return false }
        let ip = "\(host)".replacingOccurrences(of: "::ffff:", with: "").components(separatedBy: "%")[0]
        if ip == "127.0.0.1" || ip == "::1" { return true }
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1]))
            || (p[0] == 100 && (64...127).contains(p[1]))
    }

    private func serve(_ c: NWConnection) {
        c.start(queue: .main)
        guard allowed(c) else { c.cancel(); return }
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self = self, let d = data, let text = String(data: d, encoding: .utf8),
                  let line = text.components(separatedBy: "\r\n").first else { c.cancel(); return }
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { self.reply(c, "400 Bad Request", "text/plain", Data()); return }
            let target = String(parts[1])
            if parts[0] == "POST", target.hasPrefix("/unlock") {
                let head = text.components(separatedBy: "\r\n\r\n").first ?? ""
                let body = text.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
                let length = head.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                // the body may come in a second packet after the headers (Android's HttpURLConnection writes twice)
                if body.utf8.count < length {
                    c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { more, _, _, _ in
                        self.unlockForm(c, body + (more.flatMap { String(data: $0, encoding: .utf8) } ?? ""))
                    }
                    return
                }
                self.unlockForm(c, body)
                return
            }
            if let u = URLComponents(string: target), u.path == "/keys" {
                let after = Int(u.queryItems?.first { $0.name == "after" }?.value ?? "") ?? -1
                if self.keys > after { self.reply(c, "200 OK", "application/json", Data("{\"keys\":\(self.keys)}".utf8)); return }
                self.waiting.append((c, after))
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self, self.waiting.contains(where: { $0.c === c }) else { return }
                    self.waiting.removeAll { $0.c === c }
                    self.reply(c, "200 OK", "application/json", Data("{\"keys\":\(self.keys)}".utf8))
                }
                return
            }
            let (status, type, body) = self.answer(target)
            self.reply(c, status, type, body)
        }
    }

    // MARK: - a phone on this Mac's USB cable, unlocked with its PIN (POST /unlock)

    private func unlockForm(_ c: NWConnection, _ body: String) {
        var form: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0) }
            if kv.count == 2 { form[kv[0]] = kv[1] }
        }
        unlock(name: form["name"] ?? "", pin: form["pin"] ?? "") { ok, note in
            let j = (try? JSONSerialization.data(withJSONObject: ["ok": ok, "note": note])) ?? Data()
            self.reply(c, ok ? "200 OK" : "409 Conflict", "application/json", j)
        }
    }

    private var lastUnlock = Date.distantPast
    private var failures = 0
    private var pausedUntil = Date.distantPast
    private let adb = NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb"

    private func run(_ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: adb); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func unlock(name: String, pin: String, done: @escaping (Bool, String) -> Void) {
        let digits = pin.filter { $0.isNumber }
        let now = Date()
        if now < pausedUntil { done(false, "five wrong tries: paused until \(DateFormatter.localizedString(from: pausedUntil, dateStyle: .none, timeStyle: .short))"); return }
        if now.timeIntervalSince(lastUnlock) < 15 { done(false, "one try per 15 seconds"); return }
        if digits.isEmpty || digits.count > 16 { done(false, "no PIN"); return }
        lastUnlock = now
        DispatchQueue.global().async {
            // the phone of that model among the devices on the cable (a serial without ':' is USB)
            let want = name.uppercased().replacingOccurrences(of: " ", with: "")
            let serials = self.run(["devices"]).split(separator: "\n").dropFirst()
                .compactMap { l -> String? in let f = l.split(separator: "\t"); return f.count == 2 && f[1] == "device" && !f[0].contains(":") ? String(f[0]) : nil }
            guard let serial = serials.first(where: { s in
                self.run(["-s", s, "shell", "getprop", "ro.product.model"]).uppercased().replacingOccurrences(of: " ", with: "").contains(want) || want.isEmpty
            }) else { DispatchQueue.main.async { done(false, "\(name) is not on this Mac's USB cable") }; return }
            let locked = { self.run(["-s", serial, "shell", "dumpsys window | grep -m1 isKeyguardShowing"]).contains("=true") }
            if locked() {
                _ = self.run(["-s", serial, "shell", "input keyevent KEYCODE_WAKEUP; sleep 0.4; wm dismiss-keyguard; sleep 0.8; input text \(digits); sleep 0.2; input keyevent 66"])
                Thread.sleep(forTimeInterval: 1.5)
            }
            let ok = !locked()
            if ok { _ = self.run(["-s", serial, "tcpip", "5555"]) }      // the tunnel's port back (a restart loses it)
            DispatchQueue.main.async {
                if ok { self.failures = 0 } else {
                    self.failures += 1
                    if self.failures >= 5 { self.pausedUntil = Date().addingTimeInterval(600); self.failures = 0 }
                }
                done(ok, ok ? "\(name) unlocked, adb on 5555 again" : "the PIN did not open \(name)")
            }
        }
    }

    private func reply(_ c: NWConnection, _ status: String, _ type: String, _ body: Data) {
        var out = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }

    private func answer(_ target: String) -> (String, String, Data) {
        let u = URLComponents(string: target)
        let id = u?.queryItems?.first { $0.name == "id" }?.value
        let missing = ("404 Not Found", "text/plain", Data("no such app".utf8))
        switch u?.path ?? "" {
        case "/apps":
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let list: [[String: Any]] = s.dock.candidates().map {
                ["id": $0.id, "name": $0.name, "running": s.dock.running($0), "front": $0.id == front]
            }
            return ("200 OK", "application/json", (try? JSONSerialization.data(withJSONObject: ["apps": list])) ?? Data())
        case "/icon":
            guard let a = s.dock.byId(id) else { return missing }
            return ("200 OK", "image/png", icon(a))
        case "/menu":
            let ok = openMenu()
            return (ok ? "200 OK" : "409 Conflict", "application/json", Data("{\"ok\":\(ok),\"trusted\":\(AXIsProcessTrusted())}".utf8))
        case "/menuclose":
            closeMenus()
            return ("200 OK", "application/json", Data("{\"ok\":true}".utf8))
        case "/open":
            guard let a = s.dock.byId(id) else { return missing }
            if s.row != nil { s.close() }                        // the square, if it is open on the Mac, goes
            s.open(a)
            return ("200 OK", "application/json", Data("{\"ok\":true}".utf8))
        default:
            return missing
        }
    }

    // the front app's menu bar, its own menu (after the Apple menu), pressed by Accessibility. The press can wait until
    // the menu closes, so it runs aside with a short timeout; the menu stays open for the arrows.
    private func openMenu() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success, let menuBar = bar else { return false }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement], !items.isEmpty else { return false }
        let item = items[min(1, items.count - 1)]
        DispatchQueue.global().async {
            AXUIElementSetMessagingTimeout(item, 0.5)
            AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
        return true
    }

    private func closeMenus() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let app = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?, kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success, let b = bar,
              AXUIElementCopyAttributeValue(b as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement] else { return }
        DispatchQueue.global().async {
            for item in items {
                var menus: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &menus)
                for m in (menus as? [AXUIElement]) ?? [] { AXUIElementSetMessagingTimeout(m, 0.3); AXUIElementPerformAction(m, kAXCancelAction as CFString) }
            }
        }
    }

    private func icon(_ a: DockApp) -> Data {
        if let d = icons[a.id] { return d }
        let size = 192
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        a.icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        let d = rep.representation(using: .png, properties: [:]) ?? Data()
        icons[a.id] = d
        return d
    }
}
