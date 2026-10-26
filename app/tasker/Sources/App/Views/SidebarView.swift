import AppKit
import SwiftUI
import TaskerDomain

struct SidebarView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var showingNewTaskSheet = false
    @State private var showingBacklogPicker = false
    @State private var showingDayPickerForFilter = false
    @State private var showingSettings = false
    @State private var pushingFromDay: Day?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FilterMenu(showingDayPicker: $showingDayPickerForFilter,
                           pushingFromDay: $pushingFromDay)
                // 加号菜单：新建任务 / 从 Backlog 挑任务加入当前上下文那天
                // （Backlog 范围、所有日期下未选中某天的行时，第二项不可用）
                Menu {
                    Button("New task…") { showingNewTaskSheet = true }
                        .keyboardShortcut("n", modifiers: [.command])
                    Button("Add from Backlog…") { showingBacklogPicker = true }
                        .disabled(backlogTargetDay == nil)
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add a task")
                Spacer()
                if store.scope == .allDays {
                    CollapseAllButton()
                }
                StatusFilterMenu()
            }
            .padding(8)
            Divider()
            GroupedTaskList()
            Divider()
            HStack {
                Spacer()
                Button {
                    openWindow(id: "stats")
                } label: { Image(systemName: "chart.bar") }
                .help("Statistics")
                Button {
                    openWindow(id: "gantt")
                } label: { Image(systemName: "calendar.day.timeline.left") }
                .help("Gantt")
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
        .sheet(isPresented: $showingBacklogPicker) {
            if let day = backlogTargetDay {
                BacklogPickerSheet(isPresented: $showingBacklogPicker, day: day) { ids in
                    if let first = ids.first { store.selectTask(id: first, context: .day(day)) }
                }
            }
        }
        .sheet(isPresented: $showingDayPickerForFilter) {
            DayPickerSheet(isPresented: $showingDayPickerForFilter,
                           daysWithTasks: store.daysWithTasks,
                           completedDays: store.completedDays) { day in
                store.scope = .day(day)
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
        .onReceive(NotificationCenter.default.publisher(for: .newTaskRequested)) { _ in
            showingNewTaskSheet = true
        }
    }

    /// "从 Backlog 加入"的目标日：当前上下文是某天时即那天（某天范围 / 所有日期下选中某天的行），否则无
    private var backlogTargetDay: Day? {
        if case .day(let d) = store.contextFilter { return d }
        return nil
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
            Text("Push \(uncompletedCount) uncompleted task\(uncompletedCount == 1 ? "" : "s") from \(sourceDay.descriptionWithWeekday) to another day")
                .font(.headline)
            MiniCalendarView(selectedDate: $date,
                             daysWithTasks: store.daysWithTasks,
                             completedDays: store.completedDays)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Push") {
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
            ForEach(-3...3, id: \.self) { offset in
                dayItem(day: dayOffset(offset))
            }
            Button("Choose date…") { showingDayPicker = true }
            Divider()
            backlogItem
            allDaysItem
            if case .day(let d) = store.scope {
                Divider()
                Toggle("Day completed", isOn: Binding(
                    get: { store.isDayCompleted(d) },
                    set: { store.setDayCompleted(d, isCompleted: $0) }
                ))
                Button("Push uncompleted to another day…") { pushingFromDay = d }
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
        switch store.scope {
        case .backlog: return "Backlog"
        case .allDays: return "All days"
        case .day(let d): return dayLabel(d)
        }
    }

    private func dayOffset(_ n: Int) -> Day {
        let d = Calendar.current.date(byAdding: .day, value: n, to: Date()) ?? Date()
        return Day(date: d)
    }

    /// 菜单项：Toggle 让选中日呈现原生勾选态；今天前缀 ★；有任务的日子后缀 ●；已完成日子后缀 ✓
    @ViewBuilder
    private func dayItem(day: Day) -> some View {
        Toggle(dayLabel(day), isOn: Binding(
            get: { store.scope == .day(day) },
            set: { if $0 { store.scope = .day(day) } }
        ))
    }

    private func dayLabel(_ day: Day) -> String {
        let isToday = day == Day.today()
        let hasTasks = store.daysWithTasks.contains(day)
        let isCompleted = store.isDayCompleted(day)
        return (isToday ? "★ " : "") + day.descriptionWithWeekday + (hasTasks ? " ●" : "") + (isCompleted ? " ✓" : "")
    }

    @ViewBuilder
    private var backlogItem: some View {
        Toggle("Backlog", isOn: Binding(
            get: { store.scope == .backlog },
            set: { if $0 { store.scope = .backlog } }
        ))
    }

    @ViewBuilder
    private var allDaysItem: some View {
        Toggle("All days", isOn: Binding(
            get: { store.scope == .allDays },
            set: { if $0 { store.scope = .allDays } }
        ))
    }
}

// MARK: - 一键折叠 / 展开所有天分组

private struct CollapseAllButton: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        Button {
            store.toggleCollapseAllGroups()
        } label: {
            Image(systemName: store.allGroupsCollapsed
                  ? "rectangle.expand.vertical"
                  : "rectangle.compress.vertical")
        }
        .buttonStyle(.borderless)
        .help(store.allGroupsCollapsed ? "Expand all days" : "Collapse all days")
    }
}

