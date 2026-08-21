import XCTest
@testable import DarkbloomMenuSupport

final class TooltipPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    private let tooltip = CGSize(width: 140, height: 80)

    func testPrefersRightAndBelowCursor() {
        XCTAssertEqual(
            TooltipPlacement.origin(
                cursor: CGPoint(x: 400, y: 400),
                tooltipSize: tooltip,
                visibleFrame: screen
            ),
            CGPoint(x: 410, y: 310)
        )
    }

    func testFlipsLeftAtRightScreenEdge() {
        XCTAssertEqual(
            TooltipPlacement.origin(
                cursor: CGPoint(x: 980, y: 400),
                tooltipSize: tooltip,
                visibleFrame: screen
            ).x,
            830
        )
    }

    func testFlipsAboveAtBottomScreenEdge() {
        XCTAssertEqual(
            TooltipPlacement.origin(
                cursor: CGPoint(x: 400, y: 20),
                tooltipSize: tooltip,
                visibleFrame: screen
            ).y,
            30
        )
    }

    func testClampsPlacementToVisibleScreen() {
        let origin = TooltipPlacement.origin(
            cursor: CGPoint(x: 0, y: 800),
            tooltipSize: tooltip,
            visibleFrame: screen
        )

        XCTAssertGreaterThanOrEqual(origin.x, 6)
        XCTAssertLessThanOrEqual(origin.y + tooltip.height, 794)
    }

    func testPinsTooltipLargerThanScreenToPaddedOrigin() {
        XCTAssertEqual(
            TooltipPlacement.origin(
                cursor: CGPoint(x: 500, y: 400),
                tooltipSize: CGSize(width: 1_200, height: 900),
                visibleFrame: screen
            ),
            CGPoint(x: 6, y: 6)
        )
    }
}
