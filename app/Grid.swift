// The square of the Dock's apps, drawn on every screen at once (Marko, 9.9.2026: "a square menu in the middle of the
// both screens ... it gets the icon exactly the same images like on the dock"), and the clock's stack at the bottom
// centre of every screen while it is open (13-14.9.2026). A port of grid.lua: one panel per screen above every window
// on every space; the icons in a grid as square as the count allows, the name under each, a dot under the running
// ones, the lit one on a plate and a little larger; hover lights, a click is the jump, a drag moves the icon.
// The panels never activate this app, so the app in front stays in front (and the key panel takes the keys).
import AppKit

let CELL: CGFloat = 132, ICON: CGFloat = 76, PAD: CGFloat = 20, DRAG_START: CGFloat = 6
let CLOCK_W: CGFloat = 760, CLOCK_BOTTOM: CGFloat = 48, BIG: CGFloat = 48, SMALL: CGFloat = 18
let BIG_H: CGFloat = 58, SMALL_H: CGFloat = 24, GAP: CGFloat = 4, PLATE_PAD_X: CGFloat = 28, PLATE_PAD_Y: CGFloat = 10, PLATE_RADIUS: CGFloat = 16

struct GridItem { let name: String; let icon: NSImage; let running: Bool }

func screenID(_ s: NSScreen) -> Int { (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0 }

final class GridPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with e: NSEvent) { _ = onKey?(e) }            // keys the square does not use are dropped
    override func cancelOperation(_ sender: Any?) {}
    static func make(_ frame: NSRect) -> GridPanel {
        let p = GridPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false; p.acceptsMouseMovedEvents = true
        return p
    }
}

final class GridView: NSView {
    weak var grid: Grid?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    override func draw(_ r: NSRect) { grid?.draw(self) }
    override func mouseMoved(with e: NSEvent) { grid?.hover(NSEvent.mouseLocation) }
    override func mouseDown(with e: NSEvent) { grid?.down(NSEvent.mouseLocation) }
    override func mouseDragged(with e: NSEvent) { grid?.dragged(NSEvent.mouseLocation) }
    override func mouseUp(with e: NSEvent) { grid?.up(NSEvent.mouseLocation) }
}

final class ClockView: NSView {
    var lines: [String] = []
    override var isFlipped: Bool { true }
    static func attrs(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        return [.font: NSFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular),
                .foregroundColor: NSColor(white: 1, alpha: 0.97), .paragraphStyle: p]
    }
    static func clockText() -> String { fmt("HH:mm:ss") }
    static func dateText() -> String { fmt("EEEE, d MMMM yyyy") }
    static func height(_ extra: Int) -> CGFloat { PLATE_PAD_Y + BIG_H + SMALL_H + (extra > 0 ? GAP + CGFloat(extra) * SMALL_H : 0) + PLATE_PAD_Y }
    override func draw(_ r: NSRect) {
        let big = Self.attrs(BIG), small = Self.attrs(SMALL)
        let clock = Self.clockText(), date = Self.dateText()
        var w = max((clock as NSString).size(withAttributes: big).width, (date as NSString).size(withAttributes: small).width)
        for l in lines { w = max(w, (l as NSString).size(withAttributes: small).width) }
        let pw = min(CLOCK_W, w + PLATE_PAD_X * 2), h = Self.height(lines.count)
        NSColor(white: 0, alpha: 0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: (CLOCK_W - pw) / 2, y: 0, width: pw, height: h), xRadius: PLATE_RADIUS, yRadius: PLATE_RADIUS).fill()
        (clock as NSString).draw(in: NSRect(x: 0, y: PLATE_PAD_Y, width: CLOCK_W, height: BIG_H), withAttributes: big)
        (date as NSString).draw(in: NSRect(x: 0, y: PLATE_PAD_Y + BIG_H, width: CLOCK_W, height: SMALL_H), withAttributes: small)
        var y = PLATE_PAD_Y + BIG_H + SMALL_H + GAP
        for l in lines { (l as NSString).draw(in: NSRect(x: 0, y: y, width: CLOCK_W, height: SMALL_H), withAttributes: small); y += SMALL_H }
    }
}

