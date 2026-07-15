import Foundation

/// 任务与"某天集合"的关联；priority、isCurrent 和 entries 都是这条关联的属性，不同天独立。
public struct DayAssignment: Hashable, Sendable {
    public var day: Day
    public var priority: Priority
    /// 该任务在这一天是否被标记为"当前"
    public var isCurrent: Bool
    public var entries: [TimeEntry]

    public init(day: Day,
                priority: Priority = .normal,
                isCurrent: Bool = false,
                entries: [TimeEntry] = []) {
        self.day = day
        self.priority = priority
        self.isCurrent = isCurrent
        self.entries = entries.sorted(by: Self.entrySortComparator)
    }

    public mutating func sortEntries() {
        entries.sort(by: Self.entrySortComparator)
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

extension DayAssignment: Codable {
    // entries 是新字段；老数据缺失时默认空数组
    private enum CodingKeys: String, CodingKey { case day, priority, isCurrent, entries }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.day = try c.decode(Day.self, forKey: .day)
        self.priority = try c.decode(Priority.self, forKey: .priority)
        self.isCurrent = try c.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        self.entries = try c.decodeIfPresent([TimeEntry].self, forKey: .entries) ?? []
        sortEntries()
    }
}

public struct Membership: Codable, Hashable, Sendable {
    public var dayAssignments: [DayAssignment]

