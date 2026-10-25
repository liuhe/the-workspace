import SwiftUI
import AppKit
import TaskerDomain

// MARK: - 配色：分类色由 CategoryColor 解析（设置里指定 > 按分类顺序的调色板槽位 > 灰）

// MARK: - 布局常量

enum GanttLayout {
    static let labelWidth: CGFloat = 260
    static let durationWidth: CGFloat = 60
    static let rowHeight: CGFloat = 32
    static let barHeight: CGFloat = 20
    static let handleWidth: CGFloat = 7
    static let rulerHeight: CGFloat = 26
    static let columnSpacing: CGFloat = 8
}

// MARK: - 可见时段（小时整点，0...24）

struct VisibleRange: Equatable {
    var startHour: Int
    var endHour: Int

    var startOffset: TimeInterval { TimeInterval(startHour) * 3600 }
    var endOffset: TimeInterval { TimeInterval(endHour) * 3600 }
    var span: TimeInterval { max(endOffset - startOffset, 3600) }

    func x(for offset: TimeInterval, width: CGFloat) -> CGFloat {
        CGFloat((offset - startOffset) / span) * width
    }
    func offset(forX x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return startOffset }
        return startOffset + TimeInterval(x / width) * span
    }
    func seconds(forDeltaX dx: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        return TimeInterval(dx / width) * span
    }

    /// 自动范围：覆盖当天所有记录，前后各留 1 小时；无记录默认 08–19
    static func auto(for rows: [GanttTaskRow]) -> VisibleRange {
        var lo: TimeInterval = .infinity
        var hi: TimeInterval = -.infinity
        for row in rows {
            for item in row.timed {
                lo = min(lo, item.start)
                hi = max(hi, item.end)
            }
        }
        guard lo.isFinite, hi.isFinite else { return VisibleRange(startHour: 8, endHour: 19) }
        let s = max(0, Int(floor(lo / 3600)) - 1)
        let e = min(24, Int(ceil(hi / 3600)) + 1)
        return VisibleRange(startHour: s, endHour: max(e, s + 1))
    }
}

// MARK: - 行数据

struct GanttTimedEntry: Identifiable {
    let entry: TimeEntry
    let start: TimeInterval
    /// 已结束的记录是真实终点；未结束的是展示用的临时终点
    let end: TimeInterval
    let isOpen: Bool
    var id: UUID { entry.id }
}

struct GanttTaskRow: Identifiable {
    let task: TaskAggregate
    let day: Day
    let timed: [GanttTimedEntry]
    var id: UUID { task.id }

    var total: TimeInterval {
        task.entries(inDay: day).compactMap { $0.duration(inDay: day) }.reduce(0, +)
    }

    init(task: TaskAggregate, day: Day, now: Date) {
        self.task = task
        self.day = day
        let isToday = day == Day.today()
        let nowOffset = TimelineGrid.offset(of: now, inDay: day)
        self.timed = task.entries(inDay: day).compactMap { e in
            guard let s = e.startAt(inDay: day) else { return nil }
            let start = TimelineGrid.offset(of: s, inDay: day)
            if let en = e.endAt(inDay: day) {
                return GanttTimedEntry(entry: e, start: start,
                                       end: max(TimelineGrid.offset(of: en, inDay: day), start + TimelineGrid.stepSeconds),
                                       isOpen: false)
            }
            let provisional: TimeInterval
            if isToday, nowOffset > start + TimelineGrid.stepSeconds {
                provisional = min(nowOffset, TimelineGrid.dayLength)
            } else {
                provisional = min(start + 6 * TimelineGrid.stepSeconds, TimelineGrid.dayLength)
            }
            return GanttTimedEntry(entry: e, start: start, end: provisional, isOpen: true)
        }
    }
}

struct GanttCategoryGroup: Identifiable {
    let def: CategoryDef
    let slot: Int?
    let rows: [GanttTaskRow]
    var id: UUID { def.id }
}

enum GanttBuilder {
    static func build(tasks: [TaskAggregate], settings: AppSettings, day: Day, now: Date) -> [GanttCategoryGroup] {
        let inDay = TaskQueries.apply(.day(day), to: tasks)
        let grouped = TaskQueries.groupByCategory(inDay, categories: settings.categories)
        return grouped.map { (def, ts) in
            let slot = settings.categories.firstIndex(where: { $0.id == def.id })
            return GanttCategoryGroup(def: def, slot: slot,
                                      rows: ts.map { GanttTaskRow(task: $0, day: day, now: now) })
        }
    }
}