final class Grid {
    var items: [GridItem] = []
    var lit = 0, cols = 1, rows = 1
    var panels: [Int: (panel: GridPanel, view: GridView)] = [:]
    var clocks: [Int: (panel: NSPanel, view: ClockView)] = [:]
    var onPick: ((Int) -> Void)?, onHover: ((Int) -> Void)?, onDrop: ((Int, Int) -> Void)?, onKey: ((NSEvent) -> Bool)?
    var extra: (() -> [String])?
    struct Drag { var from: Int; var start: NSPoint; var moved = false; var over: Int?; var at = NSPoint.zero }
    var drag: Drag?
    var clockTimer: Timer?
    var extraKey = ""
    var isShown: Bool { !panels.isEmpty }

    func show(_ items: [GridItem], lit: Int) {
        guard !items.isEmpty else { hide(); return }
        let first = panels.isEmpty
        self.items = items; self.lit = lit
        cols = Int(Double(items.count).squareRoot().rounded(.up)); rows = Int((Double(items.count) / Double(cols)).rounded(.up))
        let w = CGFloat(cols) * CELL + PAD * 2, h = CGFloat(rows) * CELL + PAD * 2
        var seen = Set<Int>()
        for s in NSScreen.screens {
            let id = screenID(s); seen.insert(id)
            let f = s.visibleFrame
            let frame = NSRect(x: (f.midX - w / 2).rounded(), y: (f.midY - h / 2).rounded(), width: w, height: h)
            if panels[id] == nil {
                let p = GridPanel.make(frame); let v = GridView(frame: NSRect(origin: .zero, size: frame.size))
                v.grid = self; p.contentView = v; p.onKey = { [weak self] e in self?.onKey?(e) ?? false }
                panels[id] = (p, v)
            }
            let pv = panels[id]!
            pv.panel.setFrame(frame, display: false); pv.view.frame = NSRect(origin: .zero, size: frame.size)
            pv.view.needsDisplay = true
            pv.panel.orderFrontRegardless()
        }
        for (id, pv) in panels where !seen.contains(id) { pv.panel.orderOut(nil); panels[id] = nil }       // a screen unplugged
        if first {                                    // the keys go to the square on the screen with the mouse
            let m = NSEvent.mouseLocation
            let here = NSScreen.screens.first { $0.frame.contains(m) }.map(screenID)
            ((here.flatMap { panels[$0] }) ?? panels.values.first)?.panel.makeKey()
        }
        showClock()
    }
    func redraw() { panels.values.forEach { $0.view.needsDisplay = true } }

