// Draws the installer window background: 660 x 400 points, saved at 2x (1320 x 800 px, 144 dpi).
// Usage: swift scripts/make-dmg-background.swift <output.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
let w = 660.0, h = 400.0, scale = 2.0

func hex(_ v: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)   // points, so Finder shows it at 660 x 400

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Warm surface, matching the app's palette.
NSGradient(colors: [hex(0xF8F5F2), hex(0xEFE9E3)])!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerX: CGFloat, topY: CGFloat) {
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: para])
    let sz = a.size()
    a.draw(at: NSPoint(x: centerX - sz.width / 2, y: h - topY - sz.height))
}
text("Drag Cap to Applications", size: 26, weight: .bold, color: hex(0x1E1A18), centerX: w / 2, topY: 38)
text("Then open it from your Applications folder.", size: 14, weight: .regular, color: hex(0x6F645D), centerX: w / 2, topY: 76)

// Arrow between the two icons (icon centres are at x = 165 and 495, y = 190 from the top).
let y = h - 190.0
ctx.setStrokeColor(hex(0xC4643F).cgColor)
ctx.setLineWidth(4)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 262, y: y))
ctx.addLine(to: CGPoint(x: 398, y: y))
ctx.strokePath()
ctx.move(to: CGPoint(x: 380, y: y + 15))
ctx.addLine(to: CGPoint(x: 400, y: y))
ctx.addLine(to: CGPoint(x: 380, y: y - 15))
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