    public init(dayAssignments: [DayAssignment] = []) {
        self.dayAssignments = dayAssignments.sorted { $0.day < $1.day }
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

    public func entries(inDay day: Day) -> [TimeEntry] {
        dayAssignments.first(where: { $0.day == day })?.entries ?? []
    }

    public func hasEntries(inDay day: Day) -> Bool {
        !(dayAssignments.first(where: { $0.day == day })?.entries.isEmpty ?? true)
    }

    public func day(containingEntry entryId: UUID) -> Day? {
        dayAssignments.first(where: { a in
            a.entries.contains(where: { $0.id == entryId })
        })?.day
    }

    public mutating func upsertDay(_ day: Day, priority: Priority = .normal, isCurrent: Bool = false) {
        if !dayAssignments.contains(where: { $0.day == day }) {
            dayAssignments.append(DayAssignment(day: day, priority: priority, isCurrent: isCurrent))
            dayAssignments.sort { $0.day < $1.day }
        }
    }

    public mutating func setPriority(inDay day: Day, priority: Priority) {
        if let idx = dayAssignments.firstIndex(where: { $0.day == day }) {
            dayAssignments[idx].priority = priority
        } else {
            dayAssignments.append(DayAssignment(day: day, priority: priority))
            dayAssignments.sort { $0.day < $1.day }
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

    @discardableResult
    public mutating func appendEntry(inDay day: Day,
                                     priority: Priority = .normal,
                                     isCurrent: Bool = false,
                                     entry: TimeEntry) -> UUID {
        upsertDay(day, priority: priority, isCurrent: isCurrent)
        guard let idx = dayAssignments.firstIndex(where: { $0.day == day }) else { return entry.id }
        dayAssignments[idx].entries.append(entry)
        dayAssignments[idx].sortEntries()
        return entry.id
    }

    public mutating func updateEntry(id: UUID, mutate: (inout TimeEntry) -> Void) -> Bool {
        for assignmentIndex in dayAssignments.indices {
            if let entryIndex = dayAssignments[assignmentIndex].entries.firstIndex(where: { $0.id == id }) {
                mutate(&dayAssignments[assignmentIndex].entries[entryIndex])
                dayAssignments[assignmentIndex].sortEntries()
                return true
            }
        }
        return false
    }

    public mutating func deleteEntry(id: UUID) -> Bool {
        for assignmentIndex in dayAssignments.indices {
            let before = dayAssignments[assignmentIndex].entries.count
            dayAssignments[assignmentIndex].entries.removeAll { $0.id == id }
            if dayAssignments[assignmentIndex].entries.count != before { return true }
        }
        return false
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

    public init(meta: TaskMeta, entries: [TimeEntry] = []) {
        self.meta = meta
        for entry in entries {
            let day = Self.migrationDay(for: entry, fallbackDays: meta.membership.days)
            self.meta.membership.appendEntry(inDay: day, entry: entry)
        }
    }

    public var id: UUID { meta.id }
    public var entries: [TimeEntry] { meta.membership.dayAssignments.flatMap(\.entries).sorted(by: Self.entrySortComparator) }
    /// 全局状态：所有日期关联下的时间记录汇总
    public var status: TaskStatus { StatusDeriver.derive(from: entries) }
    public var openEntry: TimeEntry? { entries.first(where: { $0.isOpen }) }

    public func entries(inDay day: Day) -> [TimeEntry] {
        meta.membership.entries(inDay: day)
    }

    /// 某天的状态：只看该天关联下的时间记录
    public func statusForDay(_ day: Day, calendar: Calendar = .current) -> TaskStatus {
        StatusDeriver.derive(from: entries(inDay: day))
    }

    /// 上下文相关的状态：
    /// - 循环任务在 .day(d) 视图 → statusForDay(d)
    /// - 循环任务在 Backlog 视图 → notStarted
    /// - 否则 → 全局 status
    public func status(in filter: TaskFilter) -> TaskStatus {
        if meta.isRecurring {
            switch filter {
            case .day(let d): return statusForDay(d)
            case .backlog: return .notStarted
            }
        }
        return status
    }

    /// 上下文相关的优先级（用于列表展示、排序）
    public func priority(in filter: TaskFilter) -> Priority {
        switch filter {
        case .day(let d):
            return meta.membership.priority(inDay: d) ?? .normal
        case .backlog:
            // Backlog 视图：用最后一天关联的优先级作为前缀；没关联就 normal
            let sorted = meta.membership.dayAssignments.sorted { $0.day < $1.day }
            return sorted.last?.priority ?? .normal
        }
    }

    // MARK: - 时间记录命令

    @discardableResult
    public mutating func addEntry(inDay day: Day,
                                  priority: Priority = .normal,
                                  isCurrent: Bool = false,
                                  title: String = "",
                                  workTypeId: UUID? = nil) -> UUID {
        let entry = TimeEntry(
            title: title,
            workTypeId: workTypeId,
            startAt: nil,
            endAt: nil,
            marker: nil
        )
        meta.membership.appendEntry(inDay: day, priority: priority, isCurrent: isCurrent, entry: entry)
        meta.updatedAt = Date()
        return entry.id
    }

    public mutating func startEntry(id: UUID, now: Date = Date()) throws {
        guard let day = meta.membership.day(containingEntry: id),
              let entry = entries.first(where: { $0.id == id }) else {
            throw TaskCommandError.entryNotFound
        }
        guard entry.startAt == nil else {
            throw TaskCommandError.entryAlreadyStarted
        }
        if openEntry != nil { throw TaskCommandError.alreadyInProgress }
        let wasDone = meta.isRecurring ? statusForDay(day) == .done : status == .done
        _ = meta.membership.updateEntry(id: id) { entry in
            entry.startAt = now
            if wasDone { entry.marker = .restart }
        }
        meta.updatedAt = now
    }

    public mutating func endEntry(id: UUID, now: Date = Date()) throws {
        guard let entry = entries.first(where: { $0.id == id }) else {
            throw TaskCommandError.entryNotFound
        }
        guard entry.startAt != nil else {
            throw TaskCommandError.entryNotStarted
        }
        guard entry.endAt == nil else {
            throw TaskCommandError.entryAlreadyEnded
        }
        _ = meta.membership.updateEntry(id: id) { $0.endAt = now }
        meta.updatedAt = now
    }

    public mutating func updateEntry(id: UUID, mutate: (inout TimeEntry) -> Void) {
        guard meta.membership.updateEntry(id: id, mutate: mutate) else { return }
        meta.updatedAt = Date()
    }

    public mutating func deleteEntry(id: UUID) {
        guard meta.membership.deleteEntry(id: id) else { return }
        meta.updatedAt = Date()
    }

    public static func migrationDay(for entry: TimeEntry,
                                    fallbackDays: Set<Day>,
                                    calendar: Calendar = .current) -> Day {
        if let s = entry.startAt { return Day(date: s, calendar: calendar) }
        if let e = entry.endAt { return Day(date: e, calendar: calendar) }
        return fallbackDays.min() ?? Day.today(calendar: calendar)
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
