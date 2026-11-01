import Foundation
import TaskerDomain
import TaskerPersistence

var passed = 0
var failed = 0

func check(_ name: String, _ body: () throws -> Void) {
    do { try body(); passed += 1; print("  ✓ \(name)") }
    catch { failed += 1; print("  ✗ \(name) — \(error)") }
}

struct AssertionError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
func expect(_ cond: Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) throws {
    if !cond { throw AssertionError(message: "expect failed at \(file):\(line) \(message())") }
}
func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) throws {
    if a != b { throw AssertionError(message: "expectEqual failed at \(file):\(line): \(a) != \(b)") }
}
func expectThrows(_ body: () throws -> Void, file: StaticString = #file, line: UInt = #line) throws {
    do { try body(); throw AssertionError(message: "expected throw at \(file):\(line)") }
    catch is AssertionError { throw AssertionError(message: "expected throw at \(file):\(line)") }
    catch { }
}

let taskId = UUID()
let t0 = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: - StatusDeriver（derive = 旧 marker 规则，仅回填用；activity = 现行活动态规则）
print("StatusDeriver")

check("activity: no entries → notStarted; any past/unstarted entry → inProgress; marker ignored; future ignored") {
    try expectEqual(StatusDeriver.activity(from: []), .notStarted)
    let unstarted = TimeEntry()
    try expectEqual(StatusDeriver.activity(from: [unstarted]), .inProgress)
    let done = TimeEntry(startAt: Date(timeIntervalSinceNow: -7200), endAt: Date(timeIntervalSinceNow: -3600), marker: .done)
    try expectEqual(StatusDeriver.activity(from: [done]), .inProgress)
    let now = Date()
    let future = TimeEntry(startAt: now.addingTimeInterval(3600))
    try expectEqual(StatusDeriver.activity(from: [future], now: now), .notStarted)
}

check("no entries → notStarted") {
    try expectEqual(StatusDeriver.derive(from: []), .notStarted)
}
check("entry without startAt and no marker → inProgress (has any record)") {
    let e = TimeEntry(title: "empty")
    try expectEqual(StatusDeriver.derive(from: [e]), .inProgress)
}
check("open entry (started, no marker) → inProgress") {
    let e = TimeEntry(startAt: t0)
    try expectEqual(StatusDeriver.derive(from: [e]), .inProgress)
}
check("closed w/ done → done") {
    let e = TimeEntry(startAt: t0, endAt: t0.addingTimeInterval(60), marker: .done)
    try expectEqual(StatusDeriver.derive(from: [e]), .done)
}
check("done then unmarked new entry: last marker is done → still done") {
    let e1 = TimeEntry(startAt: t0, endAt: t0.addingTimeInterval(60), marker: .done)
    let e2 = TimeEntry(startAt: t0.addingTimeInterval(120))  // 无 marker
    try expectEqual(StatusDeriver.derive(from: [e1, e2]), .done)
}
check("done then restart marker → inProgress (last marker is restart)") {
    let e1 = TimeEntry(startAt: t0, endAt: t0.addingTimeInterval(60), marker: .done)
    let e2 = TimeEntry(startAt: t0.addingTimeInterval(120), marker: .restart)
    try expectEqual(StatusDeriver.derive(from: [e1, e2]), .inProgress)
}
check("last-marker wins regardless of order in array") {
    let older = TimeEntry(startAt: t0.addingTimeInterval(120), endAt: t0.addingTimeInterval(180), marker: .done)
    let newer_unmarked = TimeEntry(startAt: t0.addingTimeInterval(300))
    // "最后一个有标"是 older（也是唯一有标）→ done
    try expectEqual(StatusDeriver.derive(from: [newer_unmarked, older]), .done)
}
check("future entries are ignored when deriving status") {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let future = TimeEntry(startAt: now.addingTimeInterval(3600))
    try expectEqual(StatusDeriver.derive(from: [future], now: now), .notStarted)
    let futureDone = TimeEntry(startAt: now.addingTimeInterval(3600), marker: .done)
    try expectEqual(StatusDeriver.derive(from: [futureDone], now: now), .notStarted)
    let past = TimeEntry(startAt: now.addingTimeInterval(-60))
    try expectEqual(StatusDeriver.derive(from: [past, future], now: now), .inProgress)
}

// MARK: - TaskAggregate
print("TaskAggregate")
func makeTask() -> TaskAggregate { TaskAggregate(meta: TaskMeta(title: "T")) }
let checkDay = Day(year: 2026, month: 7, day: 11)

check("no entries → notStarted; addEntry → inProgress (any record = activity)") {
    var t = makeTask()
    try expectEqual(t.status, .notStarted)
    _ = t.addEntry(inDay: checkDay, title: "chunk")
    try expectEqual(t.status, .inProgress)
}
check("startEntry → inProgress") {
    var t = makeTask()
    let id = t.addEntry(inDay: checkDay)
    try t.startEntry(id: id)
    try expectEqual(t.status, .inProgress)
}
check("entry marker no longer drives status; task isDone does; startEntry on a done task still auto-marks restart") {
    var t = makeTask()
    let a = t.addEntry(inDay: checkDay); try t.startEntry(id: a); try t.endEntry(id: a)
    t.updateEntry(id: a) { $0.marker = .done }
    try expectEqual(t.status, .inProgress)   // marker 只是记录级标注
    t.setIsDone(true)
    try expectEqual(t.status, .done)
    try expectEqual(t.status(in: .day(checkDay)), .done)
    try expectEqual(t.status(in: .backlog), .done)
    let b = t.addEntry(inDay: checkDay)
    try t.startEntry(id: b)
    try expectEqual(t.entries.first(where: { $0.id == b })?.marker, .restart)
    try expectEqual(t.status, .done)   // 整体完成标不自动清除
    t.setIsDone(false)
    try expectEqual(t.status, .inProgress)
}

