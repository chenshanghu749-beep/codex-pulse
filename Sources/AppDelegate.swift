import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var usageStatusItem: NSStatusItem!
    private var taskStatusItem: NSStatusItem!
    private let usageMenu = NSMenu()
    private let taskMenu = NSMenu()

    private var usageTimer: Timer?
    private var taskTimer: Timer?
    private var startupChaseTimer: Timer?
    private var startupChaseIndex: Int?
    private var route = RouteConfigManager.currentRoute()
    private var latestCodeUsage: UsageResponse?
    private var latestOfficialUsage: OfficialUsageSnapshot?
    private var latestError: String?
    private var lastUpdated: Date?
    private var isRefreshingUsage = false
    private var isRefreshingTask = false
    private var taskSnapshot = TaskActivitySnapshot(state: .ready, changedAt: nil)
    private lazy var settings = SettingsWindowController(appDelegate: self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            _ = try RouteConfigManager.migrateLegacyCredentialCommandIfNeeded()
        } catch {
            latestError = error.localizedDescription
        }
        route = RouteConfigManager.currentRoute()

        usageStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        usageStatusItem.menu = usageMenu
        usageMenu.delegate = self

        taskStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        taskStatusItem.menu = taskMenu
        taskMenu.delegate = self

        configureUsageButton(title: "用量 …", symbol: "chart.bar.fill")
        startStartupChase()
        rebuildUsageMenu()
        rebuildTaskMenu()

        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshUsage() }
        }
        taskTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshTaskActivity() }
        }
        [usageTimer, taskTimer].compactMap { $0 }.forEach {
            RunLoop.main.add($0, forMode: .common)
        }

        Task {
            await refreshTaskActivity()
            await refreshUsage()
        }

        if route == .codeAPI && CredentialStore.load() == nil {
            configureUsageButton(title: "CodeAPI 设置", symbol: "key.fill")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.settings.present()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageTimer?.invalidate()
        taskTimer?.invalidate()
        startupChaseTimer?.invalidate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.present()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === usageMenu { rebuildUsageMenu() }
        if menu === taskMenu { rebuildTaskMenu() }
    }

    func routeDidChange(to route: RouteChoice, validatedCodeUsage: UsageResponse?) {
        self.route = route
        latestError = nil
        lastUpdated = Date()
        if let validatedCodeUsage { latestCodeUsage = validatedCodeUsage }
        startStartupChase()
        updateUsageTitle()
        rebuildUsageMenu()
        Task { await refreshUsage() }
    }

    private func configureUsageButton(title: String, symbol: String) {
        guard let button = usageStatusItem.button else { return }
        button.title = title
        button.attributedTitle = NSAttributedString(string: title)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "用量")
        button.imagePosition = .imageLeading
        button.toolTip = "\(route.displayName) 用量"
    }

    private func updateUsageTitle() {
        switch route {
        case .codeAPI:
            if let data = latestCodeUsage {
                configureUsageButton(title: "\(money(data.balance))", symbol: "wallet.pass.fill")
            } else {
                configureUsageButton(title: "CodeAPI …", symbol: "wallet.pass.fill")
            }
        case .official:
            if let window = latestOfficialUsage?.primary {
                configureUsageButton(title: "官方 \(percent(window.remainingPercent)) 剩余", symbol: "gauge.with.dots.needle.50percent")
            } else {
                configureUsageButton(title: "官方用量 …", symbol: "gauge.with.dots.needle.50percent")
            }
        }
    }

    @objc private func manualRefresh() { Task { await refreshUsage() } }

    private func refreshUsage() async {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        route = RouteConfigManager.currentRoute()
        rebuildUsageMenu()
        defer { isRefreshingUsage = false; rebuildUsageMenu() }

        do {
            switch route {
            case .codeAPI:
                guard let key = CredentialStore.load(), !key.isEmpty else {
                    latestError = "CodeAPI 尚未配置 Key"
                    configureUsageButton(title: "CodeAPI 设置", symbol: "key.fill")
                    return
                }
                latestCodeUsage = try await CodeAPIClient.fetch(key: key)
            case .official:
                latestOfficialUsage = try await OfficialUsageClient.fetch()
            }
            latestError = nil
            lastUpdated = Date()
            updateUsageTitle()
        } catch {
            latestError = error.localizedDescription
            if latestCodeUsage == nil && latestOfficialUsage == nil {
                configureUsageButton(title: "用量 ⚠︎", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func rebuildUsageMenu() {
        usageMenu.removeAllItems()
        usageMenu.addItem(info("当前路由  \(route.displayName)", emphasis: true))
        usageMenu.addItem(.separator())

        switch route {
        case .codeAPI:
            addCodeUsageMenu()
        case .official:
            addOfficialUsageMenu()
        }

        if let error = latestError {
            usageMenu.addItem(.separator())
            let errorItem = info("⚠︎ \(error)")
            errorItem.attributedTitle = NSAttributedString(
                string: errorItem.title,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            usageMenu.addItem(errorItem)
        }

        usageMenu.addItem(.separator())
        if let lastUpdated {
            usageMenu.addItem(info("更新于 \(timeFormatter.string(from: lastUpdated)) · 每分钟刷新"))
        } else {
            usageMenu.addItem(info("每分钟自动刷新"))
        }

        let refresh = NSMenuItem(title: isRefreshingUsage ? "正在刷新…" : "立即刷新", action: #selector(manualRefresh), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !isRefreshingUsage
        usageMenu.addItem(refresh)

        let routeItem = NSMenuItem(title: "切换路由与设置…", action: #selector(openSettings), keyEquivalent: ",")
        routeItem.target = self
        usageMenu.addItem(routeItem)

        let dashboardTitle = route == .codeAPI ? "打开 CodeAPI 控制台" : "打开官方用量页面"
        let dashboard = NSMenuItem(title: dashboardTitle, action: #selector(openUsageDashboard), keyEquivalent: "")
        dashboard.target = self
        usageMenu.addItem(dashboard)

        usageMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 CodeAPI Status", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        usageMenu.addItem(quit)
    }

    private func addCodeUsageMenu() {
        guard let data = latestCodeUsage else {
            usageMenu.addItem(info("暂无 CodeAPI 用量数据"))
            return
        }
        usageMenu.addItem(info("余额  \(money(data.balance))", emphasis: true))
        usageMenu.addItem(info("今日费用  \(money(data.usage.today.actualCost))"))

        let todayItem = NSMenuItem(title: "今日用量", action: nil, keyEquivalent: "")
        let todayMenu = NSMenu()
        todayMenu.addItem(info("请求  \(number(data.usage.today.requests)) 次"))
        todayMenu.addItem(info("总 Token  \(number(data.usage.today.totalTokens))"))
        todayMenu.addItem(info("输入  \(number(data.usage.today.inputTokens))"))
        todayMenu.addItem(info("输出  \(number(data.usage.today.outputTokens))"))
        todayMenu.addItem(info("缓存读取  \(number(data.usage.today.cacheReadTokens))"))
        todayItem.submenu = todayMenu
        usageMenu.addItem(todayItem)

        if let stats = data.modelStats, !stats.isEmpty {
            let modelsItem = NSMenuItem(title: "模型统计", action: nil, keyEquivalent: "")
            let modelsMenu = NSMenu()
            for model in stats.sorted(by: { $0.actualCost > $1.actualCost }) {
                modelsMenu.addItem(info("\(model.model)  ·  \(money(model.actualCost))"))
            }
            modelsItem.submenu = modelsMenu
            usageMenu.addItem(modelsItem)
        }
    }

    private func addOfficialUsageMenu() {
        guard let data = latestOfficialUsage else {
            usageMenu.addItem(info("正在读取 OpenAI 官方用量…"))
            return
        }
        if let primary = data.primary {
            usageMenu.addItem(info("\(primary.label)剩余  \(percent(primary.remainingPercent))", emphasis: true))
            usageMenu.addItem(info("已使用  \(percent(primary.usedPercent))"))
            usageMenu.addItem(info("重置时间  \(resetFormatter.string(from: primary.resetsAt))"))
        }
        if let secondary = data.secondary {
            usageMenu.addItem(.separator())
            usageMenu.addItem(info("\(secondary.label)剩余  \(percent(secondary.remainingPercent))"))
            usageMenu.addItem(info("重置时间  \(resetFormatter.string(from: secondary.resetsAt))"))
        }
        if let plan = data.planType { usageMenu.addItem(info("方案  \(plan)")) }
        if let credits = data.resetCredits { usageMenu.addItem(info("可用重置次数  \(credits)")) }
    }

    private func refreshTaskActivity() async {
        guard !isRefreshingTask else { return }
        isRefreshingTask = true
        let snapshot = await Task.detached(priority: .utility) {
            TaskActivityReader.read()
        }.value
        let shouldPlayCompletionChase: Bool
        switch (taskSnapshot.state, snapshot.state) {
        case (.running, .ready), (.waiting, .ready):
            shouldPlayCompletionChase = true
        default:
            shouldPlayCompletionChase = false
        }
        taskSnapshot = snapshot
        isRefreshingTask = false
        if shouldPlayCompletionChase {
            startStartupChase()
        } else {
            updateTaskButton()
        }
        rebuildTaskMenu()
    }

    private func updateTaskButton() {
        guard let button = taskStatusItem.button else { return }
        let (signal, tooltip): (TrafficSignal, String)
        if let startupChaseIndex {
            signal = TrafficSignal.allCases[startupChaseIndex % TrafficSignal.allCases.count]
            tooltip = "正在检测 Codex 任务状态"
        } else {
            switch taskSnapshot.state {
            case let .running(count):
                signal = .red
                tooltip = count > 1 ? "\(count) 个会话执行中" : "会话执行中"
            case let .waiting(count):
                signal = .yellow
                tooltip = count > 1 ? "\(count) 个会话等待或执行命令" : "任务等待或命令执行中"
            case .ready:
                signal = .green
                tooltip = "可以继续对话"
            }
        }

        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = TrafficLightRenderer.image(active: signal)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = tooltip
    }

    private func startStartupChase() {
        startupChaseTimer?.invalidate()
        startupChaseIndex = 0
        updateTaskButton()

        let timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, let current = self.startupChaseIndex else {
                    timer.invalidate()
                    return
                }
                let next = current + 1
                if next >= 9 {
                    timer.invalidate()
                    self.startupChaseTimer = nil
                    self.startupChaseIndex = nil
                } else {
                    self.startupChaseIndex = next
                }
                self.updateTaskButton()
            }
        }
        startupChaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func rebuildTaskMenu() {
        taskMenu.removeAllItems()
        switch taskSnapshot.state {
        case let .running(count):
            taskMenu.addItem(info(count > 1 ? "\(count) 个会话正在执行" : "会话执行中", emphasis: true))
            taskMenu.addItem(info("红灯：模型正在处理任务"))
        case let .waiting(count):
            taskMenu.addItem(info(count > 1 ? "\(count) 个会话正在等待" : "任务等待或命令执行中", emphasis: true))
            taskMenu.addItem(info("黄灯：等待工具、命令或外部结果"))
        case .ready:
            taskMenu.addItem(info("可以继续对话", emphasis: true))
            taskMenu.addItem(info("绿灯：输入框可发送新消息"))
        }
        if let changedAt = taskSnapshot.changedAt {
            taskMenu.addItem(info("状态时间  \(timeFormatter.string(from: changedAt))"))
        }
        taskMenu.addItem(.separator())
        let open = NSMenuItem(title: "打开 ChatGPT", action: #selector(openChatGPT), keyEquivalent: "")
        open.target = self
        taskMenu.addItem(open)
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

    @objc private func openSettings() { settings.present() }

    @objc private func openUsageDashboard() {
        let url = route == .codeAPI
            ? dashboardURL
            : URL(string: "https://chatgpt.com/codex/settings/usage")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openChatGPT() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChatGPTLauncher.bundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private func money(_ value: Double) -> String { String(format: "$%.2f", value) }
    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value) }

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

    private lazy var resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
