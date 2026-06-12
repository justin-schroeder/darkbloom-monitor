import XCTest
@testable import DarkbloomCore

final class CatalogDecodeTests: XCTestCase {
    func testDecodesCatalogAndFiltersInactive() throws {
        let json = """
        {
          "models": [
            {"id": "gpt-oss-20b", "display_name": "GPT-OSS 20B",
             "min_ram_gb": 24, "size_gb": 12.1, "active": true},
            {"id": "old-model", "display_name": "Old", "active": false},
            {"id": "gemma-4-26b", "display_name": "Gemma 4 26B",
             "min_ram_gb": 36, "size_gb": 31.2, "active": true}
          ]
        }
        """.data(using: .utf8)!
        let catalog = try CoordinatorAPI.decodeCatalog(json)
        XCTAssertEqual(catalog.map(\.id), ["gpt-oss-20b", "gemma-4-26b"])
        XCTAssertEqual(catalog[0].displayName, "GPT-OSS 20B")
        XCTAssertEqual(catalog[0].minRamGB, 24)
        XCTAssertEqual(catalog[1].sizeGB, 31.2)
    }

    func testMalformedCatalogEntryIsDropped() throws {
        let json = """
        {"models": [{"id": 7}, {"id": "ok", "display_name": "OK"}]}
        """.data(using: .utf8)!
        XCTAssertEqual(try CoordinatorAPI.decodeCatalog(json).map(\.id), ["ok"])
    }
}

final class LaunchAgentPlistTests: XCTestCase {
    func plist(arguments: [String]) -> Data {
        let dict: [String: Any] = ["Label": "io.darkbloom.provider", "ProgramArguments": arguments]
        return try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    func testExtractsRepeatedModelFlags() {
        let data = plist(arguments: [
            "/usr/local/bin/darkbloom", "start", "--foreground",
            "--coordinator-url", "wss://api.darkbloom.dev/ws/provider",
            "--model", "gemma-4-26b", "--model", "gpt-oss-20b",
            "--idle-timeout", "60",
        ])
        XCTAssertEqual(LaunchAgentPlist.models(fromPlist: data), ["gemma-4-26b", "gpt-oss-20b"])
    }

    func testNoModelsAndMalformedPlist() {
        XCTAssertEqual(LaunchAgentPlist.models(fromPlist: plist(arguments: ["darkbloom", "start"])), [])
        XCTAssertEqual(LaunchAgentPlist.models(fromPlist: Data("junk".utf8)), [])
        // Trailing --model with no value must not crash or invent a model.
        XCTAssertEqual(LaunchAgentPlist.models(fromPlist: plist(arguments: ["start", "--model"])), [])
    }
}

final class LocalModelsTests: XCTestCase {
    func testScansHubDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["models--gpt-oss-20b", "models--gemma-4-26b", "CACHEDIR.TAG", "mlx-community"] {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        XCTAssertEqual(LocalModels.downloadedIDs(hubDir: dir), ["gpt-oss-20b", "gemma-4-26b"])
    }

    func testMissingHubDirectory() {
        let missing = URL(fileURLWithPath: "/nonexistent/hub-\(UUID().uuidString)")
        XCTAssertEqual(LocalModels.downloadedIDs(hubDir: missing), [])
    }
}
