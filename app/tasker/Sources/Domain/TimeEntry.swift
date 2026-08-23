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

    public init(id: UUID = UUID(),
                title: String = "",
                workTypeId: UUID? = nil,
                startAt: Date? = nil,
                endAt: Date? = nil,
                marker: Marker? = nil) {
        self.id = id
        self.title = title
        self.workTypeId = workTypeId
        self.startAt = startAt
        self.endAt = endAt
        self.marker = marker
    }

    public var isOpen: Bool { startAt != nil && endAt == nil }
    public var isNotStarted: Bool { startAt == nil }

    public var duration: TimeInterval? {
        guard let s = startAt, let e = endAt else { return nil }
        return e.timeIntervalSince(s)
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
