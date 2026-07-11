import SwiftUI
import TaskerDomain

/// 简易月历视图；被选中日子高亮；有任务的日子加小点。
struct MiniCalendarView: View {
    @Binding var selectedDate: Date
    let daysWithTasks: Set<Day>
    @State private var monthAnchor: Date

    init(selectedDate: Binding<Date>, daysWithTasks: Set<Day>) {
        self._selectedDate = selectedDate
        self.daysWithTasks = daysWithTasks
        self._monthAnchor = State(initialValue: selectedDate.wrappedValue)
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // 周一为一周首日
        cal.locale = Locale(identifier: "zh_CN")
        return cal
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayHeader
            grid
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                if let m = calendar.date(byAdding: .month, value: -1, to: monthAnchor) {
                    monthAnchor = m
                }
            } label: { Image(systemName: "chevron.left") }
            .buttonStyle(.plain)

            Spacer()
            Text(monthTitle).font(.headline)
            Spacer()

            Button {
                if let m = calendar.date(byAdding: .month, value: 1, to: monthAnchor) {
                    monthAnchor = m
                }
            } label: { Image(systemName: "chevron.right") }
            .buttonStyle(.plain)
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月"
        return f.string(from: monthAnchor)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { d in
                Text(d).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid

    private var daysInMonth: [Day?] {
        let comps = calendar.dateComponents([.year, .month], from: monthAnchor)
        guard let year = comps.year, let month = comps.month,
              let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return []
        }
        let weekdayOfFirst = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        var result: [Day?] = Array(repeating: nil, count: leadingBlanks)
        if let range = calendar.range(of: .day, in: .month, for: firstDay) {
            for d in range {
                result.append(Day(year: year, month: month, day: d))
            }
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private var grid: some View {
        let cells = daysInMonth
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 6
        ) {
            ForEach(0..<cells.count, id: \.self) { idx in
                cellView(day: cells[idx])
                    .frame(height: 40)
            }
        }
    }

    @ViewBuilder
    private func cellView(day: Day?) -> some View {
        if let d = day {
            let selectedDay = Day(date: selectedDate, calendar: calendar)
            let isSelected = d == selectedDay
            let hasTasks = daysWithTasks.contains(d)
            Button {
                selectedDate = d.date(calendar: calendar)
            } label: {
                VStack(spacing: 2) {
                    Text("\(d.day)")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(width: 28, height: 24)
                        .background(isSelected ? Color.accentColor : Color.clear)
                        .clipShape(Capsule())
                    Circle()
                        .fill(hasTasks ? Color.accentColor : Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
        }
    }
}
