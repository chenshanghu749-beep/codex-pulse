import Foundation
import Network

enum ProviderConnectionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(Int, String)
    case bridgeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Base URL 无效。"
        case .invalidResponse:
            return "提供商返回了无法识别的数据。"
        case let .server(code, message):
            return "请求失败（HTTP \(code)）：\(message)"
        case let .bridgeUnavailable(message):
            return "本地协议桥接启动失败：\(message)"
        }
    }
}

enum ProviderConnectionTester {
    static func test(profile: ProviderProfile, key: String) async throws -> String {
        let format = profile.effectiveAPIFormat
        let endpoint = try endpointURL(profile: profile, format: format)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Codex-Pulse/2.4.3", forHTTPHeaderField: "User-Agent")

        let body: [String: Any]
        switch format {
        case .chatCompletions:
            body = [
                "model": profile.model,
                "messages": [["role": "user", "content": "Reply with OK only."]],
                "max_tokens": 8,
                "stream": false
            ]
        case .responses, .automatic:
            body = [
                "model": profile.model,
                "input": "Reply with OK only.",
                "max_output_tokens": 16,
                "stream": false
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startedAt = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderConnectionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderConnectionError.server(http.statusCode, errorMessage(from: data))
        }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw ProviderConnectionError.invalidResponse
        }
        let duration = Date().timeIntervalSince(startedAt)
        let protocolName = format == .chatCompletions ? "Chat Completions · 本地桥接" : "Responses API"
        return String(format: "连接成功 · %@ · %.1f 秒", protocolName, duration)
    }

    static func endpointURL(profile: ProviderProfile, format: ProviderAPIFormat) throws -> URL {
        let base = profile.normalizedBaseURL
        let suffix = format == .chatCompletions ? "/chat/completions" : "/responses"
        if base.lowercased().hasSuffix(suffix) {
            guard let url = URL(string: base) else { throw ProviderConnectionError.invalidURL }
            return url
        }
        guard let url = URL(string: base + suffix) else { throw ProviderConnectionError.invalidURL }
        return url
    }

    static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return String(message.prefix(400))
        }
        return String(String(data: data, encoding: .utf8)?.prefix(400) ?? "未知错误")
    }
}

final class ChatCompletionsBridge {
    static let port: UInt16 = 37_531

    static func baseURL(providerID: String) -> String {
        "http://127.0.0.1:\(port)/provider/\(providerID)"
    }

    private let queue = DispatchQueue(label: "net.nexita.codex-pulse.chat-bridge", qos: .userInitiated)
    private var listener: NWListener?

