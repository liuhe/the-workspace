import SwiftUI
import TaskerDomain

// 汇总数据见 Domain `TaskTimeStats`：日期区间内跨天合并，分类 → 任务 → 记录

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

// MARK: - 占比条（该行花费 / 区间总花费）

struct ShareBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.08))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: fraction > 0 ? max(2, CGFloat(min(1, fraction)) * geo.size.width) : 0)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 行选中标识

enum StatsRowID: Hashable {
    case total
    case category(UUID)
    case task(UUID)
    case entry(UUID)
}

// MARK: - 主视图

struct StatsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var editing = false
    @State private var selection: StatsRowID?
    /// 默认：含今天的最近 3 天 → [today-2, today]
    @State private var startDate: Date = Self.defaultStartDate()
    @State private var endDate: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        let categories = self.categories
        let total = categories.reduce(0) { $0 + $1.totalDuration }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Statistics").font(.title2)
                DateRangePicker(start: $startDate, end: $endDate)
                Spacer()
                Toggle("Edit", isOn: $editing)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(16)
            Divider()

            if categories.isEmpty {
                Spacer()
                Text("No time entries in this range.").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        StatsRow(
                            rowID: .total,
                            selection: $selection,
                            indent: 0,
                            expandable: .none,
                            label: "Total · \(categories.reduce(0) { $0 + $1.tasks.count }) tasks",
                            labelFont: .headline,
                            timeCell: .none,
                            fraction: total > 0 ? 1 : 0,
                            color: .indigo,
                            duration: total
                        )
                        Divider().padding(.vertical, 4)
                        ForEach(categories) {
                            CategoryBlock(category: $0, grandTotal: total, editing: editing, selection: $selection)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var categories: [CategoryTimeStat] {
        let s = Day(date: startDate)
        let e = Day(date: endDate)
        let range = s <= e ? s...e : e...s
        return TaskTimeStats.build(from: store.tasks, categories: store.settings.categories, range: range)
    }

    private static func defaultStartDate() -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: -2, to: today) ?? today
    }
}

private struct DateRangePicker: View {
    @Binding var start: Date
    @Binding var end: Date

