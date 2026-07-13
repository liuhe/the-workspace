import SwiftUI
import TaskerDomain

// MARK: - 汇总数据

struct DayStat: Identifiable {
    let day: Day
    let tasks: [TaskDayStat]
    var id: Day { day }
    var totalDuration: TimeInterval { tasks.reduce(0) { $0 + $1.totalDuration } }
    var ranges: [(Date, Date)] { tasks.flatMap(\.ranges) }
}

struct TaskDayStat: Identifiable {
    let task: TaskAggregate
    let entries: [TimeEntry]
    var id: UUID { task.id }
    var totalDuration: TimeInterval { entries.compactMap(\.duration).reduce(0, +) }
    var ranges: [(Date, Date)] {
        entries.compactMap { e in
            guard let s = e.startAt, let en = e.endAt else { return nil }
            return (s, en)
        }
    }
}

enum StatsBuilder {
    static func build(from tasks: [TaskAggregate], calendar: Calendar = .current) -> [DayStat] {
        var byDay: [Day: [UUID: [TimeEntry]]] = [:]
        var taskById: [UUID: TaskAggregate] = [:]
        for t in tasks {
            taskById[t.id] = t
            for e in t.entries {
                guard let s = e.startAt else { continue }
                let d = Day(date: s, calendar: calendar)
                byDay[d, default: [:]][t.id, default: []].append(e)
            }
        }
        return byDay.keys.sorted(by: >).map { day in
            let bucket = byDay[day]!
            let stats: [TaskDayStat] = bucket.map { (tid, es) in
                let sorted = es.sorted { ($0.startAt ?? .distantPast) < ($1.startAt ?? .distantPast) }
                return TaskDayStat(task: taskById[tid]!, entries: sorted)
            }.sorted { $0.totalDuration > $1.totalDuration }
            return DayStat(day: day, tasks: stats)
        }
    }
}

// MARK: - 格式化

enum StatsFormat {
    static func duration(_ s: TimeInterval) -> String {
        let mins = max(0, Int(s) / 60)
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
    static func timeOnly(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Gantt 条（0-24h 时间轴）

struct GanttBar: View {
    let day: Day
    let ranges: [(Date, Date)]
    let color: Color
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: height)
                ForEach(0..<ranges.count, id: \.self) { i in
                    let (x, sw) = geometry(for: ranges[i], width: w)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: sw, height: height)
                        .offset(x: x)
                }
            }
        }
        .frame(height: height)
    }

    private func geometry(for range: (Date, Date), width: CGFloat) -> (CGFloat, CGFloat) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day.date(calendar: cal))
        let dayLen: TimeInterval = 86400
        let fs = max(0, min(1, range.0.timeIntervalSince(start) / dayLen))
        let fe = max(0, min(1, range.1.timeIntervalSince(start) / dayLen))
        let x = CGFloat(fs) * width
        let sw = max(2, CGFloat(max(fe - fs, 0)) * width)
        return (x, sw)
    }
}

// MARK: - 主视图

struct StatsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Statistics").font(.title2)
                Spacer()
                Button("Close") { isPresented = false }
            }
            .padding(16)
            Divider()

            if days.isEmpty {
                Spacer()
                Text("No timed entries yet.").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(days) { DayBlock(day: $0) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 560)
    }

    private var days: [DayStat] { StatsBuilder.build(from: store.tasks) }
}

// MARK: - 块（组合行 + 子行）

private struct DayBlock: View {
    let day: DayStat
    @State private var expanded = true

    var body: some View {
        StatsRow(
            indent: 0,
            expandable: .binding($expanded, enabled: !day.tasks.isEmpty),
            label: day.day.descriptionWithWeekday,
            labelFont: .headline,
            timeText: nil,
            day: day.day,
            ranges: day.ranges,
            color: .indigo,
            duration: day.totalDuration
        )
        if expanded {
            ForEach(day.tasks) { TaskBlock(dayContext: day.day, task: $0) }
        }
        Divider().padding(.vertical, 4)
    }
}

private struct TaskBlock: View {
    let dayContext: Day
    let task: TaskDayStat
    @State private var expanded = false

    var body: some View {
        StatsRow(
            indent: 24,
            expandable: .binding($expanded, enabled: !task.entries.isEmpty),
            label: task.task.meta.title.isEmpty ? "(Untitled)" : task.task.meta.title,
            labelFont: .body,
            timeText: nil,
            day: dayContext,
            ranges: task.ranges,
            color: .teal,
            duration: task.totalDuration
        )
        if expanded {
            ForEach(task.entries, id: \.id) { e in
                let range: [(Date, Date)] = (e.startAt.flatMap { s in e.endAt.map { (s, $0) } }).map { [$0] } ?? []
                StatsRow(
                    indent: 48,
                    expandable: .none,
                    label: e.title.isEmpty ? "(no title)" : e.title,
                    labelFont: .callout,
                    timeText: timeText(for: e),
                    day: dayContext,
                    ranges: range,
                    color: .blue,
                    duration: e.duration ?? 0
                )
            }
        }
    }

    private func timeText(for e: TimeEntry) -> String? {
        guard let s = e.startAt else { return nil }
        if let en = e.endAt { return "\(StatsFormat.timeOnly(s)) – \(StatsFormat.timeOnly(en))" }
        return StatsFormat.timeOnly(s)
    }
}

// MARK: - 统一行布局：Label 列固定 240pt（chevron 和缩进都吃进这一列），
//         timeText 固定 100pt（day/task 行传 nil 时留空占位），
//         Gantt 用 maxWidth infinity 撑满剩余，Duration 固定 70pt。

private struct StatsRow: View {
    let indent: CGFloat
    let expandable: Expandable
    let label: String
    let labelFont: Font
    let timeText: String?
    let day: Day
    let ranges: [(Date, Date)]
    let color: Color
    let duration: TimeInterval

    enum Expandable {
        case none
        case binding(Binding<Bool>, enabled: Bool)
    }

    var body: some View {
        HStack(spacing: 10) {
            labelCell.frame(width: 260, alignment: .leading)
            timeCell.frame(width: 100, alignment: .leading)
            GanttBar(day: day, ranges: ranges, color: color)
                .frame(maxWidth: .infinity)
            Text(StatsFormat.duration(duration))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var labelCell: some View {
        HStack(spacing: 4) {
            Spacer().frame(width: indent)
            chevron
            Text(label)
                .font(labelFont)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var chevron: some View {
        switch expandable {
        case .none:
            Spacer().frame(width: 14)
        case .binding(let bound, let enabled):
            if enabled {
                Button {
                    bound.wrappedValue.toggle()
                } label: {
                    Image(systemName: bound.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Spacer().frame(width: 14)
            }
        }
    }

    @ViewBuilder
    private var timeCell: some View {
        if let t = timeText {
            Text(t)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        } else {
            Color.clear
        }
    }
}
