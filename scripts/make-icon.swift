// Renders AppIcon.icns: the Darkbloom logomark (traced from darkbloom.dev's
// logo-symbol SVG) in green on a dark rounded-rect. Run via scripts/build-app.sh.
// Standalone script, so the polygon data is duplicated from DarkbloomLogo.swift.
import AppKit

let logoViewBox = CGSize(width: 221.31, height: 252.91)
let logoPolygons: [[CGPoint]] = [
    [
        CGPoint(x: 126.46, y: 126.46), CGPoint(x: 94.85, y: 126.46),
        CGPoint(x: 94.85, y: 189.67), CGPoint(x: 63.22, y: 189.67),
        CGPoint(x: 63.22, y: 126.44), CGPoint(x: 63.22, y: 0),
        CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 126.44),
        CGPoint(x: 0, y: 189.67), CGPoint(x: 0, y: 252.91),
        CGPoint(x: 63.22, y: 252.91), CGPoint(x: 94.85, y: 252.91),
        CGPoint(x: 126.46, y: 252.91), CGPoint(x: 126.46, y: 252.89),
        CGPoint(x: 189.69, y: 252.89), CGPoint(x: 189.69, y: 189.67),
        CGPoint(x: 126.46, y: 189.67),
    ],
    [
        CGPoint(x: 221.31, y: 0), CGPoint(x: 189.70, y: 0),
        CGPoint(x: 189.70, y: 63.22), CGPoint(x: 221.31, y: 63.22),
    ],
    [
        CGPoint(x: 158.08, y: 0), CGPoint(x: 126.46, y: 0),
        CGPoint(x: 96.13, y: 0), CGPoint(x: 96.13, y: 31.62),
        CGPoint(x: 126.46, y: 31.62), CGPoint(x: 126.46, y: 126.44),
        CGPoint(x: 158.08, y: 126.44), CGPoint(x: 189.69, y: 126.44),
        CGPoint(x: 189.69, y: 63.20), CGPoint(x: 158.08, y: 63.20),
    ],
]

func logoPath(fitting rect: CGRect) -> CGPath {
    let scale = min(rect.width / logoViewBox.width, rect.height / logoViewBox.height)
    let drawn = CGSize(width: logoViewBox.width * scale, height: logoViewBox.height * scale)
    var transform = CGAffineTransform(
        translationX: rect.minX + (rect.width - drawn.width) / 2,
        y: rect.minY + (rect.height - drawn.height) / 2
    ).scaledBy(x: scale, y: scale)
    let path = CGMutablePath()
    for poly in logoPolygons {
        path.addLines(between: poly, transform: transform)
        path.closeSubpath()
    }
    return path
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> NSImage {
    let s = CGFloat(px)
    return NSImage(size: NSSize(width: s, height: s), flipped: true) { rect in
        let inset = rect.insetBy(dx: s * 0.05, dy: s * 0.05)
        let bg = NSBezierPath(roundedRect: inset, xRadius: s * 0.2, yRadius: s * 0.2)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.16, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.12, alpha: 1),
        ])!.draw(in: bg, angle: -90)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        ctx.addPath(logoPath(fitting: rect.insetBy(dx: s * 0.26, dy: s * 0.26)))
        ctx.setFillColor(NSColor.systemGreen.cgColor)
        ctx.fillPath()
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
