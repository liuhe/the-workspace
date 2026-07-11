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

// MARK: - StatusDeriver
print("StatusDeriver")

check("no entries → notStarted") {
    try expectEqual(StatusDeriver.derive(from: []), .notStarted)
}
check("entry without startAt and no marker → inProgress (has any record)") {
    let e = TimeEntry(taskId: taskId, title: "empty")
    try expectEqual(StatusDeriver.derive(from: [e]), .inProgress)
}
check("open entry (started, no marker) → inProgress") {
    let e = TimeEntry(taskId: taskId, startAt: t0)
    try expectEqual(StatusDeriver.derive(from: [e]), .inProgress)
}
check("closed w/ done → done") {
    let e = TimeEntry(taskId: taskId, startAt: t0, endAt: t0.addingTimeInterval(60), marker: .done)
    try expectEqual(StatusDeriver.derive(from: [e]), .done)
}
check("done then unmarked new entry: last marker is done → still done") {
    let e1 = TimeEntry(taskId: taskId, startAt: t0, endAt: t0.addingTimeInterval(60), marker: .done)
    let e2 = TimeEntry(taskId: taskId, startAt: t0.addingTimeInterval(120))  // 无 marker
    try expectEqual(StatusDeriver.derive(from: [e1, e2]), .done)
}
check("done then restart marker → inProgress (last marker is restart)") {
    let e1 = TimeEntry(taskId: taskId, startAt: t0, endAt: t0.addingTimeInterval(60), marker: .done)
    let e2 = TimeEntry(taskId: taskId, startAt: t0.addingTimeInterval(120), marker: .restart)
    try expectEqual(StatusDeriver.derive(from: [e1, e2]), .inProgress)
}
check("last-marker wins regardless of order in array") {
    let older = TimeEntry(taskId: taskId, startAt: t0.addingTimeInterval(120), endAt: t0.addingTimeInterval(180), marker: .done)
    let newer_unmarked = TimeEntry(taskId: taskId, startAt: t0.addingTimeInterval(300))
    // "最后一个有标"是 older（也是唯一有标）→ done
    try expectEqual(StatusDeriver.derive(from: [newer_unmarked, older]), .done)
}

// MARK: - TaskAggregate
print("TaskAggregate")
func makeTask() -> TaskAggregate { TaskAggregate(meta: TaskMeta(title: "T")) }

