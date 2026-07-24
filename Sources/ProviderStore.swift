import Foundation

enum ProviderAPIFormat: String, Codable, CaseIterable, Sendable {
    case automatic
    case responses
    case chatCompletions

    var displayName: String {
        switch self {
        case .automatic: return "自动识别"
        case .responses: return "Responses API"
        case .chatCompletions: return "Chat Completions（本地桥接）"
        }
    }
}

struct ProviderProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var baseURL: String
    var model: String
    var apiFormat: ProviderAPIFormat?

    init(
        id: String,
        name: String,
        baseURL: String,
        model: String,
        apiFormat: ProviderAPIFormat? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.apiFormat = apiFormat
    }

    var isCodeAPI: Bool {
        URL(string: baseURL)?.host?.lowercased() == "codeapi.nexita.net"
    }

    var isDeepSeek: Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return host == "api.deepseek.com" || host.hasSuffix(".deepseek.com")
    }

    var effectiveAPIFormat: ProviderAPIFormat {
        switch apiFormat ?? .automatic {
        case .automatic: return isDeepSeek ? .chatCompletions : .responses
        case let format: return format
        }
    }

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static let codeAPI = ProviderProfile(
        id: "codeapi",
        name: "CodeAPI",
        baseURL: "https://codeapi.nexita.net",
        model: "gpt-5.6-sol",
        apiFormat: .responses
    )
}

private struct ProviderDatabase: Codable {
    var providers: [ProviderProfile]
    var selectedProviderID: String?
    var officialModel: String?
}

enum ProviderStoreError: LocalizedError {
    case cannotSave(String)
    case duplicateID
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case let .cannotSave(message): return "无法保存提供商配置：\(message)"
        case .duplicateID: return "提供商内部标识重复，请删除异常配置后重新添加。"
        case let .duplicateName(name): return "路由名称“\(name)”已存在，请使用不同的名称。"
        }
    }
}

enum ProviderStore {
    static var databaseURL: URL {
        CredentialStore.directoryURL.appendingPathComponent("providers.json")
    }

    static func providers() -> [ProviderProfile] { load().providers }

    static func provider(id: String) -> ProviderProfile? {
        load().providers.first { $0.id == id }
    }

    static func selectedProviderID() -> String? { load().selectedProviderID }

    static func officialModel() -> String? { load().officialModel }

    static func saveProviders(_ providers: [ProviderProfile], selectedProviderID: String?) throws {
        let normalizedIDs = providers.map { $0.id.lowercased() }
        guard Set(normalizedIDs).count == normalizedIDs.count else {
            throw ProviderStoreError.duplicateID
        }
        if let collision = firstDuplicateName(in: providers) {
            throw ProviderStoreError.duplicateName(collision)
        }
        var database = load()
        database.providers = providers
        database.selectedProviderID = selectedProviderID
        try save(database)
    }

    static func normalizedName(_ name: String) -> String {
        name
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func hasNameCollision(
        _ name: String,
        excluding providerID: String,
        in providers: [ProviderProfile]
    ) -> Bool {
        let candidate = normalizedName(name)
        return providers.contains {
            $0.id != providerID && normalizedName($0.name) == candidate
        }
    }

    static func popupTitles(for providers: [ProviderProfile]) -> [String] {
        let counts = Dictionary(grouping: providers, by: { normalizedName($0.name) })
            .mapValues(\.count)
        var usedTitles = Set<String>()
        return providers.map { provider in
            guard counts[normalizedName(provider.name), default: 0] > 1 else {
                usedTitles.insert(provider.name)
                return provider.name
            }
            let host = URL(string: provider.baseURL)?.host ?? provider.normalizedBaseURL
            let descriptive = "\(provider.name) · \(host) · \(provider.model)"
            if usedTitles.insert(descriptive).inserted {
                return descriptive
            }
            let unique = "\(descriptive) · \(provider.id.prefix(8))"
            usedTitles.insert(unique)
            return unique
        }
    }

    static func makeProviderID(existing providers: [ProviderProfile]) -> String {
        let existingIDs = Set(providers.map { $0.id.lowercased() })
        var candidate: String
        repeat {
            candidate = UUID().uuidString.lowercased()
        } while existingIDs.contains(candidate)
        return candidate
    }

    static func setSelectedProviderID(_ id: String?) throws {
        var database = load()
        database.selectedProviderID = id
        try save(database)
    }

    static func setOfficialModel(_ model: String?) throws {
        var database = load()
        database.officialModel = model
        try save(database)
    }

    private static func load() -> ProviderDatabase {
        guard let data = try? Data(contentsOf: databaseURL),
              let database = try? JSONDecoder().decode(ProviderDatabase.self, from: data) else {
            return ProviderDatabase(providers: [.codeAPI], selectedProviderID: "codeapi", officialModel: nil)
        }
        return database
    }

    private static func firstDuplicateName(in providers: [ProviderProfile]) -> String? {
        var names = Set<String>()
        for provider in providers {
            guard names.insert(normalizedName(provider.name)).inserted else {
                return provider.name
            }
        }
        return nil
    }

    private static func save(_ database: ProviderDatabase) throws {
        do {
            try CredentialStore.prepareDirectory()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(database)
            try data.write(to: databaseURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        } catch {
            throw ProviderStoreError.cannotSave(error.localizedDescription)
        }
    }
}
