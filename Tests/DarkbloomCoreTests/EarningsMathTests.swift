import XCTest
@testable import DarkbloomCore

final class EarningsMathTests: XCTestCase {
    // Mid-hour, so "minutes ago" fixtures stay inside the current bucket.
    let now = Date(timeIntervalSince1970: 1_781_280_000 + 1_800)

    func earning(_ id: Int64, microUSD: Int64, agoSeconds: TimeInterval,
                 providerID: String = "p1", providerKey: String = "k1") -> CoordinatorAPI.Earning {
        CoordinatorAPI.Earning(
            id: id, providerID: providerID, providerKey: providerKey, model: "gpt-oss-20b",
            amountMicroUSD: microUSD, promptTokens: 10, completionTokens: 20,
            createdAt: now.addingTimeInterval(-agoSeconds))
    }

    func testWindows() {
        let entries = [
            earning(1, microUSD: 100, agoSeconds: 3_600),          // in 24h and 7d
            earning(2, microUSD: 200, agoSeconds: 2 * 86_400),     // in 7d only
            earning(3, microUSD: 400, agoSeconds: 8 * 86_400),     // outside both
        ]
        let w = EarningsMath.windows(entries, now: now)
        XCTAssertEqual(w.last24hMicroUSD, 100)
        XCTAssertEqual(w.last7dMicroUSD, 300)
        XCTAssertEqual(w.last24hJobs, 1)
    }

    func testWindowsEmpty() {
        XCTAssertEqual(EarningsMath.windows([], now: now), EarningsWindows())
    }

    func testHourlyBucketsShape() {
        let buckets = EarningsMath.hourlyBuckets([], now: now)
        XCTAssertEqual(buckets.count, 24)
        // Sorted oldest → newest, ending at the hour containing `now`.
        XCTAssertEqual(buckets, buckets.sorted { $0.hour < $1.hour })
        let lastHour = Calendar.current.dateInterval(of: .hour, for: now)!.start
        XCTAssertEqual(buckets.last?.hour, lastHour)
        XCTAssertTrue(buckets.allSatisfy { $0.jobs == 0 && $0.microUSD == 0 })
    }

    func testHourlyBucketsCounts() {
        let entries = [
            earning(1, microUSD: 100, agoSeconds: 60),            // current hour
            earning(2, microUSD: 50, agoSeconds: 120),            // current hour
            earning(3, microUSD: 25, agoSeconds: 5 * 3_600),      // 5 hours ago
            earning(4, microUSD: 999, agoSeconds: 25 * 3_600),    // outside window
        ]
        let buckets = EarningsMath.hourlyBuckets(entries, now: now)
        XCTAssertEqual(buckets.map(\.jobs).reduce(0, +), 3)
        XCTAssertEqual(buckets.map(\.microUSD).reduce(0, +), 175)
        XCTAssertEqual(buckets.last?.jobs, 2)
        XCTAssertEqual(buckets.last?.microUSD, 150)
    }
}

final class FleetTests: XCTestCase {
    func provider(_ id: String, serial: String, chip: String = "Apple M5 Max",
                  models: [String]? = ["gpt-oss-20b"]) -> CoordinatorAPI.AttestedProvider {
        CoordinatorAPI.AttestedProvider(
            providerID: id, chipName: chip, hardwareModel: "Mac17,6", serialNumber: serial,
            trustLevel: "hardware", status: "serving", memoryGB: 128, gpuCores: 40,
            models: models, mdmVerified: true)
    }

    func earning(providerID: String) -> CoordinatorAPI.Earning {
        CoordinatorAPI.Earning(
            id: 1, providerID: providerID, providerKey: "k", model: "m",
            amountMicroUSD: 1, promptTokens: 1, completionTokens: 1, createdAt: Date())
    }

    func testThisMacIncludedBySerialEvenWithoutEarnings() {
        let fleet = Fleet.machines(
            connected: [provider("p-new", serial: "LOCAL")],
            earnings: [],
            localSerial: "LOCAL")
        XCTAssertEqual(fleet.count, 1)
        XCTAssertTrue(fleet[0].isThisMac)
    }

    func testOtherMachinesRequireEarningsMatch() {
        let fleet = Fleet.machines(
            connected: [
                provider("p-mine", serial: "OTHER1"),
                provider("p-stranger", serial: "OTHER2"),
            ],
            earnings: [earning(providerID: "p-mine")],
            localSerial: "LOCAL")
        XCTAssertEqual(fleet.map(\.id), ["p-mine"])
        XCTAssertFalse(fleet[0].isThisMac)
    }

    func testThisMacSortsFirstAndSerialsDedupe() {
        let fleet = Fleet.machines(
            connected: [
                provider("p-other", serial: "OTHER", chip: "Apple M2 Max"),
                provider("p-local", serial: "LOCAL"),
                provider("p-local-dup", serial: "LOCAL"),
            ],
            earnings: [earning(providerID: "p-other"), earning(providerID: "p-local-dup")],
            localSerial: "LOCAL")
        XCTAssertEqual(fleet.count, 2)
        XCTAssertTrue(fleet[0].isThisMac)
        XCTAssertEqual(fleet[1].displayName, "M2 Max")
    }

    func testDisplayNameStripsApplePrefix() {
        let fleet = Fleet.machines(
            connected: [provider("p1", serial: "LOCAL")], earnings: [], localSerial: "LOCAL")
        XCTAssertEqual(fleet[0].displayName, "M5 Max")
    }
}

final class FmtTests: XCTestCase {
    func testUSDScalesPrecision() {
        XCTAssertEqual(Fmt.usd(21_949), "$0.0219")
        XCTAssertEqual(Fmt.usd(1_500_000), "$1.500")
        XCTAssertEqual(Fmt.usd(123_456_789), "$123.46")
        XCTAssertEqual(Fmt.usd(0), "$0.0000")
    }

    func testUptime() {
        XCTAssertEqual(Fmt.uptime(59), "0m")
        XCTAssertEqual(Fmt.uptime(35 * 60), "35m")
        XCTAssertEqual(Fmt.uptime(2 * 3_600 + 55 * 60), "2h 55m")
        XCTAssertEqual(Fmt.uptime(3 * 86_400 + 4 * 3_600), "3d 4h")
    }
}
