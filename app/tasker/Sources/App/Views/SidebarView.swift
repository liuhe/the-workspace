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
                Toggle("Current", isOn: $store.showCurrent)
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
                    Label("New task", systemImage: "plus")
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
            Text("Push \(uncompletedCount) uncompleted task\(uncompletedCount == 1 ? "" : "s") from \(sourceDay.descriptionWithWeekday) to another day")
                .font(.headline)
            MiniCalendarView(selectedDate: $date, daysWithTasks: store.daysWithTasks)
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
            dayShortcut("Today", day: Day.today())
            dayShortcut("Yesterday", day: dayOffset(-1))
            dayShortcut("Tomorrow", day: dayOffset(1))
            Button("Choose date…") { showingDayPicker = true }
            Divider()
            Button("Backlog") { store.dayFilter = .backlog }
            if case .day(let d) = store.dayFilter {
                Divider()
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
        switch store.dayFilter {
        case .backlog: return "Backlog"
        case .day(let d):
            if d == Day.today() { return "Today \(d.weekdayLabel())" }
            if d == dayOffset(-1) { return "Yesterday \(d.weekdayLabel())" }
            if d == dayOffset(1) { return "Tomorrow \(d.weekdayLabel())" }
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
            Text("Choose date").font(.headline)
            MiniCalendarView(selectedDate: $date, daysWithTasks: daysWithTasks)
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
        Menu("Add to") {
            Button("Today") { store.addToDay(id: aggregate.id, day: Day.today()) }
            Button("Tomorrow") {
                let d = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                store.addToDay(id: aggregate.id, day: Day(date: d))
            }
            Button("Choose date…") { onPickDay() }
        }
        if case .day(let currentDay) = store.dayFilter,
           aggregate.meta.membership.days.contains(currentDay) {
            Button("Remove from \(currentDay.description)") {
                store.removeFromDay(id: aggregate.id, day: currentDay)
            }
        }
        Menu("Priority") {
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
        // "Current" 是 day-relation 上的属性；只在 filter 是某天时可切换
        if case .day(let d) = store.dayFilter,
           aggregate.meta.membership.days.contains(d) {
            let cur = aggregate.meta.membership.isCurrent(inDay: d)
            Button(cur ? "Unmark current for \(d.description)" : "Mark current for \(d.description)") {
                store.setIsCurrent(id: aggregate.id, inDay: d, isCurrent: !cur)
            }
        }
        Divider()
        Button(role: .destructive) {
            store.deleteTask(id: aggregate.id)
        } label: {
            Label("Delete", systemImage: "trash")
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
                Text("Recurring")
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(Color.purple)
                    .clipShape(Capsule())
            }
            if isCurrentInContext {
                Text("Current")
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
        let t = aggregate.meta.title.isEmpty ? "(Untitled)" : aggregate.meta.title
        return "\(aggregate.priority(in: store.dayFilter).titlePrefix)\(t)"
    }

    private var isCurrentInContext: Bool {
        switch store.dayFilter {
        case .day(let d): return aggregate.meta.membership.isCurrent(inDay: d)
        case .backlog: return aggregate.meta.membership.hasAnyCurrent
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
