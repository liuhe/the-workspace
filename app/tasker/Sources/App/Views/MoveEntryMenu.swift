import SwiftUI
import TaskerDomain

/// "移到另一天"菜单：前后 3 天（★ 今天 / ● 任务已关联 / ✓ 已完成日；记录所在那天置灰）+ Choose date…
/// 主窗口记录行和甘特图记录编辑条共用；选任意日期的弹框由调用方通过 `onPickDay` 自行挂载。
struct MoveEntryMenu: View {
    @EnvironmentObject var store: WorkspaceStore
    let aggregate: TaskAggregate
    let entryId: UUID
    /// 记录目前所在的那天
    let currentDay: Day
    let onPickDay: () -> Void
    /// 移动前的回调（甘特图用来清空选中，因为移走后这条记录不再属于正在看的那天）
    var beforeMove: () -> Void = {}

    var body: some View {
        Menu {
            ForEach(-3...3, id: \.self) { offset in
                dayItem(day: Self.dayOffset(offset))
            }
            Button("Choose date…") { onPickDay() }
        } label: {
            Image(systemName: "calendar.badge.clock").font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Move this entry to another day")
    }

    @ViewBuilder
    private func dayItem(day: Day) -> some View {
        let isToday = day == Day.today()
        let already = aggregate.meta.membership.days.contains(day)
        let isCompleted = store.isDayCompleted(day)
        let text = (isToday ? "★ " : "") + day.descriptionWithWeekday + (already ? " ●" : "") + (isCompleted ? " ✓" : "")
        Button(text) { move(to: day) }
            .disabled(day == currentDay)
    }

    func move(to day: Day) {
        guard day != currentDay else { return }
        beforeMove()
        store.moveEntry(taskId: aggregate.id, entryId: entryId, toDay: day)
    }

    private static func dayOffset(_ n: Int) -> Day {
        let d = Calendar.current.date(byAdding: .day, value: n, to: Date()) ?? Date()
        return Day(date: d)
    }
}

/// `.sheet(item:)` 用的记录身份包装
struct EntryRef: Identifiable, Hashable {
    let taskId: UUID
    let entryId: UUID
    var id: UUID { entryId }
}