    func start() throws {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: Self.port) else {
            throw ProviderConnectionError.bridgeUnavailable("端口无效")
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                NSLog("Codex Pulse chat bridge failed: %@", error.localizedDescription)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, complete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            if next.count > 12 * 1_024 * 1_024 {
                self.sendJSONError(connection, status: 413, message: "请求过大")
                return
            }
            if let request = self.parseRequest(next) {
                self.handle(request, connection: connection)
            } else if complete || error != nil {
                self.sendJSONError(connection, status: 400, message: "无法解析本地桥接请求")
            } else {
                self.receive(connection, buffer: next)
            }
        }
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let body: Data
    }

    private func parseRequest(_ data: Data) -> HTTPRequest? {
        let marker = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: marker),
              let header = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }
        let contentLength = lines.dropFirst().compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                return nil
            }
            return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }.first ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        return HTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            body: data.subdata(in: bodyStart..<(bodyStart + contentLength))
        )
    }

    private func handle(_ request: HTTPRequest, connection: NWConnection) {
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        let components = path.split(separator: "/").map(String.init)
        guard components.count == 3,
              components[0] == "provider",
              let profile = ProviderStore.provider(id: components[1]),
              profile.effectiveAPIFormat == .chatCompletions,
              let key = CredentialStore.load(providerID: profile.id),
              !key.isEmpty else {
            sendJSONError(connection, status: 404, message: "没有找到对应的 Chat Completions 提供商")
            return
        }
        if request.method == "GET", components[2] == "models" {
            let payload: [String: Any] = ["models": []]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            send(connection, status: 200, contentType: "application/json", body: data)
            return
        }
        guard request.method == "POST", components[2] == "responses" else {
            sendJSONError(connection, status: 405, message: "该本地桥接路径不支持此请求")
            return
        }

        do {
            guard let responsesBody = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
                throw ProviderConnectionError.invalidResponse
            }
            let chatBody = try makeChatRequest(responsesBody, profile: profile)
            let endpoint = try ProviderConnectionTester.endpointURL(profile: profile, format: .chatCompletions)
            var upstream = URLRequest(url: endpoint)
            upstream.httpMethod = "POST"
            upstream.timeoutInterval = 180
            upstream.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            upstream.setValue("application/json", forHTTPHeaderField: "Content-Type")
            upstream.setValue("Codex-Pulse/2.4.3", forHTTPHeaderField: "User-Agent")
            upstream.httpBody = try JSONSerialization.data(withJSONObject: chatBody)

            URLSession.shared.dataTask(with: upstream) { [weak self] data, response, error in
                guard let self else { return }
                if let error {
                    self.sendJSONError(connection, status: 502, message: error.localizedDescription)
                    return
                }
                guard let data, let http = response as? HTTPURLResponse else {
                    self.sendJSONError(connection, status: 502, message: "上游没有返回有效响应")
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    self.sendJSONError(
                        connection,
                        status: http.statusCode,
                        message: ProviderConnectionTester.errorMessage(from: data)
                    )
                    return
                }
                do {
                    let sse = try self.makeResponsesStream(chatData: data, requestedModel: profile.model)
                    self.send(connection, status: 200, contentType: "text/event-stream", body: sse)
                } catch {
                    self.sendJSONError(connection, status: 502, message: error.localizedDescription)
                }
            }.resume()
        } catch {
            sendJSONError(connection, status: 400, message: error.localizedDescription)
        }
    }

    private func makeChatRequest(_ body: [String: Any], profile: ProviderProfile) throws -> [String: Any] {
        var messages: [[String: Any]] = []
        if let instructions = body["instructions"] as? String, !instructions.isEmpty {
            messages.append(["role": "system", "content": instructions])
        }
        if let input = body["input"] as? String {
            messages.append(["role": "user", "content": input])
        } else if let input = body["input"] as? [[String: Any]] {
            for item in input {
                let type = item["type"] as? String ?? "message"
                switch type {
                case "function_call":
                    let callID = item["call_id"] as? String ?? item["id"] as? String ?? UUID().uuidString
                    let name = item["name"] as? String ?? "tool"
                    let arguments = item["arguments"] as? String ?? "{}"
                    messages.append([
                        "role": "assistant",
                        "content": NSNull(),
                        "tool_calls": [[
                            "id": callID,
                            "type": "function",
                            "function": ["name": name, "arguments": arguments]
                        ]]
                    ])
                case "function_call_output":
                    messages.append([
                        "role": "tool",
                        "tool_call_id": item["call_id"] as? String ?? "",
                        "content": textContent(item["output"]) ?? ""
                    ])
                default:
                    let sourceRole = item["role"] as? String ?? "user"
                    let role = sourceRole == "developer" || sourceRole == "latest_reminder"
                        ? "system" : sourceRole
                    messages.append(["role": role, "content": textContent(item["content"]) ?? ""])
                }
            }
        }
        guard !messages.isEmpty else { throw ProviderConnectionError.invalidResponse }

        var chat: [String: Any] = [
            "model": body["model"] as? String ?? profile.model,
            "messages": messages,
            "stream": false
        ]
        if let maxTokens = body["max_output_tokens"] { chat["max_tokens"] = maxTokens }
        if let temperature = body["temperature"] { chat["temperature"] = temperature }
        if let topP = body["top_p"] { chat["top_p"] = topP }
        if let parallel = body["parallel_tool_calls"] { chat["parallel_tool_calls"] = parallel }
        if let tools = body["tools"] as? [[String: Any]] {
            let translated = tools.compactMap { tool -> [String: Any]? in
                guard tool["type"] as? String == "function",
                      let name = tool["name"] as? String else { return nil }
                var function: [String: Any] = ["name": name]
                if let description = tool["description"] { function["description"] = description }
                if let parameters = tool["parameters"] { function["parameters"] = parameters }
                if let strict = tool["strict"] { function["strict"] = strict }
                return ["type": "function", "function": function]
            }
            if !translated.isEmpty { chat["tools"] = translated }
        }
        return chat
    }

    private func textContent(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let parts = value as? [[String: Any]] else { return nil }
        let texts = parts.compactMap { part -> String? in
            let type = part["type"] as? String
            guard type == nil || type == "input_text" || type == "output_text" || type == "text" else {
                return nil
            }
            return part["text"] as? String
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    private func makeResponsesStream(chatData: Data, requestedModel: String) throws -> Data {
        guard let root = try JSONSerialization.jsonObject(with: chatData) as? [String: Any],
              let choice = (root["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else {
            throw ProviderConnectionError.invalidResponse
        }

        let responseID = "resp_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let model = root["model"] as? String ?? requestedModel
        let createdAt = root["created"] as? Int ?? Int(Date().timeIntervalSince1970)
        let usage = responsesUsage(root["usage"] as? [String: Any])
        var events: [[String: Any]] = []
        var output: [[String: Any]] = []

        func appendEvent(_ type: String, _ fields: [String: Any]) {
            var event = fields
            event["type"] = type
            event["sequence_number"] = events.count
            events.append(event)
        }

        appendEvent("response.created", [
            "response": responseObject(
                id: responseID, model: model, createdAt: createdAt,
                status: "in_progress", output: [], usage: NSNull()
            )
        ])
        appendEvent("response.in_progress", [
            "response": responseObject(
                id: responseID, model: model, createdAt: createdAt,
                status: "in_progress", output: [], usage: NSNull()
            )
        ])

        if let content = message["content"] as? String, !content.isEmpty {
            let itemID = "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
            let addedItem: [String: Any] = [
                "id": itemID, "type": "message", "status": "in_progress",
                "role": "assistant", "content": []
            ]
            appendEvent("response.output_item.added", ["output_index": output.count, "item": addedItem])
            let emptyPart: [String: Any] = [
                "type": "output_text", "text": "", "annotations": [], "logprobs": []
            ]
            appendEvent("response.content_part.added", [
                "item_id": itemID, "output_index": output.count, "content_index": 0, "part": emptyPart
            ])
            appendEvent("response.output_text.delta", [
                "item_id": itemID, "output_index": output.count, "content_index": 0,
                "delta": content, "logprobs": []
            ])
            appendEvent("response.output_text.done", [
                "item_id": itemID, "output_index": output.count, "content_index": 0,
                "text": content, "logprobs": []
            ])
            let finalPart: [String: Any] = [
                "type": "output_text", "text": content, "annotations": [], "logprobs": []
            ]
            appendEvent("response.content_part.done", [
                "item_id": itemID, "output_index": output.count, "content_index": 0, "part": finalPart
            ])
            let finalItem: [String: Any] = [
                "id": itemID, "type": "message", "status": "completed",
                "role": "assistant", "content": [finalPart]
            ]
            appendEvent("response.output_item.done", ["output_index": output.count, "item": finalItem])
            output.append(finalItem)
        }

        for toolCall in message["tool_calls"] as? [[String: Any]] ?? [] {
            guard let function = toolCall["function"] as? [String: Any],
                  let name = function["name"] as? String else { continue }
            let callID = toolCall["id"] as? String ?? "call_\(UUID().uuidString)"
            let arguments = function["arguments"] as? String ?? "{}"
            let itemID = "fc_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
            let item: [String: Any] = [
                "id": itemID, "type": "function_call", "status": "completed",
                "call_id": callID, "name": name, "arguments": arguments
            ]
            appendEvent("response.output_item.added", ["output_index": output.count, "item": item])
            appendEvent("response.function_call_arguments.delta", [
                "item_id": itemID, "output_index": output.count, "delta": arguments
            ])
            appendEvent("response.function_call_arguments.done", [
                "item_id": itemID, "output_index": output.count, "arguments": arguments
            ])
            appendEvent("response.output_item.done", ["output_index": output.count, "item": item])
            output.append(item)
        }

        guard !output.isEmpty else { throw ProviderConnectionError.invalidResponse }
        appendEvent("response.completed", [
            "response": responseObject(
                id: responseID, model: model, createdAt: createdAt,
                status: "completed", output: output, usage: usage
            )
        ])

        var result = Data()
        for event in events {
            let type = event["type"] as? String ?? "message"
            let json = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
            result.append(Data("event: \(type)\ndata: ".utf8))
            result.append(json)
            result.append(Data("\n\n".utf8))
        }
        return result
    }

    private func responseObject(
        id: String,
        model: String,
        createdAt: Int,
        status: String,
        output: [[String: Any]],
        usage: Any
    ) -> [String: Any] {
        [
            "id": id,
            "object": "response",
            "created_at": createdAt,
            "status": status,
            "background": false,
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "instructions": NSNull(),
            "max_output_tokens": NSNull(),
            "metadata": [:],
            "model": model,
            "output": output,
            "parallel_tool_calls": true,
            "previous_response_id": NSNull(),
            "reasoning": ["effort": NSNull(), "summary": NSNull()],
            "service_tier": "default",
            "store": false,
            "temperature": NSNull(),
            "text": ["format": ["type": "text"]],
            "tool_choice": "auto",
            "tools": [],
            "top_p": NSNull(),
            "truncation": "disabled",
            "usage": usage
        ]
    }

    private func responsesUsage(_ usage: [String: Any]?) -> [String: Any] {
        let input = usage?["prompt_tokens"] as? Int ?? 0
        let output = usage?["completion_tokens"] as? Int ?? 0
        return [
            "input_tokens": input,
            "input_tokens_details": ["cached_tokens": 0],
            "output_tokens": output,
            "output_tokens_details": ["reasoning_tokens": 0],
            "total_tokens": usage?["total_tokens"] as? Int ?? input + output
        ]
    }

    private func sendJSONError(_ connection: NWConnection, status: Int, message: String) {
        let payload: [String: Any] = [
            "error": ["message": String(message.prefix(600)), "type": "provider_error"]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        send(connection, status: status, contentType: "application/json", body: data)
    }

    private func send(_ connection: NWConnection, status: Int, contentType: String, body: Data) {
        let reason: String
        switch status {
        case 200..<300: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 413: reason = "Payload Too Large"
        default: reason = "Upstream Error"
        }
        let header = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-cache",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
