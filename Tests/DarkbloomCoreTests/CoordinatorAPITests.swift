import XCTest
@testable import DarkbloomCore

final class CoordinatorAPITests: XCTestCase {
    func testDecodesAccountEarnings() throws {
        let json = """
        {
          "account_id": "acct-1",
          "available_balance_micro_usd": 21949,
          "available_balance_usd": "0.021949",
          "count": 221,
          "earnings": [
            {
              "id": 216814, "account_id": "acct-1",
              "provider_id": "8a89fc81-b596-4908-be69-7aca9eb4e40f",
              "provider_key": "chBubxHrg76wNj0DQ8J+IhSA3uh5H+TdOxbHNNoJOGE=",
              "job_id": "1956fa49", "model": "gpt-oss-20b",
              "amount_micro_usd": 144, "prompt_tokens": 81, "completion_tokens": 2048,
              "created_at": "2026-06-12T15:08:25.071033Z"
            },
            {
              "id": 216812, "account_id": "acct-1",
              "provider_id": "p2", "provider_key": "k2",
              "job_id": "j2", "model": "gemma-4-26b",
              "amount_micro_usd": 63, "prompt_tokens": 3959, "completion_tokens": 99,
              "created_at": "2026-06-12T15:08:18Z"
            }
          ],
          "history_limit": 5, "recent_count": 2,
          "total_micro_usd": 21949, "total_usd": "0.021949",
          "withdrawable_balance_micro_usd": 21949, "withdrawable_balance_usd": "0.021949"
        }
        """.data(using: .utf8)!

        let acct = try CoordinatorAPI.decodeAccountEarnings(json)
        XCTAssertEqual(acct.accountID, "acct-1")
        XCTAssertEqual(acct.availableBalanceMicroUSD, 21_949)
        XCTAssertEqual(acct.totalMicroUSD, 21_949)
        XCTAssertEqual(acct.count, 221)
        XCTAssertEqual(acct.historyLimit, 5)
        XCTAssertEqual(acct.recentCount, 2)
        XCTAssertEqual(acct.earnings.count, 2)
        XCTAssertEqual(acct.earnings[0].amountMicroUSD, 144)
        XCTAssertEqual(acct.earnings[0].model, "gpt-oss-20b")
        // Dates parse both with and without fractional seconds.
        XCTAssertEqual(acct.earnings[0].createdAt.timeIntervalSince1970, 1_781_276_905.071, accuracy: 0.001)
        XCTAssertEqual(acct.earnings[1].createdAt.timeIntervalSince1970, 1_781_276_898, accuracy: 0.001)
    }

    static let provider = """
    {
      "provider_id": "p1", "chip_name": "Apple M5 Max", "hardware_model": "Mac17,6",
      "serial_number": "SER1", "trust_level": "hardware", "status": "serving",
      "memory_gb": 128, "gpu_cores": 40, "models": ["gpt-oss-20b"], "mdm_verified": true
    }
    """

    func testDecodesProvidersWrappedDict() throws {
        let json = #"{"providers": [\#(Self.provider)]}"#.data(using: .utf8)!
        let list = try CoordinatorAPI.decodeProviders(json)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].providerID, "p1")
        XCTAssertEqual(list[0].chipName, "Apple M5 Max")
        XCTAssertEqual(list[0].models, ["gpt-oss-20b"])
    }

    func testDecodesProvidersBareArray() throws {
        let json = "[\(Self.provider)]".data(using: .utf8)!
        XCTAssertEqual(try CoordinatorAPI.decodeProviders(json).count, 1)
    }

    func testNullModelsIsTolerated() throws {
        // The live endpoint returns "models": null for some entries; the entry
        // must survive with models == nil rather than sinking the whole list.
        let withNull = Self.provider.replacingOccurrences(
            of: #""models": ["gpt-oss-20b"]"#, with: #""models": null"#)
        let json = #"{"providers": [\#(withNull), \#(Self.provider)]}"#.data(using: .utf8)!
        let list = try CoordinatorAPI.decodeProviders(json)
        XCTAssertEqual(list.count, 2)
        XCTAssertNil(list[0].models)
        XCTAssertEqual(list[1].models, ["gpt-oss-20b"])
    }

    func testMalformedEntryIsDroppedNotFatal() throws {
        let json = #"{"providers": [{"provider_id": 12345}, \#(Self.provider)]}"#.data(using: .utf8)!
        let list = try CoordinatorAPI.decodeProviders(json)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].providerID, "p1")
    }

    func testWarmupRequestTargetsSerialAndModel() throws {
        let req = try CoordinatorAPI.warmupRequest(
            serialNumber: "SER1",
            model: "gemma-4-26b",
            token: "tok"
        )

        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.url?.path, "/v1/chat/completions")
        XCTAssertEqual(URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "serial" })?.value, "SER1")

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gemma-4-26b")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["provider_serial"] as? String, "SER1")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": "Hello"]])
    }
}
