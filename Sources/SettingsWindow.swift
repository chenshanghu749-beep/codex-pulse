import AppKit
import Foundation

@MainActor
final class SettingsWindowController: NSWindowController {
    weak var appDelegate: AppDelegate?
    private let routeControl = NSSegmentedControl(
        labels: ["OpenAI 官方", "CodeAPI"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let routeDescription = NSTextField(wrappingLabelWithString: "")
    private let keyLabel = NSTextField(labelWithString: "CodeAPI Key")
    private let keyField = NSSecureTextField()
    private let keyHelp = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let confirmButton = NSButton(title: "确认并打开 ChatGPT", target: nil, action: nil)

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodeAPI Status 路由设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "选择 ChatGPT / Codex 路由")
        title.font = .systemFont(ofSize: 21, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString: "切换后会安全更新 ~/.codex/config.toml，并自动重新打开 ChatGPT。原配置会保留备份。")
        subtitle.textColor = .secondaryLabelColor

        routeControl.target = self
        routeControl.action = #selector(routeChanged)
        routeControl.selectedSegment = 0
        routeControl.setWidth(190, forSegment: 0)
        routeControl.setWidth(190, forSegment: 1)

        routeDescription.textColor = .secondaryLabelColor

        keyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        keyField.placeholderString = "sk-…"
        keyHelp.stringValue = "密钥保存在仅当前用户可读的本地文件中（权限 600），不会触发系统授权弹窗。"
        keyHelp.textColor = .secondaryLabelColor
        keyHelp.font = .systemFont(ofSize: 11)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)

        confirmButton.target = self
        confirmButton.action = #selector(confirmSelection)
        confirmButton.keyEquivalent = "\r"
        confirmButton.bezelStyle = .rounded

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(closeWindow))
        cancelButton.bezelStyle = .rounded

        let buttonRow = NSView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(cancelButton)
        buttonRow.addSubview(confirmButton)
        NSLayoutConstraint.activate([
            buttonRow.heightAnchor.constraint(equalToConstant: 32),
            confirmButton.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor),
            confirmButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor)
        ])

        let stack = NSStackView(views: [
            title, subtitle, routeControl, routeDescription,
            keyLabel, keyField, keyHelp, statusLabel, buttonRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        [subtitle, routeDescription, keyField, keyHelp, statusLabel, buttonRow].forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        updateRouteFields()
    }

    func present() {
        let route = RouteConfigManager.currentRoute()
        routeControl.selectedSegment = route == .official ? 0 : 1
        keyField.stringValue = CredentialStore.load() ?? ""
        statusLabel.stringValue = ""
        confirmButton.isEnabled = true
        confirmButton.title = "确认并打开 ChatGPT"
        updateRouteFields()

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        if route == .codeAPI { window?.makeFirstResponder(keyField) }
    }

    @objc private func routeChanged() {
        statusLabel.stringValue = ""
        updateRouteFields()
    }

    private func updateRouteFields() {
        let codeAPI = routeControl.selectedSegment == 1
        routeDescription.stringValue = codeAPI
            ? "请求将发送到 https://codeapi.nexita.net，状态栏显示钱包余额。"
            : "使用 ChatGPT 登录态和 OpenAI 官方路由，状态栏显示官方配额剩余。"
        keyLabel.isHidden = !codeAPI
        keyField.isHidden = !codeAPI
        keyHelp.isHidden = !codeAPI
    }

    @objc private func closeWindow() { window?.close() }

    @objc private func confirmSelection() {
        let route: RouteChoice = routeControl.selectedSegment == 1 ? .codeAPI : .official
        confirmButton.isEnabled = false
        confirmButton.title = route == .codeAPI ? "正在验证…" : "正在切换…"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = route == .codeAPI ? "正在验证 CodeAPI Key…" : "正在更新官方路由…"

        Task {
            do {
                var usage: UsageResponse?
                if route == .codeAPI {
                    let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { throw APIError.invalidKey }
                    usage = try await CodeAPIClient.fetch(key: key)
                    try CredentialStore.save(key)
                }

                try RouteConfigManager.apply(route)
                appDelegate?.routeDidChange(to: route, validatedCodeUsage: usage)
                statusLabel.textColor = .systemGreen
                statusLabel.stringValue = "已切换到 \(route.displayName)，正在打开 ChatGPT…"
                confirmButton.title = "切换成功"
                window?.close()
                try await ChatGPTLauncher.restart()
            } catch {
                showError(error.localizedDescription)
                confirmButton.isEnabled = true
                confirmButton.title = "确认并打开 ChatGPT"
            }
        }
    }

    private func showError(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
    }
}
