import Foundation

public enum TaskFilter: Hashable, Sendable {
    case day(Day)
    case backlog
}

public enum TaskQueries {
    public static func apply(_ filter: TaskFilter,
                             currentOnly: Bool = false,
                             hideCompleted: Bool = false,
                             hideNotStarted: Bool = false,
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
        if hideCompleted {
            filtered = filtered.filter { $0.status(in: filter) != .done }
        }
        if hideNotStarted {
            filtered = filtered.filter { $0.status(in: filter) != .notStarted }
        }
        return sortForDisplay(filtered, in: filter)
    }

    /// 排序规则：
    /// - `.day(d)`：先看当天最早 `startAt`（有的靠前、按升序；都没有则并列进入下一档），再按 priority，最后 updatedAt 降序
    /// - `.backlog`：按 priority，再按 updatedAt 降序（时间排序不适用）
    public static func sortForDisplay(_ tasks: [TaskAggregate], in filter: TaskFilter) -> [TaskAggregate] {
        tasks.sorted { a, b in
            if case .day(let d) = filter {
                let sa = a.entries(inDay: d).compactMap(\.startAt).min()
                let sb = b.entries(inDay: d).compactMap(\.startAt).min()
                switch (sa, sb) {
                case (let x?, let y?):
                    if x != y { return x < y }
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): break
                }
            }
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
