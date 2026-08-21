import XCTest
@testable import DarkbloomCore

final class ActivityHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_787_313_600)

    private func earning(
        _ id: Int64,
        microUSD: Int64 = 100,
        hoursAgo: Double = 0,
        model: String = "model"
    ) -> CoordinatorAPI.Earning {
        CoordinatorAPI.Earning(
            id: id,
            providerID: "provider",
            providerKey: "key",
            model: model,
            amountMicroUSD: microUSD,
            promptTokens: 1,
            completionTokens: 1,
            createdAt: now.addingTimeInterval(-hoursAgo * 3_600)
        )
    }

    func testIngestDeduplicatesOverlappingPollsAndAggregatesBothValues() {
        var history = ActivityHistory()
        history.ingest(
            accountID: "account",
            entries: [earning(1), earning(2, microUSD: 250)],
            historyLimit: 1_000,
            now: now,
            calendar: calendar
        )
        history.ingest(
            accountID: "account",
            entries: [earning(1), earning(2, microUSD: 250), earning(3, microUSD: 50)],
            historyLimit: 1_000,
            now: now.addingTimeInterval(30),
            calendar: calendar
        )

        let latest = history.hourlyBuckets(now: now, calendar: calendar).last
        XCTAssertEqual(latest?.jobs, 3)
        XCTAssertEqual(latest?.microUSD, 400)
        XCTAssertEqual(latest?.earningsByCategory["model"]?.microUSD, 400)
    }

    func testBaseRewardsAreEarningsButNotThroughput() {
        var history = ActivityHistory()
        history.ingest(
            accountID: "account",
            entries: [
                earning(1, microUSD: 400, model: "base_reward"),
                earning(2, microUSD: 100, model: "gemma-4-26b-qat-4bit"),
                earning(3, microUSD: 200, model: "qwen3.6-35b-a3b-vl-mtp-mxfp8"),
            ],
            historyLimit: 1_000,
            now: now,
            calendar: calendar
        )

        let latest = history.hourlyBuckets(now: now, calendar: calendar).last
        XCTAssertEqual(latest?.jobs, 2)
        XCTAssertEqual(latest?.microUSD, 700)
        XCTAssertEqual(latest?.earningsByCategory["base_reward"]?.microUSD, 400)
        XCTAssertEqual(latest?.earningsByCategory["gemma-4-26b-qat-4bit"]?.microUSD, 100)
        XCTAssertEqual(latest?.earningsByCategory["qwen3.6-35b-a3b-vl-mtp-mxfp8"]?.microUSD, 200)
    }

    func testHistoryPersistsDeduplicationState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("activity.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        var history = ActivityHistory()
        history.ingest(
            accountID: "account",
            entries: [earning(1)],
            historyLimit: 1_000,
            now: now,
            calendar: calendar
        )
        try ActivityHistoryStore.save(history, to: url)

        var restored = ActivityHistoryStore.load(from: url)
        let added = restored.ingest(
            accountID: "account",
            entries: [earning(1)],
            historyLimit: 1_000,
            now: now.addingTimeInterval(30),
            calendar: calendar
        )
        XCTAssertEqual(added, 0)
        XCTAssertEqual(restored.hourlyBuckets(now: now, calendar: calendar).last?.jobs, 1)
    }

    func testSwitchingAccountsClearsExistingTotals() {
        var history = ActivityHistory()
        history.ingest(
            accountID: "first",
            entries: [earning(1)],
            historyLimit: 1_000,
            now: now,
            calendar: calendar
        )
        history.ingest(
            accountID: "second",
            entries: [earning(2, microUSD: 500)],
            historyLimit: 1_000,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(history.accountID, "second")
        XCTAssertEqual(history.hourlyBuckets(now: now, calendar: calendar).last?.jobs, 1)
        XCTAssertEqual(history.hourlyBuckets(now: now, calendar: calendar).last?.microUSD, 500)
    }

    func testCappedPollMarksCoverageGapWhenItNoLongerOverlaps() {
        var history = ActivityHistory()
        history.ingest(
            accountID: "account",
            entries: [earning(1, hoursAgo: 0.5)],
            historyLimit: 1,
            now: now,
            calendar: calendar
        )
        let nextPoll = now.addingTimeInterval(4 * 3_600)
        let newerEntry = CoordinatorAPI.Earning(
            id: 2,
            providerID: "provider",
            providerKey: "key",
            model: "model",
            amountMicroUSD: 100,
            promptTokens: 1,
            completionTokens: 1,
            createdAt: nextPoll.addingTimeInterval(-600)
        )
        history.ingest(
            accountID: "account",
            entries: [newerEntry],
            historyLimit: 1,
            now: nextPoll,
            calendar: calendar
        )

        XCTAssertEqual(history.coverageGaps.count, 1)
        XCTAssertFalse(history.hasCompleteCoverage(forHours: 24, now: nextPoll, calendar: calendar))
    }

    func testUncappedPollHasCompleteCoverage() {
        var history = ActivityHistory()
        history.ingest(
            accountID: "account",
            entries: [],
            historyLimit: 1_000,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(history.hasCompleteCoverage(forHours: 24, now: now, calendar: calendar))
        XCTAssertTrue(history.hasCompleteCoverage(
            forHours: ActivityHistory.retentionHours,
            now: now,
            calendar: calendar
        ))
    }

    func testTotalCountRecognizesAFullResponseAtTheNominalLimit() {
        var history = ActivityHistory()
        history.ingest(
            accountID: "account",
            entries: [earning(1)],
            historyLimit: 1,
            totalCount: 1,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(history.hasCompleteCoverage(forHours: 24, now: now, calendar: calendar))
    }
}
