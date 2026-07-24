import AppKit
import Foundation

private final class SettingsSidebarView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(calibratedWhite: 0.105, alpha: 1) : .white).cgColor
        layer?.borderColor = (dark
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.08)).cgColor
        layer?.borderWidth = 0.5
    }
}

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

enum AppThemePreference {
    private static let key = "appTheme"

    static var selected: AppTheme {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let theme = AppTheme(rawValue: raw) else { return .system }
            return theme
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    @MainActor
    static func apply(_ theme: AppTheme) {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private enum Section: Int, CaseIterable {
        case route, providers, appearance

        var title: String {
            switch self {
            case .route: return "路由"
            case .providers: return "提供商"
            case .appearance: return "状态与外观"
            }
        }

        var symbol: String {
            switch self {
            case .route: return "arrow.triangle.branch"
            case .providers: return "server.rack"
            case .appearance: return "circle.lefthalf.filled"
            }
        }
    }

    weak var appDelegate: AppDelegate?
    private var providers: [ProviderProfile] = []
    private var selectedProviderID: String?
    private var pages: [Section: NSView] = [:]
    private var sidebarButtons: [Section: NSButton] = [:]
    private let pageHost = NSView()

    private let routeControl = NSSegmentedControl(
        labels: ["OpenAI 官方", "第三方提供商"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let routeDescription = NSTextField(wrappingLabelWithString: "")
    private let routeProviderPopup = NSPopUpButton()
    private let providerPopup = NSPopUpButton()
    private let nameField = NSTextField()
    private let baseURLField = NSTextField()
    private let modelField = NSTextField()
    private let keyField = NSSecureTextField()
    private let protocolPopup = NSPopUpButton()
    private let testProviderButton = NSButton(title: "测试连接", target: nil, action: nil)
    private let iconStylePopup = NSPopUpButton()
    private let themePopup = NSPopUpButton()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let confirmButton = NSButton(title: "应用并打开 Codex", target: nil, action: nil)

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 720),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Pulse 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .windowBackgroundColor
                : .white
        }
        window.minSize = NSSize(width: 850, height: 650)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let sidebar = SettingsSidebarView()
        sidebar.wantsLayer = true
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)

        let appMark = NSImageView(image: NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)!)
        appMark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        appMark.contentTintColor = .labelColor
        let appName = NSTextField(labelWithString: "Codex Pulse")
        appName.font = .systemFont(ofSize: 14, weight: .semibold)
        let appRow = NSStackView(views: [appMark, appName])
        appRow.orientation = .horizontal
        appRow.alignment = .centerY
        appRow.spacing = 9

