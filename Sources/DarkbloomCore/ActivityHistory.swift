import Foundation

/// A durable, account-scoped hourly ledger built from the coordinator's recent
/// per-job response. Polls overlap, so earning IDs are retained for deduplication
/// while hourly totals provide a compact seven-day history.
public struct ActivityHistory: Codable, Equatable {
    public static let retentionHours = 7 * 24

    public private(set) var accountID: String?
    public private(set) var hours: [HourBucket]
    public private(set) var coverageStartedAt: Date?
    public private(set) var coverageGaps: [DateInterval]

    private var recentEarningIDs: Set<Int64>
    private var categorizedEarningIDs: Set<Int64>
    private var lastIngestedAt: Date?

    public init(
        accountID: String? = nil,
        hours: [HourBucket] = [],
        coverageStartedAt: Date? = nil,
        coverageGaps: [DateInterval] = []
    ) {
        self.accountID = accountID
        self.hours = hours
        self.coverageStartedAt = coverageStartedAt
        self.coverageGaps = coverageGaps
        recentEarningIDs = []
        categorizedEarningIDs = []
        lastIngestedAt = nil
    }

    enum CodingKeys: String, CodingKey {
        case accountID, hours, coverageStartedAt, coverageGaps
        case recentEarningIDs, categorizedEarningIDs, lastIngestedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try values.decodeIfPresent(String.self, forKey: .accountID)
        hours = try values.decodeIfPresent([HourBucket].self, forKey: .hours) ?? []
        coverageStartedAt = try values.decodeIfPresent(Date.self, forKey: .coverageStartedAt)
        coverageGaps = try values.decodeIfPresent([DateInterval].self, forKey: .coverageGaps) ?? []
        recentEarningIDs = try values.decodeIfPresent(Set<Int64>.self, forKey: .recentEarningIDs) ?? []
        categorizedEarningIDs = try values.decodeIfPresent(
            Set<Int64>.self,
            forKey: .categorizedEarningIDs
        ) ?? []
        lastIngestedAt = try values.decodeIfPresent(Date.self, forKey: .lastIngestedAt)
    }

    /// Merges a coordinator poll and returns the number of newly recorded jobs.
    /// When more than one poll-window elapsed while the app was offline, the
    /// uncovered interval is retained so the UI doesn't imply false completeness.
    @discardableResult
    public mutating func ingest(
        accountID: String,
        entries: [CoordinatorAPI.Earning],
        historyLimit: Int?,
        totalCount: Int64? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        if self.accountID != nil, self.accountID != accountID {
            self = ActivityHistory()
        }
        self.accountID = accountID

        guard let currentHour = calendar.dateInterval(of: .hour, for: now)?.start,
              let retentionStart = calendar.date(
                byAdding: .hour,
                value: -(Self.retentionHours - 1),
                to: currentHour
              )
        else { return 0 }

        let oldestEntry = entries.map(\.createdAt).min()
        let responseReachedLimit = historyLimit.map { $0 > 0 && entries.count >= $0 } ?? false
        let isCapped = totalCount.map { $0 > Int64(entries.count) } ?? responseReachedLimit

        if coverageStartedAt == nil {
            coverageStartedAt = isCapped ? (oldestEntry ?? now) : retentionStart
        } else if !isCapped {
            coverageStartedAt = min(coverageStartedAt ?? retentionStart, retentionStart)
        }

        if isCapped,
           let lastIngestedAt,
           let oldestEntry,
           oldestEntry > lastIngestedAt {
            coverageGaps.append(DateInterval(start: lastIngestedAt, end: oldestEntry))
        }

        var buckets = Dictionary(hours.map { ($0.hour, $0) }, uniquingKeysWith: { _, latest in latest })
        var knownIDs = recentEarningIDs
        var knownCategoryIDs = categorizedEarningIDs
        let migratingLegacyCategories = categorizedEarningIDs.isEmpty && !recentEarningIDs.isEmpty
        var added = 0
        for entry in entries {
            let isNewEntry = knownIDs.insert(entry.id).inserted
            let needsCategory = knownCategoryIDs.insert(entry.id).inserted
            guard isNewEntry || needsCategory else { continue }
            guard let hour = calendar.dateInterval(of: .hour, for: entry.createdAt)?.start,
                  hour >= retentionStart,
                  hour <= currentHour
            else { continue }
            var bucket = buckets[hour] ?? HourBucket(hour: hour, jobs: 0, microUSD: 0)
            let isRequest = entry.model != "base_reward"
            if isNewEntry {
                if isRequest { bucket.jobs += 1 }
                bucket.microUSD += entry.amountMicroUSD
                added += 1
            } else if !isRequest, migratingLegacyCategories {
                // ActivityHistory written before categorized earnings counted
                // base rewards as requests. Correct the overlapping portion as
                // the current API response supplies its categories.
                bucket.jobs = max(0, bucket.jobs - 1)
            }
            if needsCategory {
                var category = bucket.earningsByCategory[entry.model] ?? EarningCategoryTotal()
                category.entries += 1
                category.microUSD += entry.amountMicroUSD
                bucket.earningsByCategory[entry.model] = category
            }
            buckets[hour] = bucket
        }

        hours = buckets.values
            .filter { $0.hour >= retentionStart && $0.hour <= currentHour }
            .sorted { $0.hour < $1.hour }
        recentEarningIDs.formUnion(entries.map(\.id))
        categorizedEarningIDs.formUnion(entries.map(\.id))
        let responseLimit = min(10_000, max(1_000, historyLimit ?? 1_000))
        let retainedIDCount = responseLimit * 2
        if recentEarningIDs.count > retainedIDCount {
            recentEarningIDs = Set(recentEarningIDs.sorted().suffix(retainedIDCount))
        }
        if categorizedEarningIDs.count > retainedIDCount {
            categorizedEarningIDs = Set(categorizedEarningIDs.sorted().suffix(retainedIDCount))
        }
        lastIngestedAt = now
        coverageGaps = coverageGaps.filter { $0.end >= retentionStart }
        return added
    }

