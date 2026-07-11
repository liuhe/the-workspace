import Foundation

/// 任务与"某天集合"的关联；priority 和 isCurrent 都是这条关联的属性，不同天独立。
public struct DayAssignment: Hashable, Sendable {
    public var day: Day
    public var priority: Priority
    /// 该任务在这一天是否被标记为"当前"
    public var isCurrent: Bool

    public init(day: Day, priority: Priority = .normal, isCurrent: Bool = false) {
        self.day = day
        self.priority = priority
        self.isCurrent = isCurrent
    }
}

extension DayAssignment: Codable {
    // isCurrent 是新字段；老数据缺失时默认 false
    private enum CodingKeys: String, CodingKey { case day, priority, isCurrent }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.day = try c.decode(Day.self, forKey: .day)
        self.priority = try c.decode(Priority.self, forKey: .priority)
        self.isCurrent = try c.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
    }
}

public struct Membership: Codable, Hashable, Sendable {
    public var dayAssignments: [DayAssignment]

    public init(dayAssignments: [DayAssignment] = []) {
        self.dayAssignments = dayAssignments
    }

    public var days: Set<Day> { Set(dayAssignments.map(\.day)) }
    public var isInAnyCollection: Bool { !dayAssignments.isEmpty }

    /// 任何一天被标记为"当前"，则任务"被视作在当前集合里"
    public var hasAnyCurrent: Bool { dayAssignments.contains(where: { $0.isCurrent }) }

    public func priority(inDay day: Day) -> Priority? {
        dayAssignments.first(where: { $0.day == day })?.priority
    }

    public func isCurrent(inDay day: Day) -> Bool {
        dayAssignments.first(where: { $0.day == day })?.isCurrent ?? false
    }

    public mutating func upsertDay(_ day: Day, priority: Priority = .normal) {
        if !dayAssignments.contains(where: { $0.day == day }) {
            dayAssignments.append(DayAssignment(day: day, priority: priority))
        }
    }

    public mutating func setPriority(inDay day: Day, priority: Priority) {
        if let idx = dayAssignments.firstIndex(where: { $0.day == day }) {
            dayAssignments[idx].priority = priority
        } else {
            dayAssignments.append(DayAssignment(day: day, priority: priority))
        }
    }

    public mutating func setIsCurrent(inDay day: Day, isCurrent: Bool) {
        if let idx = dayAssignments.firstIndex(where: { $0.day == day }) {
            dayAssignments[idx].isCurrent = isCurrent
        }
    }

    public mutating func removeDay(_ day: Day) {
        dayAssignments.removeAll { $0.day == day }
    }
}


public struct TaskMeta: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var categoryId: UUID?
    public var membership: Membership
    /// 循环任务：done 状态按天独立，且始终出现在 Backlog。
    public var isRecurring: Bool

    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(),
                title: String,
                categoryId: UUID? = nil,
                membership: Membership = Membership(),
                isRecurring: Bool = false,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.categoryId = categoryId
        self.membership = membership
        self.isRecurring = isRecurring
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension TaskMeta: Codable {
    // 新增的可选字段用 decodeIfPresent 兜住；不是"旧格式迁移"，而是新字段用默认值填。
    private enum CodingKeys: String, CodingKey {
        case id, title, categoryId, membership, isRecurring, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.categoryId = try c.decodeIfPresent(UUID.self, forKey: .categoryId)
        self.membership = try c.decode(Membership.self, forKey: .membership)
        self.isRecurring = try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

public struct TaskAggregate: Identifiable, Sendable, Hashable {
    public var meta: TaskMeta
    public var entries: [TimeEntry]

    public init(meta: TaskMeta, entries: [TimeEntry] = []) {
        self.meta = meta
        self.entries = entries.sorted(by: Self.entrySortComparator)
    }

    public var id: UUID { meta.id }
    /// 全局状态：所有时间记录汇总
    public var status: TaskStatus { StatusDeriver.derive(from: entries) }
    public var openEntry: TimeEntry? { entries.first(where: { $0.isOpen }) }

    /// 某天的状态：只看 startAt 落在该天的时间记录
    public func statusForDay(_ day: Day, calendar: Calendar = .current) -> TaskStatus {
        let dayEntries = entries.filter { e in
            guard let s = e.startAt else { return false }
            return Day(date: s, calendar: calendar) == day
        }
        return StatusDeriver.derive(from: dayEntries)
    }

    /// 上下文相关的状态：
    /// - 循环任务在 .day(d) 视图 → statusForDay(d)
    /// - 否则 → 全局 status
    public func status(in filter: TaskFilter) -> TaskStatus {
        if meta.isRecurring, case .day(let d) = filter {
            return statusForDay(d)
        }
        return status
    }

    /// 上下文相关的优先级（用于列表展示、排序）
    public func priority(in filter: TaskFilter) -> Priority {
        switch filter {
        case .day(let d):
            return meta.membership.priority(inDay: d) ?? .normal
        case .backlog:
            // Backlog 视图不区分优先级；同优先级按 updatedAt 排
            return .normal
        }
    }

    // MARK: - 时间记录命令

    @discardableResult
    public mutating func addEntry(title: String = "",
                                  workTypeId: UUID? = nil) -> UUID {
        let entry = TimeEntry(
            taskId: meta.id,
            title: title,
            workTypeId: workTypeId,
            startAt: nil,
            endAt: nil,
            marker: nil
        )
        entries.append(entry)
        meta.updatedAt = Date()
        return entry.id
    }

    public mutating func startEntry(id: UUID, now: Date = Date()) throws {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else {
            throw TaskCommandError.entryNotFound
        }
        guard entries[idx].startAt == nil else {
            throw TaskCommandError.entryAlreadyStarted
        }
        if openEntry != nil { throw TaskCommandError.alreadyInProgress }
        let wasDone = status == .done
        entries[idx].startAt = now
        if wasDone { entries[idx].marker = .restart }
        meta.updatedAt = now
        entries.sort(by: Self.entrySortComparator)
    }

    public mutating func endEntry(id: UUID, now: Date = Date()) throws {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else {
            throw TaskCommandError.entryNotFound
        }
        guard entries[idx].startAt != nil else {
            throw TaskCommandError.entryNotStarted
        }
        guard entries[idx].endAt == nil else {
            throw TaskCommandError.entryAlreadyEnded
        }
        entries[idx].endAt = now
        meta.updatedAt = now
    }

    public mutating func updateEntry(id: UUID, mutate: (inout TimeEntry) -> Void) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[idx])
        entries.sort(by: Self.entrySortComparator)
        meta.updatedAt = Date()
    }

    public mutating func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        meta.updatedAt = Date()
    }

    private static func entrySortComparator(_ a: TimeEntry, _ b: TimeEntry) -> Bool {
        switch (a.startAt, b.startAt) {
        case let (l?, r?): return l < r
        case (nil, _?):    return false
        case (_?, nil):    return true
        case (nil, nil):   return false
        }
    }
}

public enum TaskCommandError: Error, LocalizedError {
    case alreadyInProgress
    case entryNotFound
    case entryAlreadyStarted
    case entryAlreadyEnded
    case entryNotStarted

    public var errorDescription: String? {
        switch self {
        case .alreadyInProgress: return "Another entry is already in progress"
        case .entryNotFound: return "Entry not found"
        case .entryAlreadyStarted: return "Entry already started"
        case .entryAlreadyEnded: return "Entry already ended"
        case .entryNotStarted: return "Entry not started yet"
        }
    }
}
