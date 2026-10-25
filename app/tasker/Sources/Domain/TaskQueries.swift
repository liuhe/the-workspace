import Foundation

/// 任务行的上下文：状态 / 优先级 / 当前标都相对于某天或 Backlog 计算。
public enum TaskFilter: Hashable, Sendable {
    case day(Day)
    case backlog
}

/// 侧栏列表范围：某天 / Backlog 对应单个 TaskFilter；所有日期把每一天 + Backlog 排开。
public enum ListScope: Hashable, Sendable {
    case day(Day)
    case backlog
    case allDays

    /// 单上下文范围对应的 TaskFilter；`.allDays` 没有单一上下文，返回 nil
    public var filter: TaskFilter? {
        switch self {
        case .day(let d): return .day(d)
        case .backlog: return .backlog
        case .allDays: return nil
        }
    }
}

/// 所有日期视图里的一个分组：某天或 Backlog，内部已按分类分组。
public struct DayGroup: Sendable {
    public let context: TaskFilter
    public let categories: [(CategoryDef, [TaskAggregate])]

    public init(context: TaskFilter, categories: [(CategoryDef, [TaskAggregate])]) {
        self.context = context
        self.categories = categories
    }

    public var tasks: [TaskAggregate] { categories.flatMap { $0.1 } }
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
                let sa = a.entries(inDay: d).compactMap { $0.startAt(inDay: d) }.min()
                let sb = b.entries(inDay: d).compactMap { $0.startAt(inDay: d) }.min()
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

    /// 所有日期视图：出现过的每一天按升序各成一组，Backlog 作为最后一组；
    /// 每组内按该组上下文过滤、排序再按分类分组；过滤后为空的组不返回。
    public static func groupAllDays(_ tasks: [TaskAggregate],
                                    categories: [CategoryDef],
                                    currentOnly: Bool = false,
                                    hideCompleted: Bool = false,
                                    hideNotStarted: Bool = false) -> [DayGroup]
    {
        var days: Set<Day> = []
        for t in tasks { days.formUnion(t.meta.membership.days) }
        var contexts: [TaskFilter] = days.sorted().map { .day($0) }
        contexts.append(.backlog)
        return contexts.compactMap { context in
            let filtered = apply(context,
                                 currentOnly: currentOnly,
                                 hideCompleted: hideCompleted,
                                 hideNotStarted: hideNotStarted,
                                 to: tasks)
            guard !filtered.isEmpty else { return nil }
            return DayGroup(context: context,
                            categories: groupByCategory(filtered, categories: categories))
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
