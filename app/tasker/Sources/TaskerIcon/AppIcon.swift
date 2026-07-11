import AppKit

/// 运行时生成 dock 图标 / 打包时导出 .icns 都用这份绘图。
/// 紫蓝渐变圆角方 + 白色对勾。
public enum AppIcon {
    public static func generate(size: CGFloat = 512) -> NSImage {
        let s = NSSize(width: size, height: size)
        let image = NSImage(size: s)
        image.lockFocus()

        let cornerRadius = size * 0.22
        let bgRect = NSRect(origin: .zero, size: s)
        let bgPath = NSBezierPath(roundedRect: bgRect,
                                  xRadius: cornerRadius,
                                  yRadius: cornerRadius)
        let gradient = NSGradient(colors: [
            NSColor(red: 0.36, green: 0.46, blue: 0.98, alpha: 1),
            NSColor(red: 0.55, green: 0.32, blue: 0.85, alpha: 1),
        ])!
        gradient.draw(in: bgPath, angle: -70)

        let check = NSBezierPath()
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.lineWidth = size * 0.095
        check.move(to: NSPoint(x: size * 0.26, y: size * 0.51))
        check.line(to: NSPoint(x: size * 0.44, y: size * 0.33))
        check.line(to: NSPoint(x: size * 0.78, y: size * 0.68))
        NSColor.white.setStroke()
        check.stroke()

        image.unlockFocus()
        return image
    }

    /// 导出成 PNG 数据（iconGen 生成 iconset 用）。
    public static func pngData(size: CGFloat) -> Data? {
        let image = generate(size: size)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}
