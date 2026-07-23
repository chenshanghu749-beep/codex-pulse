import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let mainMenu = NSMenu()
    private let contextMenu = NSMenu()

    private var usageTimer: Timer?
    private var taskTimer: Timer?
    private var iconAnimationTimer: Timer?
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
    private var statusIconStyle = StatusIconPreference.selected
    private var displayedSignal: TrafficSignal = .green
    private var previousSignal: TrafficSignal = .green
    private var targetSignal: TrafficSignal = .green
    private var transitionStartedAt = Date.distantPast
    private var animationFrame = 0
    private lazy var settings = SettingsWindowController(appDelegate: self)
    private let chatCompletionsBridge = ChatCompletionsBridge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppThemePreference.apply(AppThemePreference.selected)
        installTextEditingCommands()
        ensureChatCompletionsBridge()

        do {
            _ = try RouteConfigManager.migrateLegacyCredentialCommandIfNeeded()
            _ = try RouteConfigManager.reconcileManagedProvidersIfNeeded()
        } catch {
            latestError = error.localizedDescription
        }
        route = RouteConfigManager.currentRoute()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "CodexPulseStatusItem"
        mainMenu.delegate = self
        configureStatusButton()
        startStartupChase()
        rebuildMainMenu()

        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshUsage() }
        }
        taskTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshTaskActivity() }
        }
        iconAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.animationFrame += 1
                self?.renderStatusButton()
            }
        }
        [usageTimer, taskTimer, iconAnimationTimer].compactMap { $0 }.forEach {
            RunLoop.main.add($0, forMode: .common)
        }

        updateWidget()
        Task {
            await refreshTaskActivity()
            await refreshUsage()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.settings.present()
        }
    }

    private func installTextEditingCommands() {
        let applicationMenu = NSMenu()
        let editRoot = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editRoot.submenu = editMenu
        applicationMenu.addItem(editRoot)
        NSApp.mainMenu = applicationMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageTimer?.invalidate()
        taskTimer?.invalidate()
        iconAnimationTimer?.invalidate()
        startupChaseTimer?.invalidate()
        chatCompletionsBridge.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.present()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === mainMenu { rebuildMainMenu() }
        if menu === contextMenu { rebuildContextMenu() }
    }

    func routeDidChange(to route: RouteChoice, validatedCodeUsage: UsageResponse?) {
        self.route = route
        latestError = nil
        lastUpdated = Date()
        latestCodeUsage = validatedCodeUsage
        latestOfficialUsage = nil
        startStartupChase()
        updateStatusTitle()
        rebuildMainMenu()
        updateWidget()
        Task { await refreshUsage() }
    }

    func statusIconStyleDidChange(to style: StatusIconStyle) {
        statusIconStyle = style
        StatusIconPreference.selected = style
        renderStatusButton()
        rebuildMainMenu()
    }

    func presentLaunchWarning(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "路由已切换，Codex 未能自动打开"
        alert.informativeText = "配置已经生效。你可以稍后手动打开 Codex。\n\n\(message)"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func presentOfficialLoginRequired() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "请重新登录 OpenAI 官方账号"
        alert.informativeText = "检测到 Codex 的认证文件中残留了第三方 API Key，已将它安全移出官方认证。请在 Codex 中登录一次，后续切换会自动备份和恢复官方登录。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func ensureChatCompletionsBridge() {
        do {
            try chatCompletionsBridge.start()
        } catch {
            latestError = error.localizedDescription
        }
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleNone
        button.font = .systemFont(ofSize: 12, weight: .medium)
        updateStatusTitle()
        renderStatusButton()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            rebuildContextMenu()
            showMenu(contextMenu)
        } else {
            rebuildMainMenu()
            showMenu(mainMenu)
        }
    }

    private func showMenu(_ menu: NSMenu) {
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 3), in: button)
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        let title: String
        switch route {
        case let .provider(id):
            let provider = ProviderStore.provider(id: id)
            if provider?.isCodeAPI == true, let data = latestCodeUsage {
                title = money(data.balance)
            } else {
                title = compact(provider?.name ?? "第三方")
            }
        case .official:
            if latestOfficialUsage?.isLoggedIn == false {
                title = "官方 · 未登录"
            } else if let window = latestOfficialUsage?.primary {
                title = "官方 \(percent(window.remainingPercent))"
            } else if latestOfficialUsage?.isLoggedIn == true {
                title = "官方 —"
            } else {
                title = "官方 …"
            }
        }
        button.title = title
        button.toolTip = "Codex Pulse · \(route.displayName)"
    }

    private func compact(_ value: String) -> String {
        value.count > 12 ? String(value.prefix(11)) + "…" : value
    }

    private func currentSignal() -> TrafficSignal {
        if let startupChaseIndex {
            return TrafficSignal.allCases[startupChaseIndex % TrafficSignal.allCases.count]
        }
        switch taskSnapshot.state {
        case .running: return .red
        case .waiting: return .yellow
        case .ready: return .green
        }
    }

    private func updateSignalTarget() {
        let newSignal = currentSignal()
        guard newSignal != targetSignal else { return }
        previousSignal = targetSignal
        targetSignal = newSignal
        transitionStartedAt = Date()
    }

    private func renderStatusButton() {
        guard let button = statusItem?.button else { return }
        updateSignalTarget()
        let elapsed = Date().timeIntervalSince(transitionStartedAt)
        let progress = min(1, max(0, elapsed / 0.28))
        let oldImage = StatusIconRenderer.image(style: statusIconStyle, active: previousSignal, frame: animationFrame)
        let newImage = StatusIconRenderer.image(style: statusIconStyle, active: targetSignal, frame: animationFrame)
        if progress >= 1 {
            displayedSignal = targetSignal
            button.image = newImage
        } else {
            button.image = StatusIconRenderer.blended(from: oldImage, to: newImage, progress: CGFloat(progress))
        }
        button.toolTip = "Codex Pulse · \(taskStatusText()) · \(route.displayName)"
    }

    private func taskStatusText() -> String {
        if startupChaseIndex != nil { return "正在检测任务状态" }
        switch taskSnapshot.state {
        case let .running(count): return count > 1 ? "\(count) 个会话执行中" : "会话执行中"
        case let .waiting(count): return count > 1 ? "\(count) 个会话等待中" : "等待工具或命令"
        case .ready: return "可以继续对话"
        }
    }

    @objc private func manualRefresh() { Task { await refreshUsage() } }

    private func refreshUsage() async {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        route = RouteConfigManager.currentRoute()
        rebuildMainMenu()
        defer {
            isRefreshingUsage = false
            rebuildMainMenu()
            updateWidget()
        }

        do {
            switch route {
            case let .provider(id):
                guard let provider = ProviderStore.provider(id: id) else {
                    latestError = "当前第三方提供商不存在"
                    updateStatusTitle()
                    return
                }
                guard let key = CredentialStore.load(providerID: id), !key.isEmpty else {
                    latestError = "\(provider.name) 尚未配置 API Key"
                    updateStatusTitle()
                    return
                }
                if provider.isCodeAPI { latestCodeUsage = try await CodeAPIClient.fetch(key: key) }
            case .official:
                latestOfficialUsage = try await OfficialUsageClient.fetch()
            }
            latestError = nil
            lastUpdated = Date()
        } catch {
            latestError = error.localizedDescription
        }
        updateStatusTitle()
    }

    private func rebuildMainMenu() {
        mainMenu.removeAllItems()
        mainMenu.addItem(info("Codex Pulse", emphasis: true))
        mainMenu.addItem(info("\(taskStatusText())  ·  \(route.displayName)"))
        mainMenu.addItem(.separator())

        switch route {
        case let .provider(id):
            if ProviderStore.provider(id: id)?.isCodeAPI == true { addCodeUsageMenu(to: mainMenu) }
            else { addProviderMenu(id: id, to: mainMenu) }
        case .official:
            addOfficialUsageMenu(to: mainMenu)
        }

        if let error = latestError {
            mainMenu.addItem(.separator())
            let item = info("⚠︎ \(error)")
            item.attributedTitle = NSAttributedString(string: item.title, attributes: [.foregroundColor: NSColor.systemRed])
            mainMenu.addItem(item)
        }

        mainMenu.addItem(.separator())
        mainMenu.addItem(info(lastUpdated.map { "更新于 \(timeFormatter.string(from: $0)) · 每分钟刷新" } ?? "每分钟自动刷新"))
        let refresh = NSMenuItem(title: isRefreshingUsage ? "正在刷新…" : "立即刷新", action: #selector(manualRefresh), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !isRefreshingUsage
        mainMenu.addItem(refresh)

        let settingsItem = NSMenuItem(title: "路由与设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        mainMenu.addItem(settingsItem)
        let widgetItem = NSMenuItem(title: "添加桌面组件…", action: #selector(openWidgetGuide), keyEquivalent: "")
        widgetItem.target = self
        mainMenu.addItem(widgetItem)

        let dashboardTitle: String
        switch route {
        case .official: dashboardTitle = "打开官方用量页面"
        case let .provider(id): dashboardTitle = ProviderStore.provider(id: id)?.isCodeAPI == true ? "打开 CodeAPI 控制台" : "打开提供商地址"
        }
        let dashboard = NSMenuItem(title: dashboardTitle, action: #selector(openUsageDashboard), keyEquivalent: "")
        dashboard.target = self
        mainMenu.addItem(dashboard)
        mainMenu.addItem(.separator())
        let open = NSMenuItem(title: "打开 Codex", action: #selector(openCodex), keyEquivalent: "")
        open.target = self
        mainMenu.addItem(open)
        let quit = NSMenuItem(title: "退出 Codex Pulse", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        mainMenu.addItem(quit)
    }

    private func rebuildContextMenu() {
        contextMenu.removeAllItems()
        contextMenu.delegate = self
        let widgetItem = NSMenuItem(title: "添加 macOS 桌面组件…", action: #selector(openWidgetGuide), keyEquivalent: "")
        widgetItem.target = self
        contextMenu.addItem(widgetItem)
        let refresh = NSMenuItem(title: "立即刷新用量", action: #selector(manualRefresh), keyEquivalent: "")
        refresh.target = self
        contextMenu.addItem(refresh)
        contextMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Codex Pulse 设置…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        contextMenu.addItem(settingsItem)
    }

    private func addCodeUsageMenu(to menu: NSMenu) {
        guard let data = latestCodeUsage else {
            menu.addItem(info("暂无 CodeAPI 用量数据"))
            return
        }
        menu.addItem(info("余额  \(money(data.balance))", emphasis: true))
        menu.addItem(info("今日费用  \(money(data.usage.today.actualCost))"))
        let todayItem = NSMenuItem(title: "今日用量", action: nil, keyEquivalent: "")
        let todayMenu = NSMenu()
        todayMenu.addItem(info("请求  \(number(data.usage.today.requests)) 次"))
        todayMenu.addItem(info("总 Token  \(number(data.usage.today.totalTokens))"))
        todayMenu.addItem(info("输入  \(number(data.usage.today.inputTokens))"))
        todayMenu.addItem(info("输出  \(number(data.usage.today.outputTokens))"))
        todayMenu.addItem(info("缓存读取  \(number(data.usage.today.cacheReadTokens))"))
        todayItem.submenu = todayMenu
        menu.addItem(todayItem)
    }

    private func addProviderMenu(id: String, to menu: NSMenu) {
        guard let provider = ProviderStore.provider(id: id) else {
            menu.addItem(info("提供商配置已不存在"))
            return
        }
        menu.addItem(info(provider.name, emphasis: true))
        menu.addItem(info("模型  \(provider.model)"))
        menu.addItem(info("地址  \(provider.baseURL)"))
        menu.addItem(info("该提供商未配置用量查询接口"))
    }

    private func addOfficialUsageMenu(to menu: NSMenu) {
        guard let data = latestOfficialUsage else {
            menu.addItem(info("正在读取 OpenAI 官方账号…"))
            return
        }
        guard data.isLoggedIn else {
            menu.addItem(info("OpenAI 官方账号未登录", emphasis: true))
            menu.addItem(info("路由已切换成功；登录 Codex 后即可显示用量。"))
            return
        }
        if data.primary == nil, data.secondary == nil, data.tokenUsage == nil {
            menu.addItem(info("官方用量暂不可用", emphasis: true))
            menu.addItem(info("请稍后重新刷新。"))
        }
        if let primary = data.primary {
            menu.addItem(info("\(primary.label)剩余  \(percent(primary.remainingPercent))", emphasis: true))
            menu.addItem(info("重置时间  \(resetFormatter.string(from: primary.resetsAt))"))
        }
        if let secondary = data.secondary {
            menu.addItem(info("\(secondary.label)剩余  \(percent(secondary.remainingPercent))"))
            menu.addItem(info("重置时间  \(resetFormatter.string(from: secondary.resetsAt))"))
        }
        if let tokens = data.tokenUsage {
            menu.addItem(.separator())
            if let today = tokens.todayTokens { menu.addItem(info("今日 Token  \(number(today))")) }
            if let lifetime = tokens.lifetimeTokens { menu.addItem(info("累计 Token  \(number(lifetime))")) }
            if let peak = tokens.peakDailyTokens { menu.addItem(info("单日峰值  \(number(peak))")) }
        }
        if let plan = data.planType { menu.addItem(info("方案  \(plan)")) }
        if let credits = data.resetCredits { menu.addItem(info("可用重置次数  \(credits)")) }
    }

    private func refreshTaskActivity() async {
        guard !isRefreshingTask else { return }
        isRefreshingTask = true
        let snapshot = await Task.detached(priority: .utility) { TaskActivityReader.read() }.value
        let shouldPlayCompletionChase: Bool
        switch (taskSnapshot.state, snapshot.state) {
        case (.running, .ready), (.waiting, .ready): shouldPlayCompletionChase = true
        default: shouldPlayCompletionChase = false
        }
        taskSnapshot = snapshot
        isRefreshingTask = false
        if shouldPlayCompletionChase { startStartupChase() }
        else { renderStatusButton() }
        rebuildMainMenu()
        updateWidget()
    }

    private func startStartupChase() {
        startupChaseTimer?.invalidate()
        startupChaseIndex = 0
        renderStatusButton()
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
                self.renderStatusButton()
            }
        }
        startupChaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateWidget() {
        CodexPulseWidgetStore.update(
            route: route,
            codeUsage: latestCodeUsage,
            officialUsage: latestOfficialUsage,
            task: taskSnapshot
        )
    }

    private func info(_ title: String, emphasis: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if emphasis {
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)])
        }
        return item
    }

    @objc private func openSettings() { settings.present() }

    @objc private func openWidgetGuide() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "添加 Codex Pulse 桌面组件"
        alert.informativeText = "在 macOS 桌面空白处点按右键，选择“编辑小组件”，搜索 Codex Pulse，然后把小号或中号组件拖到桌面。\n\n组件会展示当前路由、官方剩余用量或 CodeAPI 余额、Token 和任务状态。需要 macOS 14 或更高版本。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    @objc private func openUsageDashboard() {
        switch route {
        case .official:
            NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!)
        case let .provider(id):
            guard let provider = ProviderStore.provider(id: id) else { return }
            let url = provider.isCodeAPI ? dashboardURL : URL(string: provider.baseURL)
            if let url { NSWorkspace.shared.open(url) }
        }
    }

    @objc private func openCodex() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CodexLauncher.bundleIdentifier) else { return }
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
