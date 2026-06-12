import XCTest
@testable import DarkbloomCore

final class DaemonStateTests: XCTestCase {
    // Shaped like a real ~/.darkbloom/daemon-state.json (schema 1).
    static let sample = """
    {
      "capacity": {"gpu_memory_active_gb": 11.29, "gpu_memory_cache_gb": 0, "total_memory_gb": 128},
      "current_model": "gpt-oss-20b",
      "inference_active": false,
      "pid": 4314,
      "schema": 1,
      "started_at": 1781266737.87,
      "stats": {"requests_served": 179, "tokens_generated": 202201, "usage_gaps": 0},
      "trust": {"reason": "MDM verification passed", "received_at": 1781274337.12,
                "status": "online", "trust_level": "hardware"},
      "version": "0.6.5",
      "warm_models": ["gpt-oss-20b"],
      "written_at": 1781276690.94
    }
    """.data(using: .utf8)!

    func testDecodesRealShape() throws {
        let s = try DaemonState.decode(Self.sample)
        XCTAssertEqual(s.pid, 4314)
        XCTAssertEqual(s.version, "0.6.5")
        XCTAssertEqual(s.currentModel, "gpt-oss-20b")
        XCTAssertEqual(s.warmModels, ["gpt-oss-20b"])
        XCTAssertEqual(s.stats?.requestsServed, 179)
        XCTAssertEqual(s.stats?.tokensGenerated, 202_201)
        XCTAssertEqual(s.trust?.trustLevel, "hardware")
        XCTAssertEqual(s.trust?.status, "online")
        XCTAssertEqual(s.capacity?.totalMemoryGb, 128)
    }

    func testDecodesSystemAndGPUCache() throws {
        let json = """
        {
          "pid": 1, "version": "0.6.5", "written_at": 100.0, "started_at": 50.0,
          "capacity": {"gpu_memory_active_gb": 11.4, "gpu_memory_cache_gb": 2.5, "total_memory_gb": 128},
          "system": {"memory_pressure": 0.39, "cpu_usage": 0.15, "thermal_state": "nominal"}
        }
        """.data(using: .utf8)!
        let s = try DaemonState.decode(json)
        XCTAssertEqual(s.capacity?.gpuMemoryCacheGb, 2.5)
        XCTAssertEqual(s.system?.thermalState, "nominal")
        XCTAssertEqual(s.system?.cpuUsage, 0.15)
        XCTAssertEqual(s.system?.memoryPressure, 0.39)
    }

    func testOptionalFieldsAbsent() throws {
        let minimal = """
        {"pid": 1, "version": "0.1.0", "written_at": 100.0, "started_at": 50.0}
        """.data(using: .utf8)!
        let s = try DaemonState.decode(minimal)
        XCTAssertNil(s.trust)
        XCTAssertNil(s.stats)
        XCTAssertNil(s.currentModel)
    }

    func testFreshnessBoundary() throws {
        let s = try DaemonState.decode(Self.sample)
        let written = Date(timeIntervalSince1970: s.writtenAt)
        XCTAssertTrue(s.isFresh(now: written.addingTimeInterval(89)))
        XCTAssertFalse(s.isFresh(now: written.addingTimeInterval(90)))
        XCTAssertFalse(s.isFresh(now: written.addingTimeInterval(3600)))
    }

    func testUptime() throws {
        let s = try DaemonState.decode(Self.sample)
        let now = Date(timeIntervalSince1970: s.startedAt + 120)
        XCTAssertEqual(s.uptime(now: now), 120, accuracy: 0.01)
    }
}