    /// Zero-padded hourly buckets ending at the hour containing `now`.
    public func hourlyBuckets(
        count: Int = 24,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HourBucket] {
        guard count > 0,
              let currentHour = calendar.dateInterval(of: .hour, for: now)?.start
        else { return [] }
        let values = Dictionary(hours.map { ($0.hour, $0) }, uniquingKeysWith: { _, latest in latest })
        return (0..<count).reversed().compactMap { offset in
            guard let hour = calendar.date(byAdding: .hour, value: -offset, to: currentHour) else {
                return nil
            }
            return values[hour] ?? HourBucket(hour: hour, jobs: 0, microUSD: 0)
        }
    }

    public func windows(now: Date = Date(), calendar: Calendar = .current) -> EarningsWindows {
        let day = hourlyBuckets(count: 24, now: now, calendar: calendar)
        let week = hourlyBuckets(count: Self.retentionHours, now: now, calendar: calendar)
        return EarningsWindows(
            last24hMicroUSD: day.reduce(0) { $0 + $1.microUSD },
            last7dMicroUSD: week.reduce(0) { $0 + $1.microUSD },
            last24hJobs: day.reduce(0) { $0 + $1.jobs }
        )
    }

    public func hasCompleteCoverage(
        forHours count: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard count > 0,
              let coverageStartedAt,
              let currentHour = calendar.dateInterval(of: .hour, for: now)?.start,
              let start = calendar.date(byAdding: .hour, value: -(count - 1), to: currentHour),
              coverageStartedAt <= start
        else { return false }
        let interval = DateInterval(start: start, end: now)
        return !coverageGaps.contains { $0.intersects(interval) }
    }
}

public enum ActivityHistoryStore {
    public static func load(from url: URL = DarkbloomPaths.activityHistory) -> ActivityHistory {
        guard let data = try? Data(contentsOf: url) else { return ActivityHistory() }
        return (try? JSONDecoder().decode(ActivityHistory.self, from: data)) ?? ActivityHistory()
    }

    public static func save(_ history: ActivityHistory, to url: URL = DarkbloomPaths.activityHistory) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(history)
        try data.write(to: url, options: .atomic)
    }
}
