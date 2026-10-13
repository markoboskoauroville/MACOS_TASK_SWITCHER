// The settings file, ~/.config/dock.json, shared with the Lua switcher while both exist: the counts (use), the recently
// used (mru), his dragged order (order), the shortcut (hotkey), the double tap (double), today's weather (weather) and
// the calendar (calendar). Read fresh and written back whole at every change, keys this app does not know kept.
import Foundation

let HOME = NSHomeDirectory()
let STATE_URL = URL(fileURLWithPath: HOME + "/.config/dock.json")

enum Store {
    static func load() -> [String: Any] {
        guard let d = try? Data(contentsOf: STATE_URL), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return j
    }
    static func save(_ d: [String: Any]) {
        try? FileManager.default.createDirectory(at: STATE_URL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: d) { try? data.write(to: STATE_URL, options: .atomic) }
    }
    static func update(_ change: (inout [String: Any]) -> Void) { var d = load(); change(&d); save(d) }
}

func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

// the Mac's clock, the way Lua's os.date writes it (English names, the C locale)
func fmt(_ pattern: String, _ d: Date = Date()) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = pattern
    return f.string(from: d)
}
