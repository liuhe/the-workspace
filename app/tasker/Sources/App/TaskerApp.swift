import SwiftUI
import AppKit
import TaskerPersistence
import TaskerIcon

extension Notification.Name {
    /// 全局 Cmd+N：由 App CommandGroup 发出，SidebarView 监听
    static let newTaskRequested = Notification.Name("tasker.newTaskRequested")
}

@main
struct TaskerApp: App {
    @StateObject private var store: WorkspaceStore
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let store: WorkspaceStore
        do {
            store = try WorkspaceStore(root: WorkspaceStore.loadDataRoot())
        } catch {
            fatalError("Failed to initialize repository: \(error)")
        }
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup("tasker") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            // 全局 Cmd+N：SidebarView 里的按钮 shortcut 依赖响应链，WKWebView
            // 抢焦点时会失效；这里挂 App 级 CommandGroup 保稳
            CommandGroup(after: .newItem) {
                Button("New Task") {
                    NotificationCenter.default.post(name: .newTaskRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        // 独立的可拖拽调整大小的统计窗口
        Window("Statistics", id: "stats") {
            StatsView()
                .environmentObject(store)
                .frame(minWidth: 800, idealWidth: 1000, minHeight: 500, idealHeight: 700)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIcon.generate()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
