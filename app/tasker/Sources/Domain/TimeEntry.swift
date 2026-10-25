import Foundation

public struct TimeEntry: Codable, Hashable, Identifiable, Sendable {
    public enum Marker: String, Codable, Sendable {
        case done
        case restart
    }

    public let id: UUID
    public var title: String

    /// 工作类型引用（AppSettings.workTypes[].id）；nil = 未设置
    public var workTypeId: UUID?

    public var startAt: Date?
    public var endAt: Date?
    public var marker: Marker?
    /// 手动填写的实际占用分钟数；nil = 用 endAt - startAt 计算
    public var actualMinutes: Int?

    public init(id: UUID = UUID(),
                title: String = "",
                workTypeId: UUID? = nil,
                startAt: Date? = nil,
                endAt: Date? = nil,
                marker: Marker? = nil,
                actualMinutes: Int? = nil) {
        self.id = id
        self.title = title
        self.workTypeId = workTypeId
        self.startAt = startAt
        self.endAt = endAt
        self.marker = marker
        self.actualMinutes = actualMinutes
    }

    public var isOpen: Bool { startAt != nil && endAt == nil }
    public var isNotStarted: Bool { startAt == nil }

    public var duration: TimeInterval? {
        guard let s = startAt, let e = endAt else { return nil }
        return e.timeIntervalSince(s)
    }

    /// 实际占用：手动填了分钟数就用它（即使没有起止时间），否则用起止时间差
    public var effectiveDuration: TimeInterval? {
        if let m = actualMinutes { return TimeInterval(m) * 60 }
        return duration
    }
}

/// 读时把 `startAt`/`endAt` 的日期部分丢弃，只取时分秒锚定到给定 `day`。
/// entry 归属由 `DayAssignment.day` 决定，存储里 Date 的日期部分可能因编辑漂移。
extension TimeEntry {
    public func startAt(inDay day: Day, calendar: Calendar = .current) -> Date? {
        Self.combine(day: day, time: startAt, calendar: calendar)
    }
    public func endAt(inDay day: Day, calendar: Calendar = .current) -> Date? {
        Self.combine(day: day, time: endAt, calendar: calendar)
    }
    public func duration(inDay day: Day, calendar: Calendar = .current) -> TimeInterval? {
        guard let s = startAt(inDay: day, calendar: calendar),
              let e = endAt(inDay: day, calendar: calendar) else { return nil }
        return e.timeIntervalSince(s)
    }
    /// 实际占用（按天锚定版本）：手动分钟数优先，否则起止时间差
    public func effectiveDuration(inDay day: Day, calendar: Calendar = .current) -> TimeInterval? {
        if let m = actualMinutes { return TimeInterval(m) * 60 }
        return duration(inDay: day, calendar: calendar)
    }
    private static func combine(day: Day, time: Date?, calendar: Calendar) -> Date? {
        guard let time else { return nil }
        let dayStart = calendar.startOfDay(for: day.date(calendar: calendar))
        let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: time)
        var comps = DateComponents()
        comps.hour = c.hour
        comps.minute = c.minute
        comps.second = c.second
        comps.nanosecond = c.nanosecond
        return calendar.date(byAdding: comps, to: dayStart) ?? dayStart
    }
}
