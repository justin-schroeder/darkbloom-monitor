import AppKit

/// The Darkbloom logomark, traced from the `logo-symbol` SVG on
/// darkbloom.dev (viewBox 0 0 221 253, three `currentColor` polygons).
/// Coordinates are y-down like the SVG; draw into a flipped context.
public enum DarkbloomLogo {
    public static let viewBox = CGSize(width: 221.31, height: 252.91)

    public static let polygons: [[CGPoint]] = [
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

    /// Path scaled to fit `rect`, preserving aspect ratio and centered.
    public static func path(fitting rect: CGRect) -> CGPath {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let drawn = CGSize(width: viewBox.width * scale, height: viewBox.height * scale)
        var transform = CGAffineTransform(
            translationX: rect.minX + (rect.width - drawn.width) / 2,
            y: rect.minY + (rect.height - drawn.height) / 2
        ).scaledBy(x: scale, y: scale)

        let path = CGMutablePath()
        for poly in polygons {
            path.addLines(between: poly, transform: transform)
            path.closeSubpath()
        }
        return path
    }
}
