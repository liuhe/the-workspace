import SwiftUI
import AppKit
import TaskerPersistence

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
        // 新任务快捷键在 SidebarView 的按钮上；这里不再重复注册。
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
