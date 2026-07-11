import Foundation
import SwiftUI
import TaskerDomain
import TaskerPersistence

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var tasks: [TaskAggregate] = []
    @Published var dayFilter: TaskFilter = .day(Day.today())
    @Published var showCurrent: Bool = false
    @Published var selectedTaskId: UUID?
    @Published var currentDescription: String = ""
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
            currentDescription = ""
            reload()
            reloadSettings()
        } catch {
            lastError = "Failed to change data root: \(error.localizedDescription)"
        }
    }

    var filteredTasks: [TaskAggregate] {
        TaskQueries.apply(dayFilter, currentOnly: showCurrent, to: tasks)
    }

    var groupedFilteredTasks: [(CategoryDef, [TaskAggregate])] {
        TaskQueries.groupByCategory(filteredTasks, categories: settings.categories)
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

    /// 当前过滤下选中的任务已不在列表里时，清空选中和描述。
    /// 由 filter 切换（dayFilter / showCurrent）触发；任务自身变动不触发。
    func pruneSelectionIfOffscreen() {
        guard let id = selectedTaskId else { return }
        if !filteredTasks.contains(where: { $0.id == id }) {
            selectedTaskId = nil
            currentDescription = ""
        }
    }

    // MARK: - 加载

    func reload() {
        do {
            tasks = try repo.loadAll()
            if let id = selectedTaskId, !tasks.contains(where: { $0.id == id }) {
                selectedTaskId = nil
                currentDescription = ""
            }
        } catch {
            lastError = "Load failed: \(error.localizedDescription)"
        }
    }

    // MARK: - 任务

    func createTask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var meta = TaskMeta(title: trimmed, categoryId: nil)
        if case .day(let d) = dayFilter {
            meta.membership.upsertDay(d)   // priority=normal by default
        }
        if showCurrent {
            meta.membership.isCurrent = true
        }
        var agg = TaskAggregate(meta: meta)
        do {
            try repo.save(&agg)
            tasks.append(agg)
            selectedTaskId = agg.id
            currentDescription = ""
        } catch {
            lastError = "Create failed: \(error.localizedDescription)"
        }
    }

    func deleteTask(id: UUID) {
        do {
            try repo.delete(id: id)
            tasks.removeAll { $0.id == id }
            if selectedTaskId == id { selectedTaskId = nil; currentDescription = "" }
        } catch {
            lastError = "Delete failed: \(error.localizedDescription)"
        }
    }

    func updateMeta(id: UUID, _ mutate: (inout TaskMeta) -> Void) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        var agg = tasks[idx]
        mutate(&agg.meta)
        agg.meta.updatedAt = Date()
        persist(&agg, at: idx)
    }

    /// 直接改某天关联的优先级（哪一天由调用方指定；给详情里的 chip / 列表右键用）
    func setPriority(id: UUID, inDay day: Day, priority: Priority) {
        updateMeta(id: id) { $0.membership.setPriority(inDay: day, priority: priority) }
    }

    /// 改"当前"关联的优先级
    func setCurrentPriority(id: UUID, priority: Priority) {
        updateMeta(id: id) { $0.membership.currentPriority = priority }
    }

    /// 在当前 filter 上下文改优先级；filter=.day(d) → 改那天；filter=.backlog → 若在当前，改 currentPriority
    func setPriorityInFilterContext(id: UUID, priority: Priority) {
        switch dayFilter {
        case .day(let d):
            setPriority(id: id, inDay: d, priority: priority)
        case .backlog:
            updateMeta(id: id) { meta in
                if meta.membership.isCurrent {
                    meta.membership.currentPriority = priority
                }
            }
        }
    }

    func addToDay(id: UUID, day: Day) {
        updateMeta(id: id) { $0.membership.upsertDay(day) }
    }

    func removeFromDay(id: UUID, day: Day) {
        updateMeta(id: id) { $0.membership.removeDay(day) }
    }

    func clearAllDays(id: UUID) {
        updateMeta(id: id) { $0.membership.dayAssignments.removeAll() }
    }

    func setIsCurrent(id: UUID, isCurrent: Bool) {
        updateMeta(id: id) { $0.membership.isCurrent = isCurrent }
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
        for c in candidates {
            let srcPriority = c.meta.membership.priority(inDay: sourceDay) ?? .normal
            updateMeta(id: c.id) { meta in
                if meta.membership.priority(inDay: targetDay) == nil {
                    meta.membership.upsertDay(targetDay, priority: srcPriority)
                }
            }
        }
        return candidates.count
    }

    // MARK: - 时间记录

    func addEntry(taskId: UUID, title: String = "", workTypeId: UUID? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var agg = tasks[idx]
        // 默认预选第一个工作类型
        let defaultId = workTypeId ?? settings.workTypes.first?.id
        agg.addEntry(title: title, workTypeId: defaultId)
        persist(&agg, at: idx)
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

    // MARK: - private

    private func persist(_ agg: inout TaskAggregate, at idx: Int) {
        do {
            try repo.save(&agg)
            tasks[idx] = agg
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.repo.hasExternalChanges() {
                    self.reload()
                }
            }
        }
    }
}
