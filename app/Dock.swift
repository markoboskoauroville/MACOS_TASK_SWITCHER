// The list is the Dock's own (com.apple.dock persistent-apps), Finder first because the Dock does not list it; the icons
// are the bundles' own. THE ORDER LEARNS HIS HABITS: the app in front, the one used before it (so a tap is "back"), the
// most opened first, the never opened last in Dock order. Or, once he has dragged an icon, HIS ORDER (13.9.2026).
// A port of switcher.lua's Dock part.
import AppKit

struct DockApp { let id: String; let name: String; let path: String; let icon: NSImage }

let FINDER_ID = "com.apple.finder"

final class DockList {
    var apps: [DockApp] = []
    var mru: [String] = []
    var use: [String: Int] = [:]
    var order: [String]?
    private var signature = ""

    func loadState() {
        let s = Store.load()
        mru = s["mru"] as? [String] ?? []
        use = (s["use"] as? [String: Any] ?? [:]).compactMapValues { num($0).map { Int($0) } }
        order = s["order"] as? [String]
    }
    func remember() {
        Store.update { d in
            d["mru"] = mru; d["use"] = use
            if let o = order { d["order"] = o } else { d.removeValue(forKey: "order") }
        }
    }

    private func tiles() -> [[String: Any]] {
        if let a = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] { return a }
        let url = URL(fileURLWithPath: HOME + "/Library/Preferences/com.apple.dock.plist")
        guard let d = try? Data(contentsOf: url), let p = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return [] }
        return p["persistent-apps"] as? [[String: Any]] ?? []
    }

    @discardableResult func readDock() -> Int {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        var list = [DockApp(id: FINDER_ID, name: "Finder", path: "/System/Library/CoreServices/Finder.app",
                            icon: NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app"))]
        for tile in tiles() {
            let td = tile["tile-data"] as? [String: Any] ?? [:]
            guard let urlString = (td["file-data"] as? [String: Any])?["_CFURLString"] as? String else { continue }
            var path = URL(string: urlString)?.path ?? urlString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding ?? urlString
            if path.hasSuffix("/") && path.count > 1 { path.removeLast() }
            let b = Bundle(path: path)
            let id = td["bundle-identifier"] as? String ?? b?.bundleIdentifier ?? path
            let name = td["file-label"] as? String ?? b?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? b?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: path); icon.size = NSSize(width: 128, height: 128)
            list.append(DockApp(id: id, name: name, path: path, icon: icon))
        }
        apps = list
        signature = list.map { $0.path }.joined(separator: "|")
        return apps.count
    }
    // the Dock changed (an app added, removed, moved): read it again
    func followDock() {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let now = tiles().compactMap { (($0["tile-data"] as? [String: Any])?["file-data"] as? [String: Any])?["_CFURLString"] as? String }
        let sig = (["/System/Library/CoreServices/Finder.app"] + now.map { s -> String in
            var p = URL(string: s)?.path ?? s; if p.hasSuffix("/") && p.count > 1 { p.removeLast() }; return p }).joined(separator: "|")
        if sig != signature { readDock() }
    }

    func byId(_ id: String?) -> DockApp? { guard let id = id else { return nil }; return apps.first { $0.id == id } }
    func running(_ a: DockApp) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: a.id).isEmpty }

    func touch(_ id: String) {
        guard byId(id) != nil else { return }
        mru.removeAll { $0 == id }; mru.insert(id, at: 0)
        if mru.count > 64 { mru = Array(mru.prefix(64)) }
        use[id, default: 0] += 1
        remember()
    }

    func candidates() -> [DockApp] {
        var list: [DockApp] = []; var seen = Set<String>()
        func take(_ a: DockApp?) { if let a = a, !seen.contains(a.id) { list.append(a); seen.insert(a.id) } }
        if let o = order {
            o.forEach { take(byId($0)) }; apps.forEach { take($0) }
            return list
        }
        take(byId(NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
        for id in mru where !seen.contains(id) { if byId(id) != nil { take(byId(id)); break } }
        var recency: [String: Int] = [:]; for (i, id) in mru.enumerated() where recency[id] == nil { recency[id] = i }
        let rest = apps.filter { !seen.contains($0.id) && (use[$0.id] ?? 0) > 0 }.sorted {
            let ua = use[$0.id] ?? 0, ub = use[$1.id] ?? 0
            if ua != ub { return ua > ub }
            return (recency[$0.id] ?? Int.max) < (recency[$1.id] ?? Int.max)
        }
        rest.forEach { take($0) }; apps.forEach { take($0) }
        return list
    }

    // the app used before the one in front: the second cell of the learned order, or, under his order, the first of
    // the recently used that is not in front (0-based)
    func previousIndex(_ list: [DockApp]) -> Int {
        guard order != nil else { return 1 }
        let fid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for id in mru where id != fid { if let i = list.firstIndex(where: { $0.id == id }) { return i } }
        return 0
    }
}