check("day done flag → doneForDay in that day only; setDayDone ignores unassigned days; task isDone overrides") {
    var t = makeTask()
    let d2 = Day(year: 2026, month: 7, day: 12)
    let d3 = Day(year: 2026, month: 7, day: 13)
    t.meta.membership.upsertDay(checkDay)
    t.meta.membership.upsertDay(d2)
    t.setDayDone(inDay: checkDay, isDone: true)
    t.setDayDone(inDay: d3, isDone: true)   // 未关联 → 忽略
    try expectEqual(t.meta.membership.days, [checkDay, d2])
    try expectEqual(t.status(in: .day(checkDay)), .doneForDay)
    try expectEqual(t.status(in: .day(d2)), .notStarted)
    try expectEqual(t.status(in: .backlog), .notStarted)
    try expectEqual(t.status, .notStarted)
    try expect(t.isUnfinished(inDay: checkDay))   // 非循环：当天完成不算整体完成，仍要跟进
    t.setIsDone(true)
    try expectEqual(t.status(in: .day(checkDay)), .done)
    try expectEqual(t.status(in: .day(d2)), .done)
    try expect(!t.isUnfinished(inDay: d2))
}

check("hideDayCompleted filters doneForDay only in day context; hideCompleted leaves doneForDay alone") {
    let d = Day(year: 2026, month: 7, day: 11)
    var dayDone = TaskAggregate(meta: TaskMeta(title: "DD", membership: Membership(dayAssignments: [DayAssignment(day: d)])))
    dayDone.setDayDone(inDay: d, isDone: true)
    let fullDone = TaskAggregate(meta: TaskMeta(title: "FD", membership: Membership(dayAssignments: [DayAssignment(day: d)]), isDone: true))
    let open = TaskAggregate(meta: TaskMeta(title: "O", membership: Membership(dayAssignments: [DayAssignment(day: d)])))
    let all = [dayDone, fullDone, open]
    try expectEqual(Set(TaskQueries.apply(.day(d), to: all).map(\.meta.title)), ["DD", "FD", "O"])
    try expectEqual(Set(TaskQueries.apply(.day(d), hideCompleted: true, to: all).map(\.meta.title)), ["DD", "O"])
    try expectEqual(Set(TaskQueries.apply(.day(d), hideDayCompleted: true, to: all).map(\.meta.title)), ["FD", "O"])
    // Backlog：只有整体未完成的；当天完成不影响
    try expectEqual(Set(TaskQueries.apply(.backlog, hideDayCompleted: true, to: all).map(\.meta.title)), ["DD", "O"])
}

check("backfillDoneFlags: legacy markers → per-day isDone, non-recurring task isDone; idempotent; recurring keeps task flag off") {
    let d1 = Day(year: 2026, month: 7, day: 11)
    let d2 = Day(year: 2026, month: 7, day: 12)
    let doneEntry = TimeEntry(startAt: d1.date().addingTimeInterval(3600),
                              endAt: d1.date().addingTimeInterval(7200), marker: .done)
    let openEntry = TimeEntry(startAt: d2.date().addingTimeInterval(3600))
    var n = TaskAggregate(meta: TaskMeta(title: "N", membership: Membership(
        dayAssignments: [DayAssignment(day: d1), DayAssignment(day: d2)])), entries: [doneEntry, openEntry])
    try expectEqual(n.status, .inProgress)
    try expect(n.backfillDoneFlags())
    try expect(n.meta.isDone)                       // 全部记录里最后一个有标的是 done
    try expect(n.meta.membership.isDone(inDay: d1))
    try expect(!n.meta.membership.isDone(inDay: d2))
    try expect(!n.backfillDoneFlags())              // 再跑无变化
    var r = TaskAggregate(meta: TaskMeta(title: "R", membership: Membership(
        dayAssignments: [DayAssignment(day: d1), DayAssignment(day: d2)]), isRecurring: true), entries: [doneEntry, openEntry])
    try expect(r.backfillDoneFlags())
    try expect(!r.meta.isDone)
    try expectEqual(r.status(in: .day(d1)), .doneForDay)
    try expectEqual(r.status(in: .day(d2)), .inProgress)
}

check("isDone flags roundtrip in JSON; missing keys decode as false") {
    let d = Day(year: 2026, month: 7, day: 11)
    let meta = TaskMeta(title: "T", membership: Membership(dayAssignments: [DayAssignment(day: d, isDone: true)]), isDone: true)
    let enc = JSONEncoder(); let dec = JSONDecoder()
    let back = try dec.decode(TaskMeta.self, from: try enc.encode(meta))
    try expect(back.isDone)
    try expect(back.membership.isDone(inDay: d))
    let legacy = """
    {"id":"00000000-0000-0000-0000-000000000001","title":"L","membership":{"dayAssignments":[{"day":"2026-07-11","priority":"normal"}]},"createdAt":0,"updatedAt":0}
    """
    let l = try dec.decode(TaskMeta.self, from: Data(legacy.utf8))
    try expect(!l.isDone)
    try expect(!l.membership.isDone(inDay: d))
}

