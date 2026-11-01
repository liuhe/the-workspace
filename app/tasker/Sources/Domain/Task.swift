import Foundation

/// 任务与"某天集合"的关联；priority、isCurrent 和 entries 都是这条关联的属性，不同天独立。
public struct DayAssignment: Hashable, Sendable {
    public var day: Day
    public var priority: Priority
    /// 该任务在这一天是否被标记为"当前"
    public var isCurrent: Bool
    /// 该任务这一天的活是否已完成；任务整体 `isDone` 为真时忽略
    public var isDone: Bool
    public var entries: [TimeEntry]

    public init(day: Day,
                priority: Priority = .normal,
                isCurrent: Bool = false,
                isDone: Bool = false,
                entries: [TimeEntry] = []) {
        self.day = day
        self.priority = priority
        self.isCurrent = isCurrent
        self.isDone = isDone
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
    // entries / isDone 是后加字段；老数据缺失时默认空数组 / false
    private enum CodingKeys: String, CodingKey { case day, priority, isCurrent, isDone, entries }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.day = try c.decode(Day.self, forKey: .day)
        self.priority = try c.decode(Priority.self, forKey: .priority)
        self.isCurrent = try c.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        self.isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
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

    public func isDone(inDay day: Day) -> Bool {
        dayAssignments.first(where: { $0.day == day })?.isDone ?? false
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

    /// 只对已关联的那天生效；未关联的日子不会因此被建立关联
    public mutating func setIsDone(inDay day: Day, isDone: Bool) {
        if let idx = dayAssignments.firstIndex(where: { $0.day == day }) {
            dayAssignments[idx].isDone = isDone
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

    /// 把一条记录移到另一天：目标日尚未关联时先建立关联（优先级复制自原来那天，不标当前）；
    /// 起止时间的日期部分改到目标日、时分不变；原来那天的关联保留（即使记录被移空）。
    /// 记录不存在或目标日就是原来那天 → false。
    @discardableResult
    public mutating func moveEntry(id: UUID, toDay target: Day, calendar: Calendar = .current) -> Bool {
        guard let sourceIndex = dayAssignments.firstIndex(where: { a in a.entries.contains(where: { $0.id == id }) }),
              let entryIndex = dayAssignments[sourceIndex].entries.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let source = dayAssignments[sourceIndex]
        guard source.day != target else { return false }
        var entry = dayAssignments[sourceIndex].entries.remove(at: entryIndex)
        entry.startAt = entry.startAt(inDay: target, calendar: calendar)
        entry.endAt = entry.endAt(inDay: target, calendar: calendar)
        appendEntry(inDay: target, priority: source.priority, entry: entry)
        return true
    }
}

public struct TaskMeta: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var categoryId: UUID?
    public var membership: Membership
    /// 循环任务：日常完成按天（DayAssignment.isDone）记录，且始终出现在 Backlog。
    public var isRecurring: Bool
    /// 任务整体完成；为真时任何上下文下状态都是 done，不再看某天完成标；也决定是否离开 Backlog
    public var isDone: Bool

    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(),
                title: String,
                categoryId: UUID? = nil,
                membership: Membership = Membership(),
                isRecurring: Bool = false,
                isDone: Bool = false,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.categoryId = categoryId
        self.membership = membership
        self.isRecurring = isRecurring
        self.isDone = isDone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension TaskMeta: Codable {
    // 新增的可选字段用 decodeIfPresent 兜住；不是"旧格式迁移"，而是新字段用默认值填。
    private enum CodingKeys: String, CodingKey {
        case id, title, categoryId, membership, isRecurring, isDone, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.categoryId = try c.decodeIfPresent(UUID.self, forKey: .categoryId)
        self.membership = try c.decode(Membership.self, forKey: .membership)
        self.isRecurring = try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
        self.isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
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
    /// 全局状态：整体完成标优先；否则按所有日期关联下的时间记录看是否有活动
    public var status: TaskStatus {
        meta.isDone ? .done : StatusDeriver.activity(from: entries)
    }
    public var openEntry: TimeEntry? { entries.first(where: { $0.isOpen }) }

    public func entries(inDay day: Day) -> [TimeEntry] {
        meta.membership.entries(inDay: day)
    }

    /// 某天的状态：整体完成 → done；该天完成标 → doneForDay；否则只看该天记录的活动
    public func statusForDay(_ day: Day, calendar: Calendar = .current) -> TaskStatus {
        if meta.isDone { return .done }
        if meta.membership.isDone(inDay: day) { return .doneForDay }
        return StatusDeriver.activity(from: entries(inDay: day))
    }

    /// 上下文相关的状态（整体完成在任何上下文都优先）：
    /// - .day(d)：该天完成标 → doneForDay；否则循环任务看该天记录、非循环任务看全部记录
    /// - .backlog：循环任务 → notStarted；否则全局 status
    public func status(in filter: TaskFilter) -> TaskStatus {
        if meta.isDone { return .done }
        switch filter {
        case .day(let d):
            if meta.isRecurring { return statusForDay(d) }
            if meta.membership.isDone(inDay: d) { return .doneForDay }
            return status
        case .backlog:
            return meta.isRecurring ? .notStarted : status
        }
    }

    /// "推到另一天"的候选判定：循环任务看该天完成标，非循环任务只看整体完成标
    /// （某天完成只是当天视图的标记，任务还没整体完成就仍要跟进）
    public func isUnfinished(inDay day: Day) -> Bool {
        if meta.isRecurring { return !meta.membership.isDone(inDay: day) }
        return !meta.isDone
    }

    // MARK: - 完成标命令

    public mutating func setIsDone(_ isDone: Bool, now: Date = Date()) {
        guard meta.isDone != isDone else { return }
        meta.isDone = isDone
        meta.updatedAt = now
    }

    public mutating func setDayDone(inDay day: Day, isDone: Bool, now: Date = Date()) {
        guard meta.membership.days.contains(day),
              meta.membership.isDone(inDay: day) != isDone else { return }
        meta.membership.setIsDone(inDay: day, isDone: isDone)
        meta.updatedAt = now
    }

    /// 历史回填：按旧的 marker 规则（`StatusDeriver.derive`）推导完成标。
    /// - 每个某天关联：该天记录推出 done → 该天 isDone
    /// - 非循环任务：全部记录推出 done → 整体 isDone（循环任务不设整体完成）
    /// 返回是否有任何变化；幂等。
    @discardableResult
    public mutating func backfillDoneFlags(now: Date = Date()) -> Bool {
        var changed = false
        for idx in meta.membership.dayAssignments.indices {
            let derived = StatusDeriver.derive(from: meta.membership.dayAssignments[idx].entries, now: now) == .done
            if meta.membership.dayAssignments[idx].isDone != derived {
                meta.membership.dayAssignments[idx].isDone = derived
                changed = true
            }
        }
        if !meta.isRecurring {
            let derived = StatusDeriver.derive(from: entries, now: now) == .done
            if meta.isDone != derived {
                meta.isDone = derived
                changed = true
            }
        }
        if changed { meta.updatedAt = now }
        return changed
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
        // 在已完成（整体或当天）的任务上再开始 → 记录打"再开始"阶段标；完成标本身不自动清除
        let before = status(in: .day(day))
        let wasDone = before == .done || before == .doneForDay
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

    /// 见 `Membership.moveEntry`
    @discardableResult
    public mutating func moveEntry(id: UUID, toDay day: Day, calendar: Calendar = .current) -> Bool {
        guard meta.membership.moveEntry(id: id, toDay: day, calendar: calendar) else { return false }
        meta.updatedAt = Date()
        return true
    }

    /// 重复任务在 `day` 上新建首条 entry 时，尝试从最近一天已完成的记录取时间，
    /// 并把时分锚定到 `day` 上返回。非重复任务、无更早完成记录时返回 nil。
    public func entryTimeToCarry(to day: Day, calendar: Calendar = .current) -> (startAt: Date, endAt: Date)? {
        guard meta.isRecurring else { return nil }
        let earlier = meta.membership.dayAssignments
            .filter { $0.day < day }
            .sorted { $0.day > $1.day }
        for da in earlier {
            let done = da.entries.first(where: { $0.startAt != nil && $0.endAt != nil })
            if let template = done,
               let s = template.startAt(inDay: day, calendar: calendar),
               let e = template.endAt(inDay: day, calendar: calendar) {
                return (s, e)
            }
        }
        return nil
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