// MARK: - 状态过滤下拉（3 个独立开关）

private struct StatusFilterMenu: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        Menu {
            Toggle("Current only", isOn: $store.showCurrent)
            Toggle("Hide completed", isOn: $store.hideCompleted)
            Toggle("Hide not started", isOn: $store.hideNotStarted)
        } label: {
            Image(systemName: activeCount > 0 ? "line.3.horizontal.decrease.circle.fill"
                                              : "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter: current / completed / not started")
    }

    private var activeCount: Int {
        (store.showCurrent ? 1 : 0)
            + (store.hideCompleted ? 1 : 0)
            + (store.hideNotStarted ? 1 : 0)
    }
}

// MARK: - 新任务弹框

/// 新建任务弹框。`targetDay` 非 nil 时任务加入指定那天（甘特图用）；nil 时跟随侧栏当前范围。
struct NewTaskSheet: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var isPresented: Bool
    var targetDay: Day? = nil
    /// 创建成功后的回调（甘特图用它选中新任务）
    var onCreated: ((UUID) -> Void)? = nil
    @State private var title: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New task").font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Create", action: create)
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
        if let targetDay {
            if let id = store.createTask(title: trimmed, inDay: targetDay) {
                onCreated?(id)
            }
        } else {
            store.createTask(title: trimmed)
        }
        isPresented = false
    }
}

// MARK: - 选日期弹框（带任务小点）

struct DayPickerSheet: View {
    @Binding var isPresented: Bool
    @State private var date: Date = Date()
    let daysWithTasks: Set<Day>
    let completedDays: Set<Day>
    let onPick: (Day) -> Void

