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
    /// 按 (day assignment, task) 汇总时间记录；日期升序。
    static func build(from tasks: [TaskAggregate], calendar: Calendar = .current) -> [DayStat] {
        var byDay: [Day: [UUID: [TimeEntry]]] = [:]
        var taskById: [UUID: TaskAggregate] = [:]
        for t in tasks {
            taskById[t.id] = t
            for assignment in t.meta.membership.dayAssignments where !assignment.entries.isEmpty {
                byDay[assignment.day, default: [:]][t.id, default: []].append(contentsOf: assignment.entries)
            }
        }
        return byDay.keys.sorted().map { day in
            let bucket = byDay[day]!
            let stats: [TaskDayStat] = bucket.map { (tid, es) in
                let sorted = es.sorted { ($0.startAt ?? .distantFuture) < ($1.startAt ?? .distantFuture) }
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
    @State private var editing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Statistics").font(.title2)
                Spacer()
                Toggle("Edit", isOn: $editing)
                    .toggleStyle(.switch)
                    .controlSize(.small)
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
                        ForEach(days) { DayBlock(day: $0, editing: editing) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var days: [DayStat] { StatsBuilder.build(from: store.tasks) }
}

// MARK: - 块（组合行 + 子行）

private struct DayBlock: View {
    let day: DayStat
    let editing: Bool
    @State private var expanded = true

    var body: some View {
        StatsRow(
            indent: 0,
            expandable: .binding($expanded, enabled: !day.tasks.isEmpty),
            label: day.day.descriptionWithWeekday,
            labelFont: .headline,
            timeCell: .none,
            day: day.day,
            ranges: day.ranges,
            color: .indigo,
            duration: day.totalDuration
        )
        if expanded {
            ForEach(day.tasks) { TaskBlock(dayContext: day.day, task: $0, editing: editing) }
        }
        Divider().padding(.vertical, 4)
    }
}

private struct TaskBlock: View {
    let dayContext: Day
    let task: TaskDayStat
    let editing: Bool
    @State private var expanded = false

    var body: some View {
        StatsRow(
            indent: 24,
            expandable: .binding($expanded, enabled: !task.entries.isEmpty),
            label: task.task.meta.title.isEmpty ? "(Untitled)" : task.task.meta.title,
            labelFont: .body,
            timeCell: .none,
            day: dayContext,
            ranges: task.ranges,
            color: .teal,
            duration: task.totalDuration
        )
        if expanded {
            ForEach(task.entries, id: \.id) { e in
                EntryRow(dayContext: dayContext, taskId: task.task.id, entry: e, editing: editing)
            }
        }
    }
}

private struct EntryRow: View {
    @EnvironmentObject var store: WorkspaceStore
    let dayContext: Day
    let taskId: UUID
    let entry: TimeEntry
    let editing: Bool

    var body: some View {
        let range: [(Date, Date)] = {
            if let s = entry.startAt, let e = entry.endAt { return [(s, e)] }
            return []
        }()
        StatsRow(
            indent: 48,
            expandable: .none,
            label: entry.title.isEmpty ? "(no title)" : entry.title,
            labelFont: .callout,
            timeCell: editing ? .editable(startBinding(), endBinding(), startExists: entry.startAt != nil, endExists: entry.endAt != nil)
                              : .display(displayTimeText),
            day: dayContext,
            ranges: range,
            color: .blue,
            duration: entry.duration ?? 0
        )
    }

    private var displayTimeText: String? {
        if let s = entry.startAt, let e = entry.endAt {
            return "\(StatsFormat.timeOnly(s)) – \(StatsFormat.timeOnly(e))"
        }
        if let s = entry.startAt {
            return "\(StatsFormat.timeOnly(s)) – …"
        }
        return "not started"
    }

    /// 默认 12:00 于 dayContext 那天，作为 DatePicker 的起点
    private var defaultStart: Date {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: dayContext.date(calendar: cal))
        return dayStart.addingTimeInterval(12 * 3600)
    }
    private var defaultEnd: Date {
        (entry.startAt ?? defaultStart).addingTimeInterval(3600)
    }

    private func startBinding() -> Binding<Date> {
        Binding<Date>(
            get: { entry.startAt ?? defaultStart },
            set: { new in
                store.updateEntry(taskId: taskId, entryId: entry.id) { $0.startAt = new }
            }
        )
    }
    private func endBinding() -> Binding<Date> {
        Binding<Date>(
            get: { entry.endAt ?? defaultEnd },
            set: { new in
                store.updateEntry(taskId: taskId, entryId: entry.id) { $0.endAt = new }
            }
        )
    }
}

// MARK: - 统一行布局
// [Label(260, 含缩进+chevron)] [TimeCell(200)] [Gantt(maxWidth)] [Duration(70)]

private struct StatsRow: View {
    let indent: CGFloat
    let expandable: Expandable
    let label: String
    let labelFont: Font
    let timeCell: TimeCell
    let day: Day
    let ranges: [(Date, Date)]
    let color: Color
    let duration: TimeInterval

    enum Expandable {
        case none
        case binding(Binding<Bool>, enabled: Bool)
    }

    enum TimeCell {
        case none
        case display(String?)
        /// startExists/endExists 表示原值是否已设定；未设定时 UI 淡显示，暗示"点了才生效"
        case editable(Binding<Date>, Binding<Date>, startExists: Bool, endExists: Bool)
    }

    var body: some View {
        HStack(spacing: 10) {
            labelCell.frame(width: 260, alignment: .leading)
            timeCellView.frame(width: 200, alignment: .leading)
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
    private var timeCellView: some View {
        switch timeCell {
        case .none:
            Color.clear
        case .display(let s):
            if let s {
                Text(s)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Color.clear
            }
        case .editable(let startBind, let endBind, let startExists, let endExists):
            HStack(spacing: 4) {
                DatePicker("", selection: startBind, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .controlSize(.mini)
                    .opacity(startExists ? 1.0 : 0.45)
                Text("→").font(.caption2).foregroundStyle(.secondary)
                DatePicker("", selection: endBind, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .controlSize(.mini)
                    .opacity(endExists ? 1.0 : 0.45)
            }
        }
    }
}