    var body: some View {
        HStack(spacing: 6) {
            DatePicker("", selection: $start, displayedComponents: [.date])
                .labelsHidden()
                .controlSize(.small)
            Text("→").foregroundStyle(.secondary)
            DatePicker("", selection: $end, displayedComponents: [.date])
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

// MARK: - 块（组合行 + 子行）

private struct CategoryBlock: View {
    @Environment(\.colorScheme) private var scheme
    let category: CategoryTimeStat
    let grandTotal: TimeInterval
    let editing: Bool
    @Binding var selection: StatsRowID?
    @State private var expanded = true

    var body: some View {
        let color = CategoryColor.resolve(def: category.def, slot: category.slot, scheme: scheme)
        StatsRow(
            rowID: .category(category.def.id),
            selection: $selection,
            indent: 0,
            expandable: .binding($expanded, enabled: !category.tasks.isEmpty),
            label: category.def.name,
            labelFont: .body.weight(.semibold),
            timeCell: .none,
            fraction: share(category.totalDuration),
            color: color,
            duration: category.totalDuration
        )
        if expanded {
            ForEach(category.tasks) {
                TaskBlock(task: $0, grandTotal: grandTotal, color: color, editing: editing, selection: $selection)
            }
        }
        Divider().padding(.vertical, 4)
    }

    private func share(_ d: TimeInterval) -> Double { grandTotal > 0 ? d / grandTotal : 0 }
}

private struct TaskBlock: View {
    let task: TaskTimeStat
    let grandTotal: TimeInterval
    let color: Color
    let editing: Bool
    @Binding var selection: StatsRowID?
    @State private var expanded = false

    var body: some View {
        StatsRow(
            rowID: .task(task.task.id),
            selection: $selection,
            indent: 24,
            expandable: .binding($expanded, enabled: !task.entries.isEmpty),
            label: task.task.meta.title.isEmpty ? "(Untitled)" : task.task.meta.title,
            labelFont: .body,
            timeCell: .display(dayCountText),
            fraction: grandTotal > 0 ? task.totalDuration / grandTotal : 0,
            color: color.opacity(0.75),
            duration: task.totalDuration
        )
        if expanded {
            ForEach(task.entries) { e in
                EntryRow(taskId: task.task.id, dated: e, grandTotal: grandTotal,
                         color: color.opacity(0.5), editing: editing, selection: $selection)
            }
        }
    }

    private var dayCountText: String {
        let days = Set(task.entries.map(\.day)).count
        let n = task.entries.count
        return "\(n) \(n == 1 ? "entry" : "entries") · \(days) \(days == 1 ? "day" : "days")"
    }
}

private struct EntryRow: View {
    @EnvironmentObject var store: WorkspaceStore
    let taskId: UUID
    let dated: DatedEntry
    let grandTotal: TimeInterval
    let color: Color
    let editing: Bool
    @Binding var selection: StatsRowID?

    private var entry: TimeEntry { dated.entry }

    var body: some View {
        let d = dated.duration()
        StatsRow(
            rowID: .entry(entry.id),
            selection: $selection,
            indent: 48,
            expandable: .none,
            label: entry.title.isEmpty ? "(no title)" : entry.title,
            labelFont: .callout,
            timeCell: editing ? .editable(dayText, startBinding(), endBinding(),
                                          startExists: entry.startAt != nil, endExists: entry.endAt != nil)
                              : .display("\(dayText)  \(displayTimeText)"),
            fraction: grandTotal > 0 ? d / grandTotal : 0,
            color: color,
            duration: d,
            isManualDuration: entry.actualMinutes != nil
        )
    }

    /// "11-20 Thu"
    private var dayText: String {
        String(format: "%02d-%02d ", dated.day.month, dated.day.day) + dated.day.weekdayLabel()
    }

    private var displayTimeText: String {
        if let s = dated.startAt(), let e = dated.endAt() {
            return "\(StatsFormat.timeOnly(s)) – \(StatsFormat.timeOnly(e))"
        }
        if let s = dated.startAt() {
            return "\(StatsFormat.timeOnly(s)) – …"
        }
        return "not started"
    }

    /// 默认 12:00 于记录所属那天，作为 DatePicker 的起点
    private var defaultStart: Date {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: dated.day.date(calendar: cal))
        return dayStart.addingTimeInterval(12 * 3600)
    }
    private var defaultEnd: Date {
        (dated.startAt() ?? defaultStart).addingTimeInterval(3600)
    }

    private func startBinding() -> Binding<Date> {
        Binding<Date>(
            get: { dated.startAt() ?? defaultStart },
            set: { new in
                store.updateEntry(taskId: taskId, entryId: entry.id) { $0.startAt = new }
            }
        )
    }
    private func endBinding() -> Binding<Date> {
        Binding<Date>(
            get: { dated.endAt() ?? defaultEnd },
            set: { new in
                store.updateEntry(taskId: taskId, entryId: entry.id) { $0.endAt = new }
            }
        )
    }
}

// MARK: - 统一行布局
// [Label(260, 含缩进+chevron)] [TimeCell(230)] [占比条(maxWidth)] [Duration(70)]

private struct StatsRow: View {
    let rowID: StatsRowID
    @Binding var selection: StatsRowID?
    let indent: CGFloat
    let expandable: Expandable
    let label: String
    let labelFont: Font
    let timeCell: TimeCell
    let fraction: Double
    let color: Color
    let duration: TimeInterval
    /// 手动填了实际占用的记录：时长加括号（同甘特图色块标题的约定）
    var isManualDuration: Bool = false

    enum Expandable {
        case none
        case binding(Binding<Bool>, enabled: Bool)
    }

    enum TimeCell {
        case none
        case display(String?)
        /// startExists/endExists 表示原值是否已设定；未设定时 UI 淡显示，暗示"点了才生效"
        case editable(String, Binding<Date>, Binding<Date>, startExists: Bool, endExists: Bool)
    }

    private var isSelected: Bool { selection == rowID }

    var body: some View {
        HStack(spacing: 10) {
            labelCell.frame(width: 260, alignment: .leading)
            timeCellView.frame(width: 230, alignment: .leading)
            ShareBar(fraction: fraction, color: color)
                .frame(maxWidth: .infinity)
            Text(isManualDuration ? "(\(StatsFormat.duration(duration)))" : StatsFormat.duration(duration))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
                .help(isManualDuration ? "Manually entered actual time" : "")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selection = isSelected ? nil : rowID
        }
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
        case .editable(let dayText, let startBind, let endBind, let startExists, let endExists):
            HStack(spacing: 4) {
                Text(dayText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
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