check("entryTimeToCarry: recurring picks last day's completed entry, rebased to target day") {
    let d1 = Day(year: 2026, month: 8, day: 5)
    let d2 = Day(year: 2026, month: 8, day: 8)
    let target = Day(year: 2026, month: 8, day: 10)
    let d1Start = d1.date().addingTimeInterval(9*3600)     // 09:00 on d1
    let d1End = d1.date().addingTimeInterval(10*3600)      // 10:00 on d1
    let d2Start = d2.date().addingTimeInterval(14*3600)    // 14:00 on d2
    let d2End = d2.date().addingTimeInterval(15*3600)      // 15:00 on d2
    let agg = TaskAggregate(
        meta: TaskMeta(title: "R", membership: Membership(
            dayAssignments: [DayAssignment(day: d1), DayAssignment(day: d2), DayAssignment(day: target)]
        ), isRecurring: true),
        entries: [
            TimeEntry(startAt: d1Start, endAt: d1End),
            TimeEntry(startAt: d2Start, endAt: d2End),
        ]
    )
    let carry = agg.entryTimeToCarry(to: target)
    try expect(carry != nil)
    // 取最近一天 d2 的模板；时分锚定到 target
    try expectEqual(Day(date: carry!.startAt), target)
    let cal = Calendar.current
    let sc = cal.dateComponents([.hour, .minute], from: carry!.startAt)
    let ec = cal.dateComponents([.hour, .minute], from: carry!.endAt)
    try expect((sc.hour ?? 0) == 14 && (sc.minute ?? 0) == 0)
    try expect((ec.hour ?? 0) == 15 && (ec.minute ?? 0) == 0)
}

check("entryTimeToCarry: non-recurring task returns nil") {
    let d1 = Day(year: 2026, month: 8, day: 5)
    let target = Day(year: 2026, month: 8, day: 10)
    let entry = TimeEntry(startAt: d1.date().addingTimeInterval(9*3600),
                          endAt: d1.date().addingTimeInterval(10*3600))
    let agg = TaskAggregate(
        meta: TaskMeta(title: "N", membership: Membership(
            dayAssignments: [DayAssignment(day: d1), DayAssignment(day: target)]
        ), isRecurring: false),
        entries: [entry]
    )
    try expect(agg.entryTimeToCarry(to: target) == nil)
}

check("entryTimeToCarry: skips days without completed entries") {
    let d1 = Day(year: 2026, month: 8, day: 5)
    let d2 = Day(year: 2026, month: 8, day: 8)   // 只有 in-progress
    let target = Day(year: 2026, month: 8, day: 10)
    let d1Start = d1.date().addingTimeInterval(9*3600)
    let d1End = d1.date().addingTimeInterval(10*3600)
    let d2InProgress = TimeEntry(startAt: d2.date().addingTimeInterval(20*3600), endAt: nil)
    let agg = TaskAggregate(
        meta: TaskMeta(title: "R", membership: Membership(
            dayAssignments: [DayAssignment(day: d1), DayAssignment(day: d2), DayAssignment(day: target)]
        ), isRecurring: true),
        entries: [
            TimeEntry(startAt: d1Start, endAt: d1End),
            d2InProgress,
        ]
    )
    let carry = agg.entryTimeToCarry(to: target)
    try expect(carry != nil)
    let cal = Calendar.current
    let sc = cal.dateComponents([.hour, .minute], from: carry!.startAt)
    try expect((sc.hour ?? 0) == 9 && (sc.minute ?? 0) == 0)
}

check("entryTimeToCarry: no earlier data → nil") {
    let target = Day(year: 2026, month: 8, day: 10)
    let agg = TaskAggregate(
        meta: TaskMeta(title: "R", membership: Membership(
            dayAssignments: [DayAssignment(day: target)]
        ), isRecurring: true)
    )
    try expect(agg.entryTimeToCarry(to: target) == nil)
}

// MARK: - TaskQueries
print("TaskQueries")
func mkAgg(_ title: String,
           days: Set<Day> = [],
           isCurrent: Bool = false,
           categoryId: UUID? = nil,
           priorityPerDay: Priority = .normal) -> TaskAggregate {
    let assignments = days.sorted().map {
        DayAssignment(day: $0, priority: priorityPerDay, isCurrent: isCurrent)
    }
    return TaskAggregate(
        meta: TaskMeta(title: title, categoryId: categoryId,
                       membership: Membership(dayAssignments: assignments)),
        entries: []
    )
}

check("per-day priority is independent across days") {
    let d1 = Day(year: 2026, month: 7, day: 11)
    let d2 = Day(year: 2026, month: 7, day: 12)
    var m = Membership(dayAssignments: [
        DayAssignment(day: d1, priority: .todayMustReach),
        DayAssignment(day: d2, priority: .todayMustReach),
    ])
    // 改一天的 priority 不应影响另一天
    m.setPriority(inDay: d2, priority: .normal)
    try expectEqual(m.priority(inDay: d1), .todayMustReach)
    try expectEqual(m.priority(inDay: d2), .normal)
}

check("priority(in filter) uses day's assignment") {
    let d1 = Day(year: 2026, month: 7, day: 11)
    let d2 = Day(year: 2026, month: 7, day: 12)
    let m = Membership(dayAssignments: [
        DayAssignment(day: d1, priority: .todayMustReach),
        DayAssignment(day: d2, priority: .normal),
    ])
    let agg = TaskAggregate(meta: TaskMeta(title: "t", membership: m))
    try expectEqual(agg.priority(in: .day(d1)), .todayMustReach)
    try expectEqual(agg.priority(in: .day(d2)), .normal)
}

