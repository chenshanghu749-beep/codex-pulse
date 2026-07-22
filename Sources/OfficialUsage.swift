import AppKit
import Foundation

struct OfficialRateLimitWindow: Sendable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: Date

    var remainingPercent: Double { max(0, 100 - usedPercent) }

    var label: String {
        switch windowDurationMins {
        case 0..<360: return "短时窗口"
        case 360..<1440: return "\(windowDurationMins / 60) 小时"
        case 10080: return "7 天"
        default: return "\(windowDurationMins / 1440) 天"
        }
    }
}

struct OfficialUsageSnapshot: Sendable {
    let primary: OfficialRateLimitWindow?
    let secondary: OfficialRateLimitWindow?
    let planType: String?
    let resetCredits: Int?
}

enum OfficialUsageError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case timeout
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "未找到 ChatGPT 内置的 Codex 服务。"
        case let .launchFailed(message): return "无法启动官方用量服务：\(message)"
        case .timeout: return "读取 OpenAI 官方用量超时。"
        case let .server(message): return "官方用量服务返回错误：\(message)"
        case .invalidResponse: return "官方用量数据格式无法识别。"
        }
    }
}

enum OfficialUsageClient {
    static func fetch() async throws -> OfficialUsageSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try fetchBlocking())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func codexURL() -> URL? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChatGPTLauncher.bundleIdentifier) {
            let bundled = appURL.appendingPathComponent("Contents/Resources/codex")
            if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        }
        let commonPaths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ]
        return commonPaths
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func fetchBlocking() throws -> OfficialUsageSnapshot {
        guard let executable = codexURL() else { throw OfficialUsageError.codexNotFound }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio", "-c", "model_provider=\"openai\""]

        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var buffer = Data()
        var snapshot: OfficialUsageSnapshot?
        var responseError: Error?
        var finished = false

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            lock.lock()
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(buffer.subdata(in: 0..<newline))
                buffer.removeSubrange(0...newline)
            }
            lock.unlock()

            for line in lines {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = object["id"] as? Int,
                      id == 7 else { continue }

                lock.lock()
                guard !finished else { lock.unlock(); continue }
                if let error = object["error"] as? [String: Any] {
                    responseError = OfficialUsageError.server(error["message"] as? String ?? "未知错误")
                } else {
                    do {
                        snapshot = try parse(object)
                    } catch {
                        responseError = error
                    }
                }
                finished = true
                lock.unlock()
                semaphore.signal()
            }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw OfficialUsageError.launchFailed(error.localizedDescription)
        }

        let messages = [
            "{\"method\":\"initialize\",\"id\":0,\"params\":{\"clientInfo\":{\"name\":\"codeapi_status\",\"title\":\"CodeAPI Status\",\"version\":\"1.1.0\"}}}",
            "{\"method\":\"initialized\",\"params\":{}}",
            "{\"method\":\"account/rateLimits/read\",\"id\":7}"
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(messages.utf8))

        let waitResult = semaphore.wait(timeout: .now() + 20)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }

        if waitResult == .timedOut { throw OfficialUsageError.timeout }
        if let responseError { throw responseError }
        guard let snapshot else { throw OfficialUsageError.invalidResponse }
        return snapshot
    }

    private static func parse(_ object: [String: Any]) throws -> OfficialUsageSnapshot {
        guard let result = object["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else {
            throw OfficialUsageError.invalidResponse
        }

        return OfficialUsageSnapshot(
            primary: parseWindow(limits["primary"]),
            secondary: parseWindow(limits["secondary"]),
            planType: limits["planType"] as? String,
            resetCredits: (result["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? Int
        )
    }

    private static func parseWindow(_ value: Any?) -> OfficialRateLimitWindow? {
        guard let object = value as? [String: Any],
              let used = (object["usedPercent"] as? NSNumber)?.doubleValue,
              let duration = (object["windowDurationMins"] as? NSNumber)?.intValue,
              let reset = (object["resetsAt"] as? NSNumber)?.doubleValue else { return nil }
        return OfficialRateLimitWindow(
            usedPercent: used,
            windowDurationMins: duration,
            resetsAt: Date(timeIntervalSince1970: reset)
        )
    }
}