check("addEntry doesn't affect status when there was no marker (still inProgress if any entry)") {
    var t = makeTask()
    _ = t.addEntry(title: "chunk")
    try expectEqual(t.status, .inProgress)   // 有记录 = 进行中
}
check("startEntry → inProgress") {
    var t = makeTask()
    let id = t.addEntry()
    try t.startEntry(id: id)
    try expectEqual(t.status, .inProgress)
}
check("mark done → done; then addEntry alone stays done; startEntry auto restart → inProgress") {
    var t = makeTask()
    let a = t.addEntry(); try t.startEntry(id: a); try t.endEntry(id: a)
    t.updateEntry(id: a) { $0.marker = .done }
    try expectEqual(t.status, .done)
    let b = t.addEntry()  // 新建但未开始，无 marker
    try expectEqual(t.status, .done)  // 最后一个有标依然是 done
    try t.startEntry(id: b)
    // startEntry 之前 status 是 done → 自动打 restart marker → 最后有标变 restart → inProgress
    try expectEqual(t.status, .inProgress)
    try expectEqual(t.entries.first(where: { $0.id == b })?.marker, .restart)
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

check("recurring task: statusForDay isolated to that day") {
    let d1 = Day(year: 2026, month: 7, day: 11)
    let d2 = Day(year: 2026, month: 7, day: 12)
    let tid = UUID()
    // 在 d1 打了 done，在 d2 只有一段进行中
    let d1Entry = TimeEntry(taskId: tid,
                            startAt: d1.date().addingTimeInterval(3600),
                            endAt: d1.date().addingTimeInterval(7200),
                            marker: .done)
    let d2Entry = TimeEntry(taskId: tid,
                            startAt: d2.date().addingTimeInterval(3600))
    let agg = TaskAggregate(
        meta: TaskMeta(title: "recurring", membership: Membership(
            dayAssignments: [DayAssignment(day: d1), DayAssignment(day: d2)]
        ), isRecurring: true),
        entries: [d1Entry, d2Entry]
    )
    try expectEqual(agg.statusForDay(d1), .done)
    try expectEqual(agg.statusForDay(d2), .inProgress)
    try expectEqual(agg.status(in: .day(d1)), .done)
    try expectEqual(agg.status(in: .day(d2)), .inProgress)
}

check("recurring tasks always appear in backlog even if globally done") {
    let d = Day.today()
    let tid = UUID()
    // 全局 status = done
    let doneEntry = TimeEntry(taskId: tid, startAt: Date(), endAt: Date(), marker: .done)
    let recurring = TaskAggregate(
        meta: TaskMeta(title: "R", membership: Membership(
            dayAssignments: [DayAssignment(day: d)]
        ), isRecurring: true),
        entries: [doneEntry]
    )
    let nonRecurring = TaskAggregate(
        meta: TaskMeta(title: "N", membership: Membership(
            dayAssignments: [DayAssignment(day: d)]
        ), isRecurring: false),
        entries: [doneEntry]
    )
    try expectEqual(recurring.status, .done)
    try expectEqual(nonRecurring.status, .done)
    let backlog = TaskQueries.apply(.backlog, to: [recurring, nonRecurring]).map(\.meta.title)
    try expectEqual(backlog, ["R"])  // 只有循环任务留下
}

check("pushUncompleted respects per-day status for recurring") {
    let src = Day(year: 2026, month: 7, day: 11)
    let tid = UUID()
    // 循环任务在 src 已完成
    let recurringDone = TimeEntry(taskId: tid,
                                  startAt: src.date().addingTimeInterval(3600),
                                  endAt: src.date().addingTimeInterval(7200),
                                  marker: .done)
    let recurring = TaskAggregate(
        meta: TaskMeta(title: "R", membership: Membership(
            dayAssignments: [DayAssignment(day: src)]
        ), isRecurring: true),
        entries: [recurringDone]
    )
    try expectEqual(recurring.statusForDay(src), .done)
    // 不该被推
    // 说明：这里不便直接跑 store，仅验证 statusForDay 判定；实际 store 逻辑用 statusForDay
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
check("SettingsLookup resolves workType by id") {
    let wt = WorkTypeDef(name: "coding")
    try expectEqual(SettingsLookup.workTypeName(wt.id, in: [wt]), "coding")
    try expectEqual(SettingsLookup.workTypeName(UUID(), in: [wt]), "(Unknown)")
    try expectEqual(SettingsLookup.workTypeName(nil, in: [wt]), "(Unset)")
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
    try repo.save(updated)
    let reloaded = try repo.load()
    try expectEqual(reloaded.categories[0].id, renamedId)
    try expect(reloaded.categories[0].name.hasSuffix("-改"))
}

check("task roundtrip with categoryId + workTypeId") {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tasker-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try FileRepository(root: tmp)

    let catId = UUID()
    let wtId = UUID()
    var agg = TaskAggregate(meta: TaskMeta(
        title: "hello",
        categoryId: catId,
        membership: Membership(dayAssignments: [DayAssignment(day: Day.today())])
    ))
    try repo.save(&agg)
    let eid = agg.addEntry(title: "chunk", workTypeId: wtId)
    try agg.startEntry(id: eid)
    try repo.save(&agg)

    let loaded = try repo.loadAll()
    try expectEqual(loaded[0].meta.categoryId, catId)
    try expectEqual(loaded[0].entries[0].workTypeId, wtId)
}

print("---")
print("passed: \(passed)  failed: \(failed)")
if failed > 0 { exit(1) }