check("TimeEntry.startAt(inDay:) rebases date part to the given day") {
    let dayA = Day(year: 2026, month: 8, day: 5)
    let dayB = Day(year: 2026, month: 8, day: 10)
    let cal = Calendar.current
    let dayAStart = cal.startOfDay(for: dayA.date(calendar: cal))
    let startOffset: TimeInterval = 14*3600 + 30*60 + 45
    let endOffset: TimeInterval = 15*3600 + 45*60
    let storedStart = dayAStart.addingTimeInterval(startOffset)
    let storedEnd = dayAStart.addingTimeInterval(endOffset)
    let entry = TimeEntry(startAt: storedStart, endAt: storedEnd)

    let rebasedStart = entry.startAt(inDay: dayB)!
    let rebasedEnd = entry.endAt(inDay: dayB)!
    try expectEqual(Day(date: rebasedStart), dayB)
    try expectEqual(Day(date: rebasedEnd), dayB)
    let c = cal.dateComponents([.hour, .minute, .second], from: rebasedStart)
    try expect((c.hour ?? 0) == 14)
    try expect((c.minute ?? 0) == 30)
    try expect((c.second ?? 0) == 45)
    let expected: TimeInterval = endOffset - startOffset
    try expectEqual(entry.duration(inDay: dayB), expected)
}

check("TimeEntry helpers: nil startAt/endAt → nil") {
    let d = Day.today()
    let entry = TimeEntry()
    try expect(entry.startAt(inDay: d) == nil)
    try expect(entry.endAt(inDay: d) == nil)
    try expect(entry.duration(inDay: d) == nil)
}

check("day view: sort by earliest startAt, then priority, then updatedAt") {
    let d = Day(year: 2026, month: 8, day: 5)
    // A: 有 startAt = 10:00, priority normal
    let entryA = TimeEntry(startAt: d.date().addingTimeInterval(10 * 3600))
    let a = TaskAggregate(
        meta: TaskMeta(title: "A", membership: Membership(
            dayAssignments: [DayAssignment(day: d, priority: .normal)]
        )),
        entries: [entryA]
    )
    // B: 有 startAt = 09:00, priority normal（时间更早 → 应排最前）
    let entryB = TimeEntry(startAt: d.date().addingTimeInterval(9 * 3600))
    let b = TaskAggregate(
        meta: TaskMeta(title: "B", membership: Membership(
            dayAssignments: [DayAssignment(day: d, priority: .normal)]
        )),
        entries: [entryB]
    )
    // C: 无 startAt，priority todayMustReach（高优先级但无时间 → 排到有时间的后面）
    let c = TaskAggregate(
        meta: TaskMeta(title: "C", membership: Membership(
            dayAssignments: [DayAssignment(day: d, priority: .todayMustReach)]
        ))
    )
    // D: 无 startAt，priority normal
    let d2 = TaskAggregate(
        meta: TaskMeta(title: "D", membership: Membership(
            dayAssignments: [DayAssignment(day: d, priority: .normal)]
        ))
    )
    let sorted = TaskQueries.sortForDisplay([d2, c, a, b], in: .day(d)).map(\.meta.title)
    try expectEqual(sorted, ["B", "A", "C", "D"])
}

check("backlog view: time-based sort not applied, priority still primary") {
    let d = Day.today()
    // 都无 entries；仅按 priority 排（都在 backlog，未完成）
    let hi = TaskAggregate(meta: TaskMeta(title: "H", membership: Membership(
        dayAssignments: [DayAssignment(day: d, priority: .todayMustReach)]
    )))
    let lo = TaskAggregate(meta: TaskMeta(title: "L", membership: Membership(
        dayAssignments: [DayAssignment(day: d, priority: .normal)]
    )))
    let sorted = TaskQueries.sortForDisplay([lo, hi], in: .backlog).map(\.meta.title)
    try expectEqual(sorted, ["H", "L"])
}

check("recurring task: statusForDay isolated to that day (day flag + that day's records only)") {
    let d1 = Day(year: 2026, month: 7, day: 11)
    let d2 = Day(year: 2026, month: 7, day: 12)
    let d3 = Day(year: 2026, month: 7, day: 13)
    // d1 标了当天完成，d2 只有一段进行中，d3 什么都没有
    let d2Entry = TimeEntry(startAt: d2.date().addingTimeInterval(3600))
    let agg = TaskAggregate(
        meta: TaskMeta(title: "recurring", membership: Membership(
            dayAssignments: [DayAssignment(day: d1, isDone: true), DayAssignment(day: d2), DayAssignment(day: d3)]
        ), isRecurring: true),
        entries: [d2Entry]
    )
    try expectEqual(agg.statusForDay(d1), .doneForDay)
    try expectEqual(agg.statusForDay(d2), .inProgress)
    try expectEqual(agg.status(in: .day(d1)), .doneForDay)
    try expectEqual(agg.status(in: .day(d2)), .inProgress)
    try expectEqual(agg.status(in: .day(d3)), .notStarted)   // 循环任务不看别天的记录
    try expectEqual(agg.status(in: .backlog), .notStarted)
}

