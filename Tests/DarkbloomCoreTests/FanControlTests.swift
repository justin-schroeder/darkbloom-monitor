import XCTest
@testable import DarkbloomCore

final class FanControlTests: XCTestCase {
    func testManualControlDeniedStatusReadsAsAutomaticFallback() {
        XCTAssertEqual(
            FanControlStatus.unavailable("manual fan control denied").displayText,
            "Automatic - manual fan control unavailable"
        )
    }
}
