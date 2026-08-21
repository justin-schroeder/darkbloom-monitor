import Foundation

public struct EarningsWindows: Equatable {
    public var last24hMicroUSD: Int64
    public var last7dMicroUSD: Int64
    public var last24hJobs: Int

    public init(last24hMicroUSD: Int64 = 0, last7dMicroUSD: Int64 = 0, last24hJobs: Int = 0) {
        self.last24hMicroUSD = last24hMicroUSD
        self.last7dMicroUSD = last7dMicroUSD
        self.last24hJobs = last24hJobs
    }
}

public struct EarningCategoryTotal: Codable, Equatable {
    public var entries: Int
    public var microUSD: Int64

    public init(entries: Int = 0, microUSD: Int64 = 0) {
        self.entries = entries
        self.microUSD = microUSD
    }
}

public struct HourBucket: Codable, Identifiable, Equatable {
    public var hour: Date
    public var jobs: Int
    public var microUSD: Int64
    public var earningsByCategory: [String: EarningCategoryTotal]
    public var id: Date { hour }

    public init(
        hour: Date,
        jobs: Int,
        microUSD: Int64,
        earningsByCategory: [String: EarningCategoryTotal] = [:]
    ) {
        self.hour = hour
        self.jobs = jobs
        self.microUSD = microUSD
        self.earningsByCategory = earningsByCategory
    }

    enum CodingKeys: String, CodingKey {
        case hour, jobs, microUSD, earningsByCategory
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hour = try values.decode(Date.self, forKey: .hour)
        jobs = try values.decode(Int.self, forKey: .jobs)
        microUSD = try values.decode(Int64.self, forKey: .microUSD)
        earningsByCategory = try values.decodeIfPresent(
            [String: EarningCategoryTotal].self,
            forKey: .earningsByCategory
        ) ?? [:]
    }
}

public enum EarningsMath {
    public static func windows(_ entries: [CoordinatorAPI.Earning], now: Date = Date()) -> EarningsWindows {
        let day = now.addingTimeInterval(-86_400)
        let week = now.addingTimeInterval(-7 * 86_400)
        var w = EarningsWindows()
        for e in entries where e.createdAt > week {
            w.last7dMicroUSD += e.amountMicroUSD
            if e.createdAt > day {
                w.last24hMicroUSD += e.amountMicroUSD
                if e.model != "base_reward" { w.last24hJobs += 1 }
            }
        }
        return w
    }

    /// 24 hourly buckets ending at the hour containing `now`, oldest first.
    /// Hours with no jobs are present with zero counts so charts show gaps.
    public static func hourlyBuckets(
        _ entries: [CoordinatorAPI.Earning],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HourBucket] {
        guard let hourStart = calendar.dateInterval(of: .hour, for: now)?.start else { return [] }
        var buckets: [Date: HourBucket] = [:]
        for i in 0..<24 {
            let h = hourStart.addingTimeInterval(Double(-i) * 3_600)
            buckets[h] = HourBucket(hour: h, jobs: 0, microUSD: 0)
        }
        let day = now.addingTimeInterval(-86_400)
        for e in entries where e.createdAt > day {
            guard let h = calendar.dateInterval(of: .hour, for: e.createdAt)?.start,
                  var b = buckets[h] else { continue }
            if e.model != "base_reward" { b.jobs += 1 }
            b.microUSD += e.amountMicroUSD
            var category = b.earningsByCategory[e.model] ?? EarningCategoryTotal()
            category.entries += 1
            category.microUSD += e.amountMicroUSD
            b.earningsByCategory[e.model] = category
            buckets[h] = b
        }
        return buckets.values.sorted { $0.hour < $1.hour }
    }
}

/// A machine of yours that is currently connected to the coordinator.
/// Both provider_id and provider_key rotate across provider restarts, so
/// offline machines can't be enumerated from the public API — only machines
/// we can positively identify right now are listed: this Mac by hardware
/// serial, others by their current provider_id appearing in the account's
/// recent earnings.
public struct FleetMachine: Identifiable, Equatable {
    public var live: CoordinatorAPI.AttestedProvider
    public var isThisMac: Bool

    public var id: String { live.providerID }

    public var displayName: String {
        live.chipName.replacingOccurrences(of: "Apple ", with: "")
    }

    public init(live: CoordinatorAPI.AttestedProvider, isThisMac: Bool) {
        self.live = live
        self.isThisMac = isThisMac
    }
}

extension CoordinatorAPI.AttestedProvider: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.providerID == rhs.providerID && lhs.serialNumber == rhs.serialNumber
    }
}

public enum Fleet {
    public static func machines(
        connected: [CoordinatorAPI.AttestedProvider],
        earnings: [CoordinatorAPI.Earning],
        localSerial: String?
    ) -> [FleetMachine] {
        let recentIDs = Set(earnings.map(\.providerID))
        var seenSerials = Set<String>()
        return connected
            .filter { $0.serialNumber == localSerial || recentIDs.contains($0.providerID) }
            .filter { seenSerials.insert($0.serialNumber).inserted }
            .map { FleetMachine(live: $0, isThisMac: $0.serialNumber == localSerial) }
            .sorted { a, b in
                if a.isThisMac != b.isThisMac { return a.isThisMac }
                return a.displayName < b.displayName
            }
    }
}