check("recurring tasks always appear in backlog even if globally done") {
    let d = Day.today()
    let recurring = TaskAggregate(
        meta: TaskMeta(title: "R", membership: Membership(
            dayAssignments: [DayAssignment(day: d)]
        ), isRecurring: true, isDone: true)
    )
    let nonRecurring = TaskAggregate(
        meta: TaskMeta(title: "N", membership: Membership(
            dayAssignments: [DayAssignment(day: d)]
        ), isRecurring: false, isDone: true)
    )
    try expectEqual(recurring.status, .done)
    try expectEqual(recurring.status(in: .backlog), .done)   // 整体完成优先
    try expectEqual(nonRecurring.status, .done)
    let backlog = TaskQueries.apply(.backlog, to: [recurring, nonRecurring]).map(\.meta.title)
    try expectEqual(backlog, ["R"])  // 只有循环任务留下
}

check("backlogCandidates: excludes done and already-on-day, keyword matches title case-insensitively") {
    let d = Day(year: 2026, month: 10, day: 26)
    let other = Day(year: 2026, month: 10, day: 20)
    let open = TaskAggregate(meta: TaskMeta(title: "Write Report"))
    let onDay = TaskAggregate(meta: TaskMeta(title: "Report review", membership: Membership(
        dayAssignments: [DayAssignment(day: d)]
    )))
    let elsewhere = TaskAggregate(meta: TaskMeta(title: "Other thing", membership: Membership(
        dayAssignments: [DayAssignment(day: other, priority: .important)]
    )))
    let done = TaskAggregate(meta: TaskMeta(title: "Report done", membership: Membership(
        dayAssignments: [DayAssignment(day: other)]
    ), isDone: true))
    let all = [open, onDay, elsewhere, done]
    let noKeyword = TaskQueries.backlogCandidates(forDay: d, matching: "", in: all).map(\.meta.title)
    try expectEqual(Set(noKeyword), ["Write Report", "Other thing"])
    let kw = TaskQueries.backlogCandidates(forDay: d, matching: "  report ", in: all).map(\.meta.title)
    try expectEqual(kw, ["Write Report"])
    try expectEqual(TaskQueries.backlogCandidates(forDay: d, matching: "zzz", in: all).count, 0)
}

check("isUnfinished (push candidates): recurring uses day flag, non-recurring uses task flag only") {
    let src = Day(year: 2026, month: 7, day: 11)
    let recurringDayDone = TaskAggregate(meta: TaskMeta(title: "R", membership: Membership(
        dayAssignments: [DayAssignment(day: src, isDone: true)]), isRecurring: true))
    let recurringOpen = TaskAggregate(meta: TaskMeta(title: "R2", membership: Membership(
        dayAssignments: [DayAssignment(day: src)]), isRecurring: true))
    let dayDoneOnly = TaskAggregate(meta: TaskMeta(title: "N", membership: Membership(
        dayAssignments: [DayAssignment(day: src, isDone: true)])))
    let taskDone = TaskAggregate(meta: TaskMeta(title: "N2", membership: Membership(
        dayAssignments: [DayAssignment(day: src)]), isDone: true))
    try expect(!recurringDayDone.isUnfinished(inDay: src))
    try expect(recurringOpen.isUnfinished(inDay: src))
    try expect(dayDoneOnly.isUnfinished(inDay: src))     // 当天完成 ≠ 整体完成，仍要推
    try expect(!taskDone.isUnfinished(inDay: src))
    // store.pushUncompleted 用的就是 isUnfinished(inDay:)
}

check("moveEntry: moves to another day, creates assignment with source priority, rebases date part") {
    let d1 = Day(year: 2026, month: 10, day: 20)
    let d2 = Day(year: 2026, month: 10, day: 22)
    var agg = TaskAggregate(meta: TaskMeta(title: "M", membership: Membership(
        dayAssignments: [DayAssignment(day: d1, priority: .important)]
    )))
    let id = agg.addEntry(inDay: d1, priority: .important, title: "e")
    agg.updateEntry(id: id) {
        $0.startAt = d1.date().addingTimeInterval(9 * 3600)
        $0.endAt = d1.date().addingTimeInterval(10 * 3600)
    }
    try expect(agg.moveEntry(id: id, toDay: d2))
    try expectEqual(agg.entries(inDay: d1).count, 0)
    try expectEqual(agg.entries(inDay: d2).map(\.title), ["e"])
    // 原来那天的关联保留；目标日新建关联，优先级复制自原来那天
    try expectEqual(agg.meta.membership.days, [d1, d2])
    try expectEqual(agg.meta.membership.priority(inDay: d2), .important)
    try expectEqual(agg.meta.membership.isCurrent(inDay: d2), false)
    // 存储里的日期部分已改到目标日，时分不变
    let moved = agg.entries(inDay: d2)[0]
    try expectEqual(moved.startAt, d2.date().addingTimeInterval(9 * 3600))
    try expectEqual(moved.endAt, d2.date().addingTimeInterval(10 * 3600))
    // 目标日已有关联时不改它的优先级
    let d3 = Day(year: 2026, month: 10, day: 23)
    agg.meta.membership.upsertDay(d3, priority: .todayMustReach)
    try expect(agg.moveEntry(id: id, toDay: d3))
    try expectEqual(agg.meta.membership.priority(inDay: d3), .todayMustReach)
    try expectEqual(agg.entries(inDay: d3).count, 1)
}

