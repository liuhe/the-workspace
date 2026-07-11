import Foundation

public enum Priority: String, Codable, CaseIterable, Sendable, Comparable {
    case todayMustReach
    case important
    case normal

    public var displayName: String {
        switch self {
        case .todayMustReach: return "Must reach today"
        case .important: return "Important"
        case .normal: return "Normal"
        }
    }

    /// 用于标题前缀的 emoji；normal 无 emoji。
    public var emoji: String {
        switch self {
        case .todayMustReach: return "❗️"
        case .important: return "🔶"
        case .normal: return ""
        }
    }

    public var titlePrefix: String {
        emoji.isEmpty ? "" : "\(emoji) "
    }

    private var rank: Int {
        switch self {
        case .todayMustReach: return 0
        case .important: return 1
        case .normal: return 2
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.rank < rhs.rank
    }
}
