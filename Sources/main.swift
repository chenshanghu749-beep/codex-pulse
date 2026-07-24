import AppKit
import Foundation

let usageURL = URL(string: "https://codeapi.nexita.net/v1/usage")!
let dashboardURL = URL(string: "https://codeapi.nexita.net/dashboard")!

struct UsageResponse: Codable {
    let balance: Double
    let dailyUsage: [DailyUsage]?
    let isValid: Bool
    let mode: String?
    let modelStats: [ModelStat]?
    let planName: String?
    let remaining: Double?
    let unit: String?
    let usage: UsageSummary

    enum CodingKeys: String, CodingKey {
        case balance
        case dailyUsage = "daily_usage"
        case isValid
        case mode
        case modelStats = "model_stats"
        case planName
        case remaining
        case unit
        case usage
    }
}

struct DailyUsage: Codable {
    let date: String
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let actualCost: Double

    enum CodingKeys: String, CodingKey {
        case date, requests
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case totalTokens = "total_tokens"
        case actualCost = "actual_cost"
    }
}

struct ModelStat: Codable {
    let model: String
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let cost: Double
    let actualCost: Double

    enum CodingKeys: String, CodingKey {
        case model, requests, cost
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case totalTokens = "total_tokens"
        case actualCost = "actual_cost"
    }
}

struct UsageSummary: Codable {
    let averageDurationMs: Double
    let rpm: Int?
    let tpm: Int?
    let today: UsagePeriod
    let total: UsagePeriod

    enum CodingKeys: String, CodingKey {
        case averageDurationMs = "average_duration_ms"
        case rpm, tpm, today, total
    }
}

struct UsagePeriod: Codable {
    let actualCost: Double
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
    let requests: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case actualCost = "actual_cost"
        case cacheCreationTokens = "cache_creation_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cost
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case requests
        case totalTokens = "total_tokens"
    }
}

enum APIError: LocalizedError {
    case invalidKey
    case server(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "API Key 无效，请检查后重试。"
        case let .server(code, message): return "服务返回错误（HTTP \(code)）：\(message)"
        case .invalidResponse: return "接口返回了无法识别的数据。"
        }
    }
}

enum CodeAPIClient {
    static func fetch(key: String) async throws -> UsageResponse {
        var request = URLRequest(url: usageURL)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw APIError.invalidKey }
            let body = String(data: data, encoding: .utf8) ?? "未知错误"
            throw APIError.server(http.statusCode, body)
        }
        let value = try JSONDecoder().decode(UsageResponse.self, from: data)
        guard value.isValid else { throw APIError.invalidKey }
        return value
    }
}

