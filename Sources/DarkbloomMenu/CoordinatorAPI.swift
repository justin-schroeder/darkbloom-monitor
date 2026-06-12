import Foundation

/// Read-only client for the Darkbloom coordinator (api.darkbloom.dev),
/// authenticated with the CLI's device-login token where required.
struct CoordinatorAPI {
    static let baseURL = URL(string: "https://api.darkbloom.dev")!

    struct Earning: Decodable, Identifiable {
        var id: Int64
        var providerID: String
        var providerKey: String
        var model: String
        var amountMicroUSD: Int64
        var promptTokens: Int
        var completionTokens: Int
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, model
            case providerID = "provider_id"
            case providerKey = "provider_key"
            case amountMicroUSD = "amount_micro_usd"
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case createdAt = "created_at"
        }
    }

    struct AccountEarnings: Decodable {
        var accountID: String
        var earnings: [Earning]
        var totalMicroUSD: Int64
        var count: Int64
        var availableBalanceMicroUSD: Int64
        var withdrawableBalanceMicroUSD: Int64

        enum CodingKeys: String, CodingKey {
            case earnings, count
            case accountID = "account_id"
            case totalMicroUSD = "total_micro_usd"
            case availableBalanceMicroUSD = "available_balance_micro_usd"
            case withdrawableBalanceMicroUSD = "withdrawable_balance_micro_usd"
        }
    }

    struct AttestedProvider: Codable {
        var providerID: String
        var chipName: String
        var hardwareModel: String
        var serialNumber: String
        var trustLevel: String
        var status: String
        var memoryGB: Int
        var gpuCores: Int
        var models: [String]?
        var mdmVerified: Bool

        enum CodingKeys: String, CodingKey {
            case models, status
            case providerID = "provider_id"
            case chipName = "chip_name"
            case hardwareModel = "hardware_model"
            case serialNumber = "serial_number"
            case trustLevel = "trust_level"
            case memoryGB = "memory_gb"
            case gpuCores = "gpu_cores"
            case mdmVerified = "mdm_verified"
        }
    }

    enum APIError: LocalizedError {
        case noToken
        case unauthorized
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .noToken: return "Not logged in — run `darkbloom login`"
            case .unauthorized: return "Auth token rejected — run `darkbloom login`"
            case .http(let code): return "Coordinator returned HTTP \(code)"
            }
        }
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = iso.date(from: s) ?? isoPlain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath, debugDescription: "Unparseable date: \(s)"))
        }
        return d
    }

    private static func get(_ path: String, query: [URLQueryItem] = [], token: String? = nil) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw APIError.unauthorized }
        guard (200..<300).contains(code) else { throw APIError.http(code) }
        return data
    }

    /// GET /v1/provider/account-earnings — lifetime totals, balance, and recent
    /// per-job history for the account the CLI token belongs to. Server caches 20s.
    static func accountEarnings(limit: Int = 1000) async throws -> AccountEarnings {
        guard let token = DarkbloomPaths.readAuthToken() else { throw APIError.noToken }
        let data = try await get("/v1/provider/account-earnings",
                                 query: [.init(name: "limit", value: String(limit))],
                                 token: token)
        return try decoder().decode(AccountEarnings.self, from: data)
    }

    /// GET /v1/providers/attestation — public list of every provider currently
    /// connected to the coordinator. Filtered by the caller against the
    /// account's provider IDs. Entries that fail to decode are dropped rather
    /// than failing the whole list.
    static func connectedProviders() async throws -> [AttestedProvider] {
        let data = try await get("/v1/providers/attestation")
        struct Lossy: Decodable {
            var value: AttestedProvider?
            init(from d: Decoder) throws { value = try? AttestedProvider(from: d) }
        }
        if let list = try? decoder().decode([Lossy].self, from: data) {
            return list.compactMap(\.value)
        }
        struct Wrapper: Decodable { var providers: [Lossy] }
        return try decoder().decode(Wrapper.self, from: data).providers.compactMap(\.value)
    }
}
