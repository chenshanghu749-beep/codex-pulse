import Foundation

enum TaskRunState: Sendable, Equatable {
    case running(Int)
    case waiting(Int)
    case ready
}

struct TaskActivitySnapshot: Sendable {
    let state: TaskRunState
    let changedAt: Date?
}

enum TaskActivityReader {
    private struct FileState {
        var state: TaskRunState
        var timestamp: Date
        var pendingTools: Int
    }

    private struct CacheEntry {
        let size: UInt64
        let fileState: FileState?
    }

    private struct FileReadResult {
        let fileState: FileState
        let sawToolCall: Bool
    }

    private static let cacheLock = NSLock()
    private static var cache: [String: CacheEntry] = [:]

    static func read(root customRoot: URL? = nil) -> TaskActivitySnapshot {
        let root = customRoot ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return TaskActivitySnapshot(state: .ready, changedAt: nil) }

        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= cutoff else { continue }
            files.append((url, modified))
        }

        let results = files
            .sorted { $0.1 > $1.1 }
            .prefix(40)
            .compactMap { readState(from: $0.0, fallbackDate: $0.1) }
        let states = results.map(\.fileState)

        let waiting = states.filter {
            if case .waiting = $0.state { return true }
            return false
        }
        if !waiting.isEmpty {
            return TaskActivitySnapshot(state: .waiting(waiting.count), changedAt: waiting.map(\.timestamp).max())
        }

        let recentToolActivity = results.filter {
            $0.sawToolCall && $0.fileState.state != .ready
        }
        if !recentToolActivity.isEmpty {
            return TaskActivitySnapshot(
                state: .waiting(recentToolActivity.count),
                changedAt: recentToolActivity.map(\.fileState.timestamp).max()
            )
        }

        let running = states.filter {
            if case .running = $0.state { return true }
            return false
        }
        if !running.isEmpty {
            return TaskActivitySnapshot(state: .running(running.count), changedAt: running.map(\.timestamp).max())
        }

        if let ready = states
            .filter({ $0.state == .ready })
            .max(by: { $0.timestamp < $1.timestamp }) {
            return TaskActivitySnapshot(state: .ready, changedAt: ready.timestamp)
        }
        return TaskActivitySnapshot(state: .ready, changedAt: nil)
    }

    private static func readState(from url: URL, fallbackDate: Date) -> FileReadResult? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        cacheLock.lock()
        let cached = cache[url.path]
        cacheLock.unlock()

        let canContinue = cached != nil && size >= cached!.size
        let offset = canContinue ? cached!.size : 0
        try? handle.seek(toOffset: offset)
        let data: Data
        do {
            data = try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }

        let completeLength: Int
        if let lastNewline = data.lastIndex(of: 0x0A) {
            completeLength = data.distance(from: data.startIndex, to: lastNewline) + 1
        } else {
            completeLength = 0
        }
        let completeData = data.prefix(completeLength)
        guard let text = String(data: completeData, encoding: .utf8) else { return nil }

        var latest = canContinue ? cached?.fileState : nil
        var sawToolCall = false
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { continue }

            let timestamp = (object["timestamp"] as? String).flatMap(parseDate) ?? fallbackDate
            switch object["type"] as? String {
            case "event_msg":
                switch type {
                case "task_started":
                    latest = FileState(state: .running(1), timestamp: timestamp, pendingTools: 0)
                case "task_complete", "task_cancelled", "turn_aborted":
                    latest = FileState(state: .ready, timestamp: timestamp, pendingTools: 0)
                default:
                    continue
                }
            case "response_item":
                guard var state = latest else { continue }
                switch type {
                case "custom_tool_call", "function_call":
                    guard state.state != .ready else { continue }
                    sawToolCall = true
                    state.pendingTools += 1
                    state.state = .waiting(1)
                    state.timestamp = timestamp
                    latest = state
                case "custom_tool_call_output", "function_call_output":
                    guard state.state != .ready else { continue }
                    state.pendingTools = max(0, state.pendingTools - 1)
                    state.state = state.pendingTools > 0 ? .waiting(1) : .running(1)
                    state.timestamp = timestamp
                    latest = state
                default:
                    continue
                }
            default:
                continue
            }
        }

        cacheLock.lock()
        cache[url.path] = CacheEntry(size: offset + UInt64(completeLength), fileState: latest)
        cacheLock.unlock()
        guard let latest else { return nil }
        return FileReadResult(fileState: latest, sawToolCall: sawToolCall)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
