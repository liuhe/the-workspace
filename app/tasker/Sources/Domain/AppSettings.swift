import Foundation

/// 分类条目：稳定 UUID + 名字 + 可选颜色；任务 categoryId 引用这里的 id。
/// `colorHex` 形如 "#2a78d6"；nil = 自动（按分类在设置里的顺序取调色板槽位色）。
public struct CategoryDef: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var colorHex: String?

    public init(id: UUID = UUID(), name: String, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

/// 分类调色板：8 个固定槽位（dataviz 默认分类色，浅 / 深色各一套），按顺序分配、不循环。
/// 用户在设置里给分类指定颜色时，两种外观都用同一个值。
public enum CategoryPalette {
    public static let lightHex: [String] = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
    public static let darkHex: [String] = ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#008300", "#9085e9", "#e66767"]
    public static let fallbackHex = "#8e8e93"

    /// 解析分类最终颜色：显式指定 > 槽位自动色 > 超出槽位数 / 未知分类 → 灰
    public static func resolvedHex(for def: CategoryDef?, slot: Int?, dark: Bool) -> String {
        if let hex = def?.colorHex, !hex.isEmpty { return hex }
        return autoHex(slot: slot, dark: dark)
    }

    public static func autoHex(slot: Int?, dark: Bool) -> String {
        let table = dark ? darkHex : lightHex
        guard let slot, slot >= 0, slot < table.count else { return fallbackHex }
        return table[slot]
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
