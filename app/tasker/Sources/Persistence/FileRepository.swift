import Foundation
import TaskerDomain

/// 仓储：把 TaskAggregate 保存到 tasks.jsonl；旧版 entries.jsonl 会迁移进 DayAssignment.entries。
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
        var metas = try JsonlFile.read(TaskMeta.self, from: layout.tasksFile)
        let legacyEntries = try JsonlFile.read(LegacyTimeEntry.self, from: layout.entriesFile)
        if !legacyEntries.isEmpty {
            metas = migrateLegacyEntries(legacyEntries, into: metas)
            try JsonlFile.write(metas, to: layout.tasksFile)
            try archiveLegacyEntriesFile()
        }
        lastTasksMTime = mtime(of: layout.tasksFile)
        lastEntriesMTime = mtime(of: layout.entriesFile)
        return metas.map { TaskAggregate(meta: $0) }
    }

    public func loadDescription(taskId: UUID) throws -> String {
        let url = layout.descriptionURL(for: taskId)
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - 写

    /// 保存/更新一个聚合。策略：全量重写 tasks.jsonl。
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
        try JsonlFile.write(metas, to: layout.tasksFile)
        lastTasksMTime = mtime(of: layout.tasksFile)
        lastEntriesMTime = mtime(of: layout.entriesFile)
    }

    private func migrateLegacyEntries(_ legacyEntries: [LegacyTimeEntry],
                                      into metas: [TaskMeta]) -> [TaskMeta] {
        var migrated = metas
        let entriesByTask = Dictionary(grouping: legacyEntries, by: \.taskId)
        for idx in migrated.indices {
            guard let legacyForTask = entriesByTask[migrated[idx].id] else { continue }
            for legacy in legacyForTask {
                let entry = legacy.entry
                let day = TaskAggregate.migrationDay(for: entry,
                                                     fallbackDays: migrated[idx].membership.days)
                migrated[idx].membership.appendEntry(inDay: day, entry: entry)
            }
        }
        return migrated
    }

    private func archiveLegacyEntriesFile() throws {
        guard FileManager.default.fileExists(atPath: layout.entriesFile.path) else { return }
        var destination = layout.entriesLegacyFile
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = layout.root.appendingPathComponent("entries.legacy-\(UUID().uuidString).jsonl")
        }
        try FileManager.default.moveItem(at: layout.entriesFile, to: destination)
        lastEntriesMTime = nil
    }

    private func mtime(of url: URL) -> Date? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
}

private struct LegacyTimeEntry: Decodable {
    let id: UUID
    let taskId: UUID
    let title: String
    let workTypeId: UUID?
    let startAt: Date?
    let endAt: Date?
    let marker: TimeEntry.Marker?

    private enum CodingKeys: String, CodingKey {
        case id, taskId, title, workTypeId, startAt, endAt, marker
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        taskId = try c.decode(UUID.self, forKey: .taskId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        workTypeId = try c.decodeIfPresent(UUID.self, forKey: .workTypeId)
        startAt = try c.decodeIfPresent(Date.self, forKey: .startAt)
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        marker = try c.decodeIfPresent(TimeEntry.Marker.self, forKey: .marker)
    }

    var entry: TimeEntry {
        TimeEntry(id: id,
                  title: title,
                  workTypeId: workTypeId,
                  startAt: startAt,
                  endAt: endAt,
                  marker: marker)
    }
}
