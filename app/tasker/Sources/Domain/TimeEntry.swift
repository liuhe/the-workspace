import Foundation

public struct TimeEntry: Codable, Hashable, Identifiable, Sendable {
    public enum Marker: String, Codable, Sendable {
        case done
        case restart
    }

    public let id: UUID
    public let taskId: UUID
    public var title: String

    /// 工作类型引用（AppSettings.workTypes[].id）；nil = 未设置
    public var workTypeId: UUID?

    public var startAt: Date?
    public var endAt: Date?
    public var marker: Marker?

    public init(id: UUID = UUID(),
                taskId: UUID,
                title: String = "",
                workTypeId: UUID? = nil,
                startAt: Date? = nil,
                endAt: Date? = nil,
                marker: Marker? = nil) {
        self.id = id
        self.taskId = taskId
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