    func showClock() {
        let lines = extra?() ?? []
        let h = ClockView.height(lines.count)
        var seen = Set<Int>()
        for s in NSScreen.screens {
            let id = screenID(s); seen.insert(id)
            let f = s.visibleFrame
            let frame = NSRect(x: (f.midX - CLOCK_W / 2).rounded(), y: f.minY + CLOCK_BOTTOM, width: CLOCK_W, height: h)
            if clocks[id] == nil {
                let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                p.level = .popUpMenu; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
                p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false
                let v = ClockView(frame: NSRect(origin: .zero, size: frame.size)); p.contentView = v
                clocks[id] = (p, v)
            }
            let cv = clocks[id]!
            cv.panel.setFrame(frame, display: false); cv.view.frame = NSRect(origin: .zero, size: frame.size)
            cv.view.lines = lines; cv.view.needsDisplay = true
            cv.panel.orderFrontRegardless()
        }
        for (id, cv) in clocks where !seen.contains(id) { cv.panel.orderOut(nil); clocks[id] = nil }
        extraKey = lines.joined(separator: "\n")
        if clockTimer == nil {                        // the seconds move while the square is open
            clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if (self.extra?() ?? []).joined(separator: "\n") != self.extraKey { self.showClock() }   // the weather or the calendar arrived
                else { self.clocks.values.forEach { $0.view.needsDisplay = true } }
            }
        }
    }

    func hide() {
        drag = nil
        panels.values.forEach { $0.panel.orderOut(nil) }; panels = [:]
        clocks.values.forEach { $0.panel.orderOut(nil) }; clocks = [:]
        clockTimer?.invalidate(); clockTimer = nil
    }

    func inside(_ p: NSPoint) -> Bool { panels.values.contains { $0.panel.frame.contains(p) } }

    // the cell under a point of the screen (bottom-left coordinates), and the view it is in
    func cellAt(_ p: NSPoint) -> (Int?, GridView?) {
        for pv in panels.values where pv.panel.frame.contains(p) {
            let f = pv.panel.frame
            let lx = p.x - f.minX - PAD, ly = f.maxY - p.y - PAD
            if lx < 0 || ly < 0 { return (nil, pv.view) }
            let c = Int(lx / CELL), r = Int(ly / CELL)
            if c >= cols { return (nil, pv.view) }
            let i = r * cols + c
            return (i < items.count ? i : nil, pv.view)
        }
        return (nil, nil)
    }

    func hover(_ p: NSPoint) {
        guard drag == nil, let i = cellAt(p).0, i != lit else { return }
        onHover?(i)
    }
    // THE DRAG (13.9.2026): a press that travels a few points lifts the icon; its picture follows the mouse, the cell
    // under it lights as the landing place; letting go there hands (from, to) to the owner. No travel: the click, the jump.
    func down(_ p: NSPoint) {
        guard let i = cellAt(p).0 else { return }
        drag = Drag(from: i, start: p)
    }
    func dragged(_ p: NSPoint) {
        guard var d = drag else { return }
        if !d.moved && abs(p.x - d.start.x) + abs(p.y - d.start.y) >= DRAG_START { d.moved = true }
        if d.moved { d.over = cellAt(p).0; d.at = p }
        drag = d
        if d.moved { redraw() }
    }
    func up(_ p: NSPoint) {
        guard let d = drag else { return }
        drag = nil
        if !d.moved { onPick?(d.from) } else { onDrop?(d.from, cellAt(p).0 ?? d.from) }
    }

    func draw(_ v: GridView) {
        let size = v.bounds.size
        NSColor(white: 0.08, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 22, yRadius: 22).fill()
        let dragging = drag?.moved == true
        let litNow = dragging ? (drag!.over ?? drag!.from) : lit
        let lifted = dragging ? drag!.from : -1
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byTruncatingTail
        for (i, it) in items.enumerated() {
            let r = i / cols, c = i % cols
            let x = PAD + CGFloat(c) * CELL, y = PAD + CGFloat(r) * CELL
            if i == litNow {
                NSColor(white: 1, alpha: 0.22).setFill()
                NSBezierPath(roundedRect: NSRect(x: x + 4, y: y + 4, width: CELL - 8, height: CELL - 8), xRadius: 16, yRadius: 16).fill()
            }
            let s = i == litNow ? ICON * 1.22 : ICON
            it.icon.draw(in: NSRect(x: x + (CELL - s) / 2, y: y + 12 - (s - ICON) / 2, width: s, height: s), from: .zero, operation: .sourceOver,
                         fraction: i == lifted ? 0.25 : (i == litNow ? 1 : 0.85), respectFlipped: true, hints: nil)
            (it.name as NSString).draw(with: NSRect(x: x + 4, y: y + ICON + 16, width: CELL - 8, height: 16), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                       attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 1, alpha: i == litNow ? 1 : 0.65), .paragraphStyle: para])
            if it.running {
                NSColor(white: 1, alpha: 0.8).setFill()
                NSBezierPath(ovalIn: NSRect(x: x + CELL / 2 - 2.2, y: y + CELL - 6 - 2.2, width: 4.4, height: 4.4)).fill()
            }
        }
        // the lifted icon's picture under the mouse, on the square the mouse is over
        if dragging, let d = drag, let w = v.window, w.frame.contains(d.at), d.from < items.count {
            let lx = d.at.x - w.frame.minX, ly = w.frame.maxY - d.at.y
            items[d.from].icon.draw(in: NSRect(x: lx - ICON / 2, y: ly - ICON / 2, width: ICON, height: ICON), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
