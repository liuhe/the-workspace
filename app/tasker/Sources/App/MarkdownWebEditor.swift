import AppKit
import SwiftUI
import MarkdownEditor

/// WKWebView + Toast UI Editor 的 WYSIWYG markdown 编辑器。
/// 存储层还是 markdown 文本；WKWebView 侧持有富文本编辑体验。
/// 把 CSS/JS 直接内联进 HTML 再 loadHTMLString，避免 file:// 的 CORS 限制。
struct TaskMarkdownEditor: View {
    @Binding var markdown: String
    let fileURL: URL?
    let workspaceRootURL: URL?

    @StateObject private var documentStore = DocumentStore()
    @StateObject private var bridge = EditorBridge()
    @State private var syncedMarkdown = ""

    var body: some View {
        MarkdownEditor.MarkdownWebEditor(store: documentStore, bridge: bridge)
            .onAppear {
                configureBridge()
                syncFileURL()
                syncDocumentText(markdown)
            }
            .onChange(of: markdown) { _, newValue in
                syncDocumentText(newValue)
            }
            .onChange(of: fileURL) { _, _ in
                syncFileURL()
            }
            .onChange(of: workspaceRootURL) { _, newValue in
                bridge.workspaceRootURL = newValue
            }
            .onReceive(documentStore.$text) { newValue in
                guard newValue != syncedMarkdown else { return }
                syncedMarkdown = newValue
                markdown = newValue
            }
    }

    private func configureBridge() {
        bridge.workspaceRootURL = workspaceRootURL
        bridge.onOpenLink = { url in
            NSWorkspace.shared.open(url)
        }
        bridge.onDropURL = { url in
            NSWorkspace.shared.open(url)
        }
        bridge.onPasteImage = { data, mime in
            savePastedImage(data: data, mime: mime)
        }
        bridge.onFileLinkPickerRequested = { selectedText in
            pickFileLink(selectedText: selectedText)
        }
    }

    private func syncFileURL() {
        if let fileURL {
            documentStore.retarget(to: fileURL)
        } else {
            documentStore.detachFromDisk()
        }
        bridge.workspaceRootURL = workspaceRootURL
    }

    private func syncDocumentText(_ newValue: String) {
        syncedMarkdown = newValue
        guard documentStore.text != newValue else { return }
        documentStore.text = newValue
    }

    private func savePastedImage(data: Data, mime: String) -> URL? {
        guard let sourceURL = documentStore.fileURL else {
            NSSound.beep()
            return nil
        }

        let assetsDir = sourceURL
            .deletingPathExtension()
            .appendingPathExtension("assets")

        do {
            try FileManager.default.createDirectory(
                at: assetsDir,
                withIntermediateDirectories: true
            )

            let ext = MarkdownEditor.MarkdownWebEditor.extensionForMIME(mime)
            let stamp = Self.imagePasteStamp()
            var target = assetsDir.appendingPathComponent("paste-\(stamp).\(ext)")
            var i = 2

            while FileManager.default.fileExists(atPath: target.path) {
                target = assetsDir.appendingPathComponent("paste-\(stamp)-\(i).\(ext)")
                i += 1
            }

            try data.write(to: target, options: .atomic)
            return target
        } catch {
            NSSound.beep()
            return nil
        }
    }

    private func pickFileLink(selectedText: String?) {
        guard let sourceURL = documentStore.fileURL else {
            NSSound.beep()
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let pickedURL = panel.url else { return }

        let href = RelativePath.relative(from: sourceURL, to: pickedURL)
        let text = selectedText?.isEmpty == false
            ? selectedText!
            : pickedURL.deletingPathExtension().lastPathComponent
        bridge.insertLink(href: href, text: text)
    }

    private static func imagePasteStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
