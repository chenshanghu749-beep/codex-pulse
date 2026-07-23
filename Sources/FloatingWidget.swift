import Foundation
import WidgetKit

struct CodexPulseWidgetData: Codable {
    let updatedAt: Date
    let routeName: String
    let modelName: String
    let primaryValue: String
    let primaryLabel: String
    let detail: String
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let taskText: String
    let taskColor: String

    static let placeholder = CodexPulseWidgetData(
        updatedAt: Date(),
        routeName: "OpenAI 官方",
        modelName: "Codex",
        primaryValue: "—",
        primaryLabel: "正在读取用量",
        detail: "打开 Codex Pulse 以刷新数据",
        inputTokens: nil,
        outputTokens: nil,
        totalTokens: nil,
        taskText: "可以继续对话",
        taskColor: "green"
    )
}

enum CodexPulseWidgetStore {
    static let kind = "CodexPulseUsageWidget"
    static let dataDirectoryName = "Codex Pulse"
    static let dataFileName = "widget-data.json"

    private static var dataURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(dataDirectoryName, isDirectory: true)
            .appendingPathComponent(dataFileName)
    }

    static func update(
        route: RouteChoice,
        codeUsage: UsageResponse?,
        officialUsage: OfficialUsageSnapshot?,
        task: TaskActivitySnapshot
    ) {
        let routeName = route.displayName
        var modelName = "Codex"
        var primaryValue = "—"
        var primaryLabel = "正在读取用量"
        var detail = ""
        var inputTokens: Int?
        var outputTokens: Int?
        var totalTokens: Int?

        switch route {
        case let .provider(id):
            let provider = ProviderStore.provider(id: id)
            modelName = provider?.model ?? "第三方模型"
            if provider?.isCodeAPI == true, let codeUsage {
                primaryValue = String(format: "$%.2f", codeUsage.balance)
                primaryLabel = "账户余额"
                detail = "今日费用 $\(String(format: "%.2f", codeUsage.usage.today.actualCost))"
                inputTokens = codeUsage.usage.today.inputTokens
                outputTokens = codeUsage.usage.today.outputTokens
                totalTokens = codeUsage.usage.today.totalTokens
            } else {
                primaryValue = provider?.name ?? "第三方"
                primaryLabel = "当前提供商"
                detail = provider?.baseURL ?? "配置不可用"
            }
        case .official:
            if let officialUsage, officialUsage.isLoggedIn {
                modelName = officialUsage.planType ?? "ChatGPT"
                if let window = officialUsage.primary {
                    primaryValue = String(format: "%.0f%%", window.remainingPercent)
                    primaryLabel = "官方用量剩余"
                    detail = "\(window.label) · 自动刷新"
                } else {
                    primaryValue = "—"
                    primaryLabel = "官方用量剩余"
                    detail = officialUsage.email ?? "用量数据暂不可用"
                }
                totalTokens = officialUsage.tokenUsage?.todayTokens
            } else if officialUsage != nil {
                primaryValue = "未登录"
                primaryLabel = "OpenAI 官方账号"
                detail = "请在 Codex 中完成登录"
            }
        }

        let taskText: String
        let taskColor: String
        switch task.state {
        case let .running(count):
            taskText = count > 1 ? "\(count) 个会话执行中" : "会话执行中"
            taskColor = "red"
        case let .waiting(count):
            taskText = count > 1 ? "\(count) 个会话等待中" : "等待工具或命令"
            taskColor = "yellow"
        case .ready:
            taskText = "可以继续对话"
            taskColor = "green"
        }

        let value = CodexPulseWidgetData(
            updatedAt: Date(), routeName: routeName, modelName: modelName,
            primaryValue: primaryValue, primaryLabel: primaryLabel, detail: detail,
            inputTokens: inputTokens, outputTokens: outputTokens, totalTokens: totalTokens,
            taskText: taskText, taskColor: taskColor
        )
        guard let data = try? JSONEncoder().encode(value) else { return }
        let directory = dataURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: dataURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dataURL.path)
        } catch {
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
