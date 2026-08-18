import XCTest
@testable import DarkbloomCore

final class ThermalStateTests: XCTestCase {
    func testMapsProcessInfoStates() {
        XCTAssertEqual(ThermalState(ProcessInfo.ThermalState.nominal), .nominal)
        XCTAssertEqual(ThermalState(ProcessInfo.ThermalState.fair), .fair)
        XCTAssertEqual(ThermalState(ProcessInfo.ThermalState.serious), .serious)
        XCTAssertEqual(ThermalState(ProcessInfo.ThermalState.critical), .critical)
    }

    func testParsesDaemonStrings() {
        XCTAssertEqual(ThermalState(daemonString: "nominal"), .nominal)
        XCTAssertEqual(ThermalState(daemonString: "Fair"), .fair)
        XCTAssertEqual(ThermalState(daemonString: " SERIOUS "), .serious)
        XCTAssertEqual(ThermalState(daemonString: "critical"), .critical)
        XCTAssertNil(ThermalState(daemonString: "overheated"))
        XCTAssertNil(ThermalState(daemonString: ""))
    }

    func testSeverityOrdering() {
        XCTAssertLessThan(ThermalState.nominal, .fair)
        XCTAssertLessThan(ThermalState.fair, .serious)
        XCTAssertLessThan(ThermalState.serious, .critical)
        XCTAssertEqual(
            ThermalState.allCases.sorted(),
            [.nominal, .fair, .serious, .critical]
        )
    }

    func testElevation() {
        XCTAssertFalse(ThermalState.nominal.isElevated)
        XCTAssertTrue(ThermalState.fair.isElevated)
        XCTAssertTrue(ThermalState.serious.isElevated)
        XCTAssertTrue(ThermalState.critical.isElevated)
    }

    // Mirrors the coordinator dashboard: fair 0.8x, serious 0.4x,
    // critical zero health with routing blocked.
    func testServingHealthImpact() {
        XCTAssertEqual(ThermalState.nominal.servingHealthMultiplier, 1)
        XCTAssertEqual(ThermalState.fair.servingHealthMultiplier, 0.8)
        XCTAssertEqual(ThermalState.serious.servingHealthMultiplier, 0.4)
        XCTAssertEqual(ThermalState.critical.servingHealthMultiplier, 0)
        XCTAssertFalse(ThermalState.nominal.blocksRouting)
        XCTAssertFalse(ThermalState.serious.blocksRouting)
        XCTAssertTrue(ThermalState.critical.blocksRouting)
    }
}
