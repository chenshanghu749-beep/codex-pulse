import AppKit
import Foundation

enum RouteChoice: String, Sendable {
    case official
    case codeAPI

    var displayName: String {
        switch self {
        case .official: return "OpenAI 官方"
        case .codeAPI: return "CodeAPI"
        }
    }
}

enum RouteConfigError: LocalizedError {
    case cannotReadConfig
    case cannotWriteConfig(String)
    case chatGPTNotFound

    var errorDescription: String? {
        switch self {
        case .cannotReadConfig:
            return "无法读取 ~/.codex/config.toml。"
        case let .cannotWriteConfig(message):
            return "无法更新 Codex 配置：\(message)"
        case .chatGPTNotFound:
            return "未找到 ChatGPT 应用，请确认它已安装。"
        }
    }
}

enum RouteConfigManager {
    static let beginMarker = "# >>> CodeAPI Status managed provider >>>"
    static let endMarker = "# <<< CodeAPI Status managed provider <<<"

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    static func currentRoute() -> RouteChoice {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return .official
        }
        let topLevel = topLevelProvider(in: content)?.lowercased()
        if topLevel == "codeapi" { return .codeAPI }
        if let topLevel,
           content.range(of: "[model_providers.\(topLevel)]", options: .caseInsensitive) != nil,
           content.range(of: "codeapi.nexita.net", options: .caseInsensitive) != nil {
            return .codeAPI
        }
        return .official
    }

    static func apply(_ route: RouteChoice) throws {
        let fileManager = FileManager.default
        let directory = configURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            if fileManager.fileExists(atPath: configURL.path) {
                let backup = directory.appendingPathComponent("config.toml.codeapi-status.bak")
                try Data(existing.utf8).write(to: backup, options: .atomic)
            }
            let rendered = render(existing, route: route)
            try Data(rendered.utf8).write(to: configURL, options: .atomic)
        } catch {
            throw RouteConfigError.cannotWriteConfig(error.localizedDescription)
        }
    }

    @discardableResult
    static func migrateLegacyCredentialCommandIfNeeded() throws -> Bool {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8),
              content.contains(beginMarker),
              content.contains(endMarker),
              content.contains("command = \"/usr/bin/security\"") else {
            return false
        }
        try apply(currentRoute())
        return true
    }

    static func render(_ content: String, route: RouteChoice) -> String {
        var cleaned = removingManagedBlock(from: content)
        var lines = cleaned.components(separatedBy: .newlines)
        var inTopLevel = true
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inTopLevel = false }
            return inTopLevel && trimmed.hasPrefix("model_provider") && trimmed.contains("=")
        }

        while lines.first?.isEmpty == true { lines.removeFirst() }
        let provider = route == .codeAPI ? "codeapi" : "openai"
        lines.insert("model_provider = \"\(provider)\"", at: 0)
        cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let managed = """
        \(beginMarker)
        [model_providers.codeapi]
        name = "CodeAPI"
        base_url = "https://codeapi.nexita.net"
        wire_api = "responses"

        [model_providers.codeapi.auth]
        command = "/bin/cat"
        args = ["\(CredentialStore.keyURL.path)"]
        timeout_ms = 5000
        \(endMarker)
        """
        return cleaned + "\n\n" + managed + "\n"
    }

    private static func topLevelProvider(in content: String) -> String? {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            guard trimmed.hasPrefix("model_provider"), let equals = trimmed.firstIndex(of: "=") else { continue }
            return trimmed[trimmed.index(after: equals)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private static func removingManagedBlock(from content: String) -> String {
        guard let start = content.range(of: beginMarker),
              let end = content.range(of: endMarker, range: start.lowerBound..<content.endIndex) else {
            return content
        }
        var result = content
        var upper = end.upperBound
        if upper < result.endIndex, result[upper] == "\n" { upper = result.index(after: upper) }
        result.removeSubrange(start.lowerBound..<upper)
        return result
    }
}

@MainActor
enum ChatGPTLauncher {
    nonisolated static let bundleIdentifier = "com.openai.codex"

    static func restart() async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw RouteConfigError.chatGPTNotFound
        }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in running { app.terminate() }

        if !running.isEmpty {
            for _ in 0..<15 {
                if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