check("moveEntry: same day or unknown entry → false, nothing changes") {
    let d1 = Day(year: 2026, month: 10, day: 20)
    var agg = TaskAggregate(meta: TaskMeta(title: "M"))
    let id = agg.addEntry(inDay: d1, title: "e")
    let before = agg.meta.membership
    try expect(!agg.moveEntry(id: id, toDay: d1))
    try expect(!agg.moveEntry(id: UUID(), toDay: Day(year: 2026, month: 10, day: 21)))
    try expectEqual(agg.meta.membership, before)
}

check("group by category respects settings order, renames don't break linkage") {
    let d = Day.today()
    let cat1 = CategoryDef(name: "会议")
    let cat2 = CategoryDef(name: "日常")
    let a = mkAgg("A", days: [d], categoryId: cat1.id)
    let b = mkAgg("B", days: [d], categoryId: cat2.id)
    // 用户改了名字：cat1 现在叫"会议x"，仍然用同一个 id
    let renamed = CategoryDef(id: cat1.id, name: "会议x")
    let groups = TaskQueries.groupByCategory([a, b], categories: [renamed, cat2])
    try expectEqual(groups.first?.0.name, "会议x")
    try expectEqual(groups.first?.1.map(\.meta.title), ["A"])
    try expectEqual(groups.last?.0.name, "日常")
    try expectEqual(groups.last?.1.map(\.meta.title), ["B"])
}
check("group by category: deleted category id shows as (Unknown)") {
    let d = Day.today()
    let ghostId = UUID()
    let a = mkAgg("A", days: [d], categoryId: ghostId)
    let groups = TaskQueries.groupByCategory([a], categories: [])
    try expectEqual(groups.first?.0.name, "(Unknown)")
}
check("group by category: nil categoryId → (Unset)") {
    let d = Day.today()
    let a = mkAgg("A", days: [d], categoryId: nil)
    let groups = TaskQueries.groupByCategory([a], categories: [])
    try expectEqual(groups.first?.0.name, "(Unset)")
}
check("all days: days ascending, category inside day, Backlog last") {
    let d1 = Day(year: 2026, month: 10, day: 24)
    let d2 = Day(year: 2026, month: 10, day: 25)
    let cat1 = CategoryDef(name: "Meetings")
    let cat2 = CategoryDef(name: "Daily")
    // A 只在 d2；B 在 d1 和 d2；C 不属于任何一天（只出现在 Backlog）
    let a = mkAgg("A", days: [d2], categoryId: cat1.id)
    let b = mkAgg("B", days: [d1, d2], categoryId: cat2.id)
    let c = mkAgg("C", days: [], categoryId: cat1.id)
    let groups = TaskQueries.groupAllDays([a, b, c], categories: [cat1, cat2])
    try expectEqual(groups.map(\.context), [.day(d1), .day(d2), .backlog])
    // d1 只有 B（Daily）
    try expectEqual(groups[0].categories.map(\.0.name), ["Daily"])
    try expectEqual(groups[0].tasks.map(\.meta.title), ["B"])
    // d2 按分类顺序：Meetings(A) → Daily(B)
    try expectEqual(groups[1].categories.map(\.0.name), ["Meetings", "Daily"])
    try expectEqual(groups[1].tasks.map(\.meta.title), ["A", "B"])
    // Backlog = 所有未完成任务，含不属于任何一天的 C
    try expectEqual(Set(groups[2].tasks.map(\.meta.title)), ["A", "B", "C"])
}
check("all days: completed task stays under its day but leaves Backlog; empty groups dropped") {
    let d = Day(year: 2026, month: 10, day: 25)
    let done = TaskAggregate(
        meta: TaskMeta(title: "D", membership: Membership(dayAssignments: [DayAssignment(day: d)]), isDone: true)
    )
    let groups = TaskQueries.groupAllDays([done], categories: [])
    try expectEqual(groups.map(\.context), [.day(d)])  // Backlog 为空，被丢掉
    try expectEqual(groups[0].tasks.map(\.meta.title), ["D"])
    // hideCompleted 逐天应用 → 整个列表为空
    let hidden = TaskQueries.groupAllDays([done], categories: [], hideCompleted: true)
    try expect(hidden.isEmpty)
}
check("all days: currentOnly applies per day context") {
    let d1 = Day(year: 2026, month: 10, day: 24)
    let d2 = Day(year: 2026, month: 10, day: 25)
    var t = mkAgg("T", days: [d1, d2])
    t.meta.membership.setIsCurrent(inDay: d2, isCurrent: true)
    let groups = TaskQueries.groupAllDays([t], categories: [], currentOnly: true)
    // d1 没有 current → 不出现；d2 有；Backlog 下 hasAnyCurrent 成立
    try expectEqual(groups.map(\.context), [.day(d2), .backlog])
}
check("ListScope.filter: single-context scopes map to TaskFilter, allDays has none") {
    let d = Day.today()
    try expectEqual(ListScope.day(d).filter, .day(d))
    try expectEqual(ListScope.backlog.filter, .backlog)
    try expect(ListScope.allDays.filter == nil)
}
check("SettingsLookup resolves workType by id") {
    let wt = WorkTypeDef(name: "coding")
    try expectEqual(SettingsLookup.workTypeName(wt.id, in: [wt]), "coding")
    try expectEqual(SettingsLookup.workTypeName(UUID(), in: [wt]), "(Unknown)")
    try expectEqual(SettingsLookup.workTypeName(nil, in: [wt]), "(Unset)")
}

// MARK: - TimeEntry 实际占用

