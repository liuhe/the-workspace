import SwiftUI
import TaskerDomain

struct SidebarView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var showingNewTaskSheet = false
    @State private var showingDayPickerForFilter = false
    @State private var showingSettings = false
    @State private var pushingFromDay: Day?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FilterMenu(showingDayPicker: $showingDayPickerForFilter,
                           pushingFromDay: $pushingFromDay)
                Spacer()
                Toggle("当前", isOn: $store.showCurrent)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(8)
            Divider()
            GroupedTaskList()
            Divider()
            HStack {
                Button {
                    showingNewTaskSheet = true
                } label: {
                    Label("新任务", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command])
                Spacer()
                Button {
                    showingSettings = true
                } label: { Image(systemName: "gearshape") }
                Button {
                    store.reload()
                } label: { Image(systemName: "arrow.clockwise") }
            }
            .padding(8)
        }
        .sheet(isPresented: $showingNewTaskSheet) {
            NewTaskSheet(isPresented: $showingNewTaskSheet)
        }
        .sheet(isPresented: $showingDayPickerForFilter) {
            DayPickerSheet(isPresented: $showingDayPickerForFilter,
                           daysWithTasks: store.daysWithTasks) { day in
                store.dayFilter = .day(day)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
        }
        .sheet(item: Binding(
            get: { pushingFromDay.map { DayWrap(day: $0) } },
            set: { pushingFromDay = $0?.day }
        )) { wrap in
            PushToDaySheet(sourceDay: wrap.day) { target in
                store.pushUncompleted(from: wrap.day, to: target)
                pushingFromDay = nil
            } onCancel: {
                pushingFromDay = nil
            }
        }
    }
}

private struct DayWrap: Identifiable {
    let day: Day
    var id: Day { day }
}

/// 推未完成到 target 的 sheet：内嵌 mini 日历（可看到有任务的日子）。
private struct PushToDaySheet: View {
    @EnvironmentObject var store: WorkspaceStore
    let sourceDay: Day
    let onPick: (Day) -> Void
    let onCancel: () -> Void

    @State private var date: Date

    init(sourceDay: Day, onPick: @escaping (Day) -> Void, onCancel: @escaping () -> Void) {
        self.sourceDay = sourceDay
        self.onPick = onPick
        self.onCancel = onCancel
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: sourceDay.date()) ?? Date()
        self._date = State(initialValue: tomorrow)
    }

    private var uncompletedCount: Int {
        store.tasks.filter {
            $0.meta.membership.days.contains(sourceDay) && $0.status != .done
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("把 \(sourceDay.descriptionWithWeekday) 的未完成任务（\(uncompletedCount) 项）推到另一天")
                .font(.headline)
            MiniCalendarView(selectedDate: $date, daysWithTasks: store.daysWithTasks)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("推过去") {
                    onPick(Day(date: date))
                }
                .buttonStyle(.borderedProminent)
                .disabled(uncompletedCount == 0)
            }
        }
        .padding(20)
    }
}

// MARK: - 过滤器下拉

private struct FilterMenu: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var showingDayPicker: Bool
    @Binding var pushingFromDay: Day?

    var body: some View {
        Menu {
            dayShortcut("今天", day: Day.today())
            dayShortcut("昨天", day: dayOffset(-1))
            dayShortcut("明天", day: dayOffset(1))
            Button("选择日期…") { showingDayPicker = true }
            Divider()
            Button("Backlog") { store.dayFilter = .backlog }
            if case .day(let d) = store.dayFilter {
                Divider()
                Button("把未完成推到别一天…") { pushingFromDay = d }
            }
        } label: {
            HStack {
                Text(label).font(.headline)
                Image(systemName: "chevron.down").font(.caption)
                Spacer()
            }
        }
        .menuStyle(.borderlessButton)
    }

    private var label: String {
        switch store.dayFilter {
        case .backlog: return "Backlog"
        case .day(let d):
            if d == Day.today() { return "今天 \(d.weekdayLabel())" }
            if d == dayOffset(-1) { return "昨天 \(d.weekdayLabel())" }
            if d == dayOffset(1) { return "明天 \(d.weekdayLabel())" }
            return d.descriptionWithWeekday
        }
    }

    private func dayOffset(_ n: Int) -> Day {
        let d = Calendar.current.date(byAdding: .day, value: n, to: Date()) ?? Date()
        return Day(date: d)
    }

    /// 菜单快捷条目：有任务的日子在文字后加 ● 标识。
    private func dayShortcut(_ label: String, day: Day) -> Button<Text> {
        let hasTasks = store.daysWithTasks.contains(day)
        let text = hasTasks ? "\(label) ●" : label
        return Button(text) { store.dayFilter = .day(day) }
    }
}

// MARK: - 新任务弹框

