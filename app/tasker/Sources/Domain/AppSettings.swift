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
            CategoryDef(name: "Daily follow-up"),
            CategoryDef(name: "Meeting"),
            CategoryDef(name: "My task"),
            CategoryDef(name: "Platform/Chaos test"),
            CategoryDef(name: "Other"),
        ],
        workTypes: [
            WorkTypeDef(name: "Unspecified"),
            WorkTypeDef(name: "Coding"),
            WorkTypeDef(name: "Reading"),
            WorkTypeDef(name: "Communication"),
            WorkTypeDef(name: "Meeting"),
            WorkTypeDef(name: "Docs"),
        ]
    )
}

extension TimeEntry.Marker {
    public var displayName: String {
        switch self {
        case .done: return "Done"
        case .restart: return "New phase"
        }
    }
}

public enum SettingsLookup {
    public static let unknownName = "(Unknown)"
    public static let unsetName = "(Unset)"

    public static func categoryName(_ id: UUID?, in categories: [CategoryDef]) -> String {
        guard let id else { return unsetName }
        return categories.first(where: { $0.id == id })?.name ?? unknownName
    }
    public static func workTypeName(_ id: UUID?, in workTypes: [WorkTypeDef]) -> String {
        guard let id else { return unsetName }
        return workTypes.first(where: { $0.id == id })?.name ?? unknownName
    }
}
