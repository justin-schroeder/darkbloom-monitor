import XCTest
@testable import DarkbloomCore

final class FanControlTests: XCTestCase {
    func testManualControlDeniedStatusReadsAsAutomaticFallback() {
        XCTAssertEqual(
            FanControlStatus.unavailable("manual fan control denied").displayText,
            "Automatic - manual fan control unavailable"
        )
    }

    func testExternalFanControllerStatusReadsAsPaused() {
        XCTAssertEqual(
            FanControlStatus.unavailable("external fan controller active").displayText,
            "Paused - another fan controller is running"
        )
    }

    func testUnconfirmedFanTargetStatusDoesNotClaimCooling() {
        XCTAssertEqual(
            FanControlStatus.unavailable("fan target not confirmed").displayText,
            "Cooling not confirmed"
        )
    }
}
