// Today's weather for the clock's stack (Marko, 14.9.2026: "once a day ... minimum temperature / maximum temperature and
// one word: sunny, cloudy, rain, 18%"). KNMI's Harmonie model through Open-Meteo (knmi_seamless, no key), Open-Meteo's
// best model where KNMI has nothing. Fetched when the switcher starts and again only on a new day; kept in dock.json
// under "weather". A port of weather.lua.
import Foundation

final class Weather {
    static let DEFAULT_PLACE: (name: String, lat: Double, lon: Double, country: String) = ("Zagreb", 45.8144, 15.978, "Croatia")
    let RETRY: TimeInterval = 600
    var tried: Date?
    var fetching = false

    func state() -> [String: Any] { Store.load()["weather"] as? [String: Any] ?? [:] }
    func remember(_ w: [String: Any]) { Store.update { $0["weather"] = w } }
    func today() -> String { fmt("yyyy-MM-dd") }

    func place() -> (name: String, lat: Double, lon: Double, country: String?) {
        let w = state()
        if let lat = num(w["lat"]), let lon = num(w["lon"]), let n = w["place"] as? String { return (n, lat, lon, w["country"] as? String) }
        return (Self.DEFAULT_PLACE.name, Self.DEFAULT_PLACE.lat, Self.DEFAULT_PLACE.lon, Self.DEFAULT_PLACE.country)
    }

    static func word(_ code: Int) -> String {
        switch code {
        case 0, 1: return "sunny"
        case 2, 3: return "cloudy"
        case 45, 48: return "fog"
        case 51...57: return "drizzle"
        case 61...67: return "rain"
        case 71...77: return "snow"
        case 80...82: return "showers"
        case 85, 86: return "snow"
        case 95...: return "storm"
        default: return "cloudy"
        }
    }
    func degrees(_ v: Double) -> String { "\(Int((v + 0.5).rounded(.down)))°" }

    // one line under the date: 18° – 23°   rain   87%
    func lines() -> [String] {
        let w = state()
        guard (w["day"] as? String) == today(), let mn = num(w["min"]), let mx = num(w["max"]) else { return [] }
        var t = "\(degrees(mn)) – \(degrees(mx))   \(w["word"] as? String ?? "cloudy")"
        if let c = num(w["chance"]) { t += "   \(Int((c + 0.5).rounded(.down)))%" }
        return [t]
    }
    func text() -> String { lines().joined(separator: "   ") }

    private func url(_ p: (name: String, lat: Double, lon: Double, country: String?), _ model: String?) -> URL {
        var s = "https://api.open-meteo.com/v1/forecast?latitude=\(p.lat)&longitude=\(p.lon)"
            + "&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max&timezone=auto&forecast_days=1"
        if let m = model { s += "&models=" + m }
        return URL(string: s)!
    }
    private func parse(_ data: Data?) -> [String: Any]? {
        guard let data = data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let d = j["daily"] as? [String: Any],
              let mn = num((d["temperature_2m_min"] as? [Any])?.first), let mx = num((d["temperature_2m_max"] as? [Any])?.first) else { return nil }
        var out: [String: Any] = ["day": (d["time"] as? [Any])?.first as? String ?? today(), "min": mn, "max": mx,
                                  "word": Self.word(Int(num((d["weather_code"] as? [Any])?.first) ?? -1))]
        if let c = num((d["precipitation_probability_max"] as? [Any])?.first) { out["chance"] = c }
        return out
    }
    private func get(_ u: URL, _ done: @escaping (Int, Data?) -> Void) {
        var r = URLRequest(url: u); r.timeoutInterval = 15
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            DispatchQueue.main.async { done((resp as? HTTPURLResponse)?.statusCode ?? 0, d) }
        }.resume()
    }

    func refresh(force: Bool, done: ((Bool) -> Void)? = nil) {
        let w = state()
        if !force {
            if (w["day"] as? String) == today() && num(w["min"]) != nil { done?(true); return }
            if let t = tried, Date().timeIntervalSince(t) < RETRY { return }
        }
        if fetching { return }
        fetching = true; tried = Date()
        let p = place()
        let keep: ([String: Any], String) -> Void = { got, model in
            self.fetching = false
            var s = self.state()
            s["place"] = p.name; s["lat"] = p.lat; s["lon"] = p.lon; s["country"] = p.country
            for (k, v) in got { s[k] = v }
            if got["chance"] == nil { s.removeValue(forKey: "chance") }
            s["model"] = model; s["at"] = fmt("HH:mm")
            self.remember(s); done?(true)
        }
        get(url(p, "knmi_seamless")) { code, data in
            if code == 200, let got = self.parse(data) { return keep(got, "KNMI") }
            self.get(self.url(p, nil)) { code2, data2 in
                if code2 == 200, let got = self.parse(data2) { return keep(got, "Open-Meteo") }
                self.fetching = false
                NSLog("Dock Switcher: no weather for \(p.name) (\(code), \(code2))")
                done?(false)
            }
        }
    }
    func daily() { if (state()["day"] as? String) != today() { refresh(force: false) } }

    func setPlace(_ name: String, done: @escaping (String) -> Void) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let q = n.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let u = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(q)&count=1&language=en") else { return }
        get(u) { code, data in
            guard code == 200, let data = data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let r = (j["results"] as? [[String: Any]])?.first, let lat = num(r["latitude"]), let lon = num(r["longitude"]) else {
                done("no place called \(n)"); return
            }
            var s = self.state()
            s["place"] = r["name"] as? String ?? n; s["lat"] = lat; s["lon"] = lon; s["country"] = r["country"]
            s.removeValue(forKey: "day")                     // the old place's forecast is not this one's
            self.remember(s)
            done("the weather is \(s["place"] as? String ?? n)\((r["country"] as? String).map { ", " + $0 } ?? "")")
            self.refresh(force: true)
        }
    }
}
