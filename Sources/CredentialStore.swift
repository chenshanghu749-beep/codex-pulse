import Foundation

enum CredentialStoreError: LocalizedError {
    case cannotSave(String)

    var errorDescription: String? {
        switch self {
        case let .cannotSave(message): return "无法保存 API Key：\(message)"
        }
    }
}

enum CredentialStore {
    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/codeapi-status", isDirectory: true)
    }

    private static var keysDirectoryURL: URL { directoryURL.appendingPathComponent("keys", isDirectory: true) }

    static func keyURL(for providerID: String) -> URL {
        if providerID == "codeapi" { return directoryURL.appendingPathComponent("codeapi.key") }
        let safeID = providerID.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
                ? Character(String(scalar)) : "_"
        }
        return keysDirectoryURL.appendingPathComponent(String(safeID) + ".key")
    }

    static func load(providerID: String) -> String? {
        guard let data = try? Data(contentsOf: keyURL(for: providerID)),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    static func save(_ key: String, providerID: String) throws {
        do {
            let fileManager = FileManager.default
            try prepareDirectory()
            try fileManager.createDirectory(at: keysDirectoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: keysDirectoryURL.path)
            let keyURL = keyURL(for: providerID)

            if !fileManager.fileExists(atPath: keyURL.path) {
                guard fileManager.createFile(
                    atPath: keyURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    throw CredentialStoreError.cannotSave("无法创建凭据文件")
                }
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)

            let handle = try FileHandle(forWritingTo: keyURL)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data((key + "\n").utf8))
            try handle.synchronize()
            try handle.close()
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.cannotSave(error.localizedDescription)
        }
    }

    static func delete(providerID: String) throws {
        let url = keyURL(for: providerID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func prepareDirectory() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }
}
