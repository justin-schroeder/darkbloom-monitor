import Foundation

/// Read-only client for the Darkbloom coordinator (api.darkbloom.dev),
/// authenticated with the CLI's device-login token where required.
public struct CoordinatorAPI {
    public static let baseURL = URL(string: "https://api.darkbloom.dev")!

    public struct Earning: Decodable, Identifiable {
        public var id: Int64
        public var providerID: String
        public var providerKey: String
        public var model: String
        public var amountMicroUSD: Int64
        public var promptTokens: Int
        public var completionTokens: Int
        public var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, model
            case providerID = "provider_id"
            case providerKey = "provider_key"
            case amountMicroUSD = "amount_micro_usd"
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case createdAt = "created_at"
        }

        public init(
            id: Int64, providerID: String, providerKey: String, model: String,
            amountMicroUSD: Int64, promptTokens: Int, completionTokens: Int, createdAt: Date
        ) {
            self.id = id
            self.providerID = providerID
            self.providerKey = providerKey
            self.model = model
            self.amountMicroUSD = amountMicroUSD
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.createdAt = createdAt
        }
    }

    public struct AccountEarnings: Decodable {
        public var accountID: String
        public var earnings: [Earning]
        public var totalMicroUSD: Int64
        public var count: Int64
        public var historyLimit: Int?
        public var recentCount: Int?
        public var availableBalanceMicroUSD: Int64
        public var withdrawableBalanceMicroUSD: Int64

        enum CodingKeys: String, CodingKey {
            case earnings, count
            case accountID = "account_id"
            case totalMicroUSD = "total_micro_usd"
            case historyLimit = "history_limit"
            case recentCount = "recent_count"
            case availableBalanceMicroUSD = "available_balance_micro_usd"
            case withdrawableBalanceMicroUSD = "withdrawable_balance_micro_usd"
        }
    }

    public struct AttestedProvider: Codable {
        public var providerID: String
        public var chipName: String
        public var hardwareModel: String
        public var serialNumber: String
        public var trustLevel: String
        public var status: String
        public var memoryGB: Int
        public var gpuCores: Int
        public var models: [String]?
        public var mdmVerified: Bool

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

        public init(
            providerID: String, chipName: String, hardwareModel: String, serialNumber: String,
            trustLevel: String, status: String, memoryGB: Int, gpuCores: Int,
            models: [String]?, mdmVerified: Bool
        ) {
            self.providerID = providerID
            self.chipName = chipName
            self.hardwareModel = hardwareModel
            self.serialNumber = serialNumber
            self.trustLevel = trustLevel
            self.status = status
            self.memoryGB = memoryGB
            self.gpuCores = gpuCores
            self.models = models
            self.mdmVerified = mdmVerified
        }
    }

    public struct CatalogModel: Decodable, Identifiable, Equatable {
        public var id: String
        public var displayName: String
        public var minRamGB: Double?
        public var sizeGB: Double?
        public var active: Bool?

        enum CodingKeys: String, CodingKey {
            case id, active
            case displayName = "display_name"
            case minRamGB = "min_ram_gb"
            case sizeGB = "size_gb"
        }

        public init(id: String, displayName: String, minRamGB: Double?, sizeGB: Double?, active: Bool?) {
            self.id = id
            self.displayName = displayName
            self.minRamGB = minRamGB
            self.sizeGB = sizeGB
            self.active = active
        }
    }

    public enum APIError: LocalizedError {
        case noToken
        case unauthorized
        case http(Int)

        public var errorDescription: String? {
            switch self {
            case .noToken: return "Not logged in — run `darkbloom login`"
            case .unauthorized: return "Auth token rejected — run `darkbloom login`"
            case .http(let code): return "Coordinator returned HTTP \(code)"
            }
        }
    }

    struct ChatMessage: Encodable {
        var role: String
        var content: String
    }

    struct WarmupRequestBody: Encodable {
        var model: String
        var messages: [ChatMessage]
        var stream: Bool
        var providerSerial: String

        enum CodingKeys: String, CodingKey {
            case model, messages, stream
            case providerSerial = "provider_serial"
        }
    }

    // MARK: - Decoding (pure, tested)

    static func decoder() -> JSONDecoder {
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

    public static func decodeAccountEarnings(_ data: Data) throws -> AccountEarnings {
        try decoder().decode(AccountEarnings.self, from: data)
    }

    /// Tolerates both a bare array and a `{"providers": [...]}` wrapper, and
    /// drops entries that fail to decode rather than failing the whole list.
    public static func decodeProviders(_ data: Data) throws -> [AttestedProvider] {
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

    /// Active catalog entries, in the coordinator's order. Entries that fail
    /// to decode are dropped rather than failing the whole list.
    public static func decodeCatalog(_ data: Data) throws -> [CatalogModel] {
        struct Lossy: Decodable {
            var value: CatalogModel?
            init(from d: Decoder) throws { value = try? CatalogModel(from: d) }
        }
        struct Wrapper: Decodable { var models: [Lossy] }
        return try decoder().decode(Wrapper.self, from: data).models
            .compactMap(\.value)
            .filter { $0.active ?? true }
    }

    // MARK: - Network

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

    static func warmupRequest(serialNumber: String, model: String, token: String) throws -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/v1/chat/completions"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "serial", value: serialNumber)]
        var req = URLRequest(url: comps.url!, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(WarmupRequestBody(
            model: model,
            messages: [.init(role: "user", content: "Hello")],
            stream: false,
            providerSerial: serialNumber
        ))
        return req
    }

    private static func send(_ request: URLRequest) async throws {
        let (_, resp) = try await URLSession.shared.data(for: request)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw APIError.unauthorized }
        guard (200..<300).contains(code) else { throw APIError.http(code) }
    }

    /// GET /v1/provider/account-earnings — lifetime totals, balance, and recent
    /// per-job history for the account the CLI token belongs to. Server caches 20s.
    public static func accountEarnings(limit: Int = 1000) async throws -> AccountEarnings {
        guard let token = DarkbloomPaths.readAuthToken() else { throw APIError.noToken }
        let data = try await get("/v1/provider/account-earnings",
                                 query: [.init(name: "limit", value: String(limit))],
                                 token: token)
        return try decodeAccountEarnings(data)
    }

    /// GET /v1/providers/attestation — public list of every provider currently
    /// connected to the coordinator. Filtered by the caller against the
    /// account's provider IDs.
    public static func connectedProviders() async throws -> [AttestedProvider] {
        try decodeProviders(await get("/v1/providers/attestation"))
    }

    /// GET /v1/models/catalog — the same public catalog the CLI's model
    /// picker shows (display names, sizes, RAM requirements).
    public static func modelCatalog() async throws -> [CatalogModel] {
        try decodeCatalog(await get("/v1/models/catalog"))
    }

    /// POST /v1/chat/completions once per model, pinned to this Mac's serial,
    /// so the provider loads each selected model after restart.
    public static func warmupMachine(serialNumber: String, models: [String]) async throws {
        guard let token = DarkbloomPaths.readAuthToken() else { throw APIError.noToken }
        for model in models {
            try await send(warmupRequest(serialNumber: serialNumber, model: model, token: token))
        }
    }
}