/// 甘特图里的选中对象：点任务名选中任务（改标题 / 分类 / 当天优先级），点色条选中记录（改标题 / 起止）
enum GanttSelection: Equatable {
    case task(UUID)
    case entry(taskId: UUID, entryId: UUID)
}

// MARK: - 主视图

struct GanttView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var date: Date = Calendar.current.startOfDay(for: Date())
    @State private var manualRange: VisibleRange?
    @State private var selection: GanttSelection?
    @State private var showingNewTaskSheet = false

    private var day: Day { Day(date: date) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            content(now: ctx.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let groups = GanttBuilder.build(tasks: store.tasks, settings: store.settings, day: day, now: now)
        let range = manualRange ?? VisibleRange.auto(for: groups.flatMap(\.rows))
        VStack(spacing: 0) {
            header(range: range)
            Divider()
            if groups.isEmpty {
                Spacer()
                Text("No tasks on this day.").foregroundStyle(.secondary)
                Spacer()
            } else {
                GanttRulerRow(range: range, nowOffset: nowOffset(now))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            GanttCategoryHeader(group: group)
                            ForEach(group.rows) { row in
                                GanttTaskRowView(row: row, range: range, def: group.def, slot: group.slot,
                                                 nowOffset: nowOffset(now), selection: $selection)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            Divider()
            GanttInspector(day: day, selection: $selection)
        }
        .onChange(of: date) { _, _ in
            manualRange = nil
            selection = nil
        }
    }

    private func nowOffset(_ now: Date) -> TimeInterval? {
        guard day == Day.today() else { return nil }
        return TimelineGrid.offset(of: now, inDay: day)
    }

    @ViewBuilder
    private func header(range: VisibleRange) -> some View {
        HStack(spacing: 12) {
            Text("Gantt").font(.title2)
            HStack(spacing: 4) {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                DatePicker("", selection: $date, displayedComponents: [.date])
                    .labelsHidden()
                    .controlSize(.small)
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                Button("Today") { date = Calendar.current.startOfDay(for: Date()) }
                    .controlSize(.small)
            }
            Text(day.weekdayLabel() + (store.isDayCompleted(day) ? " ✓" : ""))
                .foregroundStyle(.secondary)
            Button {
                showingNewTaskSheet = true
            } label: { Image(systemName: "plus") }
            .help("New task on this day")
            .sheet(isPresented: $showingNewTaskSheet) {
                NewTaskSheet(isPresented: $showingNewTaskSheet, targetDay: day) { id in
                    selection = .task(id)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Text("Hours").foregroundStyle(.secondary)
                Stepper(value: Binding(
                    get: { range.startHour },
                    set: { manualRange = VisibleRange(startHour: $0, endHour: range.endHour) }
                ), in: 0...(range.endHour - 1)) {
                    Text(String(format: "%02d:00", range.startHour))
                        .font(.system(.body, design: .monospaced))
                }
                Text("–").foregroundStyle(.secondary)
                Stepper(value: Binding(
                    get: { range.endHour },
                    set: { manualRange = VisibleRange(startHour: range.startHour, endHour: $0) }
                ), in: (range.startHour + 1)...24) {
                    Text(String(format: "%02d:00", range.endHour))
                        .font(.system(.body, design: .monospaced))
                }
                Button("Auto") { manualRange = nil }
                    .disabled(manualRange == nil)
            }
            .controlSize(.small)
        }
        .padding(16)
    }

    private func shiftDay(_ delta: Int) {
        let cal = Calendar.current
        date = cal.date(byAdding: .day, value: delta, to: date) ?? date
    }
}

// MARK: - 顶部刻度

private struct GanttRulerRow: View {
    let range: VisibleRange
    let nowOffset: TimeInterval?

    var body: some View {
        HStack(spacing: GanttLayout.columnSpacing) {
            Spacer().frame(width: GanttLayout.labelWidth)
            GanttRuler(range: range, nowOffset: nowOffset).frame(maxWidth: .infinity)
            Spacer().frame(width: GanttLayout.durationWidth)
        }
        .frame(height: GanttLayout.rulerHeight)
    }
}

private struct GanttRuler: View {
    let range: VisibleRange
    let nowOffset: TimeInterval?

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let pxPerHour = w / CGFloat(range.endHour - range.startHour)
            let labelStep = pxPerHour >= 48 ? 1 : (pxPerHour >= 26 ? 2 : 3)
            let minorMinutes: Int? = pxPerHour >= 110 ? 15 : (pxPerHour >= 55 ? 30 : nil)
            let major = GraphicsContext.Shading.color(.secondary.opacity(0.6))
            let minor = GraphicsContext.Shading.color(.secondary.opacity(0.3))
            let baseY = size.height
            for h in range.startHour...range.endHour {
                let x = range.x(for: TimeInterval(h) * 3600, width: w)
                ctx.fill(Path(CGRect(x: x - 0.5, y: baseY - 6, width: 1, height: 6)), with: major)
                if (h - range.startHour) % labelStep == 0 || h == range.endHour {
                    let label = Text(String(format: "%02d:00", h))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    let anchor: UnitPoint = h == range.startHour ? .bottomLeading
                        : (h == range.endHour ? .bottomTrailing : .bottom)
                    ctx.draw(label, at: CGPoint(x: x, y: baseY - 8), anchor: anchor)
                }
                if let minorMinutes, h < range.endHour {
                    var m = minorMinutes
                    while m < 60 {
                        let mx = range.x(for: TimeInterval(h) * 3600 + TimeInterval(m) * 60, width: w)
                        ctx.fill(Path(CGRect(x: mx - 0.5, y: baseY - 3, width: 1, height: 3)), with: minor)
                        m += minorMinutes
                    }
                }
            }
            if let nowOffset, nowOffset >= range.startOffset, nowOffset <= range.endOffset {
                let x = range.x(for: nowOffset, width: w)
                var tri = Path()
                tri.move(to: CGPoint(x: x - 4, y: baseY - 8))
                tri.addLine(to: CGPoint(x: x + 4, y: baseY - 8))
                tri.addLine(to: CGPoint(x: x, y: baseY))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(.red))
            }
        }
    }
}