    init(isPresented: Binding<Bool>,
         daysWithTasks: Set<Day> = [],
         completedDays: Set<Day> = [],
         onPick: @escaping (Day) -> Void) {
        self._isPresented = isPresented
        self.daysWithTasks = daysWithTasks
        self.completedDays = completedDays
        self.onPick = onPick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose date").font(.headline)
            MiniCalendarView(selectedDate: $date,
                             daysWithTasks: daysWithTasks,
                             completedDays: completedDays)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Select") {
                    onPick(Day(date: date))
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

// MARK: - 任务列表

/// 列表中一行的身份：任务 + 它所属的上下文。所有日期模式下同一任务可在多天出现，各自独立选中。
private struct RowRef: Hashable {
    let taskId: UUID
    let context: TaskFilter
}

/// 某天 / Backlog：按分类分组；所有日期：天 → 分类 → 任务，Backlog 为最后一组。
private struct GroupedTaskList: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var addingDayFor: UUID?

    var body: some View {
        List(selection: selectionBinding) {
            switch store.scope {
            case .day, .backlog:
                let context = store.contextFilter
                ForEach(store.groupedFilteredTasks, id: \.0.id) { pair in
                    Section(pair.0.name) {
                        TaskRows(context: context, tasks: pair.1, onPickDay: { addingDayFor = $0 })
                    }
                }
            case .allDays:
                ForEach(store.allDayGroups, id: \.context) { group in
                    Section(isExpanded: expandedBinding(group.context)) {
                        ForEach(group.categories, id: \.0.id) { pair in
                            Text(pair.0.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                                .selectionDisabled()
                            TaskRows(context: group.context, tasks: pair.1, onPickDay: { addingDayFor = $0 })
                                .padding(.leading, 8)
                        }
                    } header: {
                        DayGroupHeader(title: groupHeader(group.context),
                                       count: group.tasks.count,
                                       isToday: group.context == .day(Day.today())) {
                            let collapsed = store.collapsedGroups.contains(group.context)
                            store.setGroupCollapsed(group.context, !collapsed)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(item: sheetBinding) { wrap in
            DayPickerSheet(
                isPresented: Binding(
                    get: { addingDayFor != nil },
                    set: { if !$0 { addingDayFor = nil } }
                ),
                daysWithTasks: store.daysWithTasks,
                completedDays: store.completedDays
            ) { day in
                store.addToDay(id: wrap.id, day: day)
            }
        }
    }

    /// 天分组标题：今天前缀 ★；已完成日子后缀 ✓
    private func groupHeader(_ context: TaskFilter) -> String {
        switch context {
        case .backlog: return "Backlog"
        case .day(let d):
            let isToday = d == Day.today()
            let isCompleted = store.isDayCompleted(d)
            return (isToday ? "★ " : "") + d.descriptionWithWeekday + (isCompleted ? " ✓" : "")
        }
    }

    private func expandedBinding(_ context: TaskFilter) -> Binding<Bool> {
        Binding(
            get: { !store.collapsedGroups.contains(context) },
            set: { store.setGroupCollapsed(context, !$0) }
        )
    }

    private var selectionBinding: Binding<RowRef?> {
        Binding(
            get: {
                guard let id = store.selectedTaskId else { return nil }
                return RowRef(taskId: id, context: store.contextFilter)
            },
            set: { new in
                store.selectTask(id: new?.taskId, context: new?.context)
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

/// 所有日期模式的天分组标题：粗体 + 任务数；今天用强调色；点击整行切换折叠
private struct DayGroupHeader: View {
    let title: String
    let count: Int
    let isToday: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: Capsule())
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

private struct TaskRows: View {
    let context: TaskFilter
    let tasks: [TaskAggregate]
    let onPickDay: (UUID) -> Void

    var body: some View {
        ForEach(tasks, id: \.id) { agg in
            TaskRow(aggregate: agg, context: context)
                .tag(RowRef(taskId: agg.id, context: context))
                .contextMenu {
                    TaskContextMenu(aggregate: agg, context: context, onPickDay: { onPickDay(agg.id) })
                }
        }
    }
}

private struct IdWrap: Identifiable { let id: UUID }

private struct TaskContextMenu: View {
    @EnvironmentObject var store: WorkspaceStore
    let aggregate: TaskAggregate
    /// 这一行所属的上下文（某天 / Backlog）
    let context: TaskFilter
    let onPickDay: () -> Void

    var body: some View {
        Menu("Add to") {
            ForEach(-3...3, id: \.self) { offset in
                addToDayItem(day: Self.dayOffset(offset))
            }
            Button("Choose date…") { onPickDay() }
        }
        if case .day(let currentDay) = context,
           aggregate.meta.membership.days.contains(currentDay) {
            Button("Remove from \(currentDay.description)") {
                store.removeFromDay(id: aggregate.id, day: currentDay)
            }
        }
        Menu("Priority") {
            ForEach(Priority.allCases, id: \.self) { p in
                Button {
                    store.setPriority(id: aggregate.id, in: context, priority: p)
                } label: {
                    HStack {
                        Text("\(p.titlePrefix)\(p.displayName)")
                        if aggregate.priority(in: context) == p {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        // "Current" 是 day-relation 上的属性；只在上下文是某天时可切换
        if case .day(let d) = context,
           aggregate.meta.membership.days.contains(d) {
            let cur = aggregate.meta.membership.isCurrent(inDay: d)
            Button(cur ? "Unmark current for \(d.description)" : "Mark current for \(d.description)") {
                store.setIsCurrent(id: aggregate.id, inDay: d, isCurrent: !cur)
            }
        }
        Divider()
        Button {
            let path = store.descriptionURL(for: aggregate.id).path
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(path, forType: .string)
        } label: {
            Label("Copy description path", systemImage: "doc.on.clipboard")
        }
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([store.descriptionURL(for: aggregate.id)])
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
        Divider()
        Button(role: .destructive) {
            store.deleteTask(id: aggregate.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Add-to 菜单项：今天前缀 ★；任务已归属的日子后缀 ●；已完成日子后缀 ✓；再点已归属日为幂等（upsertDay）
    @ViewBuilder
    private func addToDayItem(day: Day) -> some View {
        let isToday = day == Day.today()
        let already = aggregate.meta.membership.days.contains(day)
        let isCompleted = store.isDayCompleted(day)
        let text = (isToday ? "★ " : "") + day.descriptionWithWeekday + (already ? " ●" : "") + (isCompleted ? " ✓" : "")
        Button(text) { store.addToDay(id: aggregate.id, day: day) }
    }

    private static func dayOffset(_ n: Int) -> Day {
        let d = Calendar.current.date(byAdding: .day, value: n, to: Date()) ?? Date()
        return Day(date: d)
    }
}

// MARK: - 单行（emoji 前缀 + 状态点，无副行）

private struct TaskRow: View {
    let aggregate: TaskAggregate
    /// 这一行所属的上下文（某天 / Backlog）
    let context: TaskFilter

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: aggregate.status(in: context))
            Text(displayTitle)
                .lineLimit(1)
            Spacer()
            if aggregate.meta.isRecurring {
                Text("🔁").font(.caption)
            }
            if isCurrentInContext {
                Text("👀").font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayTitle: String {
        let t = aggregate.meta.title.isEmpty ? "(Untitled)" : aggregate.meta.title
        return "\(aggregate.priority(in: context).titlePrefix)\(t)"
    }

    private var isCurrentInContext: Bool {
        switch context {
        case .day(let d): return aggregate.meta.membership.isCurrent(inDay: d)
        case .backlog: return false
        }
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
