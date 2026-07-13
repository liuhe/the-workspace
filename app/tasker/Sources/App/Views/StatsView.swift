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
    let entries: [TimeEntry]      // 落在这一天的、有 startAt+endAt 的记录
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
    /// 从所有任务里抽出"有 startAt 的时间记录"，按 (day, task) 汇总。
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

// MARK: - 时长格式化

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

// MARK: - Gantt 条

/// 一条 0-24h 的时间轴，画出 ranges 里的各段。
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
                    let seg = ranges[i]
                    let (x, sw) = geometry(for: seg, width: w)
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

// MARK: - 视图

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
                        ForEach(days) { d in
                            DayBlock(day: d)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var days: [DayStat] { StatsBuilder.build(from: store.tasks) }
}

// MARK: - Day / Task / Entry 行

private struct DayBlock: View {
    let day: DayStat
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(day.tasks) { t in
                        TaskBlock(dayContext: day.day, task: t)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 4)
            } label: {
                Row(
                    label: day.day.descriptionWithWeekday,
                    labelFont: .headline,
                    day: day.day,
                    ranges: day.ranges,
                    color: Color.indigo,
                    duration: day.totalDuration
                )
            }
            Divider()
        }
        .padding(.vertical, 4)
    }
}

private struct TaskBlock: View {
    let dayContext: Day
    let task: TaskDayStat
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(task.entries, id: \.id) { e in
                        EntryRow(dayContext: dayContext, entry: e)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 2)
            } label: {
                Row(
                    label: task.task.meta.title.isEmpty ? "(Untitled)" : task.task.meta.title,
                    labelFont: .body,
                    day: dayContext,
                    ranges: task.ranges,
                    color: Color.teal,
                    duration: task.totalDuration
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct EntryRow: View {
    let dayContext: Day
    let entry: TimeEntry

    var body: some View {
        let range: [(Date, Date)] = {
            if let s = entry.startAt, let e = entry.endAt { return [(s, e)] }
            return []
        }()
        Row(
            label: displayLabel,
            labelFont: .callout,
            day: dayContext,
            ranges: range,
            color: Color.blue,
            duration: entry.duration ?? 0,
            timeText: timeText
        )
    }

    private var displayLabel: String {
        entry.title.isEmpty ? "(no title)" : entry.title
    }
    private var timeText: String? {
        guard let s = entry.startAt else { return nil }
        if let e = entry.endAt {
            return "\(StatsFormat.timeOnly(s)) – \(StatsFormat.timeOnly(e))"
        }
        return StatsFormat.timeOnly(s)
    }
}

/// 通用一行：label | Gantt | duration
private struct Row: View {
    let label: String
    let labelFont: Font
    let day: Day
    let ranges: [(Date, Date)]
    let color: Color
    let duration: TimeInterval
    var timeText: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(labelFont)
                .frame(width: 220, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)

            if let t = timeText {
                Text(t)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
            }

            GanttBar(day: day, ranges: ranges, color: color)
                .frame(maxWidth: .infinity)

            Text(StatsFormat.duration(duration))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }
}
