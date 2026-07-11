import Foundation

public enum TaskFilter: Hashable, Sendable {
    case day(Day)
    case backlog
}

public enum TaskQueries {
    public static func apply(_ filter: TaskFilter,
                             currentOnly: Bool = false,
                             to tasks: [TaskAggregate]) -> [TaskAggregate] {
        var filtered: [TaskAggregate]
        switch filter {
        case .day(let d):
            filtered = tasks.filter { $0.meta.membership.days.contains(d) }
        case .backlog:
            // Backlog = 未完成任务；循环任务永远在 Backlog
            filtered = tasks.filter { $0.status != .done || $0.meta.isRecurring }
        }
        if currentOnly {
            // isCurrent 是 DayAssignment 的属性：
            // - .day(d) 视图：那天的 assignment.isCurrent == true
            // - .backlog 视图：任何一天的 assignment.isCurrent == true
            switch filter {
            case .day(let d):
                filtered = filtered.filter { $0.meta.membership.isCurrent(inDay: d) }
            case .backlog:
                filtered = filtered.filter { $0.meta.membership.hasAnyCurrent }
            }
        }
        return sortForDisplay(filtered, in: filter)
    }

    /// 按上下文里的 priority 排序（emoji 高→emoji 低），同优先级按 updatedAt 倒序。
    public static func sortForDisplay(_ tasks: [TaskAggregate], in filter: TaskFilter) -> [TaskAggregate] {
        tasks.sorted { a, b in
            let pa = a.priority(in: filter)
            let pb = b.priority(in: filter)
            if pa != pb { return pa < pb }
            return a.meta.updatedAt > b.meta.updatedAt
        }
    }

    /// 按分类分组：以 CategoryDef 数组为顺序，未在配置里的 id 归入"(未知)"，
    /// nil categoryId 归入"(未设置)"。传入的 tasks 应已按需排过序。
    public static func groupByCategory(_ tasks: [TaskAggregate],
                                       categories: [CategoryDef])
        -> [(CategoryDef, [TaskAggregate])]
    {
        var buckets: [UUID?: [TaskAggregate]] = [:]
        for t in tasks {
            buckets[t.meta.categoryId, default: []].append(t)
        }
        var result: [(CategoryDef, [TaskAggregate])] = []
        var used: Set<UUID> = []
        for def in categories {
            if let arr = buckets[def.id], !arr.isEmpty {
                result.append((def, arr))
                used.insert(def.id)
            }
        }
        for (id, arr) in buckets where id != nil {
            guard let uid = id, !used.contains(uid) else { continue }
            let placeholder = CategoryDef(id: uid, name: SettingsLookup.unknownName)
            result.append((placeholder, arr))
        }
        if let arr = buckets[nil], !arr.isEmpty {
            let placeholder = CategoryDef(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                name: SettingsLookup.unsetName
            )
            result.append((placeholder, arr))
        }
        return result
    }
}
