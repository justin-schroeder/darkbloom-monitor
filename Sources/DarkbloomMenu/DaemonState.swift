import Foundation

/// Mirror of the provider's ~/.darkbloom/daemon-state.json (schema 1).
/// Written by the provider every heartbeat; considered stale after 90s.
struct DaemonState: Decodable {
    struct Trust: Decodable {
        var trustLevel: String
        var status: String
        var reason: String
        var receivedAt: Double

        enum CodingKeys: String, CodingKey {
            case trustLevel = "trust_level"
            case status, reason
            case receivedAt = "received_at"
        }
    }

    struct Stats: Decodable {
        var requestsServed: UInt64
        var tokensGenerated: UInt64

        enum CodingKeys: String, CodingKey {
            case requestsServed = "requests_served"
            case tokensGenerated = "tokens_generated"
        }
    }

    struct Capacity: Decodable {
        var totalMemoryGb: Double
        var gpuMemoryActiveGb: Double

        enum CodingKeys: String, CodingKey {
            case totalMemoryGb = "total_memory_gb"
            case gpuMemoryActiveGb = "gpu_memory_active_gb"
        }
    }

    var pid: Int32
    var version: String
    var writtenAt: Double
    var startedAt: Double
    var trust: Trust?
    var currentModel: String?
    var warmModels: [String]?
    var inferenceActive: Bool?
    var stats: Stats?
    var capacity: Capacity?

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
    var isFresh: Bool {
        Date().timeIntervalSince1970 - writtenAt < 90
    }

    /// Liveness probe identical to the CLI's: signal 0 to the recorded pid.
    var processAlive: Bool {
        kill(pid, 0) == 0
    }

    var uptime: TimeInterval {
        Date().timeIntervalSince1970 - startedAt
    }
}

enum DarkbloomPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let stateDir = home.appendingPathComponent(".darkbloom")
    static let daemonState = stateDir.appendingPathComponent("daemon-state.json")
    static let authToken = stateDir.appendingPathComponent("auth_token")
    static let cli = stateDir.appendingPathComponent("bin/darkbloom")

    static func readDaemonState() -> DaemonState? {
        guard let data = try? Data(contentsOf: daemonState) else { return nil }
        return try? JSONDecoder().decode(DaemonState.self, from: data)
    }

    static func readAuthToken() -> String? {
        guard let raw = try? String(contentsOf: authToken, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
