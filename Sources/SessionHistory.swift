import AppKit
import Foundation

struct CodexSessionSummary: Sendable {
    let id: String
    let title: String
    let preview: String
    let modelProvider: String
    let cwd: String?
    let createdAt: Date
    let updatedAt: Date
    let isArchived: Bool
}

enum SessionHistoryError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case timeout
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "未找到 Codex 服务。"
        case let .launchFailed(message): return "无法启动会话记录服务：\(message)"
        case .timeout: return "读取会话记录超时。"
        case let .server(message): return "读取会话记录失败：\(message)"
        case .invalidResponse: return "会话记录格式无法识别。"
        }
    }
}

enum SessionHistoryClient {
    static func fetch(limit: Int = 5_000) async throws -> [CodexSessionSummary] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try fetchBlocking(limit: limit))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func unarchive(id: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try unarchiveBlocking(id: id)
                    continuation.resume()
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
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func fetchBlocking(limit: Int) throws -> [CodexSessionSummary] {
        guard let executable = codexURL() else { throw SessionHistoryError.codexNotFound }

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
        let maximumSessions = max(1, min(limit, 10_000))
        var collectedSessions: [CodexSessionSummary] = []
        var sessions: [CodexSessionSummary]?
        var responseError: Error?
        var finished = false
        var nextRequestID = 20
        var seenCursors = Set<String>()
        var readingArchived = false

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
                      let id = (object["id"] as? NSNumber)?.intValue,
                      id >= 20 else { continue }

                lock.lock()
                guard !finished else { lock.unlock(); continue }
                var nextRequest: Data?
                var shouldSignal = false
                if let error = object["error"] as? [String: Any] {
                    responseError = SessionHistoryError.server(error["message"] as? String ?? "未知错误")
                    finished = true
                    shouldSignal = true
                } else {
                    do {
                        let page = try parsePage(object, archived: readingArchived)
                        let existingIDs = Set(collectedSessions.map(\.id))
                        collectedSessions.append(contentsOf: page.sessions.filter { !existingIDs.contains($0.id) })
                        if collectedSessions.count >= maximumSessions {
                            sessions = Array(collectedSessions.prefix(maximumSessions))
                            finished = true
                            shouldSignal = true
                        } else if let cursor = page.nextCursor,
                                  !cursor.isEmpty,
                                  !seenCursors.contains(cursor) {
                            seenCursors.insert(cursor)
                            nextRequestID += 1
                            nextRequest = threadListRequest(
                                id: nextRequestID,
                                cursor: cursor,
                                limit: min(100, maximumSessions - collectedSessions.count),
                                archived: readingArchived
                            )
                        } else if !readingArchived {
                            readingArchived = true
                            seenCursors.removeAll()
                            nextRequestID += 1
                            nextRequest = threadListRequest(
                                id: nextRequestID,
                                cursor: nil,
                                limit: min(100, maximumSessions - collectedSessions.count),
                                archived: true
                            )
                        } else {
                            sessions = collectedSessions
                            finished = true
                            shouldSignal = true
                        }
                    } catch {
                        responseError = error
                        finished = true
                        shouldSignal = true
                    }
                }
                lock.unlock()
                if let nextRequest { input.fileHandleForWriting.write(nextRequest) }
                if shouldSignal { semaphore.signal() }
            }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw SessionHistoryError.launchFailed(error.localizedDescription)
        }

        let messages = [
            "{\"method\":\"initialize\",\"id\":0,\"params\":{\"clientInfo\":{\"name\":\"codex_pulse\",\"title\":\"Codex Pulse\",\"version\":\"2.4.3\"}}}",
            "{\"method\":\"initialized\",\"params\":{}}"
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(messages.utf8))
        input.fileHandleForWriting.write(threadListRequest(
            id: 20,
            cursor: nil,
            limit: min(100, maximumSessions),
            archived: false
        ))

        let waitResult = semaphore.wait(timeout: .now() + 60)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }

        if waitResult == .timedOut { throw SessionHistoryError.timeout }
        if let responseError { throw responseError }
        guard let sessions else { throw SessionHistoryError.invalidResponse }
        return sessions
    }

    private static func unarchiveBlocking(id: String) throws {
        guard let executable = codexURL() else { throw SessionHistoryError.codexNotFound }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio", "-c", "model_provider=\"openai\""]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var buffer = Data()
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
                      (object["id"] as? NSNumber)?.intValue == 30 else { continue }
                lock.lock()
                guard !finished else { lock.unlock(); continue }
                if let error = object["error"] as? [String: Any] {
                    responseError = SessionHistoryError.server(error["message"] as? String ?? "未知错误")
                }
                finished = true
                lock.unlock()
                semaphore.signal()
            }
        }

        do { try process.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw SessionHistoryError.launchFailed(error.localizedDescription)
        }
        let initialize = [
            "{\"method\":\"initialize\",\"id\":0,\"params\":{\"clientInfo\":{\"name\":\"codex_pulse\",\"title\":\"Codex Pulse\",\"version\":\"2.4.3\"}}}",
            "{\"method\":\"initialized\",\"params\":{}}"
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(initialize.utf8))
        let request: [String: Any] = ["method": "thread/unarchive", "id": 30, "params": ["threadId": id]]
        var requestData = try JSONSerialization.data(withJSONObject: request)
        requestData.append(0x0A)
        input.fileHandleForWriting.write(requestData)

        let waitResult = semaphore.wait(timeout: .now() + 20)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        if waitResult == .timedOut { throw SessionHistoryError.timeout }
        if let responseError { throw responseError }
    }

    private static func threadListRequest(id: Int, cursor: String?, limit: Int, archived: Bool) -> Data {
        let params: [String: Any] = [
            "cursor": cursor ?? NSNull(),
            "limit": limit,
            "sortKey": "recency_at",
            "sortDirection": "desc",
            "modelProviders": [],
            "sourceKinds": ["appServer", "cli", "vscode", "unknown"],
            "archived": archived,
            "useStateDbOnly": true
        ]
        let object: [String: Any] = ["method": "thread/list", "id": id, "params": params]
        var data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        data.append(0x0A)
        return data
    }

    private static func parsePage(_ object: [String: Any], archived: Bool) throws -> (sessions: [CodexSessionSummary], nextCursor: String?) {
        guard let result = object["result"] as? [String: Any],
              let data = result["data"] as? [[String: Any]] else {
            throw SessionHistoryError.invalidResponse
        }

        let sessions: [CodexSessionSummary] = data.compactMap { value -> CodexSessionSummary? in
            guard let id = value["id"] as? String else { return nil }
            let preview = (value["preview"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = (value["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let created = (value["createdAt"] as? NSNumber)?.doubleValue ?? 0
            let updated = (value["updatedAt"] as? NSNumber)?.doubleValue ?? created
            return CodexSessionSummary(
                id: id,
                title: name?.isEmpty == false ? name! : (preview.isEmpty ? "未命名会话" : preview),
                preview: preview,
                modelProvider: value["modelProvider"] as? String ?? "unknown",
                cwd: value["cwd"] as? String,
                createdAt: Date(timeIntervalSince1970: created),
                updatedAt: Date(timeIntervalSince1970: updated),
                isArchived: (value["archived"] as? Bool) ?? archived
            )
        }
        return (sessions, result["nextCursor"] as? String)
    }
}
