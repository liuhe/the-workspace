import Foundation
import AppKit
import TaskerIcon

// 预热 AppKit，让 NSImage.lockFocus 在无 GUI runloop 的 CLI 里也能工作
_ = NSApplication.shared

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: iconGen <output-iconset-dir>\n".data(using: .utf8)!)
    exit(2)
}

let outDir = args[1]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

/// iconutil 认识的固定文件名 + 尺寸。
let specs: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let base = URL(fileURLWithPath: outDir)
for (name, size) in specs {
    guard let png = AppIcon.pngData(size: size) else {
        FileHandle.standardError.write("failed to render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try png.write(to: base.appendingPathComponent(name))
    print("wrote \(name)  \(Int(size))×\(Int(size))")
}
