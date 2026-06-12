import Foundation

/// Mirror of the provider's ~/.darkbloom/daemon-state.json (schema 1).
/// Written by the provider every heartbeat; considered stale after 90s.
public struct DaemonState: Decodable {
    public struct Trust: Decodable {
        public var trustLevel: String
        public var status: String
        public var reason: String
        public var receivedAt: Double

        enum CodingKeys: String, CodingKey {
            case trustLevel = "trust_level"
            case status, reason
            case receivedAt = "received_at"
        }
    }

    public struct Stats: Decodable {
        public var requestsServed: UInt64
        public var tokensGenerated: UInt64

        enum CodingKeys: String, CodingKey {
            case requestsServed = "requests_served"
            case tokensGenerated = "tokens_generated"
        }
    }

    public struct Capacity: Decodable {
        public var totalMemoryGb: Double
        public var gpuMemoryActiveGb: Double

        enum CodingKeys: String, CodingKey {
            case totalMemoryGb = "total_memory_gb"
            case gpuMemoryActiveGb = "gpu_memory_active_gb"
        }
    }

    public var pid: Int32
    public var version: String
    public var writtenAt: Double
    public var startedAt: Double
    public var trust: Trust?
    public var currentModel: String?
    public var warmModels: [String]?
    public var inferenceActive: Bool?
    public var stats: Stats?
    public var capacity: Capacity?

    enum CodingKeys: String, CodingKey {
        case pid, version, trust, stats, capacity
        case writtenAt = "written_at"
        case startedAt = "started_at"
        case currentModel = "current_model"
        case warmModels = "warm_models"
        case inferenceActive = "inference_active"
    }

    /// The provider rewrites the state file on every heartbeat; if it hasn't
    /// been touched in 90s the process is gone or wedged (same rule the CLI uses).
    public static let stalenessThreshold: TimeInterval = 90

    public func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince1970 - writtenAt < Self.stalenessThreshold
    }

    /// Liveness probe identical to the CLI's: signal 0 to the recorded pid.
    public var processAlive: Bool {
        kill(pid, 0) == 0
    }

    public func uptime(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince1970 - startedAt
    }

    public static func decode(_ data: Data) throws -> DaemonState {
        try JSONDecoder().decode(DaemonState.self, from: data)
    }
}

public enum DarkbloomPaths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser
    public static let stateDir = home.appendingPathComponent(".darkbloom")
    public static let daemonState = stateDir.appendingPathComponent("daemon-state.json")
    public static let authToken = stateDir.appendingPathComponent("auth_token")
    public static let cli = stateDir.appendingPathComponent("bin/darkbloom")
    public static let launchAgentPlist = home
        .appendingPathComponent("Library/LaunchAgents/io.darkbloom.provider.plist")

    public static func readDaemonState() -> DaemonState? {
        guard let data = try? Data(contentsOf: daemonState) else { return nil }
        return try? DaemonState.decode(data)
    }

    public static func readAuthToken() -> String? {
        guard let raw = try? String(contentsOf: authToken, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
