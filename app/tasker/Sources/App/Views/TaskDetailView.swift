import SwiftUI
import TaskerDomain

struct TaskDetailView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        if let agg = store.selectedTask {
            VStack(alignment: .leading, spacing: 12) {
                MembershipBar(aggregate: agg)
                Divider()
                TaskInfoSection(aggregate: agg)
                Divider()
                EntriesSection(aggregate: agg)
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

// MARK: - 第一部分：关联

private struct MembershipBar: View {
    @EnvironmentObject var store: WorkspaceStore
    let aggregate: TaskAggregate

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            daysDropdown
            Spacer()
            if let controlDay = filterDay {
                priorityPicker(for: controlDay)
                currentToggle(for: controlDay)
            }
        }
    }

    private var sortedAssignments: [DayAssignment] {
        aggregate.meta.membership.dayAssignments.sorted { $0.day < $1.day }
    }

    /// 右侧控件永远针对当前 filter 的日期；filter 是 Backlog 或任务不在那天 → 隐藏
    private var filterDay: Day? {
        if case .day(let d) = store.dayFilter,
           aggregate.meta.membership.days.contains(d) {
            return d
        }
        return nil
    }

    // MARK: - 关联日期只读下拉

    private var daysDropdown: some View {
        Menu {
            if sortedAssignments.isEmpty {
                Text("(none)")
            } else {
                ForEach(sortedAssignments, id: \.day) { a in
                    // 只读：Button no-op；标记 filter 的当天为 selected
                    Button {} label: {
                        HStack {
                            Text(dayListItem(a))
                            if a.day == filterDay {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Days").font(.caption).foregroundStyle(.secondary)
                Text("(\(sortedAssignments.count))").font(.caption)
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func dayListItem(_ a: DayAssignment) -> String {
        var parts = [a.day.descriptionWithWeekday]
        if !a.priority.emoji.isEmpty { parts.append(a.priority.emoji) }
        if a.isCurrent { parts.append("👀") }
        return parts.joined(separator: " ")
    }

    // MARK: - 编辑控件（作用于 selectedDay）

    private func priorityPicker(for day: Day) -> some View {
        HStack(spacing: 4) {
            Text("Priority").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding<Priority>(
                get: { aggregate.meta.membership.priority(inDay: day) ?? .normal },
                set: { p in store.setPriority(id: aggregate.id, inDay: day, priority: p) }
            )) {
                ForEach(Priority.allCases, id: \.self) { p in
                    Text("\(p.titlePrefix)\(p.displayName)").tag(p)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private func currentToggle(for day: Day) -> some View {
        Toggle(isOn: Binding(
            get: { aggregate.meta.membership.isCurrent(inDay: day) },
            set: { v in store.setIsCurrent(id: aggregate.id, inDay: day, isCurrent: v) }
        )) {
            Text("Current")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

// MARK: - 第二部分：状态 + 标题 + 分类 + 描述

private struct TaskInfoSection: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var debounce: Task<Void, Never>?
    let aggregate: TaskAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                statusBadge
                TextField("Task title", text: Binding(
                    get: { aggregate.meta.title },
                    set: { new in store.updateMeta(id: aggregate.id) { $0.title = new } }
                ))
                .textFieldStyle(.plain)
                .font(.title2)
                categoryPicker
                Toggle(isOn: Binding(
                    get: { aggregate.meta.isRecurring },
                    set: { store.setIsRecurring(id: aggregate.id, isRecurring: $0) }
                )) {
                    Text("Recurring")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            descriptionEditor
                .frame(minHeight: 240)
        }
    }

    private var categoryPicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { aggregate.meta.categoryId },
            set: { id in store.updateMeta(id: aggregate.id) { $0.categoryId = id } }
        )) {
            Text(SettingsLookup.unsetName).tag(UUID?.none)
            ForEach(store.settings.categories) { def in
                Text(def.name).tag(UUID?.some(def.id))
            }
            // 若引用了不在配置里的 id，加个 placeholder 避免"selection invalid"
            if let cid = aggregate.meta.categoryId,
               !store.settings.categories.contains(where: { $0.id == cid }) {
                Text(SettingsLookup.unknownName).tag(UUID?.some(cid))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    /// 描述编辑器：左源右实时 markdown 渲染；HStack 显式 50/50 分配保证两边都能看见。
    private var descriptionEditor: some View {
        HStack(spacing: 0) {
            TextEditor(text: Binding(
                get: { store.currentDescription },
                set: { new in
                    store.currentDescription = new
                    scheduleSave()
                }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(Color.secondary.opacity(0.2))

            MarkdownRenderView(source: store.currentDescription)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.06))
                .border(Color.secondary.opacity(0.2))
        }
    }

    private var contextualStatus: TaskStatus { aggregate.status(in: store.dayFilter) }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Text(contextualStatus.displayName)
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(badgeColor.opacity(0.2))
                .foregroundStyle(badgeColor)
                .clipShape(Capsule())
            if aggregate.meta.isRecurring {
                Text("🔁").font(.body)
            }
        }
    }
    private var badgeColor: Color {
        switch contextualStatus {
        case .notStarted: return .gray
        case .inProgress: return .blue
        case .done: return .green
        }
    }

    private func scheduleSave() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled { store.saveDescription() }
        }
    }
}

// MARK: - 第三部分：时间记录

private struct EntriesSection: View {
    @EnvironmentObject var store: WorkspaceStore
    let aggregate: TaskAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Time entries").font(.headline)
                Spacer()
                Button {
                    store.addEntry(taskId: aggregate.id)
                } label: {
                    Label("Add", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            }

            if aggregate.entries.isEmpty {
                Text("No entries yet").foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(aggregate.entries, id: \.id) { e in
                        EntryRow(taskId: aggregate.id, entry: e)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct EntryRow: View {
    @EnvironmentObject var store: WorkspaceStore
    let taskId: UUID
    let entry: TimeEntry

    var body: some View {
        HStack(spacing: 10) {
            workTypePicker

            TextField("Entry title", text: Binding(
                get: { entry.title },
                set: { new in store.updateEntry(taskId: taskId, entryId: entry.id) { $0.title = new } }
            ))
            .textFieldStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            timeControls

            Menu {
                Button("(None)") { setMarker(nil) }
                Button("Done") { setMarker(.done) }
                Button("New phase") { setMarker(.restart) }
            } label: {
                markerBadge
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                store.deleteEntry(taskId: taskId, entryId: entry.id)
            } label: {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 6)
    }

    private var workTypePicker: some View {
        Picker("", selection: Binding<UUID?>(
            get: { entry.workTypeId },
            set: { id in store.updateEntry(taskId: taskId, entryId: entry.id) { $0.workTypeId = id } }
        )) {
            Text(SettingsLookup.unsetName).tag(UUID?.none)
            ForEach(store.settings.workTypes) { def in
                Text(def.name).tag(UUID?.some(def.id))
            }
            if let wt = entry.workTypeId,
               !store.settings.workTypes.contains(where: { $0.id == wt }) {
                Text(SettingsLookup.unknownName).tag(UUID?.some(wt))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 110)
    }

    @ViewBuilder
    private var timeControls: some View {
        HStack(spacing: 4) {
            if entry.startAt == nil {
                Button("Start") { store.startEntry(taskId: taskId, entryId: entry.id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                DatePicker("", selection: Binding(
                    get: { entry.startAt ?? Date() },
                    set: { new in
                        store.updateEntry(taskId: taskId, entryId: entry.id) { $0.startAt = new }
                    }
                ), displayedComponents: [.hourAndMinute])
                .labelsHidden()
                .fixedSize()
            }

            Text("→").foregroundStyle(.secondary)

            if entry.startAt == nil {
                Text("--:--").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            } else if entry.endAt == nil {
                Button("End") { store.endEntry(taskId: taskId, entryId: entry.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                DatePicker("", selection: Binding(
                    get: { entry.endAt ?? Date() },
                    set: { new in
                        store.updateEntry(taskId: taskId, entryId: entry.id) { $0.endAt = new }
                    }
                ), displayedComponents: [.hourAndMinute])
                .labelsHidden()
                .fixedSize()
            }

            if let d = entry.duration {
                Text(formatDuration(d))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var markerBadge: some View {
        if let m = entry.marker {
            Text(m.displayName)
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background((m == .done ? Color.green : Color.orange).opacity(0.2))
                .foregroundStyle(m == .done ? Color.green : Color.orange)
                .clipShape(Capsule())
        } else {
            Text("--").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func setMarker(_ m: TimeEntry.Marker?) {
        store.updateEntry(taskId: taskId, entryId: entry.id) { $0.marker = m }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let mins = Int(s) / 60
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h\(mins % 60)m"
    }
}
