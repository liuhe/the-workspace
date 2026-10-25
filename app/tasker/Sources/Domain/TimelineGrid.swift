import Foundation

/// 甘特图时间轴编辑规则。所有量都是"距当天 0:00 的秒数"（0...86400），
/// 这样规则与 Date / 时区解耦，可以直接被 check 验证。
///
/// - 最小刻度 5 分钟：拖动 / 拉伸落点一律吸附到 5 分钟格
/// - 时间段不能越出当天 [0:00, 24:00]
/// - 时间段最短 1 格（5 分钟），起点必须早于终点
public enum TimelineGrid {
    public static let stepSeconds: TimeInterval = 5 * 60
    public static let dayLength: TimeInterval = 24 * 3600

    /// 吸附到最近的 5 分钟格，并夹到当天范围内
    public static func snap(_ offset: TimeInterval) -> TimeInterval {
        let snapped = (offset / stepSeconds).rounded() * stepSeconds
        return min(max(snapped, 0), dayLength)
    }

    /// 整体平移：起点吸附到格，时长保持不变；整段不越出当天
    public static func move(start: TimeInterval, end: TimeInterval, by delta: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
        let duration = max(end - start, stepSeconds)
        var newStart = snap(start + delta)
        if newStart + duration > dayLength {
            // 贴到当天末尾；若时长本身超过一天的剩余，退到 0
            newStart = max(0, (dayLength - duration))
            newStart = (newStart / stepSeconds).rounded(.down) * stepSeconds
        }
        return (newStart, newStart + duration)
    }

    /// 拉伸起点：吸附到格，且至少比终点早 1 格
    public static func resizeStart(start: TimeInterval, end: TimeInterval, to candidate: TimeInterval) -> TimeInterval {
        let upper = end - stepSeconds
        return min(snap(candidate), max(0, upper))
    }

    /// 拉伸终点：吸附到格，且至少比起点晚 1 格
    public static func resizeEnd(start: TimeInterval, end: TimeInterval, to candidate: TimeInterval) -> TimeInterval {
        let lower = start + stepSeconds
        return max(snap(candidate), min(dayLength, lower))
    }

    /// 在空白处拖出新时间段：两端吸附到格，自动排序，最短 1 格
    public static func newRange(from a: TimeInterval, to b: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
        var s = snap(min(a, b))
        var e = snap(max(a, b))
        if e - s < stepSeconds {
            if s + stepSeconds <= dayLength {
                e = s + stepSeconds
            } else {
                e = dayLength
                s = dayLength - stepSeconds
            }
        }
        return (s, e)
    }

    // MARK: - Date ↔ 当天秒偏移

    public static func offset(of date: Date, inDay day: Day, calendar: Calendar = .current) -> TimeInterval {
        let dayStart = calendar.startOfDay(for: day.date(calendar: calendar))
        return date.timeIntervalSince(dayStart)
    }

    public static func date(atOffset offset: TimeInterval, inDay day: Day, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: day.date(calendar: calendar))
        return dayStart.addingTimeInterval(offset)
    }

    /// "HH:mm" 文案（偏移 86400 显示为 24:00）
    public static func label(_ offset: TimeInterval) -> String {
        let total = Int(offset.rounded()) / 60
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