check("effectiveDuration: manual minutes win over start/end, fall back to end - start") {
    let day = Day(year: 2026, month: 3, day: 15)
    let s = TimelineGrid.date(atOffset: 9 * 3600, inDay: day)
    let e = TimelineGrid.date(atOffset: 10 * 3600, inDay: day)
    let computed = TimeEntry(startAt: s, endAt: e)
    try expectEqual(computed.effectiveDuration, 3600)
    try expectEqual(computed.effectiveDuration(inDay: day), 3600)
    let manual = TimeEntry(startAt: s, endAt: e, actualMinutes: 45)
    try expectEqual(manual.effectiveDuration, 45 * 60)
    try expectEqual(manual.effectiveDuration(inDay: day), 45 * 60)
    // 没有起止时间但填了分钟数 → 仍算占用
    let onlyManual = TimeEntry(actualMinutes: 20)
    try expectEqual(onlyManual.duration, nil)
    try expectEqual(onlyManual.effectiveDuration, 20 * 60)
    try expectEqual(TimeEntry().effectiveDuration, nil)
}

check("TimeEntry actualMinutes roundtrips; missing key decodes as nil") {
    let enc = JSONEncoder(), dec = JSONDecoder()
    let withActual = TimeEntry(title: "x", actualMinutes: 30)
    let back = try dec.decode(TimeEntry.self, from: try enc.encode(withActual))
    try expectEqual(back.actualMinutes, 30)
    let legacy = """
    {"id":"\(UUID().uuidString)","title":"old"}
    """.data(using: .utf8)!
    try expectEqual(try dec.decode(TimeEntry.self, from: legacy).actualMinutes, nil)
}

// MARK: - TimelineGrid（甘特图 5 分钟刻度）

check("TimelineGrid.snap rounds to 5-minute grid and clamps to the day") {
    try expectEqual(TimelineGrid.snap(10 * 3600 + 2 * 60 + 29), 10 * 3600)          // 10:02:29 → 10:00
    try expectEqual(TimelineGrid.snap(10 * 3600 + 2 * 60 + 31), 10 * 3600 + 5 * 60) // 10:02:31 → 10:05
    try expectEqual(TimelineGrid.snap(-300), 0)
    try expectEqual(TimelineGrid.snap(90_000), TimelineGrid.dayLength)
}

check("TimelineGrid.move keeps duration, snaps start, stays inside the day") {
    // 10:03 – 10:48 (45m) 右移 7 分钟 → 10:10 – 10:55
    let r = TimelineGrid.move(start: 10 * 3600 + 3 * 60, end: 10 * 3600 + 48 * 60, by: 7 * 60)
    try expectEqual(r.start, 10 * 3600 + 10 * 60)
    try expectEqual(r.end - r.start, 45 * 60)
    // 推过当天末尾 → 贴到 24:00 结束
    let tail = TimelineGrid.move(start: 23 * 3600, end: 23 * 3600 + 30 * 60, by: 3600)
    try expectEqual(tail.end, TimelineGrid.dayLength)
    try expectEqual(tail.start, TimelineGrid.dayLength - 30 * 60)
    // 推到当天开头之前 → 从 0 开始
    let head = TimelineGrid.move(start: 600, end: 1800, by: -3600)
    try expectEqual(head.start, 0)
    try expectEqual(head.end, 1200)
}

check("TimelineGrid.resizeStart/End snap and keep at least one step apart") {
    let s = 10 * 3600.0, e = 11 * 3600.0
    try expectEqual(TimelineGrid.resizeStart(start: s, end: e, to: 10 * 3600 + 58 * 60), e - 300)
    try expectEqual(TimelineGrid.resizeStart(start: s, end: e, to: 11 * 3600 + 600), e - 300)
    try expectEqual(TimelineGrid.resizeStart(start: s, end: e, to: 9 * 3600 + 32 * 60 + 40), 9 * 3600 + 35 * 60)
    try expectEqual(TimelineGrid.resizeEnd(start: s, end: e, to: 10 * 3600 + 1), s + 300)
    try expectEqual(TimelineGrid.resizeEnd(start: s, end: e, to: 9 * 3600), s + 300)
    try expectEqual(TimelineGrid.resizeEnd(start: s, end: e, to: 99_999), TimelineGrid.dayLength)
}

check("TimelineGrid.newRange sorts ends, snaps, enforces minimum one step") {
    let r = TimelineGrid.newRange(from: 14 * 3600 + 17 * 60, to: 13 * 3600 + 2 * 60)
    try expectEqual(r.start, 13 * 3600)
    try expectEqual(r.end, 14 * 3600 + 15 * 60)
    let tiny = TimelineGrid.newRange(from: 9 * 3600 + 61, to: 9 * 3600 + 62)
    try expectEqual(tiny.start, 9 * 3600)
    try expectEqual(tiny.end, 9 * 3600 + 300)
    let edge = TimelineGrid.newRange(from: TimelineGrid.dayLength, to: TimelineGrid.dayLength)
    try expectEqual(edge.start, TimelineGrid.dayLength - 300)
    try expectEqual(edge.end, TimelineGrid.dayLength)
}

check("TimelineGrid offset/date roundtrip anchors to the given day") {
    let day = Day(year: 2026, month: 3, day: 15)
    let d = TimelineGrid.date(atOffset: 9 * 3600 + 5 * 60, inDay: day)
    try expectEqual(Day(date: d), day)
    try expectEqual(TimelineGrid.offset(of: d, inDay: day), 9 * 3600 + 5 * 60)
    try expectEqual(TimelineGrid.label(9 * 3600 + 5 * 60), "09:05")
    try expectEqual(TimelineGrid.label(TimelineGrid.dayLength), "24:00")
}

