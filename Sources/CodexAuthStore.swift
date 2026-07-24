import Foundation

enum CodexAuthStoreError: LocalizedError {
    case cannotPrepare(String)

    var errorDescription: String? {
        switch self {
        case let .cannotPrepare(message):
            return "无法切换 Codex 认证状态：\(message)"
        }
    }
}

struct CodexAuthSnapshot {
    let existed: Bool
    let data: Data?
}

struct CodexAuthPreparation {
    let requiresOfficialLogin: Bool

    static let ready = CodexAuthPreparation(requiresOfficialLogin: false)
}

enum CodexAuthKind: Equatable {
    case empty
    case chatGPT
    case configuredProviderAPIKey
    case otherAPIKey
    case unknown
}

enum CodexOfficialAuthPlan: Equatable {
    case useCurrent(Data)
    case restoreBackup(Data)
    case removeCurrentAndRequireLogin
    case keepCurrent
}

enum CodexAuthStore {
    static var authURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    static var officialBackupURL: URL {
        CredentialStore.directoryURL.appendingPathComponent("official-auth.json")
    }

    static var displacedProviderAuthURL: URL {
        CredentialStore.directoryURL.appendingPathComponent("provider-auth.json.bak")
    }

    static func snapshot() throws -> CodexAuthSnapshot {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: authURL.path) else {
            return CodexAuthSnapshot(existed: false, data: nil)
        }
        do {
            return CodexAuthSnapshot(existed: true, data: try Data(contentsOf: authURL))
        } catch {
            throw CodexAuthStoreError.cannotPrepare(error.localizedDescription)
        }
    }

    static func restore(_ snapshot: CodexAuthSnapshot) throws {
        do {
            if snapshot.existed, let data = snapshot.data {
                try writeSecure(data, to: authURL)
            } else if FileManager.default.fileExists(atPath: authURL.path) {
                try FileManager.default.removeItem(at: authURL)
            }
        } catch {
            throw CodexAuthStoreError.cannotPrepare(error.localizedDescription)
        }
    }

    static func prepareForSwitch(to route: RouteChoice) throws -> CodexAuthPreparation {
        do {
            switch route {
            case .official:
                return try prepareOfficialAuth()
            case let .provider(id):
                try prepareProviderAuth(providerID: id)
                return .ready
            }
        } catch let error as CodexAuthStoreError {
            throw error
        } catch {
            throw CodexAuthStoreError.cannotPrepare(error.localizedDescription)
        }
    }

    static func kind(of data: Data?, configuredProviderKeys: Set<String>) -> CodexAuthKind {
        guard let data, !data.isEmpty else { return .empty }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }
        if hasChatGPTCredentials(object) { return .chatGPT }
        guard let key = nonemptyString(object["OPENAI_API_KEY"]) else { return .unknown }
        return configuredProviderKeys.contains(key) ? .configuredProviderAPIKey : .otherAPIKey
    }

    static func officialPlan(
        currentData: Data?,
        backupData: Data?,
        configuredProviderKeys: Set<String>
    ) -> CodexOfficialAuthPlan {
        if kind(of: currentData, configuredProviderKeys: configuredProviderKeys) == .chatGPT,
           let currentData,
           let sanitized = sanitizedChatGPTAuth(currentData) {
            return .useCurrent(sanitized)
        }
        if kind(of: backupData, configuredProviderKeys: configuredProviderKeys) == .chatGPT,
           let backupData,
           let sanitized = sanitizedChatGPTAuth(backupData) {
            return .restoreBackup(sanitized)
        }
        if kind(of: currentData, configuredProviderKeys: configuredProviderKeys) == .configuredProviderAPIKey {
            return .removeCurrentAndRequireLogin
        }
        if kind(of: currentData, configuredProviderKeys: configuredProviderKeys) == .empty {
            return .removeCurrentAndRequireLogin
        }
        return .keepCurrent
    }

    private static func prepareOfficialAuth() throws -> CodexAuthPreparation {
        let currentData = try readIfPresent(authURL)
        let backupData = try readIfPresent(officialBackupURL)
        let providerKeys = configuredProviderKeys()
        switch officialPlan(
            currentData: currentData,
            backupData: backupData,
            configuredProviderKeys: providerKeys
        ) {
        case let .useCurrent(data):
            try writeSecure(data, to: authURL)
            try writeSecure(data, to: officialBackupURL)
            return .ready
        case let .restoreBackup(data):
            try writeSecure(data, to: authURL)
            return .ready
        case .removeCurrentAndRequireLogin:
            if let currentData {
                try writeSecure(currentData, to: displacedProviderAuthURL)
            }
            if FileManager.default.fileExists(atPath: authURL.path) {
                try FileManager.default.removeItem(at: authURL)
            }
            return CodexAuthPreparation(requiresOfficialLogin: true)
        case .keepCurrent:
            return .ready
        }
    }

    private static func prepareProviderAuth(providerID: String) throws {
        try backupOfficialAuthIfPresent()
        guard let key = CredentialStore.load(providerID: providerID) else {
            throw CodexAuthStoreError.cannotPrepare("所选提供商尚未配置 API Key。")
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["OPENAI_API_KEY": key],
            options: [.prettyPrinted, .sortedKeys]
        )
        try writeSecure(data, to: authURL)
    }

    private static func backupOfficialAuthIfPresent() throws {
        guard let currentData = try readIfPresent(authURL),
              kind(of: currentData, configuredProviderKeys: configuredProviderKeys()) == .chatGPT,
              let sanitized = sanitizedChatGPTAuth(currentData) else { return }
        try writeSecure(sanitized, to: officialBackupURL)
    }

    private static func configuredProviderKeys() -> Set<String> {
        Set(ProviderStore.providers().compactMap { CredentialStore.load(providerID: $0.id) })
    }

    private static func sanitizedChatGPTAuth(_ data: Data) -> Data? {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              hasChatGPTCredentials(object) else { return nil }
        object["OPENAI_API_KEY"] = NSNull()
        return try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func hasChatGPTCredentials(_ object: [String: Any]) -> Bool {
        let mode = nonemptyString(object["auth_mode"])?.lowercased() ?? ""
        if mode.contains("chatgpt") { return true }
        guard let tokens = object["tokens"] as? [String: Any] else { return false }
        return ["access_token", "refresh_token", "id_token"].contains {
            nonemptyString(tokens[$0]) != nil
        }
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readIfPresent(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private static func writeSecure(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
