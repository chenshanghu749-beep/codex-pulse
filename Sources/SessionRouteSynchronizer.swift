import Foundation

enum SessionRouteSyncError: LocalizedError {
    case databaseNotFound
    case sqliteUnavailable
    case sqliteFailed(String)
    case invalidDatabaseResponse

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "没有找到 Codex 本地会话数据库。"
        case .sqliteUnavailable:
            return "系统缺少 sqlite3，无法同步会话。"
        case let .sqliteFailed(message):
            return "同步 Codex 会话数据库失败：\(message)"
        case .invalidDatabaseResponse:
            return "Codex 会话数据库返回了无法识别的数据。"
        }
    }
}

private struct SessionRouteRecord: Codable {
    let id: String
    let rolloutPath: String
    let modelProvider: String
}

private struct SessionRouteBackup: Codable {
    let createdAt: Date
    let targetProvider: String
    let records: [SessionRouteRecord]
}

enum SessionRouteSynchronizer {
    private static let sqliteURL = URL(fileURLWithPath: "/usr/bin/sqlite3")

    static func synchronize(to route: RouteChoice) async throws -> Int {
        let targetProvider = providerID(for: route)
        let managedProviders = managedProviderIDs()
        return try await Task.detached(priority: .utility) {
            try synchronizeBlocking(
                targetProvider: targetProvider,
                managedProviders: managedProviders
            )
        }.value
    }

    private static func providerID(for route: RouteChoice) -> String {
        switch route {
        case .official:
            return "openai"
        case let .provider(id):
            return RouteConfigManager.codexProviderID(for: id)
        }
    }

    private static func managedProviderIDs() -> Set<String> {
        var ids: Set<String> = [
            "openai",
            "codeapi",
            RouteConfigManager.legacyManagedProviderID.lowercased()
        ]
        for profile in ProviderStore.providers() {
            ids.insert(RouteConfigManager.codexProviderID(for: profile.id).lowercased())
        }
        return ids
    }

    private static func synchronizeBlocking(
        targetProvider: String,
        managedProviders: Set<String>
    ) throws -> Int {
        guard FileManager.default.isExecutableFile(atPath: sqliteURL.path) else {
            throw SessionRouteSyncError.sqliteUnavailable
        }
        let databaseURL = try stateDatabaseURL()
        let records = try loadRecords(databaseURL: databaseURL).filter {
            isManagedProvider($0.modelProvider, managedProviders: managedProviders)
                && $0.modelProvider.caseInsensitiveCompare(targetProvider) != .orderedSame
        }
        guard !records.isEmpty else { return 0 }

        let backupURL = try createBackup(
            databaseURL: databaseURL,
            records: records,
            targetProvider: targetProvider
        )
        do {
            try updateDatabase(
                databaseURL: databaseURL,
                managedProviders: managedProviders,
                targetProvider: targetProvider
            )
            try? pruneBackups(
                in: backupURL.deletingLastPathComponent().deletingLastPathComponent(),
                keeping: 10
            )
            return records.count
        } catch {
            try? restoreDatabase(from: backupURL, to: databaseURL)
            throw error
        }
    }

    private static func stateDatabaseURL() throws -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []
        let stateDatabases = candidates.filter {
            $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite"
        }
        guard let url = stateDatabases.max(by: {
            stateVersion($0) < stateVersion($1)
        }) else {
            throw SessionRouteSyncError.databaseNotFound
        }
        return url
    }

    private static func stateVersion(_ url: URL) -> Int {
        Int(url.deletingPathExtension().lastPathComponent.dropFirst("state_".count)) ?? 0
    }

    private static func loadRecords(databaseURL: URL) throws -> [SessionRouteRecord] {
        let sql = """
        SELECT id,
               rollout_path AS rolloutPath,
               model_provider AS modelProvider
        FROM threads
        WHERE archived = 0 OR archived = 1;
        """
        let data = try runSQLite(databaseURL: databaseURL, arguments: ["-json", sql])
        guard let records = try? JSONDecoder().decode([SessionRouteRecord].self, from: data) else {
            throw SessionRouteSyncError.invalidDatabaseResponse
        }
        return records
    }

    private static func createBackup(
        databaseURL: URL,
        records: [SessionRouteRecord],
        targetProvider: String
    ) throws -> URL {
        try CredentialStore.prepareDirectory()
        let root = CredentialStore.directoryURL
            .appendingPathComponent("session-route-backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let folder = root.appendingPathComponent(
            "\(stamp)-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let backupDatabase = folder.appendingPathComponent(databaseURL.lastPathComponent)
        let backupCommand = ".backup '\(sqliteEscape(backupDatabase.path))'"
        _ = try runSQLite(databaseURL: databaseURL, arguments: [backupCommand])

        let manifest = SessionRouteBackup(
            createdAt: Date(),
            targetProvider: targetProvider,
            records: records
        )
        let manifestURL = folder.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: manifestURL.path
        )
        return backupDatabase
    }

    private static func pruneBackups(in root: URL, keeping limit: Int) throws {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        let folders = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        .filter {
            (try? $0.resourceValues(forKeys: keys).isDirectory) == true
        }
        .sorted {
            let left = try? $0.resourceValues(forKeys: keys).contentModificationDate
            let right = try? $1.resourceValues(forKeys: keys).contentModificationDate
            return (left ?? .distantPast) > (right ?? .distantPast)
        }
        for folder in folders.dropFirst(max(1, limit)) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    private static func updateDatabase(
        databaseURL: URL,
        managedProviders: Set<String>,
        targetProvider: String
    ) throws {
        let providers = managedProviders.sorted()
            .map { "'\(sqlEscape($0))'" }
            .joined(separator: ", ")
        let sql = """
        BEGIN IMMEDIATE;
        UPDATE threads
        SET model_provider = '\(sqlEscape(targetProvider))'
        WHERE lower(model_provider) IN (\(providers))
           OR lower(model_provider) LIKE 'codeapi_status_provider_%';
        COMMIT;
        """
        _ = try runSQLite(databaseURL: databaseURL, arguments: [sql])
    }

    private static func isManagedProvider(
        _ provider: String,
        managedProviders: Set<String>
    ) -> Bool {
        let normalized = provider.lowercased()
        return managedProviders.contains(normalized)
            || normalized.hasPrefix("codeapi_status_provider_")
    }

    private static func restoreDatabase(from backupURL: URL, to databaseURL: URL) throws {
        let command = ".restore '\(sqliteEscape(backupURL.path))'"
        _ = try runSQLite(databaseURL: databaseURL, arguments: [command])
    }

    private static func runSQLite(databaseURL: URL, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = sqliteURL
        process.arguments = [databaseURL.path] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw SessionRouteSyncError.sqliteFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SessionRouteSyncError.sqliteFailed(message?.isEmpty == false ? message! : "未知错误")
        }
        return data
    }

    private static func sqlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func sqliteEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
