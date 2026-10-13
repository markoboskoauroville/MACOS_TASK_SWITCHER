// The next event of his Google Calendar, a small line under the weather (Marko, 14.9.2026). The connection is the
// calendar's SECRET ADDRESS IN iCAL FORMAT, kept in dock.json under "calendar" (never shown again, never in a
// repository); fetched at start and when the square opens a quarter of an hour after the last fetch; the coming ninety
// days of events kept. Reads VEVENTs itself: DTSTART (local, UTC, all day), DTEND, SUMMARY, STATUS, RRULE (DAILY,
// WEEKLY with BYDAY, MONTHLY, YEARLY; INTERVAL, COUNT, UNTIL), EXDATE, RECURRENCE-ID. A port of calendar.lua.
import Foundation

struct CalEvent { let t: Int; let ends: Int; let title: String; let allday: Bool }

final class CalendarFeed {
    let STALE = 15 * 60, RETRY = 5 * 60, HORIZON = 90 * 24 * 3600, KEEP = 120, TITLE_MAX = 56
    var tried: Int?
    var fetching = false
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }()

    func state() -> [String: Any] { Store.load()["calendar"] as? [String: Any] ?? [:] }
    func remember(_ c: [String: Any]) { Store.update { $0["calendar"] = c } }
    var hasAddress: Bool { state()["ics"] is String }

    // "20260914T170000", "20260914T150000Z" or "20260914" -> epoch, allday
    func when(_ value: String) -> (Int, Bool)? {
        let v = value.trimmingCharacters(in: .whitespaces)
        let digits = v.filter { $0.isNumber }
        if v.count >= 15, v[v.index(v.startIndex, offsetBy: 8)] == "T", digits.count >= 14 {
            let d = Array(digits)
            func n(_ a: Int, _ b: Int) -> Int { Int(String(d[a..<b]))! }
            var c = DateComponents(year: n(0, 4), month: n(4, 6), day: n(6, 8), hour: n(8, 10), minute: n(10, 12), second: n(12, 14))
            var k = cal
            if v.hasSuffix("Z") || v.dropFirst(15).first == "Z" { k.timeZone = TimeZone(identifier: "UTC")! }
            c.calendar = k
            guard let date = k.date(from: c) else { return nil }
            return (Int(date.timeIntervalSince1970), false)
        }
        if v.count == 8, digits.count == 8, let y = Int(v.prefix(4)), let m = Int(v.dropFirst(4).prefix(2)), let dd = Int(v.suffix(2)),
           let date = cal.date(from: DateComponents(year: y, month: m, day: dd, hour: 0)) {
            return (Int(date.timeIntervalSince1970), true)
        }
        return nil
    }
    func shift(_ t: Int, days: Int) -> Int { Int(cal.date(byAdding: .day, value: days, to: Date(timeIntervalSince1970: TimeInterval(t)))!.timeIntervalSince1970) }
    func shiftMonths(_ t: Int, _ months: Int) -> Int { Int(cal.date(byAdding: .month, value: months, to: Date(timeIntervalSince1970: TimeInterval(t)))!.timeIntervalSince1970) }
    func comps(_ t: Int) -> DateComponents { cal.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(t))) }

    func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\N", with: " ").replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
    }

    struct Rule { var freq = ""; var interval = 1; var count: Int?; var until: Int?; var byday: Set<Int>?; var bymonthday: Int? }
    let DAYS = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
    func rule(_ text: String) -> Rule? {
        var r = Rule()
        for part in text.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init); guard kv.count == 2 else { continue }
            switch kv[0].uppercased() {
            case "FREQ": r.freq = kv[1].uppercased()
            case "INTERVAL": r.interval = Int(kv[1]) ?? 1
            case "COUNT": r.count = Int(kv[1])
            case "UNTIL": r.until = when(kv[1])?.0
            case "BYDAY":
                var s = Set<Int>()
                for d in kv[1].uppercased().split(separator: ",") { let two = String(d.suffix(2)); if let w = DAYS[two] { s.insert(w) } }
                r.byday = s
            case "BYMONTHDAY": r.bymonthday = Int(kv[1].filter { $0.isNumber || $0 == "-" })
            default: break
            }
        }
        return r.freq.isEmpty ? nil : r
    }

    func occurrences(_ start: Int, _ r: Rule, _ from: Int, _ to: Int) -> [Int] {
        var out: [Int] = [], n = 0
        var last = to; if let u = r.until, u < last { last = u }
        if r.freq == "DAILY" || r.freq == "WEEKLY" {
            let step = r.freq == "DAILY" ? r.interval : 1
            var i = 0
            let sd = comps(start)
            let back = ((sd.weekday! - 2) % 7 + 7) % 7
            let weekStart = start - back * 86400                       // the Monday of DTSTART's week
            while true {
                let t = shift(start, days: i)
                if t > last { break }
                if let c = r.count, n >= c { break }
                var hit: Bool
                if r.freq == "DAILY" { hit = true } else {
                    let d = comps(t)
                    let inDay = r.byday.map { $0.contains(d.weekday!) } ?? (d.weekday == sd.weekday)
                    let weeks = Int((Double(t - weekStart) / Double(7 * 86400) + 0.01).rounded(.down))
                    hit = inDay && weeks % r.interval == 0
                }
                if hit { n += 1; if t >= from { out.append(t) } }
                i += step
                if i > 366 * 30 { break }
            }
        } else if r.freq == "MONTHLY" || r.freq == "YEARLY" {
            var i = 0
            let d0 = comps(start)
            while true {
                let t = r.freq == "MONTHLY" ? shiftMonths(start, i * r.interval) : shiftMonths(start, i * 12 * r.interval)
                if t > last { break }
                if let c = r.count, n >= c { break }
                if comps(t).day == (r.bymonthday ?? d0.day) { n += 1; if t >= from { out.append(t) } }   // a 31st in a short month: not one
                i += 1
                if i > 12 * 30 { break }
            }
        }
        return out
    }

    func parse(_ icsIn: String, now: Int) -> [CalEvent] {
        let ics = icsIn.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        let from = now - 86400, to = now + HORIZON
        struct E { var uid: String?; var title: String?; var status: String?; var t: Int?; var allday = false; var ends: Int?; var rule: Rule?; var recurrence: Int?; var exdates = Set<Int>() }
        var masters: [E] = [], overrides: [E] = [], skip: [String: Set<Int>] = [:]
        let re = try! NSRegularExpression(pattern: "BEGIN:VEVENT\\n(.*?)\\nEND:VEVENT", options: [.dotMatchesLineSeparators])
        for m in re.matches(in: ics, range: NSRange(ics.startIndex..., in: ics)) {
            guard let br = Range(m.range(at: 1), in: ics) else { continue }
            var e = E()
            for line in ics[br].split(separator: "\n", omittingEmptySubsequences: true) {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let head = line[..<colon], value = String(line[line.index(after: colon)...])
                let name = String(head.split(separator: ";", maxSplits: 1).first ?? head).uppercased()
                switch name {
                case "UID": e.uid = value
                case "SUMMARY": e.title = unescape(value)
                case "STATUS": e.status = value.uppercased()
                case "DTSTART": if let w = when(value) { e.t = w.0; e.allday = w.1 }
                case "DTEND": e.ends = when(value)?.0
                case "RRULE": e.rule = rule(value)
                case "RECURRENCE-ID": e.recurrence = when(value)?.0
                case "EXDATE": for v in value.split(separator: ",") { if let x = when(String(v))?.0 { e.exdates.insert(x) } }
                default: break
                }
            }
            guard let t = e.t else { continue }
            if e.uid == nil { e.uid = "\(t)" + (e.title ?? "") }
            if let rid = e.recurrence { skip[e.uid!, default: []].insert(rid); overrides.append(e) } else { masters.append(e) }
        }
        var events: [CalEvent] = []
        func add(_ t: Int, _ e: E) {
            if e.status == "CANCELLED" { return }
            let length = (e.ends != nil && e.t != nil) ? e.ends! - e.t! : (e.allday ? 86400 : 3600)
            if t + length < from || t > to { return }
            events.append(CalEvent(t: t, ends: t + length, title: e.title ?? "(no title)", allday: e.allday))
        }
        for e in masters {
            if let r = e.rule {
                for t in occurrences(e.t!, r, from, to) where !e.exdates.contains(t) && !(skip[e.uid!]?.contains(t) ?? false) { add(t, e) }
            } else { add(e.t!, e) }
        }
        for e in overrides { add(e.t!, e) }
        events.sort { $0.t < $1.t }
        return Array(events.prefix(KEEP))
    }

    func events() -> [CalEvent] {
        (state()["events"] as? [[String: Any]] ?? []).compactMap {
            guard let t = num($0["t"]) else { return nil }
            return CalEvent(t: Int(t), ends: Int(num($0["ends"]) ?? t), title: $0["title"] as? String ?? "(no title)", allday: $0["allday"] as? Bool ?? false)
        }
    }
    func nextEvent(_ now: Int = Int(Date().timeIntervalSince1970)) -> CalEvent? { events().first { $0.t > now } }

    func short(_ title: String) -> String { title.count > TITLE_MAX ? String(title.prefix(TITLE_MAX - 1)) + "…" : title }
    func label(_ ev: CalEvent, _ now: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ev.t)), n = Date(timeIntervalSince1970: TimeInterval(now))
        let clock = ev.allday ? "" : fmt("HH:mm", d)
        var day: String
        if cal.isDate(d, inSameDayAs: n) { day = ev.allday ? "today" : "" }
        else if ev.t - now < 6 * 86400 { day = cal.isDate(d, inSameDayAs: n.addingTimeInterval(86400)) ? "tomorrow" : fmt("EEE", d) }
        else { day = fmt("d MMM", d) }
        return [day, clock].filter { !$0.isEmpty }.joined(separator: " ")
    }
    func lines() -> [String] {
        let c = state()
        guard c["ics"] is String else { return [] }
        let now = Int(Date().timeIntervalSince1970)
        guard let ev = nextEvent(now) else { return c["at"] != nil ? ["no event coming"] : [] }
        let l = label(ev, now)
        return [(l.isEmpty ? "" : l + "   ") + short(ev.title)]
    }

    func refresh(force: Bool, done: ((Bool) -> Void)? = nil) {
        let c = state()
        guard let ics = c["ics"] as? String, let u = URL(string: ics) else { done?(false); return }
        let now = Int(Date().timeIntervalSince1970)
        if !force {
            if let f = num(c["fetched"]), now - Int(f) < STALE { return }
            if let t = tried, now - t < RETRY { return }
        }
        if fetching { return }
        fetching = true; tried = now
        var r = URLRequest(url: u); r.timeoutInterval = 30
        URLSession.shared.dataTask(with: r) { data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DispatchQueue.main.async {
                self.fetching = false
                guard code == 200, body.contains("BEGIN:VCALENDAR") else { NSLog("Dock Switcher: the calendar did not answer (\(code))"); done?(false); return }
                let evs = self.parse(body, now: now)
                var s = self.state()
                s["events"] = evs.map { ["t": $0.t, "ends": $0.ends, "title": $0.title, "allday": $0.allday] as [String: Any] }
                s["fetched"] = now; s["at"] = fmt("HH:mm")
                if s["name"] == nil, let rng = body.range(of: "X-WR-CALNAME:") {
                    s["name"] = String(body[rng.upperBound...].prefix { $0 != "\r" && $0 != "\n" })
                }
                self.remember(s); done?(true)
            }
        }.resume()
    }
    func stale() {
        let c = state()
        guard c["ics"] is String else { return }
        if let f = num(c["fetched"]), Int(Date().timeIntervalSince1970) - Int(f) < STALE { return }
        refresh(force: false)
    }
    func setAddress(_ url: String, done: @escaping (String) -> Void) {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return }
        guard u.hasPrefix("http://") || u.hasPrefix("https://") else { done("that is not an address"); return }
        remember(["ics": u])
        refresh(force: true) { ok in
            done(ok ? "the calendar is connected" + (self.lines().first.map { ": " + $0 } ?? "") : "that address did not answer with a calendar")
        }
    }
    func forget() { Store.update { $0.removeValue(forKey: "calendar") } }
}
