import Foundation

/// 分类条目：稳定 UUID + 名字；任务 categoryId 引用这里的 id。
public struct CategoryDef: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// 工作类型条目：稳定 UUID + 名字；TimeEntry.workTypeId 引用这里的 id。
public struct WorkTypeDef: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct AppSettings: Codable, Sendable, Hashable {
    public var categories: [CategoryDef]
    public var workTypes: [WorkTypeDef]

    public init(categories: [CategoryDef], workTypes: [WorkTypeDef]) {
        self.categories = categories
        self.workTypes = workTypes
    }

    public static let defaults = AppSettings(
        categories: [
            CategoryDef(name: "日常跟进"),
            CategoryDef(name: "会议"),
            CategoryDef(name: "我的任务"),
            CategoryDef(name: "Platform/Chaos test"),
            CategoryDef(name: "其他"),
        ],
        workTypes: [
            WorkTypeDef(name: "未指定"),
            WorkTypeDef(name: "编码"),
            WorkTypeDef(name: "阅读"),
            WorkTypeDef(name: "沟通"),
            WorkTypeDef(name: "会议"),
            WorkTypeDef(name: "文档"),
        ]
    )
}

extension TimeEntry.Marker {
    public var displayName: String {
        switch self {
        case .done: return "完成"
        case .restart: return "开始新阶段"
        }
    }
}

public enum SettingsLookup {
    public static let unknownName = "(未知)"
    public static let unsetName = "(未设置)"

    public static func categoryName(_ id: UUID?, in categories: [CategoryDef]) -> String {
        guard let id else { return unsetName }
        return categories.first(where: { $0.id == id })?.name ?? unknownName
    }
    public static func workTypeName(_ id: UUID?, in workTypes: [WorkTypeDef]) -> String {
        guard let id else { return unsetName }
        return workTypes.first(where: { $0.id == id })?.name ?? unknownName
    }
}
