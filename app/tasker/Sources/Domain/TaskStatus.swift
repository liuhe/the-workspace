import Foundation

public enum TaskStatus: String, Sendable, Codable {
    case notStarted
    case inProgress
    case done

    public var displayName: String {
        switch self {
        case .notStarted: return "Not started"
        case .inProgress: return "In progress"
        case .done: return "Done"
        }
    }
}

public enum StatusDeriver {
    /// 新推导规则（marker 是权威）：
    /// 1. 遍历所有时间记录，找最后一个"有标"（marker != nil）的
    ///    - marker == .done → done
    ///    - marker == .restart → inProgress
    /// 2. 找不到"有标"的：有任何记录 → inProgress；一条都没 → notStarted
    ///
    /// "最后一个"顺序：有 startAt 的按 startAt 升序，无 startAt 的排最后
    ///
    /// startAt 在未来的记录（预排的计划）不计入状态推导 —— 计划态不该让任务显得"进行中"
    public static func derive(from entries: [TimeEntry], now: Date = Date()) -> TaskStatus {
        let effective = entries.filter { e in
            guard let s = e.startAt else { return true }
            return s <= now
        }
        let sorted = effective.sorted(by: chrono)
        if let lastMarked = sorted.last(where: { $0.marker != nil }),
           let m = lastMarked.marker {
            return m == .done ? .done : .inProgress
        }
        return effective.isEmpty ? .notStarted : .inProgress
    }

    private static func chrono(_ a: TimeEntry, _ b: TimeEntry) -> Bool {
        switch (a.startAt, b.startAt) {
        case let (l?, r?): return l < r
        case (nil, _?):    return false
        case (_?, nil):    return true
        case (nil, nil):   return false
        }
    }
}
