import XCTest
@testable import DarkbloomCore

final class RunRateProjectionTests: XCTestCase {
    func testEarlyProjectionStaysCloserToRecentCompletedHours() {
        let projected = RunRateProjection.projectedTotal(
            completedTotals: [100, 100, 100],
            currentTotal: 20,
            elapsedFraction: 0.1
        )

        XCTAssertGreaterThan(projected, 100)
        XCTAssertLessThan(projected, 130)
    }

    func testCurrentMeasurementGainsConfidenceLaterInHour() {
        let early = RunRateProjection.projectedTotal(
            completedTotals: [100, 100, 100],
            currentTotal: 20,
            elapsedFraction: 0.1
        )
        let late = RunRateProjection.projectedTotal(
            completedTotals: [100, 100, 100],
            currentTotal: 160,
            elapsedFraction: 0.8
        )

        XCTAssertLessThan(abs(200 - late), abs(200 - early))
    }

    func testProjectionConvergesToActualAtHourBoundary() {
        let projected = RunRateProjection.projectedTotal(
            completedTotals: [100, 120, 90],
            currentTotal: 180,
            elapsedFraction: 1
        )

        XCTAssertEqual(projected, 180, accuracy: 0.0001)
    }

    func testProjectionNeverFallsBelowAlreadyObservedTotal() {
        let projected = RunRateProjection.projectedTotal(
            completedTotals: [10, 10, 10],
            currentTotal: 100,
            elapsedFraction: 0.1
        )

        XCTAssertGreaterThanOrEqual(projected, 100)
    }

    func testNoHistoryDoesNotInventProjection() {
        XCTAssertEqual(
            RunRateProjection.projectedTotal(
                completedTotals: [],
                currentTotal: 12,
                elapsedFraction: 0.1
            ),
            12
        )
    }
}