private struct NewTaskSheet: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var isPresented: Bool
    @State private var title: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新任务").font(.headline)
            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                Button("创建", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { focused = true }
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.createTask(title: trimmed)
        isPresented = false
    }
}

// MARK: - 选日期弹框（带任务小点）

struct DayPickerSheet: View {
    @Binding var isPresented: Bool
    @State private var date: Date = Date()
    let daysWithTasks: Set<Day>
    let onPick: (Day) -> Void

    init(isPresented: Binding<Bool>,
         daysWithTasks: Set<Day> = [],
         onPick: @escaping (Day) -> Void) {
        self._isPresented = isPresented
        self.daysWithTasks = daysWithTasks
        self.onPick = onPick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选日期").font(.headline)
            MiniCalendarView(selectedDate: $date, daysWithTasks: daysWithTasks)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                Button("选定") {
                    onPick(Day(date: date))
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

// MARK: - 任务列表（按分类分组）

private struct GroupedTaskList: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var addingDayFor: UUID?

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(store.groupedFilteredTasks, id: \.0.id) { pair in
                CategorySection(cat: pair.0, tasks: pair.1, onPickDay: { addingDayFor = $0 })
            }
        }
        .listStyle(.sidebar)
        .sheet(item: sheetBinding) { wrap in
            DayPickerSheet(isPresented: Binding(
                get: { addingDayFor != nil },
                set: { if !$0 { addingDayFor = nil } }
            ), daysWithTasks: store.daysWithTasks) { day in
                store.addToDay(id: wrap.id, day: day)
            }
        }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedTaskId },
            set: { new in
                store.selectedTaskId = new
                if let id = new { store.loadDescription(for: id) }
            }
        )
    }

    private var sheetBinding: Binding<IdWrap?> {
        Binding(
            get: { addingDayFor.map { IdWrap(id: $0) } },
            set: { addingDayFor = $0?.id }
        )
    }
}

private struct CategorySection: View {
    let cat: CategoryDef
    let tasks: [TaskAggregate]
    let onPickDay: (UUID) -> Void

    var body: some View {
        Section(cat.name) {
            ForEach(tasks, id: \.id) { agg in
                TaskRow(aggregate: agg)
                    .tag(agg.id)
                    .contextMenu {
                        TaskContextMenu(aggregate: agg, onPickDay: { onPickDay(agg.id) })
                    }
            }
        }
    }
}

private struct IdWrap: Identifiable { let id: UUID }

private struct TaskContextMenu: View {
    @EnvironmentObject var store: WorkspaceStore
    let aggregate: TaskAggregate
    let onPickDay: () -> Void

    var body: some View {
        Menu("添加到") {
            Button("今天") { store.addToDay(id: aggregate.id, day: Day.today()) }
            Button("明天") {
                let d = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                store.addToDay(id: aggregate.id, day: Day(date: d))
            }
            Button("选日期…") { onPickDay() }
        }
        if case .day(let currentDay) = store.dayFilter,
           aggregate.meta.membership.days.contains(currentDay) {
            Button("从 \(currentDay.description) 移除") {
                store.removeFromDay(id: aggregate.id, day: currentDay)
            }
        }
        Menu("优先级") {
            ForEach(Priority.allCases, id: \.self) { p in
                Button {
                    store.setPriorityInFilterContext(id: aggregate.id, priority: p)
                } label: {
                    HStack {
                        Text("\(p.titlePrefix)\(p.displayName)")
                        if aggregate.priority(in: store.dayFilter) == p {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        Button(aggregate.meta.membership.isCurrent ? "从当前移除" : "加入当前") {
            store.setIsCurrent(id: aggregate.id, isCurrent: !aggregate.meta.membership.isCurrent)
        }
        Divider()
        Button(role: .destructive) {
            store.deleteTask(id: aggregate.id)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }
}

// MARK: - 单行（emoji 前缀 + 状态点，无副行）

private struct TaskRow: View {
    @EnvironmentObject var store: WorkspaceStore
    let aggregate: TaskAggregate

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: aggregate.status(in: store.dayFilter))
            Text(displayTitle)
                .lineLimit(1)
            Spacer()
            if aggregate.meta.isRecurring {
                Text("循环")
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(Color.purple)
                    .clipShape(Capsule())
            }
            if aggregate.meta.membership.isCurrent {
                Text("当前")
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private var displayTitle: String {
        let t = aggregate.meta.title.isEmpty ? "(无标题)" : aggregate.meta.title
        return "\(aggregate.priority(in: store.dayFilter).titlePrefix)\(t)"
    }
}

private struct StatusDot: View {
    let status: TaskStatus
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
    private var color: Color {
        switch status {
        case .notStarted: return .gray
        case .inProgress: return .blue
        case .done: return .green
        }
    }
}
