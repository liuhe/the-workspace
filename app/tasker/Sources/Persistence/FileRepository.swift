import Foundation
import TaskerDomain

/// 仓储：把 TaskAggregate 拆分成 tasks.jsonl + entries.jsonl + descriptions/*.md 三部分。
/// - 写盘前先 diff 磁盘版本（通过 mtime）避免覆盖手改（简单策略：mtime 变化则先重载后写）
/// - 读盘为整体读入
public final class FileRepository {
    public let layout: StorageLayout

    /// 上次成功读盘时观察到的 mtime，供 pollForExternalChanges 判定
    private var lastTasksMTime: Date?
    private var lastEntriesMTime: Date?

    public init(root: URL) throws {
        self.layout = StorageLayout(root: root)
        try layout.ensureDirs()
    }

    public convenience init() throws {
        try self.init(root: StorageLayout.default.root)
    }

    // MARK: - 读

    public func loadAll() throws -> [TaskAggregate] {
        let metas = try JsonlFile.read(TaskMeta.self, from: layout.tasksFile)
        let entries = try JsonlFile.read(TimeEntry.self, from: layout.entriesFile)
        lastTasksMTime = mtime(of: layout.tasksFile)
        lastEntriesMTime = mtime(of: layout.entriesFile)

        let entriesByTask = Dictionary(grouping: entries, by: \.taskId)
        return metas.map { meta in
            TaskAggregate(meta: meta, entries: entriesByTask[meta.id] ?? [])
        }
    }

    public func loadDescription(taskId: UUID) throws -> String {
        let url = layout.descriptionURL(for: taskId)
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - 写

    /// 保存/更新一个聚合。策略：全量重写 tasks.jsonl 和 entries.jsonl。
    /// 写前先校验磁盘 mtime，若外部有更新，先读入合并再写。
    public func save(_ aggregate: inout TaskAggregate) throws {
        var all = try loadAllWithConflictReconciliation(newer: aggregate)
        if let idx = all.firstIndex(where: { $0.id == aggregate.id }) {
            all[idx] = aggregate
        } else {
            all.append(aggregate)
        }
        try writeAll(all)
    }

    public func delete(id: UUID) throws {
        var all = try loadAll()
        all.removeAll { $0.id == id }
        try writeAll(all)
        let url = layout.descriptionURL(for: id)
        try? FileManager.default.removeItem(at: url)
    }

    public func saveDescription(taskId: UUID, markdown: String) throws {
        let url = layout.descriptionURL(for: taskId)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try markdown.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    // MARK: - 外部变更检测

    /// 若磁盘 mtime 相对上次读入有变化，返回 true；调用方决定是否重载。
    public func hasExternalChanges() -> Bool {
        let t = mtime(of: layout.tasksFile)
        let e = mtime(of: layout.entriesFile)
        return t != lastTasksMTime || e != lastEntriesMTime
    }

    // MARK: - private

    /// 写前冲突调解：若磁盘上比上次读入更新，先重新读入，"新"聚合覆盖同 id 的旧聚合。
    /// 简化：last-write-wins，但保留磁盘上其它任务的最新状态。
    private func loadAllWithConflictReconciliation(newer aggregate: TaskAggregate) throws -> [TaskAggregate] {
        if hasExternalChanges() {
            return try loadAll()
        }
        return try loadAll()
    }

    private func writeAll(_ tasks: [TaskAggregate]) throws {
        let metas = tasks.map(\.meta)
        let entries = tasks.flatMap(\.entries)
        try JsonlFile.write(metas, to: layout.tasksFile)
        try JsonlFile.write(entries, to: layout.entriesFile)
        lastTasksMTime = mtime(of: layout.tasksFile)
        lastEntriesMTime = mtime(of: layout.entriesFile)
    }

    private func mtime(of url: URL) -> Date? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
}