// MARK: - 分类标题行

private struct GanttCategoryHeader: View {
    @Environment(\.colorScheme) private var scheme
    let group: GanttCategoryGroup

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(CategoryColor.resolve(def: group.def, slot: group.slot, scheme: scheme))
                .frame(width: 10, height: 10)
            Text(group.def.name).font(.headline)
            Text("\(group.rows.count)")
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
            Spacer()
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

// MARK: - 任务行：[标题] [时间轴] [时长]

private struct GanttTaskRowView: View {
    @Environment(\.colorScheme) private var scheme
    let row: GanttTaskRow
    let range: VisibleRange
    let def: CategoryDef
    let slot: Int?
    let nowOffset: TimeInterval?
    @Binding var selection: GanttSelection?

    var body: some View {
        HStack(spacing: GanttLayout.columnSpacing) {
            label.frame(width: GanttLayout.labelWidth, alignment: .leading)
            GanttTrack(row: row, range: range,
                       color: CategoryColor.resolve(def: def, slot: slot, scheme: scheme),
                       nowOffset: nowOffset, selection: $selection)
                .frame(maxWidth: .infinity)
            Text(StatsFormat.duration(row.total))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: GanttLayout.durationWidth, alignment: .trailing)
        }
        .frame(height: GanttLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isTaskSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
    }

    private var isTaskSelected: Bool { selection == .task(row.id) }

    /// 与侧栏一致：该天优先级的 emoji 前缀 + 标题
    private var displayTitle: String {
        let t = row.task.meta.title.isEmpty ? "(Untitled)" : row.task.meta.title
        return "\(row.task.priority(in: .day(row.day)).titlePrefix)\(t)"
    }

    private var label: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 16)
            Text(displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .fontWeight(isTaskSelected ? .semibold : .regular)
            Spacer(minLength: 0)
            statusMark
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selection = isTaskSelected ? nil : .task(row.id)
        }
    }

    @ViewBuilder
    private var statusMark: some View {
        switch row.task.statusForDay(row.day) {
        case .done:
            Image(systemName: "checkmark").font(.caption2).foregroundStyle(.secondary)
        case .inProgress:
            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
        case .notStarted:
            EmptyView()
        }
    }
}

// MARK: - 时间轴（可拖动编辑）

