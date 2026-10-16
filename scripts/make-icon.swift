// Draws the Finder Menu app icon and writes Resources/AppIcon.icns plus docs/icon.png for the README.
// Usage: swift scripts/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func withShadow(y: CGFloat, blur: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowOffset = NSSize(width: 0, height: -y)
    s.shadowBlurRadius = blur
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

// All coordinates are on a 1024×1024 canvas with the origin at the top-left.
func drawIcon() {
    // Body: Apple's macOS icon grid (824pt rounded square, 100pt margin).
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    withShadow(y: 10, blur: 22, alpha: 0.28) { color(0x2F7CF6).setFill(); body.fill() }
    NSGradient(starting: color(0x5BC0FF), ending: color(0x1D63F0))!.draw(in: body, angle: 90)
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: 100, y: 100, width: 824, height: 460), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // A right-click menu card with four rows, the second one highlighted.
    let card = NSRect(x: 236, y: 232, width: 500, height: 560)
    withShadow(y: 18, blur: 40, alpha: 0.30) {
        NSColor.white.setFill()
        NSBezierPath(roundedRect: card, xRadius: 58, yRadius: 58).fill()
    }
    let rowH: CGFloat = 104
    for i in 0..<4 {
        let row = NSRect(x: card.minX + 28, y: card.minY + 44 + CGFloat(i) * (rowH + 12), width: card.width - 56, height: rowH)
        let highlighted = i == 1
        if highlighted {
            color(0x0A84FF).setFill()
            NSBezierPath(roundedRect: row, xRadius: 26, yRadius: 26).fill()
        }
        (highlighted ? NSColor.white : color(0xB8BCC6)).setFill()
        NSBezierPath(roundedRect: NSRect(x: row.minX + 26, y: row.midY - 24, width: 48, height: 48), xRadius: 12, yRadius: 12).fill()
        (highlighted ? NSColor.white : color(0xD5D8DF)).setFill()
        let barW: CGFloat = [250, 200, 210, 260][i]
        NSBezierPath(roundedRect: NSRect(x: row.minX + 100, y: row.midY - 13, width: barW, height: 26), xRadius: 13, yRadius: 13).fill()
    }

    // Mouse pointer resting on the highlighted row.
    let tip = NSPoint(x: 600, y: 410), k: CGFloat = 250
    let shape: [(CGFloat, CGFloat)] = [(0, 0), (0, 0.80), (0.20, 0.62), (0.33, 0.92), (0.45, 0.87), (0.32, 0.58), (0.58, 0.58)]
    let arrow = NSBezierPath()
    for (i, p) in shape.enumerated() {
        let pt = NSPoint(x: tip.x + p.0 * k, y: tip.y + p.1 * k)
        i == 0 ? arrow.move(to: pt) : arrow.line(to: pt)
    }
    arrow.close()
    arrow.lineJoinStyle = .round
    arrow.lineWidth = 22
    withShadow(y: 8, blur: 18, alpha: 0.35) { NSColor.white.setStroke(); arrow.stroke() }
    color(0x1C1C1E).setFill()
    arrow.fill()
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let s = CGFloat(px) / 1024
    ctx.cgContext.translateBy(x: 0, y: CGFloat(px))
    ctx.cgContext.scaleBy(x: s, y: -s)   // top-left origin
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ px: Int, cache: inout [Int: Data]) -> Data {
    if let data = cache[px] { return data }
    let data = render(px).representation(using: .png, properties: [:])!
    cache[px] = data
    return data
}

// Drawing inputs are fixed for this run; retain encoded bytes, not bitmap or graphics-context state.
var pngByPixelSize: [Int: Data] = [:]
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
try! png(512, cache: &pngByPixelSize).write(to: root.appendingPathComponent("docs/icon.png"))
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try! png(pt, cache: &pngByPixelSize).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try! png(pt * 2, cache: &pngByPixelSize).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
