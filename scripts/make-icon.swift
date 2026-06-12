// Renders AppIcon.icns: a dark rounded-rect with a green leaf, in the spirit
// of the Darkbloom brand. Run via scripts/build-app.sh.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> NSImage {
    let s = CGFloat(px)
    return NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
        let inset = rect.insetBy(dx: s * 0.05, dy: s * 0.05)
        let bg = NSBezierPath(roundedRect: inset, xRadius: s * 0.2, yRadius: s * 0.2)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.12, alpha: 1),
            NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.16, alpha: 1),
        ])!.draw(in: bg, angle: -90)

        let config = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .medium)
        guard let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return true }
        let leafRect = NSRect(
            x: (s - leaf.size.width) / 2, y: (s - leaf.size.height) / 2,
            width: leaf.size.width, height: leaf.size.height)
        leaf.draw(in: leafRect)
        NSGraphicsContext.current?.cgContext.setBlendMode(.sourceAtop)
        NSColor.systemGreen.setFill()
        leafRect.fill()
        return true
    }
}

for px in sizes {
    let img = render(px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: iconset.appendingPathComponent("icon_\(px)x\(px).png"))
    if px <= 512 {
        let img2x = render(px * 2)
        if let t = img2x.tiffRepresentation, let r = NSBitmapImageRep(data: t),
           let p = r.representation(using: .png, properties: [:]) {
            try! p.write(to: iconset.appendingPathComponent("icon_\(px)x\(px)@2x.png"))
        }
    }
}
print("iconset written to \(iconset.path)")
