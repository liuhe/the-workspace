import Foundation
import SwiftUI
import TaskerDomain
import TaskerPersistence

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var tasks: [TaskAggregate] = []
    @Published var scope: ListScope = .day(Day.today())
    /// 所有日期模式下选中行所属的上下文（某天 / Backlog）；单上下文模式下忽略
    @Published var selectedContext: TaskFilter?
    /// 所有日期模式下被折叠的分组；仅内存态，不落盘
    @Published var collapsedGroups: Set<TaskFilter> = []
    @Published var showCurrent: Bool = false
    @Published var hideCompleted: Bool = false
    @Published var hideNotStarted: Bool = false
    @Published var selectedTaskId: UUID?
    @Published var currentDescription: String = ""
    @Published private(set) var completedDays: Set<Day> = []
    @Published var lastError: String?
    @Published private(set) var settings: AppSettings = .defaults
    @Published private(set) var dataRoot: URL

    private var repo: FileRepository
    private var settingsRepo: SettingsRepository
    private var pollTimer: Timer?

    static let dataRootDefaultsKey = "tasker.dataRoot"

    /// 从 UserDefaults 读上次配置的数据目录；否则用 `~/Documents/tasker/`。
    static func loadDataRoot() -> URL {
        if let s = UserDefaults.standard.string(forKey: dataRootDefaultsKey),
           !s.isEmpty {
            return URL(fileURLWithPath: s)
        }
        return StorageLayout.default.root
    }

    init(root: URL) throws {
        let repo = try FileRepository(root: root)
        let settingsRepo = try SettingsRepository(layout: repo.layout)
        self.repo = repo
        self.settingsRepo = settingsRepo
        self.dataRoot = root
        reload()
        reloadSettings()
        startPolling()
    }

    /// 切换数据目录：重建 repo，全量重载，选中和描述清空。
    func setDataRoot(_ url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true
            )
            let newRepo = try FileRepository(root: url)
            let newSettingsRepo = try SettingsRepository(layout: newRepo.layout)
            repo = newRepo
            settingsRepo = newSettingsRepo
            dataRoot = url
            UserDefaults.standard.set(url.path, forKey: Self.dataRootDefaultsKey)
            selectedTaskId = nil
            selectedContext = nil
            currentDescription = ""
            completedDays = []
            reload()
            reloadSettings()
        } catch {
            lastError = "Failed to change data root: \(error.localizedDescription)"
        }
    }

    /// 详情页 / 命令使用的上下文：单上下文模式下即范围本身；
    /// 所有日期模式下是选中行所属的上下文，没有选中时按 Backlog 处理。
    var contextFilter: TaskFilter {
        scope.filter ?? selectedContext ?? .backlog
    }

    /// 单上下文模式（某天 / Backlog）下过滤排序后的任务；所有日期模式返回空
    var filteredTasks: [TaskAggregate] {
        guard let filter = scope.filter else { return [] }
        return TaskQueries.apply(filter,
                                 currentOnly: showCurrent,
                                 hideCompleted: hideCompleted,
                                 hideNotStarted: hideNotStarted,
                                 to: tasks)
    }

    var groupedFilteredTasks: [(CategoryDef, [TaskAggregate])] {
        TaskQueries.groupByCategory(filteredTasks, categories: settings.categories)
    }

    /// 所有日期模式：天 → 分类 → 任务，Backlog 为最后一组
    var allDayGroups: [DayGroup] {
        TaskQueries.groupAllDays(tasks,
                                 categories: settings.categories,
                                 currentOnly: showCurrent,
                                 hideCompleted: hideCompleted,
                                 hideNotStarted: hideNotStarted)
    }

    /// 所有日期模式：是否所有分组都已折叠（空列表视为未全折叠）
    var allGroupsCollapsed: Bool {
        let contexts = allDayGroups.map(\.context)
        return !contexts.isEmpty && contexts.allSatisfy { collapsedGroups.contains($0) }
    }

    /// 一键折叠 / 展开：有任何展开的 → 全部折叠；已经全折叠 → 全部展开
    func toggleCollapseAllGroups() {
        if allGroupsCollapsed {
            collapsedGroups = []
        } else {
            collapsedGroups = Set(allDayGroups.map(\.context))
        }
    }

    func setGroupCollapsed(_ context: TaskFilter, _ collapsed: Bool) {
        if collapsed { collapsedGroups.insert(context) } else { collapsedGroups.remove(context) }
    }

    /// 选中某行：记录任务和它所属的上下文，并加载描述
    func selectTask(id: UUID?, context: TaskFilter?) {
        selectedTaskId = id
        selectedContext = context
        if let id { loadDescription(for: id) }
    }

    func categoryName(_ id: UUID?) -> String {
        SettingsLookup.categoryName(id, in: settings.categories)
    }
    func workTypeName(_ id: UUID?) -> String {
        SettingsLookup.workTypeName(id, in: settings.workTypes)
    }

    var selectedTask: TaskAggregate? {
        guard let id = selectedTaskId else { return nil }
        return tasks.first { $0.id == id }
    }

    /// 所有出现过的日期（用于日历打点）
    var daysWithTasks: Set<Day> {
        var acc: Set<Day> = []
        for t in tasks { acc.formUnion(t.meta.membership.days) }
        return acc
    }

    func isDayCompleted(_ day: Day) -> Bool {
        completedDays.contains(day)
    }

    func setDayCompleted(_ day: Day, isCompleted: Bool) {
        if isCompleted {
            completedDays.insert(day)
        } else {
            completedDays.remove(day)
        }
        saveCompletedDays()
    }

    /// 当前范围下选中的任务已不在列表里时，清空选中和描述。
    /// 由范围切换（scope / 状态开关）触发；任务自身变动不触发。
    /// 所有日期模式下要求 (任务, 上下文) 这一行仍然存在。
    func pruneSelectionIfOffscreen() {
        guard let id = selectedTaskId else { return }
        let visible: Bool
        switch scope {
        case .day, .backlog:
            visible = filteredTasks.contains(where: { $0.id == id })
        case .allDays:
            visible = allDayGroups.contains { group in
                group.context == selectedContext && group.tasks.contains(where: { $0.id == id })
            }
        }
        if !visible {
            selectedTaskId = nil
            selectedContext = nil
            currentDescription = ""
        }
    }

    // MARK: - 加载

    func reload() {
        do {
            tasks = try repo.loadAll()
            completedDays = try repo.loadCompletedDays()
            if let id = selectedTaskId, !tasks.contains(where: { $0.id == id }) {
                selectedTaskId = nil
                selectedContext = nil
                currentDescription = ""
            }
        } catch {
            lastError = "Load failed: \(error.localizedDescription)"
        }
    }

    // MARK: - 任务

    /// 侧栏新建：归属跟随当前范围（某天 → 加入那天；Backlog / 所有日期 → 不归属任何天）
    func createTask(title: String) {
        var day: Day?
        if case .day(let d) = scope { day = d }
        createTask(title: title, inDay: day, isCurrent: showCurrent)
    }

    /// 显式指定归属日（甘特图窗口用）；`day` 为 nil 时不归属任何天。返回新任务 id，失败返回 nil。
    @discardableResult
    func createTask(title: String, inDay day: Day?, isCurrent: Bool = false) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var meta = TaskMeta(title: trimmed, categoryId: nil)
        var addedDay: Day?
        if let d = day {
            meta.membership.dayAssignments.append(
                DayAssignment(day: d, priority: .normal, isCurrent: isCurrent)
            )
            addedDay = d
        }
        var agg = TaskAggregate(meta: meta)
        do {
            try repo.save(&agg)
            if let addedDay { clearCompletedDay(addedDay) }
            tasks.append(agg)
            selectedTaskId = agg.id
            selectedContext = addedDay.map { .day($0) } ?? .backlog
            currentDescription = ""
            return agg.id
        } catch {
            lastError = "Create failed: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteTask(id: UUID) {
        do {
            try repo.delete(id: id)
            tasks.removeAll { $0.id == id }
            if selectedTaskId == id { selectedTaskId = nil; selectedContext = nil; currentDescription = "" }
        } catch {
            lastError = "Delete failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func updateMeta(id: UUID, _ mutate: (inout TaskMeta) -> Void) -> Bool {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return false }
        var agg = tasks[idx]
        mutate(&agg.meta)
        agg.meta.updatedAt = Date()
        return persist(&agg, at: idx)
    }

    /// 直接改某天关联的优先级（哪一天由调用方指定；给详情里的 chip / 列表右键用）
    func setPriority(id: UUID, inDay day: Day, priority: Priority) {
        updateMeta(id: id) { $0.membership.setPriority(inDay: day, priority: priority) }
    }

    /// 在给定上下文改优先级；只在 .day(d) 有意义；Backlog 上下文无优先级概念，忽略
    func setPriority(id: UUID, in context: TaskFilter, priority: Priority) {
        if case .day(let d) = context {
            setPriority(id: id, inDay: d, priority: priority)
        }
    }

    func addToDay(id: UUID, day: Day) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let wasAssigned = task.meta.membership.days.contains(day)
        let sourcePriority = task.priority(in: contextFilter)
        let saved = updateMeta(id: id) { $0.membership.upsertDay(day, priority: sourcePriority) }
        if saved && !wasAssigned { clearCompletedDay(day) }
    }

    func removeFromDay(id: UUID, day: Day) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        guard !task.meta.membership.hasEntries(inDay: day) else {
            lastError = "Cannot remove a day that has time entries"
            return
        }
        updateMeta(id: id) { $0.membership.removeDay(day) }
    }

    func clearAllDays(id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        guard task.entries.isEmpty else {
            lastError = "Cannot clear days while the task has time entries"
            return
        }
        updateMeta(id: id) { $0.membership.dayAssignments.removeAll() }
    }

    /// 在某天关联上打/去 current 标
    func setIsCurrent(id: UUID, inDay day: Day, isCurrent: Bool) {
        updateMeta(id: id) { $0.membership.setIsCurrent(inDay: day, isCurrent: isCurrent) }
    }

    func setIsRecurring(id: UUID, isRecurring: Bool) {
        updateMeta(id: id) { $0.isRecurring = isRecurring }
    }

    /// 把 sourceDay 下所有未完成任务在 targetDay 上建立关联；priority 复制自 sourceDay 关联。
    /// - 循环任务：以 sourceDay 上的当日 status 判定"未完成"
    /// - 非循环：以全局 status 判定
    /// - 目标日已经关联的任务不覆盖它已有的 priority
    @discardableResult
    func pushUncompleted(from sourceDay: Day, to targetDay: Day) -> Int {
        guard sourceDay != targetDay else { return 0 }
        let candidates = tasks.filter {
            guard $0.meta.membership.days.contains(sourceDay) else { return false }
            let s = $0.meta.isRecurring ? $0.statusForDay(sourceDay) : $0.status
            return s != .done
        }
        var addedToTarget = false
        for c in candidates {
            let wasAssigned = c.meta.membership.days.contains(targetDay)
            let srcPriority = c.meta.membership.priority(inDay: sourceDay) ?? .normal
            let saved = updateMeta(id: c.id) { meta in
                if meta.membership.priority(inDay: targetDay) == nil {
                    meta.membership.upsertDay(targetDay, priority: srcPriority)
                }
            }
            if saved && !wasAssigned { addedToTarget = true }
        }
        if addedToTarget { clearCompletedDay(targetDay) }
        return candidates.count
    }

    // MARK: - 时间记录

    /// 新建一条未开始的记录。`context` 缺省为侧栏当前上下文；甘特图详情面板显式传入那天。
    func addEntry(taskId: UUID, in context: TaskFilter? = nil, title: String = "", workTypeId: UUID? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var agg = tasks[idx]
        let ctx = context ?? contextFilter
        let day = entryDay(for: agg, in: ctx)
        let wasAssigned = agg.meta.membership.days.contains(day)
        let sourcePriority = agg.priority(in: ctx)
        let shouldMarkCurrent: Bool
        switch ctx {
        case .day: shouldMarkCurrent = showCurrent
        case .backlog: shouldMarkCurrent = false
        }
        // 默认预选第一个工作类型
        let defaultId = workTypeId ?? settings.workTypes.first?.id
        let wasEmpty = agg.entries(inDay: day).isEmpty
        let newId = agg.addEntry(inDay: day,
                                 priority: sourcePriority,
                                 isCurrent: shouldMarkCurrent,
                                 title: title,
                                 workTypeId: defaultId)
        // 重复任务当天首条 → 从最近一天已完成的记录带时间
        if wasEmpty, let carry = agg.entryTimeToCarry(to: day) {
            agg.updateEntry(id: newId) {
                $0.startAt = carry.startAt
                $0.endAt = carry.endAt
            }
        }
        let saved = persist(&agg, at: idx)
        if saved && !wasAssigned { clearCompletedDay(day) }
    }

    func startEntry(taskId: UUID, entryId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var agg = tasks[idx]
        do {
            try agg.startEntry(id: entryId)
            persist(&agg, at: idx)
        } catch { lastError = error.localizedDescription }
    }

    func endEntry(taskId: UUID, entryId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var agg = tasks[idx]
        do {
            try agg.endEntry(id: entryId)
            persist(&agg, at: idx)
        } catch { lastError = error.localizedDescription }
    }

    func updateEntry(taskId: UUID, entryId: UUID, mutate: (inout TimeEntry) -> Void) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var agg = tasks[idx]
        agg.updateEntry(id: entryId, mutate: mutate)
        persist(&agg, at: idx)
    }

    /// 甘特图：设置某条记录在 `day` 上的起止时间（以当天秒偏移表示，已由 TimelineGrid 吸附）
    func setEntryRange(taskId: UUID, entryId: UUID, inDay day: Day, start: TimeInterval, end: TimeInterval?) {
        updateEntry(taskId: taskId, entryId: entryId) { e in
            e.startAt = TimelineGrid.date(atOffset: start, inDay: day)
            if let end { e.endAt = TimelineGrid.date(atOffset: end, inDay: day) }
        }
    }

    /// 甘特图：在 `day` 的空白处拖出一段时间。优先填入该天尚未开始的记录；没有则新建一条。
    func addTimedEntry(taskId: UUID, inDay day: Day, start: TimeInterval, end: TimeInterval) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var agg = tasks[idx]
        let startAt = TimelineGrid.date(atOffset: start, inDay: day)
        let endAt = TimelineGrid.date(atOffset: end, inDay: day)
        if let placeholder = agg.entries(inDay: day).first(where: { $0.isNotStarted }) {
            agg.updateEntry(id: placeholder.id) { $0.startAt = startAt; $0.endAt = endAt }
            persist(&agg, at: idx)
            return
        }
        let wasAssigned = agg.meta.membership.days.contains(day)
        let newId = agg.addEntry(inDay: day,
                                 priority: agg.meta.membership.priority(inDay: day) ?? .normal,
                                 isCurrent: agg.meta.membership.isCurrent(inDay: day),
                                 workTypeId: settings.workTypes.first?.id)
        agg.updateEntry(id: newId) { $0.startAt = startAt; $0.endAt = endAt }
        let saved = persist(&agg, at: idx)
        if saved && !wasAssigned { clearCompletedDay(day) }
    }

    func deleteEntry(taskId: UUID, entryId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var agg = tasks[idx]
        agg.deleteEntry(id: entryId)
        persist(&agg, at: idx)
    }

    // MARK: - 设置

    func reloadSettings() {
        do { settings = try settingsRepo.load() }
        catch { lastError = "Load settings failed: \(error.localizedDescription)" }
    }

    func updateSettings(_ new: AppSettings) {
        do {
            try settingsRepo.save(new)
            settings = new
        } catch {
            lastError = "Save settings failed: \(error.localizedDescription)"
        }
    }

    // MARK: - 描述

    func loadDescription(for id: UUID) {
        do {
            currentDescription = try repo.loadDescription(taskId: id)
        } catch {
            currentDescription = ""
            lastError = "Load description failed: \(error.localizedDescription)"
        }
    }

    func saveDescription() {
        guard let id = selectedTaskId else { return }
        do {
            try repo.saveDescription(taskId: id, markdown: currentDescription)
        } catch { lastError = "Save description failed: \(error.localizedDescription)" }
    }

    func descriptionURL(for id: UUID) -> URL {
        repo.layout.descriptionURL(for: id)
    }

    // MARK: - private

    private func clearCompletedDay(_ day: Day) {
        guard completedDays.contains(day) else { return }
        completedDays.remove(day)
        saveCompletedDays()
    }

    private func saveCompletedDays() {
        do {
            try repo.saveCompletedDays(completedDays)
        } catch {
            lastError = "Save completed days failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func persist(_ agg: inout TaskAggregate, at idx: Int) -> Bool {
        do {
            try repo.save(&agg)
            tasks[idx] = agg
            return true
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    /// 详情页展示 / 新建时间记录用的那天：上下文是某天 → 那天；Backlog → 最后一个关联日（空则今天）
    func entryDay(for agg: TaskAggregate) -> Day {
        entryDay(for: agg, in: contextFilter)
    }

    func entryDay(for agg: TaskAggregate, in context: TaskFilter) -> Day {
        switch context {
        case .day(let d): return d
        case .backlog:
            return agg.meta.membership.dayAssignments.map(\.day).max() ?? Day.today()
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.repo.hasExternalChanges() {
                    self.reload()
                }
            }
        }
    }
}