private struct DragSession {
    enum Mode { case move, resizeStart, resizeEnd, create }
    let mode: Mode
    let entryId: UUID?
    let isOpen: Bool
    let originStart: TimeInterval
    let originEnd: TimeInterval
    let anchor: TimeInterval
    var start: TimeInterval
    var end: TimeInterval
    var moved = false
}

private struct GanttTrack: View {
    @EnvironmentObject var store: WorkspaceStore
    let row: GanttTaskRow
    let range: VisibleRange
    let color: Color
    let nowOffset: TimeInterval?
    @Binding var selection: GanttSelection?
    @State private var drag: DragSession?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                GanttGridLines(range: range, nowOffset: nowOffset)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(createGesture(width: w))
                ForEach(row.timed) { item in
                    bar(for: item, width: w)
                }
                if let drag, drag.mode == .create {
                    previewBar(start: drag.start, end: drag.end, width: w)
                }
            }
            .coordinateSpace(name: "track")
        }
        .frame(height: GanttLayout.rowHeight)
        .clipped()
    }

    // MARK: 条

    private func displayed(_ item: GanttTimedEntry) -> (start: TimeInterval, end: TimeInterval) {
        if let drag, drag.entryId == item.id { return (drag.start, drag.end) }
        return (item.start, item.end)
    }

    @ViewBuilder
    private func bar(for item: GanttTimedEntry, width w: CGFloat) -> some View {
        let (s, e) = displayed(item)
        let x0 = range.x(for: s, width: w)
        let x1 = range.x(for: e, width: w)
        let bw = max(x1 - x0, 4)
        let isSelected = selection == .entry(taskId: row.id, entryId: item.id)
        let isDragging = drag?.entryId == item.id
        let titleText = item.entry.title.isEmpty ? "(no title)" : item.entry.title
        // 条太窄放不下标题时，标题从条左边缘起向右书写，允许超出条本身
        let labelFits = bw > 56
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(item.isOpen ? 0.35 : 0.9))
            if item.isOpen {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary, lineWidth: 2)
            }
            if labelFits {
                Text(titleText)
                    .font(.caption)
                    .foregroundStyle(item.isOpen ? Color.primary : Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, GanttLayout.handleWidth + 2)
            }
            HStack(spacing: 0) {
                handle(mode: .resizeStart, item: item, width: w)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(barGesture(mode: .move, item: item, width: w))
                    .onHover { inside in
                        if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                    }
                handle(mode: .resizeEnd, item: item, width: w)
            }
        }
        .frame(width: bw, height: GanttLayout.barHeight)
        .overlay(alignment: .leading) {
            if !labelFits {
                Text(titleText)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: 4)
                    .allowsHitTesting(false)
            }
        }
        .offset(x: x0, y: (GanttLayout.rowHeight - GanttLayout.barHeight) / 2)
        .overlay(alignment: .topLeading) {
            if isDragging {
                Text("\(TimelineGrid.label(s)) – \(TimelineGrid.label(e))")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.4)))
                    .fixedSize()
                    .offset(x: x0, y: -16)
            }
        }
        .help(helpText(item))
        .zIndex(isDragging ? 2 : (isSelected ? 1 : 0))
    }

    private func helpText(_ item: GanttTimedEntry) -> String {
        let title = item.entry.title.isEmpty ? "(no title)" : item.entry.title
        let endText = item.isOpen ? "…" : TimelineGrid.label(item.end)
        return "\(title)\n\(TimelineGrid.label(item.start)) – \(endText)"
    }

    private func handle(mode: DragSession.Mode, item: GanttTimedEntry, width w: CGFloat) -> some View {
        Color.clear
            .frame(width: GanttLayout.handleWidth)
            .contentShape(Rectangle())
            .gesture(barGesture(mode: mode, item: item, width: w))
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    @ViewBuilder
    private func previewBar(start: TimeInterval, end: TimeInterval, width w: CGFloat) -> some View {
        let x0 = range.x(for: start, width: w)
        let x1 = range.x(for: end, width: w)
        RoundedRectangle(cornerRadius: 4)
            .fill(color.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: 1.5))
            .frame(width: max(x1 - x0, 4), height: GanttLayout.barHeight)
            .offset(x: x0, y: (GanttLayout.rowHeight - GanttLayout.barHeight) / 2)
            .overlay(alignment: .topLeading) {
                Text("\(TimelineGrid.label(start)) – \(TimelineGrid.label(end))")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.4)))
                    .fixedSize()
                    .offset(x: x0, y: -16)
            }
            .allowsHitTesting(false)
    }

    // MARK: 手势

    private func barGesture(mode: DragSession.Mode, item: GanttTimedEntry, width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("track"))
            .onChanged { value in
                if drag == nil || drag?.entryId != item.id || drag?.mode != mode {
                    drag = DragSession(mode: mode, entryId: item.id, isOpen: item.isOpen,
                                       originStart: item.start, originEnd: item.end,
                                       anchor: range.offset(forX: value.startLocation.x, width: w),
                                       start: item.start, end: item.end)
                }
                guard var d = drag else { return }
                if abs(value.translation.width) >= 3 { d.moved = true }
                switch mode {
                case .move:
                    let delta = range.seconds(forDeltaX: value.translation.width, width: w)
                    let r = TimelineGrid.move(start: d.originStart, end: d.originEnd, by: delta)
                    d.start = r.start
                    d.end = r.end
                case .resizeStart:
                    let candidate = range.offset(forX: value.location.x, width: w)
                    d.start = TimelineGrid.resizeStart(start: d.originStart, end: d.originEnd, to: candidate)
                case .resizeEnd:
                    let candidate = range.offset(forX: value.location.x, width: w)
                    d.end = TimelineGrid.resizeEnd(start: d.originStart, end: d.originEnd, to: candidate)
                case .create:
                    break
                }
                drag = d
            }
            .onEnded { _ in
                guard let d = drag else { return }
                drag = nil
                let sel: GanttSelection = .entry(taskId: row.id, entryId: item.id)
                if !d.moved {
                    selection = selection == sel ? nil : sel
                    return
                }
                selection = sel
                switch d.mode {
                case .move, .resizeStart:
                    // 未结束的记录只改起点，终点保持"进行中"
                    store.setEntryRange(taskId: row.id, entryId: item.id, inDay: row.day,
                                        start: d.start, end: d.isOpen ? nil : d.end)
                case .resizeEnd:
                    // 拖未结束记录的右端 = 给它一个终点
                    store.setEntryRange(taskId: row.id, entryId: item.id, inDay: row.day,
                                        start: d.start, end: d.end)
                case .create:
                    break
                }
            }
    }

    private func createGesture(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("track"))
            .onChanged { value in
                let anchor = range.offset(forX: value.startLocation.x, width: w)
                if drag == nil || drag?.mode != .create {
                    let r = TimelineGrid.newRange(from: anchor, to: anchor)
                    drag = DragSession(mode: .create, entryId: nil, isOpen: false,
                                       originStart: r.start, originEnd: r.end, anchor: anchor,
                                       start: r.start, end: r.end)
                }
                guard var d = drag else { return }
                if abs(value.translation.width) >= 3 { d.moved = true }
                let r = TimelineGrid.newRange(from: d.anchor, to: range.offset(forX: value.location.x, width: w))
                d.start = r.start
                d.end = r.end
                drag = d
            }
            .onEnded { _ in
                guard let d = drag else { return }
                drag = nil
                if !d.moved {
                    selection = nil
                    return
                }
                store.addTimedEntry(taskId: row.id, inDay: row.day, start: d.start, end: d.end)
            }
    }
}

