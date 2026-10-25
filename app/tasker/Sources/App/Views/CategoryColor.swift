import SwiftUI
import AppKit
import TaskerDomain

/// 分类颜色的 SwiftUI 侧工具：hex ↔ Color，以及按外观解析分类色。
enum CategoryColor {
    static func color(hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return Color(.sRGB,
                     red: Double((v >> 16) & 0xff) / 255,
                     green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255,
                     opacity: 1)
    }

    static func hex(from color: Color) -> String? {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    /// 分类最终显示色（显式指定 > 槽位自动色 > 灰）
    static func resolve(def: CategoryDef?, slot: Int?, scheme: ColorScheme) -> Color {
        let hex = CategoryPalette.resolvedHex(for: def, slot: slot, dark: scheme == .dark)
        return color(hex: hex) ?? Color.gray
    }

    static func auto(slot: Int?, scheme: ColorScheme) -> Color {
        color(hex: CategoryPalette.autoHex(slot: slot, dark: scheme == .dark)) ?? Color.gray
    }
}