#if false
@MainActor
final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate {
    weak var appDelegate: AppDelegate?
    private let keyField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "保存并验证", target: nil, action: nil)

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Pulse 设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "连接 CodeAPI")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let help = NSTextField(wrappingLabelWithString: "输入 API Key。密钥只会保存在当前 Mac 的系统钥匙串中。")
        help.textColor = .secondaryLabelColor

        let keyLabel = NSTextField(labelWithString: "API Key")
        keyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        keyField.placeholderString = "sk-…"
        keyField.stringValue = KeychainStore.load() ?? ""
        keyField.delegate = self

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        saveButton.target = self
        saveButton.action = #selector(saveAndVerify)
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(closeWindow))
        cancelButton.bezelStyle = .rounded

        let buttons = NSView()
        buttons.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        buttons.addSubview(cancelButton)
        buttons.addSubview(saveButton)
        NSLayoutConstraint.activate([
            buttons.heightAnchor.constraint(equalToConstant: 32),
            saveButton.trailingAnchor.constraint(equalTo: buttons.trailingAnchor),
            saveButton.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: buttons.centerYAnchor)
        ])

        let stack = NSStackView(views: [title, help, keyLabel, keyField, statusLabel, buttons])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        keyField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        help.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
    }

    func present() {
        keyField.stringValue = KeychainStore.load() ?? ""
        statusLabel.stringValue = ""
        saveButton.isEnabled = true
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(keyField)
    }

    @objc private func closeWindow() { window?.close() }

    @objc private func saveAndVerify() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            showError("请输入 API Key。")
            return
        }
        saveButton.isEnabled = false
        saveButton.title = "正在验证…"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在连接 CodeAPI…"

        Task {
            do {
                let usage = try await CodeAPIClient.fetch(key: key)
                try KeychainStore.save(key)
                appDelegate?.acceptValidatedUsage(usage)
                statusLabel.textColor = .systemGreen
                statusLabel.stringValue = "验证成功，已保存到系统钥匙串。"
                saveButton.title = "已保存"
                try? await Task.sleep(for: .milliseconds(550))
                window?.close()
            } catch {
                showError(error.localizedDescription)
                saveButton.isEnabled = true
                saveButton.title = "保存并验证"
            }
        }
    }

    private func showError(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?
    private var latestUsage: UsageResponse?
    private var latestError: String?
    private var lastUpdated: Date?
    private var isRefreshing = false
    private lazy var preferences = PreferencesWindowController(appDelegate: self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        configureStatusButton(title: "CodeAPI …", symbol: "chart.bar.fill")
        rebuildMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)

        if KeychainStore.load() == nil {
            configureStatusButton(title: "CodeAPI 设置", symbol: "key.fill")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.preferences.present()
            }
        } else {
            Task { await refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func configureStatusButton(title: String, symbol: String) {
        guard let button = statusItem.button else { return }
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "CodeAPI")
        button.imagePosition = .imageLeading
        button.toolTip = "CodeAPI 使用情况"
    }

    func acceptValidatedUsage(_ usage: UsageResponse) {
        latestUsage = usage
        latestError = nil
        lastUpdated = Date()
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func manualRefresh() { Task { await refresh() } }

    private func refresh() async {
        guard !isRefreshing else { return }
        guard let key = KeychainStore.load(), !key.isEmpty else {
            latestError = "尚未配置 API Key"
            configureStatusButton(title: "CodeAPI 设置", symbol: "key.fill")
            rebuildMenu()
            return
        }

        isRefreshing = true
        rebuildMenu()
        defer { isRefreshing = false; rebuildMenu() }
        do {
            let usage = try await CodeAPIClient.fetch(key: key)
            acceptValidatedUsage(usage)
        } catch {
            latestError = error.localizedDescription
            if latestUsage == nil {
                configureStatusButton(title: "CodeAPI ⚠︎", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func updateStatusTitle() {
        guard let data = latestUsage else { return }
        configureStatusButton(
            title: "\(money(data.balance)) · 今日 \(money(data.usage.today.actualCost))",
            symbol: "chart.bar.fill"
        )
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if let data = latestUsage {
            menu.addItem(info("余额  \(money(data.balance))", emphasis: true))
            menu.addItem(info("今日费用  \(money(data.usage.today.actualCost))"))
            menu.addItem(.separator())

            let todayItem = NSMenuItem(title: "今日用量", action: nil, keyEquivalent: "")
            let todayMenu = NSMenu()
            todayMenu.addItem(info("请求  \(number(data.usage.today.requests)) 次"))
            todayMenu.addItem(info("总 Token  \(number(data.usage.today.totalTokens))"))
            todayMenu.addItem(info("输入  \(number(data.usage.today.inputTokens))"))
            todayMenu.addItem(info("输出  \(number(data.usage.today.outputTokens))"))
            todayMenu.addItem(info("缓存读取  \(number(data.usage.today.cacheReadTokens))"))
            todayItem.submenu = todayMenu
            menu.addItem(todayItem)

            let totalItem = NSMenuItem(title: "累计用量", action: nil, keyEquivalent: "")
            let totalMenu = NSMenu()
            totalMenu.addItem(info("实际费用  \(money(data.usage.total.actualCost))"))
            totalMenu.addItem(info("请求  \(number(data.usage.total.requests)) 次"))
            totalMenu.addItem(info("总 Token  \(number(data.usage.total.totalTokens))"))
            totalMenu.addItem(info(String(format: "平均响应  %.2f 秒", data.usage.averageDurationMs / 1000)))
            totalItem.submenu = totalMenu
            menu.addItem(totalItem)

            if let stats = data.modelStats, !stats.isEmpty {
                let modelsItem = NSMenuItem(title: "模型统计", action: nil, keyEquivalent: "")
                let modelsMenu = NSMenu()
                for model in stats.sorted(by: { $0.actualCost > $1.actualCost }) {
                    let item = NSMenuItem(title: model.model, action: nil, keyEquivalent: "")
                    let detail = NSMenu()
                    detail.addItem(info("费用  \(money(model.actualCost))"))
                    detail.addItem(info("请求  \(number(model.requests)) 次"))
                    detail.addItem(info("Token  \(number(model.totalTokens))"))
                    item.submenu = detail
                    modelsMenu.addItem(item)
                }
                modelsItem.submenu = modelsMenu
                menu.addItem(modelsItem)
            }

            menu.addItem(.separator())
            if let plan = data.planName { menu.addItem(info("方案  \(plan)")) }
            if let mode = data.mode { menu.addItem(info("模式  \(mode)")) }
        } else {
            menu.addItem(info("暂无使用数据"))
        }

        if let error = latestError {
            menu.addItem(.separator())
            let item = info("⚠︎ \(error)")
            item.attributedTitle = NSAttributedString(
                string: item.title,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if let date = lastUpdated {
            menu.addItem(info("更新于 \(timeFormatter.string(from: date)) · 每分钟自动刷新"))
        } else {
            menu.addItem(info("每分钟自动刷新"))
        }

        let refresh = NSMenuItem(title: isRefreshing ? "正在刷新…" : "立即刷新", action: #selector(manualRefresh), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !isRefreshing
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "设置 API Key…", action: #selector(openPreferences), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let dashboard = NSMenuItem(title: "打开 CodeAPI 控制台", action: #selector(openDashboard), keyEquivalent: "")
        dashboard.target = self
        menu.addItem(dashboard)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Codex Pulse", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func info(_ title: String, emphasis: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if emphasis {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)]
            )
        }
        return item
    }

    @objc private func openPreferences() { preferences.present() }
    @objc private func openDashboard() { NSWorkspace.shared.open(dashboardURL) }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func money(_ value: Double) -> String { String(format: "$%.2f", value) }

    private func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
#endif

if CommandLine.arguments.contains("--login-status-test") {
    print("LOGIN_STATUS \(OfficialUsageClient.loginStatusDiagnostic())")
} else if CommandLine.arguments.contains("--task-state-test") {
    let snapshot = TaskActivityReader.read()
    switch snapshot.state {
    case let .running(count): print("TASK_STATE_OK running=\(count)")
    case let .waiting(count): print("TASK_STATE_OK waiting=\(count)")
    case .ready: print("TASK_STATE_OK ready")
    }
} else if CommandLine.arguments.contains("--official-usage-test") {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let snapshot = try await OfficialUsageClient.fetch()
            let remaining = snapshot.primary?.remainingPercent ?? -1
            print(String(format: "OFFICIAL_USAGE_OK loggedIn=%@ remaining=%.0f", snapshot.isLoggedIn ? "yes" : "no", remaining))
        } catch {
            print("OFFICIAL_USAGE_ERROR \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
} else if CommandLine.arguments.contains("--session-history-test") {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let sessions = try await SessionHistoryClient.fetch()
            let providerCounts = Dictionary(grouping: sessions, by: \.modelProvider)
                .map { "\($0.key)=\($0.value.count)" }
                .sorted()
                .joined(separator: ",")
            print("SESSION_HISTORY_OK count=\(sessions.count) providers=\(providerCounts)")
        } catch {
            print("SESSION_HISTORY_ERROR \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
} else if CommandLine.arguments.contains("--repair-route-config") {
    do {
        let route = RouteConfigManager.currentRoute()
        try RouteConfigManager.apply(route)
        print("ROUTE_CONFIG_REPAIRED \(route.displayName)")
    } catch {
        FileHandle.standardError.write(Data("ROUTE_CONFIG_REPAIR_ERROR \(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
} else if CommandLine.arguments.contains("--self-test") {
    let sample = """
    model = "gpt-5.6-sol"
    model_provider = "legacy"

    [mcp_servers.example]
    command = "example"
    """
    let provider = ProviderProfile(
        id: "test-provider",
        name: "Test \"Provider\"",
        baseURL: "https://api.example.com/v1",
        model: "custom-model"
    )
    let custom = RouteConfigManager.render(sample, route: .provider(provider.id), profile: provider)
    precondition(custom.hasPrefix("model_provider = \"openai\""))
    precondition(custom.contains("model = \"custom-model\""))
    precondition(custom.contains("openai_base_url = \"https://api.example.com/v1\""))
    precondition(custom.contains("name = \"Test \\\"Provider\\\"\""))
    precondition(custom.contains("base_url = \"https://api.example.com/v1\""))
    precondition(custom.contains("[mcp_servers.example]"))
    precondition(custom.contains("command = \"/bin/cat\""))
    precondition(custom.contains("test-provider.key"))
    precondition(custom.contains("[model_providers.codeapi_status_custom]"))
    precondition(!custom.contains("model_provider = \"legacy\""))

    let sameNameProvider = ProviderProfile(
        id: "same-name-provider",
        name: provider.name,
        baseURL: "https://second.example.com/v1",
        model: "second-model"
    )
    precondition(ProviderStore.hasNameCollision(
        "  TEST \"PROVIDER\"  ",
        excluding: sameNameProvider.id,
        in: [provider]
    ))
    let duplicateTitles = ProviderStore.popupTitles(for: [provider, sameNameProvider])
    precondition(duplicateTitles.count == 2)
    precondition(duplicateTitles[0] != duplicateTitles[1])
    let sameNameConfig = RouteConfigManager.render(
        sample,
        route: .provider(sameNameProvider.id),
        profile: sameNameProvider,
        profiles: [provider, sameNameProvider],
        legacyProfile: sameNameProvider
    )
    precondition(sameNameConfig.hasPrefix("model_provider = \"openai\""))
    precondition(sameNameConfig.contains(
        "openai_base_url = \"https://second.example.com/v1\""
    ))
    precondition(sameNameConfig.contains(
        "[model_providers.codeapi_status_provider_test-provider]"
    ))
    precondition(sameNameConfig.contains(
        "[model_providers.codeapi_status_provider_same-name-provider]"
    ))
    try! RouteConfigManager.validate(sameNameConfig)

    let official = RouteConfigManager.render(
        custom,
        route: .official,
        profiles: [provider],
        legacyProfile: provider,
        officialModel: "gpt-5.6-sol"
    )
    precondition(official.hasPrefix("model_provider = \"openai\""))
    precondition(official.contains("model = \"gpt-5.6-sol\""))
    precondition(!official.contains("openai_base_url ="))
    precondition(official.contains(RouteConfigManager.beginMarker))
    precondition(official.contains("[model_providers.codeapi_status_provider_test-provider]"))
    precondition(official.contains("[mcp_servers.example]"))

    let codeAPIConfig = RouteConfigManager.render(
        sample,
        route: .provider("codeapi"),
        profile: .codeAPI,
        profiles: [.codeAPI],
        legacyProfile: .codeAPI
    )
    precondition(codeAPIConfig.hasPrefix("model_provider = \"openai\""))
    precondition(codeAPIConfig.contains("openai_base_url = \"https://codeapi.nexita.net\""))
    precondition(codeAPIConfig.contains("[model_providers.codeapi_status_custom]"))
    precondition(codeAPIConfig.contains("[model_providers.codeapi]"))
    precondition(codeAPIConfig.components(separatedBy: "[model_providers.codeapi]").count == 2)
    precondition(codeAPIConfig.components(separatedBy: "[model_providers.codeapi.auth]").count == 2)
    try! RouteConfigManager.validate(codeAPIConfig)

    let legacyCodeAPIConfig = """
    model_provider = "codeapi"
    model = "gpt-5.6-sol"

    [model_providers.codeapi]
    name = "codeapi"
    base_url = "https://codeapi.nexita.net"
    wire_api = "responses"
    requires_openai_auth = true

    [mcp_servers.example]
    command = "example"
    """
    let repairedCodeAPIConfig = RouteConfigManager.render(
        legacyCodeAPIConfig,
        route: .provider("codeapi"),
        profile: .codeAPI,
        profiles: [.codeAPI],
        legacyProfile: .codeAPI
    )
    precondition(repairedCodeAPIConfig.components(separatedBy: "[model_providers.codeapi]").count == 2)
    precondition(repairedCodeAPIConfig.components(separatedBy: "[model_providers.codeapi.auth]").count == 2)
    precondition(!repairedCodeAPIConfig.contains("requires_openai_auth"))
    precondition(repairedCodeAPIConfig.contains("[mcp_servers.example]"))
    try! RouteConfigManager.validate(repairedCodeAPIConfig)
    let rerenderedCodeAPIConfig = RouteConfigManager.render(
        repairedCodeAPIConfig,
        route: .provider("codeapi"),
        profile: .codeAPI,
        profiles: [.codeAPI],
        legacyProfile: .codeAPI
    )
    precondition(rerenderedCodeAPIConfig == repairedCodeAPIConfig)

    let deepSeek = ProviderProfile(
        id: "deepseek-test",
        name: "DeepSeek",
        baseURL: "https://api.deepseek.com",
        model: "deepseek-v4-pro"
    )
    let deepSeekConfig = RouteConfigManager.render(
        sample,
        route: .provider(deepSeek.id),
        profile: deepSeek,
        profiles: [deepSeek],
        legacyProfile: deepSeek
    )
    precondition(deepSeek.effectiveAPIFormat == .chatCompletions)
    precondition(deepSeekConfig.hasPrefix("model_provider = \"openai\""))
    precondition(deepSeekConfig.contains(
        "openai_base_url = \"http://127.0.0.1:37531/provider/deepseek-test\""
    ))
    precondition(deepSeekConfig.contains(
        "base_url = \"http://127.0.0.1:37531/provider/deepseek-test\""
    ))
    precondition(deepSeekConfig.contains("wire_api = \"responses\""))
    precondition(RouteConfigManager.detectedRoute(
        in: deepSeekConfig,
        profiles: [deepSeek],
        selectedProviderID: deepSeek.id
    ) == .provider(deepSeek.id))
    precondition(RouteConfigManager.detectedRoute(
        in: official,
        profiles: [provider],
        selectedProviderID: provider.id
    ) == .official)

    let providerKey = "provider-test-key"
    let providerAuth = try! JSONSerialization.data(withJSONObject: ["OPENAI_API_KEY": providerKey])
    let chatGPTAuth = try! JSONSerialization.data(withJSONObject: [
        "auth_mode": "chatgpt",
        "OPENAI_API_KEY": providerKey,
        "tokens": ["access_token": "official-access-token"]
    ])
    precondition(CodexAuthStore.kind(
        of: providerAuth,
        configuredProviderKeys: [providerKey]
    ) == .configuredProviderAPIKey)
    precondition(CodexAuthStore.kind(
        of: chatGPTAuth,
        configuredProviderKeys: [providerKey]
    ) == .chatGPT)
    let restorePlan = CodexAuthStore.officialPlan(
        currentData: providerAuth,
        backupData: chatGPTAuth,
        configuredProviderKeys: [providerKey]
    )
    guard case let .restoreBackup(restoredAuth) = restorePlan else {
        preconditionFailure("Expected official auth backup to be restored")
    }
    let restoredObject = try! JSONSerialization.jsonObject(with: restoredAuth) as! [String: Any]
    precondition(restoredObject["OPENAI_API_KEY"] is NSNull)
    precondition(CodexAuthStore.officialPlan(
        currentData: providerAuth,
        backupData: nil,
        configuredProviderKeys: [providerKey]
    ) == .removeCurrentAndRequireLogin)
    precondition(!OfficialUsageClient.loginStatusIndicatesChatGPT(
        "Logged in using an API key",
        terminationStatus: 0
    ))
    precondition(OfficialUsageClient.loginStatusUsesAPIKey("Logged in using an API key"))
    precondition(OfficialUsageClient.loginStatusIndicatesChatGPT(
        "Logged in using ChatGPT",
        terminationStatus: 0
    ))
    precondition(!OfficialUsageClient.loginStatusIndicatesChatGPT(
        "Not logged in",
        terminationStatus: 1
    ))

    for style in StatusIconStyle.allCases {
        for signal in TrafficSignal.allCases {
            for frame in [0, 6, 12, 18] {
                let icon = StatusIconRenderer.image(style: style, active: signal, frame: frame)
                precondition(icon.size.height == 18)
                precondition(icon.tiffRepresentation != nil)
            }
        }
    }

    let taskRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("codeapi-status-task-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: taskRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: taskRoot) }

    let timestamp = ISO8601DateFormatter().string(from: Date())
    func event(_ type: String) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\"}}\n"
    }
    func responseItem(_ type: String) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"response_item\",\"payload\":{\"type\":\"\(type)\"}}\n"
    }

    let completedSession = taskRoot.appendingPathComponent("completed.jsonl")
    try! Data(event("task_started").utf8).write(to: completedSession)
    precondition(TaskActivityReader.read(root: taskRoot).state == .running(1))
    let completedHandle = try! FileHandle(forWritingTo: completedSession)
    _ = try! completedHandle.seekToEnd()
    try! completedHandle.write(contentsOf: Data(responseItem("custom_tool_call").utf8))
    try! completedHandle.synchronize()
    precondition(TaskActivityReader.read(root: taskRoot).state == .waiting(1))
    try! completedHandle.write(contentsOf: Data(responseItem("custom_tool_call_output").utf8))
    try! completedHandle.synchronize()
    precondition(TaskActivityReader.read(root: taskRoot).state == .running(1))
    try! completedHandle.write(contentsOf: Data(event("task_complete").utf8))
    try! completedHandle.synchronize()
    try! completedHandle.close()
    precondition(TaskActivityReader.read(root: taskRoot).state == .ready)

    let instantToolSession = taskRoot.appendingPathComponent("instant-tool.jsonl")
    try! Data((
        event("task_started")
        + responseItem("custom_tool_call")
        + responseItem("custom_tool_call_output")
    ).utf8).write(to: instantToolSession)
    let instantFirst = TaskActivityReader.read(root: taskRoot).state
    let instantSecond = TaskActivityReader.read(root: taskRoot).state
    precondition(instantFirst == .waiting(1))
    precondition(instantSecond == .running(1))
    let instantHandle = try! FileHandle(forWritingTo: instantToolSession)
    _ = try! instantHandle.seekToEnd()
    try! instantHandle.write(contentsOf: Data(event("task_complete").utf8))
    try! instantHandle.close()
    precondition(TaskActivityReader.read(root: taskRoot).state == .ready)

    let abortedSession = taskRoot.appendingPathComponent("aborted.jsonl")
    try! Data((event("task_started") + event("turn_aborted")).utf8).write(to: abortedSession)
    precondition(TaskActivityReader.read(root: taskRoot).state == .ready)
    print("SELF_TEST_OK")
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
