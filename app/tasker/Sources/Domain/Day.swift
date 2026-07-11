import Foundation

public struct Day: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    public static func today(calendar: Calendar = .current) -> Day {
        Day(date: Date(), calendar: calendar)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// "周X"（中文短星期）。默认用 zh-CN locale。
    public func weekdayLabel(locale: Locale = .current,
                             calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.dateFormat = "EEE"
        return f.string(from: date(calendar: calendar))
    }

    /// "yyyy-MM-dd EEE"
    public var descriptionWithWeekday: String {
        "\(description) \(weekdayLabel())"
    }

    public func date(calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return calendar.date(from: c) ?? Date()
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "Day must be yyyy-MM-dd")
        }
        self.year = y; self.month = m; self.day = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
