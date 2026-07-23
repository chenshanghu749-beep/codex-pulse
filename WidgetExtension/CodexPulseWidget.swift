import SwiftUI
import WidgetKit
import Darwin

let widgetKind = "CodexPulseUsageWidget"
let widgetDataRelativePath = "Library/Application Support/Codex Pulse/widget-data.json"

struct WidgetData: Codable {
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

    static let placeholder = WidgetData(
        updatedAt: Date(), routeName: "OpenAI 官方", modelName: "Codex",
        primaryValue: "82%", primaryLabel: "官方用量剩余", detail: "5 小时 · 自动刷新",
        inputTokens: 12840, outputTokens: 3980, totalTokens: 16820,
        taskText: "可以继续对话", taskColor: "green"
    )

    static func current() -> WidgetData {
        guard let passwordEntry = getpwuid(getuid()),
              let homePointer = passwordEntry.pointee.pw_dir else {
            return placeholder
        }
        let home = URL(fileURLWithPath: String(cString: homePointer), isDirectory: true)
        let url = home.appendingPathComponent(widgetDataRelativePath)
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return placeholder
        }
        return value
    }
}

struct PulseEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(PulseEntry(date: Date(), data: context.isPreview ? .placeholder : .current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let now = Date()
        completion(Timeline(
            entries: [PulseEntry(date: now, data: .current())],
            policy: .after(now.addingTimeInterval(15 * 60))
        ))
    }
}

struct PulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseEntry

    private var statusColor: Color {
        switch entry.data.taskColor {
        case "red": return Color(red: 1, green: 0.27, blue: 0.25)
        case "yellow": return Color(red: 1, green: 0.78, blue: 0.17)
        default: return Color(red: 0.27, green: 0.82, blue: 0.45)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            HStack(spacing: 7) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                Text("CODEX PULSE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.7)
                Spacer(minLength: 0)
                Circle().fill(statusColor).frame(width: 7, height: 7)
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.data.primaryValue)
                    .font(.system(size: family == .systemSmall ? 28 : 32, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.data.primaryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if family == .systemMedium {
                HStack(spacing: 16) {
                    metric("TOTAL", entry.data.totalTokens)
                    metric("INPUT", entry.data.inputTokens)
                    metric("OUTPUT", entry.data.outputTokens)
                    Spacer(minLength: 0)
                }
            } else {
                Text(entry.data.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(entry.data.routeName)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(entry.data.taskText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(15)
        .containerBackground(Color(nsColor: .windowBackgroundColor), for: .widget)
    }

    private func metric(_ name: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(.tertiary)
            Text(value.map(shortNumber) ?? "—").font(.caption.weight(.medium))
        }
    }

    private func shortNumber(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return String(value)
    }
}

@main
struct CodexPulseUsageWidget: Widget {
    let kind = widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProvider()) { entry in
            PulseWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex Pulse")
        .description("在桌面查看当前路由、用量、Token 与 Codex 任务状态。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