private struct GanttGridLines: View {
    let range: VisibleRange
    let nowOffset: TimeInterval?

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let hour = GraphicsContext.Shading.color(.secondary.opacity(0.18))
            let half = GraphicsContext.Shading.color(.secondary.opacity(0.07))
            for h in range.startHour...range.endHour {
                let x = range.x(for: TimeInterval(h) * 3600, width: w)
                ctx.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)), with: hour)
                if h < range.endHour {
                    let hx = range.x(for: TimeInterval(h) * 3600 + 1800, width: w)
                    ctx.fill(Path(CGRect(x: hx - 0.5, y: 0, width: 1, height: size.height)), with: half)
                }
            }
            if let nowOffset, nowOffset >= range.startOffset, nowOffset <= range.endOffset {
                let x = range.x(for: nowOffset, width: w)
                ctx.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)),
                         with: .color(.red.opacity(0.7)))
            }
        }
    }
}

// MARK: - 底部选中条目编辑（标题可直接改；DatePicker 输入同样吸附到 5 分钟）

private struct GanttInspector: View {
    @EnvironmentObject var store: WorkspaceStore
    let day: Day
    @Binding var selection: GanttSelection?

    var body: some View {
        HStack(spacing: 10) {
            switch selection {
            case .task(let taskId):
                if let task = store.tasks.first(where: { $0.id == taskId }) {
                    taskEditor(task)
                } else {
                    hint
                }
            case .entry(let taskId, let entryId):
                if let task = store.tasks.first(where: { $0.id == taskId }),
                   let entry = task.entries(inDay: day).first(where: { $0.id == entryId }),
                   let startAt = entry.startAt(inDay: day) {
                    entryEditor(task: task, entry: entry, startAt: startAt)
                } else {
                    hint
                }
            case nil:
                hint
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 40)
    }

    private var hint: some View {
        HStack {
            Text("Click a task to edit it · click a bar to select · drag to move · drag an edge to resize · drag on empty space to add · 5-minute grid")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var closeButton: some View {
        Button {
            selection = nil
        } label: { Image(systemName: "xmark.circle") }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: 任务：标题 / 分类 / 当天优先级

    @ViewBuilder
    private func taskEditor(_ task: TaskAggregate) -> some View {
        Text("Task").font(.caption).foregroundStyle(.secondary)
        TextField("Task title", text: Binding(
            get: { task.meta.title },
            set: { new in store.updateMeta(id: task.id) { $0.title = new } }
        ))
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .frame(maxWidth: 360)
        Spacer()
        Text("Category").font(.caption).foregroundStyle(.secondary)
        Picker("", selection: Binding<UUID?>(
            get: { task.meta.categoryId },
            set: { id in store.updateMeta(id: task.id) { $0.categoryId = id } }
        )) {
            Text(SettingsLookup.unsetName).tag(UUID?.none)
            ForEach(store.settings.categories) { def in
                Text(def.name).tag(UUID?.some(def.id))
            }
            if let cid = task.meta.categoryId,
               !store.settings.categories.contains(where: { $0.id == cid }) {
                Text(SettingsLookup.unknownName).tag(UUID?.some(cid))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
        Text("Priority").font(.caption).foregroundStyle(.secondary)
        Picker("", selection: Binding<Priority>(
            get: { task.meta.membership.priority(inDay: day) ?? .normal },
            set: { p in store.setPriority(id: task.id, inDay: day, priority: p) }
        )) {
            ForEach(Priority.allCases, id: \.self) { p in
                Text("\(p.titlePrefix)\(p.displayName)").tag(p)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
        closeButton
    }

    // MARK: 记录：标题 / 起止

    @ViewBuilder
    private func entryEditor(task: TaskAggregate, entry: TimeEntry, startAt: Date) -> some View {
                let start = TimelineGrid.offset(of: startAt, inDay: day)
                let end = entry.endAt(inDay: day).map { TimelineGrid.offset(of: $0, inDay: day) }
                Text(task.meta.title.isEmpty ? "(Untitled)" : task.meta.title)
                    .font(.headline).lineLimit(1)
                Text("·").foregroundStyle(.secondary)
                TextField("Entry title", text: Binding(
                    get: { entry.title },
                    set: { new in store.updateEntry(taskId: task.id, entryId: entry.id) { $0.title = new } }
                ))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 360)
                Spacer()
                DatePicker("", selection: Binding(
                    get: { startAt },
                    set: { new in
                        let candidate = TimelineGrid.offset(of: new, inDay: day)
                        let s = end.map { TimelineGrid.resizeStart(start: start, end: $0, to: candidate) }
                            ?? TimelineGrid.snap(candidate)
                        store.setEntryRange(taskId: task.id, entryId: entry.id, inDay: day, start: s, end: end)
                    }
                ), displayedComponents: [.hourAndMinute])
                .labelsHidden()
                .controlSize(.small)
                Text("→").foregroundStyle(.secondary)
                if let end, let endAt = entry.endAt(inDay: day) {
                    DatePicker("", selection: Binding(
                        get: { endAt },
                        set: { new in
                            let candidate = TimelineGrid.offset(of: new, inDay: day)
                            let e = TimelineGrid.resizeEnd(start: start, end: end, to: candidate)
                            store.setEntryRange(taskId: task.id, entryId: entry.id, inDay: day, start: start, end: e)
                        }
                    ), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .controlSize(.small)
                    Text(StatsFormat.duration(end - start))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("in progress").foregroundStyle(.secondary)
                }
                closeButton
    }
}
