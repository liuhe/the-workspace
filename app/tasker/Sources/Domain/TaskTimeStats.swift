import Foundation

// MARK: - 任务花费时间统计（跨日期合并）
//
// 统计窗口不再按天分组：日期区间内所有某天关联的时间记录按任务合并，
// 再按分类分组（顺序跟设置）。任务花费 = 其记录实际占用之和；
// 单条记录实际占用 = 手动分钟数（actualMinutes）优先，否则 结束 − 开始（按所属天锚定）。

/// 一条时间记录 + 它所属的那天（某天关联的 day）
public struct DatedEntry: Identifiable, Hashable, Sendable {
    public let day: Day
    public let entry: TimeEntry
    public var id: UUID { entry.id }

    public init(day: Day, entry: TimeEntry) {
        self.day = day
        self.entry = entry
    }

    public func startAt(calendar: Calendar = .current) -> Date? { entry.startAt(inDay: day, calendar: calendar) }
    public func endAt(calendar: Calendar = .current) -> Date? { entry.endAt(inDay: day, calendar: calendar) }

    /// 实际占用；未结束且没手填 → 0
    public func duration(calendar: Calendar = .current) -> TimeInterval {
        entry.effectiveDuration(inDay: day, calendar: calendar) ?? 0
    }
}

public struct TaskTimeStat: Identifiable {
    public let task: TaskAggregate
    /// 按 (天, 开始时间) 升序；未开始的排在该天最后
    public let entries: [DatedEntry]
    public var id: UUID { task.id }
    public var totalDuration: TimeInterval { entries.reduce(0) { $0 + $1.duration() } }
}

public struct CategoryTimeStat: Identifiable {
    public let def: CategoryDef
    /// 设置里的槽位（用于自动色）；未知 / 未设置分类为 nil
    public let slot: Int?
    /// 组内按花费时长降序
    public let tasks: [TaskTimeStat]
    public var id: UUID { def.id }
    public var totalDuration: TimeInterval { tasks.reduce(0) { $0 + $1.totalDuration } }
}

public enum TaskTimeStats {
    /// `range` 非 nil 时只统计落在闭区间内的某天关联；没有任何记录的任务不出现。
    public static func build(from tasks: [TaskAggregate],
                             categories: [CategoryDef],
                             range: ClosedRange<Day>? = nil,
                             calendar: Calendar = .current) -> [CategoryTimeStat] {
        let stats: [TaskTimeStat] = tasks.compactMap { t in
            var dated: [DatedEntry] = []
            for a in t.meta.membership.dayAssignments {
                if let range, !range.contains(a.day) { continue }
                dated.append(contentsOf: a.entries.map { DatedEntry(day: a.day, entry: $0) })
            }
            guard !dated.isEmpty else { return nil }
            dated.sort {
                if $0.day != $1.day { return $0.day < $1.day }
                return ($0.startAt(calendar: calendar) ?? .distantFuture) < ($1.startAt(calendar: calendar) ?? .distantFuture)
            }
            return TaskTimeStat(task: t, entries: dated)
        }.sorted { $0.totalDuration > $1.totalDuration }

        let statByTask = Dictionary(uniqueKeysWithValues: stats.map { ($0.task.id, $0) })
        return TaskQueries.groupByCategory(stats.map(\.task), categories: categories).map { (def, ts) in
            CategoryTimeStat(def: def,
                             slot: categories.firstIndex(where: { $0.id == def.id }),
                             tasks: ts.compactMap { statByTask[$0.id] })
        }
    }
}