        let navigation = NSStackView()
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = 4
        for section in Section.allCases {
            let button = makeSidebarButton(section)
            sidebarButtons[section] = button
            navigation.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: navigation.widthAnchor).isActive = true
        }
        let sidebarStack = NSStackView(views: [appRow, navigation, NSView()])
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 23
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)
        navigation.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true

        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(main)

        pageHost.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(pageHost)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.isSelectable = true
        confirmButton.target = self
        confirmButton.action = #selector(confirmSelection)
        confirmButton.keyEquivalent = "\r"
        confirmButton.bezelStyle = .rounded
        let cancelButton = NSButton(title: "取消", target: self, action: #selector(closeWindow))
        let footer = NSStackView(views: [statusLabel, NSView(), cancelButton, confirmButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 9
        footer.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(footer)

        let footerLine = NSBox()
        footerLine.boxType = .separator
        footerLine.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(footerLine)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 210),

            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 15),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -15),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 52),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18),

            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            main.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            main.topAnchor.constraint(equalTo: content.topAnchor),
            main.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            pageHost.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            pageHost.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            pageHost.topAnchor.constraint(equalTo: main.topAnchor),
            pageHost.bottomAnchor.constraint(equalTo: footerLine.topAnchor),

            footerLine.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            footerLine.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            footerLine.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 28),
            footer.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -28),
            footer.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -17),
            footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 330)
        ])

        configureControls()
        pages[.route] = buildRoutePage()
        pages[.providers] = buildProvidersPage()
        pages[.appearance] = buildAppearancePage()
        selectSection(.route)
    }

    private func configureControls() {
        routeControl.target = self
        routeControl.action = #selector(routeChanged)
        routeControl.setWidth(142, forSegment: 0)
        routeControl.setWidth(142, forSegment: 1)
        routeProviderPopup.target = self
        routeProviderPopup.action = #selector(routeProviderChanged)
        routeProviderPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        routeDescription.textColor = .secondaryLabelColor
        routeDescription.font = .systemFont(ofSize: 12)
        routeDescription.isSelectable = true

        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        providerPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        nameField.placeholderString = "例如：公司代理"
        baseURLField.placeholderString = "https://api.example.com"
        modelField.placeholderString = "例如：gpt-5.6-sol"
        keyField.placeholderString = "sk-…"
        protocolPopup.addItems(withTitles: ProviderAPIFormat.allCases.map(\.displayName))
        protocolPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        testProviderButton.target = self
        testProviderButton.action = #selector(testProviderConnection)

        iconStylePopup.addItems(withTitles: StatusIconStyle.allCases.map(\.displayName))
        for (index, style) in StatusIconStyle.allCases.enumerated() {
            iconStylePopup.item(at: index)?.image = StatusIconRenderer.image(style: style, active: .green)
        }
        iconStylePopup.target = self
        iconStylePopup.action = #selector(iconStyleChanged)
        iconStylePopup.widthAnchor.constraint(equalToConstant: 240).isActive = true

        themePopup.addItems(withTitles: AppTheme.allCases.map(\.displayName))
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        themePopup.widthAnchor.constraint(equalToConstant: 240).isActive = true

    }

    private func buildRoutePage() -> NSView {
        let routeRow = settingRow(
            title: "模型来源",
            detail: "选择 OpenAI 官方账号或自定义模型提供商。",
            control: routeControl
        )
        let providerRow = settingRow(
            title: "第三方提供商",
            detail: "切换时会重新启动 Codex，并保留本地会话的原始记录。",
            control: routeProviderPopup
        )
        let historyRow = settingRow(
            title: "会话记录",
            detail: "所有路由显示同一份历史；会话内容不会被复制、归档或删除。",
            control: NSTextField(labelWithString: "始终保留")
        )
        return page(
            title: "路由",
            subtitle: "选择 Codex 使用的模型来源。",
            cards: [
                card([routeRow, separator(), providerRow, separator(), historyRow])
            ]
        )
    }

    private func buildProvidersPage() -> NSView {
        let addButton = NSButton(title: "新增", target: self, action: #selector(addProvider))
        let deleteButton = NSButton(title: "删除", target: self, action: #selector(deleteProvider))
        let picker = NSStackView(views: [providerPopup, addButton, deleteButton])
        picker.orientation = .horizontal
        picker.spacing = 8
        let providerRow = settingRow(
            title: "配置",
            detail: "保存多个提供商，并在模型路由中选择使用。",
            control: picker
        )

        let form = NSGridView(views: [
            [fieldLabel("名称"), nameField],
            [fieldLabel("Base URL"), baseURLField],
            [fieldLabel("模型 ID"), modelField],
            [fieldLabel("API 协议"), protocolPopup],
            [fieldLabel("API Key"), keyField]
        ])
        form.rowSpacing = 13
        form.columnSpacing = 16
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .fill
        let formContainer = padded(form, horizontal: 18, vertical: 17)
        let saveButton = NSButton(title: "保存提供商", target: self, action: #selector(saveProvider))
        let actions = NSStackView(views: [testProviderButton, saveButton])
        actions.orientation = .horizontal
        actions.spacing = 8
        let footer = settingRow(
            title: "连接验证",
            detail: "发送一条最小请求验证地址、模型和 API Key。Key 只保存在本机。",
            control: actions
        )
        return page(
            title: "提供商",
            subtitle: "配置 Responses 服务，或通过本地桥接使用 DeepSeek 等 Chat Completions 服务。",
            cards: [card([providerRow]), card([formContainer, separator(), footer])]
        )
    }

    private func buildAppearancePage() -> NSView {
        let themeRow = settingRow(
            title: "主题",
            detail: "选择浅色、深色或跟随系统。",
            control: themePopup
        )
        let iconRow = settingRow(
            title: "状态图标",
            detail: "选择菜单栏中的图标样式。",
            control: iconStylePopup
        )
        let preview = NSTextField(wrappingLabelWithString: "红：执行中   ·   黄：等待工具   ·   绿：可以输入")
        preview.textColor = .secondaryLabelColor
        preview.font = .systemFont(ofSize: 12)
        preview.alignment = .center
        preview.isSelectable = true
        return page(
            title: "状态与外观",
            subtitle: "自定义 Codex Pulse 的显示方式。",
            cards: [card([themeRow, separator(), iconRow]), card([padded(preview, vertical: 13)])]
        )
    }

    private func page(title: String, subtitle: String, cards: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        titleLabel.isSelectable = true
        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.isSelectable = true
        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 5

        let stack = NSStackView(views: [header] + cards + [NSView()])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(stack)
        ([header] + cards).forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -34),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 55),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
        return view
    }

    private func card(_ rows: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor.black.withAlphaComponent(0.09)
        }
        box.borderWidth = 0.6
        box.cornerRadius = 11
        box.fillColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.13, alpha: 1)
                : .white
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)
        rows.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor)
        ])
        return box
    }

    private func settingRow(title: String, detail: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.isSelectable = true
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.isSelectable = true
        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let row = NSStackView(views: [text, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return padded(row, horizontal: 18, vertical: 14)
    }

    private func padded(_ child: NSView, horizontal: CGFloat = 18, vertical: CGFloat = 10) -> NSView {
        let view = NSView()
        child.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontal),
            child.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontal),
            child.topAnchor.constraint(equalTo: view.topAnchor, constant: vertical),
            child.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -vertical)
        ])
        return view
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.isSelectable = true
        return label
    }

    private func makeSidebarButton(_ section: Section) -> NSButton {
        let button = NSButton(title: section.title, target: self, action: #selector(sidebarClicked(_:)))
        button.tag = section.rawValue
        button.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .left
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    @objc private func sidebarClicked(_ sender: NSButton) {
        guard let section = Section(rawValue: sender.tag) else { return }
        selectSection(section)
    }

    private func selectSection(_ section: Section) {
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        guard let page = pages[section] else { return }
        page.translatesAutoresizingMaskIntoConstraints = false
        pageHost.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            page.topAnchor.constraint(equalTo: pageHost.topAnchor),
            page.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor)
        ])
        for (key, button) in sidebarButtons {
            let selected = key == section
            button.layer?.backgroundColor = selected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.13).cgColor : NSColor.clear.cgColor
            button.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        }
    }

    func present() {
        providers = ProviderStore.providers()
        let route = RouteConfigManager.currentRoute()
        routeControl.selectedSegment = route == .official ? 0 : 1
        if case let .provider(id) = route {
            selectedProviderID = id
        } else {
            selectedProviderID = ProviderStore.selectedProviderID() ?? providers.first?.id
        }
        reloadProviderPopups()
        loadSelectedProvider()
        statusLabel.stringValue = ""
        confirmButton.isEnabled = true
        confirmButton.title = "应用并打开 Codex"
        if let index = StatusIconStyle.allCases.firstIndex(of: StatusIconPreference.selected) {
            iconStylePopup.selectItem(at: index)
        }
        if let index = AppTheme.allCases.firstIndex(of: AppThemePreference.selected) {
            themePopup.selectItem(at: index)
        }
        updateRouteFields()
        selectSection(.route)

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func routeChanged() {
        statusLabel.stringValue = ""
        updateRouteFields()
    }

    @objc private func routeProviderChanged() {
        guard let id = selectedProviderID(from: routeProviderPopup) else { return }
        selectedProviderID = id
        selectProvider(id, in: providerPopup)
        loadSelectedProvider()
        routeControl.selectedSegment = 1
        updateRouteFields()
    }

    @objc private func iconStyleChanged() {
        let index = iconStylePopup.indexOfSelectedItem
        guard StatusIconStyle.allCases.indices.contains(index) else { return }
        let style = StatusIconStyle.allCases[index]
        StatusIconPreference.selected = style
        appDelegate?.statusIconStyleDidChange(to: style)
        showSuccess("已切换为\(style.displayName)。")
    }

    @objc private func themeChanged() {
        let index = themePopup.indexOfSelectedItem
        guard AppTheme.allCases.indices.contains(index) else { return }
        let theme = AppTheme.allCases[index]
        AppThemePreference.selected = theme
        AppThemePreference.apply(theme)
        showSuccess("已切换为\(theme.displayName)主题。")
    }

    private func updateRouteFields() {
        let custom = routeControl.selectedSegment == 1
        routeProviderPopup.isEnabled = custom && !providers.isEmpty
        routeDescription.stringValue = custom
            ? "第三方路由使用当前选中的提供商。应用后 Codex 会重新启动，但本地会话不会删除。"
            : "官方路由使用 Codex 当前的 ChatGPT 登录状态；无需重复配置 API Key。"
    }

    private func reloadProviderPopups() {
        providerPopup.removeAllItems()
        routeProviderPopup.removeAllItems()
        let titles = ProviderStore.popupTitles(for: providers)
        for (provider, title) in zip(providers, titles) {
            addProviderItem(title: title, providerID: provider.id, to: providerPopup)
            addProviderItem(title: title, providerID: provider.id, to: routeProviderPopup)
        }
        if let id = selectedProviderID, providers.contains(where: { $0.id == id }) {
            selectProvider(id, in: providerPopup)
            selectProvider(id, in: routeProviderPopup)
        } else if !providers.isEmpty {
            selectedProviderID = providers[0].id
            selectProvider(providers[0].id, in: providerPopup)
            selectProvider(providers[0].id, in: routeProviderPopup)
        }
        updateRouteFields()
    }

    private func addProviderItem(title: String, providerID: String, to popup: NSPopUpButton) {
        popup.addItem(withTitle: title)
        popup.lastItem?.representedObject = providerID
    }

    private func selectedProviderID(from popup: NSPopUpButton) -> String? {
        popup.selectedItem?.representedObject as? String
    }

    private func selectProvider(_ providerID: String, in popup: NSPopUpButton) {
        guard let index = popup.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == providerID
        }) else { return }
        popup.selectItem(at: index)
    }

    private func loadSelectedProvider() {
        guard let id = selectedProviderID, let provider = providers.first(where: { $0.id == id }) else {
            nameField.stringValue = ""
            baseURLField.stringValue = ""
            modelField.stringValue = ""
            keyField.stringValue = ""
            protocolPopup.selectItem(at: 0)
            return
        }
        nameField.stringValue = provider.name
        baseURLField.stringValue = provider.baseURL
        modelField.stringValue = provider.model
        keyField.stringValue = CredentialStore.load(providerID: id) ?? ""
        let selectedFormat = provider.apiFormat ?? .automatic
        protocolPopup.selectItem(at: ProviderAPIFormat.allCases.firstIndex(of: selectedFormat) ?? 0)
    }

    @objc private func providerChanged() {
        guard let id = selectedProviderID(from: providerPopup) else { return }
        selectedProviderID = id
        selectProvider(id, in: routeProviderPopup)
        loadSelectedProvider()
        statusLabel.stringValue = ""
    }

    @objc private func addProvider() {
        selectedProviderID = ProviderStore.makeProviderID(existing: providers)
        nameField.stringValue = "新提供商"
        baseURLField.stringValue = ""
        modelField.stringValue = ""
        keyField.stringValue = ""
        protocolPopup.selectItem(at: 0)
        routeControl.selectedSegment = 1
        updateRouteFields()
        window?.makeFirstResponder(nameField)
    }

    @objc private func deleteProvider() {
        guard let id = selectedProviderID else { return }
        guard let index = providers.firstIndex(where: { $0.id == id }) else {
            selectedProviderID = providers.first?.id
            reloadProviderPopups()
            loadSelectedProvider()
            return
        }
        if RouteConfigManager.currentRoute() == .provider(id) {
            showError("当前正在使用该提供商，请先切换到其他路由。")
            return
        }
        let alert = NSAlert()
        alert.messageText = "删除 \(providers[index].name)？"
        alert.informativeText = "对应的本地 API Key 也会被删除。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try CredentialStore.delete(providerID: id)
            providers.remove(at: index)
            selectedProviderID = providers.indices.contains(index) ? providers[index].id : providers.last?.id
            try ProviderStore.saveProviders(providers, selectedProviderID: selectedProviderID)
            reloadProviderPopups()
            loadSelectedProvider()
            showSuccess("已删除提供商。")
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func saveProvider() {
        do {
            let profile = try persistCurrentProvider()
            appDelegate?.ensureChatCompletionsBridge()
            showSuccess("已保存 \(profile.name)。")
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func testProviderConnection() {
        let draft: (profile: ProviderProfile, key: String)
        do {
            draft = try currentProviderDraft()
        } catch {
            showError(error.localizedDescription)
            return
        }
        testProviderButton.isEnabled = false
        testProviderButton.title = "正在测试…"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在发送最小模型请求…"
        Task {
            do {
                let result = try await ProviderConnectionTester.test(profile: draft.profile, key: draft.key)
                showSuccess(result)
            } catch {
                showError(error.localizedDescription)
            }
            testProviderButton.isEnabled = true
            testProviderButton.title = "测试连接"
        }
    }

    private func persistCurrentProvider() throws -> ProviderProfile {
        let draft = try currentProviderDraft()
        let profile = draft.profile
        let key = draft.key
        let id = profile.id
        if let index = providers.firstIndex(where: { $0.id == id }) {
            providers[index] = profile
        } else {
            providers.append(profile)
        }
        selectedProviderID = id
        try ProviderStore.saveProviders(providers, selectedProviderID: id)
        try CredentialStore.save(key, providerID: id)
        reloadProviderPopups()
        return profile
    }

    private func currentProviderDraft() throws -> (profile: ProviderProfile, key: String) {
        guard let id = selectedProviderID else { throw SettingsError.noProvider }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !model.isEmpty, !key.isEmpty else { throw SettingsError.incomplete }
        if ProviderStore.hasNameCollision(name, excluding: id, in: providers) {
            throw SettingsError.duplicateName(name)
        }
        guard let url = URL(string: baseURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw SettingsError.invalidURL
        }
        let formatIndex = protocolPopup.indexOfSelectedItem
        let format = ProviderAPIFormat.allCases.indices.contains(formatIndex)
            ? ProviderAPIFormat.allCases[formatIndex] : .automatic
        let profile = ProviderProfile(
            id: id,
            name: name,
            baseURL: baseURL,
            model: model,
            apiFormat: format == .automatic ? nil : format
        )
        return (profile, key)
    }

    @objc private func closeWindow() { window?.close() }

    @objc private func confirmSelection() {
        confirmButton.isEnabled = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在更新路由…"
        confirmButton.title = "正在切换…"

        Task {
            let route: RouteChoice
            var usage: UsageResponse?
            do {
                if routeControl.selectedSegment == 1 {
                    let profile = try persistCurrentProvider()
                    appDelegate?.ensureChatCompletionsBridge()
                    route = .provider(profile.id)
                    if profile.isCodeAPI, let key = CredentialStore.load(providerID: profile.id) {
                        statusLabel.stringValue = "正在验证 CodeAPI Key…"
                        usage = try await CodeAPIClient.fetch(key: key)
                    }
                } else {
                    route = .official
                }
            } catch {
                showError(error.localizedDescription)
                confirmButton.isEnabled = true
                confirmButton.title = "应用并打开 Codex"
                return
            }

            let authSnapshot: CodexAuthSnapshot
            do {
                authSnapshot = try CodexAuthStore.snapshot()
            } catch {
                showError(error.localizedDescription)
                confirmButton.isEnabled = true
                confirmButton.title = "应用并打开 Codex"
                return
            }

            statusLabel.stringValue = "正在关闭 Codex…"
            var codexWasStopped = false
            var authPreparation = CodexAuthPreparation.ready
            do {
                try await CodexLauncher.terminate()
                codexWasStopped = true
                statusLabel.stringValue = "正在切换认证状态…"
                authPreparation = try CodexAuthStore.prepareForSwitch(to: route)
                statusLabel.stringValue = "正在更新路由配置…"
                try RouteConfigManager.apply(route)
            } catch {
                try? CodexAuthStore.restore(authSnapshot)
                if codexWasStopped {
                    try? await CodexLauncher.launch()
                }
                showError(error.localizedDescription)
                confirmButton.isEnabled = true
                confirmButton.title = "应用并打开 Codex"
                return
            }

            appDelegate?.routeDidChange(to: route, validatedCodeUsage: usage)
            if authPreparation.requiresOfficialLogin {
                showSuccess("已切换到官方路由，请在 Codex 中重新登录官方账号。")
            } else {
                showSuccess("已切换到 \(route.displayName)。")
            }
            confirmButton.title = "切换成功"
            window?.close()

            do {
                try await CodexLauncher.launch()
                if authPreparation.requiresOfficialLogin {
                    appDelegate?.presentOfficialLoginRequired()
                }
            } catch {
                appDelegate?.presentLaunchWarning(error.localizedDescription)
            }
        }
    }

    private func showSuccess(_ message: String) {
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = message
    }

    private func showError(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
    }
}

private enum SettingsError: LocalizedError {
    case noProvider
    case incomplete
    case invalidURL
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case .noProvider: return "请先新增一个第三方提供商。"
        case .incomplete: return "请完整填写名称、Base URL、模型 ID 和 API Key。"
        case .invalidURL: return "Base URL 必须是有效的 http 或 https 地址。"
        case let .duplicateName(name): return "路由名称“\(name)”已存在，请换一个名称。"
        }
    }
}