// MARK: - Persistence
print("Persistence")
check("settings roundtrip with id-based defs") {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tasker-settings-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try SettingsRepository(layout: StorageLayout(root: tmp))
    let seeded = try repo.load()
    try expect(!seeded.categories.isEmpty)
    try expect(!seeded.workTypes.isEmpty)

    // rename first category
    var updated = seeded
    updated.categories[0].name = updated.categories[0].name + "-改"
    let renamedId = updated.categories[0].id
    updated.categories[1].colorHex = "#123456"
    try repo.save(updated)
    let reloaded = try repo.load()
    try expectEqual(reloaded.categories[0].id, renamedId)
    try expect(reloaded.categories[0].name.hasSuffix("-改"))
    try expectEqual(reloaded.categories[0].colorHex, nil)
    try expectEqual(reloaded.categories[1].colorHex, "#123456")
}

check("CategoryPalette: explicit color wins, else slot color, else gray") {
    let explicit = CategoryDef(name: "A", colorHex: "#123456")
    try expectEqual(CategoryPalette.resolvedHex(for: explicit, slot: 0, dark: false), "#123456")
    try expectEqual(CategoryPalette.resolvedHex(for: explicit, slot: 0, dark: true), "#123456")
    let auto = CategoryDef(name: "B")
    try expectEqual(CategoryPalette.resolvedHex(for: auto, slot: 0, dark: false), CategoryPalette.lightHex[0])
    try expectEqual(CategoryPalette.resolvedHex(for: auto, slot: 0, dark: true), CategoryPalette.darkHex[0])
    try expectEqual(CategoryPalette.resolvedHex(for: auto, slot: 8, dark: false), CategoryPalette.fallbackHex)
    try expectEqual(CategoryPalette.resolvedHex(for: nil, slot: nil, dark: false), CategoryPalette.fallbackHex)
}

check("completed days roundtrip") {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tasker-days-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try FileRepository(root: tmp)
    let d1 = Day(year: 2026, month: 9, day: 8)
    let d2 = Day(year: 2026, month: 9, day: 9)

    try expectEqual(try repo.loadCompletedDays(), [])
    try repo.saveCompletedDays([d2, d1])
    try expectEqual(try repo.loadCompletedDays(), [d1, d2])

    let data = try Data(contentsOf: StorageLayout(root: tmp).dayCompletionsFile)
    let raw = String(data: data, encoding: .utf8) ?? ""
    try expect(raw.contains("2026-09-08"))
    try expect(raw.contains("2026-09-09"))
}

check("task roundtrip with categoryId + workTypeId") {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tasker-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try FileRepository(root: tmp)

    let catId = UUID()
    let wtId = UUID()
    let day = Day.today()
    var agg = TaskAggregate(meta: TaskMeta(
        title: "hello",
        categoryId: catId,
        membership: Membership(dayAssignments: [DayAssignment(day: day)])
    ))
    try repo.save(&agg)
    let eid = agg.addEntry(inDay: day, title: "chunk", workTypeId: wtId)
    try agg.startEntry(id: eid)
    try repo.save(&agg)

    let loaded = try repo.loadAll()
    try expectEqual(loaded[0].meta.categoryId, catId)
    try expectEqual(loaded[0].entries(inDay: day)[0].workTypeId, wtId)
    try expectEqual(loaded[0].meta.membership.dayAssignments[0].entries[0].workTypeId, wtId)
}

check("legacy entries.jsonl migrates into day assignment entries and archives") {
    struct OldEntry: Encodable {
        let id: UUID
        let taskId: UUID
        let title: String
        let workTypeId: UUID?
        let startAt: Date?
        let endAt: Date?
        let marker: TimeEntry.Marker?
    }

    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tasker-migrate-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try FileRepository(root: tmp)
    let layout = StorageLayout(root: tmp)
    let d1 = Day(year: 2026, month: 7, day: 11)
    let d2 = Day(year: 2026, month: 7, day: 12)
    let taskId = UUID()
    var agg = TaskAggregate(meta: TaskMeta(
        id: taskId,
        title: "legacy",
        membership: Membership(dayAssignments: [DayAssignment(day: d1), DayAssignment(day: d2)])
    ))
    try repo.save(&agg)

    let timed = OldEntry(id: UUID(), taskId: taskId, title: "timed", workTypeId: nil,
                         startAt: d2.date().addingTimeInterval(3600), endAt: nil, marker: nil)
    let floating = OldEntry(id: UUID(), taskId: taskId, title: "floating", workTypeId: nil,
                            startAt: nil, endAt: nil, marker: nil)
    try JsonlFile.write([timed, floating], to: layout.entriesFile)

    let loaded = try repo.loadAll()
    try expectEqual(loaded[0].entries(inDay: d2).map(\.title), ["timed"])
    try expectEqual(loaded[0].entries(inDay: d1).map(\.title), ["floating"])
    try expect(!FileManager.default.fileExists(atPath: layout.entriesFile.path))
    try expect(FileManager.default.fileExists(atPath: layout.entriesLegacyFile.path))
}

print("---")
print("passed: \(passed)  failed: \(failed)")
if failed > 0 { exit(1) }
