// The icon, drawn: what the app is, the square of app tiles with one lit on its plate, and the clock's plate under it;
// the version under all (version-visible.md). Writes icon_1024.png; build.sh makes the .icns from it.
import AppKit
let S: CGFloat = 1024
let version = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "1"
let img = NSImage(size: NSSize(width: S, height: S)); img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 180, cornerHeight: 180, transform: nil))
ctx.setFillColor(NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.06, alpha: 1).cgColor); ctx.fillPath()
// the square: 3 x 3 tiles of different colours, the middle-left one lit
let colours: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple, .systemRed, .systemTeal, .systemYellow, .systemPink, .systemIndigo]
let cell: CGFloat = 170, x0: CGFloat = 257, y0: CGFloat = 330
ctx.addPath(CGPath(roundedRect: CGRect(x: x0 - 22, y: y0 - 22, width: cell * 3 + 44, height: cell * 3 + 44), cornerWidth: 40, cornerHeight: 40, transform: nil))
ctx.setFillColor(NSColor(calibratedWhite: 0.16, alpha: 1).cgColor); ctx.fillPath()
for i in 0..<9 {
    let r = CGFloat(2 - i / 3), c = CGFloat(i % 3)
    let cellRect = CGRect(x: x0 + c * cell, y: y0 + r * cell, width: cell, height: cell)
    if i == 3 {
        ctx.addPath(CGPath(roundedRect: cellRect.insetBy(dx: 8, dy: 8), cornerWidth: 30, cornerHeight: 30, transform: nil))
        ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.28).cgColor); ctx.fillPath()
    }
    let inset: CGFloat = i == 3 ? 26 : 38
    ctx.addPath(CGPath(roundedRect: cellRect.insetBy(dx: inset, dy: inset), cornerWidth: 24, cornerHeight: 24, transform: nil))
    ctx.setFillColor(colours[i].cgColor); ctx.fillPath()
}
// the clock's plate
ctx.addPath(CGPath(roundedRect: CGRect(x: 412, y: 190, width: 330, height: 76), cornerWidth: 20, cornerHeight: 20, transform: nil))
ctx.setFillColor(NSColor(calibratedWhite: 0.25, alpha: 1).cgColor); ctx.fillPath()
("09:41" as NSString).draw(at: NSPoint(x: 470, y: 196), withAttributes: [.font: NSFont(name: "Menlo", size: 54)!, .foregroundColor: NSColor.white])
("v" + version as NSString).draw(at: NSPoint(x: 170, y: 150), withAttributes: [.font: NSFont.systemFont(ofSize: 92, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1)])
img.unlockFocus()
try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
