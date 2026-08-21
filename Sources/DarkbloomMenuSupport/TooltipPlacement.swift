import CoreGraphics

public enum TooltipPlacement {
    public static func origin(
        cursor: CGPoint,
        tooltipSize: CGSize,
        visibleFrame: CGRect,
        offset: CGFloat = 10,
        screenPadding: CGFloat = 6
    ) -> CGPoint {
        let preferredX = cursor.x + offset
        let x: CGFloat
        if preferredX + tooltipSize.width <= visibleFrame.maxX - screenPadding {
            x = preferredX
        } else {
            x = cursor.x - offset - tooltipSize.width
        }

        let preferredY = cursor.y - offset - tooltipSize.height
        let y: CGFloat
        if preferredY >= visibleFrame.minY + screenPadding {
            y = preferredY
        } else {
            y = cursor.y + offset
        }

        let minimumX = visibleFrame.minX + screenPadding
        let minimumY = visibleFrame.minY + screenPadding
        let maximumX = max(minimumX, visibleFrame.maxX - screenPadding - tooltipSize.width)
        let maximumY = max(minimumY, visibleFrame.maxY - screenPadding - tooltipSize.height)

        return CGPoint(
            x: min(max(x, minimumX), maximumX),
            y: min(max(y, minimumY), maximumY)
        )
    }
}
