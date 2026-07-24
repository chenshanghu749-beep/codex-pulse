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

struct OfficialTokenUsageSummary: Sendable {
    let lifetimeTokens: Int?
    let peakDailyTokens: Int?
    let longestRunningTurnSec: Int?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let todayTokens: Int?
}

struct OfficialUsageSnapshot: Sendable {
    let isLoggedIn: Bool
    let accountType: String?
    let email: String?
    let primary: OfficialRateLimitWindow?
    let secondary: OfficialRateLimitWindow?
    let planType: String?
    let resetCredits: Int?
    let tokenUsage: OfficialTokenUsageSummary?

    static let loggedOut = OfficialUsageSnapshot(
        isLoggedIn: false,
        accountType: nil,
        email: nil,
        primary: nil,
        secondary: nil,
        planType: nil,
        resetCredits: nil,
        tokenUsage: nil
    )
}

enum OfficialUsageError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case timeout
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "未找到 Codex 服务。"
        case let .launchFailed(message): return "无法启动官方用量服务：\(message)"
        case .timeout: return "读取 OpenAI 官方账号超时。"
        case let .server(message): return "官方账号服务返回错误：\(message)"
        case .invalidResponse: return "官方账号数据格式无法识别。"
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
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CodexLauncher.bundleIdentifier) {
            let bundled = appURL.appendingPathComponent("Contents/Resources/codex")
            if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        }
        return [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func fetchBlocking() throws -> OfficialUsageSnapshot {
        guard let executable = codexURL() else { throw OfficialUsageError.codexNotFound }
        // `account/read` is served by a newly spawned app-server process. On some
        // Codex builds it can temporarily return `account: null` even though the
        // desktop app and the shared Codex CLI session are authenticated. Treat
        // the CLI's explicit login status as the source of truth in that case.
        let cliStatus = loginStatus(executable: executable)
        if loginStatusUsesAPIKey(cliStatus.output) { return .loggedOut }
        let cliReportsLoggedIn = cliStatus.loggedIn

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
        var account: [String: Any]?
        var requiresOpenAIAuth = true
        var rateResult: [String: Any]?
        var usageResult: [String: Any]?
        var pendingDetails = 2
        var accountResponseReceived = false
        var receivedRateLimits = false
        var receivedTokenUsage = false
        var finished = false

        func completeLocked() {
            guard !finished else { return }
            finished = true
            if let account {
                snapshot = makeSnapshot(account: account, rateResult: rateResult, usageResult: usageResult)
            } else if !requiresOpenAIAuth {
                snapshot = .loggedOut
            } else {
                snapshot = .loggedOut
            }
            semaphore.signal()
        }

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
                      let id = (object["id"] as? NSNumber)?.intValue else { continue }

                lock.lock()
                guard !finished else { lock.unlock(); continue }
                if id == 1 {
                    accountResponseReceived = true
                    if let error = object["error"] as? [String: Any] {
                        responseError = OfficialUsageError.server(error["message"] as? String ?? "未知错误")
                        finished = true
                        lock.unlock()
                        semaphore.signal()
                        continue
                    }
                    guard let result = object["result"] as? [String: Any] else {
                        responseError = OfficialUsageError.invalidResponse
                        finished = true
                        lock.unlock()
                        semaphore.signal()
                        continue
                    }
                    requiresOpenAIAuth = result["requiresOpenaiAuth"] as? Bool ?? true
                    account = result["account"] as? [String: Any]
                    if account == nil, cliReportsLoggedIn {
                        account = ["type": "chatgpt"]
                    }
                    guard let account else {
                        completeLocked()
                        lock.unlock()
                        continue
                    }
                    let type = (account["type"] as? String)?.lowercased() ?? ""
                    let supportsChatGPTUsage = ["chatgpt", "chatgptauthtokens", "agentidentity", "personalaccesstoken"].contains(type)
                    guard supportsChatGPTUsage else {
                        completeLocked()
                        lock.unlock()
                        continue
                    }
                    if pendingDetails == 0 { completeLocked() }
                    lock.unlock()
                    continue
                }

                if id == 6 {
                    rateResult = object["result"] as? [String: Any]
                    if !receivedRateLimits {
                        receivedRateLimits = true
                        pendingDetails -= 1
                    }
                } else if id == 7 {
                    usageResult = object["result"] as? [String: Any]
                    if !receivedTokenUsage {
                        receivedTokenUsage = true
                        pendingDetails -= 1
                    }
                }
                if accountResponseReceived, pendingDetails == 0 { completeLocked() }
                lock.unlock()
            }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw OfficialUsageError.launchFailed(error.localizedDescription)
        }

        let messages = [
            "{\"method\":\"initialize\",\"id\":0,\"params\":{\"clientInfo\":{\"name\":\"codex_pulse\",\"title\":\"Codex Pulse\",\"version\":\"2.4.4\"}}}",
            "{\"method\":\"initialized\",\"params\":{}}",
            "{\"method\":\"account/read\",\"id\":1,\"params\":{\"refreshToken\":true}}",
            "{\"method\":\"account/rateLimits/read\",\"id\":6}",
            "{\"method\":\"account/usage/read\",\"id\":7}"
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(messages.utf8))

        let waitResult = semaphore.wait(timeout: .now() + 20)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }

        if waitResult == .timedOut, cliReportsLoggedIn {
            return makeSnapshot(
                account: ["type": "chatgpt"],
                rateResult: rateResult,
                usageResult: usageResult
            )
        }
        if waitResult == .timedOut { throw OfficialUsageError.timeout }
        if let responseError { throw responseError }
        if cliReportsLoggedIn, snapshot?.isLoggedIn != true {
            return makeSnapshot(
                account: ["type": "chatgpt"],
                rateResult: rateResult,
                usageResult: usageResult
            )
        }
        guard let snapshot else { throw OfficialUsageError.invalidResponse }
        return snapshot
    }

    static func loginStatusDiagnostic() -> String {
        guard let executable = codexURL() else { return "executable=missing" }
        let result = loginStatus(executable: executable)
        return "executable=\(executable.path) status=\(result.status) loggedIn=\(result.loggedIn) output=\(result.output)"
    }

    private static func loginStatus(executable: URL) -> (loggedIn: Bool, status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["login", "status"]
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        do {
            try process.run()
            process.waitUntilExit()
            let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
                + standardError.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (
                loginStatusIndicatesChatGPT(text, terminationStatus: process.terminationStatus),
                process.terminationStatus,
                text
            )
        } catch {
            return (false, -1, error.localizedDescription)
        }
    }

    static func loginStatusIndicatesChatGPT(_ text: String, terminationStatus: Int32) -> Bool {
        guard terminationStatus == 0 else { return false }
        let explicitlyLoggedOut = text.range(of: "not logged in", options: .caseInsensitive) != nil
            || text.range(of: "logged out", options: .caseInsensitive) != nil
        return !explicitlyLoggedOut && !loginStatusUsesAPIKey(text)
    }

    static func loginStatusUsesAPIKey(_ text: String) -> Bool {
        text.range(of: "using an api key", options: .caseInsensitive) != nil
    }

    private static func makeSnapshot(
        account: [String: Any],
        rateResult: [String: Any]?,
        usageResult: [String: Any]?
    ) -> OfficialUsageSnapshot {
        let limits = rateResult?["rateLimits"] as? [String: Any]
        let summary = usageResult?["summary"] as? [String: Any]
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let buckets = usageResult?["dailyUsageBuckets"] as? [[String: Any]]
        let todayTokens = buckets?.first { ($0["startDate"] as? String) == String(today) }?["tokens"] as? Int
        let tokenUsage: OfficialTokenUsageSummary? = summary == nil && todayTokens == nil ? nil : OfficialTokenUsageSummary(
            lifetimeTokens: summary?["lifetimeTokens"] as? Int,
            peakDailyTokens: summary?["peakDailyTokens"] as? Int,
            longestRunningTurnSec: summary?["longestRunningTurnSec"] as? Int,
            currentStreakDays: summary?["currentStreakDays"] as? Int,
            longestStreakDays: summary?["longestStreakDays"] as? Int,
            todayTokens: todayTokens
        )
        return OfficialUsageSnapshot(
            isLoggedIn: true,
            accountType: account["type"] as? String,
            email: account["email"] as? String,
            primary: parseWindow(limits?["primary"]),
            secondary: parseWindow(limits?["secondary"]),
            planType: (account["planType"] as? String) ?? (limits?["planType"] as? String),
            resetCredits: (rateResult?["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? Int,
            tokenUsage: tokenUsage
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
